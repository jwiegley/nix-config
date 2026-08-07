{
  autoPatchelfHook,
  fetchurl,
  lib,
  makeWrapper,
  openssh,
  rsync,
  stdenv,
  zlib,
}:

let
  source = (import ./source-catalog.nix "ai").cass;
  licenseFile = ./cass/LICENSE;
  licenseSha256 = "32a82e0a5754e72e51fae44b65a936c831c07376f21c90f5fb9e76897fcc3509";
  system = stdenv.hostPlatform.system;
  archive =
    if system == "aarch64-darwin" then
      source.source
    else
      source.artifacts.${system} or (throw "cass does not provide a release asset for ${system}");
in
assert builtins.hashFile "sha256" licenseFile == licenseSha256;
assert archive.fetcher == "fetchurl";
stdenv.mkDerivation {
  pname = "cass";
  inherit (source) version;

  src = fetchurl archive.args;
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  nativeBuildInputs = [ makeWrapper ] ++ lib.optional stdenv.isLinux autoPatchelfHook;
  buildInputs = lib.optionals stdenv.isLinux [
    stdenv.cc.cc.lib
    zlib
  ];

  unpackPhase = ''
    runHook preUnpack

    mkdir source
    tar -xzf "$src" -C source
    test "$(find source -type f | wc -l)" -eq 1
    test -f source/cass

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 source/cass "$out/bin/cass"
    install -Dm644 ${licenseFile} "$out/share/licenses/cass/LICENSE"

    runHook postInstall
  '';

  postFixup = ''
    # Nix owns executable updates; leave the TUI interactive while disabling
    # upstream's installer prompt. Remote sources get their local transport tools.
    wrapProgram "$out/bin/cass" \
      --set CODING_AGENT_SEARCH_NO_UPDATE_PROMPT 1 \
      --prefix PATH : ${
        lib.makeBinPath [
          openssh
          rsync
        ]
      }
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test "$($out/bin/cass --version)" = "cass ${source.version}"
    cmp ${licenseFile} "$out/share/licenses/cass/LICENSE"
    grep -F 'CODING_AGENT_SEARCH_NO_UPDATE_PROMPT' "$out/bin/cass" >/dev/null
    grep -F '${openssh}/bin' "$out/bin/cass" >/dev/null
    grep -F '${rsync}/bin' "$out/bin/cass" >/dev/null

    runHook postInstallCheck
  '';

  meta = {
    description = "Unified search over local coding-agent session histories";
    homepage = "https://github.com/Dicklesworthstone/coding_agent_session_search";
    license = lib.licenses.unfree;
    mainProgram = "cass";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
