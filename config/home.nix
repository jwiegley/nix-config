# Darwin-specific home-manager wrapper for John Wiegley.
#
# This imports the shared cross-platform module and adds Darwin-specific
# packages and overrides.

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

  # Give the Discord gateway one declarative host owner.
  johnw.agentDeck.enableConductorDiscordBridge = config.johnw.host.isHera;

  home = {
    stateVersion = "23.11";

    # Darwin-specific timezone representation
    sessionVariables.TZ = "PST8PDT";

    # packages.nix applies its own platform and host gates.
    packages = packages.package-list;
  };
}
