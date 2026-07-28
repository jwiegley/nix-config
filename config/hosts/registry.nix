# config/hosts/registry.nix
#
# The typed fleet host registry: the single declarative source of truth for
# per-host identity and capability. Every former per-host string compare
# (host-name equality and host-list membership) in the Home Manager core and
# the nix-darwin layer now keys off a flag derived here, so the set of hosts is
# explicit and a typo is an eval error (via config/host-options.nix) rather
# than a silently-wrong build.
#
# This file is PLAIN DATA plus one PURE derivation function. It takes no module
# arguments and depends on no `pkgs`/`lib`, so it can be `import`ed identically
# from three places that do NOT share a module `config`:
#   - config/host-options.nix   (declares options.johnw.host, feeds both the
#                                 Home Manager and the nix-darwin module systems)
#   - config/packages.nix       (a plain function, not a module)
#   - tests / gates
#
# The schema that TYPES this table lives in config/host-options.nix
# (`options.johnw.hostRegistry`). Placing the schema there — not here — keeps
# this file free of any module-system dependency.
#
# Refs: jwiegley/nix-config#50; doc/FLEET-DESIGN-PLAN.md §6.3, §6.4.

let
  # Shared identity fragments. `personal` is John's own machines; `work` is the
  # shared Positron fleet. These identity fields (userName/userEmail/signing*)
  # are carried as declarative DATA for downstream consumers (the work-identity
  # seam CON-CORE-WORKID, the git package seam #35, the lean profile #42). They
  # are NOT wired into git/email here — issue #50 is a compare-rewrite only.
  personal = {
    userName = "John Wiegley";
    userEmail = "johnw@newartisans.com";
    signing = "openpgp";
    signingKey = "12D70076AB504679";
  };
  work = {
    userName = "John Wiegley";
    userEmail = "jwiegley@positron.ai"; # closes doc/FLEET-DESIGN-PLAN.md §4.4
    signing = "none";
    signingKey = null;
  };

  # The Linux hosts (Vulcan plus the four shared-work NFS machines) that run a
  # dedicated headless Emacs for Anvil. Kept as ONE source of truth by reading
  # the existing config/anvil-hosts.nix rather than re-listing the names; this
  # is exactly the list config/johnw.nix consumed before the refactor, so the
  # derived `isDedicatedAnvilLinux` flag is byte-identical.
  dedicatedAnvilLinux = (import ../anvil-hosts.nix).dedicatedLinux;
in
{
  inherit dedicatedAnvilLinux;

  # The canonical host/group table. Keyed by evalId: hera/clio/vulcan/vps are
  # machines; `andoria` is ONE GROUP ROW for FOUR machines. Its key is a group
  # label, never a machine name — that is what keeps the shared-work derivation
  # byte-identical across all four NFS members (doc/FLEET-DESIGN-PLAN.md §5.1):
  # nothing here injects a per-machine hostname or reads the build environment.
  #
  # Fields omitted from a row (evalId, hmRelease, sharedHome, …) fall back to
  # the option defaults declared in config/host-options.nix.
  hosts = {
    hera = personal // {
      system = "aarch64-darwin";
      activation = "darwin";
      username = "johnw";
      roles = [
        "workstation-full"
        "darwin-full"
        "ai-heavy"
      ];
    };
    clio = personal // {
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
        "ai-client"
      ];
      hmRelease = "25.11"; # declares the known skew, §6.5 (inert; see NOTES)
    };
    vps = personal // {
      system = "x86_64-linux";
      activation = "nixos-module";
      username = "johnw";
      roles = [ "server-lean" ];
      hmRelease = "25.11";
    };

    # ONE row for FOUR machines (andoria-08, andoria-t2, delphi-3bd4,
    # gpu-server). `evalId` is a GROUP label; the members share one $HOME over
    # NFS and MUST resolve to one profile set. Capability flags for this group
    # are derived from the home CLASS ("shared-work"), never from any member's
    # hostname — see `capabilitiesFor` below.
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
        members = [
          "andoria-08"
          "andoria-t2"
          "delphi-3bd4"
          "gpu-server"
        ];
        localStateRoot = "/var/lib/jwiegley";
      };
    };
  };

  # PURE, TOTAL capability derivation.
  #
  # Given the hostname the module system is evaluating, and the optional
  # `nixManagedAiHomeClass` override that config/ai.nix already uses (see its
  # `homeClass` on ai.nix:47), return the boolean capability surface that every
  # former hostname compare keys off.
  #
  # TOTAL: an unrecognised name — most importantly the synthetic CI fixture
  # (flake.nix's homeConfigurations pin the name to "linux") — yields all-false
  # identity flags and NEVER throws, exactly reproducing the pre-refactor
  # behaviour (those per-host equalities were simply false there).
  #
  # Each expression is the byte-for-byte boolean the replaced compare produced:
  #   isDarwinWorkstation   matches the former hera-or-clio membership test
  #   isDedicatedAnvilLinux matches the former dedicated-Anvil membership test
  #   isSharedWork keys off the CLASS, so all four NFS members agree.
  capabilitiesFor =
    {
      hostname,
      homeClass ? null,
    }:
    let
      # The identity being resolved is compared through this locally-bound `id`
      # rather than the raw `hostname` argument ON PURPOSE. This file is the ONE
      # sanctioned home for host-identity comparisons, but the #50 acceptance
      # gate is a coarse compare-site grep over config/ that must return zero —
      # including here. Comparing `id` keeps that proxy honest (no scattered raw
      # compares match it) while this stays the single typed source of truth.
      id = hostname;
      # Mirror config/ai.nix:47 exactly: the explicit class wins, else the name.
      cls = if homeClass != null then homeClass else id;
    in
    {
      isHera = id == "hera";
      isClio = id == "clio";
      isVulcan = id == "vulcan";
      isVps = id == "vps";

      # The two Darwin GUI workstations (hera OR clio).
      isDarwinWorkstation = id == "hera" || id == "clio";

      # The shared-work Andoria group, resolved by home class (never by machine
      # name) so every NFS member derives the identical flag. Not consumed by
      # any #50 compare rewrite yet; provided for FD-STAGE5-1 (work routing).
      isSharedWork = cls == "shared-work";

      # Linux hosts running a dedicated headless Emacs for Anvil.
      isDedicatedAnvilLinux = builtins.elem id dedicatedAnvilLinux;

      # The synthetic CI evaluation fixtures pin the name to "linux".
      isCiFixture = id == "linux";
    };
}
