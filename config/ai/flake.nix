{
  description = "Portable AI CLI and MCP tooling";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    rust-overlay = {
      url = "github:oxalica/rust-overlay/47759faaddf38fadaf172151ca9df8adae9c0b2e";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents.url = "github:numtide/llm-agents.nix";

    superpowers = {
      url = "github:obra/superpowers/d884ae04edebef577e82ff7c4e143debd0bbec99";
      flake = false;
    };

    ponytail = {
      url = "github:DietrichGebert/ponytail/16f29800fd2681bdf24f3eb4ccffe38be3baec6b";
      flake = false;
    };

    translate-tool = {
      url = "github:jwiegley/translate-tool/bffdb7ba3e5db603ea1390fee555354c1d45d642";
      flake = false;
    };

    pi-mcp-adapter = {
      url = "github:nicobailon/pi-mcp-adapter/82724dccc13a49310530898f922bafff12b7f3fe";
      flake = false;
    };

    pi-openai-server-compaction = {
      url = "github:algal/pi-openai-server-compaction/c6d593087709e9481223dc6c6c2269b371b5e055";
      flake = false;
    };

    pi-quiet = {
      url = "github:zenspc/pi-extensions/b281afef4e61188e7aa76aaa114ba505274fa7bc";
      flake = false;
    };

    pi-subagent = {
      url = "github:mjakl/pi-subagent/70248dcf7c8a5ca74497e817a699f009c55e6917";
      flake = false;
    };

    mcp-remote = {
      url = "github:geelen/mcp-remote/02619aff36e79803d7c894e8c8ae7b34b2d11f8c";
      flake = false;
    };

    git-ai = {
      url = "github:git-ai-project/git-ai";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pal-mcp-server = {
      url = "github:jwiegley/pal-mcp-server";
      flake = false;
    };
  };

  outputs =
    inputs:
    import ../../tests/ai/compatibility-check.nix {
      inherit inputs;
      actual = import ../../packages/ai-flake-outputs.nix inputs;
    };
}
