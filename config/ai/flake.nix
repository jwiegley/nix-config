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
      url = "github:danielvm-git/bigpowers/960ab5283e7b7766f02fbf8703da5bb6e997159d";
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

    pi-hashline-edit-pro = {
      url = "github:YuGiMob/pi-hashline-edit-pro/5d97f2a0d8aaa0e06a637583845263ed2ca455f1";
      flake = false;
    };

    pi-web-access = {
      url = "github:nicobailon/pi-web-access/7bdc30a65cf77273eb9c0034647b373bda4060d7";
      flake = false;
    };

    pi-lens = {
      url = "github:apmantza/pi-lens/2ea8691a25e3a39bf944e0d1c5ed4178c50b55da";
      flake = false;
    };

    pi-dynamic-workflows = {
      url = "github:QuintinShaw/pi-dynamic-workflows/6d866e16396ca487dfde2591dd4d4e7ab04e9ba1";
      flake = false;
    };

    pi-agent-browser-native = {
      url = "github:fitchmultz/pi-agent-browser-native/211a012c9b199d758768e8ba729f35e11e661f65";
      flake = false;
    };

    lean-ctx = {
      url = "github:yvgude/lean-ctx/54e0a66bcbb9a6695e45848d3ea97a491a0b5275";
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

    pi-artifacts = {
      url = "github:jakeryderv/pi-packages/9056b18bac35d01fa79d255911f0a74b919c46d2";
      flake = false;
    };

    pi-btw = {
      url = "github:dbachelder/pi-btw/4f858102706910ee9d520a9666832f3103631b61";
      flake = false;
    };

    pi-insights = {
      url = "github:ygncode/pi-insights/f2de4880e5d8b1f66f207e220269703b6ca38ecf";
      flake = false;
    };

    pi-subagentura = {
      url = "github:lmn451/pi-subagentura/e49e4d259a1b0186ac6924602b5faf673f61bee3";
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
