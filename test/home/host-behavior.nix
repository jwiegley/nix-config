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
  desktopHomes = map (configuration: configuration.config.home-manager.users.johnw) (
    builtins.attrValues darwinConfigurations
  );
  sharedWork = homeConfigurations."jwiegley@x86_64-linux".config;
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
  ownsCmState =
    config:
    let
      paths = builtins.attrNames config.home.file;
      roots = [
        ".cass-memory"
        ".cache/cass-memory"
        ".local/share/cass-memory"
      ];
    in
    builtins.any (path: builtins.any (root: path == root || lib.hasPrefix "${root}/" path) roots) paths;
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
assert builtins.all (hasPackage "cass") allHomes;
assert builtins.all (hasPackage "cm") allHomes;
assert builtins.all (config: !(ownsCmState config)) allHomes;
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
