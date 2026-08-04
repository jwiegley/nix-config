{
  config,
  hostname,
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
    home.packages = lib.optionals (pkgs ? plasma-fractal && pkgs ? plasma-wiki) [
      pkgs.plasma-fractal
      pkgs.plasma-wiki
    ];

    home.file = lib.mkIf enabled (
      {
        ".local/bin/agent-deck-env".source = ../bin/agent-deck-env;
      }
      // lib.optionalAttrs (pkgs ? plasma-fractal && pkgs ? plasma-wiki) {
        ".agents/skills/fractal".source = "${pkgs.plasma-fractal}/share/skills/fractal";
        ".agents/skills/wiki".source = "${pkgs.plasma-wiki}/share/skills/wiki";
      }
    );
  };
}
