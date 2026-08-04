# overlays/00-last-known-good.nix
# Purpose: Pin specific packages to known-good nixpkgs revisions
_final: prev:

let
  sources = import ../packages/source-catalog.nix "compatibility";
  nixpkgs =
    name:
    let
      source = sources.${name}.source;
    in
    assert source.fetcher == "fetchTree";
    import (builtins.fetchTree source.args).outPath {
      localSystem = prev.stdenv.hostPlatform.system;
    };
  # Compatibility snapshot for the Darwin packages still pinned below.
  lastGood = nixpkgs "nixpkgs-last-good";

in
{
  # Keep ntp on the compatibility snapshot.
  inherit (lastGood)
    ntp
    ;

}
