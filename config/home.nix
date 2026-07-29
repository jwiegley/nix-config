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
  # ./johnw.nix already imports ./host-options.nix, so johnw.host resolves today.
  # Declared explicitly anyway: this module reads config.johnw.host, and its
  # correctness should not depend on a sibling's import list staying as it is.
  imports = [
    ./johnw.nix
    ./host-options.nix
  ];

  # Run one Discord gateway client. Enabling this on Clio as well would
  # make both hosts compete for the same bot connection.
  johnw.agentDeck.enableConductorDiscordBridge = config.johnw.host.isHera;

  johnw.anvil = {
    useDedicatedDarwinEmacs = config.johnw.host.isDarwinWorkstation;
    # The code is ready on both hosts; deploy and prove Hera before Clio.
    usePerAgentDaemon = true;
  };

  home = {
    # Darwin has been on 23.11 longer than NixOS
    stateVersion = "23.11";

    # Darwin-specific timezone representation
    sessionVariables.TZ = "PST8PDT";

    # Darwin-specific packages from the extensive packages.nix
    packages = packages.package-list;
  };
}
