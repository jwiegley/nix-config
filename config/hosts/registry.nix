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

in
{
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

  # Pure, total capability derivation. Unknown names never throw: concrete-host
  # flags remain false, while CI-fixture and shared-work flags follow their
  # explicit inputs.
  capabilitiesFor =
    {
      hostname,
      homeClass ? null,
    }:
    let
      # Keep raw host-identity comparisons localized in this registry.
      id = hostname;
      # An explicit home class supplies group classification; physical
      # shared-work membership is also recognized below.
      cls = if homeClass != null then homeClass else id;
    in
    {
      isHera = id == "hera";
      isClio = id == "clio";
      isVulcan = id == "vulcan";

      # The two Darwin GUI workstations (hera OR clio).
      isDarwinWorkstation = id == "hera" || id == "clio";

      # Resolve the shared-work group from either its explicit home class or a
      # physical member hostname.
      isSharedWork = cls == "shared-work" || builtins.elem id sharedWorkMembers;

      # The synthetic CI evaluation fixtures pin the name to "linux".
      isCiFixture = id == "linux";
    };
}
