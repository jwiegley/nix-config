{
  buildNpmPackage,
  fetchFromGitHub,
  fetchzip,
  nodejs_24,
}:

let
  buildNpmPackageWithNode24 = buildNpmPackage.override { nodejs = nodejs_24; };
  piAiRelease = fetchzip {
    url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-0.83.0.tgz";
    hash = "sha256-OpiG7u0hptGZRnwhSlB6jbA1iNHd71zBXrDEERrpQTg=";
  };
in
buildNpmPackageWithNode24 {
  pname = "pi-coding-agent-source-build";
  version = "0.83.0";

  src = fetchFromGitHub {
    owner = "earendil-works";
    repo = "pi";
    rev = "845d6ff1f6643aba440341cce877ce1c43ebbc39";
    hash = "sha256-+XRJua2TSXkZMnWtxtLMskSzEHrGEFFyvYcPATi7An4=";
  };

  # Temporary downstream patches against the exact v0.83.0 source pin above.
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

  npmDepsHash = "sha256-AbSfP1Ion8bN309NUBQb1QSn2cIIUjNONmZgls9vnYE=";
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
