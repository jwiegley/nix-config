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
      fiat_HEAD       = pkg ./coq/fiat.nix;
      # category-theory = pkg ./coq/category-theory.nix;
    };

  extend_coq = coq: extendAttrs (self.mkCoqPackages coq) myCoqPackages;

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
       || pkgs.lib.hasSuffix ".a" path
       || pkgs.lib.hasSuffix ".o" path
       || pkgs.lib.hasSuffix ".cmi" path
       || pkgs.lib.hasSuffix ".cmo" path
       || pkgs.lib.hasSuffix ".cmx" path
       || pkgs.lib.hasSuffix ".cmxa" path
       || pkgs.lib.hasSuffix ".cmxs" path
       || pkgs.lib.hasSuffix ".ml.d" path
       || pkgs.lib.hasSuffix ".ml4" path
       || pkgs.lib.hasSuffix ".ml4.d" path
       || pkgs.lib.hasSuffix ".mllib.d" path
       || pkgs.lib.hasSuffix ".aux" path
       || pkgs.lib.hasSuffix ".glob" path
       || pkgs.lib.hasSuffix ".v.d" path
       || pkgs.lib.hasSuffix ".vo" path);
};

coq_HEAD = with pkgs; pkgs.lib.overrideDerivation self.coq_8_13 (attrs: rec {
  version = "HEAD";
  name = "coq-${version}-pre";
  coq-version = "${version}";

  src = ~/src/coq;

  buildInputs = attrs.buildInputs
    ++ (with pkgs; [ texFull hevea fig2dev imagemagick_light ]);

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

coq_8_13 = pkgs.coq_8_13.override { buildIde = false; };
coq_8_12 = pkgs.coq_8_12.override { buildIde = false; };
coq_8_11 = pkgs.coq_8_11.override { buildIde = false; };
coq_8_10 = pkgs.coq_8_10.override { buildIde = false; };

coqPackages_HEAD = extend_coq self.coq_HEAD;
coqPackages_8_13 = extend_coq self.coq_8_13;
coqPackages_8_12 = extend_coq self.coq_8_12;
coqPackages_8_11 = extend_coq self.coq_8_11;
coqPackages_8_10 = extend_coq self.coq_8_10;
coqPackages_8_9  = extend_coq self.coq_8_9;
coqPackages_8_8  = extend_coq self.coq_8_8;
coqPackages_8_7  = extend_coq self.coq_8_7;
coqPackages_8_6  = extend_coq self.coq_8_6;

coqPackages = self.coqPackages_8_13;

}
