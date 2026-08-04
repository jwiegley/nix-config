{
  lib,
  pkgs,
  src,
}:

let
  modelData = import "${src}/config/fleet/models.nix" { };
  rendererPkgs = pkgs // {
    agent-resources = "/catalog-agent-resources";
    pi-gallery = "/catalog-pi-gallery";
  };
  catalog = import "${src}/config/fleet/catalog.nix" {
    inherit lib modelData;
    resources = "/catalog-agent-resources";
  };
  reject = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
  withMcpServers = mcpServers: catalog.items // { inherit mcpServers; };
  context7 = catalog.items.mcpServers.context7;
  extraPiMcp = context7 // {
    name = "synthetic";
    targetPaths = [ "mcp/synthetic" ];
    transport = {
      command = "true";
      args = [ ];
    };
    selectors.profiles = [ "hera-pi" ];
  };
  wrongContext7Header = context7 // {
    transport = context7.transport // {
      headers = {
        Authorization.env = "CONTEXT7_API_KEY";
      };
    };
  };
  wrongContext7Environment = context7 // {
    transport = context7.transport // {
      headers.CONTEXT7_API_KEY.env = "CONTEXT7_TOKEN";
    };
  };
  missingContext7Header = context7 // {
    transport = builtins.removeAttrs context7.transport [ "headers" ];
  };
  multipleContext7Headers = context7 // {
    transport = context7.transport // {
      headers = context7.transport.headers // {
        Authorization.env = "CONTEXT7_API_KEY";
      };
    };
  };
  memoryWithHeader = catalog.items.mcpServers.memory-vault // {
    transport = catalog.items.mcpServers.memory-vault.transport // {
      headers.Authorization.env = "CONTEXT7_API_KEY";
    };
  };
  piProfile = catalog.profiles.hera-pi;
  selected = lib.mapAttrs (_: itemSet: catalog.select piProfile itemSet) catalog.items;
  selectedProviders = catalog.select piProfile modelData.providers;
  selectedModels = lib.filterAttrs (
    _: model:
    builtins.hasAttr model.provider selectedProviders
    && catalog.matches piProfile (model.selectors or { })
  ) modelData.models;
  piRenderer = import "${src}/config/fleet/renderers/pi.nix" {
    inherit lib;
    pkgs = rendererPkgs;
  };
in
assert catalog.validate { };
assert !(builtins.hasAttr "Ref" catalog.items.mcpServers);
assert !(builtins.hasAttr "perplexity" catalog.items.mcpServers);
assert builtins.all reject [
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { synthetic = extraPiMcp; });
  })
  (catalog.validate {
    items = withMcpServers (builtins.removeAttrs catalog.items.mcpServers [ "context7" ]);
  })
  (catalog.validate {
    modelData = modelData // {
      providers = modelData.providers // {
        synthetic = modelData.providers.omlx;
      };
    };
  })
  (catalog.validate {
    modelData = modelData // {
      providers = builtins.removeAttrs modelData.providers [ "llama-swap" ];
    };
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { context7 = wrongContext7Header; });
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { context7 = wrongContext7Environment; });
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { context7 = missingContext7Header; });
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { context7 = multipleContext7Headers; });
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { memory-vault = memoryWithHeader; });
  })
  (piRenderer {
    profile = piProfile // {
      id = "unsupported-pi";
    };
    inherit selected;
    modelData = {
      providers = selectedProviders;
      models = selectedModels;
    };
    homeDirectory = "/Users/test";
    xdgConfigHome = "/Users/test/.config";
  })
];
pkgs.runCommand "ai-catalog-transport" { } "touch $out"
