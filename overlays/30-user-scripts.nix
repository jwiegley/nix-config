# overlays/30-user-scripts.nix
# Purpose: Personal script collections
# Dependencies: prev.myLib (from 00-lib.nix); final for perl/haskellPackages
# Packages: nix-scripts, my-scripts
# Notes:
#   - nix-scripts from this repository's bin/ directory
#   - my-scripts requires paths.scripts
final: prev:

let
  paths = import ../config/paths.nix { inherit (prev) inputs; };
  inherit (prev.myLib) mkScriptPackage;
in
{

  nix-scripts = mkScriptPackage {
    name = "nix-scripts";
    src = ../bin;
    description = "Nix configuration scripts";
  };

}
// prev.lib.optionalAttrs (paths.scripts != null) {

  my-scripts = mkScriptPackage {
    name = "my-scripts";
    src = paths.scripts;
    description = "John Wiegley's various scripts";
    extraInstall = ''
      ${final.perl}/bin/perl -i -pe \
          's^#!/usr/bin/env runhaskell^#!${final.haskellPackages.ghc}/bin/runhaskell^;' $out/bin/*
    '';
  };

}
