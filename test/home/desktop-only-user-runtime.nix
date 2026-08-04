{
  darwinConfigurations,
  homeConfigurations,
  nixosHomeEvaluationFixtures,
  pkgs,
}:

let
  inherit (pkgs) lib;
  registry = import ../../config/hosts/registry.nix;
  desktopPackages = [
    "eask-cli"
    "emacs-lsp-booster"
    "env-emacs30MacPort"
    "git-crypt"
    "git-secret"
    "gnupg"
    "paperkey"
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
  desktopSigningKey = registry.hosts.hera.signingKey;
  positive = map (host: darwinConfigurations.${host}.config.home-manager.users.johnw) [
    "hera"
    "clio"
  ];
  negative = [
    nixosHomeEvaluationFixtures.vulcan.config
    nixosHomeEvaluationFixtures.vps.config
    homeConfigurations."jwiegley@x86_64-linux".config
    homeConfigurations."johnw@aarch64-linux".config
  ];
  contains = needle: value: builtins.isString value && lib.hasInfix needle value;
  featureFlags =
    config:
    let
      packageNames = map lib.getName config.home.packages;
      variables = config.home.sessionVariables or { };
      files = config.home.file or { };
      git = config.programs.git;
      gitSettings = git.settings or { };
      emailAccounts = builtins.attrValues (config.accounts.email.accounts or { });
      emailPasswordCommands = map (account: account.passwordCommand or "") emailAccounts;
      runtimeOptions = builtins.toJSON {
        inherit emailPasswordCommands variables;
        git = gitSettings;
        gh = config.programs.gh.settings or { };
      };
      runtimeText = builtins.unsafeDiscardStringContext runtimeOptions;
      runtimeReferences = map lib.getName (builtins.attrNames (builtins.getContext runtimeOptions));
      runtimeNameForbidden =
        name:
        builtins.any (root: name == root || lib.hasPrefix "${root}-" name) [
          "emacs"
          "gnupg"
          "pass"
          "password-store"
        ];
    in
    map (name: builtins.elem name packageNames) desktopPackages
    ++ map (name: builtins.hasAttr name variables) desktopVariables
    ++ map (name: builtins.hasAttr name files) [
      ".emacs.d"
      ".gnupg"
    ]
    ++ [
      (config.programs.browserpass.enable or false)
      (config.programs.gpg.enable or false)
      (config.programs.password-store.enable or false)
      (config.services.gpg-agent.enable or false)
      (emailAccounts != [ ])
      (builtins.any (account: (account.gpg.key or null) == desktopSigningKey) emailAccounts)
      ((git.signing.format or null) == "openpgp")
      ((git.signing.key or null) == desktopSigningKey)
      ((git.signing.signByDefault or false) == true)
      ((lib.attrByPath [ "commit" "gpgsign" ] false gitSettings) == true)
      (contains "pass-git-helper" (lib.attrByPath [ "credential" "helper" ] "" gitSettings))
      (contains "emacs" (variables.EDITOR or ""))
      (contains "emacs" (lib.attrByPath [ "core" "editor" ] "" gitSettings))
      (contains "emacs" (config.programs.gh.settings.editor or ""))
      (
        contains "/bin/pass" runtimeText
        || contains "emacs" runtimeText
        || builtins.any runtimeNameForbidden runtimeReferences
      )
    ];
  allTrue = values: builtins.all lib.id values;
  allFalse = values: builtins.all (value: !value) values;
  desktopRegistry = map (host: registry.hosts.${host}) [
    "hera"
    "clio"
  ];
  serverRegistry = map (host: registry.hosts.${host}) [
    "vulcan"
    "vps"
    "andoria"
  ];
in
assert builtins.all (host: host.signing == "openpgp" && host.signingKey != null) desktopRegistry;
assert registry.hosts.clio.signingKey == desktopSigningKey;
assert builtins.all (host: host.signing == "none" && host.signingKey == null) serverRegistry;
assert builtins.all (config: config.johnw.host.isDarwinWorkstation) positive;
assert builtins.all (config: !config.johnw.host.isDarwinWorkstation) negative;
assert builtins.all (config: allTrue (featureFlags config)) positive;
assert builtins.all (config: allFalse (featureFlags config)) negative;
assert builtins.all (
  config: !(lib.hasAttrByPath [ "gpg" "openpgp" "program" ] (config.programs.git.settings or { }))
) negative;
assert builtins.all
  (
    host:
    darwinConfigurations.${host}.config.programs.gnupg.agent.enable
    && lib.hasAttrByPath [ "launchd" "user" "agents" "gnupg-agent" ] darwinConfigurations.${host}.config
  )
  [
    "hera"
    "clio"
  ];
pkgs.runCommand "desktop-only-user-runtime" { } ''
  touch "$out"
''
