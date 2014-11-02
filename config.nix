{ pkgs }: {

packageOverrides = self: with pkgs; rec {

emacs = pkgs.emacs24Macport_24_3;
emacs24Packages =
  recurseIntoAttrs (emacsPackages emacs24Macport_24_3 pkgs.emacs24Packages)
    // { proofgeneral = pkgs.emacs24Packages.proofgeneral_4_3_pre; };

ledger = self.callPackage /Users/johnw/Projects/ledger {};

haskellProjects = { self, super, callPackage }: rec {
  sizes         = callPackage /Users/johnw/Projects/sizes {};
  c2hsc         = callPackage /Users/johnw/Projects/c2hsc {};
  bugs          = callPackage /Users/johnw/Projects/bugs {};
  consistent    = callPackage /Users/johnw/Projects/consistent {};
  findConduit   = callPackage /Users/johnw/Projects/find-conduit {};
  asyncPool     = callPackage /Users/johnw/Projects/async-pool {};
  gitAll        = callPackage /Users/johnw/Projects/git-all {};
  hours         = callPackage /Users/johnw/Projects/hours {};
  loggingHEAD   = callPackage /Users/johnw/Projects/logging {};
  pushme        = callPackage /Users/johnw/Projects/pushme {};
  simpleMirror  = callPackage /Users/johnw/Projects/simple-mirror {};
  # theseHEAD     = callPackage /Users/johnw/Projects/these {};
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

  # rhubarb       = callPackage /Users/johnw/Projects/rhubarb {};

  newartisans   = callPackage /Users/johnw/Documents/newartisans {
    yuicompressor = pkgs.yuicompressor;
  };

  # shellyHEAD             = callPackage /Users/johnw/src/shelly {};
  # shellyExtraHEAD        = callPackage /Users/johnw/src/shelly/shelly-extra {};
  lensHEAD               = callPackage /Users/johnw/Contracts/OSS/Projects/lens {};
  machinesHEAD           = callPackage /Users/johnw/Contracts/OSS/Projects/machines {};
  exceptionsHEAD         = callPackage /Users/johnw/Contracts/OSS/Projects/exceptions {};

  ########## nixpkgs overrides ##########

  cabalNoLinks = self.cabal.override { enableHyperlinkSource = false; };
  disableLinks = x: x.override { cabal = self.cabalNoLinks; };

  hdevtools = callPackage /Users/johnw/Contracts/OSS/Projects/hdevtools {};
  ghcMod = callPackage /Users/johnw/Contracts/OSS/Projects/ghc-mod {
    emacs = pkgs.emacs24Macport_24_3;
  };

  systemFileio = self.disableTest  super.systemFileio;
  shake        = self.disableTest  super.shake;
  unlambda     = self.disableLinks super.unlambda;
};

##############################################################################

haskellTools = ghcEnv: ([
  ghcEnv.ghc
  sloccount
  emacs24Packages.idris
] ++ (with ghcEnv.hsPkgs; [
  cabalBounds
  cabalInstall_1_20_0_3
  ghcCore
  ghcMod
  hdevtools
  hlint
  (myHoogleLocal ghcEnv)
]) ++ (with haskellPackages_ghc783; [
  cabal2nix
  codex
  hobbes
  simpleMirror
  hakyll
  idris
]) ++ (with haskellPackages_ghc763; [
  #cabalMeta                     # jww: joelteon broken
  #hasktags                      # jww: joelteon broken
  #lambdabot                     # jww: joelteon broken
  #djinn mueval                  # jww: joelteon broken
  #threadscope                   # jww (2014-08-09): cairo is broken
]));

agdaEnv = pkgs.myEnvFun {
  name = "agda";
  buildInputs = [
    haskellPackages.Agda
    AgdaStdlib
    #haskellPackages.AgdaPrelude
  ];
};

buildToolsEnv = pkgs.buildEnv {
  name = "buildTools";
  paths = [
    ninja
    scons
    global
    autoconf automake
    bazaar bazaarTools
    ccache
    cvs cvsps
    darcs
    diffstat
    doxygen
    fcgi
    flex
    htmlTidy
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
      #bbdb                      # jww: joelteon broken
      coffee
      colorTheme
      cryptol
      cua
      emacsSessionManagement
      emacsw3m
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
      #structuredHaskellMode     # jww (2014-10-14): broken
      htmlize
      logito
      loremIpsum
      maudeMode
      pcache
      phpMode
      prologMode
      quack
      rectMark
      #remember                  # jww: joelteon broken
      rudel
      sbtMode
      sunriseCommander
      writeGood
      xmlRpc
    ]);
};

coqEnv = pkgs.myEnvFun {
  name = "coqHEAD";
  buildInputs = [ coq_HEAD ];
};

coqToolsEnv = pkgs.buildEnv {
  name = "coqTools";
  paths = [
    ocaml
    ocamlPackages.camlp5_transitional
    coq
    #coqPackages.bedrock
    # coqPackages.containers     # jww: tarball missing
    coqPackages.coqExtLib
    #coqPackages.domains         # jww: joelteon broken (fetchdarcs)
    coqPackages.flocq
    coqPackages.heq
    coqPackages.mathcomp
    coqPackages.paco
    coqPackages.ssreflect
    coqPackages.tlc
    coqPackages.ynot
    prooftree
    emacs24Packages.proofgeneral_4_3_pre
  ];
};

langToolsEnv = pkgs.buildEnv {
  name = "langTools";
  paths = [
    clang llvm boost
    ott isabelle
    gnumake
    compcert #verasco
    rust
    sbcl
    erlang
    swiProlog
    yuicompressor
  ];
 };

gameToolsEnv = pkgs.buildEnv {
    name = "gameTools";
    paths = [ chessdb craftyFull eboard gnugo ];
  };

gitToolsEnv = pkgs.buildEnv {
    name = "gitTools";
    paths = [
      diffutils patchutils
      # bup                       # jww: joelteon broken
      # dar                       # jww: joelteon broken

      pkgs.gitAndTools.gitAnnex
      # haskellPackages.gitGpush # jww (2014-10-14): broken
      haskellPackages.gitMonitor
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

    cabextract
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
    #unarj                       # jww: joelteon broken (no gcc)
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
    arcanist
    cacert
    fping
    httrack
    #iperf                       # jww: joelteon broken
    mosh
    mtr
    openssl
    rsync
    s3cmd
    socat2pre
    spiped
    # wget
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
  paths = [ texLiveFull djvu2pdf ghostscript librsvg ];
};

serviceToolsEnv = pkgs.buildEnv {
  name = "serviceTools";
  paths = [ nginx postgresql redis pdnsd mysql55 nodejs ];
};

perlToolsEnv = pkgs.buildEnv {
  name = "perlTools";
  paths = [ perl ];
};

pythonToolsEnv = pkgs.buildEnv {
  name = "pythonTools";
  paths = [
    python27Full
    pythonDocs.pdf_letter.python27
    pythonDocs.html.python27
  ];
};

rubyToolsEnv = pkgs.buildEnv {
  name = "rubyTools";
  paths = [ ruby_2_1_2 ];
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
  dataFin
  dataFix
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
  HStringTemplate
  html
  httpClient
  httpDate
  httpTypes
  ioMemoize
  ioStorage
  json
  keys
  languageC
  languageJava
  languageJavascript
  liftedAsync
  liftedBase
  listExtras
  logging
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
  multirec
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

  pipes
  # pipesAeson
  # pipesAttoparsec
  # pipesBinary
  # pipesBytestring
  # pipesConcurrency
  # pipesCsv
  # pipesGroup
  # pipesHttp
  # pipesNetwork
  # pipesParse
  # pipesPostgresqlSimple
  # pipesSafe
  # pipesText
  # pipesZlib

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
  regular
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
     [ trifecta
       parsers
       compdata
       singletons
       units
       criterion
       kanExtensions
     ]

++ pkgs.stdenv.lib.optionals
     (pkgs.stdenv.lib.versionOlder "7.5" ghcEnv.ghc.version)
     # Packages that only work in 7.6+
     [ folds
       linear
       lens
     ]

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
     [ recursionSchemes
     ]

++ pkgs.stdenv.lib.optionals
     (ghcEnv.name != "ghc783-prof" && ghcEnv.name != "ghc742")
     # Packages that do not work in specific versions
     [ httpClientTls
       httpConduit
       yesod
     ]
;

};

allowUnfree = true;
allowBroken = true;

}
