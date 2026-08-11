{
  lib,
  llmAgents,
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
  renderLib = import "${src}/config/ai/renderers/render-lib.nix" { inherit lib; };
  inherit (renderLib) renderMarkdownText;
  reject = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
  withMcpServers = mcpServers: catalog.items // { inherit mcpServers; };
  withoutFessCommand = catalog.items // {
    commands = builtins.removeAttrs catalog.items.commands [ "fess" ];
  };
  baseAgentMetadata = catalog.items.agents.bash-reviewer.metadata;
  itemsWithAgentMetadata =
    metadata:
    catalog.items
    // {
      agents = catalog.items.agents // {
        bash-reviewer = catalog.items.agents.bash-reviewer // {
          inherit metadata;
        };
      };
    };
  claudeSettings = catalog.items.settings.claude;
  withClaudeSettingsBase =
    base:
    catalog.items
    // {
      settings.claude = claudeSettings // {
        inherit base;
      };
    };
  escapedModelIdentifier = builtins.fromJSON "\"claude-opus-5\\u001b[1m\"";
  c1CsiModelIdentifier = builtins.fromJSON "\"model\\u009b1m\"";
  c1OscModelIdentifier = builtins.fromJSON "\"model\\u009dtitle\"";
  profiles = builtins.attrValues catalog.profiles;
  localModelEndpointsFor =
    profile:
    if profile.localModelRoutes then catalog.localModelEndpointsByHost.${profile.host} else null;
  profileFor =
    client:
    lib.findFirst (profile: profile.client == client) (throw "${client} profile missing") profiles;
  claudeProfiles = lib.filter (profile: profile.client == "claude") profiles;
  syntheticClaudeProfile = catalog.profiles.hera-claude-personal // {
    id = "synthetic-claude-personal";
  };
  notificationSelectionCases = [
    {
      name = "all dimensions match";
      profile = syntheticClaudeProfile;
      expected = true;
    }
    {
      name = "client differs";
      profile = syntheticClaudeProfile // {
        id = "synthetic-codex-personal";
        client = "codex";
      };
      expected = false;
    }
    {
      name = "host differs";
      profile = syntheticClaudeProfile // {
        id = "synthetic-remote-claude-personal";
        host = "vps";
        platform = "linux";
      };
      expected = false;
    }
    {
      name = "audience differs";
      profile = syntheticClaudeProfile // {
        id = "synthetic-claude-positron";
        audiences = [ "positron" ];
      };
      expected = false;
    }
  ];
  piProfiles = lib.filter (profile: profile.client == "pi") profiles;
  claudeProfile = profileFor "claude";
  codexProfile = profileFor "codex";
  piProfile = profileFor "pi";
  droidProfile = profileFor "droid";
  primeProfile = profileFor "prime";
  stdioMcp = lib.findFirst (server: server.transport ? command) (throw "stdio MCP server missing") (
    builtins.attrValues catalog.items.mcpServers
  );
  syntheticHttpMcp = stdioMcp // {
    transport.url = "https://example.invalid/mcp";
    selectors.profiles = [ ];
  };
  unsupportedHttpHeader = syntheticHttpMcp // {
    transport = syntheticHttpMcp.transport // {
      headers.Authorization.env = "OPENAI_API_KEY";
    };
  };
  mismatchedStdioEnvironment = stdioMcp // {
    transport = stdioMcp.transport // {
      env.SYNTHETIC_TOKEN.env = "OPENAI_API_KEY";
    };
  };
  missingHttpUrl = syntheticHttpMcp // {
    transport = { };
  };
  safeArgumentValues = [
    "--header=X-Request-ID:request-42"
    "MODE=stdio"
    "--max-tokens=42"
    "--token-count=42"
    "--authorization-mode=none"
    "--no-auth"
    "--label=secret"
  ];
  safeArguments = map (public: { inherit public; }) safeArgumentValues ++ [
    { protectedFile = "/run/secrets/service-token"; }
  ];
  syntheticArgumentMcp = {
    selectors.clients = [
      "claude"
      "codex"
      "droid"
      "pi"
    ];
    transport = {
      command = "synthetic-mcp";
      args = safeArguments;
    };
  };
  withSyntheticArguments =
    args:
    withMcpServers (
      catalog.items.mcpServers
      // {
        synthetic-arguments = syntheticArgumentMcp // {
          transport = syntheticArgumentMcp.transport // {
            inherit args;
          };
        };
      }
    );
  safeArgumentItems = withSyntheticArguments safeArguments;
  unsafeArgumentLists = [
    [ "--stdio" ]
    [ "-HAuthorization:credential-sentinel" ]
    [
      "--api-key"
      "credential-sentinel"
    ]
    [
      "-H"
      "Authorization: credential-sentinel"
    ]
    [ "--CrEdEnTiAlS=credential-sentinel" ]
    [ "wrapper=--api-key=credential-sentinel" ]
    [ "sh -c=curl -HAuthorization:credential-sentinel" ]
    [ "OPENAI_API_KEY=credential-sentinel" ]
    [ "--auth=credential-sentinel" ]
    [ "--set=api.key=credential-sentinel" ]
    [ "--set=api..key=credential-sentinel" ]
    [ "--set=api%2Dkey=credential-sentinel" ]
    [ "--set=api%252Dkey=credential-sentinel" ]
    [ { env = "OPENAI_API_KEY"; } ]
    [ { protectedFile = "/tmp/credential-sentinel"; } ]
    [ { protectedFile = "/run/secrets/../credential-sentinel"; } ]
    [
      {
        public = "ordinary";
        unexpected = "field";
      }
    ]
  ];
  selectFrom = items: profile: lib.mapAttrs (_: itemSet: catalog.select profile itemSet) items;
  selectFor = selectFrom catalog.items;
  selectWithHttp =
    profile:
    let
      selected = selectFor profile;
    in
    selected
    // {
      mcpServers = selected.mcpServers // {
        synthetic-http = syntheticHttpMcp;
      };
    };
  adversarialName = "metadata-probe";
  adversarialDescription = ''
    Colon: value # not a comment
    --- &anchor *alias
    Quotes: "double" and 'single'; scalars: null true 2026-08-10
    Unicode: café 模型; JSON: {"nested":[1,2]}
  '';
  adversarialAgent = catalog.items.agents.fess-auditor // {
    metadata = {
      name = adversarialName;
      description = adversarialDescription;
    };
    selectors = { };
  };
  adversarialCommand = catalog.items.commands.assess // {
    metadata.description = adversarialDescription;
    selectors = { };
  };
  selectAdversarialFor =
    profile:
    let
      selected = selectFor profile;
    in
    selected
    // {
      agents = {
        metadata-probe = adversarialAgent;
      };
      commands = {
        metadata-probe = adversarialCommand;
      };
      prompts = { };
      skills = { };
    };
  renderSelectedFor =
    renderer: profile: homeDirectory: selected:
    renderer (
      {
        inherit
          profile
          homeDirectory
          selected
          ;
        xdgConfigHome = "${homeDirectory}/.config";
      }
      //
        lib.optionalAttrs
          (builtins.elem profile.client [
            "codex"
            "pi"
            "prime"
          ])
          {
            localModelEndpoints = localModelEndpointsFor profile;
          }
    );
  renderFor =
    renderer: profile: homeDirectory:
    renderSelectedFor renderer profile homeDirectory (selectWithHttp profile);
  codexRenderer = import "${src}/config/ai/renderers/codex.nix" {
    inherit lib pkgs llmAgents;
  };
  codexRendered = renderFor codexRenderer codexProfile "/Users/test";
  codexAdversarialRendered = renderSelectedFor codexRenderer codexProfile "/Users/test" (
    selectAdversarialFor codexProfile
  );
  claudeRenderer = import "${src}/config/ai/renderers/claude.nix" {
    inherit lib;
    pkgs = rendererPkgs;
  };
  renderClaude =
    profile:
    let
      homeDirectory = if profile.platform == "darwin" then "/Users/test" else "/home/test";
    in
    {
      inherit profile;
      rendered = claudeRenderer {
        inherit profile homeDirectory;
        selected = selectWithHttp profile;
        xdgConfigHome = "${homeDirectory}/.config";
      };
    };
  claudeRenderings = map renderClaude claudeProfiles;
  claudeAdversarialRendered = claudeRenderer {
    profile = claudeProfile;
    selected = selectAdversarialFor claudeProfile;
    homeDirectory = "/Users/test";
    xdgConfigHome = "/Users/test/.config";
  };
  piRenderer = import "${src}/config/ai/renderers/pi.nix" {
    inherit lib;
    pkgs = rendererPkgs;
  };
  mcpRegistryRenderer = import "${src}/config/ai/renderers/mcp-registry.nix" {
    inherit lib;
    pkgs = rendererPkgs;
  };
  renderMcpRegistryFor =
    profile: items:
    mcpRegistryRenderer {
      projection = catalog.sharedMcpRegistryFor {
        profiles = [ profile ];
        inherit items;
      };
      homeDirectory = "/Users/test";
      xdgConfigHome = "/Users/test/.config";
    };
  renderPi =
    profile:
    let
      darwin = profile.platform == "darwin";
      homeDirectory = if darwin then "/Users/test" else "/home/test";
      localModelEndpoints = localModelEndpointsFor profile;
    in
    {
      inherit profile darwin localModelEndpoints;
      rendered = piRenderer {
        inherit profile homeDirectory localModelEndpoints;
        selected = selectWithHttp profile;
        xdgConfigHome = "${homeDirectory}/.config";
        passwordStoreDir = if darwin then "${homeDirectory}/doc/.password-store" else null;
        gnupgHome = if darwin then "${homeDirectory}/.config/gnupg" else null;
      };
    };
  piRenderings = map renderPi piProfiles;
  piAdversarialRendered = piRenderer {
    profile = piProfile;
    selected = selectAdversarialFor piProfile;
    homeDirectory = "/Users/test";
    xdgConfigHome = "/Users/test/.config";
    passwordStoreDir = "/Users/test/doc/.password-store";
    gnupgHome = "/Users/test/.config/gnupg";
    localModelEndpoints = localModelEndpointsFor piProfile;
  };
  droidRenderer = import "${src}/config/ai/renderers/droid.nix" {
    inherit lib;
    pkgs = rendererPkgs;
  };
  droidRendered = renderFor droidRenderer droidProfile "/Users/test";
  droidAdversarialRendered = renderSelectedFor droidRenderer droidProfile "/Users/test" (
    selectAdversarialFor droidProfile
  );
  primeRenderer = import "${src}/config/ai/renderers/prime.nix" {
    inherit lib;
    pkgs = rendererPkgs;
  };
  primeRendered = renderFor primeRenderer primeProfile "/Users/test";
  primeAdversarialRendered = renderSelectedFor primeRenderer primeProfile "/Users/test" (
    selectAdversarialFor primeProfile
  );
  capabilityProbeName = "capability-probe";
  primaryCapabilities = [
    "read-files"
    "run-commands"
  ];
  reorderedCapabilities = [
    "run-commands"
    "read-files"
  ];
  discoveryCapabilities = [
    "find-files"
    "search-text"
  ];
  capabilityAgent =
    capabilities:
    catalog.items.agents.bash-reviewer
    // {
      metadata = baseAgentMetadata // {
        inherit capabilities;
        name = capabilityProbeName;
      };
      selectors = { };
    };
  selectWithCapabilities =
    profile: capabilities:
    selectFor profile
    // {
      agents = {
        "${capabilityProbeName}" = capabilityAgent capabilities;
      };
    };
  renderPiSelected =
    selected:
    piRenderer {
      profile = piProfile;
      inherit selected;
      homeDirectory = "/Users/test";
      xdgConfigHome = "/Users/test/.config";
      passwordStoreDir = "/Users/test/doc/.password-store";
      gnupgHome = "/Users/test/.config/gnupg";
      localModelEndpoints = localModelEndpointsFor piProfile;
    };
  capabilityRendering =
    capabilities:
    let
      claude = renderSelectedFor claudeRenderer claudeProfile "/Users/test" (
        selectWithCapabilities claudeProfile capabilities
      );
      codex = renderSelectedFor codexRenderer codexProfile "/Users/test" (
        selectWithCapabilities codexProfile capabilities
      );
      droid = renderSelectedFor droidRenderer droidProfile "/Users/test" (
        selectWithCapabilities droidProfile capabilities
      );
      pi = renderPiSelected (selectWithCapabilities piProfile capabilities);
      prime = renderSelectedFor primeRenderer primeProfile "/Users/test" (
        selectWithCapabilities primeProfile capabilities
      );
    in
    {
      claude = claude.files."${claudeProfile.root}/agents/${capabilityProbeName}.md".text;
      codex = codex.files."${codexProfile.root}/agents/${capabilityProbeName}.toml".source;
      droid = droid.files."${droidProfile.root}/droids/${capabilityProbeName}.md".text;
      pi = pi.files."${piProfile.root}/agents/${capabilityProbeName}.md".text;
      prime = prime.files."${primeProfile.root}/prompts/agent-${capabilityProbeName}.md".text;
    };
  frontMatter = text: builtins.fromJSON (builtins.elemAt (lib.splitString "\n" text) 1);
  primaryRendering = capabilityRendering primaryCapabilities;
  reorderedRendering = capabilityRendering reorderedCapabilities;
  discoveryRendering = capabilityRendering discoveryCapabilities;
  safeSelectedFor = selectFrom safeArgumentItems;
  unsafeRenderedSources =
    args:
    let
      selectedFor = selectFrom (withSyntheticArguments args);
    in
    [
      (builtins.toString
        (renderSelectedFor claudeRenderer claudeProfile "/Users/test" (selectedFor claudeProfile))
        .files."${claudeProfile.root}/nix-managed-mcp.json".source
      )
      (builtins.toString
        (renderSelectedFor codexRenderer codexProfile "/Users/test" (selectedFor codexProfile))
        .files."${codexProfile.root}/nix-managed.config.toml".source
      )
      (builtins.toString
        (renderSelectedFor droidRenderer droidProfile "/Users/test" (selectedFor droidProfile))
        .files."${droidProfile.root}/mcp.json".source
      )
      (builtins.toString
        (renderMcpRegistryFor piProfile (withSyntheticArguments args)).files.".config/mcp/mcp.json".source
      )
    ];
  safeClaudeRendered = renderSelectedFor claudeRenderer claudeProfile "/Users/test" (
    safeSelectedFor claudeProfile
  );
  safeCodexRendered = renderSelectedFor codexRenderer codexProfile "/Users/test" (
    safeSelectedFor codexProfile
  );
  safeDroidRendered = renderSelectedFor droidRenderer droidProfile "/Users/test" (
    safeSelectedFor droidProfile
  );
  safeMcpRegistryRendered = renderMcpRegistryFor piProfile safeArgumentItems;
  httpMcpRegistryRendered = renderMcpRegistryFor piProfile (
    withMcpServers (
      catalog.items.mcpServers
      // {
        synthetic-http = syntheticHttpMcp // {
          selectors.clients = [ "pi" ];
        };
      }
    )
  );
  fessSource = catalog.items.agents.fess-auditor.source;
  fessText = builtins.readFile fessSource;
  hasFessRubric = text: lib.hasInfix "**Fallback smuggling**" text;
  parallelizeSource = catalog.items.skills.parallelize.source;
  validatedReviewSource = catalog.items.skills.validated-code-review.source;
  nodeRedSource = catalog.items.skills.node-red.source;
  nodeRedSkillText = builtins.readFile "${nodeRedSource}/SKILL.md";
  nodeRedApiReferenceText = builtins.readFile "${nodeRedSource}/references/api_reference.md";
  nodeRedContractTexts = [
    nodeRedSkillText
    nodeRedApiReferenceText
  ];
  nodeRedAdminCommands = [
    "node-red-admin flows get"
    "node-red-admin flow get FLOW_ID"
    "node-red-admin flow put FLOW_ID < flow.json"
  ];
  nodeRedForbiddenHelperForms = [
    "node-red-admin list"
    "node-red-admin get"
    "node-red-admin put"
    "node-red-admin create"
    "node-red-admin delete"
    "node-red-admin flows put"
    "node-red-admin flow create"
    "node-red-admin flow delete"
    "sudo node-red-admin"
    "sudo -u node-red-admin"
  ];
  hasNodeRedAdminContract =
    text: builtins.all (command: lib.hasInfix command text) nodeRedAdminCommands;
  parallelizeText = builtins.readFile "${parallelizeSource}/SKILL.md";
  validatedReviewText = builtins.readFile "${validatedReviewSource}/SKILL.md";
  noHistoryContractTexts = map builtins.readFile [
    fessSource
    "${src}/config/ai/commands/alexey.md"
    "${src}/config/ai/commands/deep-review.md"
    "${src}/config/ai/commands/heavy-review.md"
    "${src}/config/ai/skills/wiggum/SKILL.md"
    "${src}/config/ai/skills/wiggum/references/fess-audit.md"
  ];
  fessPaths = {
    codex = {
      agent = "${codexProfile.root}/agents/fess-auditor.toml";
      command = ".agents/skills/command-fess";
    };
    droid = {
      agent = "${droidProfile.root}/droids/fess-auditor.md";
      command = "${droidProfile.root}/skills/fess";
    };
    pi = {
      agent = ".config/pi/agent/agents/fess-auditor.md";
      command = ".config/pi/agent/prompts/fess.md";
    };
    prime = {
      agent = "${primeProfile.root}/prompts/agent-fess-auditor.md";
      command = "${primeProfile.root}/prompts/fess.md";
    };
  };
  frontmatterCase = name: document: expectedMetadata: {
    inherit name document;
    expected = pkgs.writeText "${name}-frontmatter.json" (builtins.toJSON expectedMetadata);
    expectedPrefix = pkgs.writeText "${name}-frontmatter-prefix" (
      renderMarkdownText expectedMetadata ""
    );
  };
  frontmatterTextCase =
    name: text: expectedMetadata:
    frontmatterCase name (pkgs.writeText "${name}-frontmatter.md" text) expectedMetadata;
  frontmatterCases = [
    (frontmatterTextCase "claude-agent"
      claudeAdversarialRendered.files."${claudeProfile.root}/agents/${adversarialName}.md".text
      adversarialAgent.metadata
    )
    (frontmatterCase "codex-command"
      "${codexAdversarialRendered.files.".agents/skills/command-${adversarialName}".source}/SKILL.md"
      {
        name = "command-${adversarialName}";
        description = adversarialDescription;
      }
    )
    (frontmatterTextCase "droid-agent"
      droidAdversarialRendered.files."${droidProfile.root}/droids/${adversarialName}.md".text
      adversarialAgent.metadata
    )
    (frontmatterTextCase "pi-agent"
      piAdversarialRendered.files.".config/pi/agent/agents/${adversarialName}.md".text
      adversarialAgent.metadata
    )
    (frontmatterTextCase "prime-agent"
      primeAdversarialRendered.files."${primeProfile.root}/prompts/agent-${adversarialName}.md".text
      {
        description = adversarialDescription;
        argument-hint = "[task]";
      }
    )
    (frontmatterTextCase "claude-agent-capabilities" primaryRendering.claude (
      builtins.removeAttrs baseAgentMetadata [ "capabilities" ]
      // {
        name = capabilityProbeName;
        tools = "Read, Bash";
      }
    ))
    (frontmatterTextCase "droid-agent-capabilities" primaryRendering.droid (
      builtins.removeAttrs baseAgentMetadata [ "capabilities" ]
      // {
        name = capabilityProbeName;
        tools = [
          "Read"
          "Execute"
        ];
      }
    ))
    (frontmatterTextCase "pi-agent-capabilities" primaryRendering.pi (
      builtins.removeAttrs baseAgentMetadata [ "capabilities" ]
      // {
        name = capabilityProbeName;
        tools = "read,bash";
      }
    ))
  ];
  frontmatterPython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]);
  frontmatterChecker = pkgs.writeText "check-frontmatter.py" ''
    import json
    import pathlib
    import sys

    import yaml

    case, document_name, expected_name, expected_prefix_name = sys.argv[1:]
    document = pathlib.Path(document_name).read_text(encoding="utf-8")
    expected_prefix = pathlib.Path(expected_prefix_name).read_text(encoding="utf-8")
    if not document.startswith(expected_prefix):
        raise SystemExit(f"{case}: document does not use the shared frontmatter renderer")
    lines = document.splitlines()
    if not lines or lines[0] != "---":
        raise SystemExit(f"{case}: missing opening frontmatter delimiter")
    try:
        end = lines.index("---", 1)
    except ValueError as error:
        raise SystemExit(f"{case}: missing closing frontmatter delimiter") from error
    actual = yaml.safe_load("\n".join(lines[1:end]))
    with open(expected_name, encoding="utf-8") as expected_file:
        expected = json.load(expected_file)
    if actual != expected:
        raise SystemExit(f"{case}: parsed metadata differs: {actual!r} != {expected!r}")
  '';
