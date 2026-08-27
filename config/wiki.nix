{
  config,
  lib,
  pkgs,
  ...
}:

let
  enabled = config.johnw.host.isHera;
in
{
  # Import the host capability option this module reads rather than relying on a
  # parent module's import list.
  imports = [ ./host-options.nix ];

  config = {
    home.packages = lib.optional (pkgs ? plasma-wiki) pkgs.plasma-wiki;

    home.file = lib.mkIf enabled (
      lib.optionalAttrs (pkgs ? plasma-wiki) {
        ".agents/skills/wiki".source = "${pkgs.plasma-wiki}/share/skills/wiki";
      }
    );
  };
}
