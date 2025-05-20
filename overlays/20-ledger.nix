self: pkgs:

let ledgerPkg = import /Users/johnw/src/ledger;
    ledger = ledgerPkg.packages.${pkgs.system}.ledger; in

{

ledger_HEAD = ledger.overrideAttrs (attrs: {
  boost = pkgs.boost.override { python = pkgs.python3; };

  preConfigure = ''
    sed -i -e "s%DESTINATION \\\''${Python_SITEARCH}%DESTINATION $out/lib/python37/site-packages%" src/CMakeLists.txt
  '';

  preInstall = ''
    mkdir -p $out/lib/python37/site-packages
  '';
});

}