in
assert catalog.validate { };
assert builtins.all (
  case:
  let
    selected = catalog.select case.profile catalog.items.settings;
  in
  (selected ? claude-personal-workstation-notifications) == case.expected
) notificationSelectionCases;
assert builtins.all (name: catalog.profiles.${name}.id == name) (
  builtins.attrNames catalog.profiles
);
assert builtins.all (name: catalog.items.agents.${name}.metadata.name == name) (
  builtins.attrNames catalog.items.agents
);
assert catalog.validate {
  items = itemsWithAgentMetadata (baseAgentMetadata // { capabilities = primaryCapabilities; });
};
assert catalog.validate {
  items = itemsWithAgentMetadata (baseAgentMetadata // { capabilities = reorderedCapabilities; });
};
assert catalog.validate {
  items = itemsWithAgentMetadata (baseAgentMetadata // { capabilities = discoveryCapabilities; });
};
assert (frontMatter primaryRendering.claude).tools == "Read, Bash";
assert (frontMatter discoveryRendering.claude).tools == "Grep, Glob";
assert
  (frontMatter primaryRendering.droid).tools == [
    "Read"
    "Execute"
  ];
assert
  (frontMatter discoveryRendering.droid).tools == [
    "Grep"
    "Glob"
  ];
assert (frontMatter primaryRendering.pi).tools == "read,bash";
assert (frontMatter discoveryRendering.pi).tools == "grep,find";
assert primaryRendering.claude == reorderedRendering.claude;
assert primaryRendering.droid == reorderedRendering.droid;
assert primaryRendering.pi == reorderedRendering.pi;
assert primaryRendering.prime == reorderedRendering.prime;
assert lib.hasInfix "Catalog tool policy (advisory in Prime Agent): Read, Bash"
  primaryRendering.prime;
assert lib.hasInfix "Catalog tool policy (advisory in Prime Agent): Grep, Glob"
  discoveryRendering.prime;
assert !(builtins.pathExists "${src}/config/ai/commands/fess.md");
assert catalog.items.commands.fess.source == fessSource;
assert lib.hasInfix ''fork_turns="none"'' parallelizeText;
assert lib.hasInfix "verify-history-isolation.py" parallelizeText;
assert !(lib.hasInfix "Each subagent starts fresh with none of your context" parallelizeText);
assert builtins.all (
  text: lib.hasInfix "explicit no-history" text && lib.hasInfix "parent-history sentinel" text
) noHistoryContractTexts;
assert lib.hasInfix "mcp__pal__chat" validatedReviewText;
assert lib.hasInfix "metadata.model_used" validatedReviewText;
assert lib.hasInfix "Do not use `mcp__pal__clink`" validatedReviewText;
assert lib.hasInfix "--expect MODEL" validatedReviewText;
assert builtins.all (phrase: lib.hasInfix phrase validatedReviewText) [
  "every roster entry, `--distinct`"
  "reviewer and verifier, `--distinct`"
  "every roster entry and `--distinct`"
];
assert builtins.all (invocation: lib.hasInfix invocation fessText) [
  "Claude Code: `/fess`"
  "Codex: `$command-fess`"
  "Factory Droid: `/fess`"
  "Pi: `/fess`"
  "Prime Agent: `/fess`"
];
assert builtins.all (
  profile:
  let
    selected = selectFor profile;
  in
  selected.agents ? fess-auditor
  && selected.commands ? fess
  && selected.agents.fess-auditor.source == selected.commands.fess.source
) profiles;
assert claudeSettings.base.model == "claude-opus-5[1m]";
assert catalog.validate {
  items = withClaudeSettingsBase (
    claudeSettings.base
    // {
      model = "provider/model@revision";
      env = claudeSettings.base.env // {
        ANTHROPIC_DEFAULT_HAIKU_MODEL = "opus[1m]";
        CLAUDE_CODE_SUBAGENT_MODEL = "sonnet[1m]";
      };
    }
  );
};
assert claudeRenderings != [ ];
assert catalog.validate {
  items = withClaudeSettingsBase (claudeSettings.base // { model = "café/模型@版本"; });
};
assert builtins.all (profile: (selectFor profile).mcpServers ? pal) profiles;
# The home-level endpoint table is one authority shared by both workstations.
assert
  builtins.attrNames catalog.localModelEndpointsByHost == [
    "clio"
    "hera"
  ];
assert catalog.localModelEndpointsByHost.clio == catalog.localModelEndpointsByHost.hera;
# Profile opt-ins drive generated codex TOML, pi local provider wiring, prime
# model overrides, and the dummy-key session variables. Pin the set so a
# gained or lost route is a visible test edit.
assert
  lib.sort builtins.lessThan (
    builtins.attrNames (lib.filterAttrs (_: profile: profile.localModelRoutes) catalog.profiles)
  ) == [
    "clio-codex"
    "clio-pi"
    "hera-codex"
    "hera-pi"
    "hera-prime"
  ];
assert catalog.validate {
  items = withMcpServers (catalog.items.mcpServers // { synthetic-http = syntheticHttpMcp; });
};
assert catalog.validate { items = safeArgumentItems; };
assert builtins.all (
  args: reject (catalog.validate { items = withSyntheticArguments args; })
) unsafeArgumentLists;
assert builtins.all (args: builtins.all reject (unsafeRenderedSources args)) unsafeArgumentLists;
assert builtins.all (
  entry:
  let
    files = entry.rendered.files;
    root = entry.profile.root;
  in
  hasFessRubric files."${root}/agents/fess-auditor.md".text
  && hasFessRubric files."${root}/commands/fess.md".text
) claudeRenderings;
assert builtins.hasAttr fessPaths.codex.agent codexRendered.files;
assert builtins.hasAttr fessPaths.codex.command codexRendered.files;
assert hasFessRubric droidRendered.files.${fessPaths.droid.agent}.text;
assert builtins.hasAttr fessPaths.droid.command droidRendered.files;
assert builtins.all hasNodeRedAdminContract nodeRedContractTexts;
assert builtins.all (
  text: builtins.all (form: !(lib.hasInfix form text)) nodeRedForbiddenHelperForms
) nodeRedContractTexts;
assert droidRendered.files."${droidProfile.root}/skills/node-red".source == nodeRedSource;
assert piRenderings != [ ];
assert builtins.hasAttr "${droidProfile.root}/mcp.json" droidRendered.files;
assert builtins.all (
  entry:
  let
    files = entry.rendered.files;
  in
  builtins.hasAttr ".config/pi/agent/models.json" files
  && !(builtins.hasAttr ".config/mcp/mcp.json" files)
  && hasFessRubric files.${fessPaths.pi.agent}.text
  && hasFessRubric files.${fessPaths.pi.command}.text
  && (builtins.hasAttr ".config/pi/agent/model-router.json" files) == entry.darwin
  && !(entry.rendered ? mutableMcpGuard)
) piRenderings;
assert
  let
    prompt = primeRendered.files.${fessPaths.prime.agent}.text;
  in
  lib.hasInfix "Read the immutable specialist role at `" prompt
  && lib.hasInfix "-fess-auditor.md` in full" prompt;
assert hasFessRubric primeRendered.files.${fessPaths.prime.command}.text;
assert !(builtins.hasAttr ".config/mcp/mcp.json" primeRendered.files);
assert !(primeRendered ? mutableMcpGuard);
assert builtins.all reject [
  (catalog.validate {
    items = itemsWithAgentMetadata (baseAgentMetadata // { capabilities = "read-files"; });
  })
  (catalog.validate {
    items = itemsWithAgentMetadata (
      baseAgentMetadata
      // {
        capabilities = [
          "read-files"
          "read-files"
        ];
      }
    );
  })
  (catalog.validate {
    items = itemsWithAgentMetadata (baseAgentMetadata // { capabilities = [ "unknown-capability" ]; });
  })
  (catalog.validate {
    items = itemsWithAgentMetadata (baseAgentMetadata // { capabilities = [ ]; });
  })
  (catalog.validate {
    items = itemsWithAgentMetadata (
      builtins.removeAttrs baseAgentMetadata [ "capabilities" ] // { tools = "Read, Grep, Glob, Bash"; }
    );
  })
  (catalog.validate { items = withoutFessCommand; })
  (catalog.validate {
    items = catalog.items // {
      commands = catalog.items.commands // {
        fess = catalog.items.commands.fess // {
          source = catalog.items.commands.cleanup.source;
        };
      };
    };
  })
  (catalog.validate {
    items = withClaudeSettingsBase (claudeSettings.base // { model = "claude-opus-5[1m"; });
  })
  (catalog.validate {
    items = withClaudeSettingsBase (claudeSettings.base // { model = escapedModelIdentifier; });
  })
  (catalog.validate {
    items = withClaudeSettingsBase (claudeSettings.base // { model = "model[1~"; });
  })
  (catalog.validate {
    items = withClaudeSettingsBase (claudeSettings.base // { model = "model[1 q"; });
  })
  (catalog.validate {
    items = withClaudeSettingsBase (claudeSettings.base // { model = c1CsiModelIdentifier; });
  })
  (catalog.validate {
    items = withClaudeSettingsBase (claudeSettings.base // { model = c1OscModelIdentifier; });
  })
  (catalog.validate {
    items = withClaudeSettingsBase (
      claudeSettings.base
      // {
        env = claudeSettings.base.env // {
          CLAUDE_CODE_SUBAGENT_MODEL = "claude-opus-5[1m";
        };
      }
    );
  })
  (catalog.validate {
    localModelEndpointsByHost = builtins.removeAttrs catalog.localModelEndpointsByHost [ "clio" ];
  })
  (catalog.validate {
    profiles = catalog.profiles // {
      clio-codex = catalog.profiles.clio-codex // {
        localModelEndpoints = catalog.localModelEndpointsByHost.clio;
      };
    };
  })
  (catalog.validate {
    profiles = catalog.profiles // {
      shared-work-pi = catalog.profiles.shared-work-pi // {
        localModelRoutes = true;
      };
    };
  })
  (piRenderer {
    profile = piProfile;
    selected = selectFor piProfile;
    homeDirectory = "/Users/test";
    xdgConfigHome = "/Users/test/.config";
    passwordStoreDir = "/Users/test/doc/.password-store";
    gnupgHome = "/Users/test/.config/gnupg";
    localModelEndpoints = null;
  })
  (catalog.validate {
    items = withClaudeSettingsBase (
      claudeSettings.base
      // {
        env = claudeSettings.base.env // {
          CLAUDE_CODE_SUBAGENT_MODEL = "claude-opus-5\n";
        };
      }
    );
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { "../synthetic-http" = syntheticHttpMcp; });
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { synthetic-http = unsupportedHttpHeader; });
  })
  (catalog.validate {
    items = withMcpServers (
      catalog.items.mcpServers // { synthetic-stdio = mismatchedStdioEnvironment; }
    );
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { synthetic-http = missingHttpUrl; });
  })
  (piRenderer {
    profile = piProfile // {
      client = "unsupported";
    };
    selected = selectFor piProfile;
    homeDirectory = "/Users/test";
    xdgConfigHome = "/Users/test/.config";
    passwordStoreDir = "/Users/test/doc/.password-store";
    gnupgHome = "/Users/test/.config/gnupg";
    localModelEndpoints = localModelEndpointsFor piProfile;
  })
];
pkgs.runCommand "ai-catalog-transport" { } ''
  history_contract=${parallelizeSource}/scripts/verify-history-isolation.py
  model_contract=${validatedReviewSource}/scripts/verify-model-dispatch.py
  test -x "$history_contract"
  test -x "$model_contract"
  ${pkgs.python3}/bin/python3 ${./review-dispatch-contract.py} \
    "$history_contract" "$model_contract"

  ${pkgs.python3}/bin/python3 - ${nodeRedSource} <<'PY'
  import re
  import sys
  from pathlib import Path

  root = Path(sys.argv[1])
  documents = [
      root / "SKILL.md",
      root / "references" / "api_reference.md",
  ]
  commands = {
      "node-red-admin flows get",
      "node-red-admin flow get FLOW_ID",
      "node-red-admin flow put FLOW_ID < flow.json",
  }
  contract_markers = (
      "trusted, authorized Node-RED flow author",
      "authorized but sensitive output",
      "operating-system sandbox",
      "fixed loopback",
      "direct flow-file access",
      "nodered.vulcan.lan",
      r"[0-9a-f]{1,32}(?:\.[0-9a-f]{1,32})?\Z",
      '"flows":[{"id":',
      '"ok":true,"id":"FLOW_ID"',
      "normalized without field loss",
      "1 MiB",
      "8 MiB",
      "10-second",
      "15-second",
      "`-h` and `--help`",
  )
  allowed_invocations = commands | {
      'node-red-admin flows get > "$workdir/flows.json"',
      'node-red-admin flow get "$flow_id" > "$workdir/before.json"',
      'node-red-admin flow put "$flow_id" < "$workdir/updated.json" > "$workdir/ack.json"',
      'node-red-admin flow get "$flow_id" > "$workdir/after.json"',
  }

  for document in documents:
      text = document.read_text(encoding="utf-8")
      missing = sorted(
          marker for marker in commands | set(contract_markers) if marker not in text
      )
      if missing:
          raise SystemExit(f"{document.relative_to(root)}: missing contract markers: {missing}")
      for line_number, line in enumerate(text.splitlines(), 1):
          invocation = line.strip()
          if invocation.startswith("node-red-admin ") and invocation not in allowed_invocations:
              raise SystemExit(
                  f"{document.relative_to(root)}:{line_number}: "
                  f"undocumented helper invocation {invocation!r}"
              )

  literal_forbidden = {
      "runtime credential path": b"/run/secrets/node-red-admin-token",
      "raw admin header": b"Authorization:",
      "raw bearer scheme": b"Bearer",
      "internal runtime port": b":1880",
  }
  regex_forbidden = {
      "raw admin header spelling": re.compile(rb"\bauthorization\s*:", re.IGNORECASE),
      "command-line HTTP client": re.compile(rb"\bcurl\b", re.IGNORECASE),
      "direct credential read": re.compile(
          rb"(?:\bcat\b|\bopen\s*\(|\bread_(?:text|bytes)\s*\(|"
          rb"\bbuiltins\.readFile\b)[^\r\n]{0,256}(?:token|/run/secrets/)",
          re.IGNORECASE,
      ),
      "Python HTTP client": re.compile(
          rb"(?:\b(?:requests|httpx)\s*\.\s*(?:get|post|put|delete|patch|request)\s*\("
          rb"|\burllib\.request\s*\.\s*(?:urlopen|Request)\s*\("
          rb"|\bhttp\.client\s*\.\s*HTTPS?Connection\s*\("
          rb"|\baiohttp\s*\.\s*ClientSession\s*\("
          rb"|\burllib3\s*\."
          rb"|\bfrom\s+(?:requests|httpx|urllib\.request|http\.client|aiohttp|urllib3)\s+import\b"
          rb"|\bimport\s+(?:requests|httpx|urllib\.request|http\.client|aiohttp|urllib3)\b)",
          re.IGNORECASE,
      ),
      "direct admin URL": re.compile(
          rb"https?://(?:localhost|127\.0\.0\.1|node-?red\.vulcan\.lan|"
          rb"nodered\.vulcan\.lan)(?::[0-9]+)?/"
          rb"(?:flows?|auth|nodes|context|settings|projects|inject|diagnostics)(?:[/\s\"']|$)",
          re.IGNORECASE,
      ),
  }

  for path in sorted(root.rglob("*")):
      if not path.is_file():
          continue
      data = path.read_bytes()
      for label, fragment in literal_forbidden.items():
          if fragment in data:
              raise SystemExit(f"{path.relative_to(root)}: contains {label}")
      for label, pattern in regex_forbidden.items():
          if pattern.search(data):
              raise SystemExit(f"{path.relative_to(root)}: contains {label}")
  PY

  ${pkgs.diffutils}/bin/cmp ${primaryRendering.codex} ${reorderedRendering.codex}
  if ${pkgs.gnugrep}/bin/grep -Eq '^(capabilities|tools) = ' ${primaryRendering.codex}; then
    echo "Codex unexpectedly rendered catalog agent policy" >&2
    exit 1
  fi

  grep -F 'base_url = "${catalog.localModelEndpointsByHost.${codexProfile.host}.omlx}"' \
    ${codexRendered.files."${codexProfile.root}/nix-managed.config.toml".source} >/dev/null
  grep -F 'base_url = "${catalog.localModelEndpointsByHost.${codexProfile.host}.llama-swap}"' \
    ${codexRendered.files."${codexProfile.root}/nix-managed.config.toml".source} >/dev/null
  ${lib.concatMapStringsSep "\n" (
    case:
    "${frontmatterPython}/bin/python ${frontmatterChecker} ${
      lib.escapeShellArgs [
        case.name
        (toString case.document)
        (toString case.expected)
        (toString case.expectedPrefix)
      ]
    }"
  ) frontmatterCases}

  ${pkgs.python3}/bin/python3 - ${
    codexRendered.files."${codexProfile.root}/nix-managed.config.toml".source
  } <<'PY'
  import sys
  import tomllib

  with open(sys.argv[1], "rb") as stream:
      mcp = tomllib.load(stream)["mcp_servers"]
  assert mcp["synthetic-http"] == {"url": "https://example.invalid/mcp"}
  assert isinstance(mcp["pal"]["command"], str)
  assert isinstance(mcp["pal"]["args"], list)
  PY

  grep -F '**Fallback smuggling**' ${codexRendered.files.${fessPaths.codex.agent}.source} >/dev/null
  grep -F '**Fallback smuggling**' ${
    codexRendered.files.${fessPaths.codex.command}.source
  }/SKILL.md >/dev/null
  grep -F '**Fallback smuggling**' ${
    droidRendered.files.${fessPaths.droid.command}.source
  }/SKILL.md >/dev/null
  ${pkgs.python3}/bin/python3 - \
    ${safeClaudeRendered.files."${claudeProfile.root}/nix-managed-mcp.json".source} \
    ${safeCodexRendered.files."${codexProfile.root}/nix-managed.config.toml".source} \
    ${safeDroidRendered.files."${droidProfile.root}/mcp.json".source} \
    ${safeMcpRegistryRendered.files.".config/mcp/mcp.json".source} <<'PY'
  import json
  import sys
  import tomllib

  expected = [
      "--header=X-Request-ID:request-42",
      "MODE=stdio",
      "--max-tokens=42",
      "--token-count=42",
      "--authorization-mode=none",
      "--no-auth",
      "--label=secret",
      "/run/secrets/service-token",
  ]
  paths = sys.argv[1:]
  with open(paths[0], encoding="utf-8") as stream:
      claude = json.load(stream)
  with open(paths[1], "rb") as stream:
      codex = tomllib.load(stream)
  with open(paths[2], encoding="utf-8") as stream:
      droid = json.load(stream)
  with open(paths[3], encoding="utf-8") as stream:
      pi = json.load(stream)

  rendered = [
      claude["mcpServers"]["synthetic-arguments"]["args"],
      codex["mcp_servers"]["synthetic-arguments"]["args"],
      droid["mcpServers"]["synthetic-arguments"]["args"],
      pi["mcpServers"]["synthetic-arguments"]["args"],
  ]
  if any(arguments != expected for arguments in rendered):
      raise SystemExit("ordinary MCP arguments changed across renderer output")
  PY
  ${lib.concatMapStringsSep "\n" (entry: ''
    ${pkgs.jq}/bin/jq -e '
      .mcpServers["synthetic-http"]
        == {"type": "http", "url": "https://example.invalid/mcp"}
      and (.mcpServers.pal.command | type == "string")
      and (.mcpServers.pal.args | type == "array")
    ' ${entry.rendered.files."${entry.profile.root}/nix-managed-mcp.json".source} >/dev/null
    ${pkgs.jq}/bin/jq -e \
      --argjson personalWorkstation ${
        if
          builtins.elem entry.profile.host [
            "clio"
            "hera"
          ]
          && builtins.elem "personal" entry.profile.audiences
        then
          "true"
        else
          "false"
      } '
      .model == "claude-opus-5[1m]"
      and .env.CLAUDE_CODE_SUBAGENT_MODEL == "claude-opus-5"
      and (
        if $personalWorkstation then
          .preferredNotifChannel == "iterm2_with_bell"
        else
          (has("preferredNotifChannel") | not)
        end
      )
    ' ${entry.rendered.files."${entry.profile.root}/nix-managed-settings.json".source} >/dev/null
  '') claudeRenderings}

  ${lib.concatMapStringsSep "\n" (entry: ''
    ${pkgs.jq}/bin/jq -e \
      --argjson localModelRoutes ${if entry.localModelEndpoints != null then "true" else "false"} '
      type == "object"
      and (.providers | type == "object")
      and (
        (
          [
            .providers
            | to_entries[]
            | select(.value | has("apiKey"))
            | .key
          ]
          | sort
        )
        == (if $localModelRoutes then ["hermes", "router"] else [] end)
      )
      and (
        if $localModelRoutes then
          .providers.router.apiKey == "pi-model-router"
          and ((.providers.hermes.apiKey | type) == "string")
          and (.providers.hermes.apiKey | startswith("!/nix/store/"))
          and (.providers.hermes.apiKey | contains("/bin/bash -c "))
          and (.providers.hermes.apiKey | contains("/bin/pass"))
        else
          true
        end
      )
      and (
        [.providers[] | select(has("transport"))] as $transportProviders
        | ($transportProviders | length) == (if $localModelRoutes then 2 else 0 end)
        and (
          $transportProviders
          | all(.transport == {"idleTimeoutMs": 7200000, "requestTimeoutMs": 7200000})
        )
      )
    ' ${entry.rendered.files.".config/pi/agent/models.json".source} >/dev/null
  '') piRenderings}

  ${pkgs.jq}/bin/jq -e '
    type == "object"
    and (.mcpServers | type == "object")
    and .mcpServers["synthetic-http"]
      == {"oauth": false, "url": "https://example.invalid/mcp"}
    and (.mcpServers.pal.command | type == "string")
    and (.mcpServers.pal.args | type == "array")
  ' ${httpMcpRegistryRendered.files.".config/mcp/mcp.json".source} >/dev/null

  ${pkgs.jq}/bin/jq -e '
    .mcpServers["synthetic-http"]
      == {"disabled": false, "type": "http", "url": "https://example.invalid/mcp"}
    and .mcpServers.pal.disabled == false
    and .mcpServers.pal.type == "stdio"
    and (.mcpServers.pal.command | type == "string")
    and (.mcpServers.pal.args | type == "array")
  ' ${droidRendered.files."${droidProfile.root}/mcp.json".source} >/dev/null
  touch "$out"
''
