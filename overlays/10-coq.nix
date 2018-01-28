self: pkgs: rec {

coq_8_7_override = pkgs.coq_8_7.override {
  ocamlPackages = pkgs.ocaml-ng.ocamlPackages_4_06;
  buildIde = false;
};

coq_HEAD = pkgs.stdenv.lib.overrideDerivation coq_8_7_override (attrs: rec {
  version = "8.8";
  name = "coq-${version}-pre";
  coq-version = "${version}";
  src = pkgs.fetchFromGitHub {
    owner = "coq";
    repo = "coq";
    rev = "d0e05a1964fb2af093ac2a15a75bb84d342bf1ad";
    sha256 = "1r4ziwjmq2kh3j52dvb6phpflvkbznkk71fiwnp1klf557li98i5";
    # date = 2018-01-25T13:52:14+01:00;
  };
  buildInputs = attrs.buildInputs
    ++ (with pkgs; [ ocaml-ng.ocamlPackages_4_06.num
                     texFull hevea fig2dev imagemagick_light ]);
  preConfigure = ''
    configureFlagsArray=(
      -with-doc no
      -coqide no
    )
  '';
});

coqPackages_HEAD = pkgs.mkCoqPackages coq_HEAD;

coqHEADEnv = myPkgs: pkgs.myEnvFun {
  name = "coqHEAD";
  buildInputs = [ coq_HEAD ];
};

coq87Env = myPkgs: pkgs.myEnvFun {
  name = "coq87";
  buildInputs = [ pkgs.coq_8_7 ] ++ myPkgs "8.7" pkgs.coqPackages_8_7;
};

coq86Env = myPkgs: pkgs.myEnvFun {
  name = "coq86";
  buildInputs = [ pkgs.coq_8_6 ] ++ myPkgs "8.6" pkgs.coqPackages_8_6;
};

coq85Env = myPkgs: pkgs.myEnvFun {
  name = "coq85";
  buildInputs = [ pkgs.coq_8_5 ] ++ myPkgs "8.5" pkgs.coqPackages_8_5;
};

coqPackages_8_4 = pkgs.mkCoqPackages pkgs.coq_8_4;

coq84Env = myPkgs: pkgs.myEnvFun {
  name = "coq84";
  buildInputs = [ pkgs.coq_8_4 ];
};

}
