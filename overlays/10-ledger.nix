self: pkgs: rec {

ledger_HEAD = pkgs.callPackage ~/src/ledger {};

boost_with_python3 = pkgs.boost160.override {
  python = pkgs.python3;
};

ledger_HEAD_python3 = pkgs.callPackage ~/src/ledger {
  boost = pkgs.boost_with_python3;
};

ledgerPy3Env = pkgs.myEnvFun {
  name = "ledger-py3";
  buildInputs = with pkgs; [
    cmake boost_with_python3 gmp mpfr libedit python texinfo gnused ninja
    clang doxygen
  ];
};

ledgerPy2Env = pkgs.myEnvFun {
  name = "ledger-py2";
  buildInputs = with pkgs; [
    cmake boost gmp mpfr libedit python texinfo gnused ninja clang doxygen
  ];
};

}
