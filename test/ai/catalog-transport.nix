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
  ref = catalog.items.mcpServers.Ref;
  extraPiMcp = ref // {
    name = "synthetic";
    targetPaths = [ "mcp/synthetic" ];
    transport = {
      command = "true";
      args = [ ];
    };
    selectors.profiles = [ "hera-pi" ];
  };
  wrongRefHeader = ref // {
    transport = ref.transport // {
      headers = {
        Authorization.env = "REF_API_KEY";
      };
    };
  };
  wrongRefEnvironment = ref // {
    transport = ref.transport // {
      headers.x-ref-api-key.env = "CONTEXT7_API_KEY";
    };
  };
  missingRefHeader = ref // {
    transport = builtins.removeAttrs ref.transport [ "headers" ];
  };
  multipleRefHeaders = ref // {
    transport = ref.transport // {
      headers = ref.transport.headers // {
        CONTEXT7_API_KEY.env = "CONTEXT7_API_KEY";
      };
    };
  };
  memoryWithHeader = catalog.items.mcpServers.memory-vault // {
    transport = catalog.items.mcpServers.memory-vault.transport // {
      headers.x-ref-api-key.env = "REF_API_KEY";
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
assert builtins.all reject [
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { synthetic = extraPiMcp; });
  })
  (catalog.validate {
    items = withMcpServers (builtins.removeAttrs catalog.items.mcpServers [ "Ref" ]);
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
      providers = builtins.removeAttrs modelData.providers [ "llama-cpp-local" ];
    };
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { Ref = wrongRefHeader; });
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { Ref = wrongRefEnvironment; });
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { Ref = missingRefHeader; });
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { Ref = multipleRefHeaders; });
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
