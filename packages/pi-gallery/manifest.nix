{ inputs, packages }:

let
  sources = import ../source-catalog.nix "pi";
  member =
    sourceName: value:
    let
      record = sources.${sourceName};
    in
    value
    // {
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
    "artifacts"
    "insights"
    "multi-pass"
    "router"
    "rewind"
    "scroll"
    "blackhole"
    "markdown-preview"
    "caveman"
    "rtk-optimizer"
    "cymbal-extension"
    "subagents"
    "dynamic-workflows"
    "goal"
  ];

  members = {
    hashline = member "pi-hashline-edit-pro" {
      attrName = "pi-hashline-edit-pro";
      package = packages.pi-hashline-edit-pro or null;
      publicName = "pi-hashline-edit-pro";
      extension = "index.ts";
    };
    smart-fetch = member "pi-smart-fetch" {
      attrName = "pi-smart-fetch";
      package = packages.pi-smart-fetch or null;
      publicName = "pi-smart-fetch";
      extension = "dist/index.js";
    };
    smart-web-search = member "pi-smart-web-search" {
      attrName = "pi-smart-web-search";
      package = packages.pi-smart-web-search or null;
      publicName = "pi-smart-web-search";
      extension = "index.ts";
    };
    lens = member "pi-lens" {
      attrName = "pi-lens";
      package = packages.pi-lens or null;
      publicName = "pi-lens";
      extension = "dist/index.js";
      skills = [ "skills" ];
    };
    ponytail = member "pi-ponytail" {
      attrName = "pi-ponytail";
      package = packages.pi-ponytail or null;
      projectionVersion = "${sources.pi-ponytail.version}+${builtins.substring 0 7 inputs.ponytail.rev}";
      publicName = "@dietrichgebert/ponytail";
      extension = "pi-extension/index.js";
      skills = [ ];
    };
    browser = member "pi-agent-browser-native" {
      attrName = "pi-agent-browser-native";
      package = packages.pi-agent-browser-native or null;
      publicName = "pi-agent-browser-native";
      extension = "dist/extensions/agent-browser/index.js";
    };
    btw = member "pi-btw" {
      attrName = "pi-btw";
      package = packages.pi-btw or null;
      publicName = "pi-btw";
      extension = "extensions/btw.ts";
      skills = [ "skills/btw" ];
    };
    artifacts = member "pi-artifacts" {
      attrName = "pi-artifacts";
      package = packages.pi-artifacts or null;
      publicName = "@jakeryderv/pi-artifacts";
      extension = "extensions/nix-bundle.js";
      skills = [ "skills/artifacts-authoring" ];
    };
    insights = member "pi-insights" {
      attrName = "pi-insights";
      package = packages.pi-insights or null;
      publicName = "@ygncode/pi-insights";
      extension = "index.ts";
    };
    multi-pass = member "pi-multi-pass" {
      attrName = "pi-multi-pass";
      package = packages.pi-multi-pass or null;
      publicName = "pi-multi-pass";
      extension = "extensions/multi-sub.ts";
    };
    router = member "pi-model-router" {
      attrName = "pi-model-router";
      package = packages.pi-model-router or null;
      publicName = "@yeliu84/pi-model-router";
      extension = "extensions/index.ts";
    };
    rewind = member "pi-rewind" {
      attrName = "pi-rewind";
      package = packages.pi-rewind or null;
      publicName = "pi-rewind";
      extension = "src/index.ts";
    };
    scroll = member "pi-scroll" {
      attrName = "pi-scroll";
      package = packages.pi-scroll or null;
      publicName = "pi-scroll";
      extension = "extensions/scroll.ts";
    };
    blackhole = member "pi-blackhole" {
      attrName = "pi-blackhole";
      package = packages.pi-blackhole or null;
      publicName = "pi-blackhole";
      extension = "index.ts";
    };
    markdown-preview = member "pi-markdown-preview" {
      attrName = "pi-markdown-preview";
      package = packages.pi-markdown-preview or null;
      publicName = "pi-markdown-preview";
      extension = "index.ts";
    };
    caveman = member "pi-caveman" {
      attrName = "pi-caveman";
      package = packages.pi-caveman or null;
      publicName = "pi-caveman";
      extension = "extensions/caveman.ts";
    };
    rtk-optimizer = member "pi-rtk-optimizer" {
      attrName = "pi-rtk-optimizer";
      package = packages.pi-rtk-optimizer or null;
      publicName = "pi-rtk-optimizer";
      extension = "index.ts";
    };
    cymbal-extension = member "pi-cymbal" {
      attrName = "pi-cymbal";
      package = packages.pi-cymbal or null;
      publicName = "pi-cymbal";
      extension = "dist/index.ts";
    };
    subagents = member "pi-subagents" {
      attrName = "pi-subagents";
      package = packages.pi-subagents or null;
      publicName = "pi-subagents";
      extension = "index.ts";
      skills = [ "skills" ];
      prompts = [ "prompts" ];
    };
    dynamic-workflows = member "pi-dynamic-workflows" {
      attrName = "pi-dynamic-workflows";
      package = packages.pi-dynamic-workflows or null;
      publicName = "@quintinshaw/pi-dynamic-workflows";
      extension = "extensions/workflow.ts";
      skills = [
        "skills/workflow-authoring"
        "skills/workflow-patterns"
      ];
    };
    goal = member "pi-goal-x" {
      attrName = "pi-goal-x";
      package = packages.pi-goal-x or null;
      publicName = "pi-goal-x";
      extension = "extensions/goal.ts";
    };
  };

  supportSources = {
    agent-browser = member "agent-browser" {
      attrName = "agent-browser";
      package = packages.agent-browser or null;
    };
    rtk = member "rtk" {
      attrName = "rtk";
      package = packages.rtk or null;
    };
    cymbal = member "cymbal" {
      attrName = "cymbal";
      package = packages.cymbal or null;
    };
  };
}
