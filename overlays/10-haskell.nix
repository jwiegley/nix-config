self: pkgs: rec {

# All of these projects are identified simply by their .cabal files, no other
# special handling is needed.
srcs = [
  "async-pool"
  "bindings-DSL"
  "c2hsc"
  "consistent"
  "coq-haskell"
  "fuzzcheck"
  "git-all"
  "git-du"
  "hackage-mirror"
  "hs-to-coq"
  "ipcvar"
  "linearscan"
  "linearscan-hoopl"
  "logging"
  "monad-extras"
  "parsec-free"
  "pipes-async"
  "pushme"
  "recursors"
  "runmany"
  "sizes"
  "una"
  "z3-generate-api"
];

myHaskellPackageDefs = super:
  let fromSrc = name: args: {
      ${name} = super.callCabal2nix name (~/src + "/${name}") args;
    }; in
  with super; let pkg = super.callPackage; in

  builtins.foldl' (acc: x: acc // fromSrc x {}) {} srcs // rec {

  git-monitor    = pkg ~/src/gitlib/git-monitor {};
  gitlib         = pkg ~/src/gitlib/gitlib {};
  gitlib-cmdline = pkg ~/src/gitlib/gitlib-cmdline
                     { inherit (pkgs.gitAndTools) git; };
  gitlib-libgit2 = pkg ~/src/gitlib/gitlib-libgit2 {};
  gitlib-test    = pkg ~/src/gitlib/gitlib-test {};
  hierarchy      = pkg ~/src/hierarchy { nixpkgs = self; };
  hlibgit2       = pkg ~/src/gitlib/hlibgit2
                     { inherit (pkgs.gitAndTools) git; };
  hnix           = pkg ~/src/hnix { nixpkgs = self; };
  pipes-files    = pkg ~/src/pipes-files { nixpkgs = self; };
  sitebuilder    = pkg ~/src/sitebuilder
                     { inherit (pkgs) yuicompressor; };
  z3             = pkg ~/bae/concerto/solver/lib/z3 {};

  hours = (pkgs.haskell.lib.dontHaddock (pkg ~/src/hours {}))
    .overrideDerivation (attrs: {
      installPhase = ''
        mkdir -p $out/bin
        cp jobhours $out/bin
        cp gethours $out/bin
        cp dist/build/bae-periods/bae-periods $out/bin
        cp dist/build/timelog-periods/timelog-periods $out/bin
        cp dist/build/process-hours/process-hours $out/bin
      '';
    });

  timeparsers = super.callCabal2nix "timeparsers" (pkgs.fetchFromGitHub {
    owner  = "jwiegley";
    repo   = "timeparsers";
    rev    = "ebdc0071f43833b220b78523f6e442425641415d";
    sha256 = "0h8wkqyvahp0csfcj5dl7j56ib8m1aad5kwcsccaahiciic249xq";
    # date = 2017-01-19T16:47:50-08:00;
  }) {};
};

haskellFilterSource = paths: src: builtins.filterSource (path: type:
    let baseName = baseNameOf path; in
    !( type == "directory"
       && builtins.elem baseName ([".git" ".cabal-sandbox" "dist"] ++ paths))
    &&
    !( type == "unknown"
       || pkgs.stdenv.lib.hasSuffix ".hdevtools.sock" path
       || pkgs.stdenv.lib.hasSuffix ".sock" path
       || pkgs.stdenv.lib.hasSuffix ".hi" path
       || pkgs.stdenv.lib.hasSuffix ".hi-boot" path
       || pkgs.stdenv.lib.hasSuffix ".o" path
       || pkgs.stdenv.lib.hasSuffix ".o-boot" path
       || pkgs.stdenv.lib.hasSuffix ".dyn_o" path
       || pkgs.stdenv.lib.hasSuffix ".p_o" path))
  src;

