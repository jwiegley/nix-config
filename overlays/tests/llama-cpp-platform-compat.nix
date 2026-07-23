{ runCommand }:

let
  overlay = import ../30-ai-llm.nix;

  linuxResult =
    (overlay { } {
      stdenv.isDarwin = false;
      llama-cpp = {
        marker = "linux-upstream";
        override = _: throw "llama-cpp must not be overridden on Linux";
      };
    }).llama-cpp;

  darwinResult =
    (overlay { nodejs_22 = "nodejs-22"; } {
      stdenv.isDarwin = true;
      llama-cpp.override = args: {
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
      fetchFromGitHub = args: args;
      fetchNpmDeps = args: args;
    }).llama-cpp;
in
assert linuxResult.marker == "linux-upstream";
assert darwinResult.marker == "darwin-override";
assert darwinResult.args.nodejs_latest == "nodejs-22";
assert darwinResult.attrs.version == "10079";
assert darwinResult.attrs.npmRoot == "tools/ui";
assert darwinResult.attrs.npmDeps.patches == [ "existing.patch" ];
runCommand "llama-cpp-platform-compat" { } "touch $out"
