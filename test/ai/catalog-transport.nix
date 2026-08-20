{
  codexPackage,
  configured,
  droidPackage,
  lib,
  pkgs,
  src,
}:

let
  rendererPkgs = configured // {
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
  modelOverrides = import "${src}/config/ai/model-overrides.nix";
  mcpEnvironment = import "${src}/config/ai/managed-stdio.nix" { inherit lib; };
  recordingTranscriptionModels = builtins.attrNames modelOverrides.localProviderOverrides.omlx.modelOverrides;
  recordingTranscriptionRoute = catalog.recordingTranscriptionRoutesByHost.hera;
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
  localModelDiscoveryEndpointsFor =
    profile:
    if profile.client == "pi" && profile.platform == "darwin" then
      catalog.localModelEndpointsByHost.${profile.host}
    else
      null;
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
  clioCodexProfile = catalog.profiles.clio-codex;
  codexProfile = catalog.profiles.hera-codex;
  piProfile = catalog.profiles.hera-pi;
  droidProfile = profileFor "droid";
  primeProfile = profileFor "prime";
  stdioMcp = lib.findFirst (server: server.transport ? command) (throw "stdio MCP server missing") (
    builtins.attrValues catalog.items.mcpServers
  );
  syntheticHttpMcp = stdioMcp // {
    transport.url = "https://example.invalid/mcp";
    selectors.profiles = [ ];
  };
  withSyntheticHttpUrl =
    url:
    withMcpServers (
      catalog.items.mcpServers
      // {
        synthetic-http = syntheticHttpMcp // {
          transport.url = url;
        };
      }
    );
  unsafeHttpUrls = [
    "https://"
    "https:///mcp"
    "https://:443/mcp"
    "https://example.invalid/mcp?token=unsafe"
    "https://example.invalid/mcp#unsafe"
    "https://user@example.invalid/mcp"
    "https://example.invalid:65536/mcp"
    "https://[::1]:65536/mcp"
    "https://256.0.0.1/mcp"
    "https://127.00.0.1/mcp"
    "https://example..invalid/mcp"
    "https://-example.invalid/mcp"
    "https://[]/mcp"
    "https://[.]/mcp"
    "https://[:::]/mcp"
    "https://[2001:db8::1::2]/mcp"
    "https://[1:2:3:4:5:6:7]/mcp"
    "https://[1:2:3:4:5:6:7:8:9]/mcp"
    "https://[1:2:3:4:5:6:7::8]/mcp"
    "https://[12345::1]/mcp"
    "https://[gggg::1]/mcp"
    "https://[::ffff:256.0.0.1]/mcp"
    "https://[192.0.2.1::]/mcp"
    (builtins.fromJSON ''"https://example.invalid/mcp\nnext"'')
    (builtins.fromJSON ''"https://example.invalid/mcp\u001b"'')
    (builtins.fromJSON ''"https://example.invalid/mcp\u0085"'')
  ];
  safeHttpUrls = [
    "https://example.invalid"
    "https://example.invalid:443/mcp"
    "https://example.invalid.:65535/mcp"
    "https://127.0.0.1:00080/mcp"
    "https://localhost:0/mcp"
    "https://[::]/mcp"
    "https://[2001:db8::1]/mcp"
    "https://[::1]:443/mcp"
    "https://[1:2:3:4:5:6:7:8]:65535/mcp"
    "https://[::ffff:192.0.2.128]/mcp"
    "https://[0:0:0:0:0:ffff:192.0.2.128]/mcp"
  ];
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
  commandOverrideMcp = catalog.items.mcpServers.pal // {
    overrides.codex.command = "pal-mcp-server";
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
      command = "/synthetic-mcp";
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
  argumentlessItems = withMcpServers (
    catalog.items.mcpServers
    // {
      synthetic-arguments = syntheticArgumentMcp // {
        transport = builtins.removeAttrs syntheticArgumentMcp.transport [ "args" ];
      };
    }
  );
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
    [ { public = builtins.fromJSON ''"ordinary\u009b1m"''; } ]
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
    inherit codexPackage lib;
    pkgs = rendererPkgs;
  };
  codexRendered = renderFor codexRenderer codexProfile "/Users/test";
  clioCodexRendered = renderFor codexRenderer clioCodexProfile "/Users/test";
  codexUnwrappedPackage = codexPackage.unwrappedPackage;
  codexSourceCatalog = "${codexUnwrappedPackage.src}/codex-rs/models-manager/models.json";
  codexManagedCatalog =
    codexRendered.files."${codexProfile.root}/nix-managed-model-catalog.json".source;
  codexManagedConfig = codexRendered.files."${codexProfile.root}/nix-managed.config.toml".source;
  codexManagedFessSkill = codexRendered.files.".agents/skills/command-fess".source;
  mcpEnvironmentProbeScript = pkgs.writeText "mcp-environment-probe.py" (
    builtins.readFile ./mcp-environment-probe.py
  );
  codexMcpProbeItems = catalog.items // {
    mcpServers = {
      managed-environment-probe = {
        selectors.profiles = [ codexProfile.id ];
        transport = {
          command = "${pkgs.python3}/bin/python3";
          args = [
            { public = toString mcpEnvironmentProbeScript; }
            { public = configured.nix-managed-mcp-stdio.runtimePath; }
          ];
          env = {
            ANTHROPIC_API_KEY.env = "ANTHROPIC_API_KEY";
            DEFAULT_MODEL = "auto";
            OPENAI_API_KEY.env = "OPENAI_API_KEY";
          };
        };
      };
    };
  };
  codexMcpProbeRendered = renderSelectedFor codexRenderer codexProfile "/Users/test" (
    (selectFrom codexMcpProbeItems) codexProfile
  );
  codexMcpProbeConfig =
    codexMcpProbeRendered.files."${codexProfile.root}/nix-managed.config.toml".source;
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
      localModelDiscoveryEndpoints = localModelDiscoveryEndpointsFor profile;
    in
    {
      inherit
        profile
        darwin
        localModelEndpoints
        localModelDiscoveryEndpoints
        ;
      rendered = piRenderer {
        inherit
          profile
          homeDirectory
          localModelEndpoints
          localModelDiscoveryEndpoints
          ;
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
    localModelDiscoveryEndpoints = localModelDiscoveryEndpointsFor piProfile;
  };
  syntheticLocalModelDiscoveryEndpoints = {
    llama-swap = "http://127.0.0.1:18080/v1";
    omlx = "http://127.0.0.1:18000/v1";
  };
  piSyntheticDiscoveryRendered = piRenderer {
    profile = catalog.profiles.clio-pi;
    selected = selectFor catalog.profiles.clio-pi;
    homeDirectory = "/Users/test";
    xdgConfigHome = "/Users/test/.config";
    passwordStoreDir = "/Users/test/doc/.password-store";
    gnupgHome = "/Users/test/.config/gnupg";
    localModelEndpoints = null;
    localModelDiscoveryEndpoints = syntheticLocalModelDiscoveryEndpoints;
  };
  droidRenderer = import "${src}/config/ai/renderers/droid.nix" {
    inherit lib;
    pkgs = rendererPkgs;
  };
  droidRendered = renderFor droidRenderer droidProfile "/Users/test";
  droidMcpProbeItems = catalog.items // {
    mcpServers = {
      managed-environment-probe = {
        selectors.profiles = [ droidProfile.id ];
        transport = {
          command = "${pkgs.python3}/bin/python3";
          args = [
            { public = toString mcpEnvironmentProbeScript; }
            { public = configured.nix-managed-mcp-stdio.runtimePath; }
            { public = "droid"; }
            { public = "@DROID_HOME@"; }
            { public = "@DROID_TMPDIR@"; }
          ];
          env = {
            ANTHROPIC_API_KEY.env = "ANTHROPIC_API_KEY";
            DEFAULT_MODEL = "auto";
            GEMINI_API_KEY.env = "GEMINI_API_KEY";
            OPENAI_API_KEY.env = "OPENAI_API_KEY";
          };
        };
      };
    };
  };
  droidMcpProbeRendered = renderSelectedFor droidRenderer droidProfile "/Users/test" (
    (selectFrom droidMcpProbeItems) droidProfile
  );
  droidMcpProbeConfig = droidMcpProbeRendered.files."${droidProfile.root}/mcp.json".source;
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
      localModelDiscoveryEndpoints = localModelDiscoveryEndpointsFor piProfile;
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
  argumentlessSelectedFor = selectFrom argumentlessItems;
  argumentlessClaudeRendered = renderSelectedFor claudeRenderer claudeProfile "/Users/test" (
    argumentlessSelectedFor claudeProfile
  );
  argumentlessCodexRendered = renderSelectedFor codexRenderer codexProfile "/Users/test" (
    argumentlessSelectedFor codexProfile
  );
  argumentlessDroidRendered = renderSelectedFor droidRenderer droidProfile "/Users/test" (
    argumentlessSelectedFor droidProfile
  );
  argumentlessMcpRegistryRendered = renderMcpRegistryFor piProfile argumentlessItems;
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
  repositoryAgentInstructions = builtins.readFile "${src}/AGENTS.md";
  reviewCommandNames = [
    "deep-review"
    "heavy-review"
    "quick-review"
    "sec-audit"
  ];
  requiredReviewToolGrants = [
    "Read"
    "Grep"
    "Glob"
    "Bash(git:*)"
    "Bash(wc:*)"
  ];
  allowedReviewShellGrants = [
    "Bash(git:*)"
    "Bash(grep:*)"
    "Bash(wc:*)"
    "Bash(gh pr diff:*)"
  ];
  unsafeReviewShellGrants = [
    "Bash"
    "Bash(find:*)"
    "Bash(python:*)"
  ];
  validReviewToolPolicy =
    metadata:
    let
      grants = lib.splitString ", " metadata."allowed-tools";
    in
    builtins.all (grant: builtins.elem grant grants) requiredReviewToolGrants
    && builtins.all (
      grant: !(lib.hasPrefix "Bash" grant) || builtins.elem grant allowedReviewShellGrants
    ) grants;
  sourceReviewToolPolicies = builtins.filter (metadata: builtins.hasAttr "allowed-tools" metadata) (
    map (item: item.metadata) (builtins.attrValues catalog.items.commands)
  );
  mutatedReviewToolPolicies = lib.concatMap (
    metadata:
    map (
      unsafeGrant:
      metadata
      // {
        "allowed-tools" = metadata."allowed-tools" + ", ${unsafeGrant}";
      }
    ) unsafeReviewShellGrants
  ) sourceReviewToolPolicies;
  renderedClaudeReviewToolPolicies = lib.concatMap (
    entry:
    map (
      name: frontMatter entry.rendered.files."${entry.profile.root}/commands/${name}.md".text
    ) reviewCommandNames
  ) claudeRenderings;
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
  wiggumText = builtins.readFile "${src}/config/ai/skills/wiggum/SKILL.md";
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
assert builtins.all validReviewToolPolicy sourceReviewToolPolicies;
assert builtins.all validReviewToolPolicy renderedClaudeReviewToolPolicies;
assert builtins.all (metadata: !(validReviewToolPolicy metadata)) mutatedReviewToolPolicies;
assert lib.hasInfix "Discover executables only with `direnv exec . command -v <name>`"
  repositoryAgentInstructions;
