{ pkgs }: {

packageOverrides = super: let self = super.pkgs; in with self; rec {

myHaskellPackages = self: super: with pkgs.haskell.lib; {
  newartisans = self.callPackage ~/doc/newartisans {
    yuicompressor = pkgs.yuicompressor;
  };

  emacs-bugs      = self.callPackage ~/src/emacs-bugs {};
  firestone       = self.callPackage /tmp/firestone {};
  coq-haskell      = self.callPackage ~/src/coq-haskell {};
  linearscan       = self.callPackage ~/src/linearscan {};
  linearscan-hoopl = self.callPackage ~/src/linearscan-hoopl {};
  async-pool      = self.callPackage ~/src/async-pool {};
  c2hsc           = dontCheck (self.callPackage ~/src/c2hsc {});
  commodities     = self.callPackage ~/src/ledger/new/commodities {};
  consistent      = self.callPackage ~/src/consistent {};
  find-conduit    = self.callPackage ~/src/find-conduit {};
  fusion          = self.callPackage ~/src/fusion {};
  fuzzcheck       = self.callPackage ~/src/fuzzcheck {};
  ghc-issues      = self.callPackage ~/src/ghc-issues {};
  git-all         = self.callPackage ~/src/git-all {};
  github          = self.callPackage ~/src/github {};
  hierarchy       = self.callPackage ~/src/hierarchy {};
  hnix            = self.callPackage ~/src/hnix {};
  hours           = self.callPackage ~/src/hours {};
  ipcvar          = self.callPackage ~/src/ipcvar {};
  logging         = self.callPackage ~/src/logging {};
  monad-extras    = self.callPackage ~/src/monad-extras {};
  pipes-files     = self.callPackage ~/src/pipes-files {};
  pipes-fusion    = self.callPackage ~/src/pipes-fusion {};
  pushme          = self.callPackage ~/src/pushme {};
  rehoo           = self.callPackage ~/src/rehoo {};
  rest-client     = self.callPackage ~/src/rest-client {};
  simple-conduit  = self.callPackage ~/src/simple-conduit {};
  simple-mirror   = self.callPackage ~/src/hackage-mirror {};
  sizes           = self.callPackage ~/src/sizes {};
  streaming-tests = self.callPackage ~/src/streaming-tests {};
  una             = self.callPackage ~/src/una {};

  gitlib          = self.callPackage ~/src/gitlib/gitlib {};
  gitlib-test     = self.callPackage ~/src/gitlib/gitlib-test {};
  hlibgit2        = dontCheck (self.callPackage ~/src/gitlib/hlibgit2 {});
  gitlib-libgit2  = self.callPackage ~/src/gitlib/gitlib-libgit2 {};
  gitlib-cmdline  = self.callPackage ~/src/gitlib/gitlib-cmdline {
    git = gitAndTools.git;
  };
  gitlib-cross    = self.callPackage ~/src/gitlib/gitlib-cross {
    git = gitAndTools.git;
  };
  gitlib-hit      = self.callPackage ~/src/gitlib/gitlib-hit {};
  gitlib-lens     = self.callPackage ~/src/gitlib/gitlib-lens {};
  gitlib-s3       = self.callPackage ~/src/gitlib/gitlib-S3 {};
  gitlib-sample   = self.callPackage ~/src/gitlib/gitlib-sample {};
  git-monitor     = self.callPackage ~/src/gitlib/git-monitor {};
  git-gpush       = self.callPackage ~/src/gitlib/git-gpush {};

  pipes           = self.callPackage ~/oss/pipes {};
  pipes-safe      = self.callPackage ~/oss/pipes-safe {};
  bindings-DSL    = self.callPackage ~/oss/bindings-dsl {};
  time-recurrence = dontCheck (self.callPackage ~/oss/time-recurrence {});
  timeparsers     = dontCheck (self.callPackage ~/oss/timeparsers {});
  scalpel         = self.callPackage ~/oss/scalpel {};

  systemFileio    = dontCheck super.systemFileio;
  shake           = dontCheck super.shake;
  singletons      = dontCheck super.singletons;
};

haskell7103Packages = super.haskell.packages.ghc7103.override {
  overrides = myHaskellPackages;
};

profiledHaskell7103Packages = super.haskell.packages.ghc7103.override {
  overrides = self: super: myHaskellPackages self super // {
    mkDerivation = args: super.mkDerivation (args // {
      enableLibraryProfiling = true;
      enableExecutableProfiling = true;
    });
  };
};

