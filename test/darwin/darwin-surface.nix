# JSON-serializable projection of the seven nix-darwin value surfaces changed by
# the typed-host refactor (#50). This is intentionally wider than the older
# 15-field scratch projection: a parity check cannot protect values it never reads.
darwin:

let
  c = darwin.config;
  helpers = import ./surface-helpers.nix;
  sortNames = builtins.sort builtins.lessThan;
  unreadable = "<unreadable: removed or throwing option>";

  mapAttrs =
    f: attrs:
    builtins.listToAttrs (
      map (name: {
        inherit name;
        value = f name attrs.${name};
      }) (builtins.attrNames attrs)
    );

  jsonValue = value: builtins.fromJSON (builtins.unsafeDiscardStringContext (builtins.toJSON value));

  # tryEval is shallow. deepSeq plus toJSON forces every value in a domain before
  # success is recorded; otherwise a removed nested option can hide behind a green
  # outer attrset. Keep the domain name and a marker when forcing fails.
  tryJsonValue =
    value:
    let
      result = builtins.tryEval (
        builtins.deepSeq value (builtins.unsafeDiscardStringContext (builtins.toJSON value))
      );
    in
    if result.success then builtins.fromJSON result.value else unreadable;

  stringOrNull = value: if value == null then null else toString value;
  normalizeStoreString =
    value:
    builtins.concatStringsSep "" (
      map (part: if builtins.isList part then "/nix/store/<hash>-" else part) (
        builtins.split "/nix/store/[0-9a-df-np-sv-z]{32}-" value
      )
    );
  normalizeStoreValue =
    value:
    if builtins.isString value then
      normalizeStoreString value
    else if builtins.isList value then
      map normalizeStoreValue value
    else if builtins.isAttrs value then
      builtins.mapAttrs (_: normalizeStoreValue) value
    else
      value;
  hashJsonValue =
    value:
    builtins.hashString "sha256" (
      builtins.unsafeDiscardStringContext (builtins.toJSON (normalizeStoreValue value))
    );
  # Authorization values need exact content identity inside their opaque digest.
  # Normalizing a store prefix here would hide rebuilt key files or commands.
  hashExactJsonValue =
    value: builtins.hashString "sha256" (builtins.unsafeDiscardStringContext (builtins.toJSON value));
  projectBuildMachine =
    machine:
    let
      sshKey = machine.sshKey or null;
    in
    (builtins.removeAttrs machine [ "sshKey" ])
    // {
      sshKeySha256 = if sshKey == null then null else hashExactJsonValue (toString sshKey);
    };
in
{
  # S12-S14
  users = {
    knownUsers = c.users.knownUsers;
    knownGroups = c.users.knownGroups;
    names = sortNames (builtins.attrNames c.users.users);
    detail = mapAttrs (
      _: user:
      let
        keys = user.openssh.authorizedKeys.keys or [ ];
        keyFilePaths = user.openssh.authorizedKeys.keyFiles or [ ];
        # Source paths inherit the whole flake's store prefix. Hash file content
        # exactly, but normalize that incidental prefix before the aggregate hash.
        keyFiles = map (path: {
          contentSha256 = builtins.hashFile "sha256" path;
          path = normalizeStoreString (toString path);
        }) keyFilePaths;
      in
      {
        home = stringOrNull (user.home or null);
        shell = stringOrNull (user.shell or null);
        uid = user.uid or null;
        gid = user.gid or null;
        createHome = user.createHome or null;
        description = user.description or null;
        authorizedKeys = {
          keysCount = builtins.length keys;
          keysSha256 = hashExactJsonValue keys;
          keyFilesCount = builtins.length keyFilePaths;
          keyFilesSha256 = hashExactJsonValue keyFiles;
        };
      }
    ) c.users.users;
  };

  # S15-S16
  environment = {
    # Keep `name`, not `pname`: masking versions here would make derivation-name
    # changes invisible even though only the store HASH is supposed to be ignored.
    systemPackages = sortNames (map helpers.derivationName c.environment.systemPackages);
    etc = sortNames (builtins.attrNames c.environment.etc);
    variables = mapAttrs (_: toString) c.environment.variables;
    shells = map toString c.environment.shells;
    pathsToLink = c.environment.pathsToLink;
  };

  # S17
  services.prometheusNode = {
    enable = c.services.prometheus.exporters.node.enable;
    port = c.services.prometheus.exporters.node.port;
    listenAddress = c.services.prometheus.exporters.node.listenAddress;
    enabledCollectors = c.services.prometheus.exporters.node.enabledCollectors;
  };

  # S18-S19
  homebrew = {
    enable = c.homebrew.enable;
    brews = map (helpers.homebrewName "brew") c.homebrew.brews;
    casks = map (helpers.homebrewName "cask") c.homebrew.casks;
    taps = map (helpers.homebrewName "tap") c.homebrew.taps;
    masApps = c.homebrew.masApps;
    # onActivation is a submodule with a __functor, so project its data fields.
    onActivation = {
      autoUpdate = c.homebrew.onActivation.autoUpdate;
      cleanup = c.homebrew.onActivation.cleanup;
      upgrade = c.homebrew.onActivation.upgrade;
    };
  };

  # S20-S22. These hosts deliberately set nix.enable=false because Determinate
  # owns the daemon. Reading only config.nix behind an enable guard made the old
  # snapshot vacuous: it emitted only { enable = false; } and missed both host
  # predicates. Module option values retain the configured settings and builders.
  nix = {
    enable = c.nix.enable;
    settings = jsonValue darwin.options.nix.settings.value;
    maxJobs = darwin.options.nix.settings.value.max-jobs;
    distributedBuilds = darwin.options.nix.distributedBuilds.value;
    buildMachines = map projectBuildMachine (jsonValue darwin.options.nix.buildMachines.value);
  };

  # S23-S25
  system = {
    primaryUser = c.system.primaryUser or null;
    stateVersion = c.system.stateVersion;
    postActivation = c.system.activationScripts.postActivation.text or "";
    activationScripts = sortNames (builtins.attrNames c.system.activationScripts);

    # system.defaults contains removed options that throw on read (currently
    # alf.allowdownloadsignedenabled). Force one domain at a time so readable
    # neighbors remain protected and an unreadable domain is recorded by name.
    defaults = mapAttrs (_: tryJsonValue) c.system.defaults;
  };

  # S26-S29. launchd.agents is empty on both hosts. The real repository services
  # are launchd.user.agents and launchd.daemons, so retain all three as a tripwire.
  # Hash complete serviceConfig and script data after store-path normalization.
  # This keeps every behavioral change visible without committing credentials
  # that launchd command arguments or environment variables may contain.
  launchd =
    let
      project = agent: {
        serviceConfigSha256 = hashJsonValue agent.serviceConfig;
        scriptSha256 =
          let
            script = agent.script or null;
          in
          if script == null then
            null
          else
            builtins.hashString "sha256" (normalizeStoreString (builtins.unsafeDiscardStringContext script));
      };
    in
    {
      userAgentNames = sortNames (builtins.attrNames c.launchd.user.agents);
      daemonNames = sortNames (builtins.attrNames c.launchd.daemons);
      agentNames = sortNames (builtins.attrNames c.launchd.agents);
      userAgents = mapAttrs (_: project) c.launchd.user.agents;
      daemons = mapAttrs (_: project) c.launchd.daemons;
      agents = mapAttrs (_: project) c.launchd.agents;
    };
}
