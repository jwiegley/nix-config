{ inputs, packages }:

let
  sources = import ../source-catalog.nix "pi";
  member =
    sourceName: value:
    let
      record = sources.${sourceName};
    in
    {
      # The gallery attribute and the package lookup always follow the source
      # name; publicName stays explicit because the npm registry identity is
      # independent data (several members are scoped).
      attrName = sourceName;
      package = packages.${sourceName} or null;
    }
    // value
    // {
      inherit sourceName;
      inherit (record) source update version;
      artifacts = record.artifacts or { };
      hashes = record.hashes or { };
    };
in
{
  sourceCatalog = sources;

  order = [
    "hashline"
    "smart-fetch"
    "smart-web-search"
    "lens"
    "ponytail"
    "browser"
    "btw"
    "copy-message"
    "artifacts"
    "insights"
    "usage"
    "multi-pass"
    "llama-swap-provider"
    "omlx-provider"
    "router"
    "rewind"
    "blackhole"
    "trace"
    "markdown-preview"
    "caveman"
    "rtk-optimizer"
    "cymbal-extension"
    "subagents"
    "dynamic-workflows"
    "goal"
    "cache-optimizer"
  ];

  members = {
    hashline = member "pi-hashline-edit-pro" {
      publicName = "pi-hashline-edit-pro";
      extension = "index.ts";
    };
    smart-fetch = member "pi-smart-fetch" {
      publicName = "pi-smart-fetch";
      extension = "dist/index.js";
    };
    smart-web-search = member "pi-smart-web-search" {
      publicName = "pi-smart-web-search";
      extension = "index.ts";
    };
    lens = member "pi-lens" {
      publicName = "pi-lens";
      extension = "dist/index.js";
      skills = [ "skills" ];
    };
    ponytail = member "pi-ponytail" {
      projectionVersion = "${sources.pi-ponytail.version}+${builtins.substring 0 7 inputs.ponytail.rev}";
      publicName = "@dietrichgebert/ponytail";
      extension = "pi-extension/index.js";
      skills = [ ];
    };
    browser = member "pi-agent-browser-native" {
      publicName = "pi-agent-browser-native";
      extension = "dist/extensions/agent-browser/index.js";
    };
    btw = member "pi-btw" {
      publicName = "pi-btw";
      extension = "extensions/btw.ts";
      skills = [ "skills/btw" ];
    };
    copy-message = member "pi-copy-message" {
      publicName = "pi-copy-message";
      extension = "extensions/copy-message.ts";
    };
    artifacts = member "pi-artifacts" {
      publicName = "@jakeryderv/pi-artifacts";
      extension = "extensions/nix-bundle.js";
      skills = [ "skills/artifacts-authoring" ];
    };
    insights = member "pi-insights" {
      publicName = "@ygncode/pi-insights";
      extension = "index.ts";
    };
    usage = member "pi-usage-extension" {
      publicName = "@tmustier/pi-usage-extension";
      extension = "index.ts";
    };
    multi-pass = member "pi-multi-pass" {
      publicName = "pi-multi-pass";
      extension = "extensions/multi-sub.ts";
    };
    llama-swap-provider = member "pi-provider-llama-swap" {
      publicName = "pi-provider-llama-swap";
      extension = "index.ts";
    };
    omlx-provider = member "pi-provider-omlx" {
      publicName = "pi-provider-omlx";
      extension = "index.ts";
    };
    router = member "pi-model-router" {
      publicName = "@yeliu84/pi-model-router";
      extension = "extensions/index.ts";
    };
    rewind = member "pi-rewind" {
      publicName = "pi-rewind";
      extension = "src/index.ts";
    };
    blackhole = member "pi-blackhole" {
      publicName = "pi-blackhole";
      extension = "index.ts";
    };
    trace = member "pi-trace-extension" {
      publicName = "pi-trace-extension";
      extension = "extensions/trace/index.ts";
    };
    markdown-preview = member "pi-markdown-preview" {
      publicName = "pi-markdown-preview";
      extension = "index.ts";
    };
    caveman = member "pi-caveman" {
      publicName = "pi-caveman";
      extension = "extensions/caveman.ts";
    };
    rtk-optimizer = member "pi-rtk-optimizer" {
      publicName = "pi-rtk-optimizer";
      extension = "index.ts";
    };
    cymbal-extension = member "pi-cymbal" {
      publicName = "pi-cymbal";
      extension = "dist/index.ts";
    };
    subagents = member "pi-subagents" {
      publicName = "pi-subagents";
      extension = "index.ts";
      skills = [ "skills" ];
      prompts = [ "prompts" ];
    };
    dynamic-workflows = member "pi-dynamic-workflows" {
      publicName = "@quintinshaw/pi-dynamic-workflows";
      extension = "extensions/workflow.ts";
      skills = [
        "skills/workflow-authoring"
        "skills/workflow-patterns"
      ];
    };
    goal = member "pi-goal-x" {
      publicName = "pi-goal-x";
      extension = "extensions/goal.ts";
    };
    cache-optimizer = member "pi-cache-optimizer" {
      publicName = "pi-cache-optimizer";
      extension = "index.ts";
    };
  };

  supportSources = {
    loop = member "pi-loop" {
      publicName = "@realvendex/pi-loop";
    };
    agent-browser = member "agent-browser" {
    };
    rtk = member "rtk" {
    };
    cymbal = member "cymbal" {
    };
  };

  # Pi catalog records owned outside the gallery. Every source must be either a
  # gallery/support member above or explicitly mapped to its external consumer.
  externalSourceConsumers = {
    agent-browser-source = "packages/pi-gallery/default.nix";
    pi-mcp-adapter = "packages/agent-resources.nix";
    pi-openai-server-compaction = "packages/agent-resources.nix";
    pi-quiet = "packages/agent-resources.nix";
    ws = "packages/agent-resources.nix";
  };
}
