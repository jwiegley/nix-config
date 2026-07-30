# overlays/30-user-scripts.nix
# Purpose: Personal script collections
# Dependencies: prev.myLib (from 00-lib.nix); final for perl/haskellPackages
# Packages: nix-scripts, my-scripts
# Notes:
#   - nix-scripts from this repository's bin/ directory
#   - my-scripts requires scripts
{
  scripts ? null,
}:
final: prev:

let
  inherit (prev.myLib) mkScriptPackage;
in
{

  nix-scripts = mkScriptPackage {
    name = "nix-scripts";
    src = ../bin;
    description = "Nix configuration scripts";
    extraInstall = ''
      mkdir -p $out/libexec/nix-scripts
      cp -R ${../bin/lib}/. $out/libexec/nix-scripts/
      substituteInPlace $out/bin/switch $out/bin/update-agents $out/bin/upgrade \
        --replace-fail 'installed_routing_path=' \
        "installed_routing_path=$out/libexec/nix-scripts/host-routing.sh"
      substituteInPlace $out/bin/upgrade \
        --replace-fail 'installed_upgrade_projects=' \
        "installed_upgrade_projects=$out/bin/upgrade-projects"
    '';
  };

}
// prev.lib.optionalAttrs (scripts != null) {

  my-scripts = mkScriptPackage {
    name = "my-scripts";
    src = scripts;
    description = "John Wiegley's various scripts";
    extraInstall = ''
      ${final.perl}/bin/perl -i -pe \
          's^#!/usr/bin/env runhaskell^#!${final.haskellPackages.ghc}/bin/runhaskell^;' $out/bin/*
    '';
  };

}
