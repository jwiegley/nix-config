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

  catalog = import ./ai/catalog.nix {
    inherit lib;
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
      llmAgents = moduleInputs.llm-agents;
    };
    droid = import ./ai/renderers/droid.nix {
      inherit lib;
      pkgs = rendererPkgs;
    };
    pi = import ./ai/renderers/pi.nix {
      inherit lib;
      pkgs = piRendererPkgs;
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
  sharedSkillItems = lib.foldl' (
    skills: profileId:
    let
      profile = catalog.profiles.${profileId};
    in
    if
      builtins.elem profile.client [
        "codex"
        "pi"
      ]
    then
      skills // (selectedFor profileId).skills
    else
      skills
  ) { } profileIds;
  sharedSkillFiles = lib.mapAttrs' (
    name: item: lib.nameValuePair ".agents/skills/${name}" { inherit (item) source; }
  ) sharedSkillItems;
  renderProfile =
    profileId:
    let
      profile = catalog.profiles.${profileId};
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
      }
    );

  renderedProfiles = map renderProfile profileIds;
  rawPaths =
    builtins.attrNames sharedSkillFiles
    ++ lib.concatMap (rendered: builtins.attrNames rendered.files) renderedProfiles;
  paths = lib.sort builtins.lessThan (lib.unique rawPaths);
  mergedFiles = lib.foldl' (
    files: rendered: files // rendered.files
  ) sharedSkillFiles renderedProfiles;
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
    ".config/pi"
    ".factory"
    ".pi"
    ".pi/agent"
  ];
  ownsAncestor = path: lib.any (other: other != path && lib.hasPrefix "${path}/" other) paths;
  selectedPlatform = if isDarwin then "darwin" else "linux";
  xdgConfigRelative = lib.removePrefix "${config.home.homeDirectory}/" config.xdg.configHome;
  piAgentRelative = "${xdgConfigRelative}/pi/agent";
  piBlackholeConfigPath = "${piAgentRelative}/pi-blackhole/pi-blackhole-config.json";
  retiredAutoCompactPath = "${piAgentRelative}/extensions/auto-compact-resume/index.ts";

  preflight = (import ./ai/preflight.nix { inherit lib pkgs; }) {
    newPaths = paths;
    inherit piGuard;
    piAliasTarget = if piSelected then "${xdgConfigRelative}/pi" else null;
    blackholeConfigPath = if piSelected then piBlackholeConfigPath else null;
    retiredPaths = lib.optional piSelected retiredAutoCompactPath;
  };
  modelSync = import ./ai/model-sync.nix { inherit lib pkgs; };
  piSelected = lib.any (profileId: catalog.profiles.${profileId}.client == "pi") profileIds;
  codexSelected = lib.any (profileId: catalog.profiles.${profileId}.client == "codex") profileIds;
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
  blackholePolicy = {
    memory = true;
    compaction = "auto";
    compactionEngine = "blackhole";
    midRunCompaction = "resume";
  };
  blackholePolicyActivation = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    (
      set -euo pipefail
      umask 077

      config_path="$HOME/${piBlackholeConfigPath}"
      config_dir="''${config_path%/*}"

      if [[ -v DRY_RUN ]]; then
        printf '%s\n' \
          "Would reconcile Pi Blackhole memory and compaction policy in $config_path"
        exit 0
      fi

      if [ -L "$config_dir" ] || { [ -e "$config_dir" ] && [ ! -d "$config_dir" ]; }; then
        printf '%s\n' \
          "nix-managed AI: $config_dir must be a directory" >&2
        exit 1
      fi
      if [ -L "$config_path" ] || { [ -e "$config_path" ] && [ ! -f "$config_path" ]; }; then
        printf '%s\n' \
          "nix-managed AI: $config_path must be a regular file" >&2
        exit 1
      fi
      if [ -f "$config_path" ] \
        && ! ${pkgs.jq}/bin/jq -e 'type == "object"' "$config_path" >/dev/null 2>&1
      then
        printf '%s\n' \
          "nix-managed AI: refusing to replace invalid Pi Blackhole configuration" >&2
        exit 1
      fi

      ${pkgs.coreutils}/bin/mkdir -p -- "$config_dir"
      ${pkgs.coreutils}/bin/chmod 0700 "$config_dir"
      temporary_config="$(${pkgs.coreutils}/bin/mktemp \
        "$config_dir/.pi-blackhole-config.XXXXXX")"
      cleanup_blackhole_config() {
        ${pkgs.coreutils}/bin/rm -f -- "$temporary_config"
      }
      trap cleanup_blackhole_config EXIT
      trap 'exit 129' HUP
      trap 'exit 130' INT
      trap 'exit 143' TERM

      if [ -f "$config_path" ]; then
        ${pkgs.jq}/bin/jq -S --argjson policy ${lib.escapeShellArg (builtins.toJSON blackholePolicy)} '
          del(.overrideDefaultCompaction, .noAutoCompact, .passive) + $policy
        ' "$config_path" > "$temporary_config"
      else
        ${pkgs.jq}/bin/jq -S -n \
          --argjson policy ${lib.escapeShellArg (builtins.toJSON blackholePolicy)} \
          '$policy' > "$temporary_config"
      fi
      ${pkgs.coreutils}/bin/chmod 0600 "$temporary_config"

      if [ -f "$config_path" ] \
        && ${pkgs.diffutils}/bin/cmp -s "$temporary_config" "$config_path"
      then
        ${pkgs.coreutils}/bin/rm -f -- "$temporary_config"
        ${pkgs.coreutils}/bin/chmod 0600 "$config_path"
      else
        ${pkgs.coreutils}/bin/mv -fT -- "$temporary_config" "$config_path"
      fi
      trap - EXIT HUP INT TERM
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
    }
    // lib.optionalAttrs piSelected {
      aiManagedPiBlackholePolicy = blackholePolicyActivation;
    }
    // lib.optionalAttrs (config.johnw.host.isHera && isDarwin) {
      aiManagedModelSync = modelSync.activation;
    };
  };
}
