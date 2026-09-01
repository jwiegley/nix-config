{
  description = "Portable fleet CLI, agent, and MCP configuration";

  inputs = {
    agent-browser-source = {
      url = "github:vercel-labs/agent-browser/eb05921bad874cd2a1b4fa5d1149f1ed26576cae";
      flake = false;
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # pi-mcp-adapter's public build needs npm dependency-cache format v2.
    # Keep its coherent builder and cache hook independent of consumer
    # nixpkgs: release-25.11 silently ignores npmDepsFetcherVersion and uses
    # cache format v1.
    npm-cache-nixpkgs = {
      url = "github:NixOS/nixpkgs/a831408e6378bc02ebf8cc09b52c96ca86f6bab4";
      flake = false;
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents.url = "github:numtide/llm-agents.nix";

    pi = {
      url = "github:jwiegley/pi/94c965e85f5825a6dd7b9063a93f92aae819539c";
      flake = false;
    };

    ponytail = {
      url = "github:DietrichGebert/ponytail";
      flake = false;
    };

    translate-tool = {
      url = "github:jwiegley/translate-tool";
      flake = false;
    };

    pi-mcp-adapter = {
      url = "github:nicobailon/pi-mcp-adapter";
      flake = false;
    };

    pi-openai-server-compaction = {
      url = "github:algal/pi-openai-server-compaction";
      flake = false;
    };

    pi-quiet = {
      url = "github:zenspc/pi-extensions";
      flake = false;
    };

    pi-btw = {
      url = "github:dbachelder/pi-btw/4f858102706910ee9d520a9666832f3103631b61";
      flake = false;
    };

    git-ai = {
      url = "github:git-ai-project/git-ai";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };

    pal-mcp-server = {
      url = "github:jwiegley/pal-mcp-server";
      flake = false;
    };
  };

  outputs =
    inputs:
    let
      portableInputs = builtins.removeAttrs inputs [ "self" ];
      actual = import ../../flake/ai.nix portableInputs;
      checked = import ../../test/ai/compatibility-check.nix {
        inputs = portableInputs;
        inherit actual;
      };
    in
    checked
    // {
      lib = checked.lib // {
        inputSet = portableInputs;
      };
    };
}
