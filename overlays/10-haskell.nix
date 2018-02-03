self: pkgs: rec {

##############################################################################
# Haskell

myHaskellPackageDefs = super:
  with super; let pkg = super.callPackage; in rec {

  async-pool       = pkg ~/src/async-pool {};
  bindings-DSL     = pkg ~/src/bindings-DSL {};
  c2hsc            = pkg ~/src/c2hsc {};
  commodities      = pkg ~/src/ledger4/commodities {};
  consistent       = pkg ~/src/consistent {};
  coq-haskell      = pkg ~/src/coq-haskell {};
  fuzzcheck        = pkg ~/src/fuzzcheck {};
  git-all          = pkg ~/src/git-all {};
  git-du           = pkg ~/src/git-du {};
  git-monitor      = pkg ~/src/gitlib/git-monitor {};
  gitlib           = pkg ~/src/gitlib/gitlib {};
  gitlib-cmdline   = pkg ~/src/gitlib/gitlib-cmdline { inherit (pkgs.gitAndTools) git; };
  gitlib-hit       = pkg ~/src/gitlib/gitlib-hit {};
  gitlib-libgit2   = pkg ~/src/gitlib/gitlib-libgit2 {};
  gitlib-test      = pkg ~/src/gitlib/gitlib-test {};
  hierarchy        = pkg ~/src/hierarchy {};
  hlibgit2         = pkg ~/src/gitlib/hlibgit2 { inherit (pkgs.gitAndTools) git; };
  hnix             = pkg ~/src/hnix {};
  ipcvar           = pkg ~/src/ipcvar {};
  linearscan       = pkg ~/src/linearscan {};
  linearscan-hoopl = pkg ~/src/linearscan-hoopl {};
  logging          = pkg ~/src/logging {};
  monad-extras     = pkg ~/src/monad-extras {};
  parsec-free      = pkg ~/src/parsec-free {};
  pipes-async      = pkg ~/src/pipes-async {};
  pipes-files      = pkg ~/src/pipes-files {};
  pushme           = pkg ~/src/pushme {};
  recursors        = pkg ~/src/recursors {};
  runmany          = pkg ~/src/runmany {};
  simple-mirror    = pkg ~/src/hackage-mirror {};
  sitebuilder      = pkg ~/src/sitebuilder { inherit (pkgs) yuicompressor; };
  sizes            = pkg ~/src/sizes {};
  una              = pkg ~/src/una {};
  z3               = pkg ~/src/haskell-z3 { z3 = pkgs.z3; };
  z3-generate-api  = pkg ~/src/z3-generate-api { };

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

  hs-to-coq = pkg ~/src/hs-to-coq/hs-to-coq {};

  timeparsers = super.timeparsers.overrideDerivation (attrs: {
    src = pkgs.fetchFromGitHub {
      owner = "jwiegley";
      repo = "timeparsers";
      rev = "ebdc0071f43833b220b78523f6e442425641415d";
      sha256 = "0h8wkqyvahp0csfcj5dl7j56ib8m1aad5kwcsccaahiciic249xq";
      # date = 2017-01-19T16:47:50-08:00;
    };
  });
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

  Agda                      = dontHaddock super.Agda;
  blaze-builder-enumerator  = doJailbreak super.blaze-builder-enumerator;
  commodities               = doJailbreak mypkgs.commodities;
  compressed                = doJailbreak super.compressed;
  concurrent-output         = doJailbreak super.concurrent-output;
  consistent                = dontCheck mypkgs.consistent;
  derive-storable           = dontCheck super.derive-storable;
  diagrams-graphviz         = doJailbreak super.diagrams-graphviz;
  diagrams-rasterific       = doJailbreak super.diagrams-rasterific;
  ghc-compact               = null;
  hakyll                    = doJailbreak super.hakyll;
  heap                      = dontCheck super.heap;
  hierarchy                 = doJailbreak super.hierarchy;
  hlibgit2                  = doJailbreak super.hlibgit2;
  ipcvar                    = dontCheck super.ipcvar;
  linearscan-hoopl          = dontCheck super.linearscan-hoopl;
  liquidhaskell             = doJailbreak super.liquidhaskell;
  pipes-binary              = doJailbreak super.pipes-binary;
  pipes-files               = dontCheck (doJailbreak super.pipes-files);
  pipes-zlib                = dontCheck (doJailbreak super.pipes-zlib);
  recursors                 = doJailbreak super.recursors;
  runmany                   = doJailbreak super.runmany;
  sbvPlugin                 = doJailbreak super.sbvPlugin;
  shelly                    = dontCheck super.shelly;
  text-show                 = dontCheck super.text-show;
  time-recurrence           = doJailbreak super.time-recurrence;
  timeparsers               = doJailbreak (dontCheck mypkgs.timeparsers);

  Cabal = super.Cabal_1_24_2_0;

  cabal-install = callPackage
    ({ mkDerivation, array, async, base, base16-bytestring, binary
     , bytestring, Cabal, containers, cryptohash-sha256, directory
     , filepath, hackage-security, hashable, HTTP, mtl, network
     , network-uri, pretty, process, QuickCheck, random, regex-posix
     , stm, tagged, tar, tasty, tasty-hunit, tasty-quickcheck, time
     , unix, zlib
     }:
     mkDerivation {
       pname = "cabal-install";
       version = "1.24.0.2";
       sha256 = "1q0gl3i9cpg854lcsiifxxginnvhp2bpx19wkkzpzrd072983j1a";
       revision = "1";
       editedCabalFile = "0v112hvvppa31sklpzg54vr0hfidy1334kg5p3jc0gbgl8in1n90";
       isLibrary = false;
       isExecutable = true;
       executableHaskellDepends = [
         array async base base16-bytestring binary bytestring Cabal
         containers cryptohash-sha256 directory filepath hackage-security
         hashable HTTP mtl network network-uri pretty process random stm tar
         time unix zlib
       ];
       testHaskellDepends = [
         array async base binary bytestring Cabal containers directory
         filepath hackage-security hashable HTTP mtl network network-uri
         pretty process QuickCheck random regex-posix stm tagged tar tasty
         tasty-hunit tasty-quickcheck time unix zlib
       ];
       doCheck = false;
       postInstall = ''
         mkdir $out/etc
         mv bash-completion $out/etc/bash_completion.d
       '';
       homepage = "http://www.haskell.org/cabal/";
       description = "The command-line interface for Cabal and Hackage";
       license = pkgs.stdenv.lib.licenses.bsd3;
       maintainers = with pkgs.stdenv.lib.maintainers; [ peti ];
     }) { Cabal = Cabal; };

  cabal-helper = super.cabal-helper.override {
    cabal-install = cabal-install;
    Cabal = Cabal;
  };

  th-desugar_1_6 = mkDerivation {
    pname = "th-desugar";
    version = "1.6";
    sha256 = "0kv3gxvr7izvg1s86p92b5318bv7pjghig2hx9q21cg9ppifry68";
    revision = "2";
    editedCabalFile = "0rimjzkqky6sq4yba7vqra7hj29903f9xsn2g8rc23abrm35vds3";
    libraryHaskellDepends = [
      base containers mtl syb template-haskell th-expand-syns th-lift
      th-orphans
    ];
    testHaskellDepends = [
      base containers hspec HUnit mtl syb template-haskell th-expand-syns
      th-lift th-orphans
    ];
    homepage = "https://github.com/goldfirere/th-desugar";
    description = "Functions to desugar Template Haskell";
    license = stdenv.lib.licenses.bsd3;
  };

  singletons = dontCheck (doJailbreak (callPackage
    ({ mkDerivation, base, Cabal, containers, directory, filepath, mtl
     , process, syb, tasty, tasty-golden, template-haskell, th-desugar
     }:
     mkDerivation {
       pname = "singletons";
       version = "2.2";
       sha256 = "1bwcsp1x8bivmvkv8a724lsnwyjharhb0x0hl0isp3jgigh0dg9k";
       libraryHaskellDepends = [
         base containers mtl syb template-haskell th-desugar
       ];
       testHaskellDepends = [
         base Cabal directory filepath process tasty tasty-golden
       ];
       homepage = "http://www.github.com/goldfirere/singletons";
       description = "A framework for generating singleton types";
       license = stdenv.lib.licenses.bsd3;
     }) { th-desugar = th-desugar_1_6; }));

  units = super.units.override {
    th-desugar = th-desugar_1_6;
  };

  # lens-family 1.2.2 requires GHC 8.2 or higher
  lens-family = mkDerivation {
    pname = "lens-family";
    version = "1.2.1";
    sha256 = "1dwsrli94i8vs1wzfbxbxh49qhn8jn9hzmxwgd3dqqx07yx8x0s1";
    libraryHaskellDepends = [
      base containers lens-family-core mtl transformers
    ];
    description = "Lens Families";
    license = stdenv.lib.licenses.bsd3;
  };

  lens-family-core = mkDerivation {
    pname = "lens-family-core";
    version = "1.2.1";
    sha256 = "190r3n25m8x24nd6xjbbk9x0qhs1mw22xlpsbf3cdp3cda3vkqwm";
    libraryHaskellDepends = [ base containers transformers ];
    description = "Haskell 98 Lens Families";
    license = stdenv.lib.licenses.bsd3;
  };

  haskell-src-exts-simple_1_20_0_0 =
    super.haskell-src-exts-simple_1_20_0_0.override {
      haskell-src-exts = super.haskell-src-exts_1_20_1;
    };

  lambdabot-haskell-plugins = doJailbreak (
    super.lambdabot-haskell-plugins.override {
      haskell-src-exts-simple = haskell-src-exts-simple_1_20_0_0;
    });

  recurseForDerivations = true;

  mkDerivation = args: super.mkDerivation (args // {
    enableLibraryProfiling = libProf;
    enableExecutableProfiling = false;
  });
};