ledger = super.callPackage ~/src/ledger {};

emacsHEAD_base = super.callPackage ~/.nixpkgs/emacsHEAD.nix {
  libXaw = xorg.libXaw;
  Xaw3d = null;
  gconf = null;
  alsaLib = null;
  imagemagick = null;
  acl = null;
  gpm = null;
  inherit (darwin.apple_sdk.frameworks) AppKit Foundation;
  inherit (darwin) libobjc;
};

emacsHEAD = super.stdenv.lib.overrideDerivation emacsHEAD_base (attrs: { 
  doCheck = false; 
});

emacs = if super.stdenv.isDarwin
        then super.emacs24Macport_24_5
        else super.emacs;

emacs24Packages = recurseIntoAttrs super.emacs24Packages //
  { proofgeneral = pkgs.emacs24Packages.proofgeneral_4_3_pre;
    emacs = pkgs.emacs;
  };

emacsHEADEnv = pkgs.myEnvFun {
  name = "emacsHEAD";
  buildInputs = with emacsPackagesNgGen emacs; [
    emacsHEAD
    pkgs.auctex
    pkgs.emacs24Packages.proofgeneral_HEAD
  ];
};

emacsHEADAltEnv = pkgs.myEnvFun {
  name = "emacsHEADalt";
  buildInputs = with emacsPackagesNgGen emacs; [
    emacsHEAD
  ];
};

emacs24Env = pkgs.myEnvFun {
  name = "emacs24";
  buildInputs = with emacsPackagesNgGen emacs; [
    emacs
    pkgs.auctex
    emacs24Packages.proofgeneral
  ];
};

emacs24AltEnv = pkgs.myEnvFun {
  name = "emacs24alt";
  buildInputs = with emacsPackagesNgGen emacs; [
    emacs
  ];
};

x11ToolsEnv = pkgs.buildEnv {
  name = "x11Tools";
  paths = [ xquartz xorg.xhost xorg.xauth ratpoison ];
};

systemToolsEnv = pkgs.buildEnv {
  name = "systemTools";
  paths = [
    haskell7103Packages.pushme
    haskell7103Packages.sizes
    haskell7103Packages.una

    aspell
    aspellDicts.en
    exiv2
    findutils
    monkeysphere
    gnugrep
    gnuplot
    gnused
    gnutar
    graphviz
    haskell7103Packages.hours
    imagemagick_light
    less
    # p7zip
    haskell7103Packages.pandoc
    parallel
    pinentry
    pv
    rlwrap
    silver-searcher
    haskell7103Packages.simple-mirror
    sqlite
    stow
    time
    tree
    unrar
    unzip
    watch
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

      (haskell.lib.dontCheck pkgs.haskell7103Packages.git-annex)
      haskell7103Packages.git-monitor
      pkgs.gitAndTools.gitFull
      pkgs.gitAndTools.gitflow
      ## pkgs.gitAndTools.hub
      pkgs.gitAndTools.topGit
      pkgs.gitAndTools.git-imerge

      haskell7103Packages.git-all
    ];
  };

networkToolsEnv = pkgs.buildEnv {
  name = "networkTools";
  paths = [
    aria
    autossh
    cacert
    #httrack
    iperf
    mtr
    openssh
    openssl
    # pdnsd does not build with IPv6 on Darwin
    (super.stdenv.lib.overrideDerivation pdnsd (attrs: { configureFlags = []; }))
    rsync
    socat2pre
    httptunnel
    stunnel
    tor torsocks
    # yubikey-personalization
    wget
    youtubeDL ffmpeg
  ];
};

mailToolsEnv = pkgs.buildEnv {
  name = "mailTools";
  paths = [
    pkgs.dovecot22 or dovecot
    dovecot_pigeonhole
    leafnode
    fetchmail
    imapfilter
    contacts
  ];
};

