self: pkgs:

{

inherit (pkgs.callPackage ~/src/icp/wallet {})
  quill candid idl2json;

}
