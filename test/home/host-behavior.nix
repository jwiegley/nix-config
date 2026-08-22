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
  heraPushTankAgent = darwinConfigurations.hera.config.launchd.user.agents.push-tank;
  heraPushTankPackages = darwinConfigurations.hera.pkgs;
  heraPushTankScript = builtins.unsafeDiscardStringContext heraPushTankAgent.script;
  expectedPushTankCommand = builtins.unsafeDiscardStringContext "${heraPushTankPackages.my-scripts}/bin/push tank";
  expectedPushTankScript = ''
    timestamp=$(/bin/date '+%Y-%m-%d %H:%M:%S %Z') || exit
    printf '\n----- push tank: %s -----\n' "$timestamp" || exit
    exec ${expectedPushTankCommand}
  '';
  pushTankMarkerCommand = ''${pkgs.coreutils}/bin/touch "$marker"'';
  pushTankDateFailureProbe = pkgs.writeShellScript "push-tank-date-failure-probe" (
    lib.replaceStrings
      [
        "/bin/date"
        expectedPushTankCommand
      ]
      [
        "${pkgs.coreutils}/bin/false"
        pushTankMarkerCommand
      ]
      heraPushTankScript
  );
  pushTankPrintfFailureProbe = pkgs.writeShellScript "push-tank-printf-failure-probe" (
    lib.replaceStrings [ expectedPushTankCommand ] [ pushTankMarkerCommand ] heraPushTankScript
  );
  expectedPushTankPath = "${
    lib.makeBinPath [
      heraPushTankPackages.bash
      heraPushTankPackages.my-scripts
      heraPushTankPackages.nix-scripts
      heraPushTankPackages.openssh
      heraPushTankPackages.rsync
    ]
  }:/etc/profiles/per-user/johnw/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  gallerySourceFor =
    host:
    desktopHomesByHost.${host}.home.file.".config/pi/agent/extensions/nix-gallery/index.ts".source;
  codexPackageFor =
    host:
    lib.findFirst (
      package: lib.getName package == "codex"
    ) null desktopHomesByHost.${host}.home.packages;
  clioCodexPackage = codexPackageFor "clio";
  heraCodexPackage = codexPackageFor "hera";
  heraPrimePackage = lib.findFirst (
    package: lib.getName package == "prime-agent"
  ) null desktopHomesByHost.hera.home.packages;
  vulcanJumpPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID/5S98ifv/slBhGzSLMK+/3JAHNzzglOfau6RlqKeYs";
  expectedVulcanJumpAuthorization = ''from="192.168.1.2",restrict,port-forwarding,permitopen="andoria-08:22",command="/usr/bin/false" ${vulcanJumpPublicKey} johnw@vulcan'';
  vulcanJumpAuthorizations =
    host:
    builtins.filter (
      key: lib.hasInfix vulcanJumpPublicKey key
    ) darwinConfigurations.${host}.config.users.users.johnw.openssh.authorizedKeys.keys;
  idRsyncPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG5gtakoBc1b52Jkj29dnrFb5ADlXTBf60VOBNbnwcLD";
  expectedIdRsyncAuthorization =
    host:
    let
      forwarding = lib.optionalString (host == "hera") '',port-forwarding,permitopen="andoria-08:22"'';
      rrsync = darwinConfigurations.${host}.pkgs.rrsync;
    in
    ''from="192.168.1.2",restrict${forwarding},command="${rrsync}/bin/rrsync -ro /Users/johnw" ${idRsyncPublicKey} id_rsync'';
  idRsyncAuthorizations =
    host:
    builtins.filter (
      key: lib.hasInfix idRsyncPublicKey key
    ) darwinConfigurations.${host}.config.users.users.johnw.openssh.authorizedKeys.keys;
  expectedVulcanJumpSshdPolicy = ''
    Match User johnw Address 192.168.1.2
      AllowStreamLocalForwarding no
      AllowTcpForwarding local
      PermitListen none
    Match all
  '';
  heraSshdConfig = darwinConfigurations.hera.config.services.openssh.extraConfig;
  clioSshdConfig = darwinConfigurations.clio.config.services.openssh.extraConfig;
  andoria08HostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSVBUazhVay9ucEJZRnB2dURRS1lHNFZmZStPdFAwRDM0RkRlNi9scDdyUnggcm9vdEBwb3NpdHJvbgo=";
  andoriaT2HostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUwzK28xbWVYQkNZSzhQOTBQL2tIYW4xcnVYMkpEcmZrQUZaUklhcjZrbTIK";
  heraHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUU5Mk1uem14L0NWUzZHaUdiSjF2R0MwU2RmK0Q3L3ZTVS9QTjdmMVkxTVYK";
  vulcanHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUl0TUQ4ODYveGxlUzRpaE5QL3lwZ1VieSsyUnd6UFNJVm5CL0k1aTNXRW8gcm9vdEBuaXhvcwo=";
  expectedAndoriaBuilder = {
    mandatoryFeatures = [ ];
    protocol = "ssh-ng";
    speedFactor = 4;
    sshKey = "/Users/johnw/.config/ssh/id_positron";
    sshUser = "jwiegley";
    supportedFeatures = [ "big-parallel" ];
    system = "x86_64-linux";
    systems = [ ];
  };
  expectedAndoriaBuilders = [
    (
      expectedAndoriaBuilder
      // {
        hostName = "andoria-08";
        maxJobs = 1;
        publicHostKey = andoria08HostKey;
      }
    )
    (
      expectedAndoriaBuilder
      // {
        hostName = "andoria-t2";
        maxJobs = 1;
        publicHostKey = andoriaT2HostKey;
      }
    )
  ];
  expectedVulcanBuilder = sshKey: {
    hostName = "vulcan.lan";
    mandatoryFeatures = [ ];
    maxJobs = 4;
    protocol = "ssh-ng";
    publicHostKey = vulcanHostKey;
    speedFactor = 2;
    inherit sshKey;
    sshUser = "johnw";
    supportedFeatures = [
      "nixos-test"
      "big-parallel"
      "kvm"
    ];
    system = "aarch64-linux";
    systems = [ ];
  };
  expectedHeraBuilder = {
    hostName = "hera.lan";
    mandatoryFeatures = [ ];
    maxJobs = 24;
    protocol = "ssh-ng";
    publicHostKey = heraHostKey;
    speedFactor = 4;
    sshKey = "/Users/johnw/clio/id_clio";
    sshUser = "johnw";
    supportedFeatures = [ ];
    system = "aarch64-darwin";
    systems = [ ];
  };
  heraBuildMachines = darwinConfigurations.hera.config.nix.buildMachines;
  clioBuildMachines = darwinConfigurations.clio.config.nix.buildMachines;
  heraEtc = darwinConfigurations.hera.config.environment.etc;
  clioEtc = darwinConfigurations.clio.config.environment.etc;
  heraMachinesEntry = heraEtc."nix/machines";
  clioMachinesEntry = clioEtc."nix/machines";
  clioBuilderSshEntry = clioEtc."ssh/ssh_config.d/050-nix-builders.conf";
  clioBuilderKnownHostsEntry = clioEtc."nix/builder-known-hosts";
  expectedHeraMachinesFile = ''
    ssh-ng://johnw@vulcan.lan aarch64-linux /Users/johnw/hera/id_hera 4 2 nixos-test,big-parallel,kvm - ${vulcanHostKey}
    ssh-ng://jwiegley@andoria-08 x86_64-linux /Users/johnw/.config/ssh/id_positron 1 4 big-parallel - ${andoria08HostKey}
    ssh-ng://jwiegley@andoria-t2 x86_64-linux /Users/johnw/.config/ssh/id_positron 1 4 big-parallel - ${andoriaT2HostKey}
  '';
  expectedClioMachinesFile = ''
    ssh-ng://johnw@hera.lan aarch64-darwin /Users/johnw/clio/id_clio 24 4 - - ${heraHostKey}
    ssh-ng://johnw@vulcan.lan aarch64-linux /Users/johnw/clio/id_clio 4 2 nixos-test,big-parallel,kvm - ${vulcanHostKey}
    ssh-ng://jwiegley@andoria-08 x86_64-linux /Users/johnw/.config/ssh/id_positron 1 4 big-parallel - ${andoria08HostKey}
    ssh-ng://jwiegley@andoria-t2 x86_64-linux /Users/johnw/.config/ssh/id_positron 1 4 big-parallel - ${andoriaT2HostKey}
  '';
  expectedClioBuilderSshConfig = ''
    Host andoria-08 andoria-t2
      ProxyCommand ssh -o BatchMode=yes -o IdentitiesOnly=yes -o UserKnownHostsFile=/etc/nix/builder-known-hosts -o StrictHostKeyChecking=yes -i /Users/johnw/clio/id_clio -W %h:%p johnw@hera.lan
  '';
  expectedClioBuilderKnownHosts = ''
    hera.lan ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE92Mnzmx/CVS6GiGbJ1vGC0Sdf+D7/vSU/PN7f1Y1MV
  '';
  expectedBuilderReload = machinesEntry: coreutils: nixPackage: ''
    # nix-darwin does not reload Determinate's daemon when `nix.enable = false`.
    # Compare against the previous generation, which is still current here.
    if ! /usr/bin/cmp -s /run/current-system/etc/nix/machines ${machinesEntry.source}; then
      echo "reloading Determinate Nix builder configuration..." >&2
      /bin/launchctl kickstart -k system/systems.determinate.nix-daemon
      nix_daemon_ready=0
      # A cold Determinate daemon can take several seconds to accept the
      # first client after kickstart, especially on Clio.
      for _ in {1..6}; do
        if ${coreutils}/bin/timeout --signal=KILL 5s \
          ${nixPackage}/bin/nix store info --store daemon >/dev/null 2>&1; then
          nix_daemon_ready=1
          break
        fi
        /bin/sleep 0.25
      done
      if (( ! nix_daemon_ready )); then
        echo "Determinate Nix daemon did not become ready" >&2
        exit 1
      fi
    fi
  '';
  desktopHomes = builtins.attrValues desktopHomesByHost;
  registry = import ../../config/hosts/registry.nix;
  nixTrust = import ../../config/nix-trust.nix;
  aiCatalog = import ../../config/ai/catalog.nix {
    inherit lib;
    resources = pkgs.agent-resources;
  };
  expectedPiGalleryEndpointsByOwner =
    (import ../../config/ai/renderers/project-provider-endpoints.nix { inherit lib; })
      {
        definitions = (import ../../config/ai/model-overrides.nix).pi.galleryProviders;
        endpoints = aiCatalog.piModelDiscoveryEndpoints;
      };
  recordingTranscriptionPath = ".config/transcribe/llm-route.json";
  recordingTranscriptionRoute = aiCatalog.recordingTranscriptionRoutesByHost.hera;
  heraRecordingTranscriptionSource =
    desktopHomesByHost.hera.home.file.${recordingTranscriptionPath}.source;
  expectedRecordingTranscriptionSource = (pkgs.formats.json { }).generate "expected-llm-route.json" {
    version = 2;
    inherit (recordingTranscriptionRoute) model;
    base_url = aiCatalog.localModelEndpointsByHost.hera.${recordingTranscriptionRoute.provider};
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
  packageSelectionFor =
    hostname:
    (import ../../config/packages.nix {
      inherit hostname;
      inherit (nixosHomeEvaluationFixtures.vps) pkgs;
      inherit (nixosHomeEvaluationFixtures.vps._module.specialArgs) inputs;
    }).package-list;
  physicalSharedWorkPackages = packageSelectionFor "andoria-08";
  physicalMaintainedPackages = packageSelectionFor "vps";
  heraPackageSelection = import ../../config/packages.nix {
    hostname = "hera";
    inherit (darwinConfigurations.hera) pkgs;
    inherit (darwinConfigurations.hera._module.specialArgs) inputs;
  };
  expectedHeraSourceProjectInputs = [
    "gh-to-org"
    "git-all"
    "gitlib"
    "hours"
    "org-jw"
    "org2jsonl"
    "pushme"
    "rag-client"
    "renamer"
    "rust-overlay"
    "sizes"
    "trade-journal"
    "una"
  ];
  expectedSharedWorkNixConfig = ''
    max-jobs = 1
    cores = 8
    experimental-features = nix-command flakes
    extra-substituters = ${nixTrust.caches.iog.url}
    substituters = ${nixTrust.caches.nixos.url} ${nixTrust.caches.tron.url}
  '';
  unknownHomeClassContract = registry.homeClassContractFor "unknown";
  unknownHomeClassMessagePrefix = "set nixManagedAiHomeClass to one of ";
  nonDesktopHomes =
    map (fixture: fixture.config) (builtins.attrValues nixosHomeEvaluationFixtures)
    ++ map (configuration: configuration.config) (builtins.attrValues homeConfigurations);
  allHomes = desktopHomes ++ nonDesktopHomes;
  hasSelectedPackage = name: packages: builtins.elem name (map lib.getName packages);
  hasPackage = name: config: hasSelectedPackage name config.home.packages;
  hasPackagePrefix =
    prefix: config: builtins.any (lib.hasPrefix prefix) (map lib.getName config.home.packages);
  heraGitAll = lib.findFirst (
    package: lib.getName package == "git-all"
  ) null desktopHomesByHost.hera.home.packages;
  gitAllSource = darwinConfigurations.hera._module.specialArgs.inputs.git-all.outPath;
  hasCycloptsPromptTimeout =
    package:
    let
      postPatch = package.postPatch or "";
    in
    lib.hasInfix ''child.expect("ZTEST> ", timeout=4)'' postPatch
    && lib.hasInfix ''child.expect("ZTEST> ", timeout=20)'' postPatch;
  automaticPiExtensions = [
    ".config/pi/agent/extensions/fleet-theme/index.ts"
    ".config/pi/agent/extensions/nix-gallery/index.ts"
    ".config/pi/agent/extensions/pi-loop/index.ts"
    ".config/pi/agent/extensions/pi-mcp-adapter"
    ".config/pi/agent/extensions/pi-quiet"
  ];
  renderedAutomaticPiExtensions =
    config:
    builtins.filter (lib.hasPrefix ".config/pi/agent/extensions/") (
      builtins.attrNames config.home.file
    );
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
  hasSafeLocalModelSessionVariables =
    config:
    let
      variables = config.home.sessionVariables or { };
    in
    (variables.OMLX_API_KEY or null) == null
    && (variables.OMLX_CLIO_API_KEY or null) == null
    && (variables.OMLX_HERA_API_KEY or null) == null
    && (variables.LLAMA_SWAP_API_KEY or null) == "dummy-key";
  lacksLocalModelSessionVariables =
    config:
    let
      variables = config.home.sessionVariables or { };
    in
    (variables.OMLX_API_KEY or null) == null
    && (variables.OMLX_CLIO_API_KEY or null) == null
    && (variables.OMLX_HERA_API_KEY or null) == null
    && (variables.LLAMA_SWAP_API_KEY or null) == null;
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
  hasCycloptsPromptTimeout darwinConfigurations.${host}.pkgs.python3Packages.cyclopts
  && hasCycloptsPromptTimeout darwinConfigurations.${host}.pkgs.python313Packages.cyclopts
) requiredDarwinHosts;
assert vulcanJumpAuthorizations "hera" == [ expectedVulcanJumpAuthorization ];
assert vulcanJumpAuthorizations "clio" == [ ];
assert builtins.all (
  host: idRsyncAuthorizations host == [ (expectedIdRsyncAuthorization host) ]
) requiredDarwinHosts;
assert lib.hasInfix expectedVulcanJumpSshdPolicy heraSshdConfig;
assert !lib.hasInfix "Match User johnw Address 192.168.1.2" clioSshdConfig;
assert builtins.all (
  host:
  darwinConfigurations.${host}.config.networking.hostName == host
  && darwinConfigurations.${host}.config.networking.localHostName == host
) requiredDarwinHosts;
assert
  heraBuildMachines
  == [ (expectedVulcanBuilder "/Users/johnw/hera/id_hera") ] ++ expectedAndoriaBuilders;
