{
  autoPatchelfHook,
  buildNpmPackage,
  fd,
  fetchFromGitHub,
  lib,
  makeWrapper,
  nodejs_24,
  npmHooks,
  python3,
  ripgrep,
  runCommand,
  stdenv,
  uv,
}:

let
  source = (import ./source-catalog.nix "ai").prime-agent;
  upstream = fetchFromGitHub source.source.args;
  normalizedLock = ./prime-agent/package-lock.json;
  normalizedLockSha256 = "b3b9a8aedb933188c91e2bb9c3ef2616340145ad773f5c5be0051a701059dffb";
  upstreamLockSha256 = "b2ac9fb79434f082d4a4e84fb4671cdd7e1357c7cd0687e987fddcaff1dd9d6e";
  linuxNative =
    if stdenv.hostPlatform.isx86_64 then
      {
        koffi = "linux_x64";
        zeromq = "x64";
      }
    else if stdenv.hostPlatform.isAarch64 then
      {
        koffi = "linux_arm64";
        zeromq = "arm64";
      }
    else
      throw "prime-agent supports only x86_64-linux and aarch64-linux on Linux";
  src =
    assert builtins.hashFile "sha256" normalizedLock == normalizedLockSha256;
    runCommand "prime-agent-${source.version}-source" { nativeBuildInputs = [ python3 ]; } ''
      cp -R -- ${upstream}/. "$out"/
      chmod -R u+w "$out"

      ${python3}/bin/python3 - ${upstream}/package-lock.json ${normalizedLock} <<'PY'
      import hashlib
      import json
      import re
      import sys

      upstream_path, normalized_path = sys.argv[1:]
      upstream = json.load(open(upstream_path))
      normalized = json.load(open(normalized_path))
      assert hashlib.sha256(open(upstream_path, "rb").read()).hexdigest() == "${upstreamLockSha256}"
      assert set(upstream["packages"]) == set(normalized["packages"])
      for path, expected in upstream["packages"].items():
          actual = normalized["packages"][path]
          stripped = {key: value for key, value in actual.items() if key not in {"integrity", "resolved"}}
          baseline = {key: value for key, value in expected.items() if key not in {"integrity", "resolved"}}
          assert stripped == baseline, path
          if "node_modules/" in path and not actual.get("link") and re.fullmatch(r"[0-9][0-9A-Za-z.+-]*", str(actual.get("version", ""))):
              assert str(actual.get("resolved", "")).startswith("https://registry.npmjs.org/"), path
              assert re.fullmatch(r"sha(?:256|384|512)-[A-Za-z0-9+/=]+", str(actual.get("integrity", ""))), path
      PY

      cp -- ${normalizedLock} "$out/package-lock.json"
    '';
  primeNpmConfigHook = runCommand "prime-agent-npm-config-hook" { } ''
    mkdir -p "$out/nix-support"
    cp ${npmHooks.npmConfigHook}/nix-support/setup-hook "$out/nix-support/setup-hook"
    chmod u+w "$out/nix-support/setup-hook"
    ${python3}/bin/python3 - "$out/nix-support/setup-hook" <<'PY'
    import pathlib
    import sys

    path = pathlib.Path(sys.argv[1])
    lines = path.read_text().splitlines()
    rebuild = [index for index, line in enumerate(lines) if line.startswith("    npm rebuild ")]
    assert len(rebuild) == 1
    lines[rebuild[0]] = "    : # Lifecycle scripts are disabled; the pinned lock already contains platform artifacts."
    path.write_text("\n".join(lines) + "\n")
    PY
  '';

