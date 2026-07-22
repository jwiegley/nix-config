{ pkgs, src }:

let
  inherit (pkgs) lib;

  modelData = import "${src}/config/ai/models.nix" { };
  catalog = import "${src}/config/ai/catalog.nix" {
    inherit lib modelData;
    resources = "/agent-resources";
  };

  sortedNames = set: lib.sort builtins.lessThan (builtins.attrNames set);
  expectEqual =
    label: actual: expected:
    if actual == expected then true else throw label;
  expectReject =
    label: value:
    if (builtins.tryEval (builtins.deepSeq value true)).success then throw label else true;

  selectFor = profileId: itemSet: catalog.select catalog.profiles.${profileId} itemSet;
  selectedNames = profileId: category: sortedNames (selectFor profileId catalog.items.${category});
  selectedProviders = profileId: selectFor profileId modelData.providers;
  selectedModels =
    profileId:
    let
      profile = catalog.profiles.${profileId};
      providers = selectedProviders profileId;
    in
    lib.filterAttrs (
      _name: model:
      builtins.hasAttr model.provider providers && catalog.matches profile (model.selectors or { })
    ) modelData.models;
  selectedModelNames = profileId: sortedNames (selectedModels profileId);
  selectedModelHash =
    profileId: builtins.hashString "sha256" (builtins.toJSON (selectedModelNames profileId));

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
        ANTHROPIC_DEFAULT_HAIKU_MODEL = "claude-sonnet-4-6";
        CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "80";
        CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
        CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
        CLAUDE_CODE_MAX_OUTPUT_TOKENS = "64000";
        CLAUDE_CODE_NO_FLICKER = "1";
        CLAUDE_CODE_SUBAGENT_MODEL = "claude-fable-5";
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
      model = "claude-fable-5";
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
  expectedSourceRecords = {
    sha256 = "bd686f3423475bbf86d7de8ea83ef697565f2df8475abd18e438cf94850240d4";
    agents = 26;
    commands = 65;
    discoveredSkills = 19;
    prompts = 2;
    settings = 1;
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

  personalCommands = [
    "assess"
    "bankruptcy"
    "breakdown"
    "bugbot"
    "bugbot-stack"
    "capture"
    "code-review"
    "commit"
    "deep-review"
    "discover-bundles"
    "eliminate-dead-code"
    "expense-report"
    "fess"
    "fix"
    "fix-alert"
    "fix-ci"
    "fix-github-issue"
    "fix-integration"
    "fix-transcript"
    "flaky-rust"
    "gravity"
    "halt"
    "infer-tasks"
    "initialize"
    "install-service"
    "journal"
    "lefthook"
    "markdown"
    "medium"
    "meeting-notes"
    "narrative"
    "nix-rebuild"
    "partner-cleanup"
    "partner-collaborator"
    "partner-reviewer"
    "prepare-with"
    "process-checklist"
    "productize"
    "proofread"
    "push"
    "query-builder"
    "quick-review"
    "rebase"
    "rebase-and-fix"
    "recommit"
    "remove-service"
    "report"
    "resolve"
    "respond"
    "restack"
    "review-github-pr"
    "run-orchestrator"
    "sec-audit"
    "sitrep"
    "smooth"
    "teams"
    "transcribe-image"
    "webfix"
    "wiggum"
  ];
  positronCommands = [
    "assess"
    "bankruptcy"
    "breakdown"
    "bugbot"
    "bugbot-stack"
    "cleanup"
    "code-review"
    "commit"
    "deep-review"
    "discover-bundles"
    "eliminate-dead-code"
    "fess"
    "fix"
    "fix-ci"
    "fix-github-issue"
    "fix-transcript"
    "flaky-rust"
    "forge"
    "gravity"
    "halt"
    "heavy"
    "infer-tasks"
    "initialize"
    "journal"
    "lefthook"
    "markdown"
    "medium"
    "meeting-notes"
    "narrative"
    "nix-rebuild"
    "partner-cleanup"
    "partner-collaborator"
    "partner-reviewer"
    "prepare-with"
    "process-checklist"
    "productize"
    "proofread"
    "push"
    "query-builder"
    "quick-review"
    "rebase"
    "rebase-and-fix"
    "recommit"
    "report"
    "resolve"
    "respond"
    "restack"
    "retest"
    "retest-categorical"
    "review-github-pr"
    "run-orchestrator"
    "sec-audit"
    "sitrep"
    "smooth"
    "teams"
    "transcribe-image"
    "tron-debug"
    "wiggum"
  ];
  broadSkills = [
    "anvil"
    "brainstorming"
    "caveman"
    "comment-audit"
    "dispatching-parallel-agents"
    "eliminate-dead-code"
    "executing-plans"
    "finishing-a-development-branch"
    "fix-all"
    "fix-transcript"
    "git-surgeon"
    "it-voice"
    "johnw"
    "nixos"
    "node-red"
    "parallelize"
    "persian"
    "ponytail"
    "ponytail-audit"
    "ponytail-debt"
    "ponytail-gain"
    "ponytail-help"
    "ponytail-review"
    "receiving-code-review"
    "requesting-code-review"
    "skill-creator"
    "subagent-driven-development"
    "swiftui"
    "systematic-debugging"
    "test-driven-development"
    "toolkit"
    "translate-en"
    "using-git-worktrees"
    "using-superpowers"
    "verification-before-completion"
    "wiggum"
    "writing-plans"
    "writing-skills"
  ];

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
      commands = 59;
      skills = 39;
      mcpServers = claudePersonalMcp;
      hooks = claudeHooks;
      marketplaces = claudeMarketplaces;
      models = 0;
      hasDefault = false;
    };
    "clio-claude-positron" = {
      commands = 58;
      skills = 40;
      mcpServers = claudeMcp;
      hooks = claudeHooks;
      marketplaces = claudeMarketplaces;
      models = 0;
      hasDefault = false;
    };
    "clio-codex" = {
      commands = 59;
      skills = 38;
      mcpServers = baseMcp;
      hooks = codexHooks;
      marketplaces = [ ];
      models = 0;
      hasDefault = false;
    };
    "clio-opencode" = {
      commands = 59;
      skills = 38;
      mcpServers = personalOpenCodeMcp;
      hooks = [ ];
      marketplaces = [ ];
      models = 81;
      modelHash = "7e658d57ea24da18e172d473ff6c6f2cef456e41b0456d22747013672e83f051";
      hasDefault = true;
    };
    "hera-claude-personal" = {
      commands = 59;
      skills = 39;
      mcpServers = claudePersonalMcp;
      hooks = claudeHooks;
      marketplaces = claudeMarketplaces;
      models = 0;
      hasDefault = false;
    };
    "hera-claude-positron" = {
      commands = 58;
      skills = 40;
      mcpServers = claudeMcp;
      hooks = claudeHooks;
      marketplaces = claudeMarketplaces;
      models = 0;
      hasDefault = false;
    };
    "hera-codex" = {
      commands = 59;
      skills = 38;
      mcpServers = baseMcp;
      hooks = codexHooks;
      marketplaces = [ ];
      models = 0;
      hasDefault = false;
    };
    "hera-droid" = {
      commands = 2;
      skills = 38;
      mcpServers = droidMcp;
      hooks = [ ];
      marketplaces = [ ];
      models = 87;
      modelHash = "fc7f339312782066a7444b79bc909f81ce55e2828550e9610ded47ab03e44394";
      hasDefault = false;
    };
    "hera-opencode" = {
      commands = 59;
      skills = 38;
      mcpServers = personalOpenCodeMcp;
      hooks = [ ];
      marketplaces = [ ];
      models = 80;
      modelHash = "9faaba3cf26377b1a9d1e0ea96a57176aef6b3343ed1308a0ad6e583cccf5537";
      hasDefault = true;
    };
    "hera-pi" = {
      commands = 59;
      skills = 38;
      mcpServers = baseMcp;
      hooks = [ ];
      marketplaces = [ ];
      models = 87;
      modelHash = "fc7f339312782066a7444b79bc909f81ce55e2828550e9610ded47ab03e44394";
      hasDefault = false;
    };
    "shared-work-claude-positron" = {
      commands = 58;
      skills = 40;
      mcpServers = claudeMcp;
      hooks = claudeHooks;
      marketplaces = claudeMarketplaces;
      models = 0;
      hasDefault = false;
    };
    "shared-work-codex" = {
      commands = 65;
      skills = 39;
      mcpServers = baseMcp;
      hooks = codexHooks;
      marketplaces = [ ];
      models = 0;
      hasDefault = false;
    };
    "shared-work-opencode-positron" = {
      commands = 58;
      skills = 39;
      mcpServers = baseMcp;
      hooks = [ ];
      marketplaces = [ ];
      models = 57;
      modelHash = "b6f1fd6e19a8f7b7ea10f702878a4e1e8fc8245b6e7e4bb9561a0b24fb482af5";
      hasDefault = true;
    };
    "vps-claude-personal" = {
      commands = 59;
      skills = 39;
      mcpServers = claudeMcp;
      hooks = claudeHooks;
      marketplaces = claudeMarketplaces;
      models = 0;
      hasDefault = false;
    };
    "vulcan-claude-personal" = {
      commands = 59;
      skills = 39;
      mcpServers = vulcanClaudeMcp;
      hooks = claudeHooks;
      marketplaces = claudeMarketplaces;
      models = 0;
      hasDefault = false;
    };
    "vulcan-opencode" = {
      commands = 59;
      skills = 38;
      mcpServers = vulcanOpenCodeMcp;
      hooks = [ ];
      marketplaces = [ ];
      models = 10;
      modelHash = "28b3b03aa19e5161ea6ddb93f175eef7fa6cb6ddda64c948e730a984f5de5fba";
      hasDefault = false;
    };
  };

  profileChecks = lib.concatLists (
    lib.mapAttrsToList (
      profileId: expected:
      [
        (expectEqual (profileId + " agents") (builtins.length (selectedNames profileId "agents")) 26)
        (expectEqual (profileId + " commands") (builtins.length (
          selectedNames profileId "commands"
        )) expected.commands)
        (expectEqual (profileId + " skills") (builtins.length (
          selectedNames profileId "skills"
        )) expected.skills)
        (expectEqual (profileId + " prompts") (selectedNames profileId "prompts") [
          "emacs"
          "spanish"
        ])
        (expectEqual (profileId + " MCP") (selectedNames profileId "mcpServers") expected.mcpServers)
        (expectEqual (profileId + " hooks") (selectedNames profileId "hooks") expected.hooks)
        (expectEqual (
          profileId + " marketplaces"
        ) (selectedNames profileId "marketplaces") expected.marketplaces)
        (expectEqual (profileId + " settings") (selectedNames profileId "settings") (
          lib.optional (catalog.profiles.${profileId}.client == "claude") "settings"
        ))
        (expectEqual (profileId + " models") (builtins.length (
          selectedModelNames profileId
        )) expected.models)
        (expectEqual (
          profileId + " default"
        ) (builtins.hasAttr profileId modelData.profileDefaults) expected.hasDefault)
      ]
      ++ lib.optional (expected ? modelHash) (
        expectEqual (profileId + " model hash") (selectedModelHash profileId) expected.modelHash
      )
    ) profileExpectations
  );

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
  literalProviderSecretModels = modelData // {
    providers = modelData.providers // {
      litellm = modelData.providers.litellm // {
        apiKey = "literal-secret";
      };
    };
  };
  providerQuerySecretModels = modelData // {
    providers = modelData.providers // {
      litellm = modelData.providers.litellm // {
        baseUrl = "https://litellm.vulcan.lan/v1/?apiKey=literal-secret";
      };
    };
  };
  providerRenderedUrlModels = modelData // {
    providers = modelData.providers // {
      litellm = modelData.providers.litellm // {
        baseUrl = "https://litellm.vulcan.lan/" + "$" + "{LITELLM_API_KEY}";
      };
    };
  };
  providerHttpDowngradeModels = modelData // {
    providers = modelData.providers // {
      litellm = modelData.providers.litellm // {
        baseUrl = "http://litellm.vulcan.lan/v1/";
      };
    };
  };
  badPublicSentinelModels = modelData // {
    providers = modelData.providers // {
      llama-cpp-local = modelData.providers.llama-cpp-local // {
        apiKey.nonSecret = "literal-secret";
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

  contractChecks = [
    (expectEqual "canonical validation" (catalog.validate candidate) true)
    (expectEqual "profile IDs" (sortedNames catalog.profiles) expectedProfileIds)
    (expectEqual "profile expectation coverage" (sortedNames profileExpectations) expectedProfileIds)
    (expectEqual "profile root coverage" (lib.mapAttrs (
      _: profile: profile.root
    ) catalog.profiles) expectedProfileRoots)
    (expectEqual "canonical settings item" catalog.items.settings.settings expectedSettingsItem)
    (expectEqual "legacy selector ledger" catalog.selectorCoverage.legacySelectors
      expectedLegacySelectors
    )
    (expectEqual "source record ledger" catalog.selectorCoverage.sourceRecords expectedSourceRecords)
    (expectEqual "legacy target ledger" catalog.selectorCoverage.legacyTargets expectedLegacyTargets)
    (expectEqual "unmanaged exclusion ledger" catalog.selectorCoverage.unmanagedExclusions
      expectedUnmanagedExclusions
    )
    (expectEqual "personal command set" (selectedNames "hera-claude-personal" "commands")
      personalCommands
    )
    (expectEqual "positron command set" (selectedNames "hera-claude-positron" "commands")
      positronCommands
    )
    (expectEqual "shared Codex union" (selectedNames "shared-work-codex" "commands") (
      sortedNames catalog.items.commands
    ))
    (expectEqual "Droid command projections" (selectedNames "hera-droid" "commands") [
      "discover-bundles"
      "restack"
    ])
    (expectEqual "broad skill set" (selectedNames "hera-codex" "skills") broadSkills)
    (expectEqual "personal Claude skills" (selectedNames "hera-claude-personal" "skills") (
      lib.sort builtins.lessThan (broadSkills ++ [ "forge" ])
    ))
    (expectEqual "positron Claude skills" (selectedNames "hera-claude-positron" "skills") (
      lib.sort builtins.lessThan (
        broadSkills
        ++ [
          "forge"
          "retest"
        ]
      )
    ))
    (expectEqual "shared Codex skills" (selectedNames "shared-work-codex" "skills") (
      lib.sort builtins.lessThan (broadSkills ++ [ "retest" ])
    ))
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
    (expectEqual "model pair count" (builtins.length (sortedNames modelData.models)) 111)
    (expectEqual "model pair key hash" (builtins.hashString "sha256" (
      builtins.toJSON (sortedNames modelData.models)
    )) "71d39c94a5dc7781336fe763b1ed4fa8a39915a21de72acfa9bcf94cda9cad82")
    (expectEqual "sync inputs" modelData.syncInputs {
      chatUrl = "https://litellm.vulcan.lan/v1/chat/completions";
      model = "hera/omlx/Qwen3.6-27B-oQ4e-mtp";
      provider = "litellm";
    })
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
    (expectReject "duplicate target path accepted" (validateWithItems duplicatePathItems))
    (expectReject "unsupported override field accepted" (validateWithItems badOverrideItems))
    (expectReject "unsupported override client accepted" (validateWithItems badOverrideClientItems))
    (expectReject "multiple MCP transports accepted" (validateWithItems multipleTransportItems))
    (expectReject "missing MCP transport accepted" (validateWithItems zeroTransportItems))
    (expectReject "literal secret accepted" (validateWithItems literalSecretItems))
    (expectReject "secret query accepted" (validateWithItems querySecretItems))
    (expectReject "malformed env name accepted" (validateWithItems malformedEnvItems))
    (expectReject "undeclared env name accepted" (validateWithItems undeclaredEnvItems))
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
    (expectReject "literal provider secret accepted" (validateWithModels literalProviderSecretModels))
    (expectReject "provider query secret accepted" (validateWithModels providerQuerySecretModels))
    (expectReject "provider rendered URL accepted" (validateWithModels providerRenderedUrlModels))
    (expectReject "provider HTTP downgrade accepted" (validateWithModels providerHttpDowngradeModels))
    (expectReject "unapproved public sentinel accepted" (validateWithModels badPublicSentinelModels))
    (expectReject "anvil-tools accepted" (validateWithItems anvilToolsItems))
  ]
  ++ profileChecks;
