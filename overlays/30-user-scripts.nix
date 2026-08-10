# overlays/30-user-scripts.nix
# Purpose: Personal script collections
# Dependencies: prev.myLib (from 00-lib.nix); final for perl/haskellPackages
# Packages: nix-scripts, my-scripts
# Notes:
#   - supported nix-scripts from this repository's bin/ directory
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
    excludeFiles = [
      "update-remote"
      "upgrade-all"
    ];
    extraInstall = ''
      mkdir -p $out/libexec/nix-scripts
      cp -R ${../bin/lib}/. $out/libexec/nix-scripts/
      # Derive the consumer list instead of hand-maintaining it: every script
      # carrying the anchor gets the absolute library path.
      grep -l 'installed_routing_path=' $out/bin/* | while read -r script; do
        substituteInPlace "$script" \
          --replace-fail 'installed_routing_path=' \
          "installed_routing_path=$out/libexec/nix-scripts/host-routing.sh"
      done
      # Fail the build if a script sources the routing library without the
      # anchor: installed via the profile, neither relative fallback resolves,
      # so such a script would break on every PATH invocation.
      for script in $out/bin/*; do
        if grep -q 'host-routing\.sh' "$script" \
          && ! grep -q "installed_routing_path=$out" "$script"; then
          echo "nix-scripts: $script sources host-routing.sh without the installed_routing_path anchor" >&2
          exit 1
        fi
      done
      test ! -e $out/bin/update-remote
      test ! -e $out/bin/update-home-manager
      test ! -e $out/bin/upgrade-all
      test -x $out/bin/update-overlay
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
