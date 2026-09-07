{
  lib,
  pkgs,
  modelPolicy,
}:

{ homeDirectory, xdgConfigHome }:

let
  xdgConfigRelative = lib.removePrefix "${homeDirectory}/" xdgConfigHome;
in
assert xdgConfigHome == "${homeDirectory}/.config";
{
  files."${xdgConfigRelative}/agent-cat/routing.yaml".source =
    (pkgs.formats.yaml { }).generate "agent-cat-routing.yaml"
      {
        version = 2;
        secrets = { };
        inherit (modelPolicy.agentCat)
          default-persona
          engines
          models
          personas
          ;
      };
}