haskellPackage_8_0_overrides = libProf: mypkgs: self: super:
  with pkgs.haskell.lib; with super; let pkg = callPackage; in mypkgs // rec {

  Agda                     = dontHaddock super.Agda;
  blaze-builder-enumerator = doJailbreak super.blaze-builder-enumerator;
  commodities              = doJailbreak mypkgs.commodities;
  concurrent-output        = doJailbreak super.concurrent-output;
  consistent               = dontCheck mypkgs.consistent;
  cryptohash-sha512        = doJailbreak super.cryptohash-sha512;
  data-inttrie             = doJailbreak super.data-inttrie;
  diagrams-builder         = doJailbreak super.diagrams-builder;
  diagrams-cairo           = doJailbreak super.diagrams-cairo;
  diagrams-contrib         = doJailbreak super.diagrams-contrib;
  diagrams-core            = doJailbreak super.diagrams-core;
  diagrams-graphviz        = doJailbreak super.diagrams-graphviz;
  diagrams-lib             = doJailbreak super.diagrams-lib;
  diagrams-postscript      = doJailbreak super.diagrams-postscript;
  diagrams-rasterific      = doJailbreak super.diagrams-rasterific;
  diagrams-svg             = doJailbreak super.diagrams-svg;
  ghc-compact              = null;
  haddock-library          = doJailbreak super.haddock-library_1_2_1;
  hakyll                   = doJailbreak super.hakyll;
  heap                     = dontCheck super.heap;
  indents                  = doJailbreak super.indents;
  inline-c-cpp             = dontCheck super.inline-c-cpp;
  ipcvar                   = dontCheck super.ipcvar;
  linearscan-hoopl         = dontCheck super.linearscan-hoopl;
  machinecell              = doJailbreak super.machinecell;
  monad-logger             = doJailbreak super.monad-logger;
  pipes-binary             = doJailbreak super.pipes-binary;
  pipes-group              = doJailbreak super.pipes-group;
  pipes-zlib               = dontCheck (doJailbreak super.pipes-zlib);
  recursors                = doJailbreak super.recursors;
  runmany                  = doJailbreak super.runmany;
  sbvPlugin                = doJailbreak super.sbvPlugin;
  serialise                = dontCheck super.serialise;
  stylish-haskell          = dontCheck super.stylish-haskell;
  text-show                = dontCheck super.text-show;
  time-recurrence          = doJailbreak super.time-recurrence;

  ghc-datasize = overrideCabal super.ghc-datasize (attrs: {
    enableLibraryProfiling    = false;
    enableExecutableProfiling = false;
  });
  ghc-heap-view = overrideCabal super.ghc-heap-view (attrs: {
    enableLibraryProfiling    = false;
    enableExecutableProfiling = false;
  });

  Cabal = super.Cabal_1_24_2_0;
  cabal-install =
    self.callHackage "cabal-install" "1.24.0.2" { Cabal = Cabal; };
  cabal-helper = super.cabal-helper.override {
    cabal-install = cabal-install;
    Cabal = Cabal;
  };

  th-desugar_1_6 = self.callHackage "th-desugar" "1.6" {};
  singletons = dontCheck (doJailbreak (self.callHackage "singletons" "2.2" {
    th-desugar = th-desugar_1_6;
  }));
  units = super.units.override {
    th-desugar = th-desugar_1_6;
  };

  # lens-family 1.2.2 requires GHC 8.2 or higher
  lens-family = self.callHackage "lens-family" "1.2.1" {};
  lens-family-core = self.callHackage "lens-family-core" "1.2.1" {};

  haskell-ide-engine = (import (
    pkgs.fetchFromGitHub {
      owner = "domenkozar";
      repo = "hie-nix";
      rev = "dbb89939da8997cc6d863705387ce7783d8b6958";
      sha256 = "1bcw59zwf788wg686p3qmcq03fr7bvgbcaa83vq8gvg231bgid4m";
      # date = 2018-03-27T10:14:16+01:00;
    }) {}).hie80;

  recurseForDerivations = true;

  mkDerivation = args: super.mkDerivation (args // {
    enableLibraryProfiling = libProf;
    enableExecutableProfiling = libProf;
  });
};

