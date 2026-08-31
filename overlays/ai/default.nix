{ inputs }:
[
  (
    _final: prev:
    prev.lib.optionalAttrs
      (
        prev.stdenv.buildPlatform.system == "x86_64-linux"
        && prev.stdenv.hostPlatform.system == "x86_64-linux"
      )
      (
        let
          rustPkgs = import inputs.nixpkgs {
            system = "x86_64-linux";
            overlays = [ inputs.rust-overlay.overlays.default ];
          };
          rust195 = rustPkgs.rust-bin.stable."1.95.0".minimal;
          rustPlatform195 = prev.makeRustPlatform {
            cargo = rust195;
            rustc = rust195;
          };
        in
        {
          qdrant = prev.qdrant.override { rustPlatform = rustPlatform195; };
        }
      )
  )
  inputs.mcp-servers-nix.overlays.default
  inputs.git-ai.overlays.default
  (_final: prev: {
    github-mcp-server =
      inputs.nixpkgs.legacyPackages.${prev.stdenv.hostPlatform.system}.callPackage
        (import "${inputs.nixpkgs}/pkgs/by-name/gi/github-mcp-server/package.nix")
        { };
  })
  ((import ./30-agent-resources.nix) { inherit inputs; })
  (import ./30-prime-agent.nix)
  (import ./30-agent-deck.nix)
  (import ./30-wiki.nix)
  (import ./30-ai-python.nix)
  (import ./30-ai-llm.nix)
  ((import ./30-ai-mcp.nix) {
    llmAgents = inputs.llm-agents;
    palMcpServer = inputs.pal-mcp-server or null;
  })
  (import ./30-lazycodex.nix)
  ((import ./30-agnix.nix) { inherit inputs; })
  (import ./30-claude-vault.nix)
  (import ./30-sherlock-db.nix)
  (import ./30-vllm-mlx.nix)
]
