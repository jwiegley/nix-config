self: pkgs:

let
  srcs = [
    "async-pool"
    "bindings-DSL"
    "c2hsc"
    "git-all"
    "gitlib/git-monitor"
    "gitlib/gitlib"
  [ "gitlib/gitlib-cmdline" { inherit (self.gitAndTools) git; } ]
    "gitlib/gitlib-libgit2"
    "gitlib/gitlib-test"
  [ "gitlib/hlibgit2" { inherit (self.gitAndTools) git; } ]
    "hierarchy"
  [ "hours" { compiler = "ghc865"; }
    # hours only builds with 8.6.5, because time-recurrence has not been
    # ported forward.
  ]
    "hnix"
    "logging"
    "monad-extras"
    "parsec-free"
    "pipes-async"
    "pipes-files"
    "pushme"
    "recursors"
    "runmany"
    "sitebuilder"
    "sizes"
    "una"
  ];

  packageDrv = ghc:
    callPackage (usingWithHoogle self.haskell.packages.${ghc}) ghc;

  otherHackagePackages = ghc:
    let pkg = p: self.packageDrv ghc p {}; in self: super:
    with pkgs.haskell.lib; {

    Agda                  = doJailbreak (dontHaddock super.Agda);
    Diff                  = dontCheck super.Diff;
    EdisonAPI             = unmarkBroken super.EdisonAPI;
    EdisonCore            = unmarkBroken super.EdisonCore;
    active                = unmarkBroken (doJailbreak super.active);
    base-compat-batteries = doJailbreak super.base-compat-batteries;
    cabal2nix             = dontCheck super.cabal2nix;
    diagrams              = unmarkBroken super.diagrams;
    diagrams-cairo        = unmarkBroken super.diagrams-cairo;
    diagrams-contrib      = unmarkBroken (doJailbreak super.diagrams-contrib);
    diagrams-core         = unmarkBroken super.diagrams-core;
    diagrams-graphviz     = doJailbreak super.diagrams-graphviz;
    diagrams-lib          = unmarkBroken super.diagrams-lib;
    diagrams-svg          = unmarkBroken (doJailbreak super.diagrams-svg);
    dual-tree             = unmarkBroken (doJailbreak super.dual-tree);
    force-layout          = unmarkBroken super.force-layout;
    generic-lens          = dontCheck super.generic-lens;
    haddock-library       = dontHaddock super.haddock-library;
    hasktags              = dontCheck super.hasktags;
    language-ecmascript   = doJailbreak super.language-ecmascript;
    liquidhaskell         = doJailbreak super.liquidhaskell;
    monoid-extras         = unmarkBroken (doJailbreak super.monoid-extras);
    pipes-binary          = doJailbreak super.pipes-binary;
    pipes-text            = unmarkBroken (doJailbreak super.pipes-text);
    pipes-zlib            = dontCheck (doJailbreak super.pipes-zlib);
    random                = doJailbreak super.random;
    rebase                = doJailbreak super.rebase;
    size-based            = unmarkBroken super.size-based;
    statestack            = unmarkBroken super.statestack;
    svg-builder           = unmarkBroken super.svg-builder;
    testing-feat          = unmarkBroken super.testing-feat;
    text-show             = dontCheck (doJailbreak super.text-show);
    time-compat           = doJailbreak super.time-compat;
    time-recurrence       = unmarkBroken (doJailbreak super.time-recurrence);

    aeson = overrideCabal super.aeson (attrs: {
      libraryHaskellDepends =
        attrs.libraryHaskellDepends ++ [ self.contravariant ];
    });

    ListLike = overrideCabal super.ListLike (attrs: {
      libraryHaskellDepends =
        attrs.libraryHaskellDepends ++ [ self.semigroups ];
    });

    ghc-datasize = overrideCabal super.ghc-datasize (attrs: {
      enableLibraryProfiling    = false;
      enableExecutableProfiling = false;
    });
    ghc-heap-view = overrideCabal super.ghc-heap-view (attrs: {
      enableLibraryProfiling    = false;
      enableExecutableProfiling = false;
    });

    timeparsers = dontCheck (doJailbreak
      (self.callCabal2nix "timeparsers" (pkgs.fetchFromGitHub {
        owner  = "jwiegley";
        repo   = "timeparsers";
        rev    = "ebdc0071f43833b220b78523f6e442425641415d";
        sha256 = "0h8wkqyvahp0csfcj5dl7j56ib8m1aad5kwcsccaahiciic249xq";
        # date = 2017-01-19T16:47:50-08:00;
      }) {}));

    ghc-exactprint = self.callCabal2nix "ghc-exactprint"
      (pkgs.fetchFromGitHub {
         owner  = "alanz";
         repo   = "ghc-exactprint";
         rev    = "b6b75027811fa4c336b34122a7a7b1a8df462563";
         sha256 = "1rfzppw9faprzabk323wdnjch0kyalggajb0s6s42q2gsr100gfx";
         # date = 2021-02-24T18:10:49+00:00;
       }) {};
  };

  callPackage = hpkgs: ghc: path: args:
    filtered (
      if builtins.pathExists (path + "/default.nix")
      then hpkgs.callPackage path
             ({ pkgs = self;
                compiler = ghc;
                returnShellEnv = false; } // args)
      else hpkgs.callCabal2nix hpkgs (builtins.baseNameOf path) path args);

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

  usingWithHoogle = hpkgs: hpkgs // rec {
    ghc = hpkgs.ghc // { withPackages = hpkgs.ghc.withHoogle; };
    ghcWithPackages = ghc.withPackages;
  };

  overrideHask = ghc: hpkgs: hoverrides: hpkgs.override {
    overrides =
      pkgs.lib.composeExtensions
        hoverrides
        (pkgs.lib.composeExtensions
           (otherHackagePackages ghc)
           (pkgs.lib.composeExtensions
              (myHaskellPackages ghc)
              (self: super: {
                 ghc = super.ghc // { withPackages = super.ghc.withHoogle; };
                 ghcWithPackages = self.ghc.withPackages;

                 developPackage =
                   { root
                   , name ? builtins.baseNameOf root
                   , source-overrides ? {}
                   , overrides ? self: super: {}
                   , modifier ? drv: drv
                   , returnShellEnv ? pkgs.lib.inNixShell }:
                   let
                     hpkgs =
                       (pkgs.lib.composeExtensions
                         (_: _: self)
                         (pkgs.lib.composeExtensions
                           (self.packageSourceOverrides source-overrides)
                           overrides)) {} super;
                     drv =
                       hpkgs.callCabal2nix name root {};
                   in if returnShellEnv
                      then (modifier drv).env
                      else modifier drv;
               })));
  };

  breakout = super: names:
    builtins.listToAttrs
      (builtins.map
         (x: { name  = x;
               value = pkgs.haskell.lib.doJailbreak super.${x}; })
         names);

  filtered = drv:
    drv.overrideAttrs
      (attrs: { src = self.haskellFilterSource [] attrs.src; });

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
       || pkgs.lib.hasSuffix ".hdevtools.sock" path
       || pkgs.lib.hasSuffix ".sock" path
       || pkgs.lib.hasSuffix ".hi" path
       || pkgs.lib.hasSuffix ".hi-boot" path
       || pkgs.lib.hasSuffix ".o" path
       || pkgs.lib.hasSuffix ".dyn_o" path
       || pkgs.lib.hasSuffix ".dyn_p" path
       || pkgs.lib.hasSuffix ".o-boot" path
       || pkgs.lib.hasSuffix ".p_o" path);
};

