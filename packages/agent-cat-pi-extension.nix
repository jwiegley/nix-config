{
  callPackage,
  fetchFromGitHub,
  haskell,
  haskellPackages,
  inputs,
  lib,
  python3,
  stdenv,
  unixtools,
}:

let
  npmCachePkgs = import inputs.npm-cache-nixpkgs {
    system = stdenv.hostPlatform.system;
  };
  sources = import ./source-catalog.nix "pi";
  source = sources.agent-cat-pi-extension;
  repo =
    assert source.source.fetcher == "fetchFromGitHub";
    fetchFromGitHub source.source.args;
  runnerBase = haskellPackages.callCabal2nix "agentic" (repo + "/haskell") { };
  runner = haskell.lib.overrideCabal runnerBase (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/Agentic/Acp.hs \
        --replace-fail 'stubScript = "../test/stub_adapter.py"' \
          'stubScript = "${repo}/test/stub_adapter.py"'
    '';
  });
  piSourceBuild = callPackage ./pi-source-build.nix { piSource = inputs.pi; };
in
npmCachePkgs.buildNpmPackage {
  pname = "agent-cat-pi-extension";
  inherit (source) version;
  src = repo + "/pi-extension";

  npmDepsHash = source.hashes.npmDepsHash;
  npmDepsFetcherVersion = 2;
  npmInstallFlags = [ "--ignore-scripts" ];
  npmRebuildFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;

  postPatch = ''
    ${python3}/bin/python3 - <<'PY'
    import json
    from pathlib import Path

    path = Path("package-lock.json")
    lock = json.loads(path.read_text())
    repairs = {
      "pi-agent-core": "sha512-VURr+xBRl3RxYcw3kT9Pn3yfi6LbRoCJgHF7h1mAblMjtLNV/MfG/RyF0uJizBAM886AEakSiw3j9c/aSngppg==",
      "pi-ai": "sha512-M0YUV8vNO3y2WwWSyY8ijKJV5W4gkSUixuvk+Z00ZBjsyMfsdXfITsHEwP1UIf09YRWXT6oGn0GlCamt+P32XQ==",
      "pi-client": "sha512-zfErYane+390W0xpBJ/FWCp6aktPpkpcIcXUeZiAziWLoxE80ZNQALRyOSa/gGS5V+1OkNnMYxRxbzN0zUvnOA==",
      "pi-protocol": "sha512-9a4g6WhLOvRqvsIOFaWxg/2gdrbY4Thclwj5ipLUPAWChfsDJ/8XdPc2sRhSOkD6EsxpEFJz3xppcfwI6EcZDg==",
      "pi-telemetry": "sha512-sgEkWoKrvSGaKn+YfLLFZmn+/A7B/w62eLwTD57nI+C9to8ITlFFVbgC2OtwvPnT3NFGHdCd53qhBEMIlptD1g==",
      "pi-tui": "sha512-fS6OEQKEEALnKa6Uw8LcgZZ+9CWck7f3MQSCETQp6leUgIFwMEDtKmOUnL9nsYm+RIPmy7OmplVxYRbV6hiaFg==",
    }
    prefix = "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/"
    missing = {
      name.removeprefix(prefix)
      for name, metadata in lock["packages"].items()
      if name.startswith(prefix) and metadata.get("resolved") and not metadata.get("integrity")
    }
    if missing != set(repairs):
      raise SystemExit(f"nested Pi lock integrity omissions changed: {sorted(missing)}")
    for name, integrity in repairs.items():
      lock["packages"][prefix + name]["integrity"] = integrity
    path.write_text(json.dumps(lock, indent=2) + "\n")
    PY
  '';

  doCheck = true;
  nativeCheckInputs = [
    python3
    unixtools.ps
  ];
  checkPhase = ''
    runHook preCheck
    export TMPDIR=/tmp
    cp -R ${repo}/haskell ${repo}/test ..
    chmod -R u+w ../haskell ../test
    patchShebangs src test ../haskell/test ../test
    substituteInPlace test/native-targets-e2e.test.ts \
      --replace-fail '"--engine", "acp", "--adapter", "/usr/bin/env",' \
        '"--engine", "acp", "--adapter", "${python3}/bin/python3",' \
      --replace-fail '"--adapter-arg", "python3", "--adapter-arg", resolve' \
        '"--adapter-arg", resolve'
    npm run check
    npm test

    scope="$PWD/node_modules/@earendil-works"
    for spec in \
      pi-protocol:protocol \
      pi-client:client \
      pi-server:server \
      pi-coding-agent:coding-agent \
      pi-agent-core:agent \
      pi-ai:ai \
      pi-tui:tui \
      pi-telemetry:telemetry
    do
      package="''${spec%%:*}"
      directory="''${spec#*:}"
      found=false
      for target in \
        "$scope/$package" \
        "$scope/pi-coding-agent/node_modules/@earendil-works/$package"
      do
        if [ -d "$target" ]; then
          rm -rf "$target/dist"
          cp "${piSourceBuild}/workspace/packages/$directory/package.json" "$target/package.json"
          cp -R "${piSourceBuild}/workspace/packages/$directory/dist" "$target/dist"
          found=true
        fi
      done
      "$found"
    done
    AGENT_CAT_E2E_RUNNER="${runner}/bin/agentic-run" npm exec -- vitest run \
      test/native-targets-e2e.test.ts \
      test/current-bridge.test.ts \
      test/pi-child-acp.test.ts \
      test/pi-remote-acp.test.ts
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    root="$out/share/pi-packages/agent-cat-pi-extension"
    mkdir -p "$root" "$out/bin"
    cp -R README.md package.json src "$root/"
    ln -s "${runner}/bin/agentic-run" "$out/bin/agentic-run"
    runHook postInstall
  '';

  passthru = {
    inherit runner;
    extensionPath = "share/pi-packages/agent-cat-pi-extension/src/index.ts";
  };

  meta = {
    description = "Pi control plane for agent-cat workflows";
    homepage = "https://github.com/jwiegley/agent-cat";
    license = lib.licenses.mit;
    mainProgram = "agentic-run";
  };
}