haskellPackage_8_2_overrides = libProf: mypkgs: self: super:
  with pkgs.haskell.lib; with super; let pkg = callPackage; in mypkgs // rec {

  Agda                     = dontHaddock super.Agda;
  blaze-builder-enumerator = doJailbreak super.blaze-builder-enumerator;
  commodities              = doJailbreak mypkgs.commodities;
  consistent               = dontCheck (doJailbreak mypkgs.consistent);
  cryptohash-sha512         = doJailbreak super.cryptohash-sha512;
  diagrams-builder         = doJailbreak super.diagrams-builder;
  diagrams-cairo           = doJailbreak super.diagrams-cairo;
  diagrams-contrib         = doJailbreak super.diagrams-contrib;
  diagrams-core            = doJailbreak super.diagrams-core;
  diagrams-graphviz        = doJailbreak super.diagrams-graphviz;
  diagrams-lib             = doJailbreak super.diagrams-lib;
  diagrams-postscript      = doJailbreak super.diagrams-postscript;
  diagrams-rasterific      = doJailbreak super.diagrams-rasterific;
  diagrams-svg             = doJailbreak super.diagrams-svg;
  github-backup            = doJailbreak super.github-backup;
  heap                     = dontCheck super.heap;
  indents                  = doJailbreak super.indents;
  inline-c-cpp             = dontCheck super.inline-c-cpp;
  ipcvar                   = dontCheck super.ipcvar;
  linearscan-hoopl         = dontCheck mypkgs.linearscan-hoopl;
  machinecell              = doJailbreak super.machinecell;
  pipes-binary             = doJailbreak super.pipes-binary;
  pipes-group              = doJailbreak super.pipes-group;
  pipes-zlib               = dontCheck (doJailbreak super.pipes-zlib);
  pushme                   = doJailbreak mypkgs.pushme;
  recursors                = doJailbreak super.recursors;
  # super.runmany uses what is in Hackage; mypkgs.runmany uses local
  runmany                  = doJailbreak super.runmany;
  serialise                = dontCheck super.serialise;
  stylish-haskell          = dontCheck super.stylish-haskell;
  text-show                = dontCheck super.text-show;
  time-recurrence          = doJailbreak super.time-recurrence;
  timeparsers              = dontCheck (doJailbreak mypkgs.timeparsers);

  cabal-install =
    self.callHackage "cabal-install" "2.0.0.1" { Cabal = Cabal; };
  cabal-helper =
    self.callCabal2nix "cabal-install" (pkgs.fetchFromGitHub {
      owner  = "DanielG";
      repo   = "cabal-helper";
      rev    = "8648be0324c8f9e5f2904907ae5da3f867ea9f5a";
      sha256 = "092c01q0hnp6kx8h6qw2b7n5bh82nmnlw75vl3a35hxqx4qr3wq9";
      # date = 2018-04-30T14:30:23+02:00;
    }) {
      cabal-install = cabal-install;
      Cabal = Cabal;
    };

  hdevtools     = super.hdevtools.override { Cabal = super.Cabal; };
  hpc-coveralls = super.hpc-coveralls.override { Cabal = super.Cabal; };
  scotty        = super.scotty.override { hpc-coveralls = hpc-coveralls; };
  idris         = super.idris.override { Cabal = super.Cabal; };

  ghc-datasize = overrideCabal super.ghc-datasize (attrs: {
    enableLibraryProfiling    = false;
    enableExecutableProfiling = false;
  });
  ghc-heap-view = overrideCabal super.ghc-heap-view (attrs: {
    enableLibraryProfiling    = false;
    enableExecutableProfiling = false;
  });

  haskell-ide-engine = (import (pkgs.fetchFromGitHub {
    owner  = "domenkozar";
    repo   = "hie-nix";
    rev    = "dbb89939da8997cc6d863705387ce7783d8b6958";
    sha256 = "1bcw59zwf788wg686p3qmcq03fr7bvgbcaa83vq8gvg231bgid4m";
  }) {}).hie82;

  recurseForDerivations = true;

  mkDerivation = args: super.mkDerivation (args // {
    enableLibraryProfiling = libProf;
  });
};

