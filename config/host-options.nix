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

  sharedHomeType = types.submodule {
    options = {
      members = mkOption {
        type = types.listOf types.str;
        description = "Real machine hostnames that share one NFS \$HOME under this group.";
      };
      localStateRoot = mkOption {
        type = types.str;
        description = "Per-machine local (non-shared) state root for the group.";
      };
    };
  };

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
      userName = mkOption {
        type = types.str;
        description = "Human name (git/email identity). Carried as data; not wired by #50.";
      };
      userEmail = mkOption {
        type = types.str;
        description = "Commit/email identity. Carried as data; wired by CON-CORE-WORKID, not #50.";
      };
      signing = mkOption {
        type = types.enum [
          "openpgp"
          "ssh"
          "none"
        ];
        default = "none";
        description = "Commit-signing scheme. Carried as data; not wired by #50.";
      };
      signingKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Signing key id, when `signing != \"none\"`.";
      };
      roles = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Coarse role tags consumed by the lean/full profile seam (#42).";
      };
      hmRelease = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          The home-manager release this host's authoritative checkout tracks,
          when it is knowingly skewed from the root. This field is declarative;
          the release-skew gate does not read it.
        '';
      };
      evalId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Group label for shared-home fleets. Never a machine name.";
      };
      sharedHome = mkOption {
        type = types.nullOr sharedHomeType;
        default = null;
        description = "Present only on shared-\$HOME group rows (the Andoria fleet).";
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
        default = false;
        description = "This evaluation is Hera.";
      };
      isClio = mkOption {
        type = types.bool;
        default = false;
        description = "This evaluation is Clio.";
      };
      isVulcan = mkOption {
        type = types.bool;
        default = false;
        description = "This evaluation is Vulcan.";
      };
      isVps = mkOption {
        type = types.bool;
        default = false;
        description = "This evaluation is the VPS.";
      };
      isDarwinWorkstation = mkOption {
        type = types.bool;
        default = false;
        description = "A Darwin GUI workstation (Hera or Clio).";
      };
      isSharedWork = mkOption {
        type = types.bool;
        default = false;
        description = "A member of the shared-\$HOME Positron work group (home class \"shared-work\").";
      };
      isCiFixture = mkOption {
        type = types.bool;
        default = false;
        description = "A synthetic CI evaluation fixture (hostname \"linux\"), not a real host.";
      };
    };

    profile.heavy = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable workstation-oriented programs and package-backed settings. Real
        hosts tagged `server-lean` default this off; unknown and synthetic hosts
        default on so existing consumers remain compatible. Consumers may still
        override the value explicitly.
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
