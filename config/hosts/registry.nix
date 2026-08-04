# Declarative host identity and capability data shared by the module schema in
# config/host-options.nix and the plain package selector in config/packages.nix.
# Keeping this file free of module arguments lets both consumers import the same
# table and pure capability function.

let
  # Typed identity metadata for personal machines and the shared work fleet.
  # Active Git and mail identity still comes from config/vars.nix.
  personal = {
    userName = "John Wiegley";
    userEmail = "johnw@newartisans.com";
    signing = "none";
    signingKey = null;
  };
  desktop = {
    signing = "openpgp";
    signingKey = "12D70076AB504679";
  };
  work = {
    userName = "John Wiegley";
    userEmail = "jwiegley@positron.ai";
    signing = "none";
    signingKey = null;
  };
  sharedWorkMembers = [
    "andoria-08"
    "andoria-t2"
    "delphi-3bd4"
    "gpu-server"
  ];

in
{
  # Host rows plus one shared-work group row. The typed module supplies defaults
  # for fields omitted here.
  hosts = {
    hera =
      personal
      // desktop
      // {
        system = "aarch64-darwin";
        activation = "darwin";
        username = "johnw";
        roles = [
          "workstation-full"
          "darwin-full"
          "ai-heavy"
        ];
      };
    clio =
      personal
      // desktop
      // {
        system = "aarch64-darwin";
        activation = "darwin";
        username = "johnw";
        roles = [
          "workstation-lite"
          "darwin-core"
          "ai-client"
        ];
      };
    vulcan = personal // {
      system = "aarch64-linux";
      activation = "nixos-module";
      username = "johnw";
      roles = [
        "server-headless"
        "server-lean"
        "ai-client"
      ];
      hmRelease = "25.11"; # Intentional Home Manager release skew.
    };
    vps = personal // {
      system = "x86_64-linux";
      activation = "nixos-module";
      username = "johnw";
      roles = [ "server-lean" ];
      hmRelease = "25.11";
    };

    # Group four shared-work hostnames under one profile identity.
    andoria = work // {
      system = "x86_64-linux";
      activation = "home-standalone";
      username = "jwiegley";
      roles = [
        "shared-work"
        "ai-client"
      ];
      evalId = "andoria";
      sharedHome = {
        members = sharedWorkMembers;
        localStateRoot = "/var/lib/jwiegley";
      };
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
      isVps = id == "vps";

      # The two Darwin GUI workstations (hera OR clio).
      isDarwinWorkstation = id == "hera" || id == "clio";

      # Resolve the shared-work group from either its explicit home class or a
      # physical member hostname.
      isSharedWork = cls == "shared-work" || builtins.elem id sharedWorkMembers;

      # The synthetic CI evaluation fixtures pin the name to "linux".
      isCiFixture = id == "linux";
    };
}
