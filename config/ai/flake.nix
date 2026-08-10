{
  description = "Portable fleet CLI, agent, and MCP configuration";

  inputs = {
    agent-browser-source = {
      url = "github:vercel-labs/agent-browser/da1237e2543de87119cfd48cb48284402bd4dc40";
      flake = false;
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # cm's compiled output is coupled to Bun's executable template. Keep its
    # build Bun independent of consumer channels so all fleet hosts use the
    # exact runtime version recorded in sources/ai.json.
    cm-bun-nixpkgs.url = "github:NixOS/nixpkgs/a5e9f2fd9ef6011c6886d6935f3ef678c81385fa";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents.url = "github:numtide/llm-agents.nix";

    obr.url = "github:jwiegley/obr";

    # Pi combines llm-agents packaging with the reviewed patched source in
    # packages/pi-source-build.nix. Keep that packaging substrate at the exact
    # compatible revision while the general llm-agents feed advances.
    pi-llm-agents.url = "github:numtide/llm-agents.nix/f99bb437fd6860f23ea6c67a5161578a3b89d856";

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
        inputNames = builtins.attrNames portableInputs;
      };
    };
}