assert
  darwinConfigurations.hera.config.nix.settings.trusted-substituters
  == nixTrust.darwin.trustedSubstituters;
assert
  darwinConfigurations.hera.config.nix.settings.trusted-public-keys
  == nixTrust.darwin.trustedPublicKeys;
assert
  darwinConfigurations.clio.config.nix.settings.trusted-substituters
  == nixTrust.darwin.trustedSubstituters;
assert
  darwinConfigurations.clio.config.nix.settings.trusted-public-keys
  == nixTrust.darwin.trustedPublicKeys;
assert
  clioBuildMachines == [
    expectedHeraBuilder
    (expectedVulcanBuilder "/Users/johnw/clio/id_clio")
  ]
  ++ expectedAndoriaBuilders;
assert heraMachinesEntry.enable;
assert heraMachinesEntry.target == "nix/machines";
assert heraMachinesEntry.text == expectedHeraMachinesFile;
assert
  heraMachinesEntry.knownSha256Hashes == [
    "46f63cb24e8924d42d09c6dfcb50b9c4c64c84b137d65ee65f21b4c9f07403ef"
  ];
assert clioMachinesEntry.enable;
assert clioMachinesEntry.target == "nix/machines";
assert clioMachinesEntry.text == expectedClioMachinesFile;
assert
  clioMachinesEntry.knownSha256Hashes == [
    "44c02435dbd05dabf4b972e9575d4ddeceba5d9eca7b30d7788a8388971a85f1"
  ];
