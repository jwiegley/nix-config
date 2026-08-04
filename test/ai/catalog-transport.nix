{
  lib,
  pkgs,
  src,
}:

let
  rendererPkgs = pkgs // {
    agent-resources = "/catalog-agent-resources";
    pi-gallery = {
      outPath = "/catalog-pi-gallery";
      packages.pi-loop = "/catalog-pi-loop";
    };
  };
  catalog = import "${src}/config/ai/catalog.nix" {
    inherit lib;
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
  clioPiProfile = catalog.profiles.clio-pi;
  clioPiSelected = lib.mapAttrs (_: itemSet: catalog.select clioPiProfile itemSet) catalog.items;
  sharedWorkPiProfile = catalog.profiles.shared-work-pi;
  sharedWorkPiSelected = lib.mapAttrs (
    _: itemSet: catalog.select sharedWorkPiProfile itemSet
  ) catalog.items;
  vpsPiProfile = catalog.profiles.vps-pi;
  vpsPiSelected = lib.mapAttrs (_: itemSet: catalog.select vpsPiProfile itemSet) catalog.items;
  vulcanPiProfile = catalog.profiles.vulcan-pi;
  vulcanPiSelected = lib.mapAttrs (_: itemSet: catalog.select vulcanPiProfile itemSet) catalog.items;
  droidProfile = catalog.profiles.hera-droid;
  droidSelected = lib.mapAttrs (_: itemSet: catalog.select droidProfile itemSet) catalog.items;
  droidRendered =
    (import "${src}/config/ai/renderers/droid.nix" {
      inherit lib;
      pkgs = rendererPkgs;
    })
      {
        profile = droidProfile;
        selected = droidSelected;
        homeDirectory = "/Users/test";
        xdgConfigHome = "/Users/test/.config";
      };
  piRenderer = import "${src}/config/ai/renderers/pi.nix" {
    inherit lib;
    pkgs = rendererPkgs;
  };
  renderPi =
    profile: selectedForProfile:
    piRenderer {
      inherit profile;
      selected = selectedForProfile;
      homeDirectory = "/Users/test";
      xdgConfigHome = "/Users/test/.config";
    };
  heraPiRendered = renderPi piProfile selected;
  clioPiRendered = renderPi clioPiProfile clioPiSelected;
  sharedWorkPiRendered =
    (import "${src}/config/ai/renderers/pi.nix" {
      inherit lib;
      pkgs = rendererPkgs;
    })
      {
        profile = sharedWorkPiProfile;
        selected = sharedWorkPiSelected;
        homeDirectory = "/home/test";
        xdgConfigHome = "/home/test/.config";
      };
  vpsPiRendered =
    (import "${src}/config/ai/renderers/pi.nix" {
      inherit lib;
      pkgs = rendererPkgs;
    })
      {
        profile = vpsPiProfile;
        selected = vpsPiSelected;
        homeDirectory = "/home/test";
        xdgConfigHome = "/home/test/.config";
      };
  vulcanPiRendered =
    (import "${src}/config/ai/renderers/pi.nix" {
      inherit lib;
      pkgs = rendererPkgs;
    })
      {
        profile = vulcanPiProfile;
        selected = vulcanPiSelected;
        homeDirectory = "/home/test";
        xdgConfigHome = "/home/test/.config";
      };
in
assert catalog.validate { };
assert !(builtins.hasAttr "Ref" catalog.items.mcpServers);
assert !(builtins.hasAttr "perplexity" catalog.items.mcpServers);
assert droidRendered.companions == [ ".config/factory/mcp.json" ];
assert !(builtins.hasAttr ".config/factory/nix-managed-settings.json" droidRendered.files);
assert clioPiSelected == selected;
assert builtins.attrNames clioPiRendered.files == builtins.attrNames heraPiRendered.files;
assert clioPiRendered.requiredEnvNames == heraPiRendered.requiredEnvNames;
assert clioPiRendered.mutableMcpGuard == heraPiRendered.mutableMcpGuard;
assert builtins.hasAttr ".config/pi/agent/models.json" sharedWorkPiRendered.files;
assert sharedWorkPiRendered.mutableMcpGuard == heraPiRendered.mutableMcpGuard;
assert builtins.hasAttr ".config/pi/agent/models.json" vpsPiRendered.files;
assert vpsPiRendered.mutableMcpGuard == heraPiRendered.mutableMcpGuard;
assert builtins.hasAttr ".config/pi/agent/models.json" vulcanPiRendered.files;
assert vulcanPiRendered.mutableMcpGuard == heraPiRendered.mutableMcpGuard;
assert builtins.all reject [
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { synthetic = extraPiMcp; });
  })
  (catalog.validate {
    items = withMcpServers (builtins.removeAttrs catalog.items.mcpServers [ "context7" ]);
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
    homeDirectory = "/Users/test";
    xdgConfigHome = "/Users/test/.config";
  })
];
pkgs.runCommand "ai-catalog-transport" { } ''
  cmp ${heraPiRendered.files.".config/pi/agent/keybindings.json".source} \
    ${clioPiRendered.files.".config/pi/agent/keybindings.json".source}
  cmp ${heraPiRendered.files.".config/pi/agent/model-router.json".source} \
    ${clioPiRendered.files.".config/pi/agent/model-router.json".source}
  cmp ${heraPiRendered.files.".config/pi/agent/models.json".source} \
    ${clioPiRendered.files.".config/pi/agent/models.json".source}
  cmp ${heraPiRendered.files.".config/mcp/mcp.json".source} \
    ${clioPiRendered.files.".config/mcp/mcp.json".source}
  touch "$out"
''
