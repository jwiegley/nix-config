# Typed host-registry options and resolved capability flags shared by Home
# Manager and nix-darwin. Given the required hostname special argument, this
# module declares and populates `johnw.host`; its assertion forces the complete
# registry through the typed schema so invalid rows fail evaluation.

args@{
  config,
  lib,
  hostname,
  ...
}:

let
  inherit (lib) mkOption types;

  registry = import ./hosts/registry.nix;

  # Use the same optional home-class override as the AI module so shared-work
  # resolves to the Andoria registry row; other evaluations use their hostname.
  homeClass = args.nixManagedAiHomeClass or null;

  resolvedRegistryId = if homeClass == "shared-work" then "andoria" else hostname;
  resolvedRegistryRow = registry.hosts.${resolvedRegistryId} or null;
  profileHeavyDefault =
    resolvedRegistryRow == null || !(builtins.elem "server-lean" resolvedRegistryRow.roles);

  # The typed row. Enums throw loudly on an unknown value.
  hostRow = types.submodule {
    options = {
      system = mkOption {
        type = types.enum [
          "aarch64-darwin"
          "aarch64-linux"
          "x86_64-linux"
        ];
        description = "Nix system double for the host.";
      };
      activation = mkOption {
        type = types.enum [
          "darwin"
          "nixos-module"
          "home-standalone"
        ];
        description = "How this host realizes its configuration.";
      };
      username = mkOption {
        type = types.str;
        description = "Login user this host's configuration is built for.";
      };
      roles = mkOption {
        type = types.listOf types.str;
        description = "Coarse role tags consumed by the lean/full profile seam (#42).";
      };
    };
  };
in
{
  options.johnw = {
    hostRegistry = mkOption {
      type = types.attrsOf hostRow;
      description = ''
        Typed fleet metadata and capability inputs populated from
        config/hosts/registry.nix.
      '';
    };

    # Capability booleans keep host-specific consumers keyed to properties
    # rather than scattering hostname comparisons.
    host = {
      isHera = mkOption {
        type = types.bool;
        description = "This evaluation is Hera.";
      };
      isClio = mkOption {
        type = types.bool;
        description = "This evaluation is Clio.";
      };
      isVulcan = mkOption {
        type = types.bool;
        description = "This evaluation is Vulcan.";
      };
      isDarwinWorkstation = mkOption {
        type = types.bool;
        description = "A Darwin GUI workstation (Hera or Clio).";
      };
      isSharedWork = mkOption {
        type = types.bool;
        description = "A member of the shared-\$HOME Positron work group (home class \"shared-work\").";
      };
      isCiFixture = mkOption {
        type = types.bool;
        description = "A synthetic CI evaluation fixture (hostname \"linux\"), not a real host.";
      };
    };

    profile.heavy = mkOption {
      type = types.bool;
      description = ''
        Enable workstation-oriented programs and package-backed settings.
        Real hosts tagged `server-lean` default this off; other hosts default
        on. Consumers may still override the value explicitly.
      '';
    };
  };

  config = {
    johnw = {
      hostRegistry = registry.hosts;
      host = registry.capabilitiesFor { inherit hostname homeClass; };
      profile.heavy = lib.mkDefault profileHeavyDefault;
    };

    # Force the whole typed table on every build so a malformed row (bad enum,
    # missing required field, wrong type) is a loud eval error rather than a
    # lazily-skipped option. `deepSeq` evaluates every field, triggering each
    # enum's check.
    assertions = [
      {
        assertion = builtins.deepSeq config.johnw.hostRegistry true;
        message = "fleet host registry failed typed-schema validation (config/hosts/registry.nix)";
      }
    ];
  };
}
