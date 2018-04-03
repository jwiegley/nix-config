self: pkgs: rec {

QuickChick = cpkgs:
  self.callPackage ./coq/QuickChick.nix { inherit (cpkgs) coq ssreflect; };
fiat_HEAD = cpkgs:
  self.callPackage ./coq/fiat.nix { inherit (cpkgs) coq; };
equations_8_8 = cpkgs:
  self.callPackage ./coq/equations.nix { inherit (cpkgs) coq; };
coq-haskell = cpkgs:
  self.callPackage ./coq/coq-haskell.nix { inherit (cpkgs) coq ssreflect; };

coq_8_7_override = pkgs.coq_8_7.override {
  ocamlPackages = pkgs.ocaml-ng.ocamlPackages_4_06;
  buildIde = true;
};

coq_HEAD = with pkgs; stdenv.lib.overrideDerivation coq_8_7_override (attrs: rec {
  version = "HEAD";
  name = "coq-${version}-pre";
  coq-version = "${version}";

  src = ~/src/coq;

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

coqPackages_HEAD = let cpkgs = pkgs.mkCoqPackages coq_HEAD; in cpkgs // {
  QuickChick = QuickChick cpkgs;
  equations = equations_8_8 cpkgs;
  fiat_HEAD = fiat_HEAD cpkgs;
  coq-haskell = coq-haskell cpkgs;
};

coqPackages_8_8 = let cpkgs = pkgs.mkCoqPackages pkgs.coq_8_8; in cpkgs // {
  QuickChick = QuickChick cpkgs;
  equations = equations_8_8 cpkgs;
  fiat_HEAD = fiat_HEAD cpkgs;
  coq-haskell = coq-haskell cpkgs;
};

coqPackages_8_7 = let cpkgs = pkgs.mkCoqPackages pkgs.coq_8_7; in cpkgs // {
  QuickChick = QuickChick cpkgs;
  fiat_HEAD = fiat_HEAD cpkgs;
  coq-haskell = coq-haskell cpkgs;
};

coqPackages_8_6 = let cpkgs = pkgs.mkCoqPackages pkgs.coq_8_6; in cpkgs // {
  QuickChick = QuickChick cpkgs;
  fiat_HEAD = fiat_HEAD cpkgs;
  coq-haskell = coq-haskell cpkgs;
};

coqPackages_8_5 = pkgs.mkCoqPackages pkgs.coq_8_5;
coqPackages_8_4 = pkgs.mkCoqPackages pkgs.coq_8_4;

coqHEADEnv = myPkgs: pkgs.myEnvFun {
  name = "coqHEAD";
  buildInputs = [ coq_HEAD ] ++ myPkgs "HEAD" coqPackages_HEAD;
};

coq88Env = myPkgs: pkgs.myEnvFun {
  name = "coq88";
  buildInputs = [ pkgs.coq_8_8 ] ++ myPkgs "8.8+beta1" coqPackages_8_8;
};

coq87Env = myPkgs: pkgs.myEnvFun {
  name = "coq87";
  buildInputs = [ pkgs.coq_8_7 ] ++ myPkgs "8.7" coqPackages_8_7;
};

coq86Env = myPkgs: pkgs.myEnvFun {
  name = "coq86";
  buildInputs = [ pkgs.coq_8_6 ] ++ myPkgs "8.6" coqPackages_8_6;
};

coq85Env = myPkgs: pkgs.myEnvFun {
  name = "coq85";
  buildInputs = [ pkgs.coq_8_5 ] ++ myPkgs "8.5" coqPackages_8_5;
};

coq84Env = myPkgs: pkgs.myEnvFun {
  name = "coq84";
  buildInputs = [ pkgs.coq_8_4 ] ++ myPkgs "8.4" coqPackages_8_4;
};

}
