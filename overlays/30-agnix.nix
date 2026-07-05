# overlays/30-agnix.nix
# Purpose: agnix - Linter and LSP for AI coding assistant config files
# Dependencies: Uses prev only
# Packages: agnix
_final: prev: {

  agnix =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "agnix";
      version = "0.37.5";

      src = fetchFromGitHub {
        owner = "avifenesh";
        repo = "agnix";
        tag = "v${version}";
        hash = "sha256-PILK3m21wtVYHDhXmN73qWOod0q4muaQvBCwrnNjdXk=";
      };

      cargoHash = "sha256-f2qdRfNwcfa2VMmaw4j1WQt8CPh5qzKRFM8PUT0iptA=";

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
        mainProgram = "agnix";
      };
    };

}
