# Darwin-specific home-manager wrapper for John Wiegley.
#
# This imports the shared cross-platform module (johnw.nix) and adds
# Darwin-specific packages and overrides. The shared module contains
# the full user environment with platform conditionals.

{
  pkgs,
  lib,
  config,
  hostname,
  inputs,
  ...
}@args:

let
  packages = import ./packages.nix args;
in
{
  imports = [ ./johnw.nix ];

  home = {
    # Darwin has been on 23.11 longer than NixOS
    stateVersion = "23.11";

    # Darwin-specific timezone representation
    sessionVariables.TZ = "PST8PDT";

    # Darwin-specific packages from the extensive packages.nix
    packages = packages.package-list;
  };

  # hera: SyncThing (services.syncthing in johnw.nix) must never stay down.
  # Two fixes to the home-manager syncthing launchd agent:
  #
  # 1. domain: the module sets `domain = lib.mkDefault "user"`, so home-manager
  #    bootstraps the daemon into user/$UID. On hera that bootstrap fails with
  #    launchd "I/O error (code 5)" — syncthing-init and the rest of John's
  #    user agents live in gui/$UID, and the same label will not cleanly
  #    bootstrap into the overlapping user domain. A failed bootstrap is
  #    *ignored* by home-manager's activation, so a `u switch` that reloads the
  #    agent (e.g. a syncthing version bump) leaves it unloaded and SyncThing
  #    silently dies (observed 2026-06-25). Pin it to gui/$UID so bootout +
  #    bootstrap stay in one domain, matching syncthing-init and the watchdog.
  #
  # 2. KeepAlive/RunAtLoad: the module hard-codes
  #    KeepAlive = { Crashed = true; SuccessfulExit = false; }, which only
  #    relaunches after a crash or non-zero exit. A *clean* stop exits 0 — and
  #    a bootout, `launchctl stop`, or plain SIGTERM all exit cleanly — so
  #    launchd would leave it down. Force unconditional KeepAlive so it is
  #    relaunched however it stops, and make RunAtLoad explicit.
  #
  # KeepAlive only protects an agent that is *loaded*; if a future activation
  # ever fails to bootstrap it, syncthing-watchdog in launchd.nix re-registers
  # it (also in gui/$UID).
  launchd.agents.syncthing = lib.mkIf (hostname == "hera") {
    domain = lib.mkForce "gui";
    config = {
      KeepAlive = lib.mkForce true;
      RunAtLoad = true;
    };
  };
}
