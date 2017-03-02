{ pkgs }: {

packageOverrides = super: let self = super.pkgs; in with self; rec {

myHaskellPackages = libProf: self: super:
  with pkgs.haskell.lib; let pkg = self.callPackage; in rec {

  ## Personal packages

  async-pool        = pkg ~/src/async-pool {};
  bytestring-fiat   = pkg ~/src/bytestring/src {};
  c2hsc             = dontCheck (pkg ~/src/c2hsc {});
  commodities       = pkg ~/src/old/ledger4/commodities {};
  consistent        = dontCheck (pkg ~/src/old/consistent {});
  coq-haskell       = pkg ~/src/coq-haskell {};
  emacs-bugs        = pkg ~/src/emacs-bugs {};
  fuzzcheck         = pkg ~/src/old/fuzzcheck {};
  ghc-issues        = pkg ~/src/ghc-issues {};
  git-all           = pkg ~/src/git-all {};
  git-du            = pkg ~/src/git-du {};
  git-gpush         = pkg ~/src/gitlib/git-gpush {};
  git-monitor       = pkg ~/src/gitlib/git-monitor {};
  gitlib            = pkg ~/src/gitlib/gitlib {};
  gitlib-cmdline    = pkg ~/src/gitlib/gitlib-cmdline { git = gitAndTools.git; };
  gitlib-hit        = pkg ~/src/gitlib/gitlib-hit {};
  gitlib-libgit2    = pkg ~/src/gitlib/gitlib-libgit2 {};
  gitlib-test       = pkg ~/src/gitlib/gitlib-test {};
  hierarchy         = doJailbreak (pkg ~/src/hierarchy {});
  hlibgit2          = dontCheck (pkg ~/src/gitlib/hlibgit2 {});
  hnix              = pkg ~/src/hnix {};
  hours             = pkg ~/src/hours {};
  ipcvar            = dontCheck (pkg ~/src/old/ipcvar {});
  linearscan        = pkg ~/src/linearscan {};
  linearscan-hoopl  = dontCheck (pkg ~/src/linearscan-hoopl {});
  logging           = pkg ~/src/logging {};
  monad-extras      = pkg ~/src/monad-extras {};
  parsec-free       = pkg ~/src/parsec-free {};
  pipes-async       = pkg ~/src/pipes-async {};
  pipes-files       = dontCheck (pkg ~/src/pipes-files {});
  pipes-fusion      = pkg ~/src/pipes-fusion {};
  pushme            = doJailbreak (pkg ~/src/pushme {});
  recursors         = doJailbreak (pkg ~/src/recursors {});
  rehoo             = pkg ~/src/rehoo {};
  runmany           = pkg ~/src/runmany {};
  shake-docker      = pkg ~/src/shake-docker {};
  simple-mirror     = pkg ~/src/hackage-mirror {};
  sitebuilder       = pkg ~/doc/sitebuilder { yuicompressor = pkgs.yuicompressor; };
  sizes             = pkg ~/src/sizes {};
  streaming-tests   = pkg ~/src/streaming-tests {};
  una               = pkg ~/src/una {};

  ### BAE packages

  extract           = dontHaddock (pkg ~/src/bytestring/extract {});
  hmon              = dontHaddock (pkg ~/bae/atif-deliverable/monitors/hmon {});
  hsmedl            = dontHaddock (pkg ~/bae/atif-deliverable/monitors/hmon/hsmedl {});
  apis              =
    dontHaddock
      (dontCheck
         (doJailbreak (pkg ~/bae/xhtml-deliverable/rings-dashboard/mitll/apis {})));
  parameter-dsl     =
    dontHaddock
      (dontCheck (pkg ~/bae/xhtml-deliverable/rings-dashboard/mitll/parameter-dsl {}));
  rings-dashboard   = dontHaddock (pkg ~/bae/xhtml-deliverable/rings-dashboard {});
  rings-dashboard-api =
    dontHaddock (pkg ~/bae/xhtml-deliverable/rings-dashboard/rings-dashboard-api {});
  comparator        = dontHaddock (pkg ~/bae/xhtml-deliverable/xhtml/comparator {});
  generator         = dontHaddock (pkg ~/bae/xhtml-deliverable/xhtml/generator {});

  ### Hackage overrides

  Agda                     = dontHaddock super.Agda;
  QuickCheck-safe          = doJailbreak super.QuickCheck-safe;
  bench                    = doJailbreak super.bench;
  blaze-builder-enumerator = doJailbreak super.blaze-builder-enumerator;
  compressed               = doJailbreak super.compressed;
  dependent-sum-template   = doJailbreak super.dependent-sum-template;
  derive                   = doJailbreak (pkg ~/oss/derive {});
  newtype-generics         = doJailbreak super.newtype-generics;
  hasktags                 = doJailbreak super.hasktags;
  idris                    = doJailbreak super.idris;
  language-ecmascript      = doJailbreak super.language-ecmascript;
  # liquid-fixpoint          = pkg ~/oss/liquidhaskell/liquid-fixpoint {};
  # liquiddesugar            = doJailbreak (pkg ~/oss/liquidhaskell/liquiddesugar {});
  # liquidhaskell            = pkg ~/oss/liquidhaskell {};
  machines                 = doJailbreak super.machines;
  pipes-binary             = doJailbreak super.pipes-binary;
  pipes-zlib               = doJailbreak (dontCheck super.pipes-zlib);
  pointfree                = doJailbreak super.pointfree;
  process-extras           = dontCheck super.process-extras;
  # servant                  = super.servant_0_10;
  # servant-client           = super.servant-client_0_10;
  # servant-docs             = super.servant-docs_0_10;
  # servant-foreign          = super.servant-foreign_0_10;
  # servant-server           = super.servant-server_0_10;
  time-recurrence          = doJailbreak super.time-recurrence;
  timeparsers              = dontCheck (pkg ~/oss/timeparsers {});
  total                    = doJailbreak super.total;

  mkDerivation = pkg: super.mkDerivation (pkg // {
    # src = pkgs.fetchurl {
    #   url = "file:///Volumes/Hackage/package/${pkg.pname}-${pkg.version}.tar.gz";
    #   inherit (pkg) sha256;
    # };
    enableLibraryProfiling = libProf;
    enableExecutableProfiling = false;
  });
};

haskPkgs = haskell802Packages;

haskell802Packages = super.haskell.packages.ghc802.override {
  overrides = myHaskellPackages false;
};
profiledHaskell802Packages = super.haskell.packages.ghc802.override {
  overrides = myHaskellPackages true;
};

ghc80Env = pkgs.myEnvFun {
  name = "ghc80";
  buildInputs = with haskell802Packages; [
    (ghcWithHoogle (import ~/src/hoogle-local/package-list.nix))
    alex happy cabal-install
    ghc-core
    hlint
    # pointfree
    hasktags
    simple-mirror
    ghc-mod
    djinn mueval
    # lambdabot
    # threadscope
    timeplot splot
    # liquidhaskell liquidhaskell-cabal
    idris
    # jhc
    Agda
  ];
};

ghc80ProfEnv = pkgs.myEnvFun {
  name = "ghc80prof";
  buildInputs = with profiledHaskell802Packages; [
    profiledHaskell802Packages.ghc
    alex happy cabal-install
    ghc-core
    hlint
    # pointfree
    hasktags
  ];
};

ghc80EmptyEnv = pkgs.myEnvFun {
  name = "ghc80empty";
  buildInputs = with profiledHaskell802Packages; [
    haskell802Packages.ghc
    alex happy cabal-install
    ghc-core
    hlint
    # pointfree
    hasktags
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

    haskPkgs.hmon
    haskPkgs.hsmedl
    haskPkgs.apis
    haskPkgs.parameter-dsl
    haskPkgs.rings-dashboard-api
    haskPkgs.comparator
  ];
};

emacs = emacsHEAD;

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

emacsHEADEnv = pkgs.myEnvFun {
  name = "emacsHEAD";
  buildInputs = with emacsPackagesNgGen emacs; [ emacsHEAD ];
};

emacsHEADAltEnv = pkgs.myEnvFun {
  name = "emacsHEADalt";
  buildInputs = with emacsPackagesNgGen emacs; [ emacsHEAD ];
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
    exiv2
    findutils
    gnugrep
    gnupg paperkey
    gnuplot
    gnused
    gnutar
    graphviz
    haskPkgs.hours
    haskPkgs.pandoc
    haskPkgs.pushme
    haskPkgs.runmany
    haskPkgs.simple-mirror
    haskPkgs.sizes
    haskPkgs.una
    imagemagick_light
    jenkins
    less
    multitail
    p7zip
    parallel
    pinentry_mac
    postgresql96
    pv
    ripgrep
    rlwrap
    screen
    silver-searcher
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
    git-lfs
    gitAndTools.diff-so-fancy
    gitAndTools.git-imerge
    gitAndTools.gitFull
    gitAndTools.gitflow
    gitAndTools.hub
    haskPkgs.git-all
    haskPkgs.git-monitor
    patch
    patchutils
  ];
};

