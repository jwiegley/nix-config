{ pkgs }: {

packageOverrides = super: let self = super.pkgs; in with self; rec {

myHaskellPackages = hp: hp.override {
  overrides = self: super: with pkgs.haskell-ng.lib; {
    linearscan = self.callPackage ~/bae/linearscan {};
  
    newartisans = self.callPackage ~/doc/newartisans {
      yuicompressor = pkgs.yuicompressor;
    };
  
    c2hsc         = self.callPackage ~/Projects/c2hsc {};
    git-all       = self.callPackage ~/Projects/git-all {};
    hours         = self.callPackage ~/Projects/hours {};
    pushme        = self.callPackage ~/Projects/pushme {};
    rehoo         = self.callPackage ~/Projects/rehoo {};
    simple-mirror = self.callPackage ~/Projects/simple-mirror {};
    sizes         = self.callPackage ~/Projects/sizes {};
    una           = self.callPackage ~/Projects/una {};
  
    async-pool     = self.callPackage ~/Projects/async-pool {};
    bindings-DSL   = self.callPackage ~/Projects/bindings-dsl {};
    commodities    = self.callPackage ~/Projects/ledger/new/commodities {};
    consistent     = self.callPackage ~/Projects/consistent {};
    find-conduit   = self.callPackage ~/Projects/find-conduit {};
    fuzzcheck      = self.callPackage ~/Projects/fuzzcheck {};
    github         = self.callPackage ~/Projects/github {};
    hnix           = self.callPackage ~/Projects/hnix {};
    ipcvar         = self.callPackage ~/Projects/ipcvar {};
    logging        = self.callPackage ~/Projects/logging {};
    monad-extras   = self.callPackage ~/Projects/monad-extras {};
    rest-client    = self.callPackage ~/Projects/rest-client {};
    simple-conduit = self.callPackage ~/Projects/simple-conduit {};
  
    gitlib         = self.callPackage ~/Projects/gitlib/gitlib {};
    gitlib-test    = self.callPackage ~/Projects/gitlib/gitlib-test {};
    hlibgit2       = self.callPackage ~/Projects/gitlib/hlibgit2 {};
    gitlib-libgit2 = self.callPackage ~/Projects/gitlib/gitlib-libgit2 {};
    gitlib-cmdline = self.callPackage ~/Projects/gitlib/gitlib-cmdline {
      git = gitAndTools.git;
    };
    gitlib-cross   = self.callPackage ~/Projects/gitlib/gitlib-cross {
      git = gitAndTools.git;
    };
    gitlib-hit     = self.callPackage ~/Projects/gitlib/gitlib-hit {};
    gitlib-lens    = self.callPackage ~/Projects/gitlib/gitlib-lens {};
    gitlib-s3      = self.callPackage ~/Projects/gitlib/gitlib-S3 {};
    gitlib-sample  = self.callPackage ~/Projects/gitlib/gitlib-sample {};
    git-monitor    = self.callPackage ~/Projects/gitlib/git-monitor {};
    git-gpush      = self.callPackage ~/Projects/gitlib/git-gpush {};
  
    hdevtools = self.callPackage ~/oss/hdevtools {};
  
    systemFileio = dontCheck super.systemFileio;
    shake        = dontCheck super.shake;
    singletons   = dontCheck super.singletons;
  
    cabalNoLinks = self.cabal.override { enableHyperlinkSource = false; };
    disableLinks = x: x.override { cabal = self.cabalNoLinks; };
    unlambda     = self.disableLinks super.unlambda;
  };
};

haskellngPackages  = myHaskellPackages super.haskellngPackages;
haskell784Packages = myHaskellPackages super.haskell-ng.packages.ghc784;
haskell763Packages = myHaskellPackages super.haskell-ng.packages.ghc763;
haskell742Packages = myHaskellPackages super.haskell-ng.packages.ghc742;

ledger = super.callPackage ~/Projects/ledger {};

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
  ];
};