haskellPackage_8_4_overrides = libProf: mypkgs: self: super:
  with pkgs.haskell.lib; with super; let pkg = callPackage; in mypkgs // rec {

  Agda                     = doJailbreak (dontHaddock super.Agda);
  HUnit                    = dontCheck super.HUnit;
  PSQueue                  = doJailbreak super.PSQueue;
  active                   = doJailbreak super.active;
  blaze-builder-enumerator = doJailbreak super.blaze-builder-enumerator;
  cabal-helper             = doJailbreak super.cabal-helper;
  circle-packing           = doJailbreak super.circle-packing;
  commodities              = doJailbreak mypkgs.commodities;
  compact                  = doJailbreak super.compact;
  compressed               = doJailbreak super.compressed;
  consistent               = doJailbreak (dontCheck mypkgs.consistent);
  derive-storable          = dontCheck super.derive-storable;
  diagrams-builder         = doJailbreak super.diagrams-builder;
  diagrams-cairo           = doJailbreak super.diagrams-cairo;
  diagrams-contrib         = doJailbreak super.diagrams-contrib;
  diagrams-core            = doJailbreak super.diagrams-core;
  diagrams-graphviz        = doJailbreak super.diagrams-graphviz;
  diagrams-lib             = doJailbreak super.diagrams-lib;
  diagrams-postscript      = doJailbreak super.diagrams-postscript;
  diagrams-rasterific      = doJailbreak super.diagrams-rasterific;
  diagrams-solve           = doJailbreak super.diagrams-solve;
  diagrams-svg             = doJailbreak super.diagrams-svg;
  force-layout             = doJailbreak super.force-layout;
  git-annex                = dontCheck super.git-annex;
  hakyll                   = doJailbreak super.hakyll;
  heap                     = dontCheck super.heap;
  hint                     = doJailbreak super.hint;
  hspec-smallcheck         = doJailbreak super.hspec-smallcheck;
  inline-c-cpp             = dontCheck super.inline-c-cpp;
  ipcvar                   = dontCheck super.ipcvar;
  json-stream              = doJailbreak super.json-stream;
  lattices                 = doJailbreak super.lattices;
  machinecell              = doJailbreak super.machinecell;
  monoid-extras            = doJailbreak super.monoid-extras;
  pipes-binary             = doJailbreak super.pipes-binary;
  pipes-group              = doJailbreak super.pipes-group;
  pipes-zlib               = dontCheck (doJailbreak super.pipes-zlib);
  posix-paths              = doJailbreak super.posix-paths;
  postgresql-simple        = doJailbreak super.postgresql-simple;
  recursors                = doJailbreak super.recursors;
  runmany                  = doJailbreak super.runmany;
  serialise                = doJailbreak (dontCheck super.serialise);
  servant-foreign          = doJailbreak super.servant-foreign;
  shelly                   = dontCheck (doJailbreak super.shelly);
  streaming-commons        = dontCheck super.streaming-commons;
  svg-builder              = doJailbreak super.svg-builder;
  tasty-hspec              = doJailbreak super.tasty-hspec;
  testing-feat             = doJailbreak super.testing-feat;
  text-icu                 = dontCheck super.text-icu;
  text-show                = dontCheck super.text-show;
  these                    = doJailbreak super.these;
  thyme                    = dontHaddock super.thyme;
  time-recurrence          = doJailbreak super.time-recurrence;
  timeparsers              = doJailbreak (dontCheck mypkgs.timeparsers);
  turtle                   = doJailbreak super.turtle;
  vector-sized             = doJailbreak super.vector-sized;
  wl-pprint                = doJailbreak super.wl-pprint;

  ghc-datasize =
    overrideCabal super.ghc-datasize (attrs: {
      enableLibraryProfiling    = false;
      enableExecutableProfiling = false;
    });
  ghc-heap-view =
    overrideCabal super.ghc-heap-view (attrs: {
      enableLibraryProfiling    = false;
      enableExecutableProfiling = false;
    });

  hoopl = super.hoopl_3_10_2_2;

  linearscan-hoopl = dontCheck super.linearscan-hoopl;

  recurseForDerivations = true;

  mkDerivation = args: super.mkDerivation (args // {
    # jww (2018-01-28): This crashes due to an infinite loop
    # libraryHaskellDepends =
    #   if builtins.hasAttr "libraryHaskellDepends" args
    #   then args.libraryHaskellDepends
    #          ++ [ pkgs.darwin.apple_sdk.frameworks.Cocoa ]
    #   else [ pkgs.darwin.apple_sdk.frameworks.Cocoa ];
    enableLibraryProfiling = libProf;
    enableExecutableProfiling = libProf;
  });
};

