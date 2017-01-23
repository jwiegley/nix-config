{ pkgs }: {

packageOverrides = super: let self = super.pkgs; in with self; rec {

myHaskellPackages = libProf: self: super:
  with pkgs.haskell.lib; let pkg = self.callPackage; in rec {

  ## Personal packages

  async-pool        = pkg ~/src/async-pool {};
  bytestring-fiat   = pkg ~/src/bytestring/src {};
  c2hsc             = dontCheck (pkg ~/src/c2hsc {});
  commodities       = pkg ~/src/ledger4/commodities {};
  consistent        = pkg ~/src/consistent {};
  coq-haskell       = pkg ~/src/coq-haskell {};
  emacs-bugs        = pkg ~/src/emacs-bugs {};
  find-conduit      = pkg ~/src/find-conduit {};
  fusion            = pkg ~/src/fusion {};
  fuzzcheck         = pkg ~/src/fuzzcheck {};
  ghc-issues        = pkg ~/src/ghc-issues {};
  git-all           = pkg ~/src/git-all {};
  git-du            = pkg ~/src/git-du {};
  git-gpush         = pkg ~/src/gitlib/git-gpush {};
  git-monitor       = pkg ~/src/gitlib/git-monitor {};
  gitlib            = pkg ~/src/gitlib/gitlib {};
  gitlib-cmdline    = pkg ~/src/gitlib/gitlib-cmdline { git = gitAndTools.git; };
  gitlib-cross      = pkg ~/src/gitlib/gitlib-cross { git = gitAndTools.git; };
  gitlib-hit        = pkg ~/src/gitlib/gitlib-hit {};
  gitlib-lens       = pkg ~/src/gitlib/gitlib-lens {};
  gitlib-libgit2    = pkg ~/src/gitlib/gitlib-libgit2 {};
  gitlib-s3         = pkg ~/src/gitlib/gitlib-S3 {};
  gitlib-sample     = pkg ~/src/gitlib/gitlib-sample {};
  gitlib-test       = pkg ~/src/gitlib/gitlib-test {};
  gitlib_v4         = pkg ~/src/gitlib/v4/gitlib;
  gitlib-cmdline_v4 = pkg ~/src/gitlib/v4/gitlib-cmdline {
    git = gitAndTools.git;
    gitlib = gitlib_v4;
    gitlib-test = gitlib-test_v4;
  };
  gitlib-cross_v4   = pkg ~/src/gitlib/v4/gitlib-cross {
    git = gitAndTools.git;
  };
  gitlib-hit_v4     = pkg ~/src/gitlib/v4/gitlib-hit {
    gitlib = gitlib_v4;
    gitlib-test = gitlib-test_v4;
  };
  gitlib-lens_v4    = pkg ~/src/gitlib/v4/gitlib-lens {
    gitlib = gitlib_v4;
    gitlib-libgit2 = gitlib-test_v4;
  };
  gitlib-libgit2_v4 = pkg ~/src/gitlib/v4/gitlib-libgit2 {
    gitlib = gitlib_v4;
    gitlib-test = gitlib-test_v4;
  };
  gitlib-s3_v4      = pkg ~/src/gitlib/v4/gitlib-S3 {
    gitlib = gitlib_v4;
    gitlib-test = gitlib-test_v4;
    gitlib-libgit2 = gitlib-test_v4;
  };
  gitlib-sample_v4  = pkg ~/src/gitlib/v4/gitlib-sample {
    gitlib = gitlib_v4;
  };
  gitlib-test_v4    = pkg ~/src/gitlib/v4/gitlib-test {
    gitlib = gitlib_v4;
  };
  hierarchy         = pkg ~/src/hierarchy {};
  hlibgit2          = dontCheck (pkg ~/src/gitlib/hlibgit2 {});
  hnix              = pkg ~/src/hnix {};
  hours             = pkg ~/src/hours {};
  ipcvar            = pkg ~/src/ipcvar {};
  linearscan        = pkg ~/src/linearscan {};
  linearscan-hoopl  = pkg ~/src/linearscan-hoopl {};
  logging           = pkg ~/src/logging {};
  monad-extras      = pkg ~/src/monad-extras {};
  parsec-free       = pkg ~/src/parsec-free {};
  pipes-async       = pkg ~/src/pipes-async {};
  pipes-files       = pkg ~/src/pipes-files {};
  pipes-fusion      = pkg ~/src/pipes-fusion {};
  pushme            = pkg ~/src/pushme {};
  recursors         = pkg ~/src/recursors {};
  rehoo             = pkg ~/src/rehoo {};
  runmany           = pkg ~/src/runmany {};
  shake-docker      = pkg ~/src/shake-docker {};
  simple-conduit    = pkg ~/src/simple-conduit {};
  simple-mirror     = pkg ~/src/hackage-mirror {};
  sitebuilder       = pkg ~/doc/sitebuilder { yuicompressor = pkgs.yuicompressor; };
  sizes             = pkg ~/src/sizes {};
  streaming-tests   = pkg ~/src/streaming-tests {};
  una               = pkg ~/src/una {};

  ### BAE packages

  hmon              = dontHaddock (pkg ~/bae/atif-deliverable/monitors/hmon {});
  hsmedl            = dontHaddock (pkg ~/bae/atif-deliverable/monitors/hmon/hsmedl {});
  apis              = dontHaddock (dontCheck (pkg ~/bae/xhtml-deliverable/rings-dashboard/mitll/brass-platform/apis {}));
  parameter-dsl     = dontHaddock (dontCheck (pkg ~/bae/xhtml-deliverable/rings-dashboard/mitll/brass-platform/parameter-dsl {}));
  rings-dashboard   = dontHaddock (pkg ~/bae/xhtml-deliverable/rings-dashboard {});
  comparator        = dontHaddock (pkg ~/bae/xhtml-deliverable/xhtml/comparator {});

  ### Hackage overrides

  Agda_2_5_2        = dontHaddock super.Agda_2_5_2;
  ReadArgs          = dontCheck super.ReadArgs;
  STMonadTrans      = dontCheck super.STMonadTrans;
  bindings-DSL      = pkg ~/oss/bindings-dsl {};
  blaze-builder-enumerator = doJailbreak super.blaze-builder-enumerator;
  cabal-helper      = doJailbreak super.cabal-helper;
  cabal-install     = doJailbreak super.cabal-install;
  compressed        = doJailbreak super.compressed;
  concurrent-output = doJailbreak super.concurrent-output;
  cryptohash-sha256 = pkg ~/oss/hackage-security/cryptohash-sha256.nix {};
  docker-hs         = pkg ~/oss/docker-hs {};
  ghc-mod           = doJailbreak super.ghc-mod;
  gtk2hs-buildtools = doJailbreak super.gtk2hs-buildtools;
  hackage-root-tool = pkg ~/oss/hackage-security/hackage-root-tool {};
  hackage-security  = doJailbreak (pkg ~/oss/hackage-security/hackage-security {});
  hakyll            = doJailbreak super.hakyll;
  hasktags          = doJailbreak super.hasktags;
  hoogle            = doJailbreak super.hoogle;
  idris             = dontHaddock super.idris;
  language-ecmascript = doJailbreak super.language-ecmascript;
  machines          = doJailbreak super.machines;
  pandoc            = doJailbreak super.pandoc;
  pipes-binary      = doJailbreak super.pipes-binary;
  pipes-zlib        = dontCheck super.pipes-zlib;
  servant           = super.servant_0_9_1_1;
  servant-client    = super.servant-client_0_9_1_1;
  servant-docs      = super.servant-docs_0_9_1_1;
  servant-foreign   = super.servant-foreign_0_9_1_1;
  servant-js        = super.servant-js_0_9;
  servant-server    = super.servant-server_0_9_1_1;
  shake             = doJailbreak super.shake;
  shelly            = doJailbreak (dontHaddock (dontCheck (pkg ~/oss/Shelly.hs {})));
  turtle            = doJailbreak super.turtle;
  swagger2          = dontHaddock (dontCheck super.swagger2);
  time-recurrence   = doJailbreak super.time-recurrence;
  timeparsers       = dontCheck (pkg ~/oss/timeparsers {});
  total             = doJailbreak super.total;

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

haskell7103Packages = super.haskell.packages.ghc7103.override {
  overrides = myHaskellPackages false;
};
profiledHaskell7103Packages = super.haskell.packages.ghc7103.override {
  overrides = myHaskellPackages true;
};

ghc710Env = pkgs.myEnvFun {
  name = "ghc710";
  buildInputs = with haskell7103Packages; [
    haskell7103Packages.ghc alex happy cabal-install
    ghc-core
    hlint
    pointfree
    hasktags
  ];
};

ghc710ProfEnv = pkgs.myEnvFun {
  name = "ghc710prof";
  buildInputs = with profiledHaskell7103Packages; [
    profiledHaskell7103Packages.ghc alex happy cabal-install
    ghc-core
    hlint
    pointfree
    hasktags
  ];
};

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
    pointfree
    hasktags
    simple-mirror
    ghc-mod
    djinn mueval
    # lambdabot
    # threadscope
    # timeplot splot
    # liquidhaskell
    idris
    jhc
    # Agda_2_5_2
  ];
};

ghc80ProfEnv = pkgs.myEnvFun {
  name = "ghc80prof";
  buildInputs = with profiledHaskell802Packages; [
    profiledHaskell802Packages.ghc
    alex happy cabal-install
    ghc-core
    hlint
    pointfree
    hasktags
  ];
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
  ];
};

