# overlays/30-agnix.nix
# Purpose: agnix - Linter and LSP for AI coding assistant config files
# Dependencies: Uses prev only
# Packages: agnix
final: prev: {

  agnix =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "agnix";
      version = "0.22.1";

      src = fetchFromGitHub {
        owner = "avifenesh";
        repo = "agnix";
        tag = "v${version}";
        hash = "sha256-9ZTFQ5IRkK90pZ5fDSgp5OFPupTVpjDkZDw09OQOa8o=";
      };

      cargoHash = "sha256-f0P2UclcIiOwbIJNHA2VSf1Fk6lAJyz+FdotKkfMuvI=";

      # Build all workspace binaries (CLI, LSP, MCP server)
      cargoBuildFlags = [
        "--package"
        "agnix-cli"
        "--package"
        "agnix-lsp"
        "--package"
        "agnix-mcp"
      ];

      # Tests require fixtures that may not work in sandbox
      doCheck = false;

      meta = with lib; {
        description = "Linter and LSP for AI coding assistant config files (CLAUDE.md, AGENTS.md, hooks, MCP)";
        homepage = "https://github.com/avifenesh/agnix";
        license = with licenses; [
          mit
          asl20
        ];
        maintainers = with maintainers; [ jwiegley ];
        mainProgram = "agnix";
      };
    };

}
