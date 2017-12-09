{ pkgs }: {

packageOverrides = super: let self = super.pkgs; in with self; rec {

myHaskellPackages = libProf: self: super:
  with pkgs.haskell.lib; let pkg = self.callPackage; in rec {

  # Personal packages

  async-pool       = pkg ~/src/async-pool {};
  bytestring-fiat  = pkg ~/src/bytestring/extract {};
  c2hsc            = pkg ~/src/c2hsc {};
  categorical      = dontCheck (dontHaddock (pkg ~/src/categorical {}));
  commodities      = pkg ~/src/ledger4/commodities {};
  consistent       = dontCheck (pkg ~/src/consistent {});
  coq-haskell      = pkg ~/src/coq-haskell {};
  extract          = dontHaddock (pkg ~/src/bytestring/extract {});
  fuzzcheck        = pkg ~/src/fuzzcheck {};
  git-all          = pkg ~/src/git-all {};
  git-du           = pkg ~/src/git-du {};
  git-monitor      = pkg ~/src/gitlib/git-monitor {};
  gitlib           = pkg ~/src/gitlib/gitlib {};
  gitlib-cmdline   = pkg ~/src/gitlib/gitlib-cmdline { git = gitAndTools.git; };
  gitlib-hit       = pkg ~/src/gitlib/gitlib-hit {};
  gitlib-libgit2   = pkg ~/src/gitlib/gitlib-libgit2 {};
  gitlib-test      = pkg ~/src/gitlib/gitlib-test {};
  hierarchy        = doJailbreak (pkg ~/src/hierarchy {});
  hlibgit2         = dontCheck (pkg ~/src/gitlib/hlibgit2 {});
  hnix             = pkg ~/src/hnix {};
  hours            = pkg ~/src/hours {};
  ipcvar           = dontCheck (pkg ~/src/ipcvar {});
  linearscan       = pkg ~/src/linearscan {};
  linearscan-hoopl = dontCheck (pkg ~/src/linearscan-hoopl {});
  logging          = pkg ~/src/logging {};
  monad-extras     = pkg ~/src/monad-extras {};
  parsec-free      = pkg ~/src/parsec-free {};
  pipes-async      = pkg ~/src/pipes-async {};
  pipes-files      = dontCheck (pkg ~/src/pipes-files {});
  pushme           = doJailbreak (pkg ~/src/pushme {});
  recursors        = doJailbreak (pkg ~/src/recursors {});
  runmany          = pkg ~/src/runmany {};
  simple-mirror    = pkg ~/src/hackage-mirror {};
  sitebuilder      = pkg ~/doc/sitebuilder { yuicompressor = pkgs.yuicompressor; };
  sizes            = pkg ~/src/sizes {};
  una              = pkg ~/src/una {};
  z3cat            = pkg ~/src/z3cat {};

  putting-lenses-to-work = pkg ~/doc/papers/putting-lenses-to-work {};

  # Open Source

  concat-classes   = dontCheck (dontHaddock (pkg ~/oss/concat/classes {}));
  concat-examples  = dontCheck (dontHaddock (pkg ~/oss/concat/examples {}));
  concat-plugin    = dontCheck (dontHaddock (pkg ~/oss/concat/plugin {}));
  hs-to-coq        = pkg ~/oss/hs-to-coq/hs-to-coq {};

  # BAE packages

  harness             = 
    dontHaddock (pkg ~/bae/autofocus-deliverable/rings-dashboard/mitll-harness {});
  rings-dashboard-api = 
    dontHaddock (pkg ~/bae/autofocus-deliverable/rings-dashboard/rings-dashboard-api {});
  comparator          = dontHaddock (pkg ~/bae/autofocus-deliverable/xhtml/comparator {});
  generator           = dontHaddock (pkg ~/bae/autofocus-deliverable/xhtml/generator {});
  rings-dashboard     = dontHaddock (pkg ~/bae/autofocus-deliverable/rings-dashboard {});

  hmon                = dontHaddock (pkg ~/bae/atif-deliverable/monitors/hmon {});
  hsmedl              = dontHaddock (pkg ~/bae/atif-deliverable/monitors/hmon/hsmedl {});

  solver              = dontCheck (doJailbreak (dontHaddock (pkg ~/bae/concerto/solver {})));

  # Hackage overrides

  Agda                     = dontHaddock super.Agda;
  Glob                     = dontCheck super.Glob;
  Diff                     = dontCheck super.Diff;
  bindings-DSL             = pkg ~/oss/bindings-DSL {};
  bindings-posix           = pkg ~/oss/bindings-DSL/bindings-posix {};
  diagrams-rasterific      = doJailbreak super.diagrams-rasterific;
  foundation               = dontCheck super.foundation;
  blaze-builder-enumerator = doJailbreak super.blaze-builder-enumerator;
  compressed               = doJailbreak super.compressed;
  derive-storable          = dontCheck super.derive-storable;
  freer-effects            = pkg ~/oss/freer-effects {};
  liquidhaskell            = doJailbreak super.liquidhaskell;
  hakyll                   = doJailbreak super.hakyll;
  pandoc-citeproc          = pkg ~/oss/pandoc-citeproc {};
  pipes-binary             = doJailbreak super.pipes-binary;
  pipes-zlib               = doJailbreak (dontCheck super.pipes-zlib);
  time-recurrence          = doJailbreak super.time-recurrence;
  timeparsers              = dontCheck (pkg ~/oss/timeparsers {});
  testing-feat             = doJailbreak super.testing-feat;

  mkDerivation = args: super.mkDerivation (args // {
    # src = pkgs.fetchurl {
    #   url = "file:///Volumes/Hackage/package/${pkg.pname}-${pkg.version}.tar.gz";
    #   inherit (pkg) sha256;
    # };
    enableLibraryProfiling = libProf;
    enableExecutableProfiling = false;
  });
};

haskPkgs = haskell802Packages;
haskellPackages = haskPkgs;

haskell802Packages = super.haskell.packages.ghc802.override {
  overrides = myHaskellPackages false;
};
profiledHaskell802Packages = super.haskell.packages.ghc802.override {
  overrides = myHaskellPackages true;
};

ghc80Env = pkgs.myEnvFun {
  name = "ghc80";
  buildInputs = with pkgs.haskell.lib; with haskell802Packages; [
    (ghcWithHoogle ((import ~/src/hoogle-local/package-list.nix) pkgs))
    alex happy cabal-install
    ghc-core
    hlint
    stylish-haskell
    ghc-mod
    hdevtools
    pointfree
    hasktags
    hpack
    c2hsc
    simple-mirror
    djinn mueval
    lambdabot
    # threadscope
    timeplot splot
    # liquidhaskell
    # idris
    Agda

    # Personal packages

    hnix
    async-pool
    categorical
    commodities
    concat-classes
    concat-plugin
    concat-examples
    consistent
    fuzzcheck
    gitlib
    gitlib-cmdline
    gitlib-libgit2
    gitlib-sample
    gitlib-test
    # gitlib-hit
    # gitlib-lens
    # gitlib-s3
    hierarchy
    hlibgit2
    ipcvar
    linearscan
    linearscan-hoopl
    logging
    monad-extras
    pipes-async
    pipes-files
    recursors
    z3cat
  ];
};

ghc80ProfEnv = pkgs.myEnvFun {
  name = "ghc80prof";
  buildInputs = with pkgs.haskell.lib; with profiledHaskell802Packages; [
    (ghcWithHoogle ((import ~/src/hoogle-local/package-list.nix) pkgs))
    alex happy cabal-install
    ghc-core
    hlint
    stylish-haskell
    ghc-mod
    hdevtools
    pointfree
    hasktags
    hpack
    c2hsc
    simple-mirror
    djinn mueval
    lambdabot
    # threadscope
    timeplot splot
    # liquidhaskell
    # idris
    Agda

    # Personal packages

    hnix
    async-pool
    categorical
    commodities
    concat-classes
    concat-plugin
    concat-examples
    consistent
    fuzzcheck
    gitlib
    gitlib-cmdline
    gitlib-libgit2
    gitlib-sample
    gitlib-test
    # gitlib-hit
    # gitlib-lens
    # gitlib-s3
    hierarchy
    hlibgit2
    ipcvar
    linearscan
    linearscan-hoopl
    logging
    monad-extras
    pipes-async
    pipes-files
    recursors
    z3cat
  ];
};

haskell822Packages = super.haskell.packages.ghc822.override {
  overrides = myHaskellPackages false;
};
profiledHaskell822Packages = super.haskell.packages.ghc822.override {
  overrides = myHaskellPackages true;
};

ghc82Env = pkgs.myEnvFun {
  name = "ghc82";
  buildInputs = with pkgs.haskell.lib; with haskell822Packages; [
    (ghcWithHoogle ((import ~/src/hoogle-local-82/package-list.nix) pkgs))
    alex happy # cabal-install
    ghc-core
    hlint
    stylish-haskell
    # ghc-mod
    # hdevtools
    (doJailbreak pointfree)
    hasktags
    hpack
    c2hsc
    simple-mirror
    djinn mueval
    lambdabot
    # threadscope
    # timeplot splot
    # liquidhaskell
    # idris
    Agda

    # # Personal packages

    hnix
    async-pool
    # categorical
    commodities
    # concat-classes
    # concat-plugin
    # concat-examples
    # consistent
    fuzzcheck
    gitlib
    # gitlib-cmdline
    # gitlib-libgit2
    gitlib-sample
    gitlib-test
    # gitlib-hit
    # gitlib-lens
    # gitlib-s3
    # hierarchy
    hlibgit2
    ipcvar
    linearscan
    linearscan-hoopl
    logging
    monad-extras
    pipes-async
    # pipes-files
    recursors
    # z3cat
  ];
};

ghc82ProfEnv = pkgs.myEnvFun {
  name = "ghc82prof";
  buildInputs = with pkgs.haskell.lib; with profiledHaskell822Packages; [
    (ghcWithHoogle ((import ~/src/hoogle-local-82/package-list.nix) pkgs))
    alex happy # cabal-install
    ghc-core
    hlint
    stylish-haskell
    # ghc-mod
    # hdevtools
    (doJailbreak pointfree)
    hasktags
    hpack
    c2hsc
    simple-mirror
    djinn mueval
    lambdabot
    # threadscope
    # timeplot splot
    # liquidhaskell
    # idris
    Agda

    # # Personal packages

    hnix
    async-pool
    # categorical
    commodities
    # concat-classes
    # concat-plugin
    # concat-examples
    # consistent
    fuzzcheck
    gitlib
    # gitlib-cmdline
    # gitlib-libgit2
    gitlib-sample
    gitlib-test
    # gitlib-hit
    # gitlib-lens
    # gitlib-s3
    # hierarchy
    hlibgit2
    ipcvar
    linearscan
    linearscan-hoopl
    logging
    monad-extras
    pipes-async
    # pipes-files
    recursors
    # z3cat
  ];
};

haskellHEADPackages = super.haskell.packages.ghcHEAD.override {
  overrides = myHaskellPackages false;
};
profiledHaskellHEADPackages = super.haskell.packages.ghcHEAD.override {
  overrides = myHaskellPackages true;
};

ghcHEADEnv = pkgs.myEnvFun {
  name = "ghcHEAD";
  buildInputs = with haskellHEADPackages; [
    haskellHEADPackages.ghc
    alex happy # cabal-install
    ghc-core
  ];
};

haskellFilterSource = paths: src: builtins.filterSource (path: type:
    let baseName = baseNameOf path; in
    !( type == "directory"
       && builtins.elem baseName ([".git" ".cabal-sandbox" "dist"] ++ paths))
    &&
    !( type == "unknown"
       || stdenv.lib.hasSuffix ".hdevtools.sock" path
       || stdenv.lib.hasSuffix ".sock" path
       || stdenv.lib.hasSuffix ".hi" path
       || stdenv.lib.hasSuffix ".hi-boot" path
       || stdenv.lib.hasSuffix ".o" path
       || stdenv.lib.hasSuffix ".o-boot" path
       || stdenv.lib.hasSuffix ".dyn_o" path
       || stdenv.lib.hasSuffix ".p_o" path))
  src;

ledger_HEAD = super.callPackage ~/src/ledger {};
ledger_HEAD_python3 = super.callPackage ~/src/ledger {
  boost = self.boost_with_python3;
};

ledgerPy2Env = pkgs.myEnvFun {
  name = "ledger-py2";
  buildInputs = [
    cmake boost gmp mpfr libedit python texinfo gnused ninja clang doxygen
  ];
};

boost_with_python3 = super.boost160.override {
  python = python3;
};

ledgerPy3Env = pkgs.myEnvFun {
  name = "ledger-py3";
  buildInputs = [
    cmake boost_with_python3 gmp mpfr libedit python texinfo gnused ninja
    clang doxygen
  ];
};

ringsEnv = pkgs.myEnvFun {
  name = "rings";
  buildInputs = [
    autoconf automake libtool pkgconfig clang llvm rabbitmq-c libconfig
    cmake lp_solve

    haskPkgs.hmon
    haskPkgs.hsmedl
    haskPkgs.rings-dashboard-api
  ];
};

concertoEnv = pkgs.myEnvFun {
  name = "concerto";
  buildInputs = [
    autoconf automake libtool pkgconfig clang llvm libconfig cmake
    fftw fftwFloat

    haskPkgs.concat-plugin
    haskPkgs.concat-classes
    haskPkgs.categorical
    haskPkgs.solver
    haskPkgs.silently
  ];
};

emacs = emacs25;

emacs25 = super.callPackage ~/.nixpkgs/emacs25.nix {
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

emacs25_test = super.stdenv.lib.overrideDerivation emacs25 (attrs: {
  doCheck = true;
});

emacs25Env = pkgs.myEnvFun {
  name = "emacs25";
  buildInputs = with emacsPackagesNgGen emacs; [ emacs25 ];
};

emacs26debug = super.callPackage ~/.nixpkgs/emacs26debug.nix {
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

emacs26 = super.callPackage ~/.nixpkgs/emacs26.nix {
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

emacs26_test = super.stdenv.lib.overrideDerivation emacs26 (attrs: {
  doCheck = true;
});

emacs26Env = pkgs.myEnvFun {
  name = "emacs26";
  buildInputs = with emacsPackagesNgGen emacs; [ 
    emacs26 
  ];
};

emacs26DebugEnv = pkgs.myEnvFun {
  name = "emacs26debug";
  buildInputs = with emacsPackagesNgGen emacs; [ 
    emacs26debug 
  ];
};

emacsHEAD = super.callPackage ~/.nixpkgs/emacsHEAD.nix {
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

emacsHEAD_test = super.stdenv.lib.overrideDerivation emacsHEAD (attrs: {
  doCheck = true;
});

emacsHEADEnv = pkgs.myEnvFun {
  name = "emacsHEAD";
  buildInputs = with emacsPackagesNgGen emacs; [
    (emacsHEAD.override {
       appName = "ERC";
       bundleName = "nextstep/ERC.app";
       iconFile = "/Users/johnw/.nixpkgs/Chat.icns";
     })
  ];
};

x11ToolsEnv = pkgs.buildEnv {
  name = "x11Tools";
  paths = [ xquartz xorg.xhost xorg.xauth ratpoison ];
};

systemToolsEnv = pkgs.buildEnv {
  name = "systemTools";
  paths = [
    aspell
    aspellDicts.en
    bashInteractive
    bash-completion
    nix-bash-completions
    ctop
    exiv2
    findutils
    fzf
    gawk
    gnugrep
    gnupg paperkey
    gnuplot
    gnused
    gnutar
    (haskell.lib.justStaticExecutables haskPkgs.hours)
    (haskell.lib.justStaticExecutables haskPkgs.pandoc)
    (haskell.lib.justStaticExecutables haskPkgs.pushme)
    (haskell.lib.justStaticExecutables haskPkgs.runmany)
    (haskell.lib.justStaticExecutables haskPkgs.simple-mirror)
    (haskell.lib.justStaticExecutables haskPkgs.sizes)
    (haskell.lib.justStaticExecutables haskPkgs.una)
    imagemagick_light
    jenkins
    less
    multitail
    renameutils
    p7zip
    parallel
    pinentry_mac
    postgresql96
    pv
    # qemu
    ripgrep
    rlwrap
    screen
    silver-searcher
    srm
    sqlite
    stow
    time
    tmux
    tree
    unrar
    unzip
    watch
    xz
    z3
    cvc4
    zip
    zsh
  ];
};

ghi = buildRubyGem rec {
  inherit ruby;

  name = "${gemName}-${version}";
  gemName = "ghi";
  version = "1.2.0";

  sha256 = "05cirb2ndhh0i8laqrfwijprqy63gmxmd8agqkayvqpjs26gdbwi";

  buildInputs = [bundler];
};

gist = buildRubyGem rec {
  inherit ruby;

  name = "${gemName}-${version}";
  gemName = "gist";
  version = "4.5.0";

  sha256 = "0k9bgjdmnr14whmjx6c8d5ak1dpazirj96hk5ds69rl5d9issw0l";

  buildInputs = [bundler];
};

gitToolsEnv = pkgs.buildEnv {
  name = "gitTools";
  paths = [
    diffstat
    diffutils
    ghi
    gist
    gitRepo
    gitAndTools.git-imerge
    gitAndTools.gitFull
    gitAndTools.gitflow
    gitAndTools.hub
    gitAndTools.tig
    gitAndTools.git-annex
    gitAndTools.git-annex-remote-rclone
    (haskell.lib.justStaticExecutables haskPkgs.git-all)
    (haskell.lib.justStaticExecutables haskPkgs.git-monitor)
    patch
    patchutils
  ];
};

# pdnsd does not build with IPv6 on Darwin
pdnsd = super.stdenv.lib.overrideDerivation super.pdnsd (attrs: {
  configureFlags = [];
});

backblaze-b2 = super.callPackage ~/.nixpkgs/backblaze.nix {};

networkToolsEnv = pkgs.buildEnv {
  name = "networkTools";
  paths = [
    aria2
    backblaze-b2
    cacert
    httrack
    mercurialFull
    iperf
    nmap
    lftp
    mtr
    dnsutils
    openssh
    openssl
    pdnsd
    privoxy
    rclone
    rsync
    sipcalc
    socat2pre
    spiped
    w3m
    wget
    youtube-dl
    znc
  ];
};

mailToolsEnv = pkgs.buildEnv {
  name = "mailTools";
  paths = [
    (pkgs.dovecot22 or dovecot) dovecot_pigeonhole
    contacts
    fetchmail
    imapfilter
    leafnode
    msmtp
  ];
};

jsToolsEnv = pkgs.buildEnv {
  name = "jsTools";
  paths = [
    jq
    nodejs
    nodePackages.eslint
    nodePackages.csslint
    nodePackages.jsontool
    jquery
  ];
};

pythonToolsEnv = pkgs.buildEnv {
  name = "pythonTools";
  paths = [
    python3
    python27
    pythonDocs.pdf_letter.python27
    pythonDocs.html.python27
    python27Packages.setuptools
    python27Packages.pygments
    python27Packages.certifi
  ];
};

idutils = super.stdenv.lib.overrideDerivation super.idutils (attrs: {
  doCheck = false;
});

langToolsEnv = pkgs.buildEnv {
  name = "langTools";
  paths = [
    global
    (haskell.lib.justStaticExecutables haskPkgs.bench)
    (haskell.lib.justStaticExecutables haskPkgs.hpack)
    autoconf automake libtool pkgconfig
    clang libcxx libcxxabi llvm
    cmake ninja gnumake
    cabal2nix cabal-install
    ctags
    rtags
    gmp mpfr
    htmlTidy
    idutils
    ott
    sbcl
    sloccount
    verasco
  ];
 };

coq_8_4  = super.coq_8_4.override { csdp = null; };
coq_8_5  = super.coq_8_5.override { csdp = null; };
coq_8_6  = super.coq_8_6.override { csdp = null; };
coq_8_7  = super.coq_8_7.override { csdp = null; };
coq_HEAD = super.callPackage ~/.nixpkgs/coqHEAD.nix {};

coq84Env = pkgs.myEnvFun {
  name = "coq84";
  buildInputs = [
    ocaml ocamlPackages.camlp5_transitional
    coq_8_4
    prooftree
  ] ++ (with coqPackages_8_4; [
    interval
    mathcomp
    ssreflect
  ]);
};

coq85Env = pkgs.myEnvFun {
  name = "coq85";
  buildInputs = [
    ocaml ocamlPackages.camlp5_transitional
    coq_8_5
  ] ++ (with coqPackages_8_5; [
    coq-ext-lib
    dpdgraph
    interval
    mathcomp
    ssreflect
  ]);
};

coq86Env = pkgs.myEnvFun {
  name = "coq86";
  buildInputs = [
    ocaml ocamlPackages.camlp5_transitional
    ocamlPackages.findlib
    ocamlPackages.menhir
    coq_8_6
    coq2html
  ] ++ (with coqPackages_8_6; [
    CoLoR
    QuickChick
    autosubst
    coq-ext-lib
    coquelicot
    dpdgraph
    equations
    flocq
    heq
    interval
    math-classes
    mathcomp
    metalib
    paco
    ssreflect
  ]);
};

coq87Env = pkgs.myEnvFun {
  name = "coq87";
  buildInputs = [
    ocaml ocamlPackages.camlp5_transitional
    ocamlPackages.findlib
    ocamlPackages.menhir
    coq_8_7
    coq2html
    compcert
  ] ++ (with coqPackages_8_7; [
    CoLoR
    QuickChick
    autosubst
    bignums
    coq-ext-lib
    coquelicot
    dpdgraph
    equations
    flocq
    heq
    interval
    math-classes
    mathcomp
    metalib
    paco
    ssreflect
  ]);
};

coqHEADEnv = pkgs.myEnvFun {
  name = "coqHEAD";
  buildInputs = [
    ocaml ocamlPackages.camlp5_transitional
    coq_HEAD
  ];
};

publishToolsEnv = pkgs.buildEnv {
  name = "publishTools";
  paths = [
    hugo
    biber
    dot2tex
    doxygen
    graphviz-nox
    highlight
    poppler
    sourceHighlight
    texinfo
    yuicompressor
    (haskell.lib.justStaticExecutables haskPkgs.lhs2tex)
    (haskell.lib.justStaticExecutables haskPkgs.sitebuilder)
    (texlive.combine {
       inherit (texlive) scheme-full texdoc latex2e-help-texinfo;
       pkgFilter = pkg:
          pkg.tlType == "run"
       || pkg.tlType == "bin"
       || pkg.pname == "latex2e-help-texinfo";
     })
  ];
};

withSrc = path: deriv: 
  super.stdenv.lib.overrideDerivation deriv (attrs: { src = path; });

withName = arg: deriv: 
  super.stdenv.lib.overrideDerivation deriv (attrs: { name = arg; });

};

allowUnfree = true;
allowBroken = true;

}
