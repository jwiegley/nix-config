# config/host-options.nix
#
# The TYPED surface for the fleet host registry, and the resolved per-host
# capability flags. This is a self-contained module: it DECLARES the schema and
# POPULATES it from config/hosts/registry.nix using the `hostname` that the
# surrounding module system is evaluating. A consumer only has to add it to its
# `imports`; nothing else sets `johnw.host`.
#
# Two module systems import this file:
#   - Home Manager, via config/johnw.nix `imports`
#   - nix-darwin, via config/darwin.nix `imports`
# It is deliberately free of any HM- or darwin-specific option reference, so the
# same options-only-plus-config module evaluates identically in both. It is the
# analogue of config/git-options.nix (jwiegley/nix-config#35): a small, separate
# options module. It MUST stay separate — a module that declares top-level
# `options` must move every other top-level attribute under an explicit
# `config`, and folding this into the 346-line config/git.nix or the 471-line
# config/johnw.nix would force a whole-file reindent (that is the documented
# reason git-options.nix exists apart from git.nix).
#
# Loud failure: `config = { johnw.hostRegistry = registry.hosts; … }` runs every
# row through the typed submodule below, and the `assertions` entry `deepSeq`s
# the whole table so a bad enum (e.g. system = "x86-64-linux") is a hard eval
# error under `nix flake check`, `./build system`, and activation — not a
# silently-skipped lazy option.
#
# Refs: jwiegley/nix-config#50; doc/FLEET-DESIGN-PLAN.md §6.3, §6.4;
# config/git-options.nix (the separate-options-module precedent).

args@{
  config,
  lib,
  hostname,
  ...
}:

let
  inherit (lib) mkOption types;

  registry = import ./hosts/registry.nix;

  # config/ai.nix computes its home class from this same optional specialArg
  # (ai.nix:47). Reuse it so the shared-work group resolves by class, and so the
  # Darwin HM (which never passes it) and nix-darwin fall back to the hostname.
  homeClass = args.nixManagedAiHomeClass or null;

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
          when it is knowingly skewed from the root. Declarative documentation of
          §6.5; the release-skew gate (#29) does NOT read this field. Inert.
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
  options.johnw.hostRegistry = mkOption {
    type = types.attrsOf hostRow;
    description = ''
      The typed fleet host registry — the single source of truth for per-host
      identity and capability. Populated from config/hosts/registry.nix.
    '';
  };

  # The resolved capability flags for the host currently being evaluated. Every
  # former hostname string-compare reads one of these. Booleans only: a flag
  # names a PROPERTY of the host, so a new consumer keys off the property rather
  # than re-hardcoding a hostname.
  options.johnw.host = {
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

  config = {
    johnw.hostRegistry = registry.hosts;
    johnw.host = registry.capabilitiesFor { inherit hostname homeClass; };

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