haskellPackage_8_2_overrides = libProf: mypkgs: self: super:
  with pkgs.haskell.lib; with super; let pkg = callPackage; in mypkgs // rec {

  Agda                     = dontHaddock super.Agda;
  blaze-builder-enumerator = doJailbreak super.blaze-builder-enumerator;
  compressed               = doJailbreak super.compressed;
  commodities              = doJailbreak mypkgs.commodities;
  consistent               = doJailbreak (dontCheck mypkgs.consistent);
  derive-storable          = dontCheck super.derive-storable;
  diagrams-graphviz        = doJailbreak super.diagrams-graphviz;
  diagrams-rasterific      = doJailbreak super.diagrams-rasterific;
  git-annex                = dontCheck super.git-annex;
  hakyll                   = doJailbreak super.hakyll;
  heap                     = dontCheck super.heap;
  hierarchy                = doJailbreak super.hierarchy;
  ipcvar                   = dontCheck super.ipcvar;
  lattices                 = doJailbreak super.lattices;
  linearscan-hoopl         = dontCheck super.linearscan-hoopl;
  pipes-binary             = doJailbreak super.pipes-binary;
  pipes-files              = dontCheck (doJailbreak super.pipes-files);
  pipes-zlib               = dontCheck (doJailbreak super.pipes-zlib);
  posix-paths              = doJailbreak super.posix-paths;
  recursors                = doJailbreak super.recursors;
  runmany                  = doJailbreak super.runmany;
  shelly                   = dontCheck (doJailbreak super.shelly);
  text-icu                 = dontCheck super.text-icu;
  text-show                = dontCheck super.text-show;
  these                    = doJailbreak super.these;
  time-recurrence          = doJailbreak super.time-recurrence;
  timeparsers              = doJailbreak (dontCheck mypkgs.timeparsers);

  diagrams-builder = with pkgs; with self; mkDerivation {
    pname = "diagrams-builder";
    version = "0.8.0.2";
    sha256 = "1jr98sza6bhzq9myfb9f2p8lfbs9qcxck67h2hvxisgpvmy0gjn2";
    configureFlags = [ "-fcairo" "-fps" "-frasterific" "-fsvg" ];
    isLibrary = true;
    isExecutable = true;
    libraryHaskellDepends = [
      base base-orphans cmdargs diagrams-lib directory exceptions
      filepath hashable haskell-src-exts haskell-src-exts-simple hint
      lens mtl split transformers
    ];
    executableHaskellDepends = [
      base bytestring cmdargs diagrams-cairo diagrams-lib
      diagrams-postscript diagrams-rasterific diagrams-svg directory
      filepath JuicyPixels lens svg-builder
    ];
    homepage = "http://projects.haskell.org/diagrams";
    description = "hint-based build service for the diagrams graphics EDSL";
    license = stdenv.lib.licenses.bsd3;
    hydraPlatforms = stdenv.lib.platforms.none;
  };

  haskell-src-exts-simple_1_20_0_0 =
    super.haskell-src-exts-simple_1_20_0_0.override {
      haskell-src-exts = super.haskell-src-exts_1_20_1;
    };

  lambdabot-haskell-plugins =
    super.lambdabot-haskell-plugins.override {
      haskell-src-exts-simple = haskell-src-exts-simple_1_20_0_0;
    };

  recurseForDerivations = true;

  mkDerivation = args: super.mkDerivation (args // {
    # jww (2018-01-28): This crashes due to an infinite loop
    # libraryHaskellDepends =
    #   if builtins.hasAttr "libraryHaskellDepends" args
    #   then args.libraryHaskellDepends
    #          ++ [ pkgs.darwin.apple_sdk.frameworks.Cocoa ]
    #   else [ pkgs.darwin.apple_sdk.frameworks.Cocoa ];
    enableLibraryProfiling = libProf;
    enableExecutableProfiling = false;
  });
};

