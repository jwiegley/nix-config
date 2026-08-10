# overlays/00-last-known-good.nix
# Purpose: Pin specific packages to known-good nixpkgs revisions
_final: prev:

let
  source = (import ../packages/source-catalog.nix "compatibility").nixpkgs-last-good.source;
  # Compatibility snapshot for the Darwin packages still pinned below.
  lastGood =
    assert source.fetcher == "fetchTree";
    import (builtins.fetchTree source.args).outPath {
      localSystem = prev.stdenv.hostPlatform.system;
    };

in
{
  # Keep ntp on the compatibility snapshot.
  inherit (lastGood)
    ntp
    ;

}
