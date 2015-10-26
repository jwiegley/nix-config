{ pkgs }: {

# replaceStdenv = { pkgs }: pkgs.allStdenvs.stdenvDarwinPure;

packageOverrides = super: let self = super.pkgs; in with self; rec {

myHaskellPackages = hp: hp.override {
  overrides = self: super: with pkgs.haskell-ng.lib; {
    coq-haskell      = self.callPackage ~/src/linearscan/Hask {};
    linearscan       = self.callPackage ~/src/linearscan {};
    linearscan-hoopl = self.callPackage ~/src/linearscan-hoopl {};
  
    newartisans = self.callPackage ~/doc/newartisans {
      yuicompressor = pkgs.yuicompressor;
    };
  
    ghc-issues      = self.callPackage ~/src/ghc-issues {};
    c2hsc           = dontCheck (self.callPackage ~/src/c2hsc {});
    git-all         = self.callPackage ~/src/git-all {};
    hours           = self.callPackage ~/src/hours {};
    pushme          = self.callPackage ~/src/pushme {};
    rehoo           = self.callPackage ~/src/rehoo {};
    simple-mirror   = self.callPackage ~/src/hackage-mirror {};
    sizes           = self.callPackage ~/src/sizes {};
    una             = self.callPackage ~/src/una {};
    hierarchy       = self.callPackage ~/src/hierarchy {};
    pipes-files     = self.callPackage ~/src/pipes-files {};
    pipes-fusion    = self.callPackage ~/src/pipes-fusion {};
    fusion          = self.callPackage ~/src/fusion {};
    streaming-tests = self.callPackage ~/src/streaming-tests {};

    pipes           = self.callPackage ~/Contracts/OSS/Projects/pipes {};
    pipes-safe      = self.callPackage ~/Contracts/OSS/Projects/pipes-safe {};
  
    async-pool      = self.callPackage ~/src/async-pool {};
    bindings-DSL    = self.callPackage ~/oss/bindings-dsl {};
    commodities     = self.callPackage ~/src/ledger/new/commodities {};
    consistent      = self.callPackage ~/src/consistent {};
    find-conduit    = self.callPackage ~/src/find-conduit {};
    fuzzcheck       = self.callPackage ~/src/fuzzcheck {};
    github          = self.callPackage ~/src/github {};
    hnix            = self.callPackage ~/src/hnix {};
    ipcvar          = self.callPackage ~/src/ipcvar {};
    logging         = self.callPackage ~/src/logging {};
    monad-extras    = self.callPackage ~/src/monad-extras {};
    rest-client     = self.callPackage ~/src/rest-client {};
    simple-conduit  = self.callPackage ~/src/simple-conduit {};
  
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
  
    hdevtools       = self.callPackage ~/oss/hdevtools {};
  
    systemFileio    = dontCheck super.systemFileio;
    shake           = dontCheck super.shake;
    singletons      = dontCheck super.singletons;

    time-recurrence = dontCheck (self.callPackage ~/oss/time-recurrence {});
    timeparsers     = dontCheck (self.callPackage ~/oss/timeparsers {});
  };
};

haskell7102Packages = myHaskellPackages super.haskell-ng.packages.ghc7102;
profiledHaskell7102Packages = haskell7102Packages.override {
  overrides = self: super: {
    mkDerivation = args: super.mkDerivation (args // {
      enableLibraryProfiling = true;
      enableSharedExecutables = false;
    });
  };
};

haskell784Packages  = myHaskellPackages super.haskell-ng.packages.ghc784;
profiledHaskell784Packages = haskell784Packages.override {
  overrides = self: super: {
    mkDerivation = args: super.mkDerivation (args // {
      enableLibraryProfiling = true;
      enableSharedExecutables = false;
    });
  };
};

ledger = super.callPackage ~/src/ledger {};

emacsHEAD = super.callPackage ~/.emacs.d/devel {
  # use override to enable additional features
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
    pkgs.auctex
    emacs24Packages.proofgeneral
  ];
};

systemToolsEnv = pkgs.buildEnv {
  name = "systemTools";
  paths = [
    haskell7102Packages.pushme
    haskell7102Packages.sizes
    haskell7102Packages.una

    # ack
    # apg
    # cabextract
    # bashInteractive
    # bashCompletion
    exiv2
    findutils
    gnugrep
    gnupg
    gnuplot
    gnused
    gnutar
    graphviz
    haskell7102Packages.hours
    imagemagick_light
    less
    # nixbang
    p7zip
    haskell7102Packages.pandoc
    parallel
    pinentry
    pv
    rlwrap
    # screen
    silver-searcher
    haskell7102Packages.simple-mirror
    # reptyr
    sqlite
    stow
    time
    tree
    # unarj
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

      haskell7102Packages.git-annex
      # pkgs.haskell7102Packages.git-gpush
      haskell7102Packages.git-monitor
      pkgs.gitAndTools.gitFull
      pkgs.gitAndTools.gitflow
      # pkgs.gitAndTools.hub
      pkgs.gitAndTools.topGit
      pkgs.gitAndTools.git-imerge

      pkgs.haskell7102Packages.git-all
    ];
  };

networkToolsEnv = pkgs.buildEnv {
  name = "networkTools";
  paths = [
    # ansible
    #arcanist
    # aria
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
    youtubeDL ffmpeg
    # znc
    # openssh
  ];
};

