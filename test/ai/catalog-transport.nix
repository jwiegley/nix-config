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
        (piRenderer {
          profile = piProfile;
          selected = selectedFor piProfile;
          homeDirectory = "/Users/test";
          xdgConfigHome = "/Users/test/.config";
          passwordStoreDir = "/Users/test/doc/.password-store";
          gnupgHome = "/Users/test/.config/gnupg";
          localModelEndpoints = localModelEndpointsFor piProfile;
        }).files.".config/mcp/mcp.json".source
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
  safePiRendered = piRenderer {
    profile = piProfile;
    selected = safeSelectedFor piProfile;
    homeDirectory = "/Users/test";
    xdgConfigHome = "/Users/test/.config";
    passwordStoreDir = "/Users/test/doc/.password-store";
    gnupgHome = "/Users/test/.config/gnupg";
    localModelEndpoints = localModelEndpointsFor piProfile;
  };
  fessSource = catalog.items.agents.fess-auditor.source;
  fessText = builtins.readFile fessSource;
  hasFessRubric = text: lib.hasInfix "**Fallback smuggling**" text;
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
assert !(builtins.pathExists "${src}/config/ai/commands/fess.md");
assert catalog.items.commands.fess.source == fessSource;
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
assert piRenderings != [ ];
assert builtins.hasAttr "${droidProfile.root}/mcp.json" droidRendered.files;
assert builtins.all (
  entry:
  let
    files = entry.rendered.files;
  in
  builtins.hasAttr ".config/pi/agent/models.json" files
  && builtins.hasAttr ".config/mcp/mcp.json" files
  && hasFessRubric files.${fessPaths.pi.agent}.text
  && hasFessRubric files.${fessPaths.pi.command}.text
  && (builtins.hasAttr ".config/pi/agent/model-router.json" files) == entry.darwin
  && entry.rendered.mutableMcpGuard.path == ".config/pi/agent/mcp.json"
) piRenderings;
assert
  let
    prompt = primeRendered.files.${fessPaths.prime.agent}.text;
  in
  lib.hasInfix "Read the immutable specialist role at `" prompt
  && lib.hasInfix "-fess-auditor.md` in full" prompt;
assert hasFessRubric primeRendered.files.${fessPaths.prime.command}.text;
assert builtins.all reject [
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
    ${safePiRendered.files.".config/mcp/mcp.json".source} <<'PY'
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
    ${pkgs.jq}/bin/jq -e '
      type == "object"
      and (.mcpServers | type == "object")
      and .mcpServers["synthetic-http"]
        == {"oauth": false, "url": "https://example.invalid/mcp"}
      and (.mcpServers.pal.command | type == "string")
      and (.mcpServers.pal.args | type == "array")
    ' ${entry.rendered.files.".config/mcp/mcp.json".source} >/dev/null
  '') piRenderings}

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
