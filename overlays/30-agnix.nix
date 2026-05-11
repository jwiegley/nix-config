# overlays/30-agnix.nix
# Purpose: agnix - Linter and LSP for AI coding assistant config files
# Dependencies: Uses prev only
# Packages: agnix
final: prev: {

  agnix =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "agnix";
      version = "0.25.0";

      src = fetchFromGitHub {
        owner = "avifenesh";
        repo = "agnix";
        tag = "v${version}";
        hash = "sha256-NT1I68et5n4ctvWKRssaqpF2yaCR5DFRbOaH8w/xVP4=";
      };

      cargoHash = "sha256-VdYAUX30NpYe64T0T69lUOaVBACSfE6GXDL2ust82CY=";

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
