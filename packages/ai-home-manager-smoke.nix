{
  pkgs,
  src,
  agentResources,
  homeManagerLib,
  inputs,
  testPkgsFor,
}:

let
  inherit (pkgs) lib;

  assetCheckPython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]);
  registryPath = "${src}/config/ai/model-registry.json";
  rawModelRegistry = builtins.fromJSON (builtins.readFile registryPath);
  modelPolicy = import "${src}/config/ai/model-policy.nix";
  loadModelData = args: import "${src}/config/ai/models.nix" args;
  modelData = loadModelData { };
  catalogFor =
    data:
    import "${src}/config/ai/catalog.nix" {
      inherit lib;
      modelData = data;
      resources = "/agent-resources";
    };
  catalog = catalogFor modelData;

  replaceAt =
    index: transform: values:
    lib.imap0 (current: value: if current == index then transform value else value) values;
  withProvider =
    transform:
    rawModelRegistry
    // {
      providers = replaceAt 0 transform rawModelRegistry.providers;
    };
  withModel =
    transform:
    rawModelRegistry
    // {
      models = replaceAt 0 transform rawModelRegistry.models;
    };
  loadRegistry = registry: loadModelData { inherit registry; };
  expectRegistryReject = label: registry: expectReject label (loadRegistry registry);
  expectPolicyReject =
    label: policy:
    expectReject label (loadModelData {
      inherit policy;
      registry = rawModelRegistry;
    });

  alternateRegistry = rawModelRegistry // {
    selections = rawModelRegistry.selections // {
      default = {
        provider = "nvidia";
        model = "qwen/qwen3-coder-480b-a35b-instruct";
      };
      claudeDefault = {
        provider = "positron-anthropic";
        model = "claude-opus-4-7";
      };
      claudeHaiku = {
        provider = "positron-anthropic";
        model = "claude-haiku-4-5-20251001";
      };
      claudeSubagent = {
        provider = "positron-anthropic";
        model = "claude-sonnet-4-6";
      };
    };
  };
  alternateModelData = loadRegistry alternateRegistry;
  alternateCatalog = catalogFor alternateModelData;

  renamedCredentialRegistry = rawModelRegistry // {
    providers = map (
      provider:
      if provider.id == "nvidia" then
        provider
        // {
          apiKey.env = "NVIDIA_RENAMED_API_KEY";
        }
      else
        provider
    ) rawModelRegistry.providers;
  };
  renamedCredentialModelData = loadRegistry renamedCredentialRegistry;
  renamedCredentialCatalog = catalogFor renamedCredentialModelData;

  hostFilterRegistry = rawModelRegistry // {
    models = rawModelRegistry.models ++ [
      {
        provider = "nvidia";
        id = "host-filter-regression-clio";
        displayName = "Host Filter Regression (Clio)";
        maxOutputTokens = 1;
        hosts = [ "clio" ];
      }
      {
        provider = "nvidia";
        id = "host-filter-regression-hera";
        displayName = "Host Filter Regression (Hera)";
        maxOutputTokens = 1;
        hosts = [ "hera" ];
      }
    ];
  };
  hostFilterModelData = loadRegistry hostFilterRegistry;
  hostFilterCatalog = catalogFor hostFilterModelData;

  sortedNames = set: lib.sort builtins.lessThan (builtins.attrNames set);
  expectEqual =
    label: actual: expected:
    if actual == expected then
      true
    else
      throw "${label}: expected ${builtins.toJSON expected}, got ${builtins.toJSON actual}";
  expectReject =
    label: value:
    if (builtins.tryEval (builtins.deepSeq value true)).success then throw label else true;

  selectFor = profileId: itemSet: catalog.select catalog.profiles.${profileId} itemSet;
  selectedNamesFrom = profileId: itemSet: sortedNames (selectFor profileId itemSet);
  selectedNames = profileId: category: selectedNamesFrom profileId catalog.items.${category};
  selectedProviders = profileId: selectFor profileId modelData.providers;
  selectedModelsFor =
    targetCatalog: data: profileId:
    let
      profile = targetCatalog.profiles.${profileId};
      providers = targetCatalog.select profile data.providers;
    in
    lib.filterAttrs (
      _name: model:
      builtins.hasAttr model.provider providers && targetCatalog.matches profile (model.selectors or { })
    ) data.models;
  selectedModels = selectedModelsFor catalog modelData;
  expectedProfileIds = [
    "clio-claude-personal"
    "clio-claude-positron"
    "clio-codex"
    "clio-opencode"
    "hera-claude-personal"
    "hera-claude-positron"
    "hera-codex"
    "hera-droid"
    "hera-opencode"
    "hera-pi"
    "shared-work-claude-positron"
    "shared-work-codex"
    "shared-work-opencode-positron"
    "vps-claude-personal"
    "vulcan-claude-personal"
    "vulcan-opencode"
  ];
  expectedProfileRoots = {
    clio-claude-personal = ".config/claude/personal";
    clio-claude-positron = ".config/claude/positron";
    clio-codex = ".config/codex";
    clio-opencode = ".config/opencode";
    hera-claude-personal = ".config/claude/personal";
    hera-claude-positron = ".config/claude/positron";
    hera-codex = ".config/codex";
    hera-droid = ".config/factory";
    hera-opencode = ".config/opencode";
    hera-pi = ".pi/agent";
    shared-work-claude-positron = ".claude";
    shared-work-codex = ".codex";
    shared-work-opencode-positron = ".config/opencode";
    vps-claude-personal = ".claude";
    vulcan-claude-personal = ".claude";
    vulcan-opencode = ".config/opencode";
  };
  expectedSettingsItem = {
    name = "settings";
    selectors.clients = [ "claude" ];
    targetPaths = [ "settings/settings" ];
    base = {
      env = {
        ANTHROPIC_DEFAULT_HAIKU_MODEL = rawModelRegistry.selections.claudeHaiku.model;
        CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "80";
        CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
        CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
        CLAUDE_CODE_MAX_OUTPUT_TOKENS = "64000";
        CLAUDE_CODE_NO_FLICKER = "1";
        CLAUDE_CODE_SUBAGENT_MODEL = rawModelRegistry.selections.claudeSubagent.model;
        DISABLE_AUTOUPDATER = "1";
        ENABLE_LSP_TOOL = "1";
        ENABLE_TOOL_SEARCH = "1";
        FORCE_AUTOUPDATE_PLUGINS = "1";
        MCP_TIMEOUT = "1800000";
        MCP_TOOL_TIMEOUT = "1800000";
      };
      statusLine.type = "command";
      sandbox = {
        enabled = false;
        autoAllowBashIfSandboxed = true;
        filesystem = {
          allowWrite = [
            "/private/tmp"
            "/var/folders"
          ];
          allowRead = [
            "/private/tmp"
            "/var/folders"
            "/Users/johnw/Products"
          ];
        };
        excludedCommands = [ "gh" ];
      };
      effortLevel = "max";
      showThinkingSummaries = true;
      skipDangerousModePermissionPrompt = true;
      verbose = true;
      preferredNotifChannel = "iterm2_with_bell";
      remoteControlAtStartup = true;
      agentPushNotifEnabled = true;
      model = rawModelRegistry.selections.claudeDefault.model;
      theme = "dark";
    };
    statusLineCommand = {
      executable = "bash";
      rootRelativePath = "statusline-command.sh";
    };
    intentionalDeletions = lib.genAttrs [
      "clio-claude-positron"
      "hera-claude-positron"
      "shared-work-claude-positron"
      "vps-claude-personal"
      "vulcan-claude-personal"
    ] (_: [ "preferredNotifChannel" ]);
  };
  expectedLegacySelectors = {
    filenameTags = {
      personalCommands = [
        "capture"
        "fix-alert"
        "install-service"
        "remove-service"
        "webfix"
      ];
      positronCommands = [
        "cleanup"
        "forge"
        "heavy"
        "retest"
        "retest-categorical"
        "tron-debug"
      ];
    };
    onlyPersonal = [
      "expense-report"
      "fix-integration"
    ];
    droidCommands = [
      "discover-bundles"
      "restack"
    ];
    forge.clients = [ "claude" ];
    retest.audiences = [ "positron" ];
  };
  expectedLegacyTargets = {
    clio-claude-personal = [ "claude-personal" ];
    clio-claude-positron = [ "claude-positron" ];
    clio-codex = [ "codex-clio" ];
    clio-opencode = [ "opencode-clio" ];
    hera-claude-personal = [ "claude-personal" ];
    hera-claude-positron = [ "claude-positron" ];
    hera-codex = [
      "codex-local"
      "codex-hera"
    ];
    hera-droid = [ "droid" ];
    hera-opencode = [ "opencode-hera" ];
    hera-pi = [ "pi-direct" ];
    shared-work-claude-positron = [
      "claude-andoria"
      "claude-andoria-t2"
      "claude-delphi-3bd4"
      "claude-gpu-server"
    ];
    shared-work-codex = [ "codex-andoria" ];
    shared-work-opencode-positron = [
      "opencode-andoria-08"
      "opencode-andoria-t2"
      "opencode-delphi-3bd4"
      "opencode-gpu-server"
    ];
    vps-claude-personal = [ "claude-vps" ];
    vulcan-claude-personal = [ "claude-vulcan" ];
    vulcan-opencode = [ "opencode-vulcan" ];
  };
  expectedUnmanagedExclusions = {
    gptel = [ "gptel-emacs" ];
    git-ai = [ "all git-ai personas and state" ];
    tombstones = [ "anvil-tools" ];
  };

  baseMcp = [
    "Ref"
    "anvil"
    "context-hub"
    "context7"
    "perplexity"
    "sequential-thinking"
  ];
  claudePersonalMcp = [
    "Ref"
    "anvil"
    "context-hub"
    "context7"
    "devonthink"
    "drafts"
    "memory-vault"
    "pal"
    "perplexity"
    "sequential-thinking"
    "stock-trader"
  ];
  claudeMcp = [
    "Ref"
    "anvil"
    "context-hub"
    "context7"
    "pal"
    "perplexity"
    "sequential-thinking"
  ];
  vulcanClaudeMcp = [
    "Ref"
    "anvil"
    "context-hub"
    "context7"
    "drafts-hera"
    "memory-vault"
    "pal"
    "perplexity"
    "sequential-thinking"
  ];
  personalOpenCodeMcp = [
    "Ref"
    "anvil"
    "context-hub"
    "context7"
    "devonthink"
    "memory-vault"
    "perplexity"
    "sequential-thinking"
    "stock-trader"
  ];
  vulcanOpenCodeMcp = [
    "Ref"
    "anvil"
    "context-hub"
    "context7"
    "memory-vault"
    "perplexity"
    "sequential-thinking"
    "stock-trader"
  ];
  droidMcp = claudeMcp;
  claudeHooks = [
    "agent-deck-claude"
    "claude-code"
    "claude-vault"
  ];
  codexHooks = [ "agent-deck-codex" ];
  claudeMarketplaces = [
    "claude-code-plugins"
    "claude-plugins-official"
  ];
  expectedMcpContracts = {
    Ref = {
      transport = {
        url = "https://api.ref.tools/mcp";
        headers.x-ref-api-key.env = "REF_API_KEY";
      };
      overrides = { };
    };
    anvil = {
      transport = {
        command = "anvil-mcp";
        args = [ "--server-id=anvil" ];
      };
      overrides = {
        claude.timeout = 330000;
        codex = {
          startup_timeout_sec = 330;
          tool_timeout_sec = 330;
        };
        opencode.timeout = 330000;
      };
    };
    context-hub = {
      transport = {
        command = "chub-mcp";
        args = [ ];
      };
      overrides.codex.command = "chub-mcp";
    };
    context7 = {
      transport = {
        url = "https://mcp.context7.com/mcp";
        headers.CONTEXT7_API_KEY.env = "CONTEXT7_API_KEY";
      };
      overrides = { };
    };
    devonthink = {
      transport = {
        command = "/Applications/DEVONthink.app/Contents/Library/LoginItems/DEVONthink MCP.app/Contents/MacOS/DEVONthink MCP";
        args = [ "--stdio" ];
      };
      overrides = { };
    };
    drafts = {
      transport = {
        command = "/etc/profiles/per-user/johnw/bin/drafts-mcp-server";
        args = [ ];
      };
      overrides = { };
    };
    drafts-hera = {
      transport = {
        command = "ssh";
        args = [
          "-T"
          "-i"
          "/run/secrets/drafts/hera-ssh-private-key"
          "-o"
          "IdentitiesOnly=yes"
          "-o"
          "BatchMode=yes"
          "-o"
          "StrictHostKeyChecking=yes"
          "-o"
          "ConnectTimeout=10"
          "-o"
          "ServerAliveInterval=30"
          "-o"
          "ServerAliveCountMax=3"
          "johnw@hera.lan"
          "/etc/profiles/per-user/johnw/bin/drafts-mcp-server"
        ];
      };
      overrides = { };
    };
    memory-vault = {
      transport.url = "https://memory-mcp.vulcan.lan/mcp";
      overrides = { };
    };
    pal = {
      transport = {
        command = "pal-mcp-server";
        args = [ ];
        env = {
          ANTHROPIC_API_KEY.env = "ANTHROPIC_API_KEY";
          GEMINI_API_KEY.env = "GEMINI_API_KEY";
          OPENAI_API_KEY.env = "OPENAI_API_KEY";
          DISABLED_TOOLS = "testgen,secaudit,docgen,tracer";
          DEFAULT_MODEL = "auto";
        };
      };
      overrides = { };
    };
    perplexity = {
      transport = {
        command = "uvx";
        args = [ "perplexity-mcp" ];
        env.PERPLEXITY_API_KEY.env = "PERPLEXITY_API_KEY";
      };
      overrides = { };
    };
    sequential-thinking = {
      transport = {
        command = "mcp-server-sequential-thinking";
        args = [ ];
      };
      overrides.codex.command = "mcp-server-sequential-thinking";
    };
    stock-trader = {
      transport = {
        command = "/etc/profiles/per-user/johnw/bin/stock-trader-mcp";
        args = [ ];
      };
      overrides = { };
    };
  };

  profileExpectations = {
    "clio-claude-personal" = {
      mcpServers = claudePersonalMcp;
      hooks = claudeHooks;
      marketplaces = claudeMarketplaces;
      hasDefault = false;
    };
    "clio-claude-positron" = {
      mcpServers = claudeMcp;
      hooks = claudeHooks;
      marketplaces = claudeMarketplaces;
      hasDefault = false;
    };
    "clio-codex" = {
      mcpServers = baseMcp;
      hooks = codexHooks;
      marketplaces = [ ];
      hasDefault = false;
    };
    "clio-opencode" = {
      mcpServers = personalOpenCodeMcp;
      hooks = [ ];
      marketplaces = [ ];
      hasDefault = true;
    };
    "hera-claude-personal" = {
      mcpServers = claudePersonalMcp;
      hooks = claudeHooks;
      marketplaces = claudeMarketplaces;
      hasDefault = false;
    };
    "hera-claude-positron" = {
      mcpServers = claudeMcp;
      hooks = claudeHooks;
      marketplaces = claudeMarketplaces;
      hasDefault = false;
    };
    "hera-codex" = {
      mcpServers = baseMcp;
      hooks = codexHooks;
      marketplaces = [ ];
      hasDefault = false;
    };
    "hera-droid" = {
      mcpServers = droidMcp;
      hooks = [ ];
      marketplaces = [ ];
      hasDefault = false;
    };
    "hera-opencode" = {
      mcpServers = personalOpenCodeMcp;
      hooks = [ ];
      marketplaces = [ ];
      hasDefault = true;
    };
    "hera-pi" = {
      mcpServers = baseMcp;
      hooks = [ ];
      marketplaces = [ ];
      hasDefault = false;
    };
    "shared-work-claude-positron" = {
      mcpServers = claudeMcp;
      hooks = claudeHooks;
      marketplaces = claudeMarketplaces;
      hasDefault = false;
    };
    "shared-work-codex" = {
      mcpServers = baseMcp;
      hooks = codexHooks;
      marketplaces = [ ];
      hasDefault = false;
    };
    "shared-work-opencode-positron" = {
      mcpServers = baseMcp;
      hooks = [ ];
      marketplaces = [ ];
      hasDefault = true;
    };
    "vps-claude-personal" = {
      mcpServers = claudeMcp;
      hooks = claudeHooks;
      marketplaces = claudeMarketplaces;
      hasDefault = false;
    };
    "vulcan-claude-personal" = {
      mcpServers = vulcanClaudeMcp;
      hooks = claudeHooks;
      marketplaces = claudeMarketplaces;
      hasDefault = false;
    };
    "vulcan-opencode" = {
      mcpServers = vulcanOpenCodeMcp;
      hooks = [ ];
      marketplaces = [ ];
      hasDefault = false;
    };
  };

  profileChecks = lib.concatLists (
    lib.mapAttrsToList (profileId: expected: [
      (expectEqual (profileId + " MCP") (selectedNames profileId "mcpServers") expected.mcpServers)
      (expectEqual (profileId + " hooks") (selectedNames profileId "hooks") expected.hooks)
      (expectEqual (
        profileId + " marketplaces"
      ) (selectedNames profileId "marketplaces") expected.marketplaces)
      (expectEqual (profileId + " settings") (selectedNames profileId "settings") (
        lib.optional (catalog.profiles.${profileId}.client == "claude") "settings"
      ))
      (expectEqual (
        profileId + " default"
      ) (builtins.hasAttr profileId modelData.profileDefaults) expected.hasDefault)
    ]) profileExpectations
  );
  selectedUnionFor =
    itemSet:
    lib.sort builtins.lessThan (
      lib.unique (lib.concatMap (profileId: selectedNamesFrom profileId itemSet) expectedProfileIds)
    );
  reachableProviderNames = lib.sort builtins.lessThan (
    lib.unique (lib.concatMap (profileId: sortedNames (selectedProviders profileId)) expectedProfileIds)
  );
  reachableModelNames = lib.sort builtins.lessThan (
    lib.unique (lib.concatMap (profileId: sortedNames (selectedModels profileId)) expectedProfileIds)
  );
  unreachableFixtureItems = {
    unreachable.selectors.excludeProfiles = expectedProfileIds;
  };
  reachabilityChecks =
    map (
      category:
      expectEqual "${category} reaches at least one profile" (selectedUnionFor
        catalog.items.${category}
      ) (sortedNames catalog.items.${category})
    ) (builtins.attrNames catalog.items)
    ++ [
      (expectEqual "reachability oracle detects an excluded item"
        (selectedUnionFor unreachableFixtureItems)
        [ ]
      )
      (expectEqual "every provider reaches at least one profile" reachableProviderNames (
        sortedNames modelData.providers
      ))
      (expectEqual "every model reaches at least one profile" reachableModelNames (
        sortedNames modelData.models
      ))
    ];

  claudeProfileIds = [
    "clio-claude-personal"
    "clio-claude-positron"
    "hera-claude-personal"
    "hera-claude-positron"
    "shared-work-claude-positron"
    "vps-claude-personal"
    "vulcan-claude-personal"
  ];
  codexProfileIds = [
    "clio-codex"
    "hera-codex"
    "shared-work-codex"
  ];
  openCodeProfileIds = [
    "clio-opencode"
    "hera-opencode"
    "shared-work-opencode-positron"
    "vulcan-opencode"
  ];
  droidProfileIds = [ "hera-droid" ];
  piProfileIds = sortedNames (lib.filterAttrs (_: profile: profile.client == "pi") catalog.profiles);
  fixtureHomeDirectory = "/Users/smoke";
  fixtureXdgConfigHome = "${fixtureHomeDirectory}/.config";
  selectedFor =
    profileId: lib.mapAttrs (_category: itemSet: selectFor profileId itemSet) catalog.items;
  selectedModelDataFor =
    profileId:
    {
      providers = selectedProviders profileId;
      models = selectedModels profileId;
    }
    // lib.optionalAttrs (builtins.hasAttr profileId modelData.profileDefaults) {
      default = modelData.profileDefaults.${profileId};
    };

  claudeRendererPath = "${src}/config/ai/renderers/claude.nix";
  codexRendererPath = "${src}/config/ai/renderers/codex.nix";
  openCodeRendererPath = "${src}/config/ai/renderers/opencode.nix";
  droidRendererPath = "${src}/config/ai/renderers/droid.nix";
  piRendererPath = "${src}/config/ai/renderers/pi.nix";
  piPkgs = pkgs // {
    agent-resources = agentResources;
  };
  claudeRenderer =
    if builtins.pathExists claudeRendererPath then
      import claudeRendererPath { inherit lib pkgs; }
    else
      throw "Task 6 RED: config/ai/renderers/claude.nix is missing";
  codexRenderer =
    if builtins.pathExists codexRendererPath then
      import codexRendererPath { inherit lib pkgs; }
    else
      throw "Task 6 RED: config/ai/renderers/codex.nix is missing";
  openCodeRenderer =
    if builtins.pathExists openCodeRendererPath then
      import openCodeRendererPath { inherit lib pkgs; }
    else
      throw "Task 7 RED: config/ai/renderers/opencode.nix is missing";
  hostFilterProbeRenderer = import openCodeRendererPath {
    inherit lib;
    pkgs = pkgs // {
      formats = pkgs.formats // {
        json = _: {
          generate = _name: value: value;
        };
      };
    };
  };
  hostFilterRenderedModels = lib.genAttrs openCodeProfileIds (
    profileId:
    let
      profile = hostFilterCatalog.profiles.${profileId};
      selected = lib.mapAttrs (
        _category: itemSet: hostFilterCatalog.select profile itemSet
      ) hostFilterCatalog.items;
      selectedModelData = {
        providers = hostFilterCatalog.select profile hostFilterModelData.providers;
        models = selectedModelsFor hostFilterCatalog hostFilterModelData profileId;
      };
      render = hostFilterProbeRenderer {
        inherit profile selected;
        modelData = selectedModelData;
        homeDirectory = fixtureHomeDirectory;
        xdgConfigHome = fixtureXdgConfigHome;
      };
      config = render.files."${profile.root}/opencode.json".source;
    in
    builtins.filter (lib.hasPrefix "host-filter-regression-") (
      sortedNames config.provider.nvidia.models
    )
  );
  expectedHostFilterRenderedModels = {
    clio-opencode = [ "host-filter-regression-clio" ];
    hera-opencode = [ "host-filter-regression-hera" ];
    shared-work-opencode-positron = [ ];
    vulcan-opencode = [ ];
  };
  droidRenderer =
    if builtins.pathExists droidRendererPath then
      import droidRendererPath { inherit lib pkgs; }
    else
      throw "Task 7 RED: config/ai/renderers/droid.nix is missing";
  piRenderer =
    if builtins.pathExists piRendererPath then
      import piRendererPath {
        inherit lib;
        pkgs = piPkgs;
      }
    else
      throw "Task 8 RED: config/ai/renderers/pi.nix is missing";

  renderClaude =
    profileId:
    claudeRenderer {
      profile = catalog.profiles.${profileId};
      selected = selectedFor profileId;
      inherit modelData;
      homeDirectory = fixtureHomeDirectory;
      xdgConfigHome = fixtureXdgConfigHome;
    };
  renderCodex =
    profileId:
    codexRenderer {
      profile = catalog.profiles.${profileId};
      selected = selectedFor profileId;
      inherit modelData;
      homeDirectory = fixtureHomeDirectory;
      xdgConfigHome = fixtureXdgConfigHome;
    };
  renderOpenCode =
    profileId:
    openCodeRenderer {
      profile = catalog.profiles.${profileId};
      selected = selectedFor profileId;
      modelData = selectedModelDataFor profileId;
      homeDirectory = fixtureHomeDirectory;
      xdgConfigHome = fixtureXdgConfigHome;
    };
  renamedCredentialProfileId = "clio-opencode";
  renamedCredentialProfile = renamedCredentialCatalog.profiles.${renamedCredentialProfileId};
  renamedCredentialSelected = lib.mapAttrs (
    _category: itemSet: renamedCredentialCatalog.select renamedCredentialProfile itemSet
  ) renamedCredentialCatalog.items;
  renamedCredentialProviders = renamedCredentialCatalog.select renamedCredentialProfile renamedCredentialModelData.providers;
  renamedCredentialModels = lib.filterAttrs (
    _name: model:
    builtins.hasAttr model.provider renamedCredentialProviders
    && renamedCredentialCatalog.matches renamedCredentialProfile (model.selectors or { })
  ) renamedCredentialModelData.models;
  renamedCredentialOpenCode = openCodeRenderer {
    profile = renamedCredentialProfile;
    selected = renamedCredentialSelected;
    modelData = {
      providers = renamedCredentialProviders;
      models = renamedCredentialModels;
      default = renamedCredentialModelData.profileDefaults.${renamedCredentialProfileId};
    };
    homeDirectory = fixtureHomeDirectory;
    xdgConfigHome = fixtureXdgConfigHome;
  };
  renderDroid =
    profileId:
    droidRenderer {
      profile = catalog.profiles.${profileId};
      selected = selectedFor profileId;
      modelData = selectedModelDataFor profileId;
      homeDirectory = fixtureHomeDirectory;
      xdgConfigHome = fixtureXdgConfigHome;
    };
  renderPi =
    profileId:
    piRenderer {
      profile = catalog.profiles.${profileId};
      selected = selectedFor profileId;
      modelData = selectedModelDataFor profileId;
      homeDirectory = fixtureHomeDirectory;
      xdgConfigHome = fixtureXdgConfigHome;
    };
  renderedClaude = lib.genAttrs claudeProfileIds renderClaude;
  renderedCodex = lib.genAttrs codexProfileIds renderCodex;
  renderedOpenCode = lib.genAttrs openCodeProfileIds renderOpenCode;
  renderedDroid = lib.genAttrs droidProfileIds renderDroid;
  renderedPi = lib.genAttrs piProfileIds renderPi;
  claudeCommandPromptCollisionProbe =
    let
      profileId = "vps-claude-personal";
      selected = selectedFor profileId;
    in
    claudeRenderer {
      profile = catalog.profiles.${profileId};
      selected = selected // {
        prompts = selected.prompts // {
          bankruptcy = builtins.head (builtins.attrValues selected.prompts);
        };
      };
      inherit modelData;
      homeDirectory = fixtureHomeDirectory;
      xdgConfigHome = fixtureXdgConfigHome;
    };
  expectedPiRenderKeys = [
    "companions"
    "files"
    "mutableMcpGuard"
    "requiredEnvNames"
  ];
  validatePiRenderShape =
    render:
    if sortedNames render == expectedPiRenderKeys then
      true
    else
      throw "unexpected Pi renderer output shape";
  piUnexpectedOutputProbe = renderedPi.hera-pi // {
    packages = [ ];
  };
  droidMissingProviderTypeProbe =
    let
      data = selectedModelDataFor "hera-droid";
      provider = data.providers.nvidia;
    in
    droidRenderer {
      profile = catalog.profiles.hera-droid;
      selected = selectedFor "hera-droid";
      modelData = data // {
        providers = data.providers // {
          nvidia = provider // {
            droid = builtins.removeAttrs provider.droid [ "providerType" ];
          };
        };
      };
      homeDirectory = fixtureHomeDirectory;
      xdgConfigHome = fixtureXdgConfigHome;
    };
  piUnknownAgentToolProbe = piRenderer {
    profile = catalog.profiles.hera-pi;
    selected = (selectedFor "hera-pi") // {
      agents = (selectFor "hera-pi" catalog.items.agents) // {
        bash-reviewer = catalog.items.agents.bash-reviewer // {
          metadata = catalog.items.agents.bash-reviewer.metadata // {
            tools = "Unknown";
          };
        };
      };
    };
    modelData = selectedModelDataFor "hera-pi";
    homeDirectory = fixtureHomeDirectory;
    xdgConfigHome = fixtureXdgConfigHome;
  };
  piNonstandardXdgProbe = piRenderer {
    profile = catalog.profiles.hera-pi;
    selected = selectedFor "hera-pi";
    modelData = selectedModelDataFor "hera-pi";
    homeDirectory = fixtureHomeDirectory;
    xdgConfigHome = "${fixtureHomeDirectory}/xdg-config";
  };
  piWrongProfileProbe = piRenderer {
    profile = catalog.profiles.vulcan-opencode;
    selected = selectedFor "hera-pi";
    modelData = selectedModelDataFor "hera-pi";
    homeDirectory = fixtureHomeDirectory;
    xdgConfigHome = fixtureXdgConfigHome;
  };
  codexMetadataProbeItem = catalog.items.agents.bash-reviewer // {
    name = "metadata-probe";
    metadata = catalog.items.agents.bash-reviewer.metadata // {
      name = "metadata-probe";
      tools = "must-be-removed";
      future_native_field = "must-be-preserved";
    };
  };
  codexMetadataProbe = codexRenderer {
    profile = catalog.profiles.hera-codex;
    selected = (selectedFor "hera-codex") // {
      agents.metadata-probe = codexMetadataProbeItem;
    };
    inherit modelData;
    homeDirectory = fixtureHomeDirectory;
    xdgConfigHome = fixtureXdgConfigHome;
  };

  mkCommandHook = command: attributes: {
    hooks = [
      (
        {
          type = "command";
          inherit command;
        }
        // attributes
      )
    ];
  };
  expectedAgentDeckClaudeHooks = {
    SessionStart = [ (mkCommandHook "agent-deck hook-handler" { async = true; }) ];
    UserPromptSubmit = [ (mkCommandHook "agent-deck hook-handler" { async = true; }) ];
    Stop = [ (mkCommandHook "agent-deck hook-handler" { }) ];
    PermissionRequest = [ (mkCommandHook "agent-deck hook-handler" { }) ];
    Notification = [
      (
        (mkCommandHook "agent-deck hook-handler" { async = true; })
        // {
          matcher = "permission_prompt|elicitation_dialog";
        }
      )
    ];
    SessionEnd = [ (mkCommandHook "agent-deck hook-handler" { async = true; }) ];
    PreCompact = [ (mkCommandHook "agent-deck hook-handler" { }) ];
  };
  expectedClaudeCodeHooks.Stop = [
    (
      (mkCommandHook "printf '\\a' > /dev/tty 2>/dev/null || true" { })
      // {
        matcher = ".*";
      }
    )
  ];
  expectedClaudeVaultHooks = {
    PreCompact = [ (mkCommandHook "claude-vault import >/dev/null 2>&1" { }) ];
    SessionEnd = [ (mkCommandHook "claude-vault import >/dev/null 2>&1 &" { }) ];
  };
  mergeHookSets = hookSets: lib.zipAttrsWith (_event: bodies: lib.concatLists bodies) hookSets;
  expectedClaudeHooks = mergeHookSets [
    expectedAgentDeckClaudeHooks
    expectedClaudeCodeHooks
    expectedClaudeVaultHooks
  ];
  expectedCodexHooks = {
    SessionStart = [
      (
        (mkCommandHook "agent-deck hook-handler" { })
        // {
          matcher = "startup|resume|clear|compact";
        }
      )
    ];
    UserPromptSubmit = [ (mkCommandHook "agent-deck hook-handler" { }) ];
    Stop = [ (mkCommandHook "agent-deck hook-handler" { }) ];
    PermissionRequest = [
      (
        (mkCommandHook "agent-deck hook-handler" { })
        // {
          matcher = "*";
        }
      )
    ];
    PreCompact = [
      (
        (mkCommandHook "agent-deck hook-handler" { })
        // {
          matcher = "manual|auto";
        }
      )
    ];
  };
  expectedExtraKnownMarketplaces = {
    claude-code-plugins.source = {
      source = "github";
      repo = "anthropics/claude-code";
    };
  };
  expectedEnabledPlugins = {
    "frontend-design@claude-code-plugins" = true;
    "clangd-lsp@claude-plugins-official" = true;
    "pyright-lsp@claude-plugins-official" = true;
    "rust-analyzer-lsp@claude-plugins-official" = true;
    "superpowers@claude-plugins-official" = true;
  };

  isTypedEnv =
    value: builtins.isAttrs value && sortedNames value == [ "env" ] && builtins.isString value.env;
  renderClaudeSecretReferences =
    value:
    if isTypedEnv value then
      "$" + "{" + value.env + "}"
    else if builtins.isAttrs value then
      lib.mapAttrs (_: renderClaudeSecretReferences) value
    else if builtins.isList value then
      map renderClaudeSecretReferences value
    else
      value;
  expectedClaudeMcpServer =
    server:
    let
      transport = renderClaudeSecretReferences server.transport;
      native =
        if transport ? url then
          {
            type = "http";
            inherit (transport) url;
          }
          // lib.optionalAttrs (transport ? headers) { inherit (transport) headers; }
        else
          {
            inherit (transport) command args;
          }
          // lib.optionalAttrs (transport ? env) { inherit (transport) env; };
    in
    lib.recursiveUpdate native (server.overrides.claude or { });
  expectedCodexMcpServer =
    server:
    let
      inherit (server) transport;
      typedEnv = lib.filterAttrs (_: isTypedEnv) (transport.env or { });
      literalEnv = lib.filterAttrs (_: value: !isTypedEnv value) (transport.env or { });
      native =
        if transport ? url then
          {
            inherit (transport) url;
          }
          // lib.optionalAttrs (transport ? headers) {
            env_http_headers = lib.mapAttrs (_: reference: reference.env) transport.headers;
          }
        else
          {
            inherit (transport) command args;
          }
          // lib.optionalAttrs (literalEnv != { }) { env = literalEnv; }
          // lib.optionalAttrs (typedEnv != { }) {
            env_vars = map (name: typedEnv.${name}.env) (sortedNames typedEnv);
          };
    in
    lib.recursiveUpdate native (server.overrides.codex or { });
  expectedClaudeMcp = profileId: {
    mcpServers = lib.mapAttrs (_: expectedClaudeMcpServer) (
      selectFor profileId catalog.items.mcpServers
    );
  };
  expectedCodexMcp =
    profileId: lib.mapAttrs (_: expectedCodexMcpServer) (selectFor profileId catalog.items.mcpServers);

  renderOpenCodeSecretReferences =
    value:
    if isTypedEnv value then
      "{env:${value.env}}"
    else if builtins.isAttrs value then
      lib.mapAttrs (_: renderOpenCodeSecretReferences) value
    else if builtins.isList value then
      map renderOpenCodeSecretReferences value
    else
      value;
  expectedOpenCodeMcpServer =
    server:
    let
      transport = renderOpenCodeSecretReferences server.transport;
      native =
        if transport ? url then
          {
            type = "remote";
            inherit (transport) url;
          }
          // lib.optionalAttrs (transport ? headers) { inherit (transport) headers; }
        else
          {
            type = "local";
            command = [ transport.command ] ++ transport.args;
          }
          // lib.optionalAttrs (transport ? env) { environment = transport.env; };
    in
    lib.recursiveUpdate native (server.overrides.opencode or { });
  expectedOpenCodeMcp =
    profileId:
    lib.mapAttrs (_: expectedOpenCodeMcpServer) (selectFor profileId catalog.items.mcpServers);
  renderOpenCodeCredential =
    credential: if isTypedEnv credential then "{env:${credential.env}}" else credential.nonSecret;

  orderedValues =
    set: lib.sort (left: right: left.sourceOrder < right.sourceOrder) (builtins.attrValues set);
  expectedOpenCodeModel =
    model:
    {
      name = model.displayName;
    }
    // lib.optionalAttrs (model ? contextLimit || model ? outputLimit) {
      limit =
        lib.optionalAttrs (model ? contextLimit) { context = model.contextLimit; }
        // lib.optionalAttrs (model ? outputLimit) { output = model.outputLimit; };
    };
  expectedOpenCodeProvider = profileId: providerName: provider: {
    inherit (provider.opencode) name npm;
    options = {
      apiKey = renderOpenCodeCredential provider.apiKey;
      baseURL = provider.baseUrl;
      inherit (provider.opencode) timeout;
    };
    models = lib.listToAttrs (
      map (model: lib.nameValuePair model.id (expectedOpenCodeModel model)) (
        orderedValues (
          lib.filterAttrs (_: model: model.provider == providerName) (selectedModels profileId)
        )
      )
    );
  };
  expectedOpenCodeConfig =
    profileId:
    let
      default = modelData.profileDefaults.${profileId} or null;
    in
    {
      "$schema" = "https://opencode.ai/config.json";
      disabled_providers = [
        "openai"
        "gemini"
        "anthropic"
      ];
      instructions = [
        "CLAUDE.md"
        "AGENTS.md"
      ];
      mcp = expectedOpenCodeMcp profileId;
      provider = lib.mapAttrs (expectedOpenCodeProvider profileId) (selectedProviders profileId);
    }
    // lib.optionalAttrs (default != null) {
      model = "${default.provider}/${default.model}";
      small_model = "${default.provider}/${default.model}";
    };

  renderDroidSecretReference = value: if isTypedEnv value then "$" + "{" + value.env + "}" else value;
  renderDroidCredential =
    credential:
    if isTypedEnv credential then renderDroidSecretReference credential else credential.nonSecret;
  expectedDroidModel =
    index: model:
    let
      provider = (selectedProviders "hera-droid").${model.provider};
      displayName = "[${provider.displayName}] ${model.displayName}";
    in
    {
      apiKey = renderDroidCredential provider.apiKey;
      inherit (provider) baseUrl;
      inherit displayName index;
      id = "custom:${lib.replaceStrings [ " " ] [ "-" ] displayName}-${toString index}";
      model = model.id;
      noImageSupport = provider.droid.noImageSupport or false;
      provider = provider.droid.providerType;
    }
    // lib.optionalAttrs (model ? maxOutputTokens) {
      inherit (model) maxOutputTokens;
    }
    // lib.optionalAttrs (provider.droid ? extraArgs) {
      inherit (provider.droid) extraArgs;
    }
    // lib.optionalAttrs (provider.droid ? extraHeaders) {
      inherit (provider.droid) extraHeaders;
    };
  expectedDroidSettings = {
    customModels = lib.imap0 expectedDroidModel (orderedValues (selectedModels "hera-droid"));
  };
  expectedDroidMcpServer =
    name: server:
    let
      inherit (server) transport;
      headerNames = sortedNames (transport.headers or { });
      bridge = builtins.elem name [
        "Ref"
        "context7"
      ];
      literalEnv = lib.filterAttrs (_: value: !isTypedEnv value) (transport.env or { });
    in
    if bridge then
      assert builtins.length headerNames == 1;
      let
        headerName = builtins.head headerNames;
      in
      {
        type = "stdio";
        disabled = false;
        command = "agent-http-header-bridge";
        args = [
          transport.url
          headerName
          transport.headers.${headerName}.env
        ];
      }
    else
      {
        type = "stdio";
        disabled = false;
        inherit (transport) command args;
      }
      // lib.optionalAttrs (literalEnv != { }) { env = literalEnv; };
  expectedDroidMcp = {
    mcpServers = lib.mapAttrs expectedDroidMcpServer (selectFor "hera-droid" catalog.items.mcpServers);
  };

  piProviderApis = {
    litellm = "openai-completions";
  };
  renderPiCredential =
    credential:
    if isTypedEnv credential then "$" + "{" + credential.env + "}" else credential.nonSecret;
  expectedPiModel =
    model:
    {
      inherit (model) id;
      name = model.displayName;
      maxTokens = model.outputLimit or model.maxOutputTokens;
    }
    // lib.optionalAttrs (model ? contextLimit) {
      contextWindow = model.contextLimit;
    }
    // lib.optionalAttrs (model.provider == "litellm" && model.id == "positron_openai/gpt-5.6-sol") {
      api = "openai-responses";
      reasoning = true;
      input = [
        "text"
        "image"
      ];
      cost = {
        input = 5;
        output = 30;
        cacheRead = 0.5;
        cacheWrite = 6.25;
        tiers = [
          {
            inputTokensAbove = 272000;
            input = 10;
            output = 45;
            cacheRead = 1;
            cacheWrite = 12.5;
          }
        ];
      };
      thinkingLevelMap = {
        off = "none";
        minimal = null;
        xhigh = "xhigh";
        max = null;
      };
    };
  expectedPiProvider = providerName: provider: {
    api = piProviderApis.${providerName};
    apiKey = renderPiCredential provider.apiKey;
    inherit (provider) baseUrl;
    models = map expectedPiModel (
      orderedValues (
        lib.filterAttrs (_: model: model.provider == providerName) (selectedModels "hera-pi")
      )
    );
  };
  expectedPiModels = {
    providers = lib.mapAttrs expectedPiProvider (selectedProviders "hera-pi");
  };
  renderPiSecretReferences =
    value:
    if isTypedEnv value then
      "$" + "{" + value.env + "}"
    else if builtins.isAttrs value then
      lib.mapAttrs (_: renderPiSecretReferences) value
    else if builtins.isList value then
      map renderPiSecretReferences value
    else
      value;
  expectedPiMcpServer =
    _name: server:
    let
      transport = renderPiSecretReferences server.transport;
    in
    if transport ? url then
      {
        inherit (transport) url headers;
        oauth = false;
      }
    else
      {
        inherit (transport) command args;
      }
      // lib.optionalAttrs (transport ? env) { inherit (transport) env; };
  expectedPiMcp = {
    mcpServers = lib.mapAttrs expectedPiMcpServer (selectFor "hera-pi" catalog.items.mcpServers);
  };

  expectedClaudeSettings =
    profileId:
    let
      profile = catalog.profiles.${profileId};
      deletions = expectedSettingsItem.intentionalDeletions.${profileId} or [ ];
    in
    removeAttrs expectedSettingsItem.base deletions
    // {
      statusLine = {
        type = "command";
        command = "bash ${fixtureHomeDirectory}/${profile.root}/statusline-command.sh";
      };
      hooks = expectedClaudeHooks;
      extraKnownMarketplaces = expectedExtraKnownMarketplaces;
      enabledPlugins = expectedEnabledPlugins;
    };
  expectedCodexManaged = profileId: {
    notify = [
      "agent-deck"
      "codex-notify"
    ];
    mcp_servers = expectedCodexMcp profileId;
  };
  expectedCodexHookFile = {
    hooks = expectedCodexHooks;
  };

  expectedClaudePaths =
    profileId:
    let
      root = catalog.profiles.${profileId}.root;
    in
    lib.sort builtins.lessThan (
      map (name: "${root}/agents/${name}.md") (selectedNames profileId "agents")
      ++ map (name: "${root}/commands/${name}.md") (selectedNames profileId "commands")
      ++ map (name: "${root}/skills/${name}") (selectedNames profileId "skills")
      ++ map (name: "${root}/commands/${name}.md") (selectedNames profileId "prompts")
      ++ [
        "${root}/statusline-command.sh"
        "${root}/nix-managed-settings.json"
        "${root}/nix-managed-mcp.json"
      ]
    );
  expectedCodexPaths =
    profileId:
    let
      root = catalog.profiles.${profileId}.root;
    in
    lib.sort builtins.lessThan (
      map (name: "${root}/agents/${name}.toml") (selectedNames profileId "agents")
      ++ map (name: ".agents/skills/${name}") (selectedNames profileId "skills")
      ++ map (name: ".agents/skills/command-${name}") (selectedNames profileId "commands")
      ++ map (name: ".agents/skills/prompt-${name}") (selectedNames profileId "prompts")
      ++ [
        "${root}/hooks.json"
        "${root}/nix-managed.config.toml"
      ]
    );
  expectedOpenCodePaths =
    profileId:
    let
      root = catalog.profiles.${profileId}.root;
    in
    lib.sort builtins.lessThan (
      map (name: "${root}/agents/${name}.md") (selectedNames profileId "agents")
      ++ map (name: "${root}/commands/${name}.md") (selectedNames profileId "commands")
      ++ map (name: "${root}/skills/${name}") (selectedNames profileId "skills")
      ++ map (name: "${root}/commands/${name}.md") (selectedNames profileId "prompts")
      ++ [ "${root}/opencode.json" ]
    );
  expectedDroidPaths =
    profileId:
    let
      root = catalog.profiles.${profileId}.root;
    in
    lib.sort builtins.lessThan (
      map (name: "${root}/droids/${name}.md") (selectedNames profileId "agents")
      ++ map (name: "${root}/skills/${name}") (selectedNames profileId "skills")
      ++ map (name: "${root}/skills/${name}") (selectedNames profileId "commands")
      ++ map (name: "${root}/skills/${name}") (selectedNames profileId "prompts")
      ++ [
        "${root}/mcp.json"
        "${root}/nix-managed-settings.json"
      ]
    );
  piExtensionSources = {
    pi-mcp-adapter = "${piPkgs.agent-resources}/share/agent-resources/pi-extensions/pi-mcp-adapter";
    pi-quiet = "${piPkgs.agent-resources}/share/agent-resources/pi-extensions/pi-quiet";
    pi-subagent = "${piPkgs.agent-resources}/share/agent-resources/pi-extensions/pi-subagent";
  };
  expectedPiPaths =
    profileId:
    let
      root = catalog.profiles.${profileId}.root;
    in
    lib.sort builtins.lessThan (
      map (name: "${root}/agents/${name}.md") (selectedNames profileId "agents")
      ++ map (name: "${root}/prompts/${name}.md") (selectedNames profileId "commands")
      ++ map (name: "${root}/prompts/${name}.md") (selectedNames profileId "prompts")
      ++ [
        ".config/mcp/mcp.json"
        "${root}/extensions/pi-mcp-adapter"
        "${root}/extensions/pi-quiet"
        "${root}/extensions/pi-subagent"
        "${root}/models.json"
      ]
    );
  piSharedSkillPaths = lib.sort builtins.lessThan (
    map (name: ".agents/skills/${name}") (selectedNames "hera-codex" "skills")
    ++ map (name: ".agents/skills/command-${name}") (selectedNames "hera-codex" "commands")
    ++ map (name: ".agents/skills/prompt-${name}") (selectedNames "hera-codex" "prompts")
  );
  forbiddenClaudePaths =
    profileId:
    let
      root = catalog.profiles.${profileId}.root;
    in
    [
      root
      "${root}/settings.json"
      "${root}/.claude.json"
      "${root}/auth.json"
      "${root}/history.jsonl"
    ];
  forbiddenCodexPaths =
    profileId:
    let
      root = catalog.profiles.${profileId}.root;
    in
    [
      root
      ".agents"
      ".agents/skills"
      "${root}/config.toml"
      "${root}/auth.json"
      "${root}/history.jsonl"
    ];
  forbiddenOpenCodePaths =
    profileId:
    let
      root = catalog.profiles.${profileId}.root;
    in
    [
      root
      "${root}/auth.json"
      "${root}/bun.lock"
      "${root}/node_modules"
      "${root}/package.json"
      ".cache/opencode"
      ".local/share/opencode"
      ".local/state/opencode"
    ];
  forbiddenDroidPaths =
    profileId:
    let
      root = catalog.profiles.${profileId}.root;
    in
    [
      root
      "${root}/settings.json"
      "${root}/auth.json"
      "${root}/history.jsonl"
      "${root}/sessions"
    ];
  forbiddenPiPaths =
    profileId:
    let
      root = catalog.profiles.${profileId}.root;
    in
    [
      root
      ".agents"
      ".agents/skills"
      ".mcp.json"
      ".pi/mcp.json"
      "${root}/auth.json"
      "${root}/git"
      "${root}/mcp-cache.json"
      "${root}/mcp-npx-cache.json"
      "${root}/mcp-oauth"
      "${root}/mcp-onboarding.json"
      "${root}/mcp.json"
      "${root}/models-store.json"
      "${root}/npm"
      "${root}/sessions"
      "${root}/settings.json"
      "${root}/skills"
    ];

  documentSource =
    label: file:
    file.source or (
      if file ? text then
        { inlineText = file.text; }
      else
        throw "rendered file ${label} has neither source nor text"
    );
  claudeMarkdown =
    item:
    if item.metadata == { } then
      builtins.readFile item.source
    else
      "---\n${builtins.toJSON item.metadata}\n---\n${builtins.readFile item.source}";
  codexAgentObject =
    item:
    removeAttrs item.metadata [ "tools" ]
    // {
      developer_instructions = builtins.readFile item.source;
    };
  codexProjectionMetadata = prefix: name: metadata: {
    name = "${prefix}-${name}";
    description = metadata.description or "Promptdeploy ${prefix} '${name}'.";
  };
  codexProjectionText =
    kind: name: metadata: source:
    "---\n${builtins.toJSON metadata}\n---\n"
    + "Use this skill for the promptdeploy ${kind} '${name}'.\n\n"
    + "Treat the user's current request as the arguments for the prompt below. "
    + "If the prompt contains `$ARGUMENTS`, interpret it as those arguments.\n\n"
    + "Prompt:\n\n"
    + builtins.readFile source;
  openCodeBuiltinTools = [
    "bash"
    "edit"
    "glob"
    "grep"
    "list"
    "lsp"
    "patch"
    "question"
    "read"
    "skill"
    "task"
    "todoread"
    "todowrite"
    "webfetch"
    "websearch"
    "write"
  ];
  normalizeOpenCodeTool =
    tool:
    let
      call = builtins.match "([^()]*)[(].*" tool;
      bare = if call == null then tool else builtins.head call;
      withoutMcp = lib.removePrefix "mcp__" bare;
    in
    lib.toLower (lib.replaceStrings [ "__" ] [ "_" ] withoutMcp);
  expectedOpenCodeAgentMetadata =
    item:
    let
      declared =
        if !(item.metadata ? tools) then
          [ ]
        else if builtins.isList item.metadata.tools then
          item.metadata.tools
        else
          lib.splitString ", " item.metadata.tools;
      enabled = map normalizeOpenCodeTool declared;
      toolNames = lib.unique (lib.sort builtins.lessThan (openCodeBuiltinTools ++ enabled));
    in
    removeAttrs item.metadata [ "tools" ]
    // lib.optionalAttrs (item.metadata ? tools) {
      tools = lib.genAttrs toolNames (name: builtins.elem name enabled);
    };
  normalizePiAgentTools =
    tools:
    if tools == "Read, Grep, Glob, Bash" then
      "read,grep,find,bash"
    else if
      tools == [
        "mcp__perplexity__perplexity_search_web"
        "WebFetch"
      ]
    then
      "mcp"
    else
      throw "unsupported Pi agent tools: ${builtins.toJSON tools}";
  expectedPiAgentMetadata =
    item:
    removeAttrs item.metadata [ "tools" ]
    // lib.optionalAttrs (item.metadata ? tools) {
      tools = normalizePiAgentTools item.metadata.tools;
    };
  expectedPiCommandMetadata =
    item:
    lib.optionalAttrs (item.metadata ? description) {
      inherit (item.metadata) description;
    }
    //
      lib.optionalAttrs
        (builtins.hasAttr "argument-hint" item.metadata && builtins.isString item.metadata."argument-hint")
        {
          inherit (item.metadata) argument-hint;
        };

  claudeDocumentRecords = lib.concatMap (
    profileId:
    let
      profile = catalog.profiles.${profileId};
      render = renderedClaude.${profileId};
      file = path: render.files.${path};
    in
    [
      {
        kind = "json";
        label = "${profileId} settings";
        path = documentSource "${profileId}-settings.json" (
          file "${profile.root}/nix-managed-settings.json"
        );
        expected = expectedClaudeSettings profileId;
        forbidden = [
          "_source"
          "mcpServers"
          "intentionalDeletions"
          "targetPaths"
        ];
      }
      {
        kind = "json";
        label = "${profileId} MCP";
        path = documentSource "${profileId}-mcp.json" (file "${profile.root}/nix-managed-mcp.json");
        expected = expectedClaudeMcp profileId;
        forbidden = [
          "{env:"
          "$env:"
          "?apiKey="
        ];
      }
      {
        kind = "text";
        label = "${profileId} statusline";
        path = documentSource "${profileId}-statusline.sh" (file "${profile.root}/statusline-command.sh");
        expectedText = builtins.readFile "${src}/config/ai/statusline-command.sh";
      }
    ]
    ++ lib.mapAttrsToList (name: item: {
      kind = "text";
      label = "${profileId} agent ${name}";
      path = documentSource "${profileId}-agent-${name}.md" (file "${profile.root}/agents/${name}.md");
      expectedText = claudeMarkdown item;
    }) (selectFor profileId catalog.items.agents)
    ++ lib.mapAttrsToList (name: item: {
      kind = "text";
      label = "${profileId} command ${name}";
      path = documentSource "${profileId}-command-${name}.md" (
        file "${profile.root}/commands/${name}.md"
      );
      expectedText = claudeMarkdown item;
    }) (selectFor profileId catalog.items.commands)
    ++ lib.mapAttrsToList (name: item: {
      kind = "text";
      label = "${profileId} prompt ${name}";
      path = documentSource "${profileId}-prompt-${name}.md" (file "${profile.root}/commands/${name}.md");
      expectedText = builtins.readFile item.source;
    }) (selectFor profileId catalog.items.prompts)
  ) claudeProfileIds;

  codexDocumentRecords = lib.concatMap (
    profileId:
    let
      profile = catalog.profiles.${profileId};
      render = renderedCodex.${profileId};
      file = path: render.files.${path};
    in
    [
      {
        kind = "toml";
        label = "${profileId} managed config";
        path = documentSource "${profileId}-managed.toml" (file "${profile.root}/nix-managed.config.toml");
        expected = expectedCodexManaged profileId;
        forbidden = [
          ("$" + "{")
          "{env:"
          "$env:"
          "?apiKey="
        ];
      }
      {
        kind = "json";
        label = "${profileId} hooks";
        path = documentSource "${profileId}-hooks.json" (file "${profile.root}/hooks.json");
        expected = expectedCodexHookFile;
      }
    ]
    ++ lib.mapAttrsToList (name: item: {
      kind = "toml";
      label = "${profileId} agent ${name}";
      path = documentSource "${profileId}-agent-${name}.toml" (
        file "${profile.root}/agents/${name}.toml"
      );
      expected = codexAgentObject item;
    }) (selectFor profileId catalog.items.agents)
    ++ lib.mapAttrsToList (name: item: {
      kind = "text";
      label = "${profileId} command projection ${name}";
      sourceDirectory = (file ".agents/skills/command-${name}").source;
      path = "${(file ".agents/skills/command-${name}").source}/SKILL.md";
      expectedText = codexProjectionText "command" name (codexProjectionMetadata "command" name
        item.metadata
      ) item.source;
    }) (selectFor profileId catalog.items.commands)
    ++ lib.mapAttrsToList (name: item: {
      kind = "text";
      label = "${profileId} prompt projection ${name}";
      sourceDirectory = (file ".agents/skills/prompt-${name}").source;
      path = "${(file ".agents/skills/prompt-${name}").source}/SKILL.md";
      expectedText = codexProjectionText "prompt" name {
        name = "prompt-${name}";
        description = "Promptdeploy rendered prompt '${name}'.";
      } item.source;
    }) (selectFor profileId catalog.items.prompts)
  ) codexProfileIds;
  codexMetadataProbeRecord = {
    kind = "toml";
    label = "Codex future metadata preservation";
    path =
      documentSource "codex-metadata-probe.toml"
        codexMetadataProbe.files.".config/codex/agents/metadata-probe.toml";
    expected = codexAgentObject codexMetadataProbeItem;
  };
  openCodeDocumentRecords = lib.concatMap (
    profileId:
    let
      profile = catalog.profiles.${profileId};
      render = renderedOpenCode.${profileId};
      file = path: render.files.${path};
    in
    [
      {
        kind = "json";
        label = "${profileId} complete config";
        path = documentSource "${profileId}-opencode.json" (file "${profile.root}/opencode.json");
        expected = expectedOpenCodeConfig profileId;
        forbidden = [
          ("$" + "{")
          "$env:"
          "?apiKey="
        ];
      }
    ]
    ++ lib.mapAttrsToList (name: item: {
      kind = "frontmatter";
      label = "${profileId} agent ${name}";
      path = documentSource "${profileId}-agent-${name}.md" (file "${profile.root}/agents/${name}.md");
      expectedMetadata = expectedOpenCodeAgentMetadata item;
      expectedBody = builtins.readFile item.source;
    }) (selectFor profileId catalog.items.agents)
    ++ lib.mapAttrsToList (name: item: {
      kind = "frontmatter";
      label = "${profileId} command ${name}";
      path = documentSource "${profileId}-command-${name}.md" (
        file "${profile.root}/commands/${name}.md"
      );
      expectedMetadata = item.metadata;
      expectedBody = builtins.readFile item.source;
    }) (selectFor profileId catalog.items.commands)
    ++ lib.mapAttrsToList (name: item: {
      kind = "text";
      label = "${profileId} prompt ${name}";
      path = documentSource "${profileId}-prompt-${name}.md" (file "${profile.root}/commands/${name}.md");
      expectedText = builtins.readFile item.source;
    }) (selectFor profileId catalog.items.prompts)
  ) openCodeProfileIds;
  droidDocumentRecords = lib.concatMap (
    profileId:
    let
      profile = catalog.profiles.${profileId};
      render = renderedDroid.${profileId};
      file = path: render.files.${path};
    in
    [
      {
        kind = "json";
        label = "${profileId} model settings";
        path = documentSource "${profileId}-settings.json" (
          file "${profile.root}/nix-managed-settings.json"
        );
        expected = expectedDroidSettings;
        forbidden = [
          "defaultModel"
          "?apiKey="
        ];
      }
      {
        kind = "json";
        label = "${profileId} MCP";
        path = documentSource "${profileId}-mcp.json" (file "${profile.root}/mcp.json");
        expected = expectedDroidMcp;
        forbidden = [
          "{env:"
          "anvil-tools"
          "?apiKey="
        ];
      }
    ]
    ++ lib.mapAttrsToList (name: item: {
      kind = "frontmatter";
      label = "${profileId} droid ${name}";
      path = documentSource "${profileId}-droid-${name}.md" (file "${profile.root}/droids/${name}.md");
      expectedMetadata = item.metadata;
      expectedBody = builtins.readFile item.source;
    }) (selectFor profileId catalog.items.agents)
    ++ lib.mapAttrsToList (name: item: {
      kind = "frontmatter";
      label = "${profileId} command projection ${name}";
      sourceDirectory = (file "${profile.root}/skills/${name}").source;
      path = "${(file "${profile.root}/skills/${name}").source}/SKILL.md";
      expectedMetadata = item.metadata;
      expectedBody = builtins.readFile item.source;
    }) (selectFor profileId catalog.items.commands)
    ++ lib.mapAttrsToList (name: item: {
      kind = "text";
      label = "${profileId} prompt projection ${name}";
      sourceDirectory = (file "${profile.root}/skills/${name}").source;
      path = "${(file "${profile.root}/skills/${name}").source}/SKILL.md";
      expectedText = builtins.readFile item.source;
    }) (selectFor profileId catalog.items.prompts)
  ) droidProfileIds;
  piDocumentRecords = lib.concatMap (
    profileId:
    let
      profile = catalog.profiles.${profileId};
      render = renderedPi.${profileId};
      file = path: render.files.${path};
    in
    [
      {
        kind = "json";
        label = "${profileId} models";
        path = documentSource "${profileId}-models.json" (file "${profile.root}/models.json");
        expected = expectedPiModels;
        forbidden = [
          "{env:"
          "$env:"
          "llama-cpp-remote"
          "?apiKey="
        ];
      }
      {
        kind = "json";
        label = "${profileId} MCP";
        path = documentSource "${profileId}-mcp.json" (file ".config/mcp/mcp.json");
        expected = expectedPiMcp;
        forbidden = [
          "anvil-tools"
          "devonthink"
          "drafts"
          "imports"
          "memory-vault"
          "pal"
          "stock-trader"
          "?apiKey="
        ];
      }
    ]
    ++ lib.mapAttrsToList (name: item: {
      kind = "frontmatter";
      label = "${profileId} agent ${name}";
      path = documentSource "${profileId}-agent-${name}.md" (file "${profile.root}/agents/${name}.md");
      expectedMetadata = expectedPiAgentMetadata item;
      expectedBody = builtins.readFile item.source;
    }) (selectFor profileId catalog.items.agents)
    ++ lib.mapAttrsToList (name: item: {
      kind = "frontmatter";
      label = "${profileId} command ${name}";
      path = documentSource "${profileId}-command-${name}.md" (file "${profile.root}/prompts/${name}.md");
      expectedMetadata = expectedPiCommandMetadata item;
      expectedBody = builtins.readFile item.source;
    }) (selectFor profileId catalog.items.commands)
    ++ lib.mapAttrsToList (name: item: {
      kind = "text";
      label = "${profileId} prompt ${name}";
      path = documentSource "${profileId}-prompt-${name}.md" (file "${profile.root}/prompts/${name}.md");
      expectedText = builtins.readFile item.source;
    }) (selectFor profileId catalog.items.prompts)
  ) piProfileIds;
  rendererDocumentManifest = pkgs.writeText "ai-renderer-document-fixtures.json" (
    builtins.toJSON (
      claudeDocumentRecords
      ++ codexDocumentRecords
      ++ openCodeDocumentRecords
      ++ droidDocumentRecords
      ++ piDocumentRecords
      ++ [
        codexMetadataProbeRecord
        {
          kind = "json";
          label = "renamed provider credential reaches OpenCode";
          path = renamedCredentialOpenCode.files."${renamedCredentialProfile.root}/opencode.json".source;
          expected = lib.recursiveUpdate (expectedOpenCodeConfig renamedCredentialProfileId) {
            provider.nvidia.options.apiKey = "{env:NVIDIA_RENAMED_API_KEY}";
          };
        }
      ]
    )
  );
  openCodeRequiredEnvNames = {
    clio-opencode = [
      "CONTEXT7_API_KEY"
      "LITELLM_API_KEY"
      "NVIDIA_API_KEY"
      "PERPLEXITY_API_KEY"
      "REF_API_KEY"
    ];
    hera-opencode = openCodeRequiredEnvNames.clio-opencode;
    shared-work-opencode-positron = openCodeRequiredEnvNames.clio-opencode;
    vulcan-opencode = [
      "CONTEXT7_API_KEY"
      "NVIDIA_API_KEY"
      "PERPLEXITY_API_KEY"
      "REF_API_KEY"
    ];
  };
  piRequiredEnvNames = [
    "CONTEXT7_API_KEY"
    "LITELLM_API_KEY"
    "PERPLEXITY_API_KEY"
    "REF_API_KEY"
  ];

  rendererChecks =
    lib.concatMap (
      profileId:
      let
        profile = catalog.profiles.${profileId};
        render = renderedClaude.${profileId};
        paths = sortedNames render.files;
      in
      [
        (expectEqual "${profileId} selected resource paths" paths (expectedClaudePaths profileId))
        (expectEqual "${profileId} companions" render.companions [
          "${profile.root}/nix-managed-settings.json"
          "${profile.root}/nix-managed-mcp.json"
        ])
        (expectEqual "${profileId} required environment" render.requiredEnvNames [
          "ANTHROPIC_API_KEY"
          "CONTEXT7_API_KEY"
          "GEMINI_API_KEY"
          "OPENAI_API_KEY"
          "PERPLEXITY_API_KEY"
          "REF_API_KEY"
        ])
        (expectEqual "${profileId} mutable roots remain unmanaged" (lib.intersectLists paths (
          forbiddenClaudePaths profileId
        )) [ ])
      ]
      ++ lib.mapAttrsToList (
        name: item:
        (expectEqual "${profileId} skill source ${name}"
          render.files."${profile.root}/skills/${name}".source
          item.source
        )
      ) (selectFor profileId catalog.items.skills)
    ) claudeProfileIds
    ++ lib.concatMap (
      profileId:
      let
        profile = catalog.profiles.${profileId};
        render = renderedCodex.${profileId};
        paths = sortedNames render.files;
      in
      [
        (expectEqual "${profileId} selected resource paths" paths (expectedCodexPaths profileId))
        (expectEqual "${profileId} companions" render.companions [
          "${profile.root}/hooks.json"
          "${profile.root}/nix-managed.config.toml"
        ])
        (expectEqual "${profileId} required environment" render.requiredEnvNames [
          "CONTEXT7_API_KEY"
          "PERPLEXITY_API_KEY"
          "REF_API_KEY"
        ])
        (expectEqual "${profileId} mutable roots remain unmanaged" (lib.intersectLists paths (
          forbiddenCodexPaths profileId
        )) [ ])
      ]
      ++ lib.mapAttrsToList (
        name: item:
        (expectEqual "${profileId} skill source ${name}" render.files.".agents/skills/${name}".source
          item.source
        )
      ) (selectFor profileId catalog.items.skills)
    ) codexProfileIds
    ++ lib.concatMap (
      profileId:
      let
        profile = catalog.profiles.${profileId};
        render = renderedOpenCode.${profileId};
        paths = sortedNames render.files;
      in
      [
        (expectEqual "${profileId} selected resource paths" paths (expectedOpenCodePaths profileId))
        (expectEqual "${profileId} companions" render.companions [ ])
        (expectEqual "${profileId} required environment" render.requiredEnvNames
          openCodeRequiredEnvNames.${profileId}
        )
        (expectEqual "${profileId} mutable roots remain unmanaged" (lib.intersectLists paths (
          forbiddenOpenCodePaths profileId
        )) [ ])
      ]
      ++ lib.mapAttrsToList (
        name: item:
        (expectEqual "${profileId} skill source ${name}"
          render.files."${profile.root}/skills/${name}".source
          item.source
        )
      ) (selectFor profileId catalog.items.skills)
    ) openCodeProfileIds
    ++ lib.concatMap (
      profileId:
      let
        profile = catalog.profiles.${profileId};
        render = renderedDroid.${profileId};
        paths = sortedNames render.files;
      in
      [
        (expectEqual "${profileId} selected resource paths" paths (expectedDroidPaths profileId))
        (expectReject "Droid missing provider type accepted" droidMissingProviderTypeProbe.companions)
        (expectEqual "${profileId} companions" render.companions [
          "${profile.root}/nix-managed-settings.json"
          "${profile.root}/mcp.json"
        ])
        (expectEqual "${profileId} required environment" render.requiredEnvNames [
          "ANTHROPIC_API_KEY"
          "CONTEXT7_API_KEY"
          "GEMINI_API_KEY"
          "LITELLM_API_KEY"
          "NVIDIA_API_KEY"
          "OPENAI_API_KEY"
          "PERPLEXITY_API_KEY"
          "REF_API_KEY"
        ])
        (expectEqual "${profileId} mutable roots remain unmanaged" (lib.intersectLists paths (
          forbiddenDroidPaths profileId
        )) [ ])
        (expectEqual "${profileId} settings omit default"
          (builtins.hasAttr "defaultModel" expectedDroidSettings)
          false
        )
        (expectEqual "${profileId} semantic MCP oracle" (builtins.hashString "sha256" (
          builtins.toJSON expectedDroidMcp
        )) "1c67464e875534e546c17d017253563f4875b871d827a059826a429e3eff4e29")
        (expectEqual "${profileId} MCP set" (sortedNames expectedDroidMcp.mcpServers) [
          "Ref"
          "anvil"
          "context-hub"
          "context7"
          "pal"
          "perplexity"
          "sequential-thinking"
        ])
      ]
      ++ lib.mapAttrsToList (
        name: item:
        (expectEqual "${profileId} skill source ${name}"
          render.files."${profile.root}/skills/${name}".source
          item.source
        )
      ) (selectFor profileId catalog.items.skills)
    ) droidProfileIds
    ++ lib.concatMap (
      profileId:
      let
        profile = catalog.profiles.${profileId};
        render = renderedPi.${profileId};
        paths = sortedNames render.files;
        piOwnedSkillPaths = builtins.filter (
          path: lib.hasPrefix "${profile.root}/skills/" path || lib.hasPrefix ".agents/skills/" path
        ) paths;
      in
      [
        (expectEqual "${profileId} selected resource paths" paths (expectedPiPaths profileId))
        (expectEqual "${profileId} exact renderer output shape" (validatePiRenderShape render) true)
        (expectReject "Pi unexpected renderer output accepted" (
          validatePiRenderShape piUnexpectedOutputProbe
        ))
        (expectEqual "${profileId} companions" render.companions [ ])
        (expectEqual "${profileId} required environment" render.requiredEnvNames piRequiredEnvNames)
        (expectEqual "${profileId} mutable MCP guard" render.mutableMcpGuard {
          path = ".pi/agent/mcp.json";
          forbiddenKeys = [
            "mcpServers"
            "imports"
          ];
        })
        (expectEqual "${profileId} mutable roots remain unmanaged" (lib.intersectLists paths (
          forbiddenPiPaths profileId
        )) [ ])
        (expectEqual "${profileId} owns no skill leaves" piOwnedSkillPaths [ ])
        (expectReject "Pi unknown agent tool accepted"
          piUnknownAgentToolProbe.files.".pi/agent/agents/bash-reviewer.md".text
        )
        (expectReject "Pi nonstandard XDG config home accepted" piNonstandardXdgProbe.companions)
        (expectReject "Pi non-Hera/non-Pi profile accepted" piWrongProfileProbe.companions)
        (expectEqual "${profileId} provider set" (sortedNames expectedPiModels.providers) [
          "litellm"
        ])
        (expectEqual "${profileId} selected models use only LiteLLM" (builtins.all (
          model: model.provider == "litellm"
        ) (builtins.attrValues (selectedModels profileId))) true)
        (expectEqual "${profileId} MCP set" (sortedNames expectedPiMcp.mcpServers) [
          "Ref"
          "anvil"
          "context-hub"
          "context7"
          "perplexity"
          "sequential-thinking"
        ])
        (expectEqual "${profileId} semantic MCP oracle" (builtins.hashString "sha256" (
          builtins.toJSON expectedPiMcp
        )) "03e18dfc387f1c07a8550ea3c997160e16c054819e4dc35aeeaa78c2ab5d9fdf")
        (expectEqual "${profileId} MCP extension link"
          render.files."${profile.root}/extensions/pi-mcp-adapter"
          { source = piExtensionSources.pi-mcp-adapter; }
        )
        (expectEqual "${profileId} subagent extension link"
          render.files."${profile.root}/extensions/pi-subagent"
          { source = piExtensionSources.pi-subagent; }
        )
        (expectEqual "${profileId} quiet extension link" render.files."${profile.root}/extensions/pi-quiet"
          { source = piExtensionSources.pi-quiet; }
        )
        (expectEqual "${profileId} exact extension names" (sortedNames piExtensionSources) [
          "pi-mcp-adapter"
          "pi-quiet"
          "pi-subagent"
        ])
        (expectEqual "${profileId} extension sources are unique" (builtins.length (
          lib.unique (builtins.attrValues piExtensionSources)
        )) (builtins.length (builtins.attrValues piExtensionSources)))
        (expectEqual "${profileId} incompatible compaction aliases remain inactive" (builtins.filter (
          path: lib.hasInfix "pi-openai-server-compaction" path
        ) paths) [ ])
        (expectEqual "${profileId} shared skills are Hera Codex-owned" (builtins.filter (
          path: lib.hasPrefix ".agents/skills/" path
        ) (sortedNames renderedCodex.hera-codex.files)) piSharedSkillPaths)
      ]
    ) piProfileIds
    ++ [
      (expectReject "Claude command-prompt target collision accepted" (
        builtins.attrNames claudeCommandPromptCollisionProbe.files
      ))
    ];

  candidate = {
    inherit (catalog) profiles items;
    inherit modelData;
  };
  validateWithItems = candidateItems: catalog.validate (candidate // { items = candidateItems; });
  validateWithProfiles =
    candidateProfiles: catalog.validate (candidate // { profiles = candidateProfiles; });
  validateWithModels =
    candidateModels: catalog.validate (candidate // { modelData = candidateModels; });

  withAgentSelector =
    selectors:
    catalog.items
    // {
      agents = catalog.items.agents // {
        bash-reviewer = catalog.items.agents.bash-reviewer // {
          inherit selectors;
        };
      };
    };
  duplicateSkillItems = catalog.items // {
    skills = catalog.items.skills // {
      duplicate-anvil = catalog.items.skills.anvil // {
        name = "anvil";
      };
    };
  };
  unsafeItemNameItems = catalog.items // {
    skills = removeAttrs catalog.items.skills [ "anvil" ] // {
      "../../.ssh" = catalog.items.skills.anvil // {
        name = "../../.ssh";
      };
    };
  };
  duplicatePathItems = catalog.items // {
    skills = catalog.items.skills // {
      path-one = catalog.items.skills.anvil // {
        name = "path-one";
        targetPaths = [ ".duplicate/path" ];
      };
      path-two = catalog.items.skills.caveman // {
        name = "path-two";
        targetPaths = [ ".duplicate/path" ];
      };
    };
  };
  badOverrideItems = catalog.items // {
    mcpServers = catalog.items.mcpServers // {
      anvil = lib.recursiveUpdate catalog.items.mcpServers.anvil {
        overrides.claude.unsupported = true;
      };
    };
  };
  badOverrideClientItems = catalog.items // {
    mcpServers = catalog.items.mcpServers // {
      anvil = lib.recursiveUpdate catalog.items.mcpServers.anvil {
        overrides.unknown.timeout = 1;
      };
    };
  };
  multipleTransportItems = catalog.items // {
    mcpServers = catalog.items.mcpServers // {
      Ref = lib.recursiveUpdate catalog.items.mcpServers.Ref {
        transport.command = "forbidden";
      };
    };
  };
  zeroTransportItems = catalog.items // {
    mcpServers = catalog.items.mcpServers // {
      Ref = catalog.items.mcpServers.Ref // {
        transport = { };
      };
    };
  };
  literalSecretItems = catalog.items // {
    mcpServers = catalog.items.mcpServers // {
      Ref = lib.recursiveUpdate catalog.items.mcpServers.Ref {
        transport.headers."x-ref-api-key" = "literal-secret";
      };
    };
  };
  querySecretItems = catalog.items // {
    mcpServers = catalog.items.mcpServers // {
      Ref = lib.recursiveUpdate catalog.items.mcpServers.Ref {
        transport.url = "https://api.ref.tools/mcp?apiKey=literal-secret";
      };
    };
  };
  malformedEnvItems = catalog.items // {
    mcpServers = catalog.items.mcpServers // {
      context7 = lib.recursiveUpdate catalog.items.mcpServers.context7 {
        transport.headers.CONTEXT7_API_KEY.env = "not-valid";
      };
    };
  };
  undeclaredEnvItems = catalog.items // {
    mcpServers = catalog.items.mcpServers // {
      Ref = lib.recursiveUpdate catalog.items.mcpServers.Ref {
        transport.headers."x-ref-api-key".env = "SSH_PRIVATE_KEY";
      };
    };
  };
  providerOnlyEnvItems = catalog.items // {
    mcpServers = catalog.items.mcpServers // {
      Ref = lib.recursiveUpdate catalog.items.mcpServers.Ref {
        transport.headers."x-ref-api-key".env = "NVIDIA_API_KEY";
      };
    };
  };
  withPalLiteralEnv =
    name:
    catalog.items
    // {
      mcpServers = catalog.items.mcpServers // {
        pal = lib.recursiveUpdate catalog.items.mcpServers.pal {
          transport.env.${name} = "literal-secret";
        };
      };
    };
  nonStringArgItems = catalog.items // {
    mcpServers = catalog.items.mcpServers // {
      anvil = lib.recursiveUpdate catalog.items.mcpServers.anvil {
        transport.args = [ 1 ];
      };
    };
  };
  withAnvilArg =
    arg:
    catalog.items
    // {
      mcpServers = catalog.items.mcpServers // {
        anvil = lib.recursiveUpdate catalog.items.mcpServers.anvil {
          transport.args = [ arg ];
        };
      };
    };
  badHeaderNameItems = catalog.items // {
    mcpServers = catalog.items.mcpServers // {
      Ref = lib.recursiveUpdate catalog.items.mcpServers.Ref {
        transport.headers."Bad Header" = {
          env = "REF_API_KEY";
        };
      };
    };
  };
  badOverrideValueItems = catalog.items // {
    mcpServers = catalog.items.mcpServers // {
      anvil = lib.recursiveUpdate catalog.items.mcpServers.anvil {
        overrides.claude.timeout = "literal-secret";
      };
    };
  };
  renderedUrlItems = catalog.items // {
    mcpServers = catalog.items.mcpServers // {
      Ref = lib.recursiveUpdate catalog.items.mcpServers.Ref {
        transport.url = "https://api.ref.tools/" + "$" + "{REF_API_KEY}";
      };
    };
  };
  insecureHttpItems = catalog.items // {
    mcpServers = catalog.items.mcpServers // {
      Ref = lib.recursiveUpdate catalog.items.mcpServers.Ref {
        transport.url = "http://api.ref.tools/mcp";
      };
    };
  };
  anvilToolsItems = catalog.items // {
    mcpServers = catalog.items.mcpServers // {
      anvil-tools = catalog.items.mcpServers.anvil // {
        name = "anvil-tools";
      };
    };
  };
  missingRendererProfiles = catalog.profiles // {
    hera-codex = catalog.profiles.hera-codex // {
      renderer = null;
    };
  };
  filteredDefaultModels = modelData // {
    profileDefaults = modelData.profileDefaults // {
      vulcan-opencode = modelData.profileDefaults.hera-opencode;
    };
  };
  unknownPolicyField = modelPolicy // {
    defaultModel = {
      provider = "litellm";
      model = "forbidden";
    };
  };
  unknownProviderPolicy = modelPolicy // {
    providers = modelPolicy.providers // {
      unknown = { };
    };
  };
  concreteProviderPolicy = modelPolicy // {
    providers = modelPolicy.providers // {
      litellm = modelPolicy.providers.litellm // {
        baseUrl = "https://forbidden.invalid/v1";
      };
    };
  };

  expectedProviders = [
    "litellm"
    "llama-cpp-local"
    "llama-cpp-remote"
    "nvidia"
    "omlx"
    "positron-anthropic"
    "positron-google"
    "positron-openai"
  ];
  expectedProviderBaseUrls = {
    litellm = "https://litellm.vulcan.lan/v1/";
    llama-cpp-local = "http://localhost:8080/v1";
    llama-cpp-remote = "https://10.6.0.1/v1/";
    nvidia = "https://integrate.api.nvidia.com/v1";
    omlx = "http://hera.lan:8000/v1";
    positron-anthropic = "https://api.anthropic.com";
    positron-google = "https://generativelanguage.googleapis.com/v1beta/";
    positron-openai = "https://api.openai.com/v1";
  };
  expectedProviderCredentials = {
    litellm.env = "LITELLM_API_KEY";
    llama-cpp-local.nonSecret = "not-needed";
    llama-cpp-remote.nonSecret = "dummy-api-key";
    nvidia.env = "NVIDIA_API_KEY";
    omlx.nonSecret = "dummy-key";
    positron-anthropic.env = "ANTHROPIC_API_KEY";
    positron-google.env = "GEMINI_API_KEY";
    positron-openai.env = "OPENAI_API_KEY";
  };
  expectedClientVersions = {
    claude = "2.1.217";
    codex = "0.144.6";
    droid = "0.177.0";
    opencode = "1.18.4";
    pi = "0.81.1";
  };
  expectedAdapterVersions = {
    mcp-remote = "0.1.38";
    pi-mcp-adapter = "2.11.0";
    pi-subagent = "3.0.0";
  };
  expectedSecretRouting = {
    claude = {
      transport = "native";
      reference = "dollar-braced";
      missingValue = "placeholder-warning";
    };
    codex = {
      transport = "native";
      reference = "env-http-headers";
      missingValue = "omit-header";
      isolatedState = true;
    };
    droid = {
      transport = "bridge";
      preflight = "fixed";
      argvFields = [
        "url"
        "header"
        "envName"
      ];
    };
    opencode = {
      transport = "native";
      reference = "brace-env";
      missingValue = "empty-header";
      oauthDisabled = true;
    };
    pi = {
      transport = "native";
      reference = "dollar-braced";
      missingValue = "empty-header";
      customHeaderDisablesOauth = true;
      oauthDisabled = true;
    };
  };
  expectedSecretServers = {
    Ref = {
      url = "https://api.ref.tools/mcp";
      header = "x-ref-api-key";
      envName = "REF_API_KEY";
    };
    context7 = {
      url = "https://mcp.context7.com/mcp";
      header = "CONTEXT7_API_KEY";
      envName = "CONTEXT7_API_KEY";
    };
  };
  expectedSecretCarriers = {
    claude = "header-template";
    codex = "env-http-header-name";
    droid = "header-bridge-argv-name";
    opencode = "header-env-reference";
    pi = "header-template";
  };
  expectedSecretCapabilities = lib.listToAttrs (
    lib.concatMap (
      client:
      map (server: {
        name = "${client}/${server}";
        value = expectedSecretServers.${server} // {
          inherit client server;
          carrier = expectedSecretCarriers.${client};
          oauthDisabled = builtins.elem client [
            "opencode"
            "pi"
          ];
          missingEnv = if client == "droid" then "preflight-rejected" else "connection-rejected";
          maxDiagnosticBytes = if client == "droid" then 512 else null;
          redacted = true;
          resolvedValueLocations = [ ];
        };
      }) (builtins.attrNames expectedSecretServers)
    ) (builtins.attrNames expectedSecretCarriers)
  );
  canonicalData = {
    inherit (catalog) profiles items selectorCoverage;
    inherit modelData;
  };
  canonicalJson = builtins.toJSON canonicalData;
  collectTypedEnvNames =
    value:
    if builtins.isAttrs value then
      lib.optional (sortedNames value == [ "env" ] && builtins.isString value.env) value.env
      ++ lib.concatMap collectTypedEnvNames (builtins.attrValues value)
    else if builtins.isList value then
      lib.concatMap collectTypedEnvNames value
    else
      [ ];
  expectedEnvNames = [
    "ANTHROPIC_API_KEY"
    "CONTEXT7_API_KEY"
    "GEMINI_API_KEY"
    "LITELLM_API_KEY"
    "NVIDIA_API_KEY"
    "OPENAI_API_KEY"
    "PERPLEXITY_API_KEY"
    "REF_API_KEY"
  ];
  forbiddenEnvSyntax = [
    ("$" + "{")
    "{env:"
    "$env:"
    "?apiKey="
  ]
  ++ map (name: "$" + name) [
    "ANTHROPIC_API_KEY"
    "CONTEXT7_API_KEY"
    "GEMINI_API_KEY"
    "LITELLM_API_KEY"
    "NVIDIA_API_KEY"
    "OPENAI_API_KEY"
    "PERPLEXITY_API_KEY"
    "REF_API_KEY"
  ];

  task9AiModulePath = "${src}/config/ai.nix";
  task9PreflightPath = "${src}/config/ai/preflight.nix";
  task9AiModule =
    if builtins.pathExists task9AiModulePath && builtins.pathExists task9PreflightPath then
      import task9AiModulePath
    else
      throw "Task 9 RED: config/ai.nix and config/ai/preflight.nix are missing";
  task9RenderedByProfile =
    renderedClaude // renderedCodex // renderedOpenCode // renderedDroid // renderedPi;
  task9ExpectedProfileIds = {
    hera = [
      "hera-claude-personal"
      "hera-claude-positron"
      "hera-codex"
      "hera-opencode"
      "hera-droid"
      "hera-pi"
    ];
    clio = [
      "clio-claude-personal"
      "clio-claude-positron"
      "clio-codex"
      "clio-opencode"
    ];
    vulcan = [
      "vulcan-claude-personal"
      "vulcan-opencode"
    ];
    vps = [ "vps-claude-personal" ];
    shared-work = [
      "shared-work-claude-positron"
      "shared-work-codex"
      "shared-work-opencode-positron"
    ];
    personal-linux = [ "vps-claude-personal" ];
  };
  task9ExpectedClients = {
    hera = [
      "claude"
      "codex"
      "droid"
      "opencode"
      "pi"
    ];
    clio = [
      "claude"
      "codex"
      "opencode"
    ];
    vulcan = [
      "claude"
      "opencode"
    ];
    vps = [ "claude" ];
    shared-work = [
      "claude"
      "codex"
      "opencode"
    ];
    personal-linux = [ "claude" ];
  };
  task9RawPathsForClass =
    homeClass:
    lib.concatMap (
      profileId: builtins.attrNames task9RenderedByProfile.${profileId}.files
    ) task9ExpectedProfileIds.${homeClass};
  task9PathsForClass =
    homeClass: lib.sort builtins.lessThan (lib.unique (task9RawPathsForClass homeClass));
  task9ForbiddenParentPaths = [
    ".agents"
    ".agents/skills"
    ".claude"
    ".codex"
    ".config/claude"
    ".config/claude/personal"
    ".config/claude/positron"
    ".config/codex"
    ".config/factory"
    ".config/mcp"
    ".config/opencode"
    ".factory"
    ".pi"
    ".pi/agent"
  ];
  task9SherlockPaths = [
    ".claude/skills/sherlock"
    ".claude/skills/sherlock/SKILL.md"
    ".claude/skills/sherlock/sherlock"
  ];
  task9FractalPaths = [
    ".agents/skills/fractal"
    ".agents/skills/wiki"
  ];
  task9ManagedPrefixes = [
    ".agents/skills"
    ".claude/agents"
    ".claude/commands"
    ".claude/skills"
    ".codex/agents"
    ".config/claude/personal/agents"
    ".config/claude/personal/commands"
    ".config/claude/personal/skills"
    ".config/claude/positron/agents"
    ".config/claude/positron/commands"
    ".config/claude/positron/skills"
    ".config/codex/agents"
    ".config/factory/droids"
    ".config/factory/skills"
    ".config/opencode/agents"
    ".config/opencode/commands"
    ".config/opencode/skills"
    ".pi/agent/agents"
    ".pi/agent/prompts"
  ];
  task9ManagedExactPaths = [
    ".claude/nix-managed-mcp.json"
    ".claude/nix-managed-settings.json"
    ".claude/statusline-command.sh"
    ".codex/nix-managed.config.toml"
    ".codex/hooks.json"
    ".config/claude/personal/nix-managed-mcp.json"
    ".config/claude/personal/nix-managed-settings.json"
    ".config/claude/personal/statusline-command.sh"
    ".config/claude/positron/nix-managed-mcp.json"
    ".config/claude/positron/nix-managed-settings.json"
    ".config/claude/positron/statusline-command.sh"
    ".config/codex/nix-managed.config.toml"
    ".config/codex/hooks.json"
    ".config/factory/mcp.json"
    ".config/factory/nix-managed-settings.json"
    ".config/mcp/mcp.json"
    ".config/opencode/opencode.json"
    ".pi/agent/extensions/pi-mcp-adapter"
    ".pi/agent/extensions/pi-quiet"
    ".pi/agent/extensions/pi-subagent"
    ".pi/agent/models.json"
  ];
  task9IsManagedHomePath =
    path:
    !(builtins.elem path (task9SherlockPaths ++ task9FractalPaths))
    && (
      builtins.elem path task9ManagedExactPaths
      || lib.any (prefix: lib.hasPrefix "${prefix}/" path) task9ManagedPrefixes
    );
  task9ValidRelativePath =
    path:
    let
      parts = lib.splitString "/" path;
    in
    path != ""
    && !(lib.hasPrefix "/" path)
    && builtins.all (part: part != "" && part != "." && part != "..") parts;
  task9OwnsAncestor =
    paths: path: lib.any (other: other != path && lib.hasPrefix "${path}/" other) paths;

  mkTask9AiEvaluation =
    {
      hostname,
      username,
      system,
      homeClass ? null,
    }:
    let
      fixturePkgs = testPkgsFor.${system};
      homeDirectory = "/tmp/nix-managed-ai-${username}-${hostname}";
    in
    homeManagerLib.homeManagerConfiguration {
      pkgs = fixturePkgs;
      extraSpecialArgs = {
        inherit hostname inputs;
      }
      // lib.optionalAttrs (homeClass != null) {
        nixManagedAiHomeClass = homeClass;
      };
      modules = [
        task9AiModule
        {
          home = {
            inherit homeDirectory username;
            stateVersion = "23.11";
          };
          # homeManagerConfiguration injects its own source at equal priority;
          # normalize only this standalone fixture instead of the live checkout.
          programs.home-manager.path = lib.mkForce (toString inputs.home-manager);
          targets.genericLinux.enable = fixturePkgs.stdenv.isLinux;
          xdg.enable = true;
        }
      ];
    };

  task9FixtureSpecs = {
    hera = {
      hostname = "hera";
      username = "johnw";
      system = "aarch64-darwin";
      expectedClass = "hera";
    };
    clio = {
      hostname = "clio";
      username = "johnw";
      system = "aarch64-darwin";
      expectedClass = "clio";
    };
    vulcan = {
      hostname = "vulcan";
      username = "johnw";
      system = "x86_64-linux";
      expectedClass = "vulcan";
    };
    vps = {
      hostname = "vps";
      username = "johnw";
      system = "x86_64-linux";
      expectedClass = "vps";
    };
    shared = {
      hostname = "vulcan";
      username = "jwiegley";
      system = "x86_64-linux";
      expectedClass = "shared-work";
    };
    personal-synthetic = {
      hostname = "linux";
      username = "johnw";
      system = "aarch64-linux";
      homeClass = "personal-linux";
      expectedClass = "personal-linux";
    };
    shared-synthetic = {
      hostname = "linux";
      username = "jwiegley";
      system = "x86_64-linux";
      expectedClass = "shared-work";
    };
  };
  task9Evaluations = lib.mapAttrs (
    _: spec: mkTask9AiEvaluation (builtins.removeAttrs spec [ "expectedClass" ])
  ) task9FixtureSpecs;
  task9InvalidPersonalSynthetic = mkTask9AiEvaluation {
    hostname = "linux";
    username = "jwiegley";
    system = "aarch64-linux";
    homeClass = "personal-linux";
  };
  task9UnknownHomeClass = mkTask9AiEvaluation {
    hostname = "unknown-host";
    username = "johnw";
    system = "x86_64-linux";
  };
  task9BridgeFor = system: inputs.ai-nix.packages.${system}.agent-http-header-bridge;
  task9HasBridge =
    system: evaluation:
    lib.any (
      package: toString package == toString (task9BridgeFor system)
    ) evaluation.config.home.packages;
  task9ClientsIn =
    evaluation:
    let
      files = evaluation.config.home.file;
      markers = {
        claude = [
          ".claude/nix-managed-settings.json"
          ".config/claude/personal/nix-managed-settings.json"
          ".config/claude/positron/nix-managed-settings.json"
        ];
        codex = [
          ".codex/nix-managed.config.toml"
          ".config/codex/nix-managed.config.toml"
        ];
        droid = [ ".config/factory/nix-managed-settings.json" ];
        opencode = [ ".config/opencode/opencode.json" ];
        pi = [ ".pi/agent/models.json" ];
      };
    in
    builtins.filter (client: lib.any (path: builtins.hasAttr path files) markers.${client}) (
      builtins.attrNames markers
    );
  task9HasPiGuard =
    evaluation:
    lib.hasInfix ".pi/agent/mcp.json" evaluation.config.home.activation.aiManagedPreflight.data;
  task9ActivationOrder =
    evaluation:
    map (entry: entry.name) (homeManagerLib.hm.dag.topoSort evaluation.config.home.activation).result;
  task9IndexOf =
    needle: values:
    let
      match = lib.findFirst (entry: entry.value == needle) null (
        lib.imap0 (index: value: { inherit index value; }) values
      );
    in
    if match == null then -1 else match.index;
  task9OrderingIsExact =
    evaluation:
    let
      order = task9ActivationOrder evaluation;
      preflight = task9IndexOf "aiManagedPreflight" order;
      collision = task9IndexOf "checkLinkTargets" order;
      boundary = task9IndexOf "writeBoundary" order;
      links = task9IndexOf "linkGeneration" order;
    in
    preflight >= 0 && preflight < collision && collision < boundary && boundary < links;

  task9FixtureChecks = lib.concatLists (
    lib.mapAttrsToList (
      name: spec:
      let
        evaluation = task9Evaluations.${name};
        inherit (spec) expectedClass;
        expectedPaths = task9PathsForClass expectedClass;
        actualClients = task9ClientsIn evaluation;
      in
      [
        (expectEqual "${name} exact AI paths" (builtins.filter task9IsManagedHomePath (
          sortedNames evaluation.config.home.file
        )) expectedPaths)
        (expectEqual "${name} enabled clients" actualClients task9ExpectedClients.${expectedClass})
        (expectEqual "${name} forces every managed AI leaf" (builtins.all (
          path: evaluation.config.home.file.${path}.force
        ) expectedPaths) true)
        (expectEqual "${name} Droid bridge selection" (task9HasBridge spec.system evaluation) (
          name == "hera"
        ))
        (expectEqual "${name} preflight DAG edge"
          evaluation.config.home.activation.aiManagedPreflight.before
          [ "checkLinkTargets" ]
        )
        (expectEqual "${name} Pi shadow guard selection" (task9HasPiGuard evaluation) (name == "hera"))
        (expectEqual "${name} activation ordering" (task9OrderingIsExact evaluation) true)
      ]
    ) task9FixtureSpecs
  );
  task9PathChecks = lib.concatMap (
    homeClass:
    let
      rawPaths = task9RawPathsForClass homeClass;
      paths = task9PathsForClass homeClass;
    in
    [
      (expectEqual "${homeClass} has one writer per leaf" (builtins.length rawPaths) (
        builtins.length paths
      ))
      (expectEqual "${homeClass} has only relative normalized paths"
        (builtins.all task9ValidRelativePath paths)
        true
      )
      (expectEqual "${homeClass} owns no mutable parent root"
        (lib.intersectLists paths task9ForbiddenParentPaths)
        [ ]
      )
      (expectEqual "${homeClass} owns no ancestor of another leaf"
        (builtins.any (task9OwnsAncestor paths) paths)
        false
      )
      (expectEqual "${homeClass} excludes the Sherlock writer"
        (lib.intersectLists paths task9SherlockPaths)
        [ ]
      )
    ]
  ) (builtins.attrNames task9ExpectedProfileIds);

  mkTask9JohnwEvaluation =
    {
      hostname,
      username,
      system,
      homeClass ? null,
    }:
    let
      fixturePkgs = testPkgsFor.${system};
      homeDirectory = "/tmp/nix-managed-ai-${username}-${hostname}";
    in
    homeManagerLib.homeManagerConfiguration {
      pkgs = fixturePkgs;
      extraSpecialArgs = {
        inherit hostname inputs;
      }
      // lib.optionalAttrs (homeClass != null) {
        nixManagedAiHomeClass = homeClass;
      };
      modules = [
        (import (
          if fixturePkgs.stdenv.isDarwin then "${src}/config/home.nix" else "${src}/config/johnw.nix"
        ))
        {
          home = {
            inherit homeDirectory username;
            stateVersion = "23.11";
          };
          # homeManagerConfiguration injects its own source at equal priority;
          # normalize only this standalone fixture instead of the live checkout.
          programs.home-manager.path = lib.mkForce (toString inputs.home-manager);
          targets.genericLinux.enable = fixturePkgs.stdenv.isLinux;
          xdg.enable = true;
        }
      ];
    };
  task9JohnwEvaluations = lib.mapAttrs (
    _: spec: mkTask9JohnwEvaluation (builtins.removeAttrs spec [ "expectedClass" ])
  ) task9FixtureSpecs;
  task9JohnwHera = task9JohnwEvaluations.hera;
  task9JohnwPersonalSynthetic = task9JohnwEvaluations.personal-synthetic;
  task9JohnwSharedSynthetic = task9JohnwEvaluations.shared-synthetic;
  task9AiPathsIn =
    evaluation:
    lib.sort builtins.lessThan (
      builtins.filter task9IsManagedHomePath (builtins.attrNames evaluation.config.home.file)
    );
  task9IntegratedPathChecks =
    lib.mapAttrsToList (
      name: spec:
      expectEqual "Task 9 integrated ${name} exact AI paths" (task9AiPathsIn
        task9JohnwEvaluations.${name}
      ) (task9PathsForClass spec.expectedClass)
    ) task9FixtureSpecs
    ++ [
      (expectEqual "Task 9 preserves separate Fractal skill writers" (builtins.filter (
        path: builtins.hasAttr path task9JohnwHera.config.home.file
      ) task9FractalPaths) task9FractalPaths)
      (expectEqual "Task 9 omits stale Fractal Pi model writer"
        (builtins.hasAttr "pi/agent/models.json" task9JohnwHera.config.xdg.configFile)
        false
      )
    ];
  task9ClaudeMemData = task9JohnwHera.config.home.activation.claudeMemRealClaude.data;

  task9DarwinPkgs = testPkgsFor.aarch64-darwin;
  task9WrappedClaude =
    inputs.ai-nix.lib.patchAgentPackage task9DarwinPkgs "claude-code"
      inputs.llm-agents.packages.aarch64-darwin.claude-code;
  task9HeraBridge = task9BridgeFor "aarch64-darwin";
  task9HeraPackages =
    (import "${src}/config/packages.nix" {
      hostname = "hera";
      inherit inputs;
      pkgs = task9DarwinPkgs;
    }).package-list;
  task9HeraHasPackage =
    package: lib.any (candidate: toString candidate == toString package) task9HeraPackages;
  task9AgentDeckEvaluation = homeManagerLib.homeManagerConfiguration {
    pkgs = task9DarwinPkgs;
    modules = [
      (import "${src}/config/agent-deck.nix")
      {
        home = {
          username = "johnw";
          homeDirectory = "/Users/johnw";
          stateVersion = "23.11";
        };
        johnw.agentDeck.enableConductorDiscordBridge = true;
        xdg.enable = true;
      }
    ];
  };
  task9ExpectedAgentDeckPath =
    "${task9AgentDeckEvaluation.config.home.profileDirectory}/bin:"
    + "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  task9PackageSource = builtins.readFile "${src}/config/packages.nix";
  task9FlakeSource = builtins.readFile "${src}/flake.nix";

  task9Checks = [
    (expectEqual "Task 9 direct raw Claude writer removed"
      (builtins.hasAttr ".local/bin/claude" task9JohnwHera.config.home.file)
      false
    )
    (expectEqual "Task 9 Sherlock SKILL writer preserved"
      (builtins.hasAttr ".claude/skills/sherlock/SKILL.md" task9JohnwHera.config.home.file)
      true
    )
    (expectEqual "Task 9 Sherlock executable writer preserved"
      (builtins.hasAttr ".claude/skills/sherlock/sherlock" task9JohnwHera.config.home.file)
      true
    )
    (expectEqual "Task 9 Codex alias preserved"
      (builtins.hasAttr ".codex" task9JohnwHera.config.home.file)
      true
    )
    (expectEqual "Task 9 Factory alias preserved"
      (builtins.hasAttr ".factory" task9JohnwHera.config.home.file)
      true
    )
    (expectEqual "Task 9 Linux Factory ripgrep alias preserved"
      (builtins.hasAttr ".factory/bin/rg" task9JohnwPersonalSynthetic.config.home.file)
      true
    )
    (expectEqual "Task 9 personal synthetic hostname is unchanged"
      task9JohnwPersonalSynthetic.config.home.sessionVariables.HOSTNAME
      "linux"
    )
    (expectEqual "Task 9 shared synthetic hostname is unchanged"
      task9JohnwSharedSynthetic.config.home.sessionVariables.HOSTNAME
      "linux"
    )
    (expectEqual "Task 9 personal synthetic exact AI paths" (task9AiPathsIn task9JohnwPersonalSynthetic)
      (task9PathsForClass "personal-linux")
    )
    (expectEqual "Task 9 shared synthetic exact AI paths" (task9AiPathsIn task9JohnwSharedSynthetic) (
      task9PathsForClass "shared-work"
    ))
    (expectEqual "Task 9 shared agent-deck helper preserved"
      (builtins.hasAttr ".local/bin/agent-deck-remote-env" task9JohnwSharedSynthetic.config.home.file)
      true
    )
    (expectEqual "Task 9 managed profile precedes preserved PATH prefixes"
      (lib.take 3 task9JohnwHera.config.home.sessionPath)
      [
        "${task9JohnwHera.config.home.profileDirectory}/bin"
        "${task9JohnwHera.config.home.homeDirectory}/src/scripts"
        "${task9JohnwHera.config.home.homeDirectory}/.local/bin"
      ]
    )
    (expectEqual "Task 9 standalone fixture normalizes Home Manager source"
      task9JohnwHera.config.programs.home-manager.path
      (toString inputs.home-manager)
    )
    (expectEqual "Task 9 claude-mem uses raw private command"
      (lib.hasInfix "${task9JohnwHera.config.home.profileDirectory}/bin/claude-real" task9ClaudeMemData)
      true
    )
    (expectEqual "Task 9 claude-mem no longer uses raw bypass"
      (lib.hasInfix ".local/bin/claude" task9ClaudeMemData)
      false
    )
    (expectEqual "Task 9 real Hera packages include patched Claude"
      (task9HeraHasPackage task9WrappedClaude)
      true
    )
    (expectEqual "Task 9 integrated Hera packages include Droid bridge"
      (task9HasBridge "aarch64-darwin" task9JohnwHera)
      true
    )
    (expectEqual "Task 9 integrated Hera omits legacy Pi root writer"
      (builtins.hasAttr ".pi" task9JohnwHera.config.home.file)
      false
    )
    (expectEqual "Task 9 integrated Hera owns Pi agent leaves" (lib.any (
      path: lib.hasPrefix ".pi/agent/" path
    ) (builtins.attrNames task9JohnwHera.config.home.file)) true)
    (expectEqual "Task 9 real Hera packages include persona provider"
      (task9HeraHasPackage task9DarwinPkgs.nix-scripts)
      true
    )
    (expectEqual "Task 9 package path still calls ai-nix patching"
      (lib.hasInfix "patchAgentPackage name agentPackages.\${name}" task9PackageSource)
      true
    )
    (expectEqual "Task 9 Claude package selection remains patched"
      (lib.hasInfix "++ optAgent \"claude-code\"" task9PackageSource)
      true
    )
    (expectEqual "Task 9 personal Linux fixture is explicit"
      (lib.hasInfix "nixManagedAiHomeClass = \"personal-linux\"" task9FlakeSource)
      true
    )
    (expectReject "Task 9 personal Linux fixture accepted wrong user" task9InvalidPersonalSynthetic.activationPackage.drvPath)
    (expectReject "Task 9 unknown home class accepted" task9UnknownHomeClass.activationPackage.drvPath)
    (expectEqual "Task 9 agent-deck bridge PATH"
      task9AgentDeckEvaluation.config.launchd.agents.agent-deck-conductor-bridge.config.EnvironmentVariables.PATH
      task9ExpectedAgentDeckPath
    )
    (expectEqual "Task 9 agent-deck notifier PATH"
      task9AgentDeckEvaluation.config.launchd.agents.agent-deck-transition-notifier.config.EnvironmentVariables.PATH
      task9ExpectedAgentDeckPath
    )
  ]
  ++ task9FixtureChecks
  ++ task9PathChecks
  ++ task9IntegratedPathChecks;

  task10ModelSyncPath = "${src}/config/ai/model-sync.nix";
  task10ModelSyncSource =
    if builtins.pathExists task10ModelSyncPath then
      builtins.readFile task10ModelSyncPath
    else
      throw "Task 10 RED: config/ai/model-sync.nix is missing";
  task10ModelSyncFactory = import task10ModelSyncPath {
    lib = lib // {
      inherit (homeManagerLib) hm;
    };
    inherit pkgs;
  };

  task10FakeDispatcher = pkgs.writeShellScript "task10-fake-dispatcher" ''
    set -eu

    tool=$1
    shift
    : "''${TASK10_LOG:?}"
    : "''${TASK10_FAKE_STATE:?}"
    state=$TASK10_FAKE_STATE

    log_call() {
      printf '%s' "$tool" >> "$TASK10_LOG"
      for argument in "$@"; do
        printf '\t%s' "$argument" >> "$TASK10_LOG"
      done
      printf '\n' >> "$TASK10_LOG"
    }

    case "$tool" in
      pgrep)
        log_call "$@"
        [ "$#" -eq 2 ] && [ "$1" = -x ] || exit 90
        [ "''${TASK10_FAIL_AT:-}" != pgrep-error ] || exit 2
        [ -f "$state/running" ] || exit 1
        IFS= read -r running < "$state/running" || true
        [ "$running" = "$2" ]
        ;;

      devonthinkKeyPresent)
        log_call "$@"
        [ "$#" -eq 0 ] || exit 91
        [ -s "$state/devonthink-credential" ]
        ${pkgs.coreutils}/bin/cat "$state/devonthink-credential"
        ${pkgs.coreutils}/bin/cat "$state/devonthink-credential" >&2
        ;;

      security)
        log_call "$@"
        [ "$#" -eq 5 ] || exit 92
        [ "$1" = find-generic-password ]
        [ "$2" = -s ] && [ "$3" = "iTerm2 API Keys" ]
        [ "$4" = -a ] && [ "$5" = "OpenAI API Key for iTerm2" ]
        [ -f "$state/iterm-key-metadata" ]
        ${pkgs.coreutils}/bin/cat "$state/devonthink-credential"
        ${pkgs.coreutils}/bin/cat "$state/devonthink-credential" >&2
        ;;

      defaults)
        log_call "$@"
        [ "$#" -ge 3 ] || exit 93
        operation=$1
        domain=$2
        key=$3
        case "$domain|$key" in
          "com.devon-technologies.think|ChatEngine")
            slot=devonthink.ChatEngine; kind=-int; wanted=2; stored=2; updater=devonthink ;;
          "com.devon-technologies.think|ChatModel-OpenAI (Compatible)")
            slot=devonthink.ChatModel; kind=-string
            wanted="''${TASK10_EXPECTED_MODEL:?}"; stored=$wanted; updater=devonthink ;;
          "com.devon-technologies.think|OpenAI (Compatible)URL")
            slot=devonthink.ChatURL; kind=-string
            wanted="''${TASK10_EXPECTED_URL:?}"; stored=$wanted; updater=devonthink ;;
          "com.devon-technologies.think|ChatSummaryEngine")
            slot=devonthink.ChatSummaryEngine; kind=-int; wanted=2; stored=2; updater=devonthink ;;
          "com.devon-technologies.think|ChatSummaryModel")
            slot=devonthink.ChatSummaryModel; kind=-string
            wanted="''${TASK10_EXPECTED_MODEL:?}"; stored=$wanted; updater=devonthink ;;
          "com.googlecode.iterm2|UseRecommendedAIModel")
            slot=iterm.UseRecommendedAIModel; kind=-bool; wanted=false; stored=0; updater=iterm ;;
          "com.googlecode.iterm2|AiModel")
            slot=iterm.AiModel; kind=-string
            wanted="''${TASK10_EXPECTED_MODEL:?}"; stored=$wanted; updater=iterm ;;
          "com.googlecode.iterm2|AITermAPI")
            slot=iterm.AITermAPI; kind=-int; wanted=1; stored=1; updater=iterm ;;
          "com.googlecode.iterm2|AitermURL")
            slot=iterm.AitermURL; kind=-string
            wanted="''${TASK10_EXPECTED_URL:?}"; stored=$wanted; updater=iterm ;;
          "com.googlecode.iterm2|AIVendor")
            slot=iterm.AIVendor; kind=-int; wanted=2; stored=2; updater=iterm ;;
          *) exit 94 ;;
        esac

        case "$operation" in
          read)
            [ "$#" -eq 3 ] || exit 95
            [ "''${TASK10_FAIL_AT:-}" != "$updater-verify" ] || exit 96
            [ -f "$state/prefs/$slot" ] || exit 1
            ${pkgs.coreutils}/bin/cat "$state/prefs/$slot"
            ;;
          write)
            [ "$#" -eq 5 ] || exit 97
            [ "$4" = "$kind" ] && [ "$5" = "$wanted" ] || exit 98
            [ "''${TASK10_FAIL_AT:-}" != "$updater-update" ] || exit 99
            ${pkgs.coreutils}/bin/mkdir -p "$state/prefs"
            printf '%s' "$stored" > "$state/prefs/$slot"
            ;;
          *) exit 100 ;;
        esac
        ;;

      mkdir)
        log_call "$@"
        [ "$#" -eq 3 ] && [ "$1" = -p ] && [ "$2" = -- ] || exit 101
        exec ${pkgs.coreutils}/bin/mkdir "$@"
        ;;
      mktemp)
        log_call "$@"
        [ "$#" -eq 1 ]
        [ "$1" = "$XDG_STATE_HOME/nix-managed-ai/model-sync-v1.sha256.tmp.XXXXXX" ]
        exec ${pkgs.coreutils}/bin/mktemp "$@"
        ;;
      mv)
        log_call "$@"
        [ "$#" -eq 4 ] && [ "$1" = -fT ] && [ "$2" = -- ] || exit 102
        case "$3" in
          "$XDG_STATE_HOME/nix-managed-ai/model-sync-v1.sha256.tmp."*) ;;
          *) exit 103 ;;
        esac
        [ "$4" = "$XDG_STATE_HOME/nix-managed-ai/model-sync-v1.sha256" ] || exit 104
        [ "''${TASK10_FAIL_AT:-}" != rename ] || exit 105
        exec ${pkgs.coreutils}/bin/mv "$@"
        ;;
      rm)
        log_call "$@"
        [ "$#" -eq 3 ] && [ "$1" = -f ] && [ "$2" = -- ] || exit 106
        case "$3" in
          "$XDG_STATE_HOME/nix-managed-ai/model-sync-v1.sha256.tmp."*) ;;
          *) exit 107 ;;
        esac
        exec ${pkgs.coreutils}/bin/rm "$@"
        ;;
      *) exit 108 ;;
    esac
  '';

  task10ToolNames = [
    "defaults"
    "devonthinkKeyPresent"
    "mkdir"
    "mktemp"
    "mv"
    "pgrep"
    "rm"
    "security"
  ];
  task10FakeTools = lib.genAttrs task10ToolNames (
    name:
    toString (
      pkgs.writeShellScript "task10-fake-${name}" ''
        exec ${task10FakeDispatcher} ${lib.escapeShellArg name} "$@"
      ''
    )
  );
  task10Sync = task10ModelSyncFactory {
    inherit (modelData) syncInputs;
    tools = task10FakeTools;
  };
  task10ChangedSync = task10ModelSyncFactory {
    inherit (alternateModelData) syncInputs;
    tools = task10FakeTools;
  };
  task10EmptyModelProbe = task10ModelSyncFactory {
    syncInputs = modelData.syncInputs // {
      model = "";
    };
    tools = task10FakeTools;
  };
  task10Script = pkgs.writeShellScript "task10-model-sync" task10Sync.script;
  task10ChangedScript = pkgs.writeShellScript "task10-model-sync-changed" task10ChangedSync.script;
  task10DigestFor =
    syncInputs:
    builtins.hashString "sha256" (
      builtins.toJSON {
        schema = 1;
        inherit (syncInputs) provider model chatUrl;
      }
    );
  task10Digest = task10DigestFor modelData.syncInputs;
  task10ChangedDigest = task10DigestFor alternateModelData.syncInputs;
  task10HasActivation =
    evaluation: builtins.hasAttr "aiManagedModelSync" evaluation.config.home.activation;
  task10HeraOrder = task9ActivationOrder task9Evaluations.hera;
  task10Count = needle: builtins.length (lib.splitString needle task10ModelSyncSource) - 1;
  task10ForbiddenSourceFragments = [
    "defaults export"
    "PromptdeployOpenAICompatibleKeyHash"
    "find-generic-password -w"
    "security -w"
    "NSProcessInfo"
    "processInfo.environment"
    "getenv("
    "ObjC.unwrap"
    "setObjectForKey"
    "ANTHROPIC_API_KEY"
    "CONTEXT7_API_KEY"
    "GEMINI_API_KEY"
    "LITELLM_API_KEY"
    "NVIDIA_API_KEY"
    "OPENAI_API_KEY"
    "PERPLEXITY_API_KEY"
    "REF_API_KEY"
    "console.log("
    "sha256sum"
    "shasum"
    "openssl dgst"
  ];

  task10Checks = [
    (expectEqual "Task 10 factory output shape" (sortedNames task10Sync) [
      "activation"
      "digest"
      "script"
    ])
    (expectEqual "Task 10 tool seam is exact" (sortedNames task10FakeTools) task10ToolNames)
    (expectEqual "Task 10 factory DAG edge" task10Sync.activation.after [ "linkGeneration" ])
    (expectEqual "Task 10 factory has no before edge" task10Sync.activation.before [ ])
    (expectEqual "Task 10 Hera activation exists" (task10HasActivation task9Evaluations.hera) true)
    (expectEqual "Task 10 Clio activation is absent" (task10HasActivation task9Evaluations.clio) false)
    (expectEqual "Task 10 Linux activations are absent"
      (lib.mapAttrs (_: task10HasActivation) (
        builtins.removeAttrs task9Evaluations [
          "hera"
          "clio"
        ]
      ))
      {
        personal-synthetic = false;
        shared = false;
        shared-synthetic = false;
        vps = false;
        vulcan = false;
      }
    )
    (expectEqual "Task 10 runs after linkGeneration" (
      task9IndexOf "aiManagedModelSync" task10HeraOrder > task9IndexOf "linkGeneration" task10HeraOrder
    ) true)
    (expectEqual "Task 10 generated activation carries exact DAG edge"
      task9Evaluations.hera.config.home.activation.aiManagedModelSync.after
      [ "linkGeneration" ]
    )
    (expectEqual "Task 10 digest oracle" task10Sync.digest task10Digest)
    (expectEqual "Task 10 changed digest oracle" task10ChangedSync.digest task10ChangedDigest)
    (expectEqual "Task 10 digest changes with selection" (task10Digest != task10ChangedDigest) true)
    (expectReject "Task 10 empty synchronization input accepted" task10EmptyModelProbe)
    (expectEqual "Task 10 source omits forbidden credential operations" (lib.any (
      fragment: lib.hasInfix fragment task10ModelSyncSource
    ) task10ForbiddenSourceFragments) false)
    (expectEqual "Task 10 credential key is confined to the Boolean probe"
      (task10Count "OpenAI (Compatible)Key")
      1
    )
    (expectEqual "Task 10 has one centralized exact-key defaults read"
      (task10Count ''"$defaults_tool" read "$domain" "$key"'')
      1
    )
    (expectEqual "Task 10 has one centralized exact-key defaults write"
      (task10Count ''"$defaults_tool" write "$domain" "$key" "$type" "$value"'')
      1
    )
    (expectEqual "Task 10 uses only the exact output-discarded iTerm metadata query" (task10Count ''
      "$security_tool" find-generic-password \
              -s "iTerm2 API Keys" \
              -a "OpenAI API Key for iTerm2" \
              >/dev/null 2>&1'') 2)
  ];

  task11DarwinOnlyPackageInputs = [
    "gitlib" # its default package is git-monitor
    "hours"
    "org-jw"
    "pushme"
    "renamer"
    "trade-journal"
  ];
  task11PackageInputsFor =
    system:
    {
      llm-agents.packages.${system} = { };
      retained.packages.${system}.default = null;
    }
    // lib.genAttrs task11DarwinOnlyPackageInputs (_: {
      packages.${system}.default = null;
    });
  task11UserPackageInputNamesFor =
    system:
    (import "${src}/config/packages.nix" {
      hostname = "linux";
      inputs = task11PackageInputsFor system;
      pkgs = testPkgsFor.${system};
    }).userPackageInputNames;
  task11SelectsAiperfFor =
    python313Packages:
    let
      fixturePkgs = testPkgsFor.x86_64-linux;
      selection = import "${src}/config/packages.nix" {
        hostname = "linux";
        inputs = (task11PackageInputsFor "x86_64-linux") // {
          nixpkgs.legacyPackages."x86_64-linux".python313Packages = python313Packages;
        };
        isClientMachine = false;
        pkgs = fixturePkgs;
      };
    in
    builtins.elem fixturePkgs.aiperf selection.package-list;
  task11AiperfChecks = [
    (expectEqual "Task 11 AIPerf omits both missing source dependencies" (task11SelectsAiperfFor
      { }
    ) false)
    (expectEqual "Task 11 AIPerf requires choreographer" (task11SelectsAiperfFor {
      logistro = true;
    }) false)
    (expectEqual "Task 11 AIPerf requires logistro" (task11SelectsAiperfFor {
      choreographer = true;
    }) false)
    (expectEqual "Task 11 AIPerf selects complete source dependencies" (task11SelectsAiperfFor {
      choreographer = true;
      logistro = true;
    }) true)
  ];
  task11PackageChecks =
    map
      (
        system:
        expectEqual "Task 11 ${system} keeps only the unrelated auto package"
          (task11UserPackageInputNamesFor system)
          [ "retained" ]
      )
      [
        "aarch64-linux"
        "x86_64-linux"
      ]
    ++ [
      (expectEqual "Task 11 Darwin retains the Darwin-only auto packages"
        (task11UserPackageInputNamesFor "aarch64-darwin")
        [
          "gitlib"
          "hours"
          "org-jw"
          "pushme"
          "renamer"
          "retained"
          "trade-journal"
        ]
      )
    ];

  contractChecks = [
    (expectEqual "OpenCode bash-reviewer tool oracle" (builtins.hashString "sha256" (
      builtins.toJSON (expectedOpenCodeAgentMetadata catalog.items.agents.bash-reviewer)
    )) "27eaf3302a4ff6cd97d4a0f5a7027d57c121f362318c1b4d011b0fce691b3e1a")
    (expectEqual "OpenCode web-searcher tool oracle" (builtins.hashString "sha256" (
      builtins.toJSON (expectedOpenCodeAgentMetadata catalog.items.agents.web-searcher)
    )) "409fdb2458acb50672c6a07b60486fb5c0b4c47efec6fccf45158815b82d2736")
    (expectEqual "canonical validation" (catalog.validate candidate) true)
    (expectEqual "profile IDs" (sortedNames catalog.profiles) expectedProfileIds)
    (expectEqual "profile expectation coverage" (sortedNames profileExpectations) expectedProfileIds)
    (expectEqual "Pi profile inventory" piProfileIds [ "hera-pi" ])
    (expectEqual "Pi Hera-only host" catalog.profiles.hera-pi.host "hera")
    (expectEqual "Pi Hera-only platform" catalog.profiles.hera-pi.platform "darwin")
    (expectEqual "Pi shared-skill owner host" catalog.profiles.hera-codex.host
      catalog.profiles.hera-pi.host
    )
    (expectEqual "profile root coverage" (lib.mapAttrs (
      _: profile: profile.root
    ) catalog.profiles) expectedProfileRoots)
    (expectEqual "canonical settings item" catalog.items.settings.settings expectedSettingsItem)
    (expectEqual "legacy selector ledger" catalog.selectorCoverage.legacySelectors
      expectedLegacySelectors
    )
    (expectEqual "legacy target ledger" catalog.selectorCoverage.legacyTargets expectedLegacyTargets)
    (expectEqual "unmanaged exclusion ledger" catalog.selectorCoverage.unmanagedExclusions
      expectedUnmanagedExclusions
    )
    (expectEqual "shared Codex union" (selectedNames "shared-work-codex" "commands") (
      sortedNames catalog.items.commands
    ))
    (expectEqual "Droid command projections" (selectedNames "hera-droid" "commands") [
      "discover-bundles"
      "restack"
    ])
    (expectEqual "personal Claude skills" (selectedNames "hera-claude-personal" "skills") (
      lib.sort builtins.lessThan ((selectedNames "hera-codex" "skills") ++ [ "forge" ])
    ))
    (expectEqual "positron Claude skills" (selectedNames "hera-claude-positron" "skills") (
      lib.sort builtins.lessThan (
        (selectedNames "hera-codex" "skills")
        ++ [
          "forge"
          "retest"
        ]
      )
    ))
    (expectEqual "shared Codex skills" (selectedNames "shared-work-codex" "skills") (
      lib.sort builtins.lessThan ((selectedNames "hera-codex" "skills") ++ [ "retest" ])
    ))
    (expectEqual "registry schema version" rawModelRegistry.schemaVersion 2)
    (expectEqual "registry top-level keys" (sortedNames rawModelRegistry) [
      "models"
      "providers"
      "schemaVersion"
      "selections"
    ])
    (expectEqual "selection projection" modelData.selections rawModelRegistry.selections)
    (expectEqual "alternate Claude default selection reaches catalog"
      alternateCatalog.items.settings.settings.base.model
      alternateRegistry.selections.claudeDefault.model
    )
    (expectEqual "alternate Claude Haiku selection reaches catalog"
      alternateCatalog.items.settings.settings.base.env.ANTHROPIC_DEFAULT_HAIKU_MODEL
      alternateRegistry.selections.claudeHaiku.model
    )
    (expectEqual "alternate Claude subagent selection reaches catalog"
      alternateCatalog.items.settings.settings.base.env.CLAUDE_CODE_SUBAGENT_MODEL
      alternateRegistry.selections.claudeSubagent.model
    )
    (expectEqual "alternate OpenCode default fan-out" alternateModelData.profileDefaults {
      clio-opencode = alternateRegistry.selections.default;
      hera-opencode = alternateRegistry.selections.default;
      shared-work-opencode-positron = alternateRegistry.selections.default;
    })
    (expectEqual "alternate synchronization selection" alternateModelData.syncInputs {
      chatUrl = "https://integrate.api.nvidia.com/v1/chat/completions";
      inherit (alternateRegistry.selections.default) model provider;
    })
    (expectEqual "host-filtered model rendering" hostFilterRenderedModels
      expectedHostFilterRenderedModels
    )
    (expectEqual "renamed provider credential remains catalog-valid" (renamedCredentialCatalog.validate
      { }
    ) true)
    (expectEqual "renamed provider credential reaches required environment metadata"
      renamedCredentialOpenCode.requiredEnvNames
      [
        "CONTEXT7_API_KEY"
        "LITELLM_API_KEY"
        "NVIDIA_RENAMED_API_KEY"
        "PERPLEXITY_API_KEY"
        "REF_API_KEY"
      ]
    )
    (expectRegistryReject "unknown registry key accepted" (rawModelRegistry // { forbidden = true; }))
    (expectRegistryReject "old registry version accepted" (rawModelRegistry // { schemaVersion = 1; }))
    (expectRegistryReject "non-integer registry version accepted" (
      rawModelRegistry // { schemaVersion = "2"; }
    ))
    (expectRegistryReject "missing registry selections accepted" (
      removeAttrs rawModelRegistry [ "selections" ]
    ))
    (expectRegistryReject "unknown selection accepted" (
      rawModelRegistry
      // {
        selections = rawModelRegistry.selections // {
          forbidden = rawModelRegistry.selections.default;
        };
      }
    ))
    (expectRegistryReject "missing selection field accepted" (
      rawModelRegistry
      // {
        selections = rawModelRegistry.selections // {
          default = removeAttrs rawModelRegistry.selections.default [ "model" ];
        };
      }
    ))
    (expectRegistryReject "empty selection value accepted" (
      rawModelRegistry
      // {
        selections = rawModelRegistry.selections // {
          default = rawModelRegistry.selections.default // {
            model = "";
          };
        };
      }
    ))
    (expectRegistryReject "dangling selection provider accepted" (
      rawModelRegistry
      // {
        selections = rawModelRegistry.selections // {
          default = {
            provider = "missing";
            model = rawModelRegistry.selections.default.model;
          };
        };
      }
    ))
    (expectRegistryReject "dangling selection model accepted" (
      rawModelRegistry
      // {
        selections = rawModelRegistry.selections // {
          default = rawModelRegistry.selections.default // {
            model = "missing";
          };
        };
      }
    ))
    (expectRegistryReject "provider array type accepted" (rawModelRegistry // { providers = { }; }))
    (expectRegistryReject "duplicate provider ID accepted" (
      rawModelRegistry
      // {
        providers = rawModelRegistry.providers ++ [ (builtins.head rawModelRegistry.providers) ];
      }
    ))
    (expectRegistryReject "unknown provider field accepted" (
      withProvider (provider: provider // { accessToken = "literal-secret"; })
    ))
    (expectRegistryReject "empty provider ID accepted" (
      withProvider (provider: provider // { id = ""; })
    ))
    (expectRegistryReject "malformed environment credential accepted" (
      withProvider (provider: provider // { apiKey.env = "bad-name"; })
    ))
    (expectRegistryReject "multi-field credential accepted" (
      withProvider (
        provider:
        provider
        // {
          apiKey = {
            env = "ANTHROPIC_API_KEY";
            secret = "literal-secret";
          };
        }
      )
    ))
    (expectRegistryReject "literal credential accepted" (
      withProvider (provider: provider // { apiKey.literal = "literal-secret"; })
    ))
    (expectRegistryReject "unapproved public sentinel accepted by registry" (
      withProvider (provider: provider // { apiKey.nonSecret = "literal-secret"; })
    ))
    (expectRegistryReject "another provider's public sentinel accepted" (
      withProvider (
        provider:
        provider
        // {
          apiKey = {
            nonSecret = "dummy-key";
          };
        }
      )
    ))
    (expectRegistryReject "unsafe HTTP provider URL accepted" (
      withProvider (provider: provider // { baseUrl = "http://example.invalid/v1"; })
    ))
    (expectRegistryReject "another provider's insecure URL accepted" (
      withProvider (provider: provider // { baseUrl = "http://localhost:8080/v1"; })
    ))
    (expectRegistryReject "provider URL query accepted" (
      withProvider (provider: provider // { baseUrl = "https://example.invalid/v1?token=secret"; })
    ))
    (expectRegistryReject "provider URL placeholder accepted" (
      withProvider (
        provider:
        provider
        // {
          baseUrl = "https://example.invalid/" + "$" + "{TOKEN}";
        }
      )
    ))
    (expectRegistryReject "provider URL dollar variable accepted" (
      withProvider (provider: provider // { baseUrl = "https://example.invalid/$TOKEN"; })
    ))
    (expectRegistryReject "provider URL env placeholder accepted" (
      withProvider (provider: provider // { baseUrl = "https://example.invalid/{env:TOKEN}"; })
    ))
    (expectRegistryReject "empty provider hosts accepted" (
      withProvider (provider: provider // { hosts = [ ]; })
    ))
    (expectRegistryReject "duplicate provider host accepted" (
      withProvider (
        provider:
        provider
        // {
          hosts = [
            "clio"
            "clio"
          ];
        }
      )
    ))
    (expectRegistryReject "unknown provider host accepted" (
      withProvider (provider: provider // { hosts = [ "unknown" ]; })
    ))
    (expectRegistryReject "model array type accepted" (rawModelRegistry // { models = { }; }))
    (expectRegistryReject "duplicate model route accepted" (
      rawModelRegistry
      // {
        models = rawModelRegistry.models ++ [ (builtins.head rawModelRegistry.models) ];
      }
    ))
    (expectRegistryReject "unknown model field accepted" (
      withModel (model: model // { apiToken = "literal-secret"; })
    ))
    (expectRegistryReject "empty model ID accepted" (withModel (model: model // { id = ""; })))
    (expectRegistryReject "dangling model provider accepted" (
      withModel (model: model // { provider = "missing"; })
    ))
    (expectRegistryReject "zero maximum output accepted" (
      withModel (model: model // { maxOutputTokens = 0; })
    ))
    (expectRegistryReject "negative context limit accepted" (
      withModel (model: model // { contextLimit = -1; })
    ))
    (expectRegistryReject "string output limit accepted" (
      withModel (model: model // { outputLimit = "65536"; })
    ))
    (expectRegistryReject "empty model hosts accepted" (withModel (model: model // { hosts = [ ]; })))
    (expectRegistryReject "duplicate model host accepted" (
      withModel (
        model:
        model
        // {
          hosts = [
            "hera"
            "hera"
          ];
        }
      )
    ))
    (expectRegistryReject "unknown model host accepted" (
      withModel (model: model // { hosts = [ "unknown" ]; })
    ))
    (expectPolicyReject "unknown model policy field accepted" unknownPolicyField)
    (expectPolicyReject "unknown provider policy accepted" unknownProviderPolicy)
    (expectPolicyReject "concrete provider fact accepted in policy" concreteProviderPolicy)
    (expectEqual "providers" (sortedNames modelData.providers) expectedProviders)
    (expectEqual "provider base URLs" (lib.mapAttrs (
      _: provider: provider.baseUrl
    ) modelData.providers) expectedProviderBaseUrls)
    (expectEqual "provider credentials" (lib.mapAttrs (
      _: provider: provider.apiKey
    ) modelData.providers) expectedProviderCredentials)
    (expectEqual "Clio-only remote provider selectors" modelData.providers.llama-cpp-remote.selectors {
      clients = [
        "droid"
        "opencode"
      ];
      hosts = [ "clio" ];
    })
    (expectEqual "sync selection" (removeAttrs modelData.syncInputs [
      "chatUrl"
    ]) rawModelRegistry.selections.default)
    (expectEqual "sync URL uses selected provider" (lib.hasPrefix
      modelData.providers.${modelData.syncInputs.provider}.baseUrl
      modelData.syncInputs.chatUrl
    ) true)
    (expectEqual "Ref URL" catalog.items.mcpServers.Ref.transport.url "https://api.ref.tools/mcp")
    (expectEqual "Ref header" catalog.items.mcpServers.Ref.transport.headers."x-ref-api-key" {
      env = "REF_API_KEY";
    })
    (expectEqual "Context7 URL" catalog.items.mcpServers.context7.transport.url
      "https://mcp.context7.com/mcp"
    )
    (expectEqual "Context7 header" catalog.items.mcpServers.context7.transport.headers.CONTEXT7_API_KEY
      {
        env = "CONTEXT7_API_KEY";
      }
    )
    (expectEqual "MCP transport and override contracts" (lib.mapAttrs (_: server: {
      inherit (server) transport;
      overrides = server.overrides or { };
    }) catalog.items.mcpServers) expectedMcpContracts)
    (expectEqual "client versions" catalog.selectorCoverage.clientVersions expectedClientVersions)
    (expectEqual "adapter versions" catalog.selectorCoverage.adapterVersions expectedAdapterVersions)
    (expectEqual "secret routing" catalog.selectorCoverage.secretRouting expectedSecretRouting)
    (expectEqual "secret capability rows" catalog.selectorCoverage.secretCapabilities
      expectedSecretCapabilities
    )
    (expectEqual "typed environment reference names" (lib.sort builtins.lessThan (
      lib.unique (collectTypedEnvNames canonicalData)
    )) expectedEnvNames)
    (expectEqual "canonical data uses only typed environment references" (lib.any (
      fragment: lib.hasInfix fragment canonicalJson
    ) forbiddenEnvSyntax) false)
    (expectReject "unknown selector key accepted" (
      validateWithItems (withAgentSelector {
        groups = [ "forbidden" ];
      })
    ))
    (expectReject "unknown client accepted" (
      validateWithItems (withAgentSelector {
        clients = [ "unknown" ];
      })
    ))
    (expectReject "unknown audience accepted" (
      validateWithItems (withAgentSelector {
        audiences = [ "unknown" ];
      })
    ))
    (expectReject "unknown host accepted" (
      validateWithItems (withAgentSelector {
        hosts = [ "unknown" ];
      })
    ))
    (expectReject "unknown platform accepted" (
      validateWithItems (withAgentSelector {
        platforms = [ "unknown" ];
      })
    ))
    (expectReject "unknown profile accepted" (
      validateWithItems (withAgentSelector {
        profiles = [ "unknown" ];
      })
    ))
    (expectReject "unknown excluded profile accepted" (
      validateWithItems (withAgentSelector {
        excludeProfiles = [ "unknown" ];
      })
    ))
    (expectReject "duplicate skill name accepted" (validateWithItems duplicateSkillItems))
    (expectReject "unsafe item name accepted" (validateWithItems unsafeItemNameItems))
    (expectReject "duplicate target path accepted" (validateWithItems duplicatePathItems))
    (expectReject "unsupported override field accepted" (validateWithItems badOverrideItems))
    (expectReject "unsupported override client accepted" (validateWithItems badOverrideClientItems))
    (expectReject "multiple MCP transports accepted" (validateWithItems multipleTransportItems))
    (expectReject "missing MCP transport accepted" (validateWithItems zeroTransportItems))
    (expectReject "literal secret accepted" (validateWithItems literalSecretItems))
    (expectReject "secret query accepted" (validateWithItems querySecretItems))
    (expectReject "malformed env name accepted" (validateWithItems malformedEnvItems))
    (expectReject "undeclared env name accepted" (validateWithItems undeclaredEnvItems))
    (expectReject "provider-only environment reference accepted by MCP validation" (
      validateWithItems providerOnlyEnvItems
    ))
    (expectReject "literal access token accepted" (
      validateWithItems (withPalLiteralEnv "ACCESS_TOKEN")
    ))
    (expectReject "literal SSH private key accepted" (
      validateWithItems (withPalLiteralEnv "SSH_PRIVATE_KEY")
    ))
    (expectReject "lowercase literal access token accepted" (
      validateWithItems (withPalLiteralEnv "access_token")
    ))
    (expectReject "literal bearer accepted" (validateWithItems (withPalLiteralEnv "BEARER")))
    (expectReject "literal cookie accepted" (validateWithItems (withPalLiteralEnv "COOKIE")))
    (expectReject "malformed literal env key accepted" (
      validateWithItems (withPalLiteralEnv "BAD-NAME")
    ))
    (expectReject "non-string MCP argument accepted" (validateWithItems nonStringArgItems))
    (expectReject "rendered MCP argument accepted" (
      validateWithItems (withAnvilArg ("$" + "{REF_API_KEY}"))
    ))
    (expectReject "literal token argument accepted" (
      validateWithItems (withAnvilArg "--token=literal-secret")
    ))
    (expectReject "invalid HTTP header name accepted" (validateWithItems badHeaderNameItems))
    (expectReject "malformed override value accepted" (validateWithItems badOverrideValueItems))
    (expectReject "rendered placeholder URL accepted" (validateWithItems renderedUrlItems))
    (expectReject "insecure HTTP MCP URL accepted" (validateWithItems insecureHttpItems))
    (expectReject "missing renderer accepted" (validateWithProfiles missingRendererProfiles))
    (expectReject "filtered default accepted" (validateWithModels filteredDefaultModels))
    (expectReject "anvil-tools accepted" (validateWithItems anvilToolsItems))
  ]
  ++ profileChecks
  ++ reachabilityChecks
  ++ rendererChecks
  ++ task9Checks
  ++ task10Checks
  ++ task11PackageChecks
  ++ task11AiperfChecks;
in
assert builtins.deepSeq contractChecks true;

pkgs.runCommand "ai-home-manager-smoke"
  {
    nativeBuildInputs = [
      pkgs.findutils
      pkgs.jq
      assetCheckPython
    ];
  }
  ''
    python3 "${src}/packages/statusline-command-test.py"

    test -f "${piExtensionSources.pi-mcp-adapter}/package.json"
    test -f "${piExtensionSources.pi-mcp-adapter}/index.ts"
    test -d "${piExtensionSources.pi-mcp-adapter}/node_modules/@modelcontextprotocol/sdk"
    test -d "${piExtensionSources.pi-mcp-adapter}/node_modules/zod"
    test -f "${piExtensionSources.pi-quiet}/package.json"
    test -f "${piExtensionSources.pi-quiet}/src/index.ts"
    test -f "${piExtensionSources.pi-subagent}/package.json"
    test -f "${piExtensionSources.pi-subagent}/index.ts"


    ${lib.optionalString (pkgs.stdenv.hostPlatform.system == "aarch64-darwin") ''
      profile_path="${task9JohnwHera.config.home.path}"
      test -x "$profile_path/bin/claude"
      test -x "$profile_path/bin/claude-real"
      test -x "$profile_path/bin/agent-http-header-bridge"
      test -x "$profile_path/bin/persona"
      grep -Fq 'classify_managed_artifacts' "$profile_path/bin/claude"
      ! grep -Fq 'classify_managed_artifacts' "$profile_path/bin/claude-real"
      test "$(readlink -e "$profile_path/bin/claude")" \
        = "$(readlink -e "${task9WrappedClaude}/bin/claude")"
      test "$(readlink -e "$profile_path/bin/claude-real")" \
        = "$(readlink -e "${task9WrappedClaude}/bin/claude-real")"
      test "$(readlink -e "$profile_path/bin/agent-http-header-bridge")" \
        = "$(readlink -e "${task9HeraBridge}/bin/agent-http-header-bridge")"
      test "$(readlink "${task9JohnwHera.config.home.file.".codex".source}")" \
        = "${task9JohnwHera.config.xdg.configHome}/codex"
      test "$(readlink "${task9JohnwHera.config.home.file.".factory".source}")" \
        = "${task9JohnwHera.config.xdg.configHome}/factory"
      test -f "${task9JohnwHera.config.home.file.".claude/skills/sherlock/SKILL.md".source}"

      droid_command="$("${pkgs.jq}/bin/jq" -er '.mcpServers.Ref.command' \
        "${task9JohnwHera.config.home.file.".config/factory/mcp.json".source}")"
      test "$droid_command" = agent-http-header-bridge

      fixture_home="${task9JohnwHera.config.home.homeDirectory}"
      profile_dir="${task9JohnwHera.config.home.profileDirectory}"
      legacy_bin="$fixture_home/src/scripts"
      rm -rf "$fixture_home"
      mkdir -p "$legacy_bin" "$fixture_home/.config/zsh"
      printf '#!/bin/sh\necho legacy-claude\n' > "$legacy_bin/claude"
      chmod +x "$legacy_bin/claude"
      ln -s "$profile_path" "$profile_dir"
      ln -s "${task9JohnwHera.config.home.file.".zshenv".source}" "$fixture_home/.zshenv"
      ln -s "${task9JohnwHera.config.home.file.".config/zsh/.zshenv".source}" \
        "$fixture_home/.config/zsh/.zshenv"
      ln -s "${task9JohnwHera.config.home.file.".config/zsh/.zprofile".source}" \
        "$fixture_home/.config/zsh/.zprofile"
      env -u __HM_SESS_VARS_SOURCED \
        -u __HM_ZSH_SESS_VARS_SOURCED \
        -u ZDOTDIR \
        TASK9_PROFILE="$profile_dir" \
        TASK9_DROID_COMMAND="$droid_command" \
        HOME="$fixture_home" \
        PATH="/usr/bin:/bin" \
        TERM=dumb \
        "${task9JohnwHera.config.programs.zsh.package}/bin/zsh" -l -c '
          set -eo pipefail
          case "$PATH" in
            "${task9JohnwHera.config.home.profileDirectory}/bin":*) ;;
            *) exit 1 ;;
          esac
          test "$(command -v claude)" = "$TASK9_PROFILE/bin/claude"
          test "$(command -v claude-real)" = "$TASK9_PROFILE/bin/claude-real"
          test "$(command -v "$TASK9_DROID_COMMAND")" \
            = "$TASK9_PROFILE/bin/$TASK9_DROID_COMMAND"
          test "$(command -v persona)" = "$TASK9_PROFILE/bin/persona"
        '
      rm -rf "${task9JohnwHera.config.home.homeDirectory}"

      activation="${task9Evaluations.hera.activationPackage}/activate"
      preflight_line="$(grep -nF '_iNote "Activating %s" "aiManagedPreflight"' "$activation" | head -1 | cut -d: -f1)"
      collision_line="$(grep -nF '_iNote "Activating %s" "checkLinkTargets"' "$activation" | head -1 | cut -d: -f1)"
      boundary_line="$(grep -nF '_iNote "Activating %s" "writeBoundary"' "$activation" | head -1 | cut -d: -f1)"
      links_line="$(grep -nF '_iNote "Activating %s" "linkGeneration"' "$activation" | head -1 | cut -d: -f1)"
      test -n "$preflight_line"
      test "$preflight_line" -lt "$collision_line"
      test "$collision_line" -lt "$boundary_line"
      test "$boundary_line" -lt "$links_line"
    ''}

    python3 -I - "${rendererDocumentManifest}" <<'PY'
    import json
    import subprocess
    import sys
    import tomllib
    from pathlib import Path

    records = json.loads(Path(sys.argv[1]).read_text())
    errors = []

    for record in records:
        label = record["label"]
        document = record["path"]
        if isinstance(document, dict):
            text = document["inlineText"]
        else:
            path = Path(document)
            if not path.is_file():
                errors.append(f"{label}: not a regular file: {path}")
                continue
            text = path.read_text()

        if "sourceDirectory" in record:
            source_directory = Path(record["sourceDirectory"])
            if not source_directory.is_dir():
                errors.append(
                    f"{label}: projection source is not a directory: {source_directory}"
                )
            elif {entry.name for entry in source_directory.iterdir()} != {"SKILL.md"}:
                errors.append(f"{label}: projection directory must contain only SKILL.md")

        for fragment in record.get("forbidden", []):
            if fragment in text:
                errors.append(f"{label}: contains forbidden fragment {fragment!r}")

        if record["kind"] == "json":
            parsed = subprocess.run(
                ["jq", "-e", "."],
                check=False,
                capture_output=True,
                input=text,
                text=True,
            )
            if parsed.returncode:
                errors.append(f"{label}: jq rejected JSON: {parsed.stderr.strip()}")
                continue
            actual = json.loads(text)
            if actual != record["expected"]:
                errors.append(f"{label}: semantic JSON mismatch")
        elif record["kind"] == "toml":
            try:
                actual = tomllib.loads(text)
            except tomllib.TOMLDecodeError as error:
                errors.append(f"{label}: tomllib rejected TOML: {error}")
                continue
            if actual != record["expected"]:
                errors.append(f"{label}: semantic TOML mismatch")
        elif record["kind"] == "text":
            if text != record["expectedText"]:
                errors.append(f"{label}: exact text mismatch")
        elif record["kind"] == "frontmatter":
            if text.startswith("---\n"):
                try:
                    metadata_text, body = text[4:].split("\n---\n", 1)
                    metadata = json.loads(metadata_text)
                except (ValueError, json.JSONDecodeError) as error:
                    errors.append(f"{label}: invalid frontmatter: {error}")
                    continue
            else:
                metadata = {}
                body = text
            if metadata != record["expectedMetadata"]:
                errors.append(f"{label}: semantic frontmatter mismatch")
            if body != record["expectedBody"]:
                errors.append(f"{label}: exact body mismatch")
        else:
            errors.append(f"{label}: unknown fixture kind {record['kind']!r}")

    if errors:
        print("ai-home-manager-smoke: renderer document check failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        raise SystemExit(1)
    PY

    python3 -I - "${src}/config/ai" <<'PY'
    import os
    import re
    import stat
    import sys
    import yaml
    from pathlib import Path

    root = Path(sys.argv[1])

    missing = [
        category
        for category in ("agents", "commands", "skills", "prompts")
        if not (root / category).is_dir()
    ]
    missing.extend(
        name
        for name in (
            "catalog.nix",
            "model-policy.nix",
            "model-registry.json",
            "model-sync.nix",
            "models.nix",
            "preflight.nix",
        )
        if not (root / name).is_file()
    )
    statusline = root / "statusline-command.sh"
    if not statusline.is_file():
        missing.append("statusline")
    if missing:
        print("ai-home-manager-smoke: missing asset categories:", file=sys.stderr)
        for category in missing:
            print(f"  {category}", file=sys.stderr)
        raise SystemExit(1)

    errors = []
    if root.is_symlink():
        errors.append("config/ai must not be a symlink")

    paths = []
    for directory, directories, files in os.walk(root, followlinks=False):
        directories.sort()
        files.sort()
        base = Path(directory)
        paths.extend(base / name for name in directories)
        paths.extend(base / name for name in files)

    resolved_root = root.resolve(strict=True)
    canonical_roots = {
        "agents",
        "commands",
        "skills",
        "prompts",
        "statusline-command.sh",
    }
    asset_paths = [
        path
        for path in paths
        if path.relative_to(root).parts[0] in canonical_roots
    ]

    for path in asset_paths:
        mode = path.lstat().st_mode
        if not (stat.S_ISDIR(mode) or stat.S_ISREG(mode) or stat.S_ISLNK(mode)):
            errors.append(f"unsupported file type: {path.relative_to(root)}")

    for path in paths:
        if not path.is_symlink():
            continue
        try:
            target = path.resolve(strict=True)
            target.relative_to(resolved_root)
        except (OSError, RuntimeError, ValueError) as error:
            errors.append(f"dangling or escaping symlink: {path.relative_to(root)}: {error}")

    if errors:
        print("ai-home-manager-smoke: asset check failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        raise SystemExit(1)

    for path in paths:
        name = path.name.lower()
        if (
            name.startswith(".promptdeploy")
            or name.startswith(".env")
            or "manifest" in name
            or "receipt" in name
            or (name.endswith(".json") and "selector" in name)
        ):
            errors.append(f"forbidden committed artifact: {path.relative_to(root)}")

    renderers = root / "renderers"
    if not renderers.is_dir():
        errors.append("not a renderer directory: renderers")
    else:
        required_renderers = {
            "claude.nix",
            "codex.nix",
            "droid.nix",
            "merge-files.nix",
            "opencode.nix",
            "pi.nix",
        }
        for name in required_renderers:
            if not (renderers / name).is_file():
                errors.append(f"not a regular renderer: renderers/{name}")

    for category in ("agents", "commands", "prompts"):
        entries = list((root / category).iterdir())
        if not entries:
            errors.append(f"empty asset category: {category}")
        for entry in entries:
            if entry.suffix.lower() != ".md" or not entry.is_file():
                errors.append(f"not a Markdown asset: {entry.relative_to(root)}")

    skill_entries = sorted((root / "skills").iterdir(), key=lambda path: path.name)
    if not skill_entries:
        errors.append("empty asset category: skills")
    for skill in skill_entries:
        if not skill.is_dir():
            errors.append(f"not a skill tree: {skill.relative_to(root)}")
            continue

        skill_document = skill / "SKILL.md"
        if not skill_document.is_file():
            errors.append(f"missing SKILL.md: {skill.relative_to(root)}")
            continue

        try:
            lines = skill_document.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeError) as error:
            errors.append(
                f"cannot read UTF-8 skill {skill_document.relative_to(root)}: {error}"
            )
            continue
        if not lines or lines[0].strip() != "---":
            errors.append(f"missing frontmatter: {skill_document.relative_to(root)}")
            continue
        try:
            end = next(
                index
                for index, line in enumerate(lines[1:], start=1)
                if line.strip() == "---"
            )
        except StopIteration:
            errors.append(f"unterminated frontmatter: {skill_document.relative_to(root)}")
            continue
        try:
            metadata = yaml.safe_load("\n".join(lines[1:end]))
        except yaml.YAMLError as error:
            errors.append(
                f"malformed YAML frontmatter: {skill_document.relative_to(root)}: {error}"
            )
            continue
        if not isinstance(metadata, dict):
            errors.append(
                f"frontmatter is not a mapping: {skill_document.relative_to(root)}"
            )
            continue

        name = metadata.get("name")
        description = metadata.get("description")
        if not isinstance(name, str) or not name.strip():
            errors.append(f"missing skill name: {skill_document.relative_to(root)}")
        elif name != skill.name:
            errors.append(
                f"skill name {name!r} does not match directory {skill.name!r}: "
                f"{skill_document.relative_to(root)}"
            )
        if not isinstance(description, str) or not description.strip():
            errors.append(f"missing skill description: {skill_document.relative_to(root)}")

    if not os.access(statusline, os.X_OK):
        errors.append("statusline-command.sh is not executable")

    deployment_field = re.compile(
        r"(?:^|[,{])\s*['\"]?(only|except|droid_deploy)['\"]?\s*:",
        re.MULTILINE,
    )
    for path in paths:
        if path.suffix.lower() != ".md" or not path.is_file():
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeError) as error:
            errors.append(f"cannot read UTF-8 Markdown {path.relative_to(root)}: {error}")
            continue
        if not lines or lines[0].strip() != "---":
            continue
        try:
            end = next(
                index
                for index, line in enumerate(lines[1:], start=1)
                if line.strip() == "---"
            )
        except StopIteration:
            errors.append(f"unterminated frontmatter: {path.relative_to(root)}")
            continue
        match = deployment_field.search("\n".join(lines[1:end]))
        if match:
            errors.append(
                f"deployment field {match.group(1)!r}: {path.relative_to(root)}"
            )

    if errors:
        print("ai-home-manager-smoke: asset check failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        raise SystemExit(1)
    PY

    task10_root="$TMPDIR/task10-model-sync"
    task10_sentinel='TASK10-CREDENTIAL-SENTINEL-DO-NOT-LEAK'
    mkdir -p "$task10_root"

    task10_new_case() {
      label=$1
      task10_case="$task10_root/$label"
      rm -rf "$task10_case"
      mkdir -p "$task10_case/fake/prefs" "$task10_case/xdg-state"
      export TASK10_FAKE_STATE="$task10_case/fake"
      export TASK10_LOG="$task10_case/invocations.log"
      export XDG_STATE_HOME="$task10_case/xdg-state"
      export TASK10_EXPECTED_MODEL='${modelData.syncInputs.model}'
      export TASK10_EXPECTED_URL='${modelData.syncInputs.chatUrl}'
      unset TASK10_FAIL_AT
      : > "$TASK10_LOG"
      : > "$task10_case/stdout"
      : > "$task10_case/stderr"
      printf '%s' "$task10_sentinel" > "$TASK10_FAKE_STATE/devonthink-credential"
      : > "$TASK10_FAKE_STATE/iterm-key-metadata"
      task10_stamp="$XDG_STATE_HOME/nix-managed-ai/model-sync-v1.sha256"
    }

    task10_assert_redacted() {
      for output in "$TASK10_LOG" "$task10_case/stdout" "$task10_case/stderr"; do
        ! grep -Fq "$task10_sentinel" "$output"
      done
      test '${task10Digest}' != "$task10_sentinel"
      test '${task10ChangedDigest}' != "$task10_sentinel"
      if [ -e "$task10_stamp" ] && [ ! -d "$task10_stamp" ]; then
        ! grep -Fq "$task10_sentinel" "$task10_stamp"
      fi
      ! find "$TASK10_FAKE_STATE/prefs" -type f -exec grep -Fq "$task10_sentinel" {} \; \
        -print | grep -q .
    }

    task10_run_ok() {
      "$1" > "$task10_case/stdout" 2> "$task10_case/stderr"
      task10_assert_redacted
    }

    task10_run_fail() {
      if "$1" > "$task10_case/stdout" 2> "$task10_case/stderr"; then
        echo "Task 10 expected failure: $task10_case" >&2
        exit 1
      fi
      task10_assert_redacted
    }

    task10_assert_exact_app_calls() {
      ${pkgs.python3}/bin/python3 - \
        "$TASK10_LOG" "$TASK10_EXPECTED_MODEL" "$TASK10_EXPECTED_URL" <<'PY'
    import os
    import sys

    log_path, model, url = sys.argv[1:]
    with open(log_path, encoding="utf-8") as stream:
        calls = [tuple(line.rstrip("\n").split("\t")) for line in stream]

    defaults = sorted(call[1:] for call in calls if call[0] == "defaults")
    devon = "com.devon-technologies.think"
    iterm = "com.googlecode.iterm2"
    writes = [
        ("write", devon, "ChatEngine", "-int", "2"),
        ("write", devon, "ChatModel-OpenAI (Compatible)", "-string", model),
        ("write", devon, "OpenAI (Compatible)URL", "-string", url),
        ("write", devon, "ChatSummaryEngine", "-int", "2"),
        ("write", devon, "ChatSummaryModel", "-string", model),
        ("write", iterm, "UseRecommendedAIModel", "-bool", "false"),
        ("write", iterm, "AiModel", "-string", model),
        ("write", iterm, "AITermAPI", "-int", "1"),
        ("write", iterm, "AitermURL", "-string", url),
        ("write", iterm, "AIVendor", "-int", "2"),
    ]
    expected_defaults = sorted(
        writes + [("read", domain, key) for _, domain, key, _, _ in writes]
    )
    if defaults != expected_defaults:
        raise SystemExit(
            f"defaults allowlist mismatch:\nactual={defaults!r}\n"
            f"expected={expected_defaults!r}"
        )

    expected_security = (
        "find-generic-password",
        "-s",
        "iTerm2 API Keys",
        "-a",
        "OpenAI API Key for iTerm2",
    )
    security = [call[1:] for call in calls if call[0] == "security"]
    if security != [expected_security, expected_security]:
        raise SystemExit(f"security metadata calls mismatch: {security!r}")

    probes = [call[1:] for call in calls if call[0] == "devonthinkKeyPresent"]
    if probes != [(), ()]:
        raise SystemExit(f"DEVONthink Boolean probes mismatch: {probes!r}")

    pgrep = [call[1:] for call in calls if call[0] == "pgrep"]
    expected_pgrep = [
        ("-x", "DEVONthink"),
        ("-x", "DEVONthink 3"),
        ("-x", "iTerm2"),
    ]
    if pgrep != expected_pgrep:
        raise SystemExit(f"process guard calls mismatch: {pgrep!r}")

    state_dir = os.path.join(os.environ["XDG_STATE_HOME"], "nix-managed-ai")
    stamp = os.path.join(state_dir, "model-sync-v1.sha256")
    expected_exact = {
        "mkdir": [("-p", "--", state_dir)],
        "mktemp": [(stamp + ".tmp.XXXXXX",)],
        "rm": [],
    }
    for tool, expected in expected_exact.items():
        actual = [call[1:] for call in calls if call[0] == tool]
        if actual != expected:
            raise SystemExit(f"{tool} calls mismatch: {actual!r}")

    moves = [call[1:] for call in calls if call[0] == "mv"]
    if len(moves) != 1:
        raise SystemExit(f"mv call count mismatch: {moves!r}")
    move = moves[0]
    if (
        len(move) != 4
        or move[:2] != ("-fT", "--")
        or not move[2].startswith(stamp + ".tmp.")
        or move[3] != stamp
    ):
        raise SystemExit(f"atomic mv shape mismatch: {move!r}")

    expected_tools = {
        "defaults",
        "devonthinkKeyPresent",
        "mkdir",
        "mktemp",
        "mv",
        "pgrep",
        "security",
    }
    actual_tools = {call[0] for call in calls}
    if actual_tools != expected_tools:
        raise SystemExit(f"successful tool inventory mismatch: {actual_tools!r}")
    PY
    }

    # First run writes only the ten approved fields, verifies them, and stamps.
    task10_new_case first
    task10_run_ok '${task10Script}'
    test "$(cat "$task10_stamp")" = '${task10Digest}'
    task10_assert_exact_app_calls
    test -z "$(find "$(dirname "$task10_stamp")" -name 'model-sync-v1.sha256.tmp.*' -print)"

    # The digest fast path invokes no parameterized tool at all.
    : > "$TASK10_LOG"
    task10_run_ok '${task10Script}'
    test ! -s "$TASK10_LOG"
    test "$(cat "$task10_stamp")" = '${task10Digest}'

    # A corrupt multi-line stamp is never accepted as an unchanged digest.
    printf '%s\n' corrupt-trailing-line >> "$task10_stamp"
    : > "$TASK10_LOG"
    task10_run_ok '${task10Script}'
    test "$(cat "$task10_stamp")" = '${task10Digest}'
    task10_assert_exact_app_calls

    # A changed nonsecret selection updates once and replaces the digest.
    : > "$TASK10_LOG"
    export TASK10_EXPECTED_MODEL='${alternateModelData.syncInputs.model}'
    export TASK10_EXPECTED_URL='${alternateModelData.syncInputs.chatUrl}'
    task10_run_ok '${task10ChangedScript}'
    test "$(cat "$task10_stamp")" = '${task10ChangedDigest}'
    task10_assert_exact_app_calls

    # Every guarded process independently defers before credentials or writes.
    task10_process_index=0
    for process_name in DEVONthink 'DEVONthink 3' iTerm2; do
      task10_process_index=$((task10_process_index + 1))
      task10_new_case "running-$task10_process_index"
      printf '%s' "$process_name" > "$TASK10_FAKE_STATE/running"
      task10_run_ok '${task10Script}'
      test ! -e "$task10_stamp"
      grep -Fq \
        'nix-managed model sync: deferred while DEVONthink or iTerm2 is running' \
        "$task10_case/stderr"
      ! grep -Eq $'^(defaults|devonthinkKeyPresent|security)\t' "$TASK10_LOG"
      grep -Fq "pgrep	-x	$process_name" "$TASK10_LOG"
    done

    # An indeterminate process check fails closed.
    task10_new_case pgrep-error
    export TASK10_FAIL_AT=pgrep-error
    task10_run_fail '${task10Script}'
    test ! -e "$task10_stamp"
    ! grep -Eq $'^(defaults|devonthinkKeyPresent|security)\t' "$TASK10_LOG"

    # Missing credential-presence metadata blocks before any preference write.
    task10_new_case missing-devonthink-key
    rm "$TASK10_FAKE_STATE/devonthink-credential"
    task10_run_fail '${task10Script}'
    test ! -e "$task10_stamp"
    ! grep -Fq $'defaults\twrite\t' "$TASK10_LOG"

    task10_new_case missing-iterm-key
    rm "$TASK10_FAKE_STATE/iterm-key-metadata"
    task10_run_fail '${task10Script}'
    test ! -e "$task10_stamp"
    ! grep -Fq $'defaults\twrite\t' "$TASK10_LOG"

    # Failure in the first updater never starts the second updater or stamps.
    task10_new_case first-updater-failure
    export TASK10_FAIL_AT=devonthink-update
    task10_run_fail '${task10Script}'
    test ! -e "$task10_stamp"
    ! grep -Fq $'defaults\twrite\tcom.googlecode.iterm2\t' "$TASK10_LOG"

    # Failure in the second updater preserves the old stamp; retry succeeds.
    task10_new_case second-updater-failure
    mkdir -p "$(dirname "$task10_stamp")"
    printf '%s' stale-digest > "$task10_stamp"
    export TASK10_FAIL_AT=iterm-update
    task10_run_fail '${task10Script}'
    test "$(cat "$task10_stamp")" = stale-digest
    grep -Fq $'defaults\twrite\tcom.devon-technologies.think\t' "$TASK10_LOG"
    grep -Fq $'defaults\twrite\tcom.googlecode.iterm2\t' "$TASK10_LOG"
    unset TASK10_FAIL_AT
    : > "$TASK10_LOG"
    task10_run_ok '${task10Script}'
    test "$(cat "$task10_stamp")" = '${task10Digest}'
    task10_assert_exact_app_calls

    # Readback failure also preserves the old digest and retries cleanly.
    task10_new_case verification-failure
    mkdir -p "$(dirname "$task10_stamp")"
    printf '%s' old-digest > "$task10_stamp"
    export TASK10_FAIL_AT=iterm-verify
    task10_run_fail '${task10Script}'
    test "$(cat "$task10_stamp")" = old-digest
    unset TASK10_FAIL_AT
    : > "$TASK10_LOG"
    task10_run_ok '${task10Script}'
    test "$(cat "$task10_stamp")" = '${task10Digest}'

    # Failed atomic replacement preserves the old stamp and removes its temp.
    task10_new_case rename-failure
    mkdir -p "$(dirname "$task10_stamp")"
    printf '%s' '${task10Digest}' > "$task10_stamp"
    export TASK10_EXPECTED_MODEL='${alternateModelData.syncInputs.model}'
    export TASK10_EXPECTED_URL='${alternateModelData.syncInputs.chatUrl}'
    export TASK10_FAIL_AT=rename
    task10_run_fail '${task10ChangedScript}'
    test "$(cat "$task10_stamp")" = '${task10Digest}'
    test -z "$(find "$(dirname "$task10_stamp")" -name 'model-sync-v1.sha256.tmp.*' -print)"
    grep -Fq $'mv\t-fT\t--\t' "$TASK10_LOG"
    grep -Fq $'rm\t-f\t--\t' "$TASK10_LOG"

    unset TASK10_FAIL_AT
    : > "$TASK10_LOG"
    task10_run_ok '${task10ChangedScript}'
    test "$(cat "$task10_stamp")" = '${task10ChangedDigest}'
    test -z "$(find "$(dirname "$task10_stamp")" -name 'model-sync-v1.sha256.tmp.*' -print)"

    touch "$out"
  ''
