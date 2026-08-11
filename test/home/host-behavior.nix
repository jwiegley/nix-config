{
  darwinConfigurations,
  homeConfigurations,
  nixosHomeEvaluationFixtures,
  pkgs,
}:

let
  inherit (pkgs) lib;
  requiredDarwinHosts = [
    "clio"
    "hera"
  ];
  requiredNixosHosts = [
    "vps"
    "vulcan"
  ];
  requiredStandaloneHomes = [
    "johnw@aarch64-linux"
    "jwiegley@x86_64-linux"
  ];
  desktopHomesByHost = lib.mapAttrs (
    _: configuration: configuration.config.home-manager.users.johnw
  ) darwinConfigurations;
  desktopHomes = builtins.attrValues desktopHomesByHost;
  registry = import ../../config/hosts/registry.nix;
  aiCatalog = import ../../config/ai/catalog.nix {
    inherit lib;
    resources = pkgs.agent-resources;
  };
  renderedHostRouting = import ../../config/hosts/shell-routing.nix { inherit lib; };
  personalLinuxResolution = registry.resolveFor {
    hostname = "linux";
    homeClass = "personal-linux";
  };
  sharedWorkResolution = registry.resolveFor {
    hostname = "linux";
    homeClass = "shared-work";
  };
  physicalHostResolution = registry.resolveFor { hostname = "hera"; };
  physicalSharedWorkResolution = registry.resolveFor { hostname = "andoria-08"; };
  unknownHostResolution = registry.resolveFor { hostname = "unknown"; };
  unknownHostCapabilities = registry.capabilitiesFor { hostname = "unknown"; };
  classOverrideResolution = registry.resolveFor {
    hostname = "hera";
    homeClass = "vps";
  };
  classOverridesHostname =
    (lib.evalModules {
      specialArgs = {
        hostname = "hera";
        nixManagedAiHomeClass = "vps";
      };
      modules = [
        ../../config/host-options.nix
        {
          options.assertions = lib.mkOption {
            type = lib.types.listOf lib.types.unspecified;
            default = [ ];
          };
        }
      ];
    }).config;
  personalLinux = homeConfigurations."johnw@aarch64-linux".config;
  sharedWork = homeConfigurations."jwiegley@x86_64-linux".config;
  unknownHomeClassContract = registry.homeClassContractFor "unknown";
  unknownHomeClassMessagePrefix = "set nixManagedAiHomeClass to one of ";
  nonDesktopHomes =
    map (fixture: fixture.config) (builtins.attrValues nixosHomeEvaluationFixtures)
    ++ map (configuration: configuration.config) (builtins.attrValues homeConfigurations);
  allHomes = desktopHomes ++ nonDesktopHomes;
  hasPackage = name: config: builtins.elem name (map lib.getName config.home.packages);
  managedPiExtensions = [
    ".config/pi/agent/extensions/fleet-theme/index.ts"
    ".config/pi/agent/extensions/nix-gallery/index.ts"
    ".config/pi/agent/extensions/pi-loop/index.ts"
    ".config/pi/agent/extensions/pi-mcp-adapter"
    ".config/pi/agent/extensions/pi-quiet"
  ];
  ownsObrState =
    config:
    builtins.any (
      path:
      path == ".obr"
      || lib.hasPrefix ".obr/" path
      || lib.hasInfix "/.obr/" path
      || lib.hasSuffix "/.obr" path
      || path == "PLAN.org"
      || lib.hasSuffix "/PLAN.org" path
    ) (builtins.attrNames config.home.file);
  desktopPackages = [
    "eask-cli"
    "emacs-lsp-booster"
    "env-emacs30MacPort"
    "git-crypt"
    "git-secret"
    "gnupg"
    "paperkey"
    "pinentry-mac"
    "pass-env"
    "pass-git-helper"
  ];
  desktopVariables = [
    "EDITOR"
    "EMACS_SERVER_FILE"
    "EMACSVER"
    "RCLONE_PASSWORD_COMMAND"
    "RESTIC_PASSWORD_COMMAND"
    "SSH_AUTH_SOCK"
  ];
  contains = needle: value: builtins.isString value && lib.hasInfix needle value;
  hasLocalModelSessionVariables =
    config:
    let
      variables = config.home.sessionVariables or { };
    in
    (variables.OMLX_API_KEY or null) == "dummy-key"
    && (variables.LLAMA_SWAP_API_KEY or null) == "dummy-key";
  desktopRuntimeRoots = [
    "emacs"
    "gnupg"
    "pass"
    "password-store"
  ];
  contextPackageName =
    path:
    let
      base = builtins.baseNameOf (lib.removeSuffix ".drv" path);
      match = builtins.match "^[^-]+-(.+)$" base;
    in
    if match == null then base else builtins.head match;
  contextPackageNames =
    value: map contextPackageName (builtins.attrNames (builtins.getContext value));
  isDesktopRuntimeReference =
    name: builtins.any (root: name == root || lib.hasPrefix "${root}-" name) desktopRuntimeRoots;
  runtimeContextProbe = builtins.toJSON { executable = "${pkgs.gnupg}/bin/gpg"; };
  desktopOnlyFlags =
    config:
    let
      variables = config.home.sessionVariables or { };
      git = config.programs.git;
      gitSettings = git.settings or { };
      signingKey = git.signing.key or null;
      emailAccounts = builtins.attrValues (config.accounts.email.accounts or { });
      runtimeOptions = builtins.toJSON {
        emailPasswordCommands = map (account: account.passwordCommand or "") emailAccounts;
        inherit variables;
        git = gitSettings;
        gh = config.programs.gh.settings or { };
      };
      runtimeText = builtins.unsafeDiscardStringContext runtimeOptions;
      runtimeReferences = contextPackageNames runtimeOptions;
    in
    map (name: hasPackage name config) desktopPackages
    ++ map (name: builtins.hasAttr name variables) desktopVariables
    ++ [
      (config.programs.browserpass.enable or false)
      (config.programs.gpg.enable or false)
      (config.programs.password-store.enable or false)
      (config.services.gpg-agent.enable or false)
      (emailAccounts != [ ])
      (builtins.any (
        account: signingKey != null && (account.gpg.key or null) == signingKey
      ) emailAccounts)
      ((git.signing.format or null) == "openpgp")
      (signingKey != null)
      ((git.signing.signByDefault or false) == true)
      ((lib.attrByPath [ "commit" "gpgsign" ] false gitSettings) == true)
      (contains "pass-git-helper" (lib.attrByPath [ "credential" "helper" ] "" gitSettings))
      (contains "emacs" (variables.EDITOR or ""))
      (contains "emacs" (lib.attrByPath [ "core" "editor" ] "" gitSettings))
      (contains "emacs" (config.programs.gh.settings.editor or ""))
      (
        contains "/bin/pass" runtimeText
        || contains "emacs" runtimeText
        || builtins.any isDesktopRuntimeReference runtimeReferences
      )
    ];
  allTrue = values: builtins.all lib.id values;
  allFalse = values: builtins.all (value: !value) values;
