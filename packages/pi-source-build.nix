{
  buildNpmPackage,
  fetchFromGitHub,
  fetchzip,
  nodejs_24,
}:

let
  sources = import ./source-catalog.nix "ai";
  source = sources.pi-coding-agent-source-build;
  buildNpmPackageWithNode24 = buildNpmPackage.override { nodejs = nodejs_24; };
  piAiRelease =
    assert source.artifacts.piAiRelease.fetcher == "fetchzip";
    fetchzip source.artifacts.piAiRelease.args;
in
buildNpmPackageWithNode24 {
  pname = "pi-coding-agent-source-build";
  inherit (source) version;

  src =
    assert source.source.fetcher == "fetchFromGitHub";
    fetchFromGitHub source.source.args;

  # Temporary downstream patches against the exact v0.83.0 catalog pin.
  # Remove them once the bounded-history and replacement fixes are upstreamed.
  patches = [
    ../overlays/ai/patches/pi-bounded-session-history.patch
    ../overlays/ai/patches/pi-session-replacement.patch
  ];
  patchFlags = [
    "-p1"
    "--fuzz=0"
  ];

  postPatch = ''
    mkdir -p packages/ai/src/providers/data
    cp -R ${piAiRelease}/dist/providers/data/. packages/ai/src/providers/data/
  '';

  npmDepsHash = source.hashes.npmDepsHash;
  npmInstallFlags = [ "--ignore-scripts" ];
  npmRebuildFlags = [ "--ignore-scripts" ];
  npmBuildScript = "build:offline";

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    npm exec -- vitest --run \
      packages/coding-agent/test/footer-width.test.ts \
      packages/coding-agent/test/agent-session-runtime-events.test.ts
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/coding-agent" "$out/agent"
    cp -R packages/coding-agent/dist "$out/coding-agent/dist"
    cp -R packages/agent/dist "$out/agent/dist"
    runHook postInstall
  '';
}
