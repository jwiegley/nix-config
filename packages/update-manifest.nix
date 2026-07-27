# Update targets that cannot be discovered from ordinary overlay package blocks.
# Keep this data declarative: bin/update-overlay evaluates it as JSON and WU4
# derives package/gallery projections from the same records.
{
  schemaVersion = 1;

  targets = {
    pi-hashline-edit-pro = {
      kind = "npm-release";
      package = "pi-hashline-edit-pro";
      version = "0.17.5";
      files = [
        "packages/pi-gallery/default.nix"
        "packages/pi-gallery/locks/pi-hashline-edit-pro-package-lock.json"
        "test/ai/pi-gallery.nix"
      ];
    };
    pi-web-access = {
      kind = "npm-release";
      package = "pi-web-access";
      version = "0.13.0";
      files = [
        "packages/pi-gallery/default.nix"
        "packages/pi-gallery/locks/pi-web-access-package-lock.json"
        "test/ai/pi-gallery.nix"
      ];
    };
    pi-lens = {
      kind = "npm-release";
      package = "pi-lens";
      version = "3.8.71";
      files = [
        "packages/pi-gallery/default.nix"
        "packages/pi-gallery/locks/pi-lens-package-lock.json"
        "test/ai/pi-gallery.nix"
      ];
    };
    pi-dynamic-workflows = {
      kind = "npm-release";
      package = "@quintinshaw/pi-dynamic-workflows";
      version = "3.4.1";
      files = [
        "packages/pi-gallery/default.nix"
        "packages/pi-gallery/locks/pi-dynamic-workflows-package-lock.json"
        "test/ai/pi-gallery.nix"
      ];
    };
    pi-agent-browser-native = {
      kind = "npm-release";
      package = "pi-agent-browser-native";
      version = "0.2.72";
      files = [
        "packages/pi-gallery/default.nix"
        "test/ai/pi-gallery.nix"
      ];
    };
    pi-btw = {
      kind = "npm-release+flake-input";
      package = "pi-btw";
      flakeInput = "pi-btw";
      version = "0.4.1";
      files = [
        "flake.lock"
        "config/ai/flake.lock"
        "packages/pi-gallery/default.nix"
        "test/ai/pi-gallery.nix"
      ];
    };
    pi-artifacts = {
      kind = "npm-release";
      package = "@jakeryderv/pi-artifacts";
      version = "0.9.0";
      files = [
        "packages/pi-gallery/default.nix"
        "packages/pi-gallery/locks/pi-artifacts-package-lock.json"
        "test/ai/pi-gallery.nix"
      ];
    };
    pi-insights = {
      kind = "npm-release";
      package = "@ygncode/pi-insights";
      version = "1.0.1";
      files = [
        "packages/pi-gallery/default.nix"
        "packages/pi-gallery/locks/pi-insights-package-lock.json"
        "test/ai/pi-gallery.nix"
      ];
    };
    pi-subagentura = {
      kind = "npm-release+flake-input";
      package = "pi-subagentura";
      flakeInput = "pi-subagentura";
      version = "3.0.3";
      files = [
        "flake.lock"
        "config/ai/flake.lock"
        "packages/pi-gallery/default.nix"
        "config/ai/catalog.nix"
        "test/ai/home-manager-contract.nix"
        "test/ai/pi-gallery.nix"
      ];
    };
    pi-provider-litellm = {
      kind = "npm-release";
      package = "pi-provider-litellm";
      version = "2.0.0";
      files = [
        "packages/pi-gallery/default.nix"
        "config/ai/catalog.nix"
        "test/ai/home-manager-contract.nix"
        "test/ai/pi-gallery.nix"
      ];
    };
    pi-model-router = {
      kind = "npm-release";
      package = "@yeliu84/pi-model-router";
      version = "0.4.4";
      files = [
        "packages/pi-gallery/default.nix"
        "config/ai/catalog.nix"
        "test/ai/home-manager-contract.nix"
        "test/ai/pi-gallery.nix"
      ];
    };
    pi-rewind = {
      kind = "npm-release";
      package = "pi-rewind";
      version = "0.5.0";
      files = [
        "packages/pi-gallery/default.nix"
        "test/ai/pi-gallery.nix"
      ];
    };
    pi-scroll = {
      kind = "npm-release";
      package = "pi-scroll";
      version = "0.1.2";
      files = [
        "packages/pi-gallery/default.nix"
        "test/ai/pi-gallery.nix"
      ];
    };
    agent-browser = {
      kind = "npm-release";
      package = "agent-browser";
      version = "0.33.0";
      files = [
        "packages/pi-gallery/default.nix"
        "test/ai/pi-gallery.nix"
      ];
    };

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
    bigpowers = {
      kind = "flake-input+copy";
      flakeInput = "bigpowers";
      version = "2.84.0";
      files = [
        "flake.lock"
        "config/ai/flake.lock"
        "config/ai/bigpowers-resources.nix"
        "packages/pi-gallery/default.nix"
        "test/ai/pi-gallery.nix"
      ];
    };
    ponytail = {
      kind = "flake-input+copy";
      flakeInput = "ponytail";
      version = "4.8.4";
      files = [
        "flake.lock"
        "config/ai/flake.lock"
        "packages/pi-gallery/default.nix"
        "test/ai/pi-gallery.nix"
      ];
    };

    ws = {
      kind = "npm-release";
      package = "ws";
      version = "8.18.3";
      files = [ "packages/agent-resources.nix" ];
    };

    anvil-mcp = {
      kind = "github-commit";
      owner = "jwiegley";
      repo = "anvil.el";
      version = "1.3.0";
      rev = "39f9c59bfc51379db6243b1be20edca1ea783c2b";
      files = [ "packages/anvil-mcp/source.nix" ];
    };
    anvil-ide = {
      kind = "github-commit";
      owner = "zawatton";
      repo = "anvil-ide.el";
      rev = "0e6130457ac2bdc6c6db2eebeba67a5223231190";
      files = [ "packages/anvil-mcp/source.nix" ];
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

    agent-browser-source = {
      kind = "fixed-flake-input";
      flakeInput = "agent-browser-source";
      rev = "1ed371f3af472cc0d6cd8fdaea75d1a085ff7534";
      files = [
        "flake.nix"
        "config/ai/flake.nix"
        "packages/pi-gallery/default.nix"
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
