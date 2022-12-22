self: pkgs:

{

inherit (import ~/kadena/fully-local {})
  start-kadena pact kda-tool;

}
