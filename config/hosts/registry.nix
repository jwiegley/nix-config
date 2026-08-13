# Declarative host, builder, capability, membership, and routing data shared by
# the module schema, package selector, and generated shell projection. Keeping
# this file free of module arguments lets every consumer import the same tables
# and pure capability function.

let
  # Membership is an identity fact, not an availability probe. git-ai remains
  # a real member while dormant; activeRolloutMembers is the deliberately
  # smaller operator target set.
  sharedWork = {
    members = [
      "andoria-08"
      "andoria-t2"
      "delphi-3bd4"
      "git-ai"
      "gpu-server"
    ];
    activeRolloutMembers = [
      "andoria-08"
      "andoria-t2"
      "delphi-3bd4"
      "gpu-server"
    ];
    nixDaemonAllowedCpus = "0-7";
  };

  # Builder identity, capacity, and ordered client pools are host facts. Darwin
  # supplies only the local path for each named SSH identity.
  andoriaBuilder = {
    protocol = "ssh-ng";
    system = hosts.andoria.system;
    sshUser = hosts.andoria.username;
    sshIdentity = "positron";
    maxJobs = 1;
    speedFactor = 4;
    supportedFeatures = [ "big-parallel" ];
  };
  builders = {
    hera = {
      hostName = "hera.lan";
      protocol = "ssh-ng";
      system = hosts.hera.system;
      sshUser = hosts.hera.username;
      sshIdentity = "host";
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUU5Mk1uem14L0NWUzZHaUdiSjF2R0MwU2RmK0Q3L3ZTVS9QTjdmMVkxTVYK";
      maxJobs = 24;
      speedFactor = 4;
    };
    vulcan = {
      hostName = "vulcan.lan";
      protocol = "ssh-ng";
      system = hosts.vulcan.system;
      sshUser = hosts.vulcan.username;
      sshIdentity = "host";
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUl0TUQ4ODYveGxlUzRpaE5QL3lwZ1VieSsyUnd6UFNJVm5CL0k1aTNXRW8gcm9vdEBuaXhvcwo=";
      maxJobs = 4;
      speedFactor = 2;
      supportedFeatures = [
        "nixos-test"
        "big-parallel"
        "kvm"
      ];
    };
    andoria-08 = andoriaBuilder // {
      hostName = "andoria-08";
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSVBUazhVay9ucEJZRnB2dURRS1lHNFZmZStPdFAwRDM0RkRlNi9scDdyUnggcm9vdEBwb3NpdHJvbgo=";
    };
    andoria-t2 = andoriaBuilder // {
      hostName = "andoria-t2";
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUwzK28xbWVYQkNZSzhQOTBQL2tIYW4xcnVYMkpEcmZrQUZaUklhcjZrbTIK";
    };
  };

  builderPools = {
    hera = [
      "vulcan"
      "andoria-08"
      "andoria-t2"
    ];
    clio = [
      "hera"
      "vulcan"
      "andoria-08"
      "andoria-t2"
    ];
  };

  # Canonical host classes and their shell-facing aliases. The shell library
  # is generated from this table; do not duplicate these names in Bash.
  routing = {
    hera = {
      flakeOutput = "hera";
      exactNames = [ ];
      containsNames = [ "hera" ];
    };
    clio = {
      flakeOutput = "clio";
      exactNames = [ ];
      containsNames = [ "clio" ];
    };
    vulcan = {
      flakeOutput = "vulcan";
      exactNames = [ ];
      containsNames = [ "vulcan" ];
    };
    vps = {
      flakeOutput = "ovh-vps";
      exactNames = [ "ovh-vps" ];
      containsNames = [ "srp-next" ];
    };
    shared-work = {
      flakeOutput = "jwiegley";
      exactNames = sharedWork.members;
      containsNames = [ ];
    };
  };

  # Home classes are logical evaluation identities. Keep their catalog and
  # concrete-registry projections separate: the personal-linux fixture selects
  # VPS AI profiles but must not inherit the VPS host row or server-lean role.
  homeClasses = {
    clio = {
      registryId = "clio";
      catalogHost = "clio";
    };
    hera = {
      registryId = "hera";
      catalogHost = "hera";
    };
    personal-linux = {
      registryId = null;
      catalogHost = "vps";
    };
    shared-work = {
      registryId = "andoria";
      catalogHost = "shared-work";
    };
    vps = {
      registryId = "vps";
      catalogHost = "vps";
    };
    vulcan = {
      registryId = "vulcan";
      catalogHost = "vulcan";
    };
  };

  # Host rows plus one shared-work group row.
  hosts = {
    hera = {
      system = "aarch64-darwin";
      activation = "darwin";
      username = "johnw";
      roles = [ ];
    };
    clio = {
      system = "aarch64-darwin";
      activation = "darwin";
      username = "johnw";
      roles = [ ];
    };
    vulcan = {
      system = "aarch64-linux";
      activation = "nixos-module";
      username = "johnw";
      roles = [ "server-lean" ];
    };
    vps = {
      system = "x86_64-linux";
      activation = "nixos-module";
      username = "johnw";
      roles = [ "server-lean" ];
    };

    # Group the shared-work membership under one profile identity.
    andoria = {
      system = "x86_64-linux";
      activation = "home-standalone";
      username = "jwiegley";
      roles = [ ];
    };
  };

  homeClassNames = builtins.attrNames homeClasses;
  homeClassContractFor =
    name:
    let
      row = homeClasses.${name} or null;
    in
    {
      inherit row;
      assertion = row != null;
      message = "set nixManagedAiHomeClass to one of ${builtins.concatStringsSep ", " homeClassNames}";
    };

  resolveFor =
    {
      hostname,
      homeClass ? null,
    }:
    let
      homeClassRow = if homeClass == null then null else (homeClassContractFor homeClass).row;
      registryId = if homeClassRow == null then hostname else homeClassRow.registryId;
    in
    {
      inherit homeClassRow registryId;
      registryRow = if registryId == null then null else hosts.${registryId} or null;
    };

in
assert builtins.all (row: row.registryId == null || builtins.hasAttr row.registryId hosts) (
  builtins.attrValues homeClasses
);
assert builtins.all (host: builtins.elem host sharedWork.members) sharedWork.activeRolloutMembers;
assert builtins.all (pool: builtins.all (builder: builtins.hasAttr builder builders) pool) (
  builtins.attrValues builderPools
);
{
  inherit
    builderPools
    builders
    homeClasses
    homeClassContractFor
    hosts
    routing
    resolveFor
    sharedWork
    ;

  # Pure, total capability derivation. Unknown names never throw: concrete-host
  # flags remain false, while CI-fixture and shared-work flags follow their
  # explicit inputs.
  capabilitiesFor =
    {
      hostname,
      homeClass ? null,
    }:
    let
      resolved = resolveFor { inherit hostname homeClass; };
      id = resolved.registryId;
    in
    {
      isHera = id == "hera";
      isClio = id == "clio";
      isVulcan = id == "vulcan";

      # The two Darwin GUI workstations (hera OR clio).
      isDarwinWorkstation = id == "hera" || id == "clio";

      # Resolve the shared-work group from either its explicit home class or a
      # physical member hostname.
      isSharedWork = id == "andoria" || builtins.elem hostname sharedWork.members;

      # The synthetic CI evaluation fixtures pin the name to "linux".
      isCiFixture = hostname == "linux";
    };
}
