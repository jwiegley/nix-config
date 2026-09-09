{
  configured,
  pkgs,
  src,
}:

let
  inherit (pkgs) lib;
  rendererPkgs = configured // {
    agent-resources = "/mcp-registry-agent-resources";
    pi-gallery = {
      outPath = "/mcp-registry-pi-gallery";
      packages.pi-loop = "/mcp-registry-pi-loop";
      packages.pi-gpt-fast-mode = "/mcp-registry-pi-gpt-fast-mode";
    };
  };
  catalog = import "${src}/config/ai/catalog.nix" {
    inherit lib;
    resources = "/mcp-registry-agent-resources";
  };
  selectFor = profile: lib.mapAttrs (_: items: catalog.select profile items) catalog.items;
  homeDirectory = "/Users/test";
  xdgConfigHome = "${homeDirectory}/.config";
  registryPath = ".config/mcp/mcp.json";
  piProfile = catalog.profiles.hera-pi;
  primeProfile = catalog.profiles.hera-prime;

  registryRenderer = import "${src}/config/ai/renderers/mcp-registry.nix" {
    inherit lib;
    pkgs = rendererPkgs;
  };
  renderRegistry =
    {
      profiles,
      items ? catalog.items,
    }:
    registryRenderer {
      projection = catalog.sharedMcpRegistryFor { inherit profiles items; };
      inherit homeDirectory xdgConfigHome;
    };
  caseProfiles = {
    piOnly = [ piProfile ];
    primeOnly = [ primeProfile ];
    combined = [
      piProfile
      primeProfile
    ];
  };
  cases = lib.mapAttrs (_: profiles: renderRegistry { inherit profiles; }) caseProfiles;
  unionItems = catalog.items // {
    mcpServers = {
      pi-only = catalog.items.mcpServers.pal // {
        selectors.clients = [ "pi" ];
      };
      prime-only = catalog.items.mcpServers.pal // {
        selectors.clients = [ "prime" ];
      };
    };
  };
  unionCases = {
    piOnly = renderRegistry {
      profiles = [ piProfile ];
      items = unionItems;
    };
    primeOnly = renderRegistry {
      profiles = [ primeProfile ];
      items = unionItems;
    };
    combined = renderRegistry {
      profiles = [
        piProfile
        primeProfile
      ];
      items = unionItems;
    };
  };
  crossHomeProjection = builtins.tryEval (
    builtins.deepSeq (catalog.sharedMcpRegistryFor {
      profiles = [
        catalog.profiles.vulcan-pi
        primeProfile
      ];
    }) true
  );
  guardPaths = rendered: map (guard: guard.path) rendered.mutableMcpGuards;

  piRendered =
    (import "${src}/config/ai/renderers/pi.nix" {
      inherit lib;
      pkgs = rendererPkgs;
    })
      {
        profile = piProfile;
        selected = selectFor piProfile;
        localModelEndpoints = catalog.localModelEndpointsByHost.${piProfile.host};
        localModelDiscoveryEndpoints = catalog.piModelDiscoveryEndpoints;
        inherit homeDirectory xdgConfigHome;
        passwordStoreDir = "${homeDirectory}/doc/.password-store";
        gnupgHome = "${xdgConfigHome}/gnupg";
      };
  primeRendered =
    (import "${src}/config/ai/renderers/prime.nix" {
      inherit lib;
      pkgs = rendererPkgs;
    })
      {
        profile = primeProfile;
        selected = selectFor primeProfile;
        localModelEndpoints = catalog.localModelEndpointsByHost.${primeProfile.host};
        inherit homeDirectory xdgConfigHome;
      };
in
assert
  catalog.sharedMcpRegistryFor { profiles = [ catalog.profiles.hera-codex ]; } == {
    mcpServers = { };
    mutableMcpPaths = [ ];
  };
assert
  (catalog.sharedMcpRegistryFor { profiles = [ catalog.profiles.vulcan-pi ]; }).mcpServers ? pal;
