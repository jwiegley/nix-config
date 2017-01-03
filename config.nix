{ pkgs }: {

packageOverrides = super: let self = super.pkgs; in with self; rec {

myHaskellPackages = libProf: self: super:
  with pkgs.haskell.lib;
  let pkg = self.callPackage; in {

  # Packages that I work on, or have written
  async-pool        = pkg ~/src/async-pool {};
  bytestring-fiat   = pkg ~/src/bytestring/src {};
  c2hsc             = dontCheck (pkg ~/src/c2hsc {});
  commodities       = pkg ~/src/ledger/new/commodities {};
  consistent        = pkg ~/src/consistent {};
  convert           = pkg ~/doc/johnwiegley/convert {};
  coq-haskell       = pkg ~/src/coq-haskell {};
  emacs-bugs        = pkg ~/src/emacs-bugs {};
  find-conduit      = pkg ~/src/find-conduit {};
  fusion            = pkg ~/src/fusion {};
  fuzzcheck         = pkg ~/src/fuzzcheck {};
  ghc-issues        = pkg ~/src/ghc-issues {};
  git-all           = pkg ~/src/git-all {};
  github            = pkg ~/src/github {};
  hierarchy         = pkg ~/src/hierarchy {};
  hnix              = pkg ~/src/hnix {};
  hours             = pkg ~/src/hours {};
  ipcvar            = pkg ~/src/ipcvar {};
  linearscan        = pkg ~/src/linearscan {};
  linearscan-hoopl  = pkg ~/src/linearscan-hoopl {};
  logging           = pkg ~/src/logging {};
  monad-extras      = pkg ~/src/monad-extras {};
  parsec            = pkg ~/oss/parsec {};
  parsec-free       = pkg ~/src/parsec-free {};
  pipes-async       = pkg ~/src/pipes-async {};
  pipes-files       = pkg ~/src/pipes-files {};
  pipes-fusion      = pkg ~/src/pipes-fusion {};
  pushme            = pkg ~/src/pushme {};
  rehoo             = pkg ~/src/rehoo {};
  rest-client       = pkg ~/src/rest-client {};
  runmany           = pkg ~/src/runmany {};
  shake-docker      = pkg ~/src/shake-docker {};
  simple-conduit    = pkg ~/src/simple-conduit {};
  simple-mirror     = pkg ~/src/hackage-mirror {};
  sitebuilder       = pkg ~/doc/sitebuilder { yuicompressor = pkgs.yuicompressor; };
  sizes             = pkg ~/src/sizes {};
  streaming-tests   = pkg ~/src/streaming-tests {};
  una               = pkg ~/src/una {};

  # BAE Haskell packages
  apis              = dontCheck (pkg ~/bae/xhtml-deliverable/rings-dashboard/mitll/brass-platform/apis {});
  hsmedl            = pkg ~/bae/hsmedl {};
  parameter-dsl     = pkg ~/bae/xhtml-deliverable/rings-dashboard/mitll/brass-platform/parameter-dsl {};
  rings-dashboard   = dontHaddock (pkg ~/bae/xhtml-deliverable/rings-dashboard {});
  xhtml-comparator  = pkg ~/bae/xhtml-deliverable/xhtml/comparator {};

  # Gitlib
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
  hlibgit2          = dontCheck (pkg ~/src/gitlib/hlibgit2 {});

  # Hackage packages
  STMonadTrans      = dontCheck super.STMonadTrans;
  agdaBase          = dontHaddock super.agdaBase;
  bindings-DSL      = pkg ~/oss/bindings-dsl {};
  blaze-builder-enumerator  = doJailbreak super.blaze-builder-enumerator;
  cabal-install     = doJailbreak super.cabal-install;
  compressed        = doJailbreak super.compressed;
  cryptohash-sha256 = pkg ~/oss/hackage-security/cryptohash-sha256.nix {};
  docker-hs         = pkg ~/oss/docker-hs {};
  ghc-mod           = doJailbreak super.ghc-mod;
  hackage-root-tool = pkg ~/oss/hackage-security/hackage-root-tool {};
  hackage-security  = pkg ~/oss/hackage-security/hackage-security {};
  hoogle            = doJailbreak super.hoogle;
  idris             = dontHaddock super.idris;
  lambdabot-haskell-plugins = doJailbreak super.lambdabot-haskell-plugins;
  pipes             = pkg ~/oss/pipes {};
  pipes-binary      = doJailbreak super.pipes-binary;
  pipes-safe        = pkg ~/oss/pipes-safe {};
  pipes-shell       = pkg ~/oss/pipes-shell {};
  swagger2          = dontHaddock (dontCheck super.swagger2);
  time-recurrence   = dontCheck (pkg ~/oss/time-recurrence {});
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

haskPkgs = haskell801Packages;

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

haskell801Packages = super.haskell.packages.ghc801.override {
  overrides = myHaskellPackages false;
};
profiledHaskell801Packages = super.haskell.packages.ghc801.override {
  overrides = myHaskellPackages true;
};

ghc80Env = pkgs.myEnvFun {
  name = "ghc80";
  buildInputs = with haskell801Packages; [
    (stdenv.lib.attrsets.mapAttrsToList (name: value: "haskell801Packages." + name)
       (myHaskellPackages false haskell801Packages haskell801Packages))
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
    threadscope
    # timeplot splot
    # liquidhaskell
    idris
    jhc
    Agda
  ];
};

ghc80ProfEnv = pkgs.myEnvFun {
  name = "ghc80prof";
  buildInputs = with profiledHaskell801Packages; [
    # (stdenv.lib.attrsets.mapAttrsToList (name: value: "profiledHaskell801Packages." + name)
    #    (myHaskellPackages true profiledHaskell801Packages profiledHaskell801Packages))
    profiledHaskell801Packages.ghc 
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
    haskPkgs.pushme
    haskPkgs.sizes
    haskPkgs.una

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
    haskPkgs.runmany
    jq
    imagemagick_light
    multitail
    less
    p7zip
    haskPkgs.pandoc
    parallel
    pinentry_mac
    postgresql96
    pv
    ripgrep
    rlwrap
    silver-searcher
    haskPkgs.simple-mirror
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
    diffutils diffstat patchutils patch

    haskPkgs.git-monitor
    haskPkgs.git-all

    pkgs.gitAndTools.hub
    pkgs.gitAndTools.gitFull
    pkgs.gitAndTools.gitflow
    pkgs.gitAndTools.git-imerge
    pkgs.gitAndTools.diff-so-fancy

    git-lfs
  ];
};

networkToolsEnv = pkgs.buildEnv {
  name = "networkTools";
  paths = [
    cacert
    httrack
    iperf
    mtr
    dnsutils
    openssh
    openssl
    # pdnsd does not build with IPv6 on Darwin
    (super.stdenv.lib.overrideDerivation pdnsd (attrs: { configureFlags = []; }))
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
    leafnode
    fetchmail
    imapfilter
    contacts
    msmtp
    pflogsumm
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

devToolsEnv = pkgs.myEnvFun {
  name = "devTools";
  buildInputs = [
    autoconf automake libtool pkgconfig clang llvm
  ];
};

langToolsEnv = pkgs.buildEnv {
  name = "langTools";
  paths = [
    global
    idutils
    ctags
    htmlTidy
    cabal2nix
    gnumake
    # isabelle
    ott
    verasco # compcert
    sbcl
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
    haskPkgs.sitebuilder
    texlive.combined.scheme-full
    texinfo
    doxygen
    ffmpeg
  ];
};

};

allowUnfree = true;
allowBroken = true;

}