publishToolsEnv = pkgs.buildEnv {
  name = "publishTools";
  paths = [
    texLiveFull
    ghostscript
    libpng
    haskell7103Packages.newartisans
  ];
};

serviceToolsEnv = pkgs.buildEnv {
  name = "serviceTools";
  paths = [
    #nginx
    postgresql
    redis
    #mysql
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
    python27Packages.certifi
  ];
};

rubyToolsEnv = pkgs.buildEnv {
  name = "rubyTools";
  paths = [
    ruby
  ];
};

buildToolsEnv = pkgs.buildEnv {
  name = "buildTools";
  paths = [
    ninja
    global idutils ctags
    autoconf automake114x libtool pkgconfig
    cvs #cvsps
    darcs
    diffstat
    doxygen
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
    clang llvm boost libcxx
    libxml2
    # isabelle
    ott
    gnumake
    guile
    compcert # verasco
    # rustc
    sbcl # acl2
    sloccount
    yuicompressor
  ];
 };

myCoq84 = super.callPackage ~/.nixpkgs/coq84.nix {
  inherit (ocamlPackages_4_01_0) ocaml findlib lablgtk;
  camlp5 = ocamlPackages_4_01_0.camlp5_transitional;
};

coq84Env = pkgs.myEnvFun {
  name = "coq84";
  buildInputs = [
    ocaml
    ocamlPackages.camlp5_transitional
    coq
    coqPackages.flocq
    coqPackages.mathcomp
    coqPackages.ssreflect
    coqPackages.QuickChick
    coqPackages.tlc
    coqPackages.ynot
    prooftree
  ];
};

coq85Env = pkgs.myEnvFun {
  name = "coq85";
  buildInputs =
    [ ocaml ocamlPackages.camlp5_transitional
      coq_8_5
      coqPackages_8_5.ssreflect
      coqPackages_8_5.mathcomp
    ];
};

coqHEADEnv = pkgs.myEnvFun {
  name = "coqHEAD";
  buildInputs = [
    ocaml
    ocamlPackages.camlp5_transitional
    coq_HEAD
    (coqPackages.mathcomp.override { coq = coq_HEAD; })
    (coqPackages.ssreflect.override { coq = coq_HEAD; })
  ];
};

agdaEnv = pkgs.myEnvFun {
  name = "agda";
  buildInputs = [
    haskell7103Packages.Agda
    haskell7103Packages.Agda-executable
  ];
};

gameToolsEnv = pkgs.buildEnv {
  name = "gameTools";
  paths = [
    # chessdb
    craftyFull
    # eboard
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

ghc710Env = pkgs.myEnvFun {
  name = "ghc710";
  buildInputs = with haskell7103Packages; [
    (haskell7103Packages.ghcWithPackages my-packages-7103)
    (hoogle-local my-packages-7103 haskell7103Packages)

    alex happy
    cabal-install
    ghc-core
    ghc-mod
    hlint
    simple-mirror
    hasktags
    djinn mueval
    pointfree
    threadscope
    timeplot splot
    # lambdabot
    # idris
    # liquidhaskell
  ];
};

hoogle-local = f: pkgs: with pkgs;
  import ~/.nixpkgs/local.nix {
    inherit stdenv hoogle rehoo ghc;
    packages = f pkgs ++ [ trifecta ];
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

my-packages-7103 = hp: with hp; [
  Boolean
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
  # criterion                # jww (2016-07-08): NYI
  cryptohash
  css-text
  curl
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
  free
  fsnotify
  ghc-paths
  graphviz
  groups
  hamlet
  hashable
  hashtables
  haskeline
  haskell-lexer
  haskell-src
  haskell-src-exts
  hfsevents
  hoopl
  hslogger
  hspec
  hspec-expectations
  hspec-wai
  html
  http-client
  http-date
  http-types
  io-memoize
  io-storage
  io-streams
  json
  kan-extensions
  keys
  language-c
  language-java
  language-javascript
  lattices
  lens
  lens-action
  lens-aeson
  lens-datetime
  lens-family
  lens-family-core
  lifted-async
  lifted-base
  linear
  list-extras
  list-t
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
  pipes-files
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
  safe
  sbv
  scalpel
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
  streaming
  streaming-bytestring
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
  total
  transformers
  transformers-base
  turtle
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