systemToolsEnv = pkgs.buildEnv {
  name = "systemTools";
  paths = [
    haskellngPackages.pushme
    haskellngPackages.sizes
    haskellngPackages.una

    # ack
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
    haskell784Packages.newartisans
    # nixbang
    # p7zip
    haskell784Packages.pandoc
    parallel
    pinentry
    pv
    # recutils
    # rlwrap
    screen
    silver-searcher
    haskellngPackages.simple-mirror
    sqlite
    stow
    time
    # tmux
    # tree
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

      haskell784Packages.git-annex
      # pkgs.haskellngPackages.git-gpush
      haskellngPackages.git-monitor
      pkgs.gitAndTools.gitFull
      pkgs.gitAndTools.gitflow
      pkgs.gitAndTools.hub
      pkgs.gitAndTools.topGit

      # pkgs.haskellngPackages.git-all
    ];
  };

networkToolsEnv = pkgs.buildEnv {
  name = "networkTools";
  paths = [
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
    # s3cmd
    socat2pre
    # spiped
    wget
    # youtubeDL
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
    # texLiveFull
    # djvu2pdf
    ghostscript
    # librsvg
    # poppler poppler_data
    libpng
  ];
};

serviceToolsEnv = pkgs.buildEnv {
  name = "serviceTools";
  paths = [
    # nginx
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
    # darcs
    diffstat
    doxygen
    fcgi
    flex
    htmlTidy
    # lcov
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
    # coq_8_5
    # coqPackages.bedrock
    # coqPackages.containers
    # coqPackages.coqExtLib
    # coqPackages.coqeal
    # coqPackages.domains
    # coqPackages.fiat
    # coqPackages.flocq
    # coqPackages.heq
    coqPackages.mathcomp
    # coqPackages.paco
    coqPackages.ssreflect
    # coqPackages.tlc
    # coqPackages.ynot
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
    cabal-meta
    djinn mueval
    idris
    threadscope
    timeplot splot
    liquidhaskell
    hakyll
  ];
};

ghc742Env = pkgs.myEnvFun {
  name = "ghc742";
  buildInputs = with haskell742Packages; [
    (haskell742Packages.ghcWithPackages my-packages)
    (hoogle-local my-packages haskell742Packages)

    cabal-install
    ghc-core
    ghc-mod
    hdevtools
    hlint
    hasktags
    cabal-meta
    djinn mueval
    idris
    threadscope
    timeplot splot
    liquidhaskell
    hakyll
  ];
};

ghc763Env = pkgs.myEnvFun {
  name = "ghc763";
  buildInputs = with haskell763Packages; [
    (haskell763Packages.ghcWithPackages my-packages-763)
    (hoogle-local my-packages-763 haskell763Packages)

    cabal-install
    ghc-core
    ghc-mod
    hdevtools
    hlint
    hasktags
    cabal-meta
    djinn mueval
    idris
    threadscope
    timeplot splot
    liquidhaskell
    hakyll
  ];
};

ghc7101Env = pkgs.myEnvFun {
  name = "ghc7101";
  buildInputs = with haskellngPackages; [
    (haskellngPackages.ghcWithPackages my-packages-next)
    (hoogle-local my-packages-next haskellngPackages)

    cabal-install
    ghc-core
    # ghc-mod
    # hdevtools
    hlint
    simple-mirror
    hasktags
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
  import <nixpkgs/pkgs/development/libraries/haskell/hoogle/local.nix> {
    inherit stdenv hoogle rehoo ghc;
    packages = f pkgs ++ [ cheapskate trifecta ];
  };

haskellFilterSource = paths: src: builtins.filterSource (path: type:
    let baseName = baseNameOf path; in
    !( type == "unknown"
    || builtins.elem baseName
         ([".hdevtools.sock" ".git" ".cabal-sandbox" "dist"] ++ paths)
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
  compdata
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
  recursion-schemes
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

my-packages-763 = hp: with hp; [
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
  compdata
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
  recursion-schemes
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

};

allowUnfree = true;
allowBroken = true;

}