in
assert builtins.all (host: builtins.hasAttr host darwinConfigurations) requiredDarwinHosts;
assert builtins.all (
  host:
  darwinConfigurations.${host}.config.networking.hostName == host
  && darwinConfigurations.${host}.config.networking.localHostName == host
) requiredDarwinHosts;
assert builtins.all (host: builtins.hasAttr host nixosHomeEvaluationFixtures) requiredNixosHosts;
assert builtins.all (home: builtins.hasAttr home homeConfigurations) requiredStandaloneHomes;
assert personalLinuxResolution.homeClassRow.catalogHost == "vps";
assert personalLinuxResolution.registryId == null;
assert personalLinuxResolution.registryRow == null;
assert sharedWorkResolution.homeClassRow.catalogHost == "shared-work";
assert sharedWorkResolution.registryId == "andoria";
assert sharedWorkResolution.registryRow != null;
assert (registry.capabilitiesFor { hostname = "hera"; }).isHera;
assert physicalHostResolution.homeClassRow == null;
assert physicalHostResolution.registryId == "hera";
assert physicalHostResolution.registryRow == registry.hosts.hera;
assert physicalSharedWorkResolution.homeClassRow == null;
assert physicalSharedWorkResolution.registryId == "andoria-08";
assert physicalSharedWorkResolution.registryRow == null;
assert unknownHostResolution.homeClassRow == null;
assert unknownHostResolution.registryId == "unknown";
assert unknownHostResolution.registryRow == null;
assert allFalse (builtins.attrValues unknownHostCapabilities);
assert classOverrideResolution.registryId == "vps";
assert classOverrideResolution.registryRow == registry.hosts.vps;
assert personalLinux.johnw.host.isCiFixture;
assert !personalLinux.johnw.host.isSharedWork;
assert personalLinux.johnw.profile.heavy;
assert sharedWork.johnw.host.isCiFixture;
assert sharedWork.johnw.host.isSharedWork;
assert sharedWork.johnw.profile.heavy;
assert !classOverridesHostname.johnw.host.isHera;
assert !classOverridesHostname.johnw.host.isDarwinWorkstation;
assert !classOverridesHostname.johnw.profile.heavy;
assert (registry.capabilitiesFor { hostname = "andoria-08"; }).isSharedWork;
assert (registry.capabilitiesFor { hostname = "git-ai"; }).isSharedWork;
assert builtins.elem "git-ai" registry.sharedWork.members;
assert !(builtins.elem "git-ai" registry.sharedWork.activeRolloutMembers);
assert builtins.length registry.sharedWork.activeRolloutMembers == 4;
assert builtins.all (
  host: builtins.elem host registry.sharedWork.members
) registry.sharedWork.activeRolloutMembers;
assert sharedWork.johnw.sharedWork == registry.sharedWork;
assert sharedWork.johnw.hostRouting == registry.routing;
assert renderedHostRouting == builtins.readFile ../../bin/lib/host-routing.sh;
assert unknownHomeClassContract.row == null;
assert !unknownHomeClassContract.assertion;
assert lib.hasPrefix unknownHomeClassMessagePrefix unknownHomeClassContract.message;
assert
  builtins.stringLength unknownHomeClassContract.message
  > builtins.stringLength unknownHomeClassMessagePrefix;
