args@{
  config,
  hostname,
  lib,
  pkgs,
  ...
}:

let
  nixManagedAiHomeClass = args.nixManagedAiHomeClass or null;
  inherit (pkgs.stdenv) isDarwin isLinux;
  system = pkgs.stdenv.hostPlatform.system;
  moduleInputs = args.inputs or { };
  pairedAiInput = moduleInputs.nix-config-ai or null;
  pairedAiPackages =
    if pairedAiInput != null && pairedAiInput ? packages && pairedAiInput.packages ? ${system} then
      pairedAiInput.packages.${system}
    else
      { };
  pairedPiPackage = pairedAiPackages.pi or null;
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

  modelData = import ./fleet/models.nix { };
  catalog = import ./fleet/catalog.nix {
    inherit lib modelData;
    resources = resourcePackage;
  };
  renderers = {
    claude = import ./fleet/renderers/claude.nix {
      inherit lib;
      pkgs = rendererPkgs;
    };
    codex = import ./fleet/renderers/codex.nix {
      inherit lib;
      pkgs = rendererPkgs;
      llmAgents = moduleInputs.llm-agents;
    };
    droid = import ./fleet/renderers/droid.nix {
      inherit lib;
      pkgs = rendererPkgs;
    };
    opencode = import ./fleet/renderers/opencode.nix {
      inherit lib;
      pkgs = rendererPkgs;
    };
    pi = import ./fleet/renderers/pi.nix {
      inherit lib;
      pkgs = piRendererPkgs;
    };
  };

  homeClass = if nixManagedAiHomeClass != null then nixManagedAiHomeClass else hostname;
  profileHost = if homeClass == "personal-linux" then "vps" else homeClass;
  profilesForHome = lib.filterAttrs (_: profile: profile.host == profileHost) catalog.profiles;
  homeClassKnown = profilesForHome != { };
  profileIds = lib.sort builtins.lessThan (builtins.attrNames profilesForHome);
  rootsForClient =
    client:
    lib.sort builtins.lessThan (
      lib.unique (
        map (profile: profile.root) (
          builtins.attrValues (lib.filterAttrs (_: profile: profile.client == client) profilesForHome)
        )
      )
    );
  managedMcpServersForClient =
    client:
    lib.listToAttrs (
      map (
        profileId:
        let
          profile = catalog.profiles.${profileId};
        in
        lib.nameValuePair profile.root (
          lib.sort builtins.lessThan (builtins.attrNames (selectedFor profileId).mcpServers)
        )
      ) (builtins.filter (profileId: catalog.profiles.${profileId}.client == client) profileIds)
    );
  allProfileRoots = lib.sort builtins.lessThan (
    lib.unique (map (profile: profile.root) (builtins.attrValues profilesForHome))
  );

  selectedFor =
    profileId:
    let
      profile = catalog.profiles.${profileId};
    in
    lib.mapAttrs (_: itemSet: catalog.select profile itemSet) catalog.items;
  selectedModelDataFor =
    profileId:
    let
      profile = catalog.profiles.${profileId};
      providers = catalog.select profile modelData.providers;
      models = lib.filterAttrs (
        _: model:
        builtins.hasAttr model.provider providers && catalog.matches profile (model.selectors or { })
      ) modelData.models;
    in
    {
      inherit models providers;
    }
    // lib.optionalAttrs (builtins.hasAttr profileId modelData.profileDefaults) {
      default = modelData.profileDefaults.${profileId};
    };
  renderProfile =
    profileId:
    let
      profile = catalog.profiles.${profileId};
      rendererModelData =
        if profile.renderer == "codex" then modelData else selectedModelDataFor profileId;
    in
    renderers.${profile.renderer} {
      inherit profile;
      selected = selectedFor profileId;
      modelData = rendererModelData;
      homeDirectory = config.home.homeDirectory;
      xdgConfigHome = config.xdg.configHome;
    };

  renderedProfiles = map renderProfile profileIds;
  rawPaths = lib.concatMap (rendered: builtins.attrNames rendered.files) renderedProfiles;
  paths = lib.sort builtins.lessThan (lib.unique rawPaths);
  mergedFiles = lib.foldl' (files: rendered: files // rendered.files) { } renderedProfiles;
  companionsAreOwned = builtins.all (
    rendered: builtins.all (path: builtins.hasAttr path rendered.files) rendered.companions
  ) renderedProfiles;
  piGuards = map (rendered: rendered.mutableMcpGuard) (
    builtins.filter (rendered: rendered ? mutableMcpGuard) renderedProfiles
  );
  piGuard = if piGuards == [ ] then null else builtins.head piGuards;
  piProfileMigration = (import ./pi-profile-migration.nix { inherit lib pkgs; }) {
    root = catalog.profiles.hera-pi.root;
    compatibilityRoot = ".config/pi";
  };
  retiredMcpCleanup = (import ./fleet/retired-mcp-cleanup.nix { inherit lib pkgs; }) {
    homeDirectory = config.home.homeDirectory;
    retiredServers = catalog.retiredMcpServers;
    retiredManifestMcpItems = catalog.retiredPromptdeployMcpItems;
    retiredManifestSkillItems = catalog.retiredPromptdeploySkillItems;
    codexManagedServers = managedMcpServersForClient "codex";
    claudeManagedServers = managedMcpServersForClient "claude";
    piRoots = rootsForClient "pi";
    manifestRoots = allProfileRoots;
  };

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
    ".config/opencode"
    ".config/pi"
    ".factory"
    ".pi"
    ".pi/agent"
  ];
  ownsAncestor = path: lib.any (other: other != path && lib.hasPrefix "${path}/" other) paths;
  selectedPlatform = if isDarwin then "darwin" else "linux";

  preflight = (import ./fleet/preflight.nix { inherit lib pkgs; }) {
    newPaths = paths;
    inherit piGuard;
    legacyPiGuardPath = if piSelected then ".pi/agent/mcp.json" else null;
  };
  modelSync = (import ./fleet/model-sync.nix { inherit lib pkgs; }) {
    inherit (modelData) syncInputs;
  };
  piSelected = lib.any (profileId: catalog.profiles.${profileId}.client == "pi") profileIds;
  codexSelected = lib.any (profileId: catalog.profiles.${profileId}.client == "codex") profileIds;
  droidSelected = lib.any (profileId: catalog.profiles.${profileId}.client == "droid") profileIds;
  droidSettingsConvergence = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    factory_root=${lib.escapeShellArg "${config.xdg.configHome}/factory"}
    managed_settings="$factory_root/nix-managed-settings.json"
    mutable_settings="$factory_root/settings.json"

    if [ -e "$managed_settings" ]; then
      if [ -e "$mutable_settings" ] && { [ ! -f "$mutable_settings" ] || [ -L "$mutable_settings" ]; }; then
        printf 'nix-managed AI: refusing non-regular Factory settings path: %s\n' \
          "$mutable_settings" >&2
        exit 1
      fi

      ${pkgs.jq}/bin/jq -e '.customModels | type == "array"' \
        "$managed_settings" >/dev/null
      if [ -e "$mutable_settings" ]; then
        ${pkgs.jq}/bin/jq -e 'type == "object"' "$mutable_settings" >/dev/null
        settings_tmp="$(${pkgs.coreutils}/bin/mktemp \
          "$factory_root/.settings.json.XXXXXX")"
        trap '${pkgs.coreutils}/bin/rm -f -- "$settings_tmp"' EXIT
        ${pkgs.jq}/bin/jq --slurpfile managed "$managed_settings" \
          '.customModels = $managed[0].customModels' \
          "$mutable_settings" >"$settings_tmp"
        ${pkgs.coreutils}/bin/chmod --reference="$mutable_settings" "$settings_tmp"
        if ! ${pkgs.diffutils}/bin/cmp -s "$mutable_settings" "$settings_tmp"; then
          ${pkgs.coreutils}/bin/mv -f -- "$settings_tmp" "$mutable_settings"
        fi
        ${pkgs.coreutils}/bin/rm -f -- "$settings_tmp"
        trap - EXIT
      else
        ${pkgs.coreutils}/bin/install -m 0600 "$managed_settings" "$mutable_settings"
      fi
    fi
  '';
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
    {
      assertion = homeClassKnown;
      message = "set nixManagedAiHomeClass to one of clio, hera, shared-work, vps, vulcan, or personal-linux";
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
      assertion = builtins.length rawPaths == builtins.length paths;
      message = "nix-managed AI profiles contain duplicate target paths";
    }
    {
      assertion = builtins.all validRelativePath paths;
      message = "nix-managed AI rendered an unsafe relative path";
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
      assertion = companionsAreOwned;
      message = "nix-managed AI companion metadata names an unowned path";
    }
    {
      assertion = builtins.length piGuards == (if piSelected then 1 else 0);
      message = "nix-managed AI Pi selection must have exactly one mutable guard";
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
      assertion = !piSelected || pairedAgentResources != null;
      message = "inputs.nix-config-ai.packages.${system}.agent-resources is missing";
    }
    {
      assertion = !piSelected || pairedPiGallery != null;
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
      lib.optional droidSelected pkgs.agent-http-header-bridge
      ++ lib.optional (pairedPiPackage != null) pairedPiPackage
      ++ lib.optionals piSelected piRuntimePackages;
    sessionVariables = lib.optionalAttrs codexSelected {
      OMLX_API_KEY = "dummy-key";
      LLAMA_SWAP_API_KEY = "dummy-key";
    };
    activation = {
      aiManagedPreflight = preflight.activation;
      aiRetiredMcpCleanup = retiredMcpCleanup.activation;
    }
    // lib.optionalAttrs piSelected {
      aiPiProfileMigration = piProfileMigration.activation;
      aiPiLegacyRootLink = piProfileMigration.legacyRootActivation;
    }
    // lib.optionalAttrs droidSelected {
      aiDroidSettingsConvergence = droidSettingsConvergence;
    }
    // lib.optionalAttrs (config.johnw.host.isHera && isDarwin) {
      aiManagedModelSync = modelSync.activation;
    };
  };
}
