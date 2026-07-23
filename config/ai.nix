args@{
  config,
  hostname,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  nixManagedAiHomeClass = args.nixManagedAiHomeClass or null;
  inherit (pkgs.stdenv) isDarwin isLinux;
  system = pkgs.stdenv.hostPlatform.system;
  resourcePackage = inputs.ai-nix.packages.${system}.agent-resources;
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

  profilesByHomeClass = {
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
  homeClass =
    if isLinux && config.home.username == "jwiegley" then
      "shared-work"
    else if nixManagedAiHomeClass != null then
      nixManagedAiHomeClass
    else
      hostname;
  homeClassKnown = builtins.hasAttr homeClass profilesByHomeClass;
  profileIds = if homeClassKnown then profilesByHomeClass.${homeClass} else [ ];

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
    in
    renderers.${profile.renderer} {
      inherit profile;
      selected = selectedFor profileId;
      modelData = selectedModelDataFor profileId;
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
    ".factory"
    ".pi"
    ".pi/agent"
  ];
  ownsAncestor = path: lib.any (other: other != path && lib.hasPrefix "${path}/" other) paths;
  selectedPlatform = if isDarwin then "darwin" else "linux";

  preflight = (import ./ai/preflight.nix { inherit lib pkgs; }) {
    newPaths = paths;
    inherit piGuard;
  };
  modelSync = (import ./ai/model-sync.nix { inherit lib pkgs; }) {
    inherit (modelData) syncInputs;
  };
  piSelected = lib.any (profileId: catalog.profiles.${profileId}.client == "pi") profileIds;
  droidSelected = lib.any (profileId: catalog.profiles.${profileId}.client == "droid") profileIds;
in
{
  assertions = [
    {
      assertion = inputs ? ai-nix;
      message = "nix-managed AI requires the ai-nix input";
    }
    {
      assertion = catalog.validate { };
      message = "nix-managed AI catalog validation failed";
    }
    {
      assertion = homeClassKnown;
      message = "nix-managed AI home class is not recognized";
    }
    {
      assertion =
        nixManagedAiHomeClass == null
        || (
          isLinux
          && system == "aarch64-linux"
          && config.home.username == "johnw"
          && hostname == "linux"
          && nixManagedAiHomeClass == "personal-linux"
        );
      message = "nixManagedAiHomeClass is reserved for the personal Linux test fixture";
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
    packages = lib.optional droidSelected inputs.ai-nix.packages.${system}.agent-http-header-bridge;
    activation = {
      aiManagedPreflight = preflight.activation;
    }
    // lib.optionalAttrs (hostname == "hera" && isDarwin) {
      aiManagedModelSync = modelSync.activation;
    };
  };
}
