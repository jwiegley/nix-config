# LLM package exposure and compatibility overrides.
final: prev:

let
  sources = import ../../packages/source-catalog.nix "ai";
in
(import ../../packages/ai-llm.nix { inherit final prev; })
// {
  # Skip two Node fs.cp socket tests on Darwin.
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

  # llama.cpp's current web UI and npm project live under tools/ui.
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
          npm run build
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

  # Expose the catalog-pinned Python mlx-lm package at top level.
  mlx-lm = final.python3Packages.mlx-lm;
}
