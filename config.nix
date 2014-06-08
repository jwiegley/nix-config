{ pkgs }: {

packageOverrides = self: with pkgs; rec {

emacs  = pkgs.emacs24Macport;
ledger = self.callPackage /Users/johnw/Projects/ledger {};

myProjects = cp: (self: super: {
  c2hsc         = cp /Users/johnw/Projects/c2hsc {};
  bugs          = cp /Users/johnw/Projects/bugs {};
  consistent    = cp /Users/johnw/Projects/consistent {};
  findConduit   = cp /Users/johnw/Projects/find-conduit {};
  gitAll        = cp /Users/johnw/Projects/git-all {};
  hours         = cp /Users/johnw/Projects/hours {};
  loggingHEAD   = cp /Users/johnw/Projects/logging {};
  pushme        = cp /Users/johnw/Projects/pushme {};
  simpleMirror  = cp /Users/johnw/Projects/simple-mirror {};
  theseHEAD     = cp /Users/johnw/Projects/these {};
  simpleConduit = cp /Users/johnw/Projects/simple-conduit {};
  fuzzcheck     = cp /Users/johnw/Projects/fuzzcheck {};

  gitlib        = cp /Users/johnw/Projects/gitlib/gitlib {};
  gitlibTest    = cp /Users/johnw/Projects/gitlib/gitlib-test {};
  hlibgit2      = cp /Users/johnw/Projects/gitlib/hlibgit2 {};
  gitlibLibgit2 = cp /Users/johnw/Projects/gitlib/gitlib-libgit2 {};
  gitMonitor    = cp /Users/johnw/Projects/gitlib/git-monitor {};

  newartisans   = cp /Users/johnw/src/newartisans {
    yuicompressor = pkgs.yuicompressor;
  };

  shellyHEAD             = cp /Users/johnw/src/shelly {};
  shellyExtraHEAD        = cp /Users/johnw/src/shelly/shelly-extra {};
  lensHEAD               = cp /Users/johnw/src/lens {};
  machinesHEAD           = cp /Users/johnw/src/machines {};
  exceptionsHEAD         = cp /Users/johnw/Projects/exceptions {};
  conduitHEAD            = cp /Users/johnw/Projects/conduit/conduit {};
  conduitExtraHEAD       = cp /Users/johnw/Projects/conduit/conduit-extra {};
  conduitCombinatorsHEAD = cp /Users/johnw/Projects/conduit-combinators {};

  # The nixpkgs expression is too out-of-date to build with 7.8.2.
  hdevtools = cp /Users/johnw/Projects/hdevtools {};
});

myDependencies = hsPkgs: with hsPkgs;
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
  ];

##############################################################################

haskellTools = ghcEnv: (([
    ghcEnv.ghc
    sloccount
    coq prooftree
  ]) ++ (with ghcEnv.hsPkgs; [
    #cabalBounds
    cabalInstall_1_20_0_2
    #codex
    ghcCore
    ghcMod
    hdevtools
    hlint
    (myHoogleLocal ghcEnv)
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

buildToolsEnv = pkgs.myEnvFun {
    name = "buildTools";
    buildInputs = [
      ninja global autoconf automake gnumake
      boost
      ccache
      cvs
      cvsps
      darcs
      diffstat
      doxygen
      erlang
      fcgi
      flex
      gdb
      htmlTidy
      jenkins
      lcov
      mercurial
      patch
      subversion
      swiProlog
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
      diffutils patchutils bup dar

      pkgs.gitAndTools.gitAnnex
      pkgs.gitAndTools.gitFull
      pkgs.gitAndTools.gitflow
      pkgs.gitAndTools.hub
      pkgs.gitAndTools.topGit

      haskellPackages.gitAll
    ];
  };

systemToolsEnv = pkgs.buildEnv {
    name = "systemTools";
    paths = [
      haskellPackages.pushme
      haskellPackages.sizes
      haskellPackages.una

      bashInteractive
      bashCompletion
      exiv2
      expect
      figlet
      findutils
      gnugrep
      gnupg
      gnuplot
      gnused
      gnutar
      graphviz
      guile
      imagemagick
      less
      macvim
      multitail
      p7zip
      parallel
      pinentry
      pv
      recutils
      rlwrap
      screen
      silver-searcher
      sqlite
      stow
      time
      tmux
      tree
      unarj
      unrar
      unzip
      watch
      xz
      zip
    ];
  };

networkToolsEnv = pkgs.buildEnv {
    name = "networkTools";
    paths = [
      cacert
      fping
      httrack
      iperf
      mosh
      mtr
      #openssh
      openssl
      rsync
      s3cmd
      socat
      spiped
      wget
      youtubeDL
    ];
  };

mailToolsEnv = pkgs.buildEnv {
    name = "mailTools";
    paths = [
      leafnode dovecot22 dovecot_pigeonhole fetchmail procmail w3m
      mairix
      mutt
    ];
  };

serviceToolsEnv = pkgs.buildEnv {
    name = "serviceTools";
    paths = [
      nginx postgresql redis pdnsd mysql55
    ];
  };

perlToolsEnv = pkgs.buildEnv {
    name = "perlTools";
    paths = [
      perl
    ];
  };

pythonToolsEnv = pkgs.buildEnv {
    name = "pythonTools";
    paths = [
      python27Full #python32
    ];
  };

rubyToolsEnv = pkgs.buildEnv {
    name = "rubyTools";
    paths = [
      ruby2 #ruby
    ];
  };

lispToolsEnv = pkgs.buildEnv {
    name = "lispTools";
    paths = [
      sbcl
    ];
  };

clangEnv = pkgs.myEnvFun {
    name = "clang";
    buildInputs = [ clang llvm ];
  };

gccEnv = pkgs.myEnvFun {
    name = "gcc";
    buildInputs = [ gcc gfortran ];
  };

appleEnv = pkgs.myEnvFun {
    name = "gccApple";
    buildInputs = [ gccApple ];
  };

##############################################################################

ghc = self.ghc // {
    ghcHEAD = pkgs.callPackage /Users/johnw/Projects/ghc {};
  };

myHoogleLocal = ghcEnv: ghcEnv.hsPkgs.hoogleLocal.override {
    packages = myPackages ghcEnv;
  };

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
    BlogLiterately
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
    boolExtras
    byteable
    byteorder
    bytes
    bytestringMmap
    caseInsensitive
    cassava
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
    composition
    compressed
    cond
    conduit
    conduitCombinators
    conduitExtra
    configurator
    contravariant
    convertible
    cpphs
    cssText
    dataChecked
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
    foldl
    free
    ghcPaths
    groups
    hakyll
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
    ioStorage
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
    monoTraversable
    mtl
    multimap
    network
    newtype
    numbers
    operational
    optparseApplicative
    pandoc
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
    textFormat
    these
    thyme
    time
    transformers
    transformersBase
    #units
    unixCompat
    unorderedContainers
    vector
    void
    wai
    warp
    xhtml
    xmlLens
    yaml
    zlib
  ]

  ++ pkgs.stdenv.lib.optionals
       (pkgs.stdenv.lib.versionOlder "7.7" ghcEnv.ghc.version)
       [ compdata singletons criterion ]

  ++ pkgs.stdenv.lib.optionals 
       (pkgs.stdenv.lib.versionOlder ghcEnv.ghc.version "7.7")
       [ recursionSchemes ]

  ++ pkgs.stdenv.lib.optionals
       (ghcEnv.name != "ghc782-prof" && ghcEnv.name != "ghc742")
       [ httpClientTls httpConduit yesod ]
  ;

}; 

allowUnfree = true;

}
