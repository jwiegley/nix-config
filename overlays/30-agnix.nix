# overlays/30-agnix.nix
# Purpose: agnix - Linter and LSP for AI coding assistant config files
# Dependencies: Uses prev only
# Packages: agnix
final: prev: {

  agnix =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "agnix";
      version = "0.17.0";

      src = fetchFromGitHub {
        owner = "avifenesh";
        repo = "agnix";
        tag = "v${version}";
        hash = "sha256-Pkhyn9kRws9lwmZ6aJigCBX6ywnfpp80VPk/5zT5ZzE=";
      };

      cargoHash = "sha256-8EQ7GMmuYuoLHIZ5sa5KPoP7Ul129NIIk57W8RjnNiI=";

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
