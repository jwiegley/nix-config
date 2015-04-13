# buildTools
# cabal2nix-1.73
# coqTools
# coreutils-8.23
# emacsTools
# env-agda
# env-coqHEAD
# env-ghc784
# gitTools
# langTools
# ledger-3.1.0.20141005
# mailTools
# networkTools
# nix-1.9pre4028_0d1dafa
# nix-prefetch-scripts
# nix-repl-1.8-f924081
# perlTools
# publishTools
# pythonTools
# rubyTools
# serviceTools
# systemTools
# xquartz

{ pkgs }: {

packageOverrides = super: with pkgs; rec {

# Used "super" and "pkgs" in a fashion consistent with
# https://github.com/jwiegley/nix-config/blob/master/config.nix
youtube-dl = super.stdenv.lib.overrideDerivation super.youtube-dl (attrs: {
  ffmpeg = null;
  postInstall = "";
});

idutils = super.stdenv.lib.overrideDerivation super.idutils (attrs: {
  doCheck = false;
});

emacs = if super.stdenv.isDarwin
        then super.emacs24Macport_24_5
        else super.emacs;

emacs24Packages =
  recurseIntoAttrs super.emacs24Packages
    // { proofgeneral = pkgs.emacs24Packages.proofgeneral_4_3_pre;
         emacs = pkgs.emacs; };

ledger = super.callPackage /Users/johnw/Projects/ledger {};

haskellProjects = { self, super, callPackage }: rec {
  sizes         = callPackage /Users/johnw/Projects/sizes {};
  c2hsc         = callPackage /Users/johnw/Projects/c2hsc {};
  consistent    = callPackage /Users/johnw/Projects/consistent {};
  findConduit   = callPackage /Users/johnw/Projects/find-conduit {};
  asyncPool     = callPackage /Users/johnw/Projects/async-pool {};
  gitAll        = callPackage /Users/johnw/Projects/git-all {};
  hours         = callPackage /Users/johnw/Projects/hours {};
  loggingHEAD   = callPackage /Users/johnw/Projects/logging {};
  pushme        = callPackage /Users/johnw/Projects/pushme {};
  simpleMirror  = callPackage /Users/johnw/Projects/simple-mirror {};
  simpleConduitHEAD = callPackage /Users/johnw/Projects/simple-conduit {};
  fuzzcheck     = callPackage /Users/johnw/Projects/fuzzcheck {};
  hnix          = callPackage /Users/johnw/Projects/hnix {};
  commodities   = callPackage /Users/johnw/Projects/ledger/new/commodities {};
  linearscan    = callPackage /Users/johnw/Contracts/BAE/Projects/linearscan {};

  # gitlib        = callPackage /Users/johnw/Projects/gitlib/gitlib {};
  # gitlibTest    = callPackage /Users/johnw/Projects/gitlib/gitlib-test {};
  # hlibgit2      = callPackage /Users/johnw/Projects/gitlib/hlibgit2 {};
  # gitlibLibgit2 = callPackage /Users/johnw/Projects/gitlib/gitlib-libgit2 {};
  # gitMonitor    = callPackage /Users/johnw/Projects/gitlib/git-monitor {};
  # gitGpush      = callPackage /Users/johnw/Projects/gitlib/git-gpush {};
  # gitlibCmdline = callPackage /Users/johnw/Projects/gitlib/gitlib-cmdline {
  #   git = gitAndTools.git;
  # };
  # gitlibCross   = callPackage /Users/johnw/Projects/gitlib/gitlib-cross {
  #   git = gitAndTools.git;
  # };
  # gitlibHit     = callPackage /Users/johnw/Projects/gitlib/gitlib-hit {};
  # gitlibLens    = callPackage /Users/johnw/Projects/gitlib/gitlib-lens {};
  # gitlibS3      = callPackage /Users/johnw/Projects/gitlib/gitlib-S3 {};
  # gitlibSample  = callPackage /Users/johnw/Projects/gitlib/gitlib-sample {};

  newartisans   = callPackage /Users/johnw/Documents/newartisans {
    yuicompressor = pkgs.yuicompressor;
  };

  hdevtools    = callPackage /Users/johnw/Contracts/OSS/Projects/hdevtools {};

  ########## nixpkgs overrides ##########

  cabalNoLinks = self.cabal.override { enableHyperlinkSource = false; };
  disableLinks = x: x.override { cabal = self.cabalNoLinks; };
  systemFileio = self.disableTest  super.systemFileio;
  shake        = self.disableTest  super.shake;
  unlambda     = self.disableLinks super.unlambda;
};

##############################################################################

haskellTools = ghcEnv: ([
  ghcEnv.ghc
  sloccount
  emacs24Packages.idris
# ] ++ (with ghcEnv.hs-pkgs; [
#   (my-hoogle-local ghcEnv)
] ++ (with ghcEnv.hsPkgs; [
  cabalBounds
  cabalInstall
  ghcCore
  ghcMod
  hdevtools
  hlint
  ihaskell
  (myHoogleLocal ghcEnv)
]) ++ (with haskellPackages_ghc784; [
  cabal2nix
  codex
  hobbes
  simpleMirror
  hasktags
  cabalMeta
  djinn mueval
  idris
  threadscope
  timeplot splot
  liquidhaskell cvc4
]) ++ (with haskellngPackages; [
  hakyll
]) ++ (with haskell-ng.packages.ghc763; [
  # lambdabot
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
    global idutils
    autoconf automake114x
    bazaar bazaarTools
    ccache
    cvs cvsps
    darcs
    diffstat
    doxygen
    # haskellPackages.newartisans
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
    (with emacs24Packages; [
      auctex
    ]);
};

coqEnv = pkgs.myEnvFun {
  name = "coqHEAD";
  buildInputs = [ coq_HEAD ];
};

coq85Env = pkgs.myEnvFun {
  name = "coq85";
  buildInputs = [
    coq_8_5beta1
    coqPackages.mathcomp_1_5_for_8_5beta1
    coqPackages.ssreflect_1_5_for_8_5beta1
  ];
};

coqToolsEnv = pkgs.buildEnv {
  name = "coqTools";
  paths = [
    ocaml
    ocamlPackages.camlp5_transitional
    coq
    coqPackages.bedrock
    #coqPackages.containers
    #coqPackages.coqExtLib
    coqPackages.coqeal
    coqPackages.domains
    coqPackages.fiat
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
    # fsharp
    #rustc                # jww (2015-02-01): now needs procps?
    sbcl acl2
    # erlang
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
      #bup                       # jww: joelteon broken
      dar

      pkgs.haskellngPackages.git-annex
      # haskellPackages.gitGpush # jww (2014-10-14): broken
      pkgs.haskellngPackages.git-monitor
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
    haskellngPackages.sizes
    haskellngPackages.una

    ack
    #apg                                # jww (2015-03-09): needs gcc
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
    haskellPackages.hours
    imagemagick_light
    less
    macvim
    multitail
    nixbang
    p7zip
    haskellngPackages.pandoc
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
    #unarj
    unrar
    unzip
    watch
    watchman
    xz
    z3
    zip
    zsh
  ];
};

networkToolsEnv = pkgs.buildEnv {
  name = "networkTools";
  paths = [
    # arcanist
    aria
    cacert
    fping
    httrack
    iperf
    mosh
    mtr
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
    mairix mutt msmtp lbdb contacts spamassassin
  ];
};

publishToolsEnv = pkgs.buildEnv {
  name = "publishTools";
  paths = [ 
    texLiveFull
    # djvu2pdf                                # jww (2015-03-29): broken
    ghostscript
    # librsvg                                 # jww (2015-03-29): broken
    poppler poppler_data
    libpng
  ];
};

serviceToolsEnv = pkgs.buildEnv {
  name = "serviceTools";
  paths = [
    nginx
    postgresql
    redis
    pdnsd
    # mysql
    nodejs
  ];
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
    python27Packages.ipython
    python27Packages.pygments
  ];
};

rubyToolsEnv = pkgs.buildEnv {
  name = "rubyTools";
  paths = [ ruby_2_1_2 ];
};

##############################################################################

# ghc = self.ghc // {
#   ghcHEAD = pkgs.callPackage /Users/johnw/Contracts/OSS/Projects/ghc {};
# };

myHoogleLocal = ghcEnv: ghcEnv.hsPkgs.hoogleLocal.override {
  packages = myPackages ghcEnv;
};

# my-hoogle-local = ghcEnv: ghcEnv.hs-pkgs.hoogle-local.override {
#   packages = my-packages ghcEnv;
# };

ghcTools = ghcEnv: pkgs.myEnvFun {
  name = ghcEnv.name;
  buildInputs = haskellTools ghcEnv ++ myPackages ghcEnv;
};

haskellPackages_wrapper = hp: super.recurseIntoAttrs (hp.override {
  extension = this: sup: haskellProjects {
    self = this;
    super = sup;
    callPackage = super.lib.callPackageWith this;
  };
});

haskellPackages_ghc742 = haskellPackages_wrapper super.haskellPackages_ghc742;

ghcEnv_742 = ghcTools {
  name    = "ghc742";
  ghc     = ghc.ghc742;
  hsPkgs  = haskellPackages_ghc742;
  # hs-pkgs = haskell-ng.packages.ghc742;
};

# package.overrideScope (self: super: { mkDerivation = expr:
#   super.mkDerivation (expr // { enableLibraryProfiling = true; }); })
# if you want to do all of them, it's packages.ghcVer.override {
#   overrides = self: super: { mkDerivation = ...; }; }

haskellPackages_ghc763 = haskellPackages_wrapper super.haskellPackages_ghc763;
haskellPackages_ghc763_profiling =
  haskellPackages_wrapper (recurseIntoAttrs haskell.packages_ghc763.profiling);

ghcEnv_763 = ghcTools {
  name    = "ghc763";
  ghc     = ghc.ghc763;
  hsPkgs  = haskellPackages_ghc763;
  # hs-pkgs = haskell-ng.packages.ghc763;
};
ghcEnv_763_profiling = ghcTools {
  name    = "ghc763-prof";
  ghc     = ghc.ghc763;
  hsPkgs  = haskellPackages_ghc763_profiling;
  # hs-pkgs = haskell-ng.packages.ghc763.profiling;
};

haskellPackages_ghc784 =
  haskellPackages_wrapper (recurseIntoAttrs haskell.packages_ghc784.noProfiling);
haskellPackages_ghc784_profiling =
  haskellPackages_wrapper (recurseIntoAttrs haskell.packages_ghc784.profiling);

ghcEnv_784 = ghcTools {
  name    = "ghc784";
  ghc     = ghc.ghc784;
  hsPkgs  = haskellPackages_ghc784;
  # hs-pkgs = haskell-ng.packages.ghc784;
};
ghcEnv_784_profiling = ghcTools {
  name    = "ghc784-prof";
  ghc     = ghc.ghc784;
  hsPkgs  = haskellPackages_ghc784_profiling;
  # hs-pkgs = haskell-ng.packages.ghc784.profiling;
};

# We can't add our entire package set for GHC HEAD, there are always too many
# that don't build yet.
#haskellPackages_ghcHEAD = haskell.packages_ghcHEAD.noProfiling;
#haskellPackages_ghcHEAD_profiling = haskell.packages_ghcHEAD.profiling;

#ghcEnv_HEAD = pkgs.myEnvFun {
#  name = "ghcHEAD";
#  buildInputs = with haskellPackages_ghcHEAD; [
#    pkgs.ghc.ghcHEAD cabalInstall_1_20_0_3
#  ];
#};

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
  enclosedExceptions
  errors
  exceptions
  extensibleExceptions
  failure
  fastLogger
  fileEmbed
  filepath
  fingertree
  # fixplate
  fmlist
  foldl
  free
  fsnotify
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
  hoopl
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
  lattices
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
  # orgmodeParse
  pandoc
  parallel
  parallelIo
  parsec

  pipes
  pipesAttoparsec
  pipesBinary
  pipesBytestring
  pipesConcurrency
  pipesGroup
  pipesHttp
  pipesNetwork
  pipesParse
  pipesSafe
  pipesText

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
  resourcet
  retry
  rex
  safe
  sbv
  scotty
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
  stmStats
  strict
  strptime
  syb
  systemFileio
  systemFilepath
  tagged
  tar
  tasty
  tastyHunit
  tastySmallcheck
  tastyQuickcheck
  temporary
  text
  textFormat
  these
  thyme
  time
  timeparsers
  timeRecurrence
  transformers
  transformersBase
  unixCompat
  uniplate
  unorderedContainers
  uuid
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
       pipesShell
       tastyHspec
     ]

++ pkgs.stdenv.lib.optionals
     (pkgs.stdenv.lib.versionOlder "7.5" ghcEnv.ghc.version)
     # Packages that only work in 7.6+
     [ folds
       linear
       lens
       lensFamily
       lensFamilyCore
       lensDatetime
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
;

# my-packages = ghcEnv: with ghcEnv.hs-pkgs; [
#   Boolean
#   CCdelcont
#   HTTP
#   HUnit
#   IfElse
#   MemoTrie
#   MissingH
#   MonadCatchIOTransformers
#   QuickCheck
#   abstract-deque
#   abstract-par
#   adjunctions
#   aeson
#   async
#   attempt
#   attoparsec
#   attoparsec-conduit
#   attoparsec-enumerator
#   base16-bytestring
#   base64-bytestring
#   base-unicode-symbols
#   basic-prelude
#   bifunctors
#   bindings-DSL
#   blaze-builder
#   blaze-builder-conduit
#   blaze-builder-enumerator
#   blaze-html
#   blaze-markup
#   blaze-textual
#   bool-extras
#   byteable
#   byteorder
#   bytes
#   bytestring-mmap
#   case-insensitive
#   cassava
#   cereal
#   cereal-conduit
#   charset
#   cheapskate
#   chunked-data
#   classy-prelude
#   classy-prelude-conduit
#   cmdargs
#   comonad
#   comonad-transformers
#   composition
#   compressed
#   cond
#   conduit
#   conduit-combinators
#   conduit-extra
#   configurator
#   constraints
#   contravariant
#   convertible
#   cpphs
#   cryptohash
#   css-text
#   data-checked
#   data-default
#   data-fin
#   data-fix
#   derive
#   distributive
#   dlist
#   dlist-instances
#   dns
#   doctest
#   doctest-prop
#   either
#   enclosed-exceptions
#   errors
#   exceptions
#   extensible-exceptions
#   failure
#   fast-logger
#   file-embed
#   filepath
#   fingertree
#   # fixplate
#   fmlist
#   foldl
#   free
#   fsnotify
#   ghc-paths
#   groups
#   hamlet
#   hashable
#   hashtables
#   haskeline
#   haskell-lexer
#   haskell-src
#   haskell-src-exts
#   haskell-src-meta
#   hfsevents
#   hoopl
#   hslogger
#   hspec
#   hspec-expectations
#   hstring-template
#   html
#   http-client
#   http-date
#   http-types
#   io-memoize
#   io-storage
#   json
#   keys
#   language-c
#   language-java
#   language-javascript
#   lattices
#   lifted-async
#   lifted-base
#   list-extras
#   logict
#   machines
#   mime-mail
#   mime-types
#   mmorph
#   monad-control
#   monad-coroutine
#   monad-loops
#   monad-par
#   monad-par-extras
#   monad-stm
#   monadloc
#   monoid-extras
#   mono-traversable
#   mtl
#   multimap
#   multirec
#   network
#   newtype
#   numbers
#   operational
#   optparse-applicative
#   # orgmode-parse
#   pandoc
#   parallel
#   parallel-io
#   parsec

#   pipes
#   pipes-attoparsec
#   pipes-binary
#   pipes-bytestring
#   pipes-concurrency
#   pipes-group
#   pipes-http
#   pipes-network
#   pipes-parse
#   pipes-safe
#   pipes-text

#   pointed
#   posix-paths
#   pretty-show
#   profunctors
#   random
#   reducers
#   reflection
#   regex-applicative
#   regex-base
#   regex-compat
#   regex-posix
#   regular
#   resourcet
#   retry
#   rex
#   safe
#   sbv
#   scotty
#   semigroupoids
#   semigroups
#   shake
#   shakespeare
#   shelly
#   simple-reflect
#   speculation
#   split
#   spoon
#   stm
#   stm-chans
#   stm-stats
#   strict
#   strptime
#   syb
#   system-fileio
#   system-filepath
#   tagged
#   tar
#   tasty
#   tasty-hunit
#   tasty-smallcheck
#   tasty-quickcheck
#   temporary
#   text
#   text-format
#   these
#   thyme
#   time
#   timeparsers
#   time-recurrence
#   transformers
#   transformers-base
#   unix-compat
#   uniplate
#   unordered-containers
#   uuid
#   vector
#   void
#   wai
#   warp
#   xhtml
#   yaml
#   zippers
#   zlib
# ]

# ++ pkgs.stdenv.lib.optionals
#      (pkgs.stdenv.lib.version-Older "7.7" ghc-Env.ghc.version)
#      # Packages that only work in 7.8+
#      [ trifecta
#        parsers
#        compdata
#        singletons
#        units
#        criterion
#        kan-extensions
#        pipes-shell
#        tasty-hspec
#      ]

# ++ pkgs.stdenv.lib.optionals
#      (pkgs.stdenv.lib.version-Older "7.5" ghc-Env.ghc.version)
#      # Packages that only work in 7.6+
#      [ folds
#        linear
#        lens
#        lens-family
#        lens-family-core
#        lens-datetime
#      ]

# ++ pkgs.stdenv.lib.optionals
#      (pkgs.stdenv.lib.version-Older ghc-Env.ghc.version "7.9")
#      # Packages that do not work in 7.10+
#      [ stringsearch
#        exceptions
#        arithmoi
#        fgl
#      ]

# ++ pkgs.stdenv.lib.optionals
#      (pkgs.stdenv.lib.version-Older ghc-Env.ghc.version "7.7")
#      # Packages that do not work in 7.8+
#      [ recursion-schemes
#      ]
# ;

};

allowUnfree = true;
allowBroken = true;

}
