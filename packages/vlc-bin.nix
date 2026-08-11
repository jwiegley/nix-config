{
  fetchurl,
  lib,
  python3,
  stdenvNoCC,
  undmg,
  writeText,
  writeTextFile,
}:

let
  source = (import ./source-catalog.nix "tools").vlc;
  verifierProgram = writeText "verify-vlc-bundle.py" ''
    import base64
    import hashlib
    import os
    import pathlib
    import plistlib
    import re
    import stat
    import subprocess
    import sys

    FAT_MACH_O_MAGICS = {
        b"\xca\xfe\xba\xbe",
        b"\xbe\xba\xfe\xca",
        b"\xca\xfe\xba\xbf",
        b"\xbf\xba\xfe\xca",
    }
    THIN_MACH_O_MAGICS = {
        b"\xfe\xed\xfa\xce",
        b"\xce\xfa\xed\xfe",
        b"\xfe\xed\xfa\xcf",
        b"\xcf\xfa\xed\xfe",
    }
    TEAM_ID = "75GAHG3SZQ"
    IDENTIFIER = "org.videolan.vlc"
    UNSAFE_ENTITLEMENTS = {
        "com.apple.security.cs.allow-dyld-environment-variables",
        "com.apple.security.get-task-allow",
        "get-task-allow",
    }

    def fail(message):
        raise SystemExit(f"VLC bundle verification failed: {message}")

    def run(arguments):
        try:
            return subprocess.run(
                arguments,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={},
            )
        except (OSError, subprocess.CalledProcessError):
            fail("Apple code-signing inspection failed")

    def file_digest(path):
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                digest.update(chunk)
        return digest.digest()

    def nix_mode(mode):
        if stat.S_ISLNK(mode):
            return 0o777
        if stat.S_ISDIR(mode):
            return 0o555
        if stat.S_ISREG(mode):
            return 0o555 if mode & stat.S_IXUSR else 0o444
        fail("bundle contains an unsupported filesystem object")

    def bundle_digest(bundle):
        digest = hashlib.sha256()
        entries = sorted(
            bundle.rglob("*"),
            key=lambda path: os.fsencode(path.relative_to(bundle).as_posix()),
        )
        for path in entries:
            relative = os.fsencode(path.relative_to(bundle).as_posix())
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                kind = b"L"
                value = os.fsencode(os.readlink(path))
            elif stat.S_ISDIR(mode):
                kind = b"D"
                value = b""
            elif stat.S_ISREG(mode):
                kind = b"F"
                value = file_digest(path)
            else:
                fail("bundle contains an unsupported filesystem object")
            digest.update(kind)
            digest.update(nix_mode(mode).to_bytes(2, "big"))
            for field in (relative, value):
                digest.update(len(field).to_bytes(8, "big"))
                digest.update(field)
        return digest.digest(), entries

    def require_contained(bundle, entries):
        root = bundle.resolve(strict=True)
        for path in entries:
            try:
                path.resolve(strict=True).relative_to(root)
            except (OSError, RuntimeError, ValueError):
                fail("bundle contains an escaping or dangling symlink")

    def load_plist(data, description):
        try:
            value = plistlib.loads(data)
        except Exception:
            fail(f"{description} is not a valid property list")
        if not isinstance(value, dict):
            fail(f"{description} is not a property-list dictionary")
        return value

    def verify_code(codesign, path, requirement):
        run(
            [
                codesign,
                "--verify",
                "--verbose=1",
                "--strict",
                "--ignore-resources",
                "-R",
                f"={requirement}",
                str(path),
            ]
        )
        entitlements = run(
            [codesign, "--display", "--entitlements", "-", "--xml", str(path)]
        ).stdout
        if not entitlements:
            return
        values = load_plist(entitlements, "entitlements")
        if any(
            key in UNSAFE_ENTITLEMENTS
            or key.endswith(".get-task-allow")
            for key in values
        ):
            fail("code contains a caller-controlled injection entitlement")

    def require_hardened_runtime(signature):
        lines = [
            line
            for line in signature.splitlines()
            if line.startswith(b"CodeDirectory ")
        ]
        if len(lines) != 1:
            fail("code-signing display has no unique CodeDirectory record")
        flag_atom = rb"[a-z0-9]+(?:-[a-z0-9]+)*"
        match = re.fullmatch(
            rb"CodeDirectory v=[0-9]+ size=[0-9]+ "
            rb"flags=(0x[0-9a-fA-F]+)\(("
            + flag_atom
            + rb"(?:,"
            + flag_atom
            + rb")*)\) "
            + rb"hashes=[0-9]+\+[0-9]+ location=[a-z0-9_-]+",
            lines[0],
        )
        if match is None:
            fail("code-signing display has a malformed CodeDirectory record")
        flags = int(match.group(1), 16)
        labels = match.group(2).split(b",")
        if len(labels) != len(set(labels)):
            fail("code-signing display has duplicate flag labels")
        if flags & 0x10000 == 0 or b"runtime" not in labels:
            fail("main executable does not use Hardened Runtime")

    def main():
        if len(sys.argv) != 5:
            fail("expected codesign, bundle hash, version, and bundle path")
        codesign, expected_hash, expected_version, bundle_argument = sys.argv[1:]
        if not os.path.isabs(codesign) or not os.access(codesign, os.X_OK):
            fail("codesign is not an executable absolute path")
        if not expected_hash.startswith("sha256-"):
            fail("bundle hash is not a SHA-256 SRI value")
        try:
            expected_digest = base64.b64decode(
                expected_hash.removeprefix("sha256-"), validate=True
            )
        except ValueError:
            fail("bundle hash is not valid base64")
        if len(expected_digest) != hashlib.sha256().digest_size:
            fail("bundle hash has the wrong length")

        bundle = pathlib.Path(bundle_argument)
        if bundle.is_symlink() or not bundle.is_dir():
            fail("bundle path is not a directory")
        actual_digest, entries = bundle_digest(bundle)
        if actual_digest != expected_digest:
            fail("complete xattr-free bundle hash does not match")
        require_contained(bundle, entries)

        info_path = bundle / "Contents" / "Info.plist"
        try:
            info = load_plist(info_path.read_bytes(), "Info.plist")
        except OSError:
            fail("Info.plist is missing")
        if info.get("CFBundleIdentifier") != IDENTIFIER:
            fail("Info.plist has the wrong bundle identifier")
        if info.get("CFBundleShortVersionString") != expected_version:
            fail("Info.plist has the wrong short version")
        if info.get("CFBundleVersion") != expected_version:
            fail("Info.plist has the wrong bundle version")
        if info.get("CFBundleExecutable") != "VLC":
            fail("Info.plist has the wrong executable")

        team_requirement = (
            f'anchor apple generic and certificate leaf[subject.OU] = "{TEAM_ID}"'
        )
        bundle_requirement = (
            f'anchor apple generic and identifier "{IDENTIFIER}" and '
            f'certificate leaf[subject.OU] = "{TEAM_ID}"'
        )
        verify_code(codesign, bundle, bundle_requirement)
        signature = run([codesign, "--display", "--verbose=6", str(bundle)]).stderr
        require_hardened_runtime(signature)

        executable = bundle / "Contents" / "MacOS" / "VLC"
        if not executable.is_file() or not os.access(executable, os.X_OK):
            fail("main executable is missing or not executable")
        mach_o_paths = []
        for path in entries:
            if not path.is_file() or path.is_symlink():
                continue
            try:
                with path.open("rb") as stream:
                    magic = stream.read(4)
            except OSError:
                fail("could not inspect a bundle file")
            if magic in FAT_MACH_O_MAGICS:
                fail("fat Mach-O code is outside the arm64 entitlement policy")
            if magic in THIN_MACH_O_MAGICS:
                mach_o_paths.append(path)
                verify_code(codesign, path, team_requirement)
        if executable not in mach_o_paths:
            fail("main executable was not covered by the Mach-O verification walk")

    if __name__ == "__main__":
        main()
  '';
  mkVerifier =
    {
      codesign ? "/usr/bin/codesign",
      expectedBundleHash ? source.hashes.bundleTreeHash,
      expectedVersion ? source.version,
    }:
    writeTextFile {
      name = "verify-vlc-bundle";
      executable = true;
      text = ''
        #!/usr/bin/env -S -i ${python3}/bin/python3 -I
        import runpy
        import sys

        program = ${builtins.toJSON "${verifierProgram}"}
        sys.argv = [
            program,
            ${builtins.toJSON codesign},
            ${builtins.toJSON expectedBundleHash},
            ${builtins.toJSON expectedVersion},
            *sys.argv[1:],
        ]
        runpy.run_path(program, run_name="__main__")
      '';
    };
  verifier = mkVerifier { };
in
stdenvNoCC.mkDerivation {
  pname = "vlc-bin";
  inherit (source) version;

  src =
    assert source.source.fetcher == "fetchurl";
    fetchurl source.source.args;

  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R VLC.app "$out/Applications/"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${verifier} "$out/Applications/VLC.app"
    runHook postInstallCheck
  '';

  passthru = {
    inherit mkVerifier verifier verifierProgram;
  };

  meta = {
    description = "VLC macOS application bundle";
    homepage = "https://www.videolan.org/vlc/";
    license = lib.licenses.gpl2Plus;
    platforms = [ "aarch64-darwin" ];
  };
}
