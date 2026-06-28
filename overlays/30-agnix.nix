# overlays/30-agnix.nix
# Purpose: agnix - Linter and LSP for AI coding assistant config files
# Dependencies: Uses prev only
# Packages: agnix
_final: prev: {

  agnix =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "agnix";
      version = "0.36.2";

      src = fetchFromGitHub {
        owner = "avifenesh";
        repo = "agnix";
        tag = "v${version}";
        hash = "sha256-MbOF8RuSyB2RPmYSsBsPbBzP8asnKN4Drskgp7VKlAI=";
      };

      cargoHash = "sha256-sfsAJVdxJ7cCGVQM4pVMcrZqBrIIKNUd9POgElLZ9ek=";

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