emacs = emacsHEAD;

emacsHEAD = super.stdenv.lib.overrideDerivation emacsHEAD_base (attrs: {
  doCheck = false;
});

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
    jq
    less
    multitail
    p7zip
    parallel
    pinentry_mac
    postgresql96
    pv
    ripgrep
    rlwrap
    silver-searcher
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
    (super.stdenv.lib.overrideDerivation pdnsd (attrs: {
       # pdnsd does not build with IPv6 on Darwin
       configureFlags = [];
     }))
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
    msmtp
    pflogsumm
  ];
};

jsToolsEnv = pkgs.buildEnv {
  name = "jsTools";
  paths = [
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

_grako = with python35Packages; buildPythonPackage {
  name = "grako-3.14.0";
  src = fetchurl {
    url = "https://pypi.python.org/packages/a0/f4/3b4fdf6db1d8809d344e85e714eea2ac450563d2269a1a490beba6ad5a58/grako-3.14.0.tar.gz";
    sha256 = "0dylh12sa4bfi88kvhr0pfrxgahq1g9c766wd5zsizn8m1ypydsj";
  };
  doCheck = false;
};

_libconf = with python35Packages; buildPythonPackage {
  name = "libconf-1.0.0";
  src = fetchurl {
    url = "https://pypi.python.org/packages/07/6a/4e31b8f805741db44812dccb8d4d5837d2c35a47061d5ecb5920c9b59814/libconf-1.0.0.zip";
    sha256 = "1sspqygnmc756sc0p84ihqb0v3zyzw44ysxs2gha132mb5hipr5v";
  };
};

_pyev = with python35Packages; pyev.override rec {
  postPatch = ''
    libev_so=${pkgs.libev}/lib/libev.4.dylib
    test -f "$libev_so" || { echo "ERROR: File $libev_so does not exist, please fix nix expression for pyev"; exit 1; }
    sed -i -e "s|libev_dll_name = find_library(\"ev\")|libev_dll_name = \"$libev_so\"|" setup.py
  '';
};

_pika = with python35Packages; pika.override rec {
  buildInputs = with self; [ nose mock pyyaml unittest2 _pyev ]
    ++ stdenv.lib.optionals (!isPy3k) [ twisted tornado ];
};

smedl = with python35Packages; buildPythonPackage rec {
  name = "smedl-${version}";
  version = "1.0.0rc2";
  src = ~/bae/atif-deliverable/monitors/smon/smedl;
  buildInputs = with python35Packages; [
    jinja2
    markupsafe
    _grako
    _libconf
    mccabe
    nose2
    pyelftools
    _pika
    pyparsing
  ];

  doCheck = false; # currently uses hard-coded user/host names

  meta = {
    description = "SMEDL distributing monitoring";
    maintainers = with maintainers; [ jwiegley ];
  };
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
    coqPackages_8_5.flocq
    coqPackages_8_5.mathcomp
    coqPackages_8_5.ssreflect
    # coqPackages_8_5.QuickChick
    # coqPackages_8_5.tlc
    # coqPackages_8_5.ynot
  ];
};

coq86Env = pkgs.myEnvFun {
  name = "coq86";
  buildInputs = [
    ocaml ocamlPackages.camlp5_transitional
    coq_8_6
    # coqPackages_8_6.flocq
    # coqPackages_8_6.mathcomp
    # coqPackages_8_6.ssreflect
    # coqPackages_8_6.QuickChick
    # coqPackages_8_6.tlc
    # coqPackages_8_6.ynot
  ];
};

coqHEADEnv = pkgs.myEnvFun {
  name = "coqHEAD";
  buildInputs = [
    ocaml
    ocamlPackages.camlp5_transitional
    coq_HEAD
  ];
};

fiat_HEAD = super.callPackage ~/oss/fiat/8.5 {};

gameToolsEnv = pkgs.buildEnv {
  name = "gameTools";
  paths = [
    # chessdb
    # crafty
    # eboard
    gnugo
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
