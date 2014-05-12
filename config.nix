{ pkgs }:

{ packageOverrides = self: with pkgs; rec {

ledger = self.callPackage /Users/johnw/Projects/ledger {};

myProjects = cp: (self: super: {
  bugs          = cp /Users/johnw/Projects/bugs {};
  consistent    = cp /Users/johnw/Projects/consistent {};
  findConduit   = cp /Users/johnw/Projects/find-conduit {};
  gitAll        = cp /Users/johnw/Projects/git-all {};
  hours         = cp /Users/johnw/Projects/hours {};
  loggingHEAD   = cp /Users/johnw/Projects/logging {};
  pushme        = cp /Users/johnw/Projects/pushme {};
  simpleMirror  = cp /Users/johnw/Projects/simple-mirror {};
  theseHEAD     = cp /Users/johnw/Projects/these {};
  tryhaskell    = cp /Users/johnw/Projects/tryhaskell {};

  gitlib        = cp /Users/johnw/Projects/gitlib/gitlib {};
  gitlibTest    = cp /Users/johnw/Projects/gitlib/gitlib-test {};
  hlibgit2      = cp /Users/johnw/Projects/gitlib/hlibgit2 {};
  gitlibLibgit2 = cp /Users/johnw/Projects/gitlib/gitlib-libgit2 {};
  gitMonitor    = cp /Users/johnw/Projects/gitlib/git-monitor {};

  newartisans   = cp /Users/johnw/src/newartisans {};

  shellyHEAD             = cp /Users/johnw/src/shelly {};
  shellyExtraHEAD        = cp /Users/johnw/src/shelly/shelly-extra {};
  lensHEAD               = cp /Users/johnw/src/lens {};
  exceptionsHEAD         = cp /Users/johnw/Projects/exceptions {};
  conduitHEAD            = cp /Users/johnw/Projects/conduit/conduit {};
  conduitExtraHEAD       = cp /Users/johnw/Projects/conduit/conduit-extra {};
  conduitCombinatorsHEAD = cp /Users/johnw/Projects/conduit-combinators {};

  # The nixpkgs expression is too out-of-date to build with 7.8.2.
  hdevtools     = cp /Users/johnw/Projects/hdevtools {};
});

myDependencies = hsPkgs: [
    ledger
  ] ++ (with hsPkgs;
    pkgs.stdenv.lib.concatMap (self: self.propagatedUserEnvPkgs) [
      hdevtools

      bugs
      consistent
      findConduit
      gitAll
      hours
      loggingHEAD
      pushme
      simpleMirror
      theseHEAD
      tryhaskell

      gitlib
      #gitlibTest
      hlibgit2
      #gitlibLibgit2
      #gitMonitor

      shellyHEAD
      #shellyExtraHEAD
      lensHEAD
      #conduitHEAD
      #conduitExtraHEAD
      #conduitCombinatorsHEAD

      newartisans
    ]);

##############################################################################

haskellTools = ghcEnv: (([
    ghcEnv.ghc
    sloccount
    coq
  ]) ++ (with ghcEnv.hsPkgs; [
    #cabalBounds
    cabalInstall_1_20_0_1
    #codex
    ghcCore
    ghcMod
    hdevtools
    hlint
    (hoogleLocal ghcEnv)
  ]) ++ (with haskellPackages_ghc782; [
    hobbes
    simpleMirror
  ]) ++ (with haskellPackages_ghc763; [
    Agda AgdaStdlib
    cabal2nix
    hasktags
    #hsenv
    lambdabot djinn mueval
    threadscope
  ]));

buildToolsEnv = pkgs.buildEnv {
    name = "buildTools";
    paths = [
      ninja global gcc48 autoconf automake gnumake
    ];
  };

emacsToolsEnv = pkgs.buildEnv {
    name = "emacsTools";
    paths = [
      emacs aspell aspellDicts.en
    ];
  };

gitToolsEnv = pkgs.buildEnv {
    name = "gitTools";
    paths = [
      git diffutils patchutils bup dar

      pkgs.gitAndTools.gitAnnex
      pkgs.gitAndTools.hub
      pkgs.gitAndTools.topGit

      haskellPackages.gitAll
    ];
  };

systemToolsEnv = pkgs.buildEnv {
    name = "systemTools";
    paths = [
      findutils gnused gnutar httrack iperf mosh mtr multitail p7zip parallel
      gnupg pinentry pv rsync silver-searcher socat stow watch xz youtubeDL
      exiv2 gnuplot

      haskellPackages.pushme
      haskellPackages.sizes
      haskellPackages.una
    ];
  };

mailToolsEnv = pkgs.buildEnv {
    name = "mailTools";
    paths = [
      leafnode dovecot22 dovecot_pigeonhole fetchmail procmail w3m
    ];
  };

serviceToolsEnv = pkgs.buildEnv {
    name = "serviceTools";
    paths = [
      nginx postgresql redis pdnsd
    ];
  };

clangEnv = pkgs.myEnvFun {
    name = "clang";
    buildInputs = [ clang llvm ];
  };

appleEnv = pkgs.myEnvFun {
    name = "gccApple";
    buildInputs = [ gccApple ];
  };

##############################################################################

emacs = pkgs.emacs24Macport;

ghc = self.ghc // {
    ghcHEAD = pkgs.callPackage /Users/johnw/Projects/ghc {};
  };

hoogleLocal = ghcEnv: ghcEnv.hsPkgs.hoogleLocal.override {
    packages = myPackages ghcEnv;
  };

coq = self.coq.override { lablgtk = null; };

ghcTools = ghcEnv: pkgs.myEnvFun {
    name = ghcEnv.name;
    buildInputs = haskellTools ghcEnv
      ++ myPackages ghcEnv
      ++ myDependencies ghcEnv.hsPkgs;
  };

haskellPackages_ghc742 =
  let callPackage = self.lib.callPackageWith haskellPackages_ghc742;
  in self.recurseIntoAttrs (self.haskellPackages_ghc742.override {
      extension = myProjects callPackage;
    });

ghcEnv_742 = ghcTools {
    name   = "ghc742";
    ghc    = ghc.ghc742;
    hsPkgs = haskellPackages_ghc742;
  };

haskellPackages_ghc763 =
  let callPackage = self.lib.callPackageWith haskellPackages_ghc763;
  in self.recurseIntoAttrs (self.haskellPackages_ghc763.override {
      extension = myProjects callPackage;
    });

ghcEnv_763 = ghcTools {
    name   = "ghc763";
    ghc    = ghc.ghc763;
    hsPkgs = haskellPackages_ghc763;
  };

haskellPackages_ghc763_profiling =
  let callPackage = self.lib.callPackageWith haskellPackages_ghc763_profiling;
  in self.recurseIntoAttrs (self.haskellPackages_ghc763_profiling.override {
      extension = myProjects callPackage;
    });

ghcEnv_763_profiling = ghcTools {
    name   = "ghc763-prof";
    ghc    = ghc.ghc763;
    hsPkgs = haskellPackages_ghc763_profiling;
  };

haskellPackages_ghc782 =
  let callPackage = self.lib.callPackageWith haskellPackages_ghc782;
  in self.recurseIntoAttrs (self.haskellPackages_ghc782.override {
      extension = myProjects callPackage;
    });

ghcEnv_782 = ghcTools {
    name   = "ghc782";
    ghc    = ghc.ghc782;
    hsPkgs = haskellPackages_ghc782;
  };

haskellPackages_ghc782_profiling =
  let callPackage = self.lib.callPackageWith haskellPackages_ghc782_profiling;
  in self.recurseIntoAttrs (self.haskellPackages_ghc782_profiling.override {
      extension = myProjects callPackage;
    });

ghcEnv_782_profiling = ghcTools {
    name   = "ghc782-prof";
    ghc    = ghc.ghc782;
    hsPkgs = haskellPackages_ghc782_profiling;
  };

haskellPackages_ghcHEAD =
  let callPackage = self.lib.callPackageWith haskellPackages_ghcHEAD;
  in self.recurseIntoAttrs (self.haskellPackages_ghcHEAD.override {
      # jww (2014-05-12): What goes here?
      # ghcPath = /Users/johnw/Projects/ghc;
      extension = myProjects callPackage;
    });

ghcEnv_HEAD = ghcTools {
    name   = "ghcHEAD";
    ghc    = ghc.ghcHEAD;
    hsPkgs = haskellPackages_ghcHEAD;
  };

# haskellPackages_ghcHEAD_profiling =
#   let callPackage = self.lib.callPackageWith haskellPackages_ghcHEAD_profiling;
#   in self.recurseIntoAttrs (self.haskellPackages_ghcHEAD_profiling.override {
#       extension = myProjects callPackage;
#     });

# ghcEnv_HEAD_profiling = ghcTools {
#     name   = "ghcHEAD-prof";
#     ghc    = ghc.ghcHEAD;
#     hsPkgs = haskellPackages_ghcHEAD_profiling;
#   };

##############################################################################

myPackages = ghcEnv: with ghcEnv.hsPkgs; [
    Boolean
    CCdelcont
    HTTP
    HUnit
    IfElse
    MemoTrie
    MissingH
    MonadCatchIOTransformers
    QuickCheck
    abstractDeque
    abstractPar
    adjunctions
    aeson
    arithmoi
    async
    attempt
    attoparsec
    attoparsecConduit
    attoparsecEnumerator
    base16Bytestring
    base64Bytestring
    baseUnicodeSymbols
    basicPrelude
    bifunctors
    bindingsDSL
    blazeBuilder
    blazeBuilderConduit
    blazeBuilderEnumerator
    blazeHtml
    blazeMarkup
    blazeTextual
    byteable
    byteorder
    bytestringMmap
    caseInsensitive
    #categories
    cereal
    cerealConduit
    charset
    cheapskate
    chunkedData
    classyPrelude
    classyPreludeConduit
    cmdargs
    comonad
    comonadTransformers
    #compdata
    composition
    cond
    conduit
    conduitCombinators
    conduitExtra
    configurator
    contravariant
    convertible
    cpphs
    cssText
    dataDefault
    derive
    distributive
    dlist
    dlistInstances
    dns
    doctest
    doctestProp
    either
    #ekg
    enclosedExceptions
    errors
    esqueleto
    exceptions
    extensibleExceptions
    failure
    fastLogger
    fgl
    fileEmbed
    filepath
    fingertree
    free
    ghcPaths
    groups
    hamlet
    hashable
    hashtables
    haskeline
    haskellLexer
    haskellSrc
    haskellSrcExts
    haskellSrcMeta
    hfsevents
    hslogger
    hspec
    hspecExpectations
    html
    httpClient
    httpDate
    httpTypes
    json
    kanExtensions
    keys
    languageJava
    languageJavascript
    lens
    liftedAsync
    liftedBase
    linear
    listExtras
    mimeMail
    mimeTypes
    mmorph
    monadControl
    monadCoroutine
    monadLogger
    monadLoops
    monadPar
    monadParExtras
    monadStm
    monadloc
    monoidExtras
    mtl
    multimap
    network
    newtype
    numbers
    operational
    optparseApplicative
    parallel
    parallelIo
    parsec
    persistent
    persistentPostgresql
    persistentSqlite
    persistentTemplate
    pointed
    posixPaths
    prettyShow
    profunctors
    random
    #recursionSchemes
    reducers
    reflection
    regexApplicative
    regexBase
    regexCompat
    regexPosix
    resourcePool
    resourcet
    retry
    rex
    safe
    semigroupoids
    semigroups
    shake
    shakespeare
    shelly
    simpleReflect
    speculation
    split
    spoon
    stm
    stmChans
    stmConduit
    stmStats
    strict
    stringsearch
    systemFileio
    systemFilepath
    tagged
    tar
    temporary
    text
    these
    thyme
    time
    transformers
    transformersBase
    unixCompat
    unorderedContainers
    vector
    void
    wai
    warp
    xhtml
    xmlLens
    zlib
  ]

  ++ (if (ghcEnv.name == "ghc782-prof")
      then []
      else [ httpClientTls httpConduit ])
  ;

}; }
