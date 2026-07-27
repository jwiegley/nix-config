# Update targets that cannot be discovered from ordinary overlay package blocks.
let
  gallery = import ./pi-gallery/manifest.nix {
    inputs.ponytail.rev = "0000000";
    packages = { };
  };
  commonGalleryFiles = [
    "packages/pi-gallery/manifest.nix"
    "packages/pi-gallery/default.nix"
    "test/ai/pi-gallery.nix"
  ];
  galleryTargets = builtins.listToAttrs (
    map (
      id:
      let
        member = gallery.members.${id};
        override = member.update or { };
      in
      {
        name = override.targetName or member.attrName;
        value = {
          kind = override.kind or "npm-release";
          package = member.publicName;
          inherit (member) version;
          files = commonGalleryFiles ++ (override.files or [ ]);
        }
        // builtins.removeAttrs override [
          "files"
          "targetName"
        ];
      }
    ) gallery.order
  );
  agentBrowser = gallery.supportSources.agent-browser;
in
{
  schemaVersion = 1;

  targets = galleryTargets // {
    agent-browser = {
      kind = "npm-release";
      package = agentBrowser.attrName;
      inherit (agentBrowser) version;
      files = commonGalleryFiles;
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
