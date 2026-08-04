# Purpose: agnix - Linter and LSP for AI coding assistant config files
# Dependencies: Uses prev only
# Packages: agnix
_final: prev:
let
  source = (import ../../packages/source-catalog.nix "ai").agnix;
in
{

  agnix =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "agnix";
      inherit (source) version;

      src =
        assert source.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub source.source.args;

      cargoHash = source.hashes.cargoHash;

      # Build all workspace binaries (CLI, LSP, MCP server)
      cargoBuildFlags = [
        "--package"
        "agnix-cli"
        "--package"
        "agnix-lsp"
        "--package"
        "agnix-mcp"
      ];

      doCheck = false;

      meta = with lib; {
        description = "Linter and LSP for AI coding assistant config files (CLAUDE.md, AGENTS.md, hooks, MCP)";
        homepage = "https://github.com/avifenesh/agnix";
        license = with licenses; [
          mit
          asl20
        ];
        mainProgram = "agnix";
      };
    };

}