# pdnsd does not build with IPv6 on Darwin
pdnsd = super.stdenv.lib.overrideDerivation super.pdnsd (attrs: {
  configureFlags = [];
});

networkToolsEnv = pkgs.buildEnv {
  name = "networkTools";
  paths = [
    aria2
    cacert
    httrack
    iperf
    mtr
    dnsutils
    openssh
    openssl
    pdnsd
    rsync
    socat2pre
    wget
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
    # msmtp
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
    python27Packages.ipython
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
    autoconf
    automake
    haskPkgs.bench
    cabal2nix
    clang
    ctags
    global
    gnumake
    htmlTidy
    idutils
    libtool
    llvm
    ott
    pkgconfig
    sbcl
    sloccount
    verasco
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
    ocaml ocamlPackages.camlp5_transitional
    coq_8_4
    coqPackages_8_4.flocq
    coqPackages_8_4.mathcomp
    coqPackages_8_4.ssreflect
    coqPackages_8_4.QuickChick
    coqPackages_8_4.tlc
    coqPackages_8_4.ynot
    prooftree
  ];
};

coq85Env = pkgs.myEnvFun {
  name = "coq85";
  buildInputs = [
    ocaml ocamlPackages.camlp5_transitional
    coq_8_5
    coqPackages_8_5.dpdgraph
    coqPackages_8_5.flocq
    coqPackages_8_5.mathcomp
    coqPackages_8_5.ssreflect
    coqPackages_8_5.coq-ext-lib
    compcert
  ];
};

coq86Env = pkgs.myEnvFun {
  name = "coq86";
  buildInputs = [
    ocaml ocamlPackages.camlp5_transitional
    coq_8_6
  ];
};

publishToolsEnv = pkgs.buildEnv {
  name = "publishTools";
  paths = [
    doxygen
    ffmpeg
    haskPkgs.sitebuilder
    texinfo
    texlive.combined.scheme-full
  ];
};

};

allowUnfree = true;
allowBroken = true;

}