assert
  !((catalog.sharedMcpRegistryFor { profiles = [ catalog.profiles.vps-pi ]; }).mcpServers ? pal);
assert !crossHomeProjection.success;
assert builtins.all (rendered: builtins.attrNames rendered.files == [ registryPath ]) (
  builtins.attrValues cases
);
assert guardPaths cases.piOnly == [ ".config/pi/agent/mcp.json" ];
assert guardPaths cases.primeOnly == [ ".prime/agent/mcp.json" ];
assert
  guardPaths cases.combined == [
    ".config/pi/agent/mcp.json"
    ".prime/agent/mcp.json"
  ];
assert !(builtins.hasAttr registryPath piRendered.files);
assert !(builtins.hasAttr registryPath primeRendered.files);
assert !(piRendered ? mutableMcpGuard);
assert !(primeRendered ? mutableMcpGuard);
pkgs.runCommand "ai-mcp-registry" { } ''
  ${lib.concatMapStringsSep "\n" (name: ''
    echo "Checking MCP registry: ${name}"
    ${pkgs.jq}/bin/jq -e \
      --argjson members ${
        lib.escapeShellArg (
          builtins.toJSON (
            builtins.attrNames (catalog.sharedMcpRegistryFor { profiles = caseProfiles.${name}; }).mcpServers
          )
        )
      } \
      --arg launcher ${lib.escapeShellArg "${configured.nix-managed-mcp-stdio}/bin/nix-managed-mcp-stdio"} \
      --arg pal ${lib.escapeShellArg "${configured.pal-mcp-server}/bin/pal-mcp-server"} '
      (.mcpServers | keys) == $members
      and .settings.mcpFooterStatus == "compact"
      and .mcpServers.pal == {
        command: $launcher,
        args: [
          "--inherit", "ANTHROPIC_API_KEY",
          "--inherit", "DEFAULT_MODEL",
          "--inherit", "DISABLED_TOOLS",
          "--inherit", "FACTORY_API_KEY",
          "--inherit", "GEMINI_API_KEY",
          "--inherit", "HOME",
          "--inherit", "LANG",
          "--inherit", "LC_ALL",
          "--inherit", "LOGNAME",
          "--inherit", "LOG_LEVEL",
          "--inherit", "NIX_SSL_CERT_FILE",
          "--inherit", "NODE_EXTRA_CA_CERTS",
          "--inherit", "OPENAI_API_KEY",
          "--inherit", "PAL_FACTORY_DROID_USE_LOCAL_LOGIN",
          "--inherit", "SHELL",
          "--inherit", "SSL_CERT_FILE",
          "--inherit", "TERM",
          "--inherit", "TMPDIR",
          "--inherit", "USER",
          "--inherit", "XAI_API_KEY",
          "--inherit", "XDG_CONFIG_HOME",
          "--", $pal
        ],
        env: {
          DEFAULT_MODEL: "auto",
          DISABLED_TOOLS: "testgen,secaudit,docgen,tracer",
          LOG_LEVEL: "WARNING",
          PAL_FACTORY_DROID_USE_LOCAL_LOGIN: "true"
        }
      }
    ' ${cases.${name}.files.${registryPath}.source} >/dev/null
  '') (builtins.attrNames cases)}

  ${pkgs.jq}/bin/jq -e \
    '(.mcpServers | keys) == ["pi-only"]' \
    ${unionCases.piOnly.files.${registryPath}.source} >/dev/null
  ${pkgs.jq}/bin/jq -e \
    '(.mcpServers | keys) == ["prime-only"]' \
    ${unionCases.primeOnly.files.${registryPath}.source} >/dev/null
  ${pkgs.jq}/bin/jq -e \
    '(.mcpServers | keys) == ["pi-only", "prime-only"]' \
    ${unionCases.combined.files.${registryPath}.source} >/dev/null
  touch "$out"
''
