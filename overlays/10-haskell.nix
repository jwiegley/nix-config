self: pkgs:

let
  # All of these projects are identified simply by their .cabal files, no other
  # special handling is needed.
  srcs = [
    "async-pool"
    "bindings-DSL"
    "c2hsc"
    "coq-haskell"
    "git-all"
    "git-du"
    "gitlib/git-monitor"
    "gitlib/gitlib"
    [ "gitlib/gitlib-cmdline" { inherit (self.gitAndTools) git; } ]
    "gitlib/gitlib-libgit2"
    "gitlib/gitlib-test"
    [ "gitlib/hlibgit2" { inherit (self.gitAndTools) git; } ]
    "hierarchy"
    "hnix"
    "hours"
    "hs-to-coq"
    "linearscan"
    "linearscan-hoopl"
    "logging"
    "monad-extras"
    "parsec-free"
    "pipes-async"
    "pipes-files"
    "pushme"
    "recursors"
    "runmany"
    [ "sitebuilder" { inherit (self) yuicompressor; } ]
    "sizes"
    "una"
    "z3-generate-api"
    "z3cat"
  ];

  otherHackagePackages = ghc:
    let pkg = p: self.packageDrv ghc p {}; in self: super:
    with pkgs.haskell.lib; {

    z3 = if ghc == "ghc842"
         then null
         else pkg ~/bae/concerto/solver/lib/z3;

    rings-dashboard = pkg ~/bae/micromht-deliverable/rings-dashboard;
    rings-dashboard-api =
      pkg ~/bae/micromht-deliverable/rings-dashboard/rings-dashboard-api;
    harness = pkg ~/bae/micromht-deliverable/rings-dashboard/mitll-harness;

    stanag4607 = pkg ~/bae/micromht-fiat-deliverable/atif-fiat/stanag4607;

    Agda              = dontHaddock super.Agda;
    diagrams-contrib  = doJailbreak super.diagrams-contrib;
    diagrams-graphviz = doJailbreak super.diagrams-graphviz;
    diagrams-svg      = doJailbreak super.diagrams-svg;
    hasktags          = dontCheck super.hasktags;
    pipes-binary      = doJailbreak super.pipes-binary;
    pipes-zlib        = dontCheck (doJailbreak super.pipes-zlib);
    text-show         = dontCheck (doJailbreak super.text-show);
    time-recurrence   = doJailbreak super.time-recurrence;

    timeparsers = dontCheck (doJailbreak
      (self.callCabal2nix "timeparsers" (pkgs.fetchFromGitHub {
        owner  = "jwiegley";
        repo   = "timeparsers";
        rev    = "ebdc0071f43833b220b78523f6e442425641415d";
        sha256 = "0h8wkqyvahp0csfcj5dl7j56ib8m1aad5kwcsccaahiciic249xq";
        # date = 2017-01-19T16:47:50-08:00;
      }) {}));

    ghc-datasize = overrideCabal super.ghc-datasize (attrs: {
      enableLibraryProfiling    = false;
      enableExecutableProfiling = false;
    });
    ghc-heap-view = overrideCabal super.ghc-heap-view (attrs: {
      enableLibraryProfiling    = false;
      enableExecutableProfiling = false;
    });
  };

  callPackage = hpkgs: ghc: path: args:
    filtered (
      if builtins.pathExists (path + ("/default.nix"))
      then (if ghc == null
            then import
            else hpkgs.callPackage)
             path ({ pkgs = self;
                     compiler = if ghc == null
                                then self.ghcDefaultVersion
                                else ghc;
                     returnShellEnv = false; } // args)
      else hpkgs.callCabal2nix (builtins.baseNameOf path) path args);

  myHaskellPackages = ghc: self: super:
    let fromSrc = arg:
      let
        path = if builtins.isList arg then builtins.elemAt arg 0 else arg;
        args = if builtins.isList arg then builtins.elemAt arg 1 else {};
      in {
        name  = builtins.baseNameOf path;
        value = callPackage self ghc (~/src + "/${path}") args;
      };
    in builtins.listToAttrs (builtins.map fromSrc srcs);

  overrideHask = ghc: hpkgs: hoverrides: hpkgs.override {
    overrides = pkgs.lib.composeExtensions
      (pkgs.lib.composeExtensions (otherHackagePackages ghc) hoverrides)
      (myHaskellPackages ghc);
  };

  breakout = super: names:
    builtins.listToAttrs
      (builtins.map (x: { name  = x;
                          value = pkgs.haskell.lib.doJailbreak super.${x}; })
                    names);

  filtered = drv: drv // { src = self.haskellFilterSource [] drv.src; };

in {

haskellFilterSource = paths: src: pkgs.lib.cleanSourceWith {
  inherit src;
  filter = path: type:
    let baseName = baseNameOf path; in
    !( type == "directory"
       && builtins.elem baseName ([".git" ".cabal-sandbox" "dist"] ++ paths))
    &&
    !( type == "unknown"
       || baseName == "cabal.sandbox.config"
       || baseName == "result"
       || pkgs.stdenv.lib.hasSuffix ".hdevtools.sock" path
       || pkgs.stdenv.lib.hasSuffix ".sock" path
       || pkgs.stdenv.lib.hasSuffix ".hi" path
       || pkgs.stdenv.lib.hasSuffix ".hi-boot" path
       || pkgs.stdenv.lib.hasSuffix ".o" path
       || pkgs.stdenv.lib.hasSuffix ".dyn_o" path
       || pkgs.stdenv.lib.hasSuffix ".dyn_p" path
       || pkgs.stdenv.lib.hasSuffix ".o-boot" path
       || pkgs.stdenv.lib.hasSuffix ".p_o" path);
};

usingWithHoogle = hpkgs: hpkgs.override {
  overrides = self: super: {
    ghc = super.ghc // { withPackages = super.ghc.withHoogle; };
    ghcWithPackages = self.ghc.withPackages;
  };
};

packageDrv = ghc: path: args:
  let ghcVer = if ghc == null then self.ghcDefaultVersion else ghc;
      hpkgs  = self.usingWithHoogle self.haskell.packages.${ghcVer};
  in callPackage hpkgs ghc path args;

packageDeps = path:
  let
    package  = self.packageDrv null path {};
    compiler = package.compiler;
    packages = self.haskell.lib.getHaskellBuildInputs package;
    ghc      = self.ghcDefaultVersion;
    cabal    = {
      ghc802 = "1.24.0.2";
      ghc822 = "2.0.0.1";
      ghc842 = "2.2.0.0";
    };

    # hie-nix = import (pkgs.fetchFromGitHub {
    #   owner  = "domenkozar";
    #   repo   = "hie-nix";
    #   rev    = "dbb89939da8997cc6d863705387ce7783d8b6958";
    #   sha256 = "1bcw59zwf788wg686p3qmcq03fr7bvgbcaa83vq8gvg231bgid4m";
    #   # date = 2018-03-27T10:14:16+01:00;
    # }) {};

    # hie = {
    #   ghc802 = hie-nix.hie80;
    #   ghc822 = hie-nix.hie82;
    #   ghc842 = throw "HIE not supported on GHC 8.4.2 yet";
    # };

  in compiler.withHoogle (p: with p;
       [ hpack criterion hdevtools # hie.${ghc}
         (callHackage "cabal-install" cabal.${ghc} {})
       ] ++ packages.haskellBuildInputs);

dirLocals = root:
  let
    cabal-found =
      pkgs.lib.filesystem.locateDominatingFile "([^.].*)\\.cabal" root;

    coq = self.coq_8_7;
    coqPackages = self.coqPackages_8_7; in

  if cabal-found != null
  then self.nixBufferBuilders.withPackages
         [ (self.packageDeps cabal-found.path) ]
  else
  if pkgs.lib.filesystem.locateDominatingFile "_CoqProject" root != null
  then self.nixBufferBuilders.withPackages
         [ coq coqPackages.equations coqPackages.fiat_HEAD
           coqPackages.mathcomp coqPackages.ssreflect ]
  else {};

haskell = pkgs.haskell // {
  packages = pkgs.haskell.packages // {
    ghc802 = overrideHask "ghc802" pkgs.haskell.packages.ghc802 (self: super:
      (breakout super [
        "concurrent-output"
        "hakyll"
      ])
      // (with pkgs.haskell.lib; {
        ghc-compact = null;

        th-desugar_1_6 = self.callHackage "th-desugar" "1.6" {};
        singletons = dontCheck (doJailbreak (self.callHackage "singletons" "2.2" {
          th-desugar = self.th-desugar_1_6;
        }));
        units = super.units.override {
          th-desugar = self.th-desugar_1_6;
        };

        lens-family = self.callHackage "lens-family" "1.2.1" {};
        lens-family-core = self.callHackage "lens-family-core" "1.2.1" {};
      }));

    ghc822 = overrideHask "ghc822" pkgs.haskell.packages.ghc822 (self: super: {
      });

    ghc842 = overrideHask "ghc842" pkgs.haskell.packages.ghc842 (self: super:
      breakout super [
        "compact"
        "criterion"
        "text-format"
      ]);
  };
};

haskellPackages_8_0 = self.haskell.packages.ghc802;
haskellPackages_8_2 = self.haskell.packages.ghc822;
haskellPackages_8_4 = self.haskell.packages.ghc842;

ghcDefaultVersion = "ghc822";

haskellPackages = self.haskellPackages_8_2;
haskPkgs = self.haskellPackages;

ghc84Env = myPkgs: pkgs.myEnvFun {
  name = "ghc84";
  buildInputs = with self.haskellPackages_8_4; [
    (ghcWithHoogle (pkgs: with pkgs; myPkgs pkgs ++ [
       compact
     ]))
  ];
};

ghc82Env = myPkgs: pkgs.myEnvFun {
  name = "ghc82";
  buildInputs = with self.haskellPackages_8_2; [
    (ghcWithHoogle (pkgs: with pkgs; myPkgs pkgs ++ [
       compact
     ]))

    Agda
    idris
    lambdabot
    alex
    happy
  ];
};

ghc80Env = myPkgs: pkgs.myEnvFun {
  name = "ghc80";
  buildInputs = with self.haskellPackages_8_0; [
    (ghcWithHoogle (pkgs: with pkgs; myPkgs pkgs ++ [
       singletons
       units
     ]))

    splot
  ];
};

}