assert builtins.any isDesktopRuntimeReference (contextPackageNames runtimeContextProbe);
assert
  sharedWork.programs.zsh.history.path == "${sharedWork.xdg.configHome}/zsh/history-\${HOST%%.*}";
assert !sharedWork.programs.zsh.history.share;
assert builtins.elem "INC_APPEND_HISTORY" sharedWork.programs.zsh.setOptions;
assert builtins.all (config: builtins.hasAttr ".pi" config.home.file) allHomes;
assert builtins.all (
  config: builtins.hasAttr ".config/pi/agent/models.json" config.home.file
) allHomes;
assert builtins.all (
  config: builtins.all (path: builtins.hasAttr path config.home.file) managedPiExtensions
) allHomes;
assert builtins.all (
  config: config.home.activation.aiManagedPiBlackholePolicy.after == [ "linkGeneration" ]
) allHomes;
assert builtins.all (hasPackage "unisessions") allHomes;
assert builtins.all (config: !(hasPackage "cass" config) && !(hasPackage "cm" config)) allHomes;
assert builtins.all (hasPackage "obr") allHomes;
assert builtins.all (config: !(ownsObrState config)) allHomes;
assert builtins.all (
  config:
  config.programs.starship.settings.add_newline == false
  && config.programs.starship.settings.format == "$hostname$directory$character"
  && config.programs.starship.settings.hostname.ssh_only == false
  && config.programs.starship.settings.hostname.trim_at == "."
  && config.programs.starship.settings.hostname.format == "[$hostname]($style) "
  && config.programs.starship.settings.directory.format == "[$path]($style) "
  && config.programs.starship.settings.directory.truncation_length == 1
  && config.programs.starship.settings.directory.truncate_to_repo == false
) allHomes;
assert builtins.all (
  config:
  config.programs.gpg.enable
  && config.programs.password-store.enable
  && builtins.hasAttr ".emacs.d" config.home.file
  && builtins.hasAttr ".gnupg" config.home.file
) desktopHomes;
assert builtins.all (
  config:
  !config.programs.gpg.enable
  && !config.programs.password-store.enable
  && !(builtins.hasAttr ".emacs.d" config.home.file)
  && !(builtins.hasAttr ".gnupg" config.home.file)
) nonDesktopHomes;
assert builtins.all (config: config.johnw.host.isDarwinWorkstation) desktopHomes;
assert builtins.all (config: !config.johnw.host.isDarwinWorkstation) nonDesktopHomes;
assert builtins.all hasLocalModelSessionVariables desktopHomes;
assert builtins.all (config: !(hasLocalModelSessionVariables config)) nonDesktopHomes;
assert contains aiCatalog.localModelEndpointsByHost.hera.omlx
  desktopHomesByHost.hera.home.activation.aiManagedModelSync.data;
assert !(builtins.hasAttr "aiManagedModelSync" desktopHomesByHost.clio.home.activation);
assert builtins.all (config: allTrue (desktopOnlyFlags config)) desktopHomes;
assert builtins.all (config: allFalse (desktopOnlyFlags config)) nonDesktopHomes;
assert builtins.all (
  config: !(lib.hasAttrByPath [ "gpg" "openpgp" "program" ] (config.programs.git.settings or { }))
) nonDesktopHomes;
assert builtins.all (
  host:
  darwinConfigurations.${host}.config.programs.gnupg.agent.enable
  && lib.hasAttrByPath [ "launchd" "user" "agents" "gnupg-agent" ] darwinConfigurations.${host}.config
) (builtins.attrNames darwinConfigurations);
pkgs.runCommand "host-behavior" { } "touch $out"
