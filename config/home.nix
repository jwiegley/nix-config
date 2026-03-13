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
}
