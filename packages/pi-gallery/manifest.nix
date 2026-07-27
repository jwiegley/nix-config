{ inputs, packages }:

let
  npm = url: hash: { inherit url hash; };
in
{
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
    "subagentura"
    "litellm"
    "router"
    "rewind"
    "scroll"
  ];

  members = {
    hashline = {
      attrName = "pi-hashline-edit-pro";
      package = packages.pi-hashline-edit-pro or null;
      version = "0.17.5";
      publicName = "pi-hashline-edit-pro";
      source = npm "https://registry.npmjs.org/pi-hashline-edit-pro/-/pi-hashline-edit-pro-0.17.5.tgz" "sha256-WrPRKhBNUJc6l4u1v4k8dftGUQA2Pj754zE07h3QTxU=";
      extension = "index.ts";
    };
    web = {
      attrName = "pi-web-access";
      package = packages.pi-web-access or null;
      version = "0.13.0";
      publicName = "pi-web-access";
      source = npm "https://registry.npmjs.org/pi-web-access/-/pi-web-access-0.13.0.tgz" "sha256-GmPsueJdqj4Ny+fxlwMWRVnehe4bv1GeiBo0i5uAQAA=";
      extension = "index.ts";
      skills = [ "skills" ];
    };
    lens = {
      attrName = "pi-lens";
      package = packages.pi-lens or null;
      version = "3.8.71";
      publicName = "pi-lens";
      source = npm "https://registry.npmjs.org/pi-lens/-/pi-lens-3.8.71.tgz" "sha256-YoBaBtZx5dz3QOtGharxOyVG/qlcmOTbAFVrlJ4fhqw=";
      extension = "dist/index.js";
      skills = [ "skills" ];
    };
    ponytail = {
      attrName = "pi-ponytail";
      package = packages.pi-ponytail or null;
      version = "4.8.4";
      projectionVersion = "4.8.4+${builtins.substring 0 7 inputs.ponytail.rev}";
      publicName = "@dietrichgebert/ponytail";
      extension = "pi-extension/index.js";
      skills = [ ];
    };
    workflows = {
      attrName = "pi-dynamic-workflows";
      package = packages.pi-dynamic-workflows or null;
      version = "3.4.1";
      publicName = "@quintinshaw/pi-dynamic-workflows";
      source = npm "https://registry.npmjs.org/@quintinshaw/pi-dynamic-workflows/-/pi-dynamic-workflows-3.4.1.tgz" "sha256-5bCDyn+yzRr3rUxDzHT+bGbGxYrv8gSl7S3YhN+pZ0U=";
      extension = "extensions/workflow.ts";
      skills = [
        "skills/workflow-authoring"
        "skills/workflow-patterns"
      ];
    };
    browser = {
      attrName = "pi-agent-browser-native";
      package = packages.pi-agent-browser-native or null;
      version = "0.2.72";
      publicName = "pi-agent-browser-native";
      source = npm "https://registry.npmjs.org/pi-agent-browser-native/-/pi-agent-browser-native-0.2.72.tgz" "sha256-3subgZHSxRN4wigNrM0KO6o2QmNSr8PtdrT4mg2kRlE=";
      extension = "dist/extensions/agent-browser/index.js";
    };
    btw = {
      attrName = "pi-btw";
      package = packages.pi-btw or null;
      version = "0.4.1";
      publicName = "pi-btw";
      source = npm "https://registry.npmjs.org/pi-btw/-/pi-btw-0.4.1.tgz" "sha256-CHzdNUd6Jo+ZMF0YvVoOw6piB+VQl4FHTKImwPwU/GI=";
      extension = "extensions/btw.ts";
      skills = [ "skills/btw" ];
    };
    artifacts = {
      attrName = "pi-artifacts";
      package = packages.pi-artifacts or null;
      version = "0.9.0";
      publicName = "@jakeryderv/pi-artifacts";
      source = npm "https://registry.npmjs.org/@jakeryderv/pi-artifacts/-/pi-artifacts-0.9.0.tgz" "sha256-ONiw6EtStwrB6LESSyyKUOjGGWQDbFAvXlOsnKbcWaU=";
      extension = "extensions/nix-bundle.js";
      skills = [ "skills/artifacts-authoring" ];
    };
    insights = {
      attrName = "pi-insights";
      package = packages.pi-insights or null;
      version = "1.0.1";
      publicName = "@ygncode/pi-insights";
      source = npm "https://registry.npmjs.org/@ygncode/pi-insights/-/pi-insights-1.0.1.tgz" "sha256-vMNgilZxwQ5QOxcheTNrcPLQycmXYf5kvkLcLivwWEU=";
      extension = "index.ts";
    };
    subagentura = {
      attrName = "pi-subagentura";
      package = packages.pi-subagentura or null;
      version = "3.0.3";
      publicName = "pi-subagentura";
      source = npm "https://registry.npmjs.org/pi-subagentura/-/pi-subagentura-3.0.3.tgz" "sha256-8nSPMdy4LlJ1BIckjWdqFsSCcDo4uC5R9QqK6XJSVzU=";
      extension = "src/nix-bundle.js";
      skills = [ "skills/ralplan" ];
    };
    litellm = {
      attrName = "pi-provider-litellm";
      package = packages.pi-provider-litellm or null;
      version = "2.0.0";
      publicName = "pi-provider-litellm";
      source = npm "https://registry.npmjs.org/pi-provider-litellm/-/pi-provider-litellm-2.0.0.tgz" "sha256-icmK1hCeZMU9ZINgg9fN0DZL8e/fS2Nbq6oJ4AKgVRU=";
      extension = "dist/index.js";
    };
    router = {
      attrName = "pi-model-router";
      package = packages.pi-model-router or null;
      version = "0.4.4";
      publicName = "@yeliu84/pi-model-router";
      source = npm "https://registry.npmjs.org/@yeliu84/pi-model-router/-/pi-model-router-0.4.4.tgz" "sha256-i5vZzLamyFEbyy+rZas4euSEneB8emIYPR6OoR7oasg=";
      extension = "extensions/index.ts";
    };
    rewind = {
      attrName = "pi-rewind";
      package = packages.pi-rewind or null;
      version = "0.5.0";
      publicName = "pi-rewind";
      source = npm "https://registry.npmjs.org/pi-rewind/-/pi-rewind-0.5.0.tgz" "sha256-1XufSO8QPfqZdmyWaeuwUptyipn8FT0AcH9zgIIvwTo=";
      extension = "src/index.ts";
    };
    scroll = {
      attrName = "pi-scroll";
      package = packages.pi-scroll or null;
      version = "0.1.2";
      publicName = "pi-scroll";
      source = npm "https://registry.npmjs.org/pi-scroll/-/pi-scroll-0.1.2.tgz" "sha256-LfiA6Wz3888uO7ATZ4oiVS8p4+LqUccxfSxQT7tmt3Q=";
      extension = "extensions/scroll.ts";
    };
  };

  supportSources.agent-browser = {
    attrName = "agent-browser";
    version = "0.33.0";
    source = npm "https://registry.npmjs.org/agent-browser/-/agent-browser-0.33.0.tgz" "sha256-Zdcyp6DFLuT1kCXvBX7ztk2GqqdiYrpk9IrBF4iJz4M=";
  };
}
