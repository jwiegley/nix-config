{
  description = "Portable fleet CLI, agent, and MCP configuration";

  inputs = {
    agent-browser-source = {
      url = "github:vercel-labs/agent-browser/1ed371f3af472cc0d6cd8fdaea75d1a085ff7534";
      flake = false;
    };

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

    mcp-remote = {
      url = "github:geelen/mcp-remote";
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
    let
      portableInputs = builtins.removeAttrs inputs [ "self" ];
      actual = import ../../flake-ai.nix portableInputs;
      checked = import ../../test/ai/compatibility-check.nix {
        inputs = portableInputs;
        inherit actual;
      };
    in
    checked
    // {
      lib = checked.lib // {
        inputSet = portableInputs;
        inputNames = builtins.attrNames portableInputs;
      };
    };
}
