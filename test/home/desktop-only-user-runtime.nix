{
  darwinConfigurations,
  homeConfigurations,
  nixosHomeEvaluationFixtures,
  pkgs,
}:

let
  inherit (pkgs) lib;

  requiredDesktopPackages = [
    "eask-cli"
    "emacs-lsp-booster"
    "git-crypt"
    "git-secret"
    "gnupg"
    "paperkey"
    "pass-env"
    "pass-git-helper"
  ];
  retainedPortableSecurityPackages = [
    "opensc"
    "openssl"
  ];
  packageOrderMarkers = [
    "git-cliff"
    "git-crypt"
    "git-delete-merged-branches"
    "git-repo"
    "git-secret"
    "git-series"
    "git-repo"
    "openssl"
    "paperkey"
    "pass-git-helper"
    "sshfs-fuse"
  ];
  forbiddenRuntimeRoots = [
    "eask-cli"
    "emacs-lsp-booster"
    "git-crypt"
    "git-secret"
    "gnupg"
    "paperkey"
    "pass"
    "password-store"
  ];
  forbiddenEnvironmentNames = [
    "EDITOR"
    "EMACS_SERVER_FILE"
    "EMACSVER"
    "RCLONE_PASSWORD_COMMAND"
    "RESTIC_PASSWORD_COMMAND"
    "SSH_AUTH_SOCK"
  ];

  packageName =
    package:
    if (package.pname or null) != null then
      package.pname
    else if (package.name or null) != null then
      package.name
    else
      throw "desktop-only-user-runtime: encountered an unnamed home package";
  matchesPackage = root: name: name == root || lib.hasPrefix "${root}-" name;
  isEmacsName = name: builtins.match ".*[Ee][Mm][Aa][Cc][Ss].*" name != null;
  isForbiddenRuntimeName =
    name: isEmacsName name || builtins.any (root: matchesPackage root name) forbiddenRuntimeRoots;
  stripStoreHash =
    path:
    let
      name = lib.removeSuffix ".drv" (builtins.baseNameOf path);
      match = builtins.match "[^-]+-(.*)" name;
    in
    if match == null then name else builtins.head match;
  stringContains = needle: value: builtins.isString value && lib.hasInfix needle value;
  hasAttr = name: attrs: builtins.hasAttr name attrs;

  mkSurface =
    label: config:
    let
      packageNames = map packageName config.home.packages;
      sessionVariables = config.home.sessionVariables or { };
      homeFiles = config.home.file or { };
      gitSettings = config.programs.git.settings or { };
      gitSigning = config.programs.git.signing or { };
      ghSettings = config.programs.gh.settings or { };
      emailAccounts = lib.attrByPath [ "accounts" "email" "accounts" ] { } config;
      emailPasswordCommands = map (account: account.passwordCommand or "") (
        builtins.attrValues emailAccounts
      );
      gitCoreEditor = lib.attrByPath [ "core" "editor" ] "" gitSettings;
      gitCredentialHelper = lib.attrByPath [ "credential" "helper" ] "" gitSettings;
      ghEditor = ghSettings.editor or "";

      # Root the reference check only at command-bearing user configuration.
      # This catches a hidden package reference without realizing a full Home
      # Manager closure or printing any option value.
      runtimeOptions = builtins.toJSON {
        inherit emailPasswordCommands sessionVariables;
        git = gitSettings;
        gh = ghSettings;
      };
      runtimeText = builtins.unsafeDiscardStringContext runtimeOptions;
      runtimeReferenceNames = map stripStoreHash (
        builtins.attrNames (builtins.getContext runtimeOptions)
      );
    in
    {
      inherit label packageNames;
      capabilities = config.johnw.host;
      hasAllDesktopPackages = builtins.all (
        name: builtins.elem name packageNames
      ) requiredDesktopPackages;
      hasEmacsPackage = builtins.any isEmacsName packageNames;
      hasForbiddenRuntimePackage = builtins.any isForbiddenRuntimeName packageNames;
      hasPortableSecurityPackages = builtins.all (
        name: builtins.elem name packageNames
      ) retainedPortableSecurityPackages;
      preservesDesktopPackageOrder =
        builtins.filter (name: builtins.elem name packageOrderMarkers) packageNames == packageOrderMarkers;

      passwordStoreEnabled = config.programs.password-store.enable or false;
      gpgEnabled = config.programs.gpg.enable or false;
      gpgAgentEnabled = config.services.gpg-agent.enable or false;
      browserpassEnabled = config.programs.browserpass.enable or false;
      hasEmacsFile = hasAttr ".emacs.d" homeFiles;
      hasGnuPgFile = hasAttr ".gnupg" homeFiles;
      hasEmacsEnvironment =
        hasAttr "EDITOR" sessionVariables
        && hasAttr "EMACS_SERVER_FILE" sessionVariables
        && hasAttr "EMACSVER" sessionVariables;
      hasForbiddenEnvironment = builtins.any (
        name: hasAttr name sessionVariables
      ) forbiddenEnvironmentNames;
      hasAllDesktopEnvironment = builtins.all (
        name: hasAttr name sessionVariables
      ) forbiddenEnvironmentNames;
      editorUsesEmacs = builtins.any (stringContains "emacs") [
        (sessionVariables.EDITOR or "")
        gitCoreEditor
        ghEditor
      ];
      hasEmailAccount = emailAccounts != { };
      gitOpenPgpEnabled =
        (gitSigning.format or null) == "openpgp"
        && (gitSigning.key or null) != null
        && (gitSigning.signByDefault or false) == true
        && (lib.attrByPath [ "commit" "gpgsign" ] false gitSettings) == true;
      gitUsesOpenPgpFormat = (gitSigning.format or null) == "openpgp";
      hasGpgOpenPgpProgram = lib.hasAttrByPath [
        "gpg"
        "openpgp"
        "program"
      ] gitSettings;
      gitCredentialUsesPass = stringContains "pass-git-helper" gitCredentialHelper;
      hasPassBackedRuntime =
        lib.hasInfix "/bin/pass" runtimeText || lib.hasInfix "pass-git-helper" runtimeText;
      hasForbiddenRuntimeReference = builtins.any isForbiddenRuntimeName runtimeReferenceNames;
      nonDarwinRegistryRowsUnsigned = builtins.all (
        host: host.activation == "darwin" || (host.signing == "none" && host.signingKey == null)
      ) (builtins.attrValues config.johnw.hostRegistry);
    };

  positiveSurfaces = lib.mapAttrsToList (
    label: configuration:
    (mkSurface label configuration.config.home-manager.users.johnw)
    // {
      systemGpgAgentEnabled = configuration.config.programs.gnupg.agent.enable or false;
      hasSystemGpgAgent = lib.hasAttrByPath [
        "launchd"
        "user"
        "agents"
        "gnupg-agent"
      ] configuration.config;
    }
  ) darwinConfigurations;
  negativeSurfaces = lib.mapAttrsToList (label: configuration: mkSurface label configuration.config) (
    homeConfigurations // nixosHomeEvaluationFixtures
  );

  check = ok: message: { inherit ok message; };
  coverageChecks = [
    (check (builtins.any (
      surface: surface.capabilities.isHera
    ) positiveSurfaces) "missing Hera surface")
    (check (builtins.any (
      surface: surface.capabilities.isClio
    ) positiveSurfaces) "missing Clio surface")
    (check (builtins.any (
      surface: surface.capabilities.isVulcan
    ) negativeSurfaces) "missing Vulcan surface")
    (check (builtins.any (surface: surface.capabilities.isVps) negativeSurfaces) "missing VPS surface")
    (check (builtins.any (
      surface: surface.capabilities.isSharedWork
    ) negativeSurfaces) "missing shared-work surface")
    (check (builtins.any (
      surface: surface.capabilities.isCiFixture && !surface.capabilities.isSharedWork
    ) negativeSurfaces) "missing generic personal-Linux surface")
    (check (builtins.all (
      surface: surface.capabilities.isDarwinWorkstation
    ) positiveSurfaces) "positive set contains a non-workstation surface")
    (check (builtins.all (
      surface: !surface.capabilities.isDarwinWorkstation
    ) negativeSurfaces) "negative set contains a Darwin workstation")
  ];
  positiveChecks = lib.concatMap (surface: [
    (check surface.hasAllDesktopPackages "${surface.label}: missing desktop-only package")
    (check surface.hasEmacsPackage "${surface.label}: missing Emacs package environment")
    (check surface.preservesDesktopPackageOrder "${surface.label}: desktop package order changed")
    (check surface.hasPortableSecurityPackages "${surface.label}: missing portable smart-card/TLS package")
    (check (
      surface.passwordStoreEnabled
      && surface.gpgEnabled
      && surface.gpgAgentEnabled
      && surface.browserpassEnabled
    ) "${surface.label}: desktop password/GnuPG programs are not all enabled")
    (check (
      surface.hasEmacsFile && surface.hasGnuPgFile
    ) "${surface.label}: desktop compatibility link is missing")
    (check (
      surface.hasEmacsEnvironment && surface.hasAllDesktopEnvironment && surface.editorUsesEmacs
    ) "${surface.label}: desktop editor/GnuPG environment is incomplete")
    (check surface.hasEmailAccount "${surface.label}: desktop email account is missing")
    (check (
      surface.gitOpenPgpEnabled && surface.gitCredentialUsesPass
    ) "${surface.label}: desktop Git signing/credential configuration is incomplete")
    (check (
      surface.hasPassBackedRuntime && surface.hasForbiddenRuntimeReference
    ) "${surface.label}: runtime reference scan is vacuous")
    (check (
      surface.systemGpgAgentEnabled && surface.hasSystemGpgAgent
    ) "${surface.label}: nix-darwin GnuPG agent ownership is missing")
    (check surface.nonDarwinRegistryRowsUnsigned "${surface.label}: non-Darwin registry signing policy leaked")
  ]) positiveSurfaces;
  negativeChecks = lib.concatMap (surface: [
    (check (!surface.hasForbiddenRuntimePackage) "${surface.label}: desktop-only package leaked")
    (check surface.hasPortableSecurityPackages "${surface.label}: portable smart-card/TLS package was removed")
    (check (
      !surface.passwordStoreEnabled
      && !surface.gpgEnabled
      && !surface.gpgAgentEnabled
      && !surface.browserpassEnabled
    ) "${surface.label}: password/GnuPG program or service is enabled")
    (check (
      !surface.hasEmacsFile && !surface.hasGnuPgFile
    ) "${surface.label}: desktop compatibility link leaked")
    (check (
      !surface.hasEmacsEnvironment && !surface.hasForbiddenEnvironment && !surface.editorUsesEmacs
    ) "${surface.label}: desktop editor/GnuPG environment leaked")
    (check (!surface.hasEmailAccount) "${surface.label}: pass-backed email account leaked")
    (check (
      !surface.gitOpenPgpEnabled && !surface.gitCredentialUsesPass
    ) "${surface.label}: OpenPGP signing or pass credential helper leaked")
    (check (
      !surface.gitUsesOpenPgpFormat && !surface.hasGpgOpenPgpProgram
    ) "${surface.label}: OpenPGP format/program leaked")
    (check (
      !surface.hasPassBackedRuntime && !surface.hasForbiddenRuntimeReference
    ) "${surface.label}: forbidden runtime package reference leaked")
    (check surface.nonDarwinRegistryRowsUnsigned "${surface.label}: non-Darwin registry signing policy leaked")
  ]) negativeSurfaces;
  failures = map (result: result.message) (
    builtins.filter (result: !result.ok) (coverageChecks ++ positiveChecks ++ negativeChecks)
  );
in
if failures == [ ] then
  pkgs.runCommand "desktop-only-user-runtime" { } ''
    touch "$out"
  ''
else
  throw "desktop-only-user-runtime failed:\n${lib.concatStringsSep "\n" failures}"
