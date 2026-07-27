# Update targets that cannot be discovered from ordinary overlay package blocks.
{
  schemaVersion = 1;

  targets = {

    pi-mcp-adapter = {
      kind = "flake-input+build";
      flakeInput = "pi-mcp-adapter";
      version = "2.12.1";
      files = [
        "flake.lock"
        "config/ai/flake.lock"
        "packages/agent-resources.nix"
        "config/ai/catalog.nix"
        "test/ai/agent-resources.nix"
        "test/ai/home-manager-contract.nix"
      ];
    };

    ws = {
      kind = "npm-release";
      package = "ws";
      version = "8.18.3";
      files = [ "packages/agent-resources.nix" ];
    };

    nelisp = {
      kind = "github-commit";
      owner = "zawatton";
      repo = "nelisp";
      version = "0.5.1";
      rev = "f753209d53b372933b829345fe4373acad67bcb5";
      files = [
        "packages/anvil-mcp/default.nix"
        "packages/anvil-mcp/Cargo.lock"
      ];
    };
    standalone-anvil = {
      kind = "github-commit";
      owner = "zawatton";
      repo = "anvil.el";
      version = "1.1.1";
      rev = "d50ce32b71c5fa46da3aa661481c8be44fee4f97";
      files = [ "packages/anvil-mcp/default.nix" ];
    };

    git-ai = {
      kind = "flake-input";
      flakeInput = "git-ai";
      executor = "update-agents";
      files = [
        "flake.lock"
        "config/ai/flake.lock"
      ];
    };
    llm-agents = {
      kind = "flake-input";
      flakeInput = "llm-agents";
      executor = "update-agents";
      files = [
        "flake.lock"
        "config/ai/flake.lock"
      ];
    };
    mcp-remote = {
      kind = "flake-input";
      flakeInput = "mcp-remote";
      executor = "update-agents";
      files = [
        "flake.lock"
        "config/ai/flake.lock"
      ];
    };
    mcp-servers-nix = {
      kind = "flake-input";
      flakeInput = "mcp-servers-nix";
      executor = "update-agents";
      files = [
        "flake.lock"
        "config/ai/flake.lock"
      ];
    };
    pal-mcp-server = {
      kind = "flake-input";
      flakeInput = "pal-mcp-server";
      executor = "update-agents";
      files = [
        "flake.lock"
        "config/ai/flake.lock"
      ];
    };
    pi-openai-server-compaction = {
      kind = "flake-input";
      flakeInput = "pi-openai-server-compaction";
      executor = "update-agents";
      files = [
        "flake.lock"
        "config/ai/flake.lock"
      ];
    };
    pi-quiet = {
      kind = "flake-input";
      flakeInput = "pi-quiet";
      executor = "update-agents";
      files = [
        "flake.lock"
        "config/ai/flake.lock"
      ];
    };
    translate-tool = {
      kind = "flake-input";
      flakeInput = "translate-tool";
      executor = "update-agents";
      files = [
        "flake.lock"
        "config/ai/flake.lock"
      ];
    };

    rust-overlay = {
      kind = "fixed-flake-input";
      flakeInput = "rust-overlay";
      rev = "47759faaddf38fadaf172151ca9df8adae9c0b2e";
      files = [
        "flake.nix"
        "config/ai/flake.nix"
      ];
    };
  };
}
