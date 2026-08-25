{
  hermesAgentPackage,
  lib,
  python3,
  stdenvNoCC,
}:

let
  testPython = python3.withPackages (pythonPackages: [
    pythonPackages.httpx
    pythonPackages.pyyaml
  ]);
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "hermes-qdrant-memory";
  version = "0.1.0";
  src = ./plugin;

  strictDeps = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R -- ./. "$out"/
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ testPython ];
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    PYTHONDONTWRITEBYTECODE=1 \
      ${testPython}/bin/python3 \
      ${../../test/ai/hermes-qdrant-memory-contract.py} \
        "$out"
    PYTHONDONTWRITEBYTECODE=1 \
      ${hermesAgentPackage.hermesVenv}/bin/python3 \
      ${../../test/ai/hermes-qdrant-memory-runtime-contract.py} \
        "$out"
    runHook postInstallCheck
  '';

  passthru = {
    hermesPluginDirectoryName = "nix-managed-${finalAttrs.pname}";
    upstreamRevision = "c350be1e843de820966f5a1db52b29b22b7775b9";
  };

  meta = {
    description = "Hybrid dense and sparse Qdrant memory provider for Hermes Agent";
    platforms = lib.platforms.unix;
  };
})