assert lib.hasInfix "recursively search home, filesystem roots, mounted volumes"
  repositoryAgentInstructions;
assert lib.hasInfix "other TCC-protected locations" repositoryAgentInstructions;
assert lib.hasInfix "missing tool to `flake.nix`" repositoryAgentInstructions;
assert lib.hasInfix "regenerate the environment with `de`" repositoryAgentInstructions;
assert lib.hasInfix "identify the initiating command" repositoryAgentInstructions;
assert lib.hasInfix "redact private paths, arguments, and payloads" repositoryAgentInstructions;
assert lib.hasInfix "workflow-scoped signer home and agent" repositoryAgentInstructions;
assert lib.hasInfix "separate and keyless, verify the exact signer" repositoryAgentInstructions;
assert lib.hasInfix "Never create a new signing home for" repositoryAgentInstructions;
assert !(builtins.pathExists "${src}/config/ai/commands/fess.md");
assert catalog.items.commands.fess.source == fessSource;
assert lib.hasInfix ''fork_turns="none"'' parallelizeText;
assert lib.hasInfix "verify-history-isolation.py" parallelizeText;
assert !(lib.hasInfix "Each subagent starts fresh with none of your context" parallelizeText);
assert lib.hasInfix ''
  A user request to stop or halt overrides everything below: acknowledge it,
  record the current loop state in the active `obr` issue or handoff document,
  and stop immediately.

  Exit the loop successfully ONLY when ALL of these hold, with evidence rather than self-assertion:
'' wiggumText;
assert !(lib.hasInfix "- No request to stop or halt has been received from the user." wiggumText);
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
assert builtins.all (
  profile:
  builtins.all (
    server:
    server.transport ? url
    || (server.transport.command == "nix-managed-mcp-stdio" && builtins.elem "--" server.transport.args)
  ) (builtins.attrValues (selectFor profile).mcpServers)
) profiles;
# The home-level endpoint table is one authority shared by both workstations.
assert
  builtins.attrNames catalog.localModelEndpointsByHost == [
    "clio"
    "hera"
  ];
assert catalog.localModelEndpointsByHost.clio == catalog.localModelEndpointsByHost.hera;
assert builtins.attrNames catalog.recordingTranscriptionRoutesByHost == [ "hera" ];
assert
  builtins.attrNames recordingTranscriptionRoute == [
    "model"
    "provider"
  ];
assert recordingTranscriptionRoute.provider == "omlx";
assert builtins.length recordingTranscriptionModels == 1;
assert recordingTranscriptionRoute.model == builtins.head recordingTranscriptionModels;
assert builtins.hasAttr recordingTranscriptionRoute.provider catalog.localModelEndpointsByHost.hera;
# Profile opt-ins drive generated codex TOML, pi local provider wiring, prime
# model overrides, and the dummy-key session variables. Pin the set so a
# gained or lost route is a visible test edit.
assert
  lib.sort builtins.lessThan (
    builtins.attrNames (lib.filterAttrs (_: profile: profile.localModelRoutes) catalog.profiles)
  ) == [
    "hera-codex"
    "hera-pi"
    "hera-prime"
  ];
