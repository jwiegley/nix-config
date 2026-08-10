# Declarative host and capability data shared by the module schema in
# config/host-options.nix and the plain package selector in config/packages.nix.
# Keeping this file free of module arguments lets both consumers import the same
# table and pure capability function.

let
  sharedWorkMembers = [
    "andoria-08"
    "andoria-t2"
    "delphi-3bd4"
    "gpu-server"
  ];

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

    # Group four shared-work hostnames under one profile identity.
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
{
  inherit
    homeClasses
    homeClassContractFor
    hosts
    resolveFor
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
      isSharedWork = id == "andoria" || builtins.elem hostname sharedWorkMembers;

      # The synthetic CI evaluation fixtures pin the name to "linux".
      isCiFixture = hostname == "linux";
    };
}
