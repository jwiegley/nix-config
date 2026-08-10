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
  claudeSettings = catalog.items.settings.settings;
  withClaudeSettingsBase =
    base:
    catalog.items
    // {
      settings.settings = claudeSettings // {
        inherit base;
      };
    };
  escapedModelIdentifier = builtins.fromJSON "\"claude-opus-5\\u001b[1m\"";
  c1CsiModelIdentifier = builtins.fromJSON "\"model\\u009b1m\"";
  c1OscModelIdentifier = builtins.fromJSON "\"model\\u009dtitle\"";
  profiles = builtins.attrValues catalog.profiles;
  piProfiles = lib.filter (profile: profile.client == "pi") profiles;
  piProfile = lib.findFirst (profile: profile.client == "pi") (throw "Pi profile missing") profiles;
  droidProfile = lib.findFirst (
    profile: profile.client == "droid"
  ) (throw "Droid profile missing") profiles;
  stdioMcp = lib.findFirst (server: server.transport ? command) (throw "stdio MCP server missing") (
    builtins.attrValues catalog.items.mcpServers
  );
  syntheticHttpMcp = stdioMcp // {
    transport.url = "https://example.invalid/mcp";
    selectors.profiles = [ ];
  };
  unauthorizedHttpHeader = syntheticHttpMcp // {
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
  multipleUnauthorizedHttpHeaders = syntheticHttpMcp // {
    transport = syntheticHttpMcp.transport // {
      headers = {
        Authorization.env = "OPENAI_API_KEY";
        X-Synthetic-Token.env = "OPENAI_API_KEY";
      };
    };
  };
  selectFor = profile: lib.mapAttrs (_: itemSet: catalog.select profile itemSet) catalog.items;
  piRenderer = import "${src}/config/ai/renderers/pi.nix" {
    inherit lib;
    pkgs = rendererPkgs;
  };
  renderPi =
    profile:
    let
      darwin = profile.platform == "darwin";
      homeDirectory = if darwin then "/Users/test" else "/home/test";
    in
    {
      inherit profile darwin;
      rendered = piRenderer {
        inherit profile homeDirectory;
        selected = selectFor profile;
        xdgConfigHome = "${homeDirectory}/.config";
        passwordStoreDir = if darwin then "${homeDirectory}/doc/.password-store" else null;
        gnupgHome = if darwin then "${homeDirectory}/.config/gnupg" else null;
      };
    };
  piRenderings = map renderPi piProfiles;
  droidRendered =
    (import "${src}/config/ai/renderers/droid.nix" {
      inherit lib;
      pkgs = rendererPkgs;
    })
      {
        profile = droidProfile;
        selected = selectFor droidProfile;
        homeDirectory = "/Users/test";
        xdgConfigHome = "/Users/test/.config";
      };
in
assert catalog.validate { };
assert claudeSettings.base.model == "claude-opus-5";
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
assert catalog.validate {
  items = withClaudeSettingsBase (claudeSettings.base // { model = "café/模型@版本"; });
};
assert builtins.all (profile: (selectFor profile).mcpServers ? pal) profiles;
# The endpoint-bearing profile set drives generated codex TOML, pi local
# provider wiring, prime model overrides, and the dummy-key session
# variables; pin it so a gained or lost declaration is a visible test edit.
assert
  lib.sort builtins.lessThan (
    builtins.attrNames (
      lib.filterAttrs (_: profile: profile.localModelEndpoints != null) catalog.profiles
    )
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
assert piRenderings != [ ];
assert builtins.hasAttr "${droidProfile.root}/mcp.json" droidRendered.files;
assert builtins.all (
  entry:
  let
    files = entry.rendered.files;
  in
  builtins.hasAttr ".config/pi/agent/models.json" files
  && builtins.hasAttr ".config/mcp/mcp.json" files
  && (builtins.hasAttr ".config/pi/agent/model-router.json" files) == entry.darwin
  && entry.rendered.mutableMcpGuard.path == ".config/pi/agent/mcp.json"
) piRenderings;
assert builtins.all reject [
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
    items = withMcpServers (catalog.items.mcpServers // { synthetic-http = unauthorizedHttpHeader; });
  })
  (catalog.validate {
    items = withMcpServers (
      catalog.items.mcpServers // { synthetic-stdio = mismatchedStdioEnvironment; }
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
      client = "unsupported";
    };
    selected = selectFor piProfile;
    homeDirectory = "/Users/test";
    xdgConfigHome = "/Users/test/.config";
    passwordStoreDir = "/Users/test/doc/.password-store";
    gnupgHome = "/Users/test/.config/gnupg";
  })
];
pkgs.runCommand "ai-catalog-transport" { } ''
  ${lib.concatMapStringsSep "\n" (entry: ''
    ${pkgs.jq}/bin/jq -e \
      --argjson localModelRoutes ${
        if entry.profile.localModelEndpoints != null then "true" else "false"
      } '
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
    ' ${entry.rendered.files.".config/pi/agent/models.json".source} >/dev/null
    ${pkgs.jq}/bin/jq -e '
      type == "object"
      and (.mcpServers | type == "object")
    ' ${entry.rendered.files.".config/mcp/mcp.json".source} >/dev/null
  '') piRenderings}
  touch "$out"
''
