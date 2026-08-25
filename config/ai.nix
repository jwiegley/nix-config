args@{
  config,
  hostname,
  lib,
  pkgs,
  vars,
  ...
}:

let
  nixManagedAiHomeClass = args.nixManagedAiHomeClass or null;
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  system = pkgs.stdenv.hostPlatform.system;
  moduleInputs = args.inputs or { };
  pairedAiInput = moduleInputs.nix-config-ai or null;
  pairedAiPackages =
    if pairedAiInput != null && pairedAiInput ? packages && pairedAiInput.packages ? ${system} then
      pairedAiInput.packages.${system}
    else
      { };
  pairedPiPackage = pairedAiPackages.pi or null;
  pairedDroidPackage = pairedAiPackages.droid or null;
  pairedHermesPackage = pairedAiPackages.hermes-agent or null;
  piNodeExtraCaFallback = vars.ca-bundle_crt;
  wrapRuntimeEnvironment = import ../flake/ai/wrappers/runtime-environment.nix {
    inherit lib pkgs;
  };
  omlxCredentialPolicy = import ./ai/omlx-credential-policy.nix;
  piOmlxKeychainCredentials = omlxCredentialPolicy.keychainByEnvironment;
  localOmlxKeychainCredential =
    if profileHost == null then
      null
    else
      (omlxCredentialPolicy.byHost.${profileHost} or { }).keychain or null;
  piOmlxCredentialEnvironmentNames = lib.sort builtins.lessThan (
    map (endpoint: endpoint.apiKey.env) (
      builtins.attrValues (
        lib.filterAttrs (_: endpoint: builtins.isAttrs endpoint) catalog.piModelDiscoveryEndpoints
      )
    )
  );
  piOmlxLocalProvider =
    if profileHost == null then "" else catalog.piLocalDiscoveryProviderByHost.${profileHost} or "";
  # Preserve the pre-Keychain non-secret local sentinel as Pi's last-resort
  # workstation fallback. The outer wrapper still prefers an explicit value or
  # the matching login-Keychain item and never puts either value in the store.
  piPackageWithOmlxFallback =
    if pairedPiPackage == null || !isDarwin then
      pairedPiPackage
    else
      wrapRuntimeEnvironment {
        defaults = lib.genAttrs piOmlxCredentialEnvironmentNames (_: "dummy-key");
        package = pairedPiPackage;
        program = "pi";
      };
  managedPiPackage =
    if pairedPiPackage == null || !isDarwin then
      pairedPiPackage
    else
      wrapRuntimeEnvironment {
        defaults = lib.optionalAttrs (piNodeExtraCaFallback != null) {
          NODE_EXTRA_CA_CERTS = piNodeExtraCaFallback;
        };
        keychainCredentials = piOmlxKeychainCredentials;
        package = piPackageWithOmlxFallback;
        program = "pi";
      };
  pairedCodexPackage = pairedAiPackages.codex or null;
  pairedPrimePackage = pairedAiPackages.prime-agent or null;
  managedPrimePackage =
    if pairedPrimePackage == null || !isDarwin || localOmlxKeychainCredential == null then
      pairedPrimePackage
    else
      wrapRuntimeEnvironment {
        keychainCredentials.OMLX_API_KEY = localOmlxKeychainCredential;
        package = pairedPrimePackage;
        program = "prime-agent";
      };
  pairedAgentResources = pairedAiPackages.agent-resources or null;
  pairedPiGallery = pairedAiPackages.pi-gallery or null;
  resourcePackage = pkgs.agent-resources;
  rendererPkgs = pkgs // {
    agent-resources = resourcePackage;
  };
  piRendererPkgs = rendererPkgs // {
    agent-resources = if pairedAgentResources != null then pairedAgentResources else resourcePackage;
    pi-gallery = if pairedPiGallery != null then pairedPiGallery else pkgs.pi-gallery;
  };

  catalog = import ./ai/catalog.nix {
    inherit lib;
    resources = resourcePackage;
  };
  registry = import ./hosts/registry.nix;
  renderers = {
    claude = import ./ai/renderers/claude.nix {
      inherit lib;
      pkgs = rendererPkgs;
    };
    codex = import ./ai/renderers/codex.nix {
      inherit lib;
      pkgs = rendererPkgs;
      codexPackage = pairedCodexPackage;
    };
    droid = import ./ai/renderers/droid.nix {
      inherit lib;
      pkgs = rendererPkgs;
    };
    hermes = import ./ai/renderers/hermes.nix {
      inherit lib;
      pkgs = rendererPkgs;
    };
    pi = import ./ai/renderers/pi.nix {
      inherit lib;
      pkgs = piRendererPkgs;
    };
    prime = import ./ai/renderers/prime.nix {
      inherit lib;
      pkgs = piRendererPkgs;
    };
  };
  mcpRegistryRenderer = import ./ai/renderers/mcp-registry.nix {
    inherit lib;
    pkgs = rendererPkgs;
  };

  homeClass = if nixManagedAiHomeClass != null then nixManagedAiHomeClass else hostname;
  homeClassContract = registry.homeClassContractFor homeClass;
  homeClassRow = homeClassContract.row;
  profileHost = if homeClassRow == null then null else homeClassRow.catalogHost;
  homeLocalModelEndpoints =
    if profileHost == null then null else catalog.localModelEndpointsByHost.${profileHost} or null;
  recordingTranscriptionRoute =
    if profileHost == null then
      null
    else
      catalog.recordingTranscriptionRoutesByHost.${profileHost} or null;
  agentModelAliases = import ./ai/agent-model-aliases.nix { inherit lib; };
  xdgConfigRelative = lib.removePrefix "${config.home.homeDirectory}/" config.xdg.configHome;
  recordingTranscriptionFiles = lib.optionalAttrs (recordingTranscriptionRoute != null) {
    "${xdgConfigRelative}/flatten-recordings/agent-model-aliases.json" = {
      source = (pkgs.formats.json { }).generate "agent-model-aliases.json" agentModelAliases;
    };
    "${xdgConfigRelative}/transcribe/llm-route.json" = {
      source = (pkgs.formats.json { }).generate "transcribe-llm-route.json" {
        version = 2;
        inherit (recordingTranscriptionRoute) model;
        base_url = homeLocalModelEndpoints.${recordingTranscriptionRoute.provider};
      };
    };
  };
  profilesForHome =
    if profileHost == null then
      { }
    else
      lib.filterAttrs (_: profile: profile.host == profileHost) catalog.profiles;
  homeClassDeclared = homeClassContract.assertion;
  profileHostPopulated = profilesForHome != { };
  profileIds = lib.sort builtins.lessThan (builtins.attrNames profilesForHome);
  codexLocalModelRoutes = lib.any (
    profileId:
    let
      profile = catalog.profiles.${profileId};
    in
    profile.client == "codex" && profile.localModelRoutes
  ) profileIds;
  managedCodexPackage =
    if pairedCodexPackage == null || !codexLocalModelRoutes then
      pairedCodexPackage
    else if !isDarwin || localOmlxKeychainCredential == null then
      throw "Codex local oMLX routes require a Darwin Keychain credential policy"
    else
      wrapRuntimeEnvironment {
        keychainCredentials.OMLX_API_KEY = localOmlxKeychainCredential;
        package = pairedCodexPackage;
        program = "codex";
      };
  selectedProfiles = map (profileId: catalog.profiles.${profileId}) profileIds;
  selectedFor =
    profileId:
    let
      profile = catalog.profiles.${profileId};
    in
    lib.mapAttrs (_: itemSet: catalog.select profile itemSet) catalog.items;
  # Selection lives in the catalog; the composer only projects the selected
  # items onto the shared root's paths.
  sharedSkillItems = catalog.sharedSkillsFor selectedProfiles;
  sharedSkillFiles = lib.mapAttrs' (
    name: item: lib.nameValuePair ".agents/skills/${name}" { inherit (item) source; }
  ) sharedSkillItems;
  renderProfile =
    profileId:
    let
      profile = catalog.profiles.${profileId};
      localModelEndpoints =
        if profile.localModelRoutes then
          if homeLocalModelEndpoints == null then
            throw "profile ${profile.id} enables local model routes without a home endpoint authority"
          else
            homeLocalModelEndpoints
        else
          null;
      localModelDiscoveryEndpoints =
        if profile.client == "pi" && profile.platform == "darwin" then
          catalog.piModelDiscoveryEndpoints
        else
          null;
    in
    renderers.${profile.client} (
      {
        inherit profile;
        selected = selectedFor profileId;
        homeDirectory = config.home.homeDirectory;
        xdgConfigHome = config.xdg.configHome;
      }
      // lib.optionalAttrs (profile.client == "pi") {
        passwordStoreDir = config.programs.password-store.settings.PASSWORD_STORE_DIR or null;
        gnupgHome = config.programs.gpg.homedir or null;
        inherit localModelDiscoveryEndpoints;
      }
      // lib.optionalAttrs (profile.client == "hermes") {
        caBundle = piNodeExtraCaFallback;
      }
      //
        lib.optionalAttrs
          (builtins.elem profile.client [
            "codex"
            "hermes"
            "pi"
            "prime"
          ])
          {
            inherit localModelEndpoints;
          }
    );

  renderedProfiles = map renderProfile profileIds;
  hermesRenderings = builtins.filter (rendered: rendered ? hermesServiceOptions) renderedProfiles;
  hermesSelected = hermesRenderings != [ ];
  managedHermesPackage =
    if !hermesSelected || pairedHermesPackage == null then
      null
    else
      wrapRuntimeEnvironment {
        package = pairedHermesPackage;
        programs = [
          "hermes"
          "hermes-agent"
          "hermes-acp"
        ];
        keychainCredentials = {
          API_SERVER_KEY = {
            account = "johnw";
            service = "nix-config.hermes.api-server-key";
          };
          OPENAI_API_KEY = {
            account = "johnw";
            service = "nix-config.omlx-hera-client";
          };
          PGPASSWORD = {
            account = "johnw";
            service = "nix-config.hermes.org-db-password";
          };
          QDRANT_API_KEY = {
            account = "johnw";
            service = "nix-config.hermes.qdrant-api-key";
          };
        };
        requiredKeychainCredentials = [
          "API_SERVER_KEY"
          "OPENAI_API_KEY"
          "PGPASSWORD"
          "QDRANT_API_KEY"
        ];
      };
  hermesServiceOptions =
    if !hermesSelected then { } else (builtins.head hermesRenderings).hermesServiceOptions;
  mcpRegistryProjection = catalog.sharedMcpRegistryFor { profiles = selectedProfiles; };
  mcpRegistrySelected = mcpRegistryProjection.mutableMcpPaths != [ ];
  mcpRegistryRendering =
    if mcpRegistrySelected then
      mcpRegistryRenderer {
        projection = mcpRegistryProjection;
        homeDirectory = config.home.homeDirectory;
        xdgConfigHome = config.xdg.configHome;
      }
    else
      null;
  renderedSurfaces = renderedProfiles ++ lib.optional mcpRegistrySelected mcpRegistryRendering;
  rawPaths =
    builtins.attrNames sharedSkillFiles
    ++ builtins.attrNames recordingTranscriptionFiles
    ++ lib.concatMap (rendered: builtins.attrNames rendered.files) renderedSurfaces;
  paths = lib.sort builtins.lessThan (lib.unique rawPaths);
  mergedFiles = lib.foldl' (files: rendered: files // rendered.files) (
    sharedSkillFiles // recordingTranscriptionFiles
  ) renderedSurfaces;
  mcpGuards = if mcpRegistrySelected then mcpRegistryRendering.mutableMcpGuards else [ ];
  validRelativePath =
    path:
    let
      parts = lib.splitString "/" path;
    in
    path != ""
    && !(lib.hasPrefix "/" path)
    && builtins.all (part: part != "" && part != "." && part != "..") parts;
  forbiddenParentPaths = [
    ".agents"
    ".agents/skills"
    ".claude"
    ".claude/skills/sherlock"
    ".codex"
    ".config/claude"
    ".config/claude/personal"
    ".config/claude/positron"
    ".config/codex"
    ".config/factory"
    ".config/mcp"
    ".config/pi"
    ".factory"
    ".pi"
    ".pi/agent"
    ".prime"
    ".prime/agent"
  ];
  ownsAncestor = path: lib.any (other: other != path && lib.hasPrefix "${path}/" other) paths;
  selectedPlatform = if isDarwin then "darwin" else "linux";
  piAgentRelative = "${xdgConfigRelative}/pi/agent";
  retiredAutoCompactPath = "${piAgentRelative}/extensions/auto-compact-resume/index.ts";

  preflight = (import ./ai/preflight.nix { inherit lib pkgs; }) {
    newPaths = paths;
    inherit mcpGuards;
    piAliasTarget = if piSelected then "${xdgConfigRelative}/pi" else null;
    retiredPaths = lib.optional piSelected retiredAutoCompactPath;
  };
  modelSync = import ./ai/model-sync.nix {
    inherit lib pkgs;
    # Lazily forced only where the model-sync activation is gated in (hera).
    # The endpoint comes from the same home authority as rendered clients.
    omlxBaseUrl =
      if homeLocalModelEndpoints == null then
        throw "model-sync requires a home local-model endpoint authority"
      else
        homeLocalModelEndpoints.omlx;
  };
  piSelected = lib.any (profileId: catalog.profiles.${profileId}.client == "pi") profileIds;
  primeSelected = lib.any (profileId: catalog.profiles.${profileId}.client == "prime") profileIds;
  piRuntimePackages = with pkgs; [
    actionlint
    agent-browser
    ast-grep
    bash-language-server
    biome
    cymbal
    gopls
    nil
    nodejs_22
    pyright
    ruff
    rust-analyzer
    rtk
    shellcheck
    shfmt
    taplo
    terraform-ls
    tmux
    typos
    typescript-language-server
    yaml-language-server
  ];
  piEnabledModelsMigrationActivation = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    (
      set -euo pipefail
      PI_CODING_AGENT_DIR="$HOME/${piAgentRelative}" \
        PI_OMLX_LOCAL_PROVIDER=${lib.escapeShellArg piOmlxLocalProvider} \
        PI_CODING_AGENT_ROOT=${lib.escapeShellArg "${pairedPiPackage}/lib/node_modules/@earendil-works/pi-coding-agent"} \
        ${pkgs.nodejs_22}/bin/node ${./ai/pi-enabled-models-migration.mjs}
    )
  '';
