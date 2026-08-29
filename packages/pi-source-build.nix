{
  buildNpmPackage,
  fetchFromGitHub,
  fetchzip,
  git,
  lib,
  nodejs_24,
  stdenv,
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
    assert source.version == "0.84.3";
    assert source.source.fetcher == "fetchFromGitHub";
    assert source.source.args.rev == "4e58f324fae8ebfa98a3d45181fb248072a2afac";
    fetchFromGitHub source.source.args;

  # Temporary downstream patches against the exact v0.84.3 catalog pin.
  # Remove each once its corresponding behavior is upstreamed.
  patches = [
    ../overlays/ai/patches/pi-bounded-session-history.patch
    ../overlays/ai/patches/pi-provider-transport-timeouts.patch
    ../overlays/ai/patches/pi-session-replacement.patch
    ../overlays/ai/patches/pi-model-default-thinking.patch
    ../overlays/ai/patches/pi-agent-cat-workflow-api.patch
  ];
  patchFlags = [
    "-p1"
    "--fuzz=0"
  ];

  # Full-index preimages bind this patch to the pristine catalog revision.
  prePatch = ''
    awk '
      /^diff --git / { path = $3; sub(/^i\//, "", path) }
      /^index / { split($2, hashes, "\\.\\."); print hashes[1], path }
    ' ${../overlays/ai/patches/pi-agent-cat-workflow-api.patch} |
      while read -r expected path; do
        actual="$(${git}/bin/git hash-object "$path")"
        if [[ "$actual" != "$expected" ]]; then
          echo "agent-cat Pi patch preimage mismatch: $path" >&2
          exit 1
        fi
      done
  '';
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
    ${lib.optionalString stdenv.hostPlatform.isDarwin "npm run check"}
    ${lib.optionalString (!stdenv.hostPlatform.isDarwin) ''
      npm run check:pinned-deps
      npm run check:ts-imports
      npm run check:shrinkwrap
      npm run check:install-lock:coding-agent
      npm exec -- tsgo --noEmit
      npm run check:browser-smoke
    ''}
    # Bounded history changes the SessionManager contract consumed throughout
    # the SDK, RPC, compaction, export, and interactive navigation paths. Run
    # every test changed by the downstream patches so their regressions
    # remain part of the package gate without importing unrelated upstream
    # tests whose external-tool assumptions are incompatible with Nix builds.
    npm exec -- vitest --run --testTimeout 30000 \
      packages/protocol/test/protocol.test.ts \
      packages/client/test/sessions.test.ts \
      packages/server/test/sessions.test.ts \
      packages/coding-agent/test/client/remote-session.test.ts \
      packages/coding-agent/test/client/remote-session-lifecycle.test.ts \
      packages/coding-agent/test/client/remote-session-ownership.test.ts \
      packages/coding-agent/test/suite/agent-session-prompt.test.ts \
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
    mkdir -p "$out/coding-agent" "$out/agent" "$out/ai" "$out/workspace/packages"
    cp -R packages/coding-agent/dist "$out/coding-agent/dist"
    cp -R packages/agent/dist "$out/agent/dist"
    cp -R packages/ai/dist "$out/ai/dist"
    for name in protocol client server coding-agent agent ai tui telemetry; do
      mkdir -p "$out/workspace/packages/$name"
      cp "packages/$name/package.json" "$out/workspace/packages/$name/"
      cp -R "packages/$name/dist" "$out/workspace/packages/$name/dist"
    done
    scope="$out/workspace/node_modules/@earendil-works"
    mkdir -p "$scope"
    ln -s ../../packages/protocol "$scope/pi-protocol"
    ln -s ../../packages/client "$scope/pi-client"
    ln -s ../../packages/server "$scope/pi-server"
    ln -s ../../packages/coding-agent "$scope/pi-coding-agent"
    ln -s ../../packages/agent "$scope/pi-agent-core"
    ln -s ../../packages/ai "$scope/pi-ai"
    ln -s ../../packages/tui "$scope/pi-tui"
    ln -s ../../packages/telemetry "$scope/pi-telemetry"
    runHook postInstall
  '';
}
