{
  curl,
  hermesAgentPackage,
  lib,
  python3,
  stdenvNoCC,
}:

let
  workerPython = python3.withPackages (pythonPackages: [ pythonPackages.trafilatura ]);
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "hermes-local-extract";
  version = "1.0.0";
  src = ./plugin;

  strictDeps = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm0644 __init__.py "$out/__init__.py"
    install -Dm0644 plugin.yaml "$out/plugin.yaml"
    install -Dm0644 provider.py "$out/provider.py"
    install -Dm0755 extract_worker.py "$out/libexec/hermes-local-extract-worker"
    substituteInPlace "$out/libexec/hermes-local-extract-worker" \
      --replace-fail '#!/usr/bin/env python3' '#!${workerPython}/bin/python3' \
      --replace-fail '@curl@' '${curl}/bin/curl'
    substituteInPlace "$out/provider.py" \
      --replace-fail '@worker@' "$out/libexec/hermes-local-extract-worker"
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ workerPython ];
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    PYTHONDONTWRITEBYTECODE=1 \
      ${workerPython}/bin/python3 \
      ${../../test/ai/hermes-local-extract-contract.py} \
        "$out"
    PYTHONDONTWRITEBYTECODE=1 \
      ${hermesAgentPackage.hermesVenv}/bin/python3 \
      ${../../test/ai/hermes-local-extract-runtime-contract.py} \
        "$out"
    runHook postInstallCheck
  '';

  passthru.hermesPluginDirectoryName = "nix-managed-${finalAttrs.pname}";

  meta = {
    description = "Local URL-to-Markdown extraction provider for Hermes Agent";
    platforms = lib.platforms.unix;
  };
})
