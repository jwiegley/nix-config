# overlays/30-ledger.nix
# Purpose: Ledger CLI accounting from local source
# Dependencies: None (uses only prev)
# Packages: ledger_HEAD
# Note: Requires paths.ledger
final: prev:

let
  ledger = prev.inputs.ledger.packages.${prev.system}.ledger;

in {

  ledger_HEAD = ledger.overrideAttrs (attrs: {
    boost = prev.boost.override { python = prev.python3; };

    preConfigure = ''
      sed -i -e "s%DESTINATION \\\''${Python_SITEARCH}%DESTINATION $out/lib/python37/site-packages%" src/CMakeLists.txt
    '';

    preInstall = ''
      mkdir -p $out/lib/python37/site-packages
    '';
  });

}
