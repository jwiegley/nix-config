self: pkgs:

let ledgerPkg = import ~/src/ledger;
    ledger = ledgerPkg.packages.${pkgs.system}.ledger; in

{

ledger_HEAD_python3 = ledger.overrideAttrs (attrs: {
  boost = pkgs.boost.override { python = pkgs.python3; };

  preConfigure = ''
    sed -i -e "s%DESTINATION \\\''${Python_SITEARCH}%DESTINATION $out/lib/python37/site-packages%" src/CMakeLists.txt
  '';

  preInstall = ''
    mkdir -p $out/lib/python37/site-packages
  '';
});

ledgerPy3Env = pkgs.myEnvFun {
  name = "ledger-py3";
  buildInputs = with pkgs; [
    cmake (pkgs.boost.override { python = pkgs.python3; }) gmp mpfr libedit
    python3 texinfo gnused ninja clang doxygen icu
  ];
};

}