haskellPackage_HEAD_overrides = libProf: mypkgs: self: super:
  with pkgs.haskell.lib; with super; let pkg = callPackage; in mypkgs // rec {

  Agda                     = dontHaddock super.Agda;
  blaze-builder-enumerator = doJailbreak super.blaze-builder-enumerator;
  compressed               = doJailbreak super.compressed;
  consistent               = doJailbreak (dontCheck mypkgs.consistent);
  derive-storable          = dontCheck super.derive-storable;
  diagrams-builder         = doJailbreak super.diagrams-builder;
  diagrams-cairo           = doJailbreak super.diagrams-cairo;
  diagrams-contrib         = doJailbreak super.diagrams-contrib;
  diagrams-core            = doJailbreak super.diagrams-core;
  diagrams-graphviz        = doJailbreak super.diagrams-graphviz;
  diagrams-lib             = doJailbreak super.diagrams-lib;
  diagrams-postscript      = doJailbreak super.diagrams-postscript;
  diagrams-rasterific      = doJailbreak super.diagrams-rasterific;
  diagrams-svg             = doJailbreak super.diagrams-svg;
  hakyll                   = doJailbreak super.hakyll;
  inline-c-cpp             = dontCheck super.inline-c-cpp;
  ipcvar                   = dontCheck super.ipcvar;
  lattices                 = doJailbreak super.lattices;
  linearscan-hoopl         = dontCheck super.linearscan-hoopl;
  pipes-binary             = doJailbreak super.pipes-binary;
  pipes-zlib               = dontCheck (doJailbreak super.pipes-zlib);
  posix-paths              = doJailbreak super.posix-paths;
  recursors                = doJailbreak super.recursors;
  serialise                = dontCheck super.serialise;
  shelly                   = doJailbreak super.shelly;
  text-icu                 = dontCheck super.text-icu;
  these                    = doJailbreak super.these;
  time-recurrence          = doJailbreak super.time-recurrence;
  timeparsers              = doJailbreak (dontCheck mypkgs.timeparsers);

  ghc-datasize =
    overrideCabal super.ghc-datasize (attrs: {
      enableLibraryProfiling    = false;
      enableExecutableProfiling = false;
    });
  ghc-heap-view =
    overrideCabal super.ghc-heap-view (attrs: {
      enableLibraryProfiling    = false;
      enableExecutableProfiling = false;
    });

  mkDerivation = args: super.mkDerivation (args // {
    enableLibraryProfiling = libProf;
    enableExecutableProfiling = libProf;
  });
};

haskellPackages = haskellPackages_8_2;
haskPkgs = haskellPackages;

mkHaskellPackages = hpkgs: hoverrides: hpkgs.override {
  overrides = self: super: hoverrides (myHaskellPackageDefs super) self super;
};

haskellPackages_HEAD = mkHaskellPackages pkgs.haskell.packages.ghcHEAD
  (haskellPackage_HEAD_overrides false);
profiledHaskellPackages_HEAD = mkHaskellPackages pkgs.haskell.packages.ghcHEAD
  (haskellPackage_HEAD_overrides true);

