{ pkgs }: {

packageOverrides = self: with pkgs; rec {

emacs = pkgs.emacs24Macport;
emacs24Packages = recurseIntoAttrs (emacsPackages emacs24Macport pkgs.emacs24Packages);

ledger = self.callPackage /Users/johnw/Projects/ledger {};

haskellProjects = { self, super, callPackage }: rec {
  c2hsc         = callPackage /Users/johnw/Projects/c2hsc {};
  bugs          = callPackage /Users/johnw/Projects/bugs {};
  consistent    = callPackage /Users/johnw/Projects/consistent {};
  findConduit   = callPackage /Users/johnw/Projects/find-conduit {};
  taskPool      = callPackage /Users/johnw/Projects/taskpool {};
  gitAll        = callPackage /Users/johnw/Projects/git-all {};
  hours         = callPackage /Users/johnw/Projects/hours {};
  loggingHEAD   = callPackage /Users/johnw/Projects/logging {};
  pushme        = callPackage /Users/johnw/Projects/pushme {};
  simpleMirror  = callPackage /Users/johnw/Projects/simple-mirror {};
  theseHEAD     = callPackage /Users/johnw/Projects/these {};
  simpleConduitHEAD = callPackage /Users/johnw/Projects/simple-conduit {};
  HsToGallinaHEAD = callPackage /Users/johnw/Contracts/OSS/Projects/hs-to-gallina {
    uuagc = pkgs.haskellPackages_ghc763.uuagc.override {
      haskellSrcExts = pkgs.haskellPackages_ghc763.haskellSrcExts_1_13_5;
    };
    haskellSrcExts = pkgs.haskellPackages_ghc763.haskellSrcExts_1_13_5;
  };
  fuzzcheck     = callPackage /Users/johnw/Projects/fuzzcheck {};
  hnix          = callPackage /Users/johnw/Projects/hnix {};
  commodities   = callPackage /Users/johnw/Projects/ledger/new/commodities {};

  gitlib        = callPackage /Users/johnw/Projects/gitlib/gitlib {};
  gitlibTest    = callPackage /Users/johnw/Projects/gitlib/gitlib-test {};
  hlibgit2      = callPackage /Users/johnw/Projects/gitlib/hlibgit2 {};
  gitlibLibgit2 = callPackage /Users/johnw/Projects/gitlib/gitlib-libgit2 {};
  gitMonitor    = callPackage /Users/johnw/Projects/gitlib/git-monitor {};
  gitGpush      = callPackage /Users/johnw/Projects/gitlib/git-gpush {};
  gitlibCmdline = callPackage /Users/johnw/Projects/gitlib/gitlib-cmdline {
    git = gitAndTools.git;
  };
  gitlibCross   = callPackage /Users/johnw/Projects/gitlib/gitlib-cross {
    git = gitAndTools.git;
  };
  gitlibHit     = callPackage /Users/johnw/Projects/gitlib/gitlib-hit {};
  gitlibLens    = callPackage /Users/johnw/Projects/gitlib/gitlib-lens {};
  gitlibS3      = callPackage /Users/johnw/Projects/gitlib/gitlib-S3 {};
  gitlibSample  = callPackage /Users/johnw/Projects/gitlib/gitlib-sample {};

  rhubarb       = callPackage /Users/johnw/Projects/rhubarb {};
  AgdaPrelude   = callPackage /Users/johnw/Projects/agda-prelude {};

  newartisans   = callPackage /Users/johnw/Documents/newartisans {
    yuicompressor = pkgs.yuicompressor;
  };

  foldlHEAD              = callPackage /Users/johnw/Contracts/OSS/Projects/Haskell-Foldl-Library {};
  shellyHEAD             = callPackage /Users/johnw/src/shelly {};
  shellyExtraHEAD        = callPackage /Users/johnw/src/shelly/shelly-extra {};
  lensHEAD               = callPackage /Users/johnw/Contracts/OSS/Projects/lens {};
  machinesHEAD           = callPackage /Users/johnw/Contracts/OSS/Projects/machines {};
  exceptionsHEAD         = callPackage /Users/johnw/Contracts/OSS/Projects/exceptions {};
  conduitHEAD            = callPackage /Users/johnw/Contracts/OSS/Projects/conduit/conduit {};
  conduitExtraHEAD       = callPackage /Users/johnw/Contracts/OSS/Projects/conduit/conduit-extra {};
  conduitCombinatorsHEAD = callPackage /Users/johnw/Contracts/OSS/Projects/conduit-combinators {};

  ########## nixpkgs overrides ##########

  cabalNoLinks = self.cabal.override { enableHyperlinkSource = false; };
  disableLinks = x: x.override { cabal = self.cabalNoLinks; };

  # This expression is too out-of-date to build with 7.8.x.
  hdevtools = callPackage /Users/johnw/Contracts/OSS/Projects/hdevtools {};
  ghcMod = callPackage /Users/johnw/Contracts/OSS/Projects/ghc-mod {
    emacs = pkgs.emacs24Macport;
  };

  systemFileio = self.disableTest  super.systemFileio;
  shake        = self.disableTest  super.shake;
  unlambda     = self.disableLinks super.unlambda;

  # cabal = super.cabal.override {
  #   mkDerivation = args : (super.cabal.mkDerivation args).override {
  #     defaults = x: (super.cabal.defaults x).override {
  #       src = fetchurl {
  #         urls = [
  #           "file:///Volumes/Hackage/package/${x.fname}.tar.gz"
  #           "http://hackage.haskell.org/packages/archive/${x.pname}/${x.version}/${x.fname}.tar.gz"
  #           "http://hdiff.luite.com/packages/archive/${x.pname}/${x.fname}.tar.gz"
  #         ];
  #         inherit (x) sha256;
  #       };
  #     };
  #   };
  # };
};

##############################################################################

haskellTools = ghcEnv: ([
    ghcEnv.ghc
    sloccount
    emacs24Packages.idris
  ] ++ (with ghcEnv.hsPkgs; [
    #cabalBounds
    cabalInstall_1_20_0_3
    ghcCore
    ghcMod
    hdevtools
    hlint
    (myHoogleLocal ghcEnv)
  ]) ++ (with haskellPackages_ghc783; [
    codex
    hobbes
    simpleMirror
    cabalDb
    Agda AgdaStdlib #AgdaPrelude
    idris
  ]) ++ (with haskellPackages_ghc763; [
    cabal2nix
    #cabalDev
    cabalMeta
    hasktags
    #hsenv
    lambdabot djinn mueval
    threadscope
  ]));

agdaEnv = pkgs.myEnvFun {
  name = "agda";
  buildInputs = [
    haskellPackages.Agda
    haskellPackages.AgdaStdlib
    #haskellPackages.AgdaPrelude
  ];
};

buildToolsEnv = pkgs.myEnvFun {
  name = "buildTools";
  buildInputs = [
    ninja global autoconf automake
    bazaar bazaarTools
    ccache gcc gccApple
    cvs cvsps
    darcs
    diffstat
    doxygen
    fcgi
    flex
    gdb
    htmlTidy
    jenkins
    lcov
    mercurial
    patch
    subversion
  ];
};

emacsToolsEnv = pkgs.buildEnv {
  name = "emacsTools";
  paths = [ emacs aspell aspellDicts.en ] ++
    (with self.emacs24Packages; [
      autoComplete
      bbdb
      coffee
      colorTheme
      cryptol
      cua
      darcsum
      #emacsClangCompleteAsync
      emacsSessionManagement
      emacsw3m
      #emms
      ess
      flymakeCursor
      gh
      graphvizDot
      gist
      jade
      js2
      stratego
      haskellMode
      ocamlMode
      structuredHaskellMode
      hol_light_mode
      htmlize
      logito
      loremIpsum
      #magit
      maudeMode
      # org
      # org2blog
      pcache
      phpMode
      prologMode
      quack
      rectMark
      remember
      rudel
      sbtMode
      sunriseCommander
      writeGood
      xmlRpc
    ]);
};

langToolsEnv = pkgs.buildEnv {
  name = "langTools";
  paths = [
    clang llvm boost
    #coq prooftree emacs24Packages.proofgeneral_4_3_pre
    coq_HEAD prooftree emacs24Packages.proofgeneral_4_3_pre
    gnumake
    compcert
    rust
    sbcl
    erlang
    swiProlog
    pythonDocs.pdf_letter.python27 pythonDocs.html.python27
    yuicompressor
  ];
 };

gameToolsEnv = pkgs.buildEnv {
    name = "gameTools";
    paths = [
      chessdb craftyFull eboard gnugo
    ];
  };

gitToolsEnv = pkgs.buildEnv {
    name = "gitTools";
    paths = [
      diffutils patchutils bup dar

      pkgs.gitAndTools.gitAnnex
      haskellPackages.gitGpush
      haskellPackages.gitMonitor
      haskellPackages.githubBackup
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
      haskellPackages_ghc763.sizes
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
      watchman
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
      socat2pre
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

publishToolsEnv = pkgs.buildEnv {
    name = "publishTools";
    paths = [
      texLiveFull djvu2pdf ghostscript librsvg
    ];
  };

serviceToolsEnv = pkgs.buildEnv {
    name = "serviceTools";
    paths = [
      nginx postgresql redis pdnsd mysql55 nodejs
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

##############################################################################

ghc = self.ghc // {
    ghcHEAD = pkgs.callPackage /Users/johnw/Contracts/OSS/Projects/ghc {};
  };

myHoogleLocal = ghcEnv: ghcEnv.hsPkgs.hoogleLocal.override {
    packages = myPackages ghcEnv;
  };

ghcTools = ghcEnv: pkgs.myEnvFun {
    name = ghcEnv.name;
    buildInputs = haskellTools ghcEnv ++ myPackages ghcEnv;
  };

haskellPackages_wrapper = hp: self.recurseIntoAttrs (hp.override {
    extension = this: super: haskellProjects {
      self = this;
      super = super;
      callPackage = self.lib.callPackageWith this;
    };
  });

haskellPackages_ghc742 = haskellPackages_wrapper self.haskellPackages_ghc742;

ghcEnv_742 = ghcTools {
    name   = "ghc742";
    ghc    = ghc.ghc742;
    hsPkgs = haskellPackages_ghc742;
  };

haskellPackages_ghc763 = haskellPackages_wrapper self.haskellPackages_ghc763;
haskellPackages_ghc763_profiling =
  haskellPackages_wrapper (recurseIntoAttrs haskell.packages_ghc763.profiling);

ghcEnv_763 = ghcTools {
    name   = "ghc763";
    ghc    = ghc.ghc763;
    hsPkgs = haskellPackages_ghc763;
  };
ghcEnv_763_profiling = ghcTools {
    name   = "ghc763-prof";
    ghc    = ghc.ghc763;
    hsPkgs = haskellPackages_ghc763_profiling;
  };

haskellPackages_ghc783 =
  haskellPackages_wrapper (recurseIntoAttrs haskell.packages_ghc783.noProfiling);
haskellPackages_ghc783_profiling =
  haskellPackages_wrapper (recurseIntoAttrs haskell.packages_ghc783.profiling);

ghcEnv_783 = ghcTools {
    name   = "ghc783";
    ghc    = ghc.ghc783;
    hsPkgs = haskellPackages_ghc783;
  };
ghcEnv_783_profiling = ghcTools {
    name   = "ghc783-prof";
    ghc    = ghc.ghc783;
    hsPkgs = haskellPackages_ghc783_profiling;
  };

# We can't add our entire package set for GHC HEAD, there are always too many
# that don't build yet.
haskellPackages_ghcHEAD = haskell.packages_ghcHEAD.noProfiling;
haskellPackages_ghcHEAD_profiling = haskell.packages_ghcHEAD.profiling;

ghcEnv_HEAD = pkgs.myEnvFun {
    name = "ghcHEAD";
    buildInputs = with haskellPackages_ghcHEAD; [
      pkgs.ghc.ghcHEAD cabalInstall_1_20_0_3
    ];
  };

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
    boolExtras
    byteable
    byteorder
    bytes
    bytestringMmap
    caseInsensitive
    cassava
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
    composition
    compressed
    cond
    conduit
    conduitCombinators
    conduitExtra
    configurator
    constraints
    contravariant
    convertible
    cpphs
    cryptohash
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
    extensibleExceptions
    failure
    fastLogger
    fileEmbed
    filepath
    fingertree
    fmlist
    foldl
    free
    #freeOperational
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
    ioMemoize
    ioStorage
    json
    keys
    languageJava
    languageJavascript
    liftedAsync
    liftedBase
    listExtras
    logict
    machines
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
    yaml
    zippers
    zlib
  ]

  ++ pkgs.stdenv.lib.optionals
       (pkgs.stdenv.lib.versionOlder "7.7" ghcEnv.ghc.version)
       # Packages that only work in 7.8+
       [ compdata singletons criterion kanExtensions ]

  ++ pkgs.stdenv.lib.optionals
       (pkgs.stdenv.lib.versionOlder "7.5" ghcEnv.ghc.version)
       # Packages that only work in 7.6+
       [ folds linear lens xmlLens trifecta parsers ]

  ++ pkgs.stdenv.lib.optionals 
       (pkgs.stdenv.lib.versionOlder ghcEnv.ghc.version "7.9")
       # Packages that do not work in 7.10+
       [ stringsearch
         exceptions
         arithmoi
         fgl
       ]

  ++ pkgs.stdenv.lib.optionals 
       (pkgs.stdenv.lib.versionOlder ghcEnv.ghc.version "7.7")
       # Packages that do not work in 7.8+
       [ recursionSchemes ]

  ++ pkgs.stdenv.lib.optionals
       (ghcEnv.name != "ghc783-prof" && ghcEnv.name != "ghc742")
       # Packages that do not work in specific versions
       [ httpClientTls httpConduit yesod ]
  ;

}; 

allowUnfree = true;

}
