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
  resourcePackage = pkgs.agent-resources;
  rendererPkgs = pkgs // {
    agent-resources = resourcePackage;
  };

  modelData = import ./ai/models.nix { };
  catalog = import ./ai/catalog.nix {
    inherit lib modelData;
    resources = resourcePackage;
  };
  renderers = {
    claude = import ./ai/renderers/claude.nix {
      inherit lib;
      pkgs = rendererPkgs;
    };
    codex = import ./ai/renderers/codex.nix {
      inherit lib;
      pkgs = rendererPkgs;
      llmAgents = args.inputs.llm-agents;
    };
    droid = import ./ai/renderers/droid.nix {
      inherit lib;
      pkgs = rendererPkgs;
    };
    opencode = import ./ai/renderers/opencode.nix {
      inherit lib;
      pkgs = rendererPkgs;
    };
    pi = import ./ai/renderers/pi.nix {
      inherit lib;
      pkgs = rendererPkgs;
    };
  };

  homeClass = if nixManagedAiHomeClass != null then nixManagedAiHomeClass else hostname;
  profileHost = if homeClass == "personal-linux" then "vps" else homeClass;
  profilesForHome = lib.filterAttrs (_: profile: profile.host == profileHost) catalog.profiles;
  homeClassKnown = profilesForHome != { };
  profileIds = lib.sort builtins.lessThan (builtins.attrNames profilesForHome);

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

  preflight = (import ./ai/preflight.nix { inherit lib pkgs; }) {
    newPaths = paths;
    inherit piGuard;
    legacyPiGuardPath = if piSelected then ".pi/agent/mcp.json" else null;
  };
  modelSync = (import ./ai/model-sync.nix { inherit lib pkgs; }) {
    inherit (modelData) syncInputs;
  };
  piSelected = lib.any (profileId: catalog.profiles.${profileId}.client == "pi") profileIds;
  droidSelected = lib.any (profileId: catalog.profiles.${profileId}.client == "droid") profileIds;
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
  # This module READS config.johnw.host (see the isHera/isCiFixture uses below),
  # so it must DECLARE it rather than assume a parent did. config/johnw.nix does
  # import host-options.nix, which is why every live build worked -- but this file
  # is also imported on its own, and there it evaluated to
  #
  #     error: attribute 'johnw' missing
  #     at config/ai.nix:225:27
  #
  # Module imports are deduplicated by path, so declaring it here is a no-op
  # wherever a parent already did (verified: hera and clio surfaces unchanged).
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
  ];

  home = {
    file = lib.mapAttrs (_: file: file // { force = true; }) mergedFiles;
    packages =
      lib.optional droidSelected pkgs.agent-http-header-bridge
      ++ lib.optionals piSelected piRuntimePackages;
    sessionVariables = lib.optionalAttrs piSelected {
      PI_CODING_AGENT_DIR = "${config.xdg.configHome}/pi";
    };
    activation = {
      aiManagedPreflight = preflight.activation;
    }
    // lib.optionalAttrs piSelected {
      aiPiProfileMigration = piProfileMigration.activation;
    }
    // lib.optionalAttrs (config.johnw.host.isHera && isDarwin) {
      aiManagedModelSync = modelSync.activation;
    };
  };
}
