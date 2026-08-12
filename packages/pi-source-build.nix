{
  buildNpmPackage,
  fetchFromGitHub,
  fetchzip,
  git,
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
  # Remove each once its corresponding behavior is upstreamed.
  patches = [
    ../overlays/ai/patches/pi-bounded-session-history.patch
    ../overlays/ai/patches/pi-provider-transport-timeouts.patch
    ../overlays/ai/patches/pi-session-replacement.patch
    ../overlays/ai/patches/pi-model-default-thinking.patch
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
  nativeCheckInputs = [ git ];
  checkPhase = ''
    runHook preCheck
    # Bounded history changes the SessionManager contract consumed throughout
    # the SDK, RPC, compaction, export, and interactive navigation paths. Run
    # every test changed by the downstream patches so their regressions
    # remain part of the package gate without importing unrelated upstream
    # tests whose external-tool assumptions are incompatible with Nix builds.
    npm exec -- vitest --run --testTimeout 30000 \
      packages/agent/test/agent.test.ts \
      packages/coding-agent/test/agent-session-auto-compaction-queue.test.ts \
      packages/coding-agent/test/agent-session-jsonl-export.test.ts \
      packages/coding-agent/test/agent-session-runtime-events.test.ts \
      packages/coding-agent/test/agent-session-runtime-ownership.test.ts \
      packages/coding-agent/test/agent-session-stats.test.ts \
      packages/coding-agent/test/compaction.test.ts \
      packages/coding-agent/test/export-html-streaming.test.ts \
      packages/coding-agent/test/export-html-whitespace.test.ts \
      packages/coding-agent/test/export-html-write.test.ts \
      packages/coding-agent/test/extensions-runner.test.ts \
      packages/coding-agent/test/footer-width.test.ts \
      packages/coding-agent/test/git-update.test.ts \
      packages/coding-agent/test/interactive-mode-history-cap.test.ts \
      packages/coding-agent/test/model-default-thinking.test.ts \
      packages/coding-agent/test/print-mode.test.ts \
      packages/coding-agent/test/rpc-client-paging.test.ts \
      packages/coding-agent/test/rpc-prompt-response-semantics.test.ts \
      packages/coding-agent/test/session-info-search-text.test.ts \
      packages/coding-agent/test/session-manager/file-operations.test.ts \
      packages/coding-agent/test/session-manager/indexed-history-store.test.ts \
      packages/coding-agent/test/session-manager/migration.test.ts \
      packages/coding-agent/test/session-manager/paged-navigation.test.ts \
      packages/coding-agent/test/session-manager/tree-traversal.test.ts \
      packages/coding-agent/test/session-selector-path-delete.test.ts \
      packages/coding-agent/test/session-selector-rename.test.ts \
      packages/coding-agent/test/session-selector-search.test.ts \
      packages/coding-agent/test/test-harness.test.ts \
      packages/coding-agent/test/tree-selector.test.ts \
      packages/coding-agent/test/user-message-selector.test.ts
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/coding-agent" "$out/agent" "$out/ai"
    cp -R packages/coding-agent/dist "$out/coding-agent/dist"
    cp -R packages/agent/dist "$out/agent/dist"
    cp -R packages/ai/dist "$out/ai/dist"
    runHook postInstall
  '';
}
