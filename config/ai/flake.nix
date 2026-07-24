{
  description = "Portable AI CLI and MCP tooling";

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

    bigpowers = {
      url = "github:danielvm-git/bigpowers";
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

    pi-hashline-edit-pro = {
      url = "github:YuGiMob/pi-hashline-edit-pro";
      flake = false;
    };

    pi-web-access = {
      url = "github:nicobailon/pi-web-access";
      flake = false;
    };

    pi-lens = {
      url = "github:apmantza/pi-lens";
      flake = false;
    };

    pi-dynamic-workflows = {
      url = "github:QuintinShaw/pi-dynamic-workflows";
      flake = false;
    };

    pi-agent-browser-native = {
      url = "github:fitchmultz/pi-agent-browser-native";
      flake = false;
    };

    lean-ctx = {
      url = "github:yvgude/lean-ctx";
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

    pi-artifacts = {
      url = "github:jakeryderv/pi-packages";
      flake = false;
    };

    pi-btw = {
      url = "github:dbachelder/pi-btw";
      flake = false;
    };

    pi-insights = {
      url = "github:ygncode/pi-insights";
      flake = false;
    };

    pi-subagentura = {
      url = "github:lmn451/pi-subagentura";
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
    import ../../test/ai/compatibility-check.nix {
      inherit inputs;
      actual = import ../../packages/ai-flake-outputs.nix inputs;
    };
}
