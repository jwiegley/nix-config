self: pkgs:

let
  extendAttrs = base: f: with pkgs; lib.fix (lib.extends f (self: base));

  filtered = drv: drv // { inherit (self.coqFilterSource [] drv) src; };

  coqPackage = self: path:
    let drv = self.callPackage path {}; in
    if builtins.pathExists (path + "/default.nix")
    then filtered drv
    else drv;

  myCoqPackages = self: super:
    let pkg = coqPackage self; in {
      QuickChick      = pkg ./coq/QuickChick.nix;
      fiat_HEAD       = pkg ./coq/fiat.nix;
      category-theory = pkg ./coq/category-theory.nix;
      procrastination = pkg ./coq/procrastination.nix;
    };

in {

coqFilterSource = paths: src: pkgs.lib.cleanSourceWith {
  inherit src;
  filter = path: type:
    let baseName = baseNameOf path; in
    !( type == "directory"
       && builtins.elem baseName ([".git"] ++ paths))
    &&
    !( type == "unknown"
       || baseName == ".coq-version"
       || baseName == "CoqMakefile.conf"
       || baseName == "Makefile.coq"
       || baseName == "Makefile.coq-old.conf"
       || baseName == "result"
       || pkgs.stdenv.lib.hasSuffix ".a" path
       || pkgs.stdenv.lib.hasSuffix ".o" path
       || pkgs.stdenv.lib.hasSuffix ".cmi" path
       || pkgs.stdenv.lib.hasSuffix ".cmo" path
       || pkgs.stdenv.lib.hasSuffix ".cmx" path
       || pkgs.stdenv.lib.hasSuffix ".cmxa" path
       || pkgs.stdenv.lib.hasSuffix ".cmxs" path
       || pkgs.stdenv.lib.hasSuffix ".ml.d" path
       || pkgs.stdenv.lib.hasSuffix ".ml4" path
       || pkgs.stdenv.lib.hasSuffix ".ml4.d" path
       || pkgs.stdenv.lib.hasSuffix ".mllib.d" path
       || pkgs.stdenv.lib.hasSuffix ".aux" path
       || pkgs.stdenv.lib.hasSuffix ".glob" path
       || pkgs.stdenv.lib.hasSuffix ".v.d" path
       || pkgs.stdenv.lib.hasSuffix ".vo" path);
};

coq_8_8_override = pkgs.coq_8_8.override {
  ocamlPackages = self.ocaml-ng.ocamlPackages_4_06;
  buildIde = true;
};

coq_HEAD = with pkgs; stdenv.lib.overrideDerivation self.coq_8_8_override (attrs: rec {
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

coqPackages_HEAD = extendAttrs (self.mkCoqPackages self.coq_HEAD)
  (pkgs.lib.composeExtensions
     (self: super: let pkg = coqPackage self; in {
        ssreflect = null;
        equations = pkg ./coq/equations.nix;
      })
     myCoqPackages);

coqPackages_8_8 = extendAttrs (self.mkCoqPackages self.coq_8_8)
  (pkgs.lib.composeExtensions
     (self: super: let pkg = coqPackage self; in {
        ssreflect = null;
        equations = pkg ./coq/equations.nix;
      })
     myCoqPackages);

coqPackages_8_7 = extendAttrs (self.mkCoqPackages self.coq_8_7) myCoqPackages;
coqPackages_8_6 = extendAttrs (self.mkCoqPackages self.coq_8_6) myCoqPackages;
coqPackages_8_5 = self.mkCoqPackages self.coq_8_5;
coqPackages_8_4 = self.mkCoqPackages self.coq_8_4;

coqHEADEnv = myPkgs: pkgs.myEnvFun {
  name = "coqHEAD";
  buildInputs = [ self.coq_HEAD ] ++ myPkgs "HEAD" self.coqPackages_HEAD;
};

coq88Env = myPkgs: pkgs.myEnvFun {
  name = "coq88";
  buildInputs = [ self.coq_8_8 ] ++ myPkgs "8.8" self.coqPackages_8_8;
};

coq87Env = myPkgs: pkgs.myEnvFun {
  name = "coq87";
  buildInputs = [ self.coq_8_7 ] ++ myPkgs "8.7" self.coqPackages_8_7;
};

coq86Env = myPkgs: pkgs.myEnvFun {
  name = "coq86";
  buildInputs = [ self.coq_8_6 ] ++ myPkgs "8.6" self.coqPackages_8_6;
};

coq85Env = myPkgs: pkgs.myEnvFun {
  name = "coq85";
  buildInputs = [ self.coq_8_5 ] ++ myPkgs "8.5" self.coqPackages_8_5;
};

coq84Env = myPkgs: pkgs.myEnvFun {
  name = "coq84";
  buildInputs = [ self.coq_8_4 ] ++ myPkgs "8.4" self.coqPackages_8_4;
};

}