mailToolsEnv = pkgs.buildEnv {
  name = "mailTools";
  paths = [
    dovecot22
    dovecot_pigeonhole
    leafnode
    fetchmail
    # procmail
    # imapfilter
    # mairix
    # mutt
    # msmtp
    # lbdb
    contacts
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
    # poppler poppler_data
    libpng
    haskell7102Packages.newartisans
  ];
};

serviceToolsEnv = pkgs.buildEnv {
  name = "serviceTools";
  paths = [
    # nginx
    # postgresql
    # redis
    pdnsd
    # mysql
    # nodejs
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
  paths = [ 
    # ruby_2_1_2 
  ];
};

buildToolsEnv = pkgs.buildEnv {
  name = "buildTools";
  paths = [
    ninja
    global idutils
    # autoconf automake114x
    # bazaar bazaarTools
    # ccache
    # cvs cvsps
    # darcs
    diffstat
    # doxygen
    # fcgi
    # flex
    htmlTidy
    lcov
    # mercurial
    patch
    # subversion
  ];
};

langToolsEnv = pkgs.buildEnv {
  name = "langTools";
  paths = [
    # clang llvm boost libcxx
    # ott isabelle
    gnumake
    # guile
    # compcert #verasco
    # fsharp
    # rustc
    # sbcl #acl2
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

coq84Env = pkgs.myEnvFun {
  name = "coq84";
  buildInputs = [
    ocaml
    ocamlPackages.camlp5_transitional
    coq
    # coqPackages.fiat coqPackages.bedrock
    coqPackages.mathcomp
    coqPackages.ssreflect
    coqPackages.QuickChick
    # coqPackages.tlc
    # coqPackages.ynot
    prooftree
  ];
};

coq85Env = pkgs.myEnvFun {
  name = "coq85";
  buildInputs = 
    let mpath = /Users/johnw/.nix-defexpr/nixpkgs/pkgs/development/coq-modules; in
    let ssreflect_8_5 = callPackage (mpath + /ssreflect/generic.nix) {
        coq = coq_8_5;
        src = fetchurl {
          url = http://ssr.msr-inria.inria.fr/FTP/ssreflect-1.5.coq85beta2.tar.gz;
          sha256 = "084l9xd5vgb8jml0dkm66g8cil5rsf04w821pjhn2qk9mdbwaagf";
        };
        patches = [ (mpath + /ssreflect/threads.patch) ];
      }; in

    let mathcomp_8_5 = callPackage (mpath + /mathcomp/generic.nix) {
        coq = coq_8_5;
        src = fetchurl {
          url = http://ssr.msr-inria.inria.fr/FTP/mathcomp-1.5.coq85beta2.tar.gz;
          sha256 = "03bnq44ym43x8shi7whc02l0g5vy6rx8f1imjw478chlgwcxazqy";
        };
        ssreflect = ssreflect_8_5;
      }; in

    [ ocaml ocamlPackages.camlp5_transitional
      coq_8_5 mathcomp_8_5 ssreflect_8_5
      prooftree
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
    (haskell784Packages.ghcWithPackages my-packages-784)
    # (hoogle-local my-packages-784 haskell784Packages)

    alex happy
    cabal-install
    ghc-core
    # ghc-mod
    hdevtools
    hlint
    hasktags
    cabal-meta
    # lambdabot djinn mueval
    pointfree
    # idris
    # threadscope
    # timeplot splot
    # liquidhaskell
  ];
};

ghc7102Env = pkgs.myEnvFun {
  name = "ghc7102";
  buildInputs = with haskell7102Packages; [
    (haskell7102Packages.ghcWithPackages my-packages-7102)
    (hoogle-local my-packages-7102 haskell7102Packages)

    alex happy
    cabal-install
    ghc-core
    ghc-mod
    # hdevtools
    hlint
    simple-mirror
    hasktags
    cabal-meta
    # lambdabot djinn mueval
    idris
    # threadscope
    # timeplot splot
    liquidhaskell
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

my-packages-784 = hp: with hp; [
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
  # attoparsec-conduit
  attoparsec-enumerator
  base-unicode-symbols
  base16-bytestring
  base64-bytestring
  basic-prelude
  bifunctors
  bindings-DSL
  blaze-builder
  # blaze-builder-conduit
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
  # cereal-conduit
  charset
  chunked-data
  # classy-prelude
  # classy-prelude-conduit
  cmdargs
  comonad
  comonad-transformers
  # compdata
  composition
  compressed
  cond
  # conduit
  # conduit-combinators
  # conduit-extra
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
  # dns
  doctest
  doctest-prop
  either
  enclosed-exceptions
  # errors
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
  # linearscan
  # linearscan-hoopl
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
  singletons
  speculation
  split
  spoon
  stm
  stm-chans
  stm-stats
  #streaming
  #streaming-bytestring
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
  # these
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
  # yaml
  zippers
  zlib
];

my-packages-7102 = hp: with hp; [
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
  # errors
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
  # linearscan
  # linearscan-hoopl
  list-extras
  list-t
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
  # singletons
  speculation
  split
  spoon
  stm
  stm-chans
  stm-stats
  #streaming
  #streaming-bytestring
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
  # these
  # thyme
  time
  # time-recurrence
  # timeparsers
  total
  transformers
  transformers-base
  turtle
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