assert lib.hasPrefix (
  expectedBuilderReload heraMachinesEntry darwinConfigurations.hera.pkgs.coreutils
    darwinConfigurations.hera.config.nix.package
  + ''
    # Hera hosts LLM services continuously. Reapply sleep=0 on each
    # activation; disksleep and displaysleep remain user-managed.
    /usr/bin/pmset -a sleep 0
  ''
) darwinConfigurations.hera.config.system.activationScripts.postActivation.text;
assert lib.hasPrefix (expectedBuilderReload clioMachinesEntry
  darwinConfigurations.clio.pkgs.coreutils
  darwinConfigurations.clio.config.nix.package
) darwinConfigurations.clio.config.system.activationScripts.postActivation.text;
assert clioBuilderSshEntry.enable;
assert clioBuilderSshEntry.target == "ssh/ssh_config.d/050-nix-builders.conf";
assert clioBuilderSshEntry.text == expectedClioBuilderSshConfig;
assert clioBuilderKnownHostsEntry.enable;
assert clioBuilderKnownHostsEntry.target == "nix/builder-known-hosts";
assert clioBuilderKnownHostsEntry.text == expectedClioBuilderKnownHosts;
assert !(builtins.hasAttr "ssh/ssh_config.d/050-nix-builders.conf" heraEtc);
assert !(builtins.hasAttr "nix/builder-known-hosts" heraEtc);
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
assert builtins.all (
  home: !(home.programs.git-ai.enable or false) && !(home.programs.git-ai.installHooks or false)
) desktopHomes;
assert builtins.all (
  host: (registry.capabilitiesFor { hostname = host; }).isSharedWork
) registry.sharedWork.members;
assert builtins.elem "git-ai" registry.sharedWork.members;
assert !(builtins.elem "git-ai" registry.sharedWork.activeRolloutMembers);
assert builtins.length registry.sharedWork.activeRolloutMembers == 4;
assert registry.sharedWork.nixDaemonAllowedCpus == "0-7";
assert builtins.all (
  host: builtins.elem host registry.sharedWork.members
) registry.sharedWork.activeRolloutMembers;
assert sharedWork.johnw.sharedWork == registry.sharedWork;
assert sharedWork.johnw.hostRouting == registry.routing;
assert sharedWork.xdg.configFile."nix/nix.conf".text == expectedSharedWorkNixConfig;
assert !(builtins.hasAttr "nix/nix.conf" personalLinux.xdg.configFile);
assert nixTrust.determinateLinux.requireSigs;
assert nixTrust.determinateLinux.trustedUsers == [ "root" ];
assert
  nixTrust.determinateLinux.extraSubstituters == [
    nixTrust.caches.tron.url
    nixTrust.caches.iog.url
  ];