in
{
  # Import the host capability option this module reads rather than relying on a
  # parent module's import list.
  imports = [ ./host-options.nix ];

  assertions = [
    {
      assertion = catalog.validate { };
      message = "nix-managed AI catalog validation failed";
    }
    (builtins.removeAttrs homeClassContract [ "row" ])
    {
      assertion = !homeClassDeclared || profileHostPopulated;
      message = "nix-managed AI home class ${homeClass} maps to a catalog host with no profiles";
    }
    {
      assertion =
        nixManagedAiHomeClass == null
        || nixManagedAiHomeClass != "personal-linux"
        || (
          isLinux
          && system == "aarch64-linux"
          && config.home.username == "johnw"
          && config.johnw.host.isCiFixture
        );
      message = "the personal-linux AI home class is reserved for its test fixture";
    }
    {
      assertion = builtins.all (
        profileId: catalog.profiles.${profileId}.platform == selectedPlatform
      ) profileIds;
      message = "nix-managed AI selected a profile for the wrong platform";
    }
    {
      assertion =
        !(lib.any (profileId: catalog.profiles.${profileId}.localModelRoutes) profileIds)
        || homeLocalModelEndpoints != null;
      message = "nix-managed AI selected local model routes without a home endpoint authority";
    }
    {
      assertion = builtins.length rawPaths == builtins.length paths;
      message = "nix-managed AI profiles contain duplicate target paths";
    }
    {
      assertion = builtins.all validRelativePath paths;
      message = "nix-managed AI rendered an unsafe relative path";
    }
    {
      assertion = validRelativePath xdgConfigRelative;
      message = "xdg.configHome must be a directory below home.homeDirectory";
    }
    {
      assertion = lib.intersectLists paths forbiddenParentPaths == [ ];
      message = "nix-managed AI attempted to own a mutable parent root";
    }
    {
      assertion = !(builtins.any ownsAncestor paths);
      message = "nix-managed AI attempted recursive parent ownership";
    }
    {
      assertion = map (guard: guard.path) mcpGuards == mcpRegistryProjection.mutableMcpPaths;
      message = "nix-managed AI MCP registry guards do not match its consuming clients";
    }
    {
      assertion = pairedAiInput != null;
      message = "nix-managed AI home requires inputs.nix-config-ai for the canonical Pi package";
    }
    {
      assertion = pairedAiInput ? packages && pairedAiInput.packages ? ${system};
      message = "inputs.nix-config-ai has no packages for ${system}";
    }
    {
      assertion = pairedPiPackage != null;
      message = "inputs.nix-config-ai.packages.${system}.pi is missing";
    }
    {
      assertion = pairedDroidPackage != null;
      message = "inputs.nix-config-ai.packages.${system}.droid is missing";
    }
    {
      assertion = pairedCodexPackage != null;
      message = "inputs.nix-config-ai.packages.${system}.codex is missing";
    }
    {
      assertion = builtins.length hermesRenderings <= 1;
      message = "nix-managed AI selected more than one Hermes Agent profile";
    }
    {
      assertion = !hermesSelected || pairedHermesPackage != null;
      message = "inputs.nix-config-ai.packages.${system}.hermes-agent is missing";
    }
    {
      assertion = builtins.attrNames piOmlxKeychainCredentials == piOmlxCredentialEnvironmentNames;
      message = "Pi oMLX Keychain credentials must match the catalog environment references";
    }
    {
      assertion = !(piSelected && isDarwin) || piOmlxLocalProvider != "";
      message = "Darwin Pi profiles require a managed local oMLX provider";
    }
    {
      assertion = !primeSelected || pairedPrimePackage != null;
      message = "inputs.nix-config-ai.packages.${system}.prime-agent is missing";
    }
    {
      assertion = !(piSelected || primeSelected) || pairedAgentResources != null;
      message = "inputs.nix-config-ai.packages.${system}.agent-resources is missing";
    }
    {
      assertion = !(piSelected || primeSelected) || pairedPiGallery != null;
      message = "inputs.nix-config-ai.packages.${system}.pi-gallery is missing";
    }
  ];

  home = {
    file =
      lib.mapAttrs (_: file: file // { force = true; }) mergedFiles
      // lib.optionalAttrs piSelected {
        ".pi" = {
          source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/pi";
          force = true;
        };
      };
    packages =
      lib.optional (managedCodexPackage != null) managedCodexPackage
      ++ lib.optional (managedPiPackage != null) managedPiPackage
      ++ lib.optional (pairedDroidPackage != null) pairedDroidPackage
      ++ lib.optional (primeSelected && managedPrimePackage != null) managedPrimePackage
      ++ lib.optionals piSelected piRuntimePackages;
    # llama-swap retains its non-secret local sentinel. Secret oMLX credentials
    # are resolved from the login Keychain by the Darwin client wrappers; Pi's
    # scoped non-secret fallback is applied inside its wrapper above.
    sessionVariables =
      lib.optionalAttrs
        (lib.any (
          profileId:
          let
            profile = catalog.profiles.${profileId};
          in
          (profile.client == "codex" && profile.localModelRoutes)
          || (profile.client == "pi" && profile.platform == "darwin")
        ) profileIds)
        {
          LLAMA_SWAP_API_KEY = "dummy-key";
        };
    activation = {
      aiManagedPreflight = preflight.activation;
    }
    // lib.optionalAttrs (piSelected && isDarwin) {
      aiManagedPiEnabledModelsMigration = piEnabledModelsMigrationActivation;
    }
    // lib.optionalAttrs (config.johnw.host.isHera && isDarwin) {
      aiManagedModelSync = modelSync.activation;
    };
  };
}
// {
  services.hermes-agent = lib.mkIf hermesSelected hermesServiceOptions;
}
// {
  johnw.hermesAgent.runtimePackage = lib.mkIf hermesSelected managedHermesPackage;
}
