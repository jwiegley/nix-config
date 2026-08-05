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
  stdioMcp = catalog.items.mcpServers.sequential-thinking;
  extraPiMcp = stdioMcp // {
    name = "synthetic";
    targetPaths = [ "mcp/synthetic" ];
    transport = {
      command = "true";
      args = [ ];
    };
    selectors.profiles = [ "hera-pi" ];
  };
  syntheticHttpMcp = stdioMcp // {
    name = "synthetic-http";
    targetPaths = [ "mcp/synthetic-http" ];
    transport = {
      url = "https://example.invalid/mcp";
    };
    selectors.profiles = [ ];
  };
  unauthorizedHttpHeader = syntheticHttpMcp // {
    transport = syntheticHttpMcp.transport // {
      headers = {
        Authorization.env = "OPENAI_API_KEY";
      };
    };
  };
  mismatchedStdioEnvironment = stdioMcp // {
    transport = stdioMcp.transport // {
      env.SYNTHETIC_TOKEN.env = "OPENAI_API_KEY";
    };
  };
  missingHttpUrl = syntheticHttpMcp // {
    transport = {
      headers = { };
    };
  };
  multipleUnauthorizedHttpHeaders = syntheticHttpMcp // {
    transport = syntheticHttpMcp.transport // {
      headers = {
        Authorization.env = "OPENAI_API_KEY";
        X-Synthetic-Token.env = "OPENAI_API_KEY";
      };
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
  linuxPiRenderings = [
    sharedWorkPiRendered
    vpsPiRendered
    vulcanPiRendered
  ];
in
assert catalog.validate { };
assert catalog.validate {
  items = withMcpServers (catalog.items.mcpServers // { synthetic-http = syntheticHttpMcp; });
};
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
assert builtins.all (
  rendered: !(builtins.hasAttr ".config/pi/agent/model-router.json" rendered.files)
) linuxPiRenderings;
assert builtins.all reject [
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { synthetic = extraPiMcp; });
  })
  (catalog.validate {
    items = withMcpServers (builtins.removeAttrs catalog.items.mcpServers [ "sequential-thinking" ]);
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { synthetic-http = unauthorizedHttpHeader; });
  })
  (catalog.validate {
    items = withMcpServers (
      catalog.items.mcpServers // { sequential-thinking = mismatchedStdioEnvironment; }
    );
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { synthetic-http = missingHttpUrl; });
  })
  (catalog.validate {
    items = withMcpServers (
      catalog.items.mcpServers // { synthetic-http = multipleUnauthorizedHttpHeaders; }
    );
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
  ${pkgs.jq}/bin/jq -e '
    (.providers | keys) == ["hermes", "llama-swap", "omlx", "openai-codex", "openrouter", "router"]
    and .providers.hermes == {
      api: "openai-completions",
      apiKey: "!${pkgs.pass}/bin/pass show api.hermes.com | ${pkgs.coreutils}/bin/head -n 1",
      baseUrl: "https://hermes.vulcan.lan/v1",
      models: [{id: "hermes-agent"}]
    }
    and .providers."llama-swap".modelOverrides."GLM-5.2".contextWindow == 262144
    and .providers.omlx.modelOverrides."DeepSeek-V4-Flash-0731-oQ8e-mtp".contextWindow == 262144
    and .providers."openai-codex".modelOverrides."gpt-5.6-sol".contextWindow == 1050000
    and .providers.openrouter.modelOverrides."z-ai/glm-5.2".contextWindow == 1048576
  ' ${heraPiRendered.files.".config/pi/agent/models.json".source} >/dev/null
  ${lib.concatMapStringsSep "\n" (rendered: ''
    ${pkgs.jq}/bin/jq -e '
      (.providers | keys) == ["openai-codex", "openrouter"]
      and (.providers | has("hermes") | not)
      and .providers."openai-codex".modelOverrides."gpt-5.6-sol".contextWindow == 1050000
      and .providers.openrouter.modelOverrides."z-ai/glm-5.2".contextWindow == 1048576
    ' ${rendered.files.".config/pi/agent/models.json".source} >/dev/null
  '') linuxPiRenderings}
  touch "$out"
''