in
buildNpmPackage {
  pname = "prime-agent";
  inherit (source) version;
  inherit src;

  patches = [
    ../overlays/ai/patches/prime-agent-managed-settings.patch
    ../overlays/ai/patches/prime-agent-pi-ai-compat.patch
  ];
  nodejs = nodejs_24;
  npmDepsHash = source.hashes.npmDepsHash;
  npmDepsFetcherVersion = 2;
  npmConfigHook = primeNpmConfigHook;
  npmInstallFlags = [ "--ignore-scripts" ];
  npmFlags = [ "--legacy-peer-deps" ];
  nativeBuildInputs = [ makeWrapper ] ++ lib.optional stdenv.hostPlatform.isLinux autoPatchelfHook;
  buildInputs = lib.optional stdenv.hostPlatform.isLinux stdenv.cc.cc.lib;

  buildPhase = ''
    runHook preBuild

    test "$(sha256sum packages/ai/src/models.generated.ts | cut -d ' ' -f1)" = \
      5a9e7f88432d7df663961fadffb9bfa3d04612cdc619a7ff0e43bcdeae693349
    (cd packages/tui && ../../node_modules/.bin/tsgo -p tsconfig.build.json)
    (cd packages/ai && ../../node_modules/.bin/tsgo -p tsconfig.build.json)
    (cd packages/agent && ../../node_modules/.bin/tsgo -p tsconfig.build.json)
    (cd packages/coding-agent && npm run build)

    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    export npm_config_prefix="$TMPDIR/npm-prefix"
    export npm_config_registry="http://127.0.0.1:9"
    export npm_config_fetch_retries=0
    export npm_config_fetch_timeout=1000
    mkdir -p "$npm_config_prefix"

    node_modules/.bin/biome check \
      packages/coding-agent/src/package-manager-cli.ts \
      packages/coding-agent/src/core/package-manager.ts \
      packages/coding-agent/src/core/settings-manager.ts \
      packages/coding-agent/src/modes/interactive/components/config-selector.ts \
      packages/coding-agent/test/managed-settings.test.ts
    node_modules/.bin/vitest --run \
      packages/coding-agent/test/managed-settings.test.ts \
      packages/coding-agent/test/package-manager.test.ts \
      packages/coding-agent/test/settings-manager.test.ts \
      packages/coding-agent/test/builtin-skills.test.ts

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    root=$out/lib/prime-agent
    mkdir -p "$root" "$out/bin"
    for entry in package.json postinstall.cjs README.md CHANGELOG.md; do
      if [ -e "packages/coding-agent/$entry" ]; then
        cp -R -- "packages/coding-agent/$entry" "$root/"
      fi
    done
    for entry in dist docs examples skills; do
      if [ -e "packages/coding-agent/$entry" ]; then
        cp -R -- "packages/coding-agent/$entry" "$root/"
      fi
    done
    ${python3}/bin/python3 - "$root/package.json" <<'PY'
    import json
    import pathlib
    import sys

    path = pathlib.Path(sys.argv[1])
    package = json.loads(path.read_text())
    package["name"] = "prime-agent"
    package["bin"] = {"prime-agent": "dist/bundle/cli.js"}
    path.write_text(json.dumps(package, indent=2) + "\n")
    PY

    cp -R -- node_modules "$root/"
    rm -f \
      "$root/node_modules/pi-extension-custom-provider-anthropic" \
      "$root/node_modules/pi-extension-custom-provider-gitlab-duo" \
      "$root/node_modules/pi-extension-sandbox" \
      "$root/node_modules/pi-extension-with-deps"

    scope="$root/node_modules/@earendil-works"
    rm -f "$scope/pi-agent-core" "$scope/pi-ai" "$scope/pi-coding-agent" "$scope/pi-tui"
    copy_internal_package() {
      source_dir=$1
      target_dir=$2
      mkdir -p "$target_dir"
      cp -- "$source_dir/package.json" "$target_dir/"
      cp -R -- "$source_dir/dist" "$target_dir/"
      for entry in README.md CHANGELOG.md; do
        if [ -e "$source_dir/$entry" ]; then
          cp -- "$source_dir/$entry" "$target_dir/"
        fi
      done
    }
    copy_internal_package packages/agent "$scope/pi-agent-core"
    copy_internal_package packages/ai "$scope/pi-ai"
    copy_internal_package packages/tui "$scope/pi-tui"
    ln -s ../.. "$scope/pi-coding-agent"

    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      find "$root/node_modules/koffi/build/koffi" -mindepth 1 -maxdepth 1 \
        ! -name ${linuxNative.koffi} -exec rm -rf -- {} +
      rm -rf \
        "$root/node_modules/zeromq/build/darwin" \
        "$root/node_modules/zeromq/build/win32"
      find "$root/node_modules/zeromq/build/linux" -mindepth 1 -maxdepth 1 \
        ! -name ${linuxNative.zeromq} -exec rm -rf -- {} +
      rm -rf \
        "$root/node_modules/zeromq/build/linux/${linuxNative.zeromq}/node/musl-127-Release"
    ''}

    makeWrapper ${nodejs_24}/bin/node "$out/bin/prime-agent" \
      --add-flags "$root/dist/bundle/cli.js" \
      --prefix PATH : ${
        lib.makeBinPath [
          uv
          fd
          ripgrep
        ]
      } \
      --set PI_PACKAGE_DIR "$root" \
      --set PI_SKIP_VERSION_CHECK 1 \
      --set PRIME_AGENT_INSTALL_UV 0 \
      --run 'export PRIME_AGENT_CODING_AGENT_DIR="''${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}"' \
      --run 'export PI_CODING_AGENT_DIR="$PRIME_AGENT_CODING_AGENT_DIR"' \
      --run 'if [ -z "''${PRIME_AGENT_MANAGED_SETTINGS+x}" ] && { [ -e "$PRIME_AGENT_CODING_AGENT_DIR/managed-settings.json" ] || [ -L "$PRIME_AGENT_CODING_AGENT_DIR/managed-settings.json" ]; }; then export PRIME_AGENT_MANAGED_SETTINGS="$PRIME_AGENT_CODING_AGENT_DIR/managed-settings.json"; fi'

    runHook postInstall
  '';

  meta = {
    description = "Self-improving RLM agent for coding and long-running tasks";
    homepage = source.source.url;
    license = lib.licenses.mit;
    mainProgram = "prime-agent";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