haskell = pkgs.haskell // {
  packages = pkgs.haskell.packages // rec {
    ghc865 = overrideHask "ghc865" pkgs.haskell.packages.ghc865 (self: super:
      { inherit (ghc884) hpack; }

      // (breakout super [
         "hakyll"
         "pandoc"
       ]));

    ghc884 = overrideHask "ghc884" pkgs.haskell.packages.ghc884 (self: super:
      (breakout super [
         "hakyll"
         "pandoc"
       ])
      );

    ghc8104 = overrideHask "ghc8104" pkgs.haskell.packages.ghc8104 (self: super:
      (breakout super [
         "hakyll"
         "pandoc"
       ])
      );

    ghc901 = overrideHask "ghc901" pkgs.haskell.packages.ghc901 (self: super:
      (breakout super [
         "hakyll"
         "pandoc"
       ])
      );
  };
};

haskellPackages_8_6  = self.haskell.packages.ghc865;
haskellPackages_8_8  = self.haskell.packages.ghc884;
haskellPackages_8_10 = self.haskell.packages.ghc8104;
haskellPackages_9_0  = self.haskell.packages.ghc901;

haskellPackages = self.haskell.packages.${self.ghcDefaultVersion};
haskPkgs = self.haskellPackages;


ghcDefaultVersion = "ghc8104";

}
