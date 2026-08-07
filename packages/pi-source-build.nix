{
  buildNpmPackage,
  fetchFromGitHub,
  fetchzip,
}:

let
  piAiRelease = fetchzip {
    url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-0.83.0.tgz";
    hash = "sha256-OpiG7u0hptGZRnwhSlB6jbA1iNHd71zBXrDEERrpQTg=";
  };
in
buildNpmPackage {
  pname = "pi-coding-agent-source-build";
  version = "0.83.0";

  src = fetchFromGitHub {
    owner = "earendil-works";
    repo = "pi";
    rev = "845d6ff1f6643aba440341cce877ce1c43ebbc39";
    hash = "sha256-+XRJua2TSXkZMnWtxtLMskSzEHrGEFFyvYcPATi7An4=";
  };

  # Temporary downstream patch against the exact v0.83.0 source pin above.
  # Remove it once the bounded-session implementation is upstreamed and pinned.
  patches = [ ../overlays/ai/patches/pi-bounded-session-history.patch ];

  postPatch = ''
    mkdir -p packages/ai/src/providers/data
    cp -R ${piAiRelease}/dist/providers/data/. packages/ai/src/providers/data/
  '';

  npmDepsHash = "sha256-AbSfP1Ion8bN309NUBQb1QSn2cIIUjNONmZgls9vnYE=";
  npmInstallFlags = [ "--ignore-scripts" ];
  npmRebuildFlags = [ "--ignore-scripts" ];
  npmBuildScript = "build:offline";

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/coding-agent" "$out/agent"
    cp -R packages/coding-agent/dist "$out/coding-agent/dist"
    cp -R packages/agent/dist "$out/agent/dist"
    runHook postInstall
  '';
}