haskellPackage_HEAD_overrides = libProf: mypkgs: self: super:
  with pkgs.haskell.lib; with super; let pkg = callPackage; in mypkgs // rec {

  Agda                     = dontHaddock super.Agda;
  blaze-builder-enumerator = doJailbreak super.blaze-builder-enumerator;
  compressed               = doJailbreak super.compressed;
  consistent               = doJailbreak (dontCheck mypkgs.consistent);
  derive-storable          = dontCheck super.derive-storable;
  diagrams-graphviz        = doJailbreak super.diagrams-graphviz;
  diagrams-rasterific      = doJailbreak super.diagrams-rasterific;
  hakyll                   = doJailbreak super.hakyll;
  hierarchy                = doJailbreak super.hierarchy;
  ipcvar                   = dontCheck super.ipcvar;
  lattices                 = doJailbreak super.lattices;
  linearscan-hoopl         = dontCheck super.linearscan-hoopl;
  pipes-binary             = doJailbreak super.pipes-binary;
  pipes-files              = dontCheck (doJailbreak super.pipes-files);
  pipes-zlib               = dontCheck (doJailbreak super.pipes-zlib);
  posix-paths              = doJailbreak super.posix-paths;
  recursors                = doJailbreak super.recursors;
  shelly                   = doJailbreak super.shelly;
  text-icu                 = dontCheck super.text-icu;
  these                    = doJailbreak super.these;
  time-recurrence          = doJailbreak super.time-recurrence;
  timeparsers              = doJailbreak (dontCheck mypkgs.timeparsers);

  mkDerivation = args: super.mkDerivation (args // {
    enableLibraryProfiling = libProf;
    enableExecutableProfiling = false;
  });
};

