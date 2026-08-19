{ inputs }:
_final: prev:
let
  source = (import ../../packages/source-catalog.nix "ai").agnix;

  # agnix >= 0.49 uses `if let` guards (RFC 2294), stabilised in Rust 1.95.0.
  # nixpkgs' own rustc is older on some consumers of this overlay -- vulcan
  # pins nixpkgs 25.11, which ships 1.91.1 -- so building against
  # prev.rustPlatform fails there with:
  #     error[E0658]: `if let` guards are experimental
  # Pin the toolchain here rather than relying on whatever nixpkgs the
  # consumer happens to have. Mirrors the rustPlatform195 pattern already used
  # for qdrant in ./default.nix, but is NOT gated to x86_64 -- vulcan is
  # aarch64 and was the host that broke.
  rustPkgs = import inputs.nixpkgs {
    inherit (prev.stdenv.hostPlatform) system;
    overlays = [ inputs.rust-overlay.overlays.default ];
  };
  rust195 = rustPkgs.rust-bin.stable."1.95.0".minimal;
  rustPlatform195 = prev.makeRustPlatform {
    cargo = rust195;
    rustc = rust195;
  };
in
{

  agnix = rustPlatform195.buildRustPackage rec {
    pname = "agnix";
    inherit (source) version;

    src =
      assert source.source.fetcher == "fetchFromGitHub";
      prev.fetchFromGitHub source.source.args;

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

    meta = with prev.lib; {
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
