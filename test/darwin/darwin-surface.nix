# JSON-serializable projection of the seven nix-darwin value surfaces changed by
# the typed-host refactor (#50). This is intentionally wider than the older
# 15-field scratch projection: a parity check cannot protect values it never reads.
darwin:

let
  c = darwin.config;
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
  packageName =
    package: if (package ? pname) && package.pname != null then package.pname else package.name;
in
{
  # S12-S14
  users = {
    knownUsers = c.users.knownUsers;
    knownGroups = c.users.knownGroups;
    names = sortNames (builtins.attrNames c.users.users);
    detail = mapAttrs (_: user: {
      home = stringOrNull (user.home or null);
      shell = stringOrNull (user.shell or null);
      uid = user.uid or null;
      gid = user.gid or null;
      createHome = user.createHome or null;
      description = user.description or null;
    }) c.users.users;
  };

  # S15-S16
  environment = {
    systemPackages = sortNames (map packageName c.environment.systemPackages);
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
    brews = map (brew: if builtins.isString brew then brew else (brew.name or "?")) c.homebrew.brews;
    casks = map (cask: if builtins.isString cask then cask else (cask.name or "?")) c.homebrew.casks;
    taps = map (tap: if builtins.isString tap then tap else (tap.name or "?")) c.homebrew.taps;
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
    buildMachines = jsonValue darwin.options.nix.buildMachines.value;
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
  # Capture complete serviceConfig data rather than a hand-picked subset. Hash
  # script text so same-named behavior changes remain visible without committing
  # command-line credentials that a launchd script may contain.
  launchd =
    let
      project = agent: {
        serviceConfig = jsonValue agent.serviceConfig;
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