haskellPackages_8_4 = mkHaskellPackages pkgs.haskell.packages.ghc842
  (haskellPackage_8_4_overrides false);
profiledHaskellPackages_8_4 = mkHaskellPackages pkgs.haskell.packages.ghc842
  (haskellPackage_8_4_overrides true);

haskellPackages_8_2 = mkHaskellPackages pkgs.haskell.packages.ghc822
  (haskellPackage_8_2_overrides false);
profiledHaskellPackages_8_2 = mkHaskellPackages pkgs.haskell.packages.ghc822
  (haskellPackage_8_2_overrides true);

haskellPackages_8_0 = mkHaskellPackages pkgs.haskell.packages.ghc802
  (haskellPackage_8_0_overrides false);
profiledHaskellPackages_8_0 = mkHaskellPackages pkgs.haskell.packages.ghc802
  (haskellPackage_8_0_overrides true);

ghcHEADEnv = myPkgs: pkgs.myEnvFun {
  name = "ghcHEAD";
  buildInputs = with pkgs.haskell.lib; with haskellPackages_HEAD; [
    (ghcWithHoogle (pkgs: myPkgs pkgs ++ (with pkgs; [
       compact
     ])))
  ];
};

ghcHEADProfEnv = myPkgs: pkgs.myEnvFun {
  name = "ghcHEADprof";
  buildInputs = with pkgs.haskell.lib; with profiledHaskellPackages_HEAD; [
    (ghcWithHoogle (pkgs: myPkgs pkgs ++ (with pkgs; [
       compact
     ])))
  ];
};

ghc84Env = myPkgs: pkgs.myEnvFun {
  name = "ghc84";
  buildInputs = with pkgs.haskell.lib; with haskellPackages_8_4; [
    (ghcWithHoogle (pkgs: myPkgs pkgs ++ (with pkgs; [
       compact
     ])))
  ];
};

ghc84ProfEnv = myPkgs: pkgs.myEnvFun {
  name = "ghc84prof";
  buildInputs = with pkgs.haskell.lib; with profiledHaskellPackages_8_4; [
    (ghcWithHoogle (pkgs: myPkgs pkgs ++ (with pkgs; [
       compact
     ])))
  ];
};

ghc82Env = myPkgs: pkgs.myEnvFun {
  name = "ghc82";
  buildInputs = with pkgs.haskell.lib; with haskellPackages_8_2; [
    (ghcWithHoogle (pkgs: myPkgs pkgs ++ (with pkgs; [
       compact
     ])))
    Agda
    idris
    haskell-ide-engine
    hdevtools
    lambdabot
    hlint
    alex
    happy
  ];
};

ghc82ProfEnv = myPkgs: pkgs.myEnvFun {
  name = "ghc82prof";
  buildInputs = with pkgs.haskell.lib; with profiledHaskellPackages_8_2; [
    (ghcWithHoogle (pkgs: myPkgs pkgs ++ (with pkgs; [
       compact
     ])))
    Agda
    idris
    haskell-ide-engine
    hdevtools
    lambdabot
    hlint
    alex
    happy
  ];
};

ghc80Env = myPkgs: pkgs.myEnvFun {
  name = "ghc80";
  buildInputs = with pkgs.haskell.lib; with haskellPackages_8_0; [
    (ghcWithHoogle (pkgs: myPkgs pkgs ++ (with pkgs; [
       singletons
       units
     ])))

    splot
    haskell-ide-engine
    hdevtools
    cabal-helper
  ];
};

ghc80ProfEnv = myPkgs: pkgs.myEnvFun {
  name = "ghc80prof";
  buildInputs = with pkgs.haskell.lib; with profiledHaskellPackages_8_0; [
    (ghcWithHoogle (pkgs: myPkgs pkgs ++ (with pkgs; [
       singletons
       units
     ])))

    splot
    haskell-ide-engine
    hdevtools
    cabal-helper
  ];
};

}
