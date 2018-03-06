self: pkgs: rec {

equations_8_8 = coq: with pkgs; stdenv.mkDerivation rec {
  name = "coq${coq.coq-version}-equations-${version}";
  version = "8.8+alpha";

  src = fetchFromGitHub {
    owner = "mattam82";
    repo = "Coq-Equations";
    rev = "5f358fb4ff463a7502adf6862efa611dff41350d";
    sha256 = "1iffarnch6grdb7d8ifzlxm45fpmnk5bax9gf556ny5qrnyx8s13";
  };

  buildInputs = [ coq.ocaml coq.camlp5 coq.findlib coq ];

  preBuild = "coq_makefile -f _CoqProject -o Makefile";

  installFlags = "COQLIB=$(out)/lib/coq/${coq.coq-version}/";

  meta = with stdenv.lib; {
    homepage = https://mattam82.github.io/Coq-Equations/;
    description = "A plugin for Coq to add dependent pattern-matching";
    maintainers = with maintainers; [ jwiegley ];
    platforms = coq.meta.platforms;
  };

  passthru = {
    compatibleCoqVersions = v: builtins.elem v [ "8.8+alpha" ];
  };
};

coq_8_7_override = pkgs.coq_8_7.override {
  ocamlPackages = pkgs.ocaml-ng.ocamlPackages_4_06;
  buildIde = true;
};

coq_HEAD = with pkgs; stdenv.lib.overrideDerivation coq_8_7_override (attrs: rec {
  version = "8.8+alpha";
  name = "coq-${version}-pre";
  coq-version = "${version}";

  src = fetchFromGitHub {
    owner = "coq";
    repo = "coq";
    rev = "15331729aaab16678c2f7e29dd391f72df53d76e";
    sha256 = "1296mzx21c4djrrfkcicnr87ns9vspdsdp15mkps7fjqmd330rk0";
    # date = 2018-03-05T13:30:08+01:00;
  };

  buildInputs = attrs.buildInputs
    ++ (with pkgs; [ ocaml-ng.ocamlPackages_4_06.num
                     texFull hevea fig2dev imagemagick_light ]);

  setupHook = writeText "setupHook.sh" ''
    addCoqPath () {
      if test -d "''$1/lib/coq/${coq-version}/user-contrib"; then
        export COQPATH="''${COQPATH}''${COQPATH:+:}''$1/lib/coq/${coq-version}/user-contrib/"
      fi
    }

    addEnvHooks "$targetOffset" addCoqPath
  '';

  preConfigure = ''
    configureFlagsArray=(
      -with-doc no
      -coqide no
    )
  '';
});

coqPackages_HEAD = pkgs.mkCoqPackages coq_HEAD // {
  equations = equations_8_8 coq_HEAD;
};

coqHEADEnv = myPkgs: pkgs.myEnvFun {
  name = "coqHEAD";
  buildInputs = [ coq_HEAD ] ++ myPkgs "8.8+alpha" coqPackages_HEAD;
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
