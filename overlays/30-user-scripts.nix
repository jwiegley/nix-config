# overlays/30-user-scripts.nix
# Purpose: Personal script collections
# Dependencies: prev.myLib (from 00-lib.nix); final for perl/haskellPackages
# Packages: nix-scripts, my-scripts
# Notes:
#   - supported nix-scripts from this repository's bin/ directory
#   - my-scripts requires scripts
#   - upgrade-projects receives an absolute Python from the package closure
{
  scripts ? null,
}:
final: prev:

let
  inherit (prev.myLib) mkScriptPackage;
  supportedNixScripts = [
    "de"
    "env-build"
    "git-sha"
    "myhost"
    "persona"
    "publish"
    "runemacs"
    "switch"
    "u"
    "update"
    "update-and-pull"
    "update-overlay"
    "upgrade"
    "upgrade-projects"
    "yubikey-switch"
  ];
  sourceOnlyNixScripts = [
    "update-remote"
    "upgrade-all"
  ];
  expectedNixScripts = prev.lib.escapeShellArgs (supportedNixScripts ++ sourceOnlyNixScripts);
  hostRouting = final.writeText "host-routing.sh" (
    import ../config/hosts/shell-routing.nix {
      inherit (final) lib;
    }
  );
in
{

  nix-scripts = mkScriptPackage {
    name = "nix-scripts";
    src = ../bin;
    description = "Nix configuration scripts";
    homepage = "https://github.com/jwiegley/nix-config";
    license = prev.lib.licenses.bsd3;
    includeFiles = supportedNixScripts;
    extraInstall = ''
      printf '%s\n' ${prev.lib.escapeShellArgs supportedNixScripts} | LC_ALL=C sort > expected-installed
      for script in $out/bin/*; do
        basename "$script"
      done | LC_ALL=C sort > actual-installed
      cmp expected-installed actual-installed

      printf '%s\n' ${expectedNixScripts} | LC_ALL=C sort > expected-source
      find ${../bin} -maxdepth 1 \( -type f -o -type l \) -executable \
          -exec basename {} \; | LC_ALL=C sort > actual-source
      cmp expected-source actual-source

      cmp ${../bin/lib/host-routing.sh} ${hostRouting} || {
        echo "nix-scripts: bin/lib/host-routing.sh is stale; regenerate it from config/hosts/registry.nix" >&2
        exit 1
      }
      mkdir -p $out/libexec/nix-scripts
      cp -R ${../bin/lib}/. $out/libexec/nix-scripts/
      cp --remove-destination ${hostRouting} $out/libexec/nix-scripts/host-routing.sh
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
      test -x $out/bin/update-overlay
      substituteInPlace $out/bin/upgrade \
        --replace-fail 'installed_upgrade_projects=' \
        "installed_upgrade_projects=$out/bin/upgrade-projects"
      substituteInPlace $out/bin/upgrade-projects \
        --replace-fail 'installed_python=' \
        "installed_python=${final.python3}/bin/python3"
      $out/bin/upgrade-projects --retention-api-check
    '';
  };

}
// prev.lib.optionalAttrs (scripts != null) {

  my-scripts = mkScriptPackage {
    name = "my-scripts";
    src = scripts;
    description = "John Wiegley's various scripts";
    homepage = "https://github.com/jwiegley/scripts";
    # The locked source declares no repository-wide license.
    license = prev.lib.licenses.unfree;
    extraInstall = ''
      ${final.perl}/bin/perl -i -pe \
          's^#!/usr/bin/env runhaskell^#!${final.haskellPackages.ghc}/bin/runhaskell^;' $out/bin/*
    '';
  };

}
