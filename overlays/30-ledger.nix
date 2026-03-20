# overlays/30-ledger.nix
# Purpose: Ledger CLI accounting from local source
# Dependencies: None (uses only prev)
# Packages: ledger_HEAD
# Note: Requires paths.ledger
final: prev:

prev.lib.optionalAttrs (prev ? inputs && prev.inputs ? ledger) {

  ledger_HEAD =
    prev.inputs.ledger.packages.${prev.stdenv.hostPlatform.system}.ledger.overrideAttrs
      (attrs: {
        boost = prev.boost.override { python = prev.python3; };

        preConfigure = ''
          sed -i -e "s%DESTINATION \\\''${Python_SITEARCH}%DESTINATION $out/${prev.python3.sitePackages}%" src/CMakeLists.txt
        '';

        preInstall = ''
          mkdir -p $out/${prev.python3.sitePackages}
        '';
      });

}