assert
  nixTrust.determinateLinux.extraTrustedPublicKeys == [
    nixTrust.caches.tron.publicKey
    nixTrust.caches.iog.publicKey
    nixTrust.clientSigningPublicKey
  ];
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
assert builtins.all (
  config:
  config.programs.zsh.completionInit == ''
    fpath=(${lib.escapeShellArg "${config.xdg.configHome}/zsh/completions"} $fpath)
    autoload -Uz compinit
    compinit -C
  ''
) desktopHomes;
assert builtins.all (
  config: config.home.activation.refreshZshCompletionDump.after == [ "linkGeneration" ]
) desktopHomes;
assert builtins.all (
  config:
  let
    activation = config.home.activation.refreshZshCompletionDump.data;
  in
  lib.hasInfix ''rm -f -- "$completion_dump"'' activation
  && lib.hasInfix "zsh -ic exit" activation
  && lib.hasInfix ''stat -c '%u:%a' "$completion_dump"'' activation
  && lib.hasInfix ''$actual_metadata != "$expected_metadata"'' activation
) desktopHomes;
assert builtins.all (
  config: !(builtins.hasAttr "refreshZshCompletionDump" config.home.activation)
) nonDesktopHomes;
assert builtins.all (config: builtins.hasAttr ".pi" config.home.file) allHomes;
assert builtins.all (
  config: builtins.hasAttr ".config/pi/agent/models.json" config.home.file
) allHomes;
assert builtins.all (
  config: renderedAutomaticPiExtensions config == automaticPiExtensions
) allHomes;
assert builtins.all (
  config: config.home.activation.aiManagedPiBlackholePolicy.after == [ "linkGeneration" ]
) allHomes;
assert builtins.all (hasPackage "unisessions") allHomes;
assert builtins.all (config: !(hasPackage "cass" config) && !(hasPackage "cm" config)) allHomes;
assert builtins.all (config: !(hasPackage "claude-vault" config)) allHomes;
assert builtins.all (
  config: !(hasPackagePrefix "git-ai" config) && !(hasPackagePrefix "cozempic" config)
) allHomes;
assert builtins.all (
  config:
  builtins.all (name: !(lib.hasPrefix "GIT_AI_" name)) (
    builtins.attrNames config.home.sessionVariables
  )
  && !(config.programs.git.settings ? trace2)
) allHomes;
assert builtins.all (config: !(hasPackage "watchman" config)) allHomes;
assert builtins.all (config: !(hasPackage "agdaWithPackages" config)) allHomes;
assert heraGitAll != null;
assert heraGitAll.version == "1.8.1";
assert heraGitAll.src == gitAllSource;
assert heraGitAll.system == "aarch64-darwin";
assert !(hasSelectedPackage "agdaWithPackages" physicalSharedWorkPackages);
assert !(hasSelectedPackage "agdaWithPackages" physicalMaintainedPackages);
assert heraPackageSelection.userPackageInputNames == expectedHeraSourceProjectInputs;
assert builtins.all (hasPackage "obr") allHomes;
assert builtins.all (config: !(ownsObrState config)) allHomes;
assert builtins.all (
  config:
  config.programs.starship.presets == [ "nerd-font-symbols" ]
  && config.programs.starship.settings.add_newline == false
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
assert builtins.all hasSafeLocalModelSessionVariables desktopHomes;
assert clioCodexPackage != null;
assert heraCodexPackage != null;
assert heraPrimePackage != null;
assert builtins.all (
  config:
  config.home.sessionVariables.NODE_EXTRA_CA_CERTS == config.home.sessionVariables.SSL_CERT_FILE
) desktopHomes;
assert builtins.hasAttr recordingTranscriptionPath desktopHomesByHost.hera.home.file;
assert !(builtins.hasAttr recordingTranscriptionPath desktopHomesByHost.clio.home.file);
assert builtins.all (
  config: !(builtins.hasAttr recordingTranscriptionPath config.home.file)
) nonDesktopHomes;
assert desktopHomesByHost.hera.home.sessionVariables.NIX_CONFIG == "cores = 8";
assert desktopHomesByHost.clio.home.sessionVariables.NIX_CONFIG == "cores = 8";
assert builtins.all lacksLocalModelSessionVariables nonDesktopHomes;
assert builtins.hasAttr ".config/pi/agent/model-router.json" desktopHomesByHost.hera.home.file;
assert !(builtins.hasAttr ".config/pi/agent/model-router.json" desktopHomesByHost.clio.home.file);
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
assert !(darwinConfigurations.clio.config.launchd.user.agents ? push-tank);
assert
  heraPushTankAgent.serviceConfig.EnvironmentVariables == {
    HOME = "/Users/johnw";
    LOGNAME = "johnw";
    PATH = expectedPushTankPath;
    SSH_AUTH_SOCK = "/Users/johnw/.config/gnupg/S.gpg-agent.ssh";
    USER = "johnw";
  };
assert !heraPushTankAgent.serviceConfig.RunAtLoad;
assert heraPushTankAgent.serviceConfig.KeepAlive == null;
assert heraPushTankAgent.serviceConfig.StartInterval == 3600;
assert heraPushTankAgent.serviceConfig.StandardOutPath == "/Users/johnw/Library/Logs/push-tank.log";
assert
  heraPushTankAgent.serviceConfig.StandardErrorPath == "/Users/johnw/Library/Logs/push-tank.log";
assert heraPushTankScript == expectedPushTankScript;
pkgs.runCommand "host-behavior" { } ''
  dateMarker="$TMPDIR/push-tank-date-ran"
  if marker="$dateMarker" ${pushTankDateFailureProbe} >/dev/null 2>&1; then
    exit 1
  fi
  test ! -e "$dateMarker"

  printfMarker="$TMPDIR/push-tank-printf-ran"
  if marker="$printfMarker" ${pushTankPrintfFailureProbe} >&- 2>/dev/null; then
    exit 1
  fi
  test ! -e "$printfMarker"

  ${pkgs.diffutils}/bin/cmp -s \
    ${heraRecordingTranscriptionSource} \
    ${expectedRecordingTranscriptionSource}
  ${pkgs.jq}/bin/jq -e '
    type == "object"
    and keys == ["base_url", "model", "version"]
    and .version == 2
    and (.model | type == "string")
    and (.base_url | type == "string")
    and ([keys[] | ascii_downcase | test("credential|key|token|secret")] | any | not)
  ' ${heraRecordingTranscriptionSource} >/dev/null
  grep -F -- ${lib.escapeShellArg "export default createNixGallery(${builtins.toJSON expectedPiGalleryEndpointsByOwner});"} ${gallerySourceFor "clio"} >/dev/null
  grep -F -- ${lib.escapeShellArg "export default createNixGallery(${builtins.toJSON expectedPiGalleryEndpointsByOwner});"} ${gallerySourceFor "hera"} >/dev/null
  if grep -Fq '/usr/bin/security find-generic-password' ${clioCodexPackage}/bin/codex; then
    exit 1
  fi
  if grep -Fq 'nix-config.omlx-clio-client' ${clioCodexPackage}/bin/codex; then
    exit 1
  fi
  grep -F '/usr/bin/security find-generic-password' ${heraCodexPackage}/bin/codex >/dev/null
  grep -F 'nix-config.omlx-hera-client' ${heraCodexPackage}/bin/codex >/dev/null
  grep -F '/usr/bin/security find-generic-password' ${heraPrimePackage}/bin/prime-agent >/dev/null
  grep -F 'nix-config.omlx-hera-client' ${heraPrimePackage}/bin/prime-agent >/dev/null
  test -f "$(dirname "$(realpath ${gallerySourceFor "clio"})")/projection.json"
  test -f "$(dirname "$(realpath ${gallerySourceFor "hera"})")/projection.json"
  touch $out
''
