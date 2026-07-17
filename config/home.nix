# Darwin-specific home-manager wrapper for John Wiegley.
#
# This imports the shared cross-platform module (johnw.nix) and adds
# Darwin-specific packages and overrides. The shared module contains
# the full user environment with platform conditionals.

{
  pkgs,
  config,
  hostname,
  inputs,
  ...
}@args:

let
  packages = import ./packages.nix args;
in
{
  imports = [
    ./agent-deck.nix
    ./johnw.nix
  ];

  # Run one Discord gateway client. Enabling this on Clio as well would
  # make both hosts compete for the same bot connection.
  johnw.agentDeck.enableConductorDiscordBridge = hostname == "hera";

  home = {
    # Darwin has been on 23.11 longer than NixOS
    stateVersion = "23.11";

    # Darwin-specific timezone representation
    sessionVariables.TZ = "PST8PDT";

    # Darwin-specific packages from the extensive packages.nix
    packages = packages.package-list;
  };
}