in
assert builtins.deepSeq contractChecks true;

pkgs.runCommand "ai-home-manager-smoke"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    python3 -I - "${src}/config/ai" <<'PY'
    import hashlib
    import os
    import re
    import stat
    import sys
    from pathlib import Path

    root = Path(sys.argv[1])

    agents = set(
        """
        bash-reviewer coq-reviewer cpp-pro cpp-reviewer elisp-reviewer
        emacs-lisp-pro fess-auditor haskell-pro haskell-reviewer nix-pro
        nix-reviewer perf-reviewer persian-translator prd-architect
        prompt-engineer python-pro python-reviewer rocq-pro rust-pro
        rust-reviewer security-reviewer sql-pro task-breakdown typescript-pro
        typescript-reviewer web-searcher
        """.split()
    )
    commands = set(
        """
        assess bankruptcy breakdown bugbot bugbot-stack capture cleanup
        code-review commit deep-review discover-bundles eliminate-dead-code
        expense-report fess fix fix-alert fix-ci fix-github-issue
        fix-integration fix-transcript flaky-rust forge gravity halt heavy
        infer-tasks initialize install-service journal lefthook markdown medium
        meeting-notes narrative nix-rebuild partner-cleanup
        partner-collaborator partner-reviewer prepare-with process-checklist
        productize proofread push query-builder quick-review rebase
        rebase-and-fix recommit remove-service report resolve respond restack
        retest retest-categorical review-github-pr run-orchestrator sec-audit
        sitrep smooth teams transcribe-image tron-debug webfix wiggum
        """.split()
    )
    skills = set(
        """
        anvil caveman comment-audit eliminate-dead-code fix-all fix-transcript
        forge it-voice johnw nixos node-red parallelize persian retest
        skill-creator swiftui toolkit wiggum
        """.split()
    )

    assert len(agents) == 26
    assert len(commands) == 65
    assert len(skills) == 18

    missing = [
        category
        for category in ("agents", "commands", "skills", "prompts")
        if not (root / category).is_dir()
    ]
    missing.extend(
        name for name in ("catalog.nix", "models.nix") if not (root / name).is_file()
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

    # Bind every canonical asset path, type, executable bit, symlink target, and byte.
    records = []
    for path in asset_paths:
        relative = path.relative_to(root).as_posix().encode()
        mode = path.lstat().st_mode
        if stat.S_ISDIR(mode):
            fields = (relative, b"d", b"-", b"", b"0", b"")
        elif stat.S_ISREG(mode):
            data = path.read_bytes()
            fields = (
                relative,
                b"f",
                b"x" if mode & 0o111 else b"-",
                b"",
                str(len(data)).encode(),
                hashlib.sha256(data).hexdigest().encode(),
            )
        elif stat.S_ISLNK(mode):
            target = os.fsencode(os.readlink(path))
            fields = (
                relative,
                b"l",
                b"-",
                target,
                str(len(target)).encode(),
                hashlib.sha256(target).hexdigest().encode(),
            )
        else:
            errors.append(f"unsupported file type: {path.relative_to(root)}")
            continue
        records.append((relative, b"\0".join(fields) + b"\0"))

    asset_digest = hashlib.sha256(
        b"".join(record for _, record in sorted(records))
    ).hexdigest()
    expected_asset_digest = (
        "422c4e45bc09b660118f3f3651f7fbce632ec07dbc678105c323ab5cb74e1768"
    )
    if asset_digest != expected_asset_digest:
        errors.append(
            f"config/ai recursive digest mismatch: {asset_digest} "
            f"!= {expected_asset_digest}"
        )

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

    expected = {
        "agents": {f"{name}.md" for name in agents},
        "commands": {f"{name}.md" for name in commands},
        "skills": skills,
        "prompts": {"emacs.md", "spanish.md"},
    }
    expected_root = set(expected) | {
        "catalog.nix",
        "models.nix",
        "statusline-command.sh",
    }
    actual_root = {entry.name for entry in root.iterdir()}
    if actual_root != expected_root:
        errors.append(
            "config/ai inventory mismatch: "
            f"missing={sorted(expected_root - actual_root)!r} "
            f"unexpected={sorted(actual_root - expected_root)!r}"
        )

    for category, wanted in expected.items():
        directory = root / category
        actual = {entry.name for entry in directory.iterdir()}
        if actual != wanted:
            errors.append(
                f"{category} inventory mismatch: "
                f"missing={sorted(wanted - actual)!r} "
                f"unexpected={sorted(actual - wanted)!r}"
            )

    for category in ("agents", "commands", "prompts"):
        for name in expected[category]:
            if not (root / category / name).is_file():
                errors.append(f"not a regular file: {category}/{name}")

    for name in skills:
        skill = root / "skills" / name
        if not skill.is_dir():
            errors.append(f"not a skill tree: skills/{name}")
        elif not (skill / "SKILL.md").is_file():
            errors.append(f"missing SKILL.md: skills/{name}")

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

    touch "$out"
  ''