assert
  lib.sort builtins.lessThan (
    builtins.attrNames (lib.filterAttrs (_: profile: profile.hermesRoute) catalog.profiles)
  ) == [
    "clio-pi"
    "hera-pi"
  ];
assert catalog.validate {
  items = withMcpServers (catalog.items.mcpServers // { synthetic-http = syntheticHttpMcp; });
};
assert builtins.all (
  url: reject (catalog.validate { items = withSyntheticHttpUrl url; })
) unsafeHttpUrls;
assert builtins.all (url: catalog.validate { items = withSyntheticHttpUrl url; }) safeHttpUrls;
assert catalog.validate { items = safeArgumentItems; };
assert catalog.validate { items = argumentlessItems; };
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
  &&
    (builtins.hasAttr ".config/pi/agent/model-router.json" files) == (entry.localModelEndpoints != null)
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
    localModelEndpointsByHost = builtins.removeAttrs catalog.localModelEndpointsByHost [ "hera" ];
  })
  (catalog.validate {
    localModelEndpointsByHost = builtins.removeAttrs catalog.localModelEndpointsByHost [ "clio" ];
  })
  (catalog.validate { recordingTranscriptionRoutesByHost = { }; })
  (catalog.validate {
    recordingTranscriptionRoutesByHost = catalog.recordingTranscriptionRoutesByHost // {
      clio = recordingTranscriptionRoute;
    };
  })
  (catalog.validate {
    recordingTranscriptionRoutesByHost.hera = recordingTranscriptionRoute // {
      provider = "llama-swap";
    };
  })
  (catalog.validate {
    recordingTranscriptionRoutesByHost.hera = recordingTranscriptionRoute // {
      model = recordingTranscriptionRoute.model + "-invalid";
    };
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
  (catalog.validate {
    profiles = catalog.profiles // {
      shared-work-pi = catalog.profiles.shared-work-pi // {
        hermesRoute = true;
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
    localModelDiscoveryEndpoints = localModelDiscoveryEndpointsFor piProfile;
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
    items = withMcpServers (catalog.items.mcpServers // { boundary-bypass = commandOverrideMcp; });
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
    localModelDiscoveryEndpoints = localModelDiscoveryEndpointsFor piProfile;
  })
];
pkgs.runCommand "ai-catalog-transport" { } ''
  ${pkgs.gnugrep}/bin/grep -F -- ${
    lib.escapeShellArg (
      "export default createNixGallery(" + builtins.toJSON syntheticLocalModelDiscoveryEndpoints + ");"
    )
  } ${
    piSyntheticDiscoveryRendered.files.".config/pi/agent/extensions/nix-gallery/index.ts".source
  } >/dev/null

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
      '"baseDigest":"sha256:<64 lowercase hex>","flow":',
      '"ok":true,"id":"FLOW_ID"',
      "stale digest",
      "1 MiB",
      "8 MiB",
      "10-second",
      "15-second",
      "network I/O",
      "whole lifecycle",
      "`-h` and `--help`",
  )
  allowed_invocations = commands | {
      'node-red-admin flows get > "$workdir/flows.json"',
      'node-red-admin flow get "$flow_id" > "$workdir/before-envelope.json"',
      'node-red-admin flow put "$flow_id" < "$workdir/updated-envelope.json" > "$workdir/ack.json"',
      'node-red-admin flow get "$flow_id" > "$workdir/after-envelope.json"',
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
      "runtime credential-store filename": b"flows_cred.json",
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
      "runtime credential backup advice": re.compile(rb"back\s+up\s+with\s+flows", re.IGNORECASE),
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

  ${pkgs.python3}/bin/python3 ${./node-red-skill-contract.py} \
    ${nodeRedSource} ${pkgs.bash}/bin/bash

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
  } ${clioCodexRendered.files."${clioCodexProfile.root}/nix-managed.config.toml".source} <<'PY'
  import sys
  import tomllib

  with open(sys.argv[1], "rb") as stream:
      managed = tomllib.load(stream)
  mcp = managed["mcp_servers"]
  assert mcp["synthetic-http"] == {"url": "https://example.invalid/mcp"}
  assert isinstance(mcp["pal"]["command"], str)
  assert isinstance(mcp["pal"]["args"], list)
  assert managed["model_providers"] == {
      "llama-swap": {
          "base_url": "${catalog.localModelEndpointsByHost.hera.llama-swap}",
          "env_key": "LLAMA_SWAP_API_KEY",
          "name": "llama-swap",
          "wire_api": "responses",
      },
      "omlx": {
          "base_url": "${catalog.localModelEndpointsByHost.hera.omlx}",
          "env_key": "OMLX_API_KEY",
          "name": "oMLX",
          "wire_api": "responses",
      },
  }
  assert managed["profiles"] == {
      "llama-swap": {"model": "GLM-5.2", "model_provider": "llama-swap"},
      "omlx": {"model": "Qwen3.6-27B-oQ6e-mtp", "model_provider": "omlx"},
  }

  with open(sys.argv[2], "rb") as stream:
      clio = tomllib.load(stream)
  assert "model_providers" not in clio
  assert "profiles" not in clio
  PY

  ${pkgs.python3}/bin/python3 ${./codex-catalog-smoke.py} ${
    lib.escapeShellArgs [
      "${codexUnwrappedPackage}/bin/codex"
      (toString codexSourceCatalog)
      (toString codexManagedCatalog)
      (toString codexManagedConfig)
      (toString codexManagedFessSkill)
      (toString codexMcpProbeConfig)
      "/Users/test/${codexProfile.root}/nix-managed-model-catalog.json"
      catalog.items.commands.fess.metadata.description
    ]
  }

  droid_home="$TMPDIR/droid-managed-mcp/home"
  droid_tmp="$TMPDIR/droid-managed-mcp/tmp"
  mkdir -p "$droid_home/.config/factory" "$droid_tmp"
  cp ${droidMcpProbeConfig} "$droid_home/.config/factory/mcp.json"
  substituteInPlace "$droid_home/.config/factory/mcp.json" \
    --replace-fail '@DROID_HOME@' "$droid_home" \
    --replace-fail '@DROID_TMPDIR@' "$droid_tmp"
  ln -s "$droid_home/.config/factory" "$droid_home/.factory"
  if ! ${pkgs.coreutils}/bin/timeout --signal=TERM --kill-after=1 20 \
    ${pkgs.coreutils}/bin/env -i \
      HOME="$droid_home" \
      USER=test \
      LOGNAME=test \
      LANG=C.UTF-8 \
      LC_ALL=C.UTF-8 \
      PATH=${
        lib.escapeShellArg (
          lib.makeBinPath [
            droidPackage
            pkgs.coreutils
          ]
        )
      } \
      TERM=dumb \
      TMPDIR="$droid_tmp" \
      NIX_SSL_CERT_FILE=/managed-ca \
      SHELL=/managed-shell \
      SSL_CERT_FILE=/managed-ssl \
      ANTHROPIC_API_KEY= \
      OPENAI_API_KEY=typed-sentinel \
      DEFAULT_MODEL=parent-poison \
      GEMINI_API_KEY=droid-gemini-sentinel \
      GIT_AI_SOCKET=/forbidden \
      GIT_TRACE2_EVENT=/forbidden \
      SSH_AUTH_SOCK=/forbidden \
      NODE_OPTIONS=--trace-warnings \
      PYTHONPATH=/forbidden \
      UNRELATED_SECRET=unrelated-sentinel \
      FACTORY_AIRGAP_ENABLED=true \
      FACTORY_OTEL_ENABLED=false \
      FACTORY_DISABLE_DYNAMIC_CONFIG=true \
      FACTORY_DROID_AUTO_UPDATE_ENABLED=false \
      FACTORY_MCP_BLOCKING_LOAD_TIMEOUT_MS=5000 \
      ${droidPackage}/bin/droid mcp list \
      >"$TMPDIR/droid-managed-mcp.stdout" \
      2>"$TMPDIR/droid-managed-mcp.stderr"; then
    ${pkgs.coreutils}/bin/cat "$TMPDIR/droid-managed-mcp.stdout" >&2
    ${pkgs.coreutils}/bin/cat "$TMPDIR/droid-managed-mcp.stderr" >&2
    exit 1
  fi
  ${pkgs.gnugrep}/bin/grep -F \
    'managed-environment-probe  stdio  connected  [user]' \
    "$TMPDIR/droid-managed-mcp.stdout" >/dev/null
  if ${pkgs.gnugrep}/bin/grep -E \
    'managed-environment-probe.*(connecting|failed|needs authentication)' \
    "$TMPDIR/droid-managed-mcp.stdout" >/dev/null; then
    echo "Droid did not connect to the managed environment probe" >&2
    exit 1
  fi
  if ${pkgs.gnugrep}/bin/grep -E \
    '(typed-sentinel|droid-gemini-sentinel|parent-poison|unrelated-sentinel|/forbidden)' \
    "$TMPDIR/droid-managed-mcp.stdout" "$TMPDIR/droid-managed-mcp.stderr" >/dev/null; then
    echo "Droid disclosed managed MCP environment canaries" >&2
    exit 1
  fi

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
    ${safeMcpRegistryRendered.files.".config/mcp/mcp.json".source} \
    ${argumentlessClaudeRendered.files."${claudeProfile.root}/nix-managed-mcp.json".source} \
    ${argumentlessCodexRendered.files."${codexProfile.root}/nix-managed.config.toml".source} \
    ${argumentlessDroidRendered.files."${droidProfile.root}/mcp.json".source} \
    ${argumentlessMcpRegistryRendered.files.".config/mcp/mcp.json".source} <<'PY'
  import json
  import sys
  import tomllib

  original_arguments = [
      "--header=X-Request-ID:request-42",
      "MODE=stdio",
      "--max-tokens=42",
      "--token-count=42",
      "--authorization-mode=none",
      "--no-auth",
      "--label=secret",
      "/run/secrets/service-token",
  ]
  platform_environment = ${builtins.toJSON mcpEnvironment.platformEnvironment}

  def managed_arguments(command, arguments, environment=()):
      result = []
      for name in sorted(set(platform_environment) | set(environment)):
          result.extend(["--inherit", name])
      return result + ["--", command] + arguments

  expected = managed_arguments("/synthetic-mcp", original_arguments)
  paths = sys.argv[1:5]
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

  argumentless_paths = sys.argv[5:]
  with open(argumentless_paths[0], encoding="utf-8") as stream:
      argumentless_claude = json.load(stream)
  with open(argumentless_paths[1], "rb") as stream:
      argumentless_codex = tomllib.load(stream)
  with open(argumentless_paths[2], encoding="utf-8") as stream:
      argumentless_droid = json.load(stream)
  with open(argumentless_paths[3], encoding="utf-8") as stream:
      argumentless_pi = json.load(stream)
  argumentless_rendered = [
      argumentless_claude["mcpServers"]["synthetic-arguments"]["args"],
      argumentless_codex["mcp_servers"]["synthetic-arguments"]["args"],
      argumentless_droid["mcpServers"]["synthetic-arguments"]["args"],
      argumentless_pi["mcpServers"]["synthetic-arguments"]["args"],
  ]
  expected_argumentless = managed_arguments("/synthetic-mcp", [])
  if any(arguments != expected_argumentless for arguments in argumentless_rendered):
      raise SystemExit("omitted MCP args were not normalized across renderer output")

  claude_pal = claude["mcpServers"]["pal"]
  codex_pal = codex["mcp_servers"]["pal"]
  droid_pal = droid["mcpServers"]["pal"]
  pi_pal = pi["mcpServers"]["pal"]
  pal_servers = [claude_pal, codex_pal, droid_pal, pi_pal]
  pal_literal_environment = {
      "DEFAULT_MODEL": "auto",
      "DISABLED_TOOLS": "testgen,secaudit,docgen,tracer",
      "LOG_LEVEL": "WARNING",
  }
  pal_environment_references = {
      "ANTHROPIC_API_KEY": "''${ANTHROPIC_API_KEY}",
      "GEMINI_API_KEY": "''${GEMINI_API_KEY}",
      "OPENAI_API_KEY": "''${OPENAI_API_KEY}",
  }
  droid_environment_references = {
      name: "$" + "{" + name + ":-}"
      for name in set(platform_environment) | set(pal_environment_references)
  }
  expected_pal_arguments = managed_arguments(
      "${configured.pal-mcp-server}/bin/pal-mcp-server",
      [],
      pal_literal_environment.keys() | pal_environment_references.keys(),
  )
  if any(
      server.get("command") != "${configured.nix-managed-mcp-stdio}/bin/nix-managed-mcp-stdio"
      or server.get("args") != expected_pal_arguments
      for server in pal_servers
  ):
      raise SystemExit("PAL stdio command changed across renderer output")

  if claude_pal.get("env") != pal_literal_environment:
      raise SystemExit("Claude PAL environment projection changed")
  if pi_pal.get("env") != pal_literal_environment:
      raise SystemExit("Pi PAL environment projection changed")
  if droid_pal.get("env") != pal_literal_environment | droid_environment_references:
      raise SystemExit("Droid PAL environment projection changed")
  if codex_pal.get("env") != pal_literal_environment or codex_pal.get(
      "env_vars"
  ) != sorted(set(platform_environment) | set(pal_environment_references)):
      raise SystemExit("Codex PAL environment projection changed")
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
    if ${pkgs.gnugrep}/bin/grep -qi 'cozempic' ${
      entry.rendered.files."${entry.profile.root}/nix-managed-settings.json".source
    }; then
      echo "Claude managed settings reintroduced Cozempic" >&2
      exit 1
    fi
  '') claudeRenderings}

  ${lib.concatMapStringsSep "\n" (entry: ''
    ${pkgs.jq}/bin/jq -e \
      --argjson localModelRoutes ${if entry.localModelEndpoints != null then "true" else "false"} \
      --argjson localModelDiscovery ${if entry.darwin then "true" else "false"} \
      --argjson hermesRoute ${if entry.profile.hermesRoute then "true" else "false"} '
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
        == (
          (if $hermesRoute then ["hermes"] else [] end)
          + (if $localModelRoutes then ["router"] else [] end)
          | sort
        )
      )
      and (
        if $hermesRoute then
          (.providers.hermes | keys | sort) == ["api", "apiKey", "baseUrl", "compat", "models"]
          and .providers.hermes.api == "openai-completions"
          and .providers.hermes.baseUrl == "https://hermes.vulcan.lan/v1"
          and .providers.hermes.compat == {"sendSessionAffinityHeaders": true}
          and .providers.hermes.models == [{"id": "hermes-agent"}]
          and ((.providers.hermes.apiKey | type) == "string")
          and (.providers.hermes.apiKey | startswith("!/nix/store/"))
          and (.providers.hermes.apiKey | contains("/bin/bash -c "))
          and (.providers.hermes.apiKey | contains("/bin/env -u GPG_TTY "))
          and (.providers.hermes.apiKey | contains("PASSWORD_STORE_DIR=/Users/test/doc/.password-store"))
          and (.providers.hermes.apiKey | contains("GNUPGHOME=/Users/test/.config/gnupg"))
          and (.providers.hermes.apiKey | contains("/bin/pass"))
        else
          (.providers | has("hermes") | not)
        end
      )
      and (
        if $localModelRoutes then
          .providers["llama-swap"] == {
            "modelOverrides": {"GLM-5.2": {"contextWindow": 262144}},
            "transport": {"idleTimeoutMs": 7200000, "requestTimeoutMs": 7200000}
          }
          and .providers.omlx == {
            "modelOverrides": {
              "DeepSeek-V4-Flash-0731-oQ8e-mtp": {"contextWindow": 262144},
              "Qwen3.6-27B-oQ6e-mtp": {
                "compat": {
                  "supportsReasoningEffort": false,
                  "thinkingFormat": "qwen-chat-template"
                },
                "contextWindow": 262144,
                "defaultThinkingLevel": "off",
                "input": ["text"],
                "maxTokens": 65536,
                "reasoning": true,
                "thinkingLevelMap": {
                  "high": "high",
                  "low": null,
                  "max": null,
                  "medium": null,
                  "minimal": null,
                  "xhigh": null
                }
              }
            },
            "transport": {"idleTimeoutMs": 7200000, "requestTimeoutMs": 7200000}
          }
          and .providers.router == {
            "api": "router-local-api",
            "apiKey": "pi-model-router",
            "baseUrl": "router://local",
            "modelOverrides": {
              "sol": {
                "defaultThinkingLevel": "off",
                "input": ["text"],
                "reasoning": true,
                "thinkingLevelMap": {
                  "high": "high",
                  "low": null,
                  "max": null,
                  "medium": null,
                  "minimal": null,
                  "xhigh": null
                }
              }
            },
            "models": [{
              "contextWindow": 262144,
              "cost": {
                "cacheRead": 0,
                "cacheWrite": 0,
                "input": 0,
                "output": 0
              },
              "id": "sol",
              "maxTokens": 65536,
              "name": "Router sol"
            }]
          }
        else
          (if $localModelDiscovery then
            .providers["llama-swap"] == {
              "transport": {"idleTimeoutMs": 7200000, "requestTimeoutMs": 7200000}
            }
            and .providers.omlx == {
              "transport": {"idleTimeoutMs": 7200000, "requestTimeoutMs": 7200000}
            }
          else
            (.providers | has("llama-swap") | not)
            and (.providers | has("omlx") | not)
          end)
          and (.providers | has("router") | not)
        end
      )
      and (
        [.providers[] | select(has("transport"))] as $transportProviders
        | ($transportProviders | length) == (if $localModelDiscovery then 2 else 0 end)
        and (
          $transportProviders
          | all(.transport == {"idleTimeoutMs": 7200000, "requestTimeoutMs": 7200000})
        )
      )
    ' ${entry.rendered.files.".config/pi/agent/models.json".source} >/dev/null
    ${pkgs.gnugrep}/bin/grep -F -- ${
      lib.escapeShellArg (
        "export default createNixGallery("
        + builtins.toJSON (
          if entry.localModelDiscoveryEndpoints == null then { } else entry.localModelDiscoveryEndpoints
        )
        + ");"
      )
    } ${entry.rendered.files.".config/pi/agent/extensions/nix-gallery/index.ts".source} >/dev/null
    ${pkgs.jq}/bin/jq -e '
      has("app.thinking.cycle") | not
    ' ${entry.rendered.files.".config/pi/agent/keybindings.json".source} >/dev/null
    ${lib.optionalString (entry.localModelEndpoints != null) ''
      ${pkgs.jq}/bin/jq -e '
        . == {
          "debug": false,
          "models": {
            "sol": {
              "contextWindow": 262144,
              "maxTokens": 65536,
              "model": "omlx/Qwen3.6-27B-oQ6e-mtp",
              "reasoning": true,
              "thinkingLevels": ["off", "high"]
            }
          },
          "phaseBias": 0.5,
          "profiles": {
            "sol": {
              "high": {"model": "sol", "thinking": "off"},
              "low": {"model": "sol", "thinking": "off"},
              "medium": {"model": "sol", "thinking": "off"}
            }
          }
        }
      ' ${entry.rendered.files.".config/pi/agent/model-router.json".source} >/dev/null
    ''}
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
