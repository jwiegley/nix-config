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
    "web"
    "lens"
    "ponytail"
    "workflows"
    "browser"
    "btw"
    "artifacts"
    "insights"
    "litellm"
    "router"
    "rewind"
    "scroll"
  ];

  members = {
    hashline = member "pi-hashline-edit-pro" {
      attrName = "pi-hashline-edit-pro";
      package = packages.pi-hashline-edit-pro or null;
      publicName = "pi-hashline-edit-pro";
      extension = "index.ts";
    };
    web = member "pi-web-access" {
      attrName = "pi-web-access";
      package = packages.pi-web-access or null;
      publicName = "pi-web-access";
      extension = "index.ts";
      skills = [ "skills" ];
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
    workflows = member "pi-dynamic-workflows" {
      attrName = "pi-dynamic-workflows";
      package = packages.pi-dynamic-workflows or null;
      publicName = "@quintinshaw/pi-dynamic-workflows";
      extension = "extensions/workflow.ts";
      skills = [
        "skills/workflow-authoring"
        "skills/workflow-patterns"
      ];
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
    litellm = member "pi-provider-litellm" {
      attrName = "pi-provider-litellm";
      package = packages.pi-provider-litellm or null;
      publicName = "pi-provider-litellm";
      extension = "dist/index.js";
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
  };

  supportSources = {
    agent-browser = member "agent-browser" {
      attrName = "agent-browser";
      package = packages.agent-browser or null;
    };
    bigpowers = member "bigpowers" {
      attrName = "bigpowers";
      package = packages.bigpowers or null;
    };
  };
}