haskPkgs = haskellPackages_8_2;
haskellPackages = haskPkgs;

mkHaskellPackages = hpkgs: hoverrides: hpkgs.override {
  overrides = self: super: hoverrides (myHaskellPackageDefs super) self super;
};

haskellPackages_HEAD = mkHaskellPackages pkgs.haskell.packages.ghcHEAD
  (haskellPackage_HEAD_overrides false);
profiledHaskellPackages_HEAD = mkHaskellPackages pkgs.haskell.packages.ghcHEAD
  (haskellPackage_HEAD_overrides true);

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
    (ghcWithHoogle myPkgs)
  ];
};

ghcHEADProfEnv = myPkgs: pkgs.myEnvFun {
  name = "ghcHEADprof";
  buildInputs = with pkgs.haskell.lib; with profiledHaskellPackages_HEAD; [
    (ghcWithHoogle myPkgs)
  ];
};

ghc82Env = myPkgs: pkgs.myEnvFun {
  name = "ghc82";
  buildInputs = with pkgs.haskell.lib; with haskellPackages_8_2; [
    (ghcWithHoogle myPkgs)
    Agda
    idris
  ];
};

ghc82ProfEnv = myPkgs: pkgs.myEnvFun {
  name = "ghc82prof";
  buildInputs = with pkgs.haskell.lib; with profiledHaskellPackages_8_2; [
    (ghcWithHoogle myPkgs)
    Agda
    idris
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
  ];
};

}
