self: pkgs:

{

inherit (pkgs.callPackage ~/kadena/fully-local {})
  start-kadena pact;

}
