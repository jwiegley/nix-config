{ runCommand }:

let
  overlay = import ../../../overlays/ai/30-ai-llm.nix;
  source = (import ../../../packages/source-catalog.nix "ai").llama-cpp;

  linuxResult =
    (overlay { } {
      stdenv.hostPlatform.isDarwin = false;
      llama-cpp = {
        marker = "linux-upstream";
        override = _: throw "llama-cpp must not be overridden on Linux";
      };
    }).llama-cpp;

  darwinResult =
    (overlay { nodejs_22 = "nodejs-22"; } {
      stdenv.hostPlatform.isDarwin = true;
      llama-cpp.override = {
        __functionArgs.nodejs_latest = false;
        __functor = _self: args: {
          overrideAttrs =
            update:
            let
              attrs = update { patches = [ "existing.patch" ]; };
            in
            {
              inherit args attrs;
              marker = "darwin-override";
            };
        };
      };
      fetchFromGitHub = args: args;
      fetchNpmDeps = args: args;
    }).llama-cpp;

  legacyDarwinResult =
    (overlay { } {
      stdenv.hostPlatform.isDarwin = true;
      lib.warn = message: value: builtins.trace message value;
      llama-cpp = {
        marker = "legacy-darwin-upstream";
        override = {
          __functionArgs = { };
          __functor = _self: _: throw "legacy llama-cpp must not be overridden";
        };
      };
    }).llama-cpp;
in
assert linuxResult.marker == "linux-upstream";
assert legacyDarwinResult.marker == "legacy-darwin-upstream";
assert darwinResult.marker == "darwin-override";
assert darwinResult.args.nodejs_latest == "nodejs-22";
assert darwinResult.attrs.version == source.version;
assert darwinResult.attrs.npmRoot == "tools/ui";
assert darwinResult.attrs.npmDeps.patches == [ "existing.patch" ];
runCommand "llama-cpp-platform-compat" { } "touch $out"
