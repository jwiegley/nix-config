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
  # Declare the option this module READS (config.johnw.host). Relying on a
  # parent to import it makes the module fail when imported on its own -- which
  # is exactly what happened to config/ai.nix (#50 stage 2, fixed in e139c62c).
  # Module imports are deduplicated by path, so this is a no-op wherever a
  # parent already imported it.
  imports = [ ./host-options.nix ];

  config = {
    home.packages = lib.optionals (pkgs ? plasma-fractal && pkgs ? plasma-wiki) [
      pkgs.plasma-fractal
      pkgs.plasma-wiki
    ];

    home.file = lib.mkIf enabled (
      {
        ".local/bin/agent-deck-litellm-env".source = ../bin/agent-deck-litellm-env;
      }
      // lib.optionalAttrs (pkgs ? plasma-fractal && pkgs ? plasma-wiki) {
        ".agents/skills/fractal".source = "${pkgs.plasma-fractal}/share/skills/fractal";
        ".agents/skills/wiki".source = "${pkgs.plasma-wiki}/share/skills/wiki";
      }
    );
  };
}
