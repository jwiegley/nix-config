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
  config = {
    home.packages = lib.optionals (pkgs ? plasma-fractal && pkgs ? plasma-wiki) [
      pkgs.plasma-fractal
      pkgs.plasma-wiki
    ];

    home.file = lib.mkIf enabled (
      {
        ".local/bin/agent-deck-litellm-env".source = ../bin/agent-deck-litellm-env;
        ".local/bin/codex".source = ../bin/codex-litellm;
      }
      // lib.optionalAttrs (pkgs ? plasma-fractal && pkgs ? plasma-wiki) {
        ".agents/skills/fractal".source = "${pkgs.plasma-fractal}/share/skills/fractal";
        ".agents/skills/wiki".source = "${pkgs.plasma-wiki}/share/skills/wiki";
      }
    );
  };
}
