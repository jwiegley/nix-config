# LLM package exposure and compatibility overrides.
final: prev:

let
  sources = import ../../packages/source-catalog.nix "ai";
in
(import ../../packages/ai-llm.nix { inherit final prev; })
// {
  # Node 26.3.1 has two fs.cp socket tests that fail under the macOS Nix
  # sandbox. Keep the override scoped to Darwin and to the specific tests.
  nodejs-slim_26 = prev.nodejs-slim_26.overrideAttrs (
    attrs:
    prev.lib.optionalAttrs prev.stdenv.buildPlatform.isDarwin {
      checkFlags = map (
        flag:
        if prev.lib.hasPrefix "CI_SKIP_TESTS=" flag then
          "${flag},test-fs-cp-async-socket,test-fs-cp-sync-copy-socket-error"
        else
          flag
      ) (attrs.checkFlags or [ ]);
    }
  );

  nodejs_26 = prev.nodejs_26.override { nodejs-slim = final.nodejs-slim_26; };
  nodejs-slim_latest = final.nodejs-slim_26;
  nodejs_latest = final.nodejs_26;

  # llama.cpp - LLM inference with GGUF models
  # NOTE: As of b9190+, the webui was relocated from tools/server/webui
  # to tools/ui. See nixpkgs commit dea49413 (llama-cpp: 9080 -> 9190).
  llama-cpp =
    if
      prev.stdenv.hostPlatform.isDarwin
      && builtins.hasAttr "nodejs_latest" prev.llama-cpp.override.__functionArgs
    then
      (prev.llama-cpp.override { nodejs_latest = final.nodejs_22; }).overrideAttrs (attrs: rec {
        version = sources.llama-cpp.version;
        src =
          assert sources.llama-cpp.source.fetcher == "fetchFromGitHub";
          prev.fetchFromGitHub sources.llama-cpp.source.args;
        postPatch = "";
        npmRoot = "tools/ui";
        preConfigure = ''
          prependToVar cmakeFlags "-DLLAMA_BUILD_COMMIT:STRING=b${version}"
          pushd tools/ui
          # node 24.15.0's libuv has a kqueue assertion bug that triggers
          # SIGABRT on exit (`Assertion failed: (errno == EINTR), function
          # uv__io_poll, file kqueue.c, line 279`). The vite plugin writes
          # the final dist/index.html before the abort, so accept the
          # non-zero exit only when the expected output actually exists.
          npm run build || true
          [[ -f dist/index.html ]] || {
            echo "ERROR: tools/ui/dist/index.html not produced — npm run build genuinely failed" >&2
            exit 1
          }
          popd
        '';
        npmDepsHash = sources.llama-cpp.hashes.npmDepsHash;
        npmDeps = prev.fetchNpmDeps {
          name = "llama-cpp-${version}-npm-deps";
          inherit src;
          patches = attrs.patches or [ ];
          preBuild = "pushd tools/ui";
          hash = npmDepsHash;
        };
      })
    else if prev.stdenv.hostPlatform.isDarwin then
      prev.lib.warn "llama-cpp: Darwin pin inactive (no nodejs_latest override arg); using upstream llama-cpp" prev.llama-cpp
    else
      prev.llama-cpp;

  # pyarrow 22.0.0 has a broken test in the Nix sandbox.
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (_: pprev: {
      pyarrow = pprev.pyarrow.overrideAttrs (_: {
        doCheck = false;
        doInstallCheck = false;
      });
    })
    # nltk's chartparser test imports tkinter, absent from headless Python.
    (_: pprev: {
      nltk = pprev.nltk.overrideAttrs (old: {
        disabledTests = (old.disabledTests or [ ]) ++ [
          "test_chartparser_app_uses_pickle_load_not_pickle_load_standard"
        ];
      });
    })
  ];

  # The Python package override is pinned to the revision required by omlx.
  mlx-lm = final.python3Packages.mlx-lm;
}
