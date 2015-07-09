{ pkgs }: {

packageOverrides = super: let self = super.pkgs; in with self; rec {

myHaskellPackages = hp: hp.override {
  overrides = self: super: with pkgs.haskell-ng.lib; {
    coq-haskell      = self.callPackage ~/src/linearscan/Hask {};
    linearscan       = self.callPackage ~/src/linearscan {};
    linearscan-hoopl = self.callPackage ~/src/linearscan-hoopl {};
  
    newartisans = self.callPackage ~/doc/newartisans {
      yuicompressor = pkgs.yuicompressor;
    };
  
    recursion-schemes = self.callPackage ~/src/recursion-schemes {};

    ghc-issues     = self.callPackage ~/src/ghc-issues {};
    c2hsc          = self.callPackage ~/src/c2hsc {};
    git-all        = self.callPackage ~/src/git-all {};
    hours          = self.callPackage ~/src/hours {};
    pushme         = self.callPackage ~/src/pushme {};
    rehoo          = self.callPackage ~/src/rehoo {};
    simple-mirror  = self.callPackage ~/src/simple-mirror {};
    sizes          = self.callPackage ~/src/sizes {};
    una            = self.callPackage ~/src/una {};
  
    async-pool     = self.callPackage ~/src/async-pool {};
    bindings-DSL   = self.callPackage ~/src/bindings-dsl {};
    commodities    = self.callPackage ~/src/ledger/new/commodities {};
    consistent     = self.callPackage ~/src/consistent {};
    find-conduit   = self.callPackage ~/src/find-conduit {};
    fuzzcheck      = self.callPackage ~/src/fuzzcheck {};
    github         = self.callPackage ~/src/github {};
    hnix           = self.callPackage ~/src/hnix {};
    ipcvar         = self.callPackage ~/src/ipcvar {};
    logging        = self.callPackage ~/src/logging {};
    monad-extras   = self.callPackage ~/src/monad-extras {};
    rest-client    = self.callPackage ~/src/rest-client {};
    simple-conduit = self.callPackage ~/src/simple-conduit {};
  
    gitlib         = self.callPackage ~/src/gitlib/gitlib {};
    gitlib-test    = self.callPackage ~/src/gitlib/gitlib-test {};
    hlibgit2       = self.callPackage ~/src/gitlib/hlibgit2 {};
    gitlib-libgit2 = self.callPackage ~/src/gitlib/gitlib-libgit2 {};
    gitlib-cmdline = self.callPackage ~/src/gitlib/gitlib-cmdline {
      git = gitAndTools.git;
    };
    gitlib-cross   = self.callPackage ~/src/gitlib/gitlib-cross {
      git = gitAndTools.git;
    };
    gitlib-hit     = self.callPackage ~/src/gitlib/gitlib-hit {};
    gitlib-lens    = self.callPackage ~/src/gitlib/gitlib-lens {};
    gitlib-s3      = self.callPackage ~/src/gitlib/gitlib-S3 {};
    gitlib-sample  = self.callPackage ~/src/gitlib/gitlib-sample {};
    git-monitor    = self.callPackage ~/src/gitlib/git-monitor {};
    git-gpush      = self.callPackage ~/src/gitlib/git-gpush {};
  
    hdevtools    = self.callPackage ~/oss/hdevtools {};
  
    systemFileio = dontCheck super.systemFileio;
    shake        = dontCheck super.shake;
    singletons   = dontCheck super.singletons;
  };
};

myHaskellPackages763 = hp: hp.override {
  overrides = self: super: with pkgs.haskell-ng.lib; {
    IOSpec = appendPatch (doJailbreak super.IOSpec) ./IOSpec.patch;
    random = dontHaddock super.random;
    regex-posix = dontHaddock super.regex-posix;
    ansi-terminal = dontHaddock super.ansi-terminal;
    hostname = dontHaddock super.hostname;
    ansi-wl-pprint = dontHaddock super.ansi-wl-pprint;
    test-framework = dontHaddock super.test-framework;
    primitive = dontHaddock super.primitive;
    tf-random = dontHaddock super.tf-random;
    QuickCheck = dontHaddock super.QuickCheck;
    QuickCheck-safe = dontHaddock super.QuickCheck-safe;
    stm = dontHaddock super.stm;
    extensible-exceptions = dontHaddock super.extensible-exceptions;
    test-framework-quickcheck2 = dontHaddock super.test-framework-quickcheck2;
    exceptions = dontHaddock super.exceptions;
    temporary = dontHaddock super.temporary;
    MonadRandom = dontHaddock super.MonadRandom;
    random-shuffle = dontHaddock super.random-shuffle;
    terminfo = dontHaddock super.terminfo;
    HUnit = dontHaddock super.HUnit;
    syb = dontHaddock super.syb;
    ChasingBottoms = dontHaddock super.ChasingBottoms;
    test-framework-hunit = dontHaddock super.test-framework-hunit;
    unordered-containers = dontHaddock super.unordered-containers;
    semigroups = dontHaddock super.semigroups;
    void = dontHaddock super.void;
    MemoTrie = dontHaddock super.MemoTrie;
    vector-space = dontHaddock super.vector-space;
    th-extras = dontHaddock super.th-extras;
    dependent-sum-template = dontHaddock super.dependent-sum-template;
    dlist = dontHaddock super.dlist;
    utf8-string = dontHaddock super.utf8-string;
    blaze-builder = dontHaddock super.blaze-builder;
    tagged = dontHaddock super.tagged;
    optparse-applicative = dontHaddock super.optparse-applicative;
    parsec = dontHaddock super.parsec;
    regex-tdfa-rc = dontHaddock super.regex-tdfa-rc;
    async = dontHaddock super.async;
    tasty = dontHaddock super.tasty;
    tasty-hunit = dontHaddock super.tasty-hunit;
    pcre-light = dontHaddock super.pcre-light;
    tasty-quickcheck = dontHaddock super.tasty-quickcheck;
    tasty-smallcheck = dontHaddock super.tasty-smallcheck;
    generic-deriving = dontHaddock super.generic-deriving;
    tasty-ant-xml = dontHaddock super.tasty-ant-xml;
    scientific = dontHaddock super.scientific;
    quickcheck-unicode = dontHaddock super.quickcheck-unicode;
    vector = dontHaddock super.vector;
    attoparsec = dontHaddock super.attoparsec;
    aeson = dontHaddock super.aeson;
    quickcheck-io = dontHaddock super.quickcheck-io;
    hspec-expectations = dontHaddock super.hspec-expectations;
    hspec-meta = dontHaddock super.hspec-meta;
    hspec-discover = dontHaddock super.hspec-discover;
    data-default-instances-dlist = dontHaddock super.data-default-instances-dlist;
    hspec-core = dontHaddock super.hspec-core;
    hspec = dontHaddock super.hspec;
    base-compat = dontHaddock super.base-compat;
    stringbuilder = dontHaddock super.stringbuilder;
    doctest = dontHaddock super.doctest;
    network = dontHaddock super.network;
    network-uri = dontHaddock super.network-uri;
    HTTP = dontHaddock super.HTTP;
    js-flot = dontHaddock super.js-flot;
    language-haskell-extract = dontHaddock super.language-haskell-extract;
    StateVar = dontHaddock super.StateVar;
    contravariant = dontHaddock super.contravariant;
    oeis = dontHaddock super.oeis;
    data-default = dontHaddock super.data-default;
    vector-th-unbox = dontHaddock super.vector-th-unbox;
    ghc-mtl = dontHaddock super.ghc-mtl;
    hint = dontHaddock super.hint;
    show = dontHaddock super.show;
    mueval = dontHaddock super.mueval;
    hslogger = dontHaddock super.hslogger;
    cereal = dontHaddock super.cereal;
    stateref = dontHaddock super.stateref;
    mwc-random = dontHaddock super.mwc-random;
    flexible-defaults = dontHaddock super.flexible-defaults;
    mersenne-random-pure64 = dontHaddock super.mersenne-random-pure64;
    random-source = dontHaddock super.random-source;
    math-functions = dontHaddock super.math-functions;
    bytes = dontHaddock super.bytes;
    base-orphans = dontHaddock super.base-orphans;
    bifunctors = dontHaddock super.bifunctors;
    distributive = dontHaddock super.distributive;
    comonad = dontHaddock super.comonad;
    semigroupoids = dontHaddock super.semigroupoids;
    profunctors = dontHaddock super.profunctors;
    reflection = dontHaddock super.reflection;
    prelude-extras = dontHaddock super.prelude-extras;
    free = dontHaddock super.free;
    parallel = dontHaddock super.parallel;
    adjunctions = dontHaddock super.adjunctions;
    kan-extensions = dontHaddock super.kan-extensions;
    polyparse = dontHaddock super.polyparse;
    cpphs = dontHaddock super.cpphs;
    temporary-rc = dontHaddock super.temporary-rc;
    tasty-golden = dontHaddock super.tasty-golden;
    haskell-src-exts = dontHaddock super.haskell-src-exts;
    test-framework-th = dontHaddock super.test-framework-th;
    extra = dontHaddock super.extra;
    uniplate = dontHaddock super.uniplate;
    hlint = dontHaddock super.hlint;
    lens = dontHaddock super.lens;
    lens-action = dontHaddock super.lens-action;
    quickcheck-instances = dontHaddock super.quickcheck-instances;
    safecopy = dontHaddock super.safecopy;
    hashable-extras = dontHaddock super.hashable-extras;
    log-domain = dontHaddock super.log-domain;
    rvar = dontHaddock super.rvar;
    random-fu = dontHaddock super.random-fu;
    Stream = dontHaddock super.Stream;
    zlib = dontHaddock super.zlib;
    streaming-commons = dontHaddock super.streaming-commons;
    hstatsd = dontHaddock super.hstatsd;
    lambdabot-trusted = dontHaddock super.lambdabot-trusted;
    SafeSemaphore = dontHaddock super.SafeSemaphore;
    case-insensitive = dontHaddock super.case-insensitive;
    http-types = dontHaddock super.http-types;
    simple-sendfile = dontHaddock super.simple-sendfile;
    vault = dontHaddock super.vault;
    wai = dontHaddock super.wai;
    http-date = dontHaddock super.http-date;
    iproute = dontHaddock super.iproute;
    warp = dontHaddock super.warp;
    transformers-base = dontHaddock super.transformers-base;
    monad-control = dontHaddock super.monad-control;
    lifted-base = dontHaddock super.lifted-base;
    resourcet = dontHaddock super.resourcet;
    conduit = dontHaddock super.conduit;
    vector-algorithms = dontHaddock super.vector-algorithms;
    shake = dontHaddock super.shake;
    hoogle = dontHaddock super.hoogle;
    haskeline = dontHaddock super.haskeline;
    edit-distance = dontHaddock super.edit-distance;
    split = dontHaddock super.split;
    regex-tdfa = dontHaddock super.regex-tdfa;
    lambdabot-core = dontHaddock super.lambdabot-core;
    lambdabot-reference-plugins = dontHaddock super.lambdabot-reference-plugins;
    regex-pcre = dontHaddock super.regex-pcre;
    misfortune = dontHaddock super.misfortune;
    numbers = dontHaddock super.numbers;
    arrows = dontHaddock super.arrows;
    lambdabot-haskell-plugins = dontHaddock super.lambdabot-haskell-plugins;
    dice = dontHaddock super.dice;
    lambdabot-misc-plugins = dontHaddock super.lambdabot-misc-plugins;
    lambdabot-novelty-plugins = dontHaddock super.lambdabot-novelty-plugins;
    lambdabot-social-plugins = dontHaddock super.lambdabot-social-plugins;
    lambdabot-irc-plugins = dontHaddock super.lambdabot-irc-plugins;
  };
};

haskell7101Packages = myHaskellPackages super.haskell-ng.packages.ghc7101;
haskell784Packages  = myHaskellPackages super.haskell-ng.packages.ghc784;
haskell763Packages  = myHaskellPackages763 super.haskell-ng.packages.ghc763;

ledger = super.callPackage ~/src/ledger {};

emacs = if super.stdenv.isDarwin
        then super.emacs24Macport_24_5
        else super.emacs;

emacs24Packages = recurseIntoAttrs super.emacs24Packages //
  { proofgeneral = pkgs.emacs24Packages.proofgeneral_4_3_pre;
    emacs = pkgs.emacs; 
  };

emacsToolsEnv = pkgs.buildEnv {
  name = "emacsTools";
  paths = with emacsPackagesNgGen emacs; [
    emacs
    aspell
    aspellDicts.en
    auctex
    emacs24Packages.proofgeneral
  ];
};

systemToolsEnv = pkgs.buildEnv {
  name = "systemTools";
  paths = [
    haskell7101Packages.pushme
    haskell7101Packages.sizes
    haskell7101Packages.una

    ack
    # apg
    # cabextract
    bashInteractive
    bashCompletion
    exiv2
    # expect
    # figlet
    findutils
    gnugrep
    gnupg
    gnuplot
    gnused
    gnutar
    graphviz
    # guile
    haskell784Packages.hours
    imagemagick_light
    less
    # macvim
    # multitail
    # haskell784Packages.newartisans
    # nixbang
    # p7zip
    haskell7101Packages.pandoc
    parallel
    pinentry
    pv
    # recutils
    rlwrap
    screen
    silver-searcher
    haskell7101Packages.simple-mirror
    sqlite
    stow
    time
    # tmux
    tree
    # unarj
    unrar
    unzip
    watch
    # watchman
    xz
    z3
    zip
    zsh
  ];
};

gitToolsEnv = pkgs.buildEnv {
    name = "gitTools";
    paths = [
      diffutils patchutils
      # bup
      dar

      haskell763Packages.lambdabot
      haskell784Packages.git-annex
      # pkgs.haskell7101Packages.git-gpush
      haskell7101Packages.git-monitor
      pkgs.gitAndTools.gitFull
      pkgs.gitAndTools.gitflow
      pkgs.gitAndTools.hub
      pkgs.gitAndTools.topGit
      pkgs.gitAndTools.git-imerge

      pkgs.haskell7101Packages.git-all
    ];
  };

networkToolsEnv = pkgs.buildEnv {
  name = "networkTools";
  paths = [
    ansible
    # arcanist
    aria
    cacert
    # fping
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
    youtubeDL ffmpeg
  ];
};

mailToolsEnv = pkgs.buildEnv {
  name = "mailTools";
  paths = [
    dovecot22
    dovecot_pigeonhole
    leafnode
    fetchmail
    procmail
    # w3m
    # mairix
    # mutt
    # msmtp
    # lbdb
    # contacts
    # spamassassin
  ];
};

publishToolsEnv = pkgs.buildEnv {
  name = "publishTools";
  paths = [ 
    texLiveFull
    # djvu2pdf
    ghostscript
    # librsvg
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
    # python27Packages.ipython
    python27Packages.pygments
  ];
};

rubyToolsEnv = pkgs.buildEnv {
  name = "rubyTools";
  paths = [ ruby_2_1_2 ];
};

buildToolsEnv = pkgs.buildEnv {
  name = "buildTools";
  paths = [
    ninja
    # scons
    global idutils
    autoconf automake114x
    bazaar bazaarTools
    # ccache
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

langToolsEnv = pkgs.buildEnv {
  name = "langTools";
  paths = [
    clang llvm boost
    ott isabelle
    gnumake
    # compcert # verasco
    # fsharp
    # rustc
    sbcl acl2
    # erlang
    sloccount
    # swiProlog
    yuicompressor
  ];
 };

# coqEnv = pkgs.myEnvFun {
#   name = "coqHEAD";
#   buildInputs = [ coq_HEAD ];
# };

coq85Env = pkgs.myEnvFun {
  name = "coq85";
  buildInputs = [
    coq_8_5
    coqPackages_8_5.mathcomp
    coqPackages_8_5.ssreflect
  ];
};

coqToolsEnv = pkgs.buildEnv {
  name = "coqTools";
  paths = [
    ocaml
    ocamlPackages.camlp5_transitional
    coq
    coqPackages.fiat coqPackages.bedrock
    # coqPackages.containers
    # coqPackages.coqExtLib
    # coqPackages.coqeal
    # coqPackages.domains
    # coqPackages.flocq
    # coqPackages.heq
    coqPackages.mathcomp
    # coqPackages.paco
    coqPackages.QuickChick
    coqPackages.ssreflect
    coqPackages.tlc
    coqPackages.ynot
    prooftree
  ];
};

agdaEnv = pkgs.myEnvFun {
  name = "agda";
  buildInputs = [
    haskell784Packages.Agda
    haskell784Packages.Agda-executable
  ];
};

gameToolsEnv = pkgs.buildEnv {
  name = "gameTools";
  paths = [ 
    chessdb 
    craftyFull
    eboard
    gnugo
  ];
};

youtube-dl = super.stdenv.lib.overrideDerivation super.youtube-dl (attrs: {
  ffmpeg = null;
  pandoc = null;
  postInstall = "";
});

idutils = super.stdenv.lib.overrideDerivation super.idutils (attrs: {
  doCheck = false;
});

ghc784Env = pkgs.myEnvFun {
  name = "ghc784";
  buildInputs = with haskell784Packages; [
    (haskell784Packages.ghcWithPackages my-packages)
    (hoogle-local my-packages haskell784Packages)

    cabal-install
    ghc-core
    ghc-mod
    hdevtools
    hlint
    hasktags
    # hpack
    cabal-meta
    djinn #mueval
    pointfree
    # idris
    # threadscope
    # timeplot splot
    # liquidhaskell
    hakyll
  ];
};

ghc7101Env = pkgs.myEnvFun {
  name = "ghc7101";
  buildInputs = with haskell7101Packages; [
    (haskell7101Packages.ghcWithPackages my-packages-next)
    (hoogle-local my-packages-next haskell7101Packages)

    cabal-install
    ghc-core
    # ghc-mod
    # hdevtools
    hlint
    simple-mirror
    hasktags
    # hpack
    cabal-meta
    djinn # mueval
    # idris
    threadscope
    # timeplot splot
    # liquidhaskell
    # hakyll
  ];
};

hoogle-local = f: pkgs: with pkgs;
  import ~/.nixpkgs/local.nix {
    inherit stdenv hoogle rehoo ghc;
    packages = f pkgs ++ [ cheapskate trifecta ];
  };

haskellFilterSource = paths: src: builtins.filterSource (path: type:
    let baseName = baseNameOf path; in
    !( type == "unknown"
    || builtins.elem baseName
         ([".hdevtools.sock" ".git" ".cabal-sandbox" "dist"] ++ paths)
    || stdenv.lib.hasSuffix ".sock" path
    || stdenv.lib.hasSuffix ".hi" path
    || stdenv.lib.hasSuffix ".hi-boot" path
    || stdenv.lib.hasSuffix ".o" path
    || stdenv.lib.hasSuffix ".o-boot" path
    || stdenv.lib.hasSuffix ".dyn_o" path
    || stdenv.lib.hasSuffix ".p_o" path))
  src;

my-packages = hp: with hp; [
  # fixplate
  # orgmode-parse
  Boolean
  CC-delcont
  HTTP
  HUnit
  IfElse
  MemoTrie
  MissingH
  MonadCatchIO-transformers
  QuickCheck
  abstract-deque
  abstract-par
  adjunctions
  aeson
  arithmoi
  async
  attempt
  attoparsec
  attoparsec-conduit
  attoparsec-enumerator
  base-unicode-symbols
  base16-bytestring
  base64-bytestring
  basic-prelude
  bifunctors
  bindings-DSL
  blaze-builder
  blaze-builder-conduit
  blaze-builder-enumerator
  blaze-html
  blaze-markup
  blaze-textual
  bool-extras
  byteable
  byteorder
  bytes
  bytestring-mmap
  case-insensitive
  cassava
  categories
  cereal
  cereal-conduit
  charset
  chunked-data
  classy-prelude
  classy-prelude-conduit
  cmdargs
  comonad
  comonad-transformers
  # compdata
  composition
  compressed
  cond
  conduit
  conduit-combinators
  conduit-extra
  configurator
  constraints
  contravariant
  convertible
  cpphs
  criterion
  cryptohash
  css-text
  data-checked
  data-default
  data-fin
  data-fix
  derive
  distributive
  dlist
  dlist-instances
  dns
  doctest
  doctest-prop
  either
  enclosed-exceptions
  errors
  exceptions
  exceptions
  extensible-exceptions
  failure
  fast-logger
  fgl
  file-embed
  filepath
  fingertree
  fmlist
  foldl
  folds
  free
  fsnotify
  ghc-paths
  groups
  hamlet
  hashable
  hashtables
  haskeline
  haskell-lexer
  haskell-src
  haskell-src-exts
  haskell-src-meta
  hfsevents
  hoopl
  hslogger
  hspec
  hspec-expectations
  html
  http-client
  http-date
  http-types
  io-memoize
  io-storage
  json
  kan-extensions
  keys
  language-c
  language-java
  language-javascript
  lattices
  lens
  lens-datetime
  lens-family
  lens-family-core
  lifted-async
  lifted-base
  linear
  list-extras
  logict
  machines
  mime-mail
  mime-types
  mmorph
  monad-control
  monad-coroutine
  monad-loops
  monad-par
  monad-par-extras
  monad-stm
  monadloc
  mono-traversable
  monoid-extras
  mtl
  multimap
  multirec
  network
  newtype
  numbers
  operational
  optparse-applicative
  pandoc
  parallel
  parallel-io
  parsec
  parsers
  pipes
  pipes-attoparsec
  pipes-binary
  pipes-bytestring
  pipes-concurrency
  pipes-extras
  pipes-group
  pipes-http
  pipes-network
  pipes-parse
  pipes-safe
  pipes-shell
  pipes-text
  pointed
  posix-paths
  postgresql-simple
  pretty-show
  profunctors
  random
  # recursion-schemes
  reducers
  reflection
  regex-applicative
  regex-base
  regex-compat
  regex-posix
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
  simple-reflect
  singletons
  speculation
  split
  spoon
  stm
  stm-chans
  stm-stats
  strict
  stringsearch
  strptime
  syb
  system-fileio
  system-filepath
  tagged
  tar
  tardis
  tasty
  tasty-hspec
  tasty-hunit
  tasty-quickcheck
  tasty-smallcheck
  temporary
  text
  text-format
  these
  thyme
  time
  time-recurrence
  timeparsers
  transformers
  transformers-base
  uniplate
  units
  unix-compat
  unordered-containers
  uuid
  vector
  void
  wai
  warp
  xhtml
  yaml
  zippers
  zlib
];

my-packages-next = hp: with hp; [
  # fixplate
  # orgmode-parse
  Boolean
  # CC-delcont
  HTTP
  HUnit
  IfElse
  MemoTrie
  MissingH
  MonadCatchIO-transformers
  QuickCheck
  abstract-deque
  abstract-par
  adjunctions
  aeson
  # arithmoi
  async
  attempt
  attoparsec
  attoparsec-conduit
  attoparsec-enumerator
  base-unicode-symbols
  base16-bytestring
  base64-bytestring
  basic-prelude
  bifunctors
  bindings-DSL
  blaze-builder
  blaze-builder-conduit
  blaze-builder-enumerator
  blaze-html
  blaze-markup
  blaze-textual
  bool-extras
  byteable
  byteorder
  bytes
  bytestring-mmap
  case-insensitive
  cassava
  categories
  cereal
  cereal-conduit
  charset
  chunked-data
  classy-prelude
  classy-prelude-conduit
  cmdargs
  comonad
  comonad-transformers
  # compdata
  composition
  compressed
  cond
  conduit
  conduit-combinators
  conduit-extra
  configurator
  constraints
  contravariant
  convertible
  cpphs
  criterion
  cryptohash
  css-text
  data-checked
  data-default
  data-fin
  data-fix
  derive
  distributive
  dlist
  dlist-instances
  dns
  doctest
  # doctest-prop
  either
  enclosed-exceptions
  errors
  exceptions
  exceptions
  extensible-exceptions
  failure
  fast-logger
  fgl
  file-embed
  filepath
  fingertree
  fmlist
  foldl
  folds
  free
  fsnotify
  ghc-paths
  groups
  hamlet
  hashable
  hashtables
  haskeline
  haskell-lexer
  haskell-src
  haskell-src-exts
  haskell-src-meta
  hfsevents
  hoopl
  hslogger
  hspec
  hspec-expectations
  html
  http-client
  http-date
  http-types
  io-memoize
  io-storage
  json
  kan-extensions
  keys
  language-c
  language-java
  language-javascript
  lattices
  lens
  lens-datetime
  lens-family
  lens-family-core
  lifted-async
  lifted-base
  linear
  list-extras
  logict
  # machines
  mime-mail
  mime-types
  mmorph
  monad-control
  monad-coroutine
  monad-loops
  monad-par
  monad-par-extras
  monad-stm
  monadloc
  mono-traversable
  monoid-extras
  mtl
  multimap
  multirec
  network
  newtype
  numbers
  operational
  optparse-applicative
  # pandoc
  parallel
  parallel-io
  parsec
  parsers
  pipes
  pipes-attoparsec
  pipes-binary
  pipes-bytestring
  pipes-concurrency
  pipes-extras
  pipes-group
  pipes-http
  pipes-network
  pipes-parse
  pipes-safe
  pipes-shell
  pipes-text
  pointed
  posix-paths
  postgresql-simple
  pretty-show
  profunctors
  random
  # recursion-schemes
  reducers
  reflection
  regex-applicative
  regex-base
  regex-compat
  regex-posix
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
  simple-reflect
  # singletons
  speculation
  split
  spoon
  stm
  stm-chans
  stm-stats
  strict
  stringsearch
  strptime
  syb
  system-fileio
  system-filepath
  tagged
  tar
  tardis
  tasty
  tasty-hspec
  tasty-hunit
  tasty-quickcheck
  tasty-smallcheck
  temporary
  text
  text-format
  these
  # thyme
  time
  # time-recurrence
  # timeparsers
  transformers
  transformers-base
  uniplate
  # units
  unix-compat
  unordered-containers
  uuid
  vector
  void
  wai
  warp
  xhtml
  yaml
  zippers
  zlib
];

};

allowUnfree = true;
allowBroken = true;

}
