{ pkgs }: {

packageOverrides = super: let self = super.pkgs; in with self; rec {

myHaskellPackages = libProf: self: super: with pkgs.haskell.lib; {
  async-pool        = self.callPackage ~/src/async-pool {};
  bytestring-fiat   = self.callPackage ~/src/bytestring/src {};
  c2hsc             = dontCheck (self.callPackage ~/src/c2hsc {});
  commodities       = self.callPackage ~/src/ledger/new/commodities {};
  consistent        = self.callPackage ~/src/consistent {};
  convert           = self.callPackage ~/doc/johnwiegley/convert {};
  features          = self.callPackage ~/bae/rings/problems/xhtml/features {};
  coq-haskell       = self.callPackage ~/src/coq-haskell {};
  emacs-bugs        = self.callPackage ~/src/emacs-bugs {};
  find-conduit      = self.callPackage ~/src/find-conduit {};
  fusion            = self.callPackage ~/src/fusion {};
  fuzzcheck         = self.callPackage ~/src/fuzzcheck {};
  ghc-issues        = self.callPackage ~/src/ghc-issues {};
  git-all           = self.callPackage ~/src/git-all {};
  github            = self.callPackage ~/src/github {};
  hierarchy         = self.callPackage ~/src/hierarchy {};
  hnix              = self.callPackage ~/src/hnix {};
  hours             = self.callPackage ~/src/hours {};
  hsmedl            = self.callPackage ~/bae/hsmedl {};
  ipcvar            = self.callPackage ~/src/ipcvar {};
  johnwiegley       = self.callPackage ~/doc/johnwiegley { yuicompressor = pkgs.yuicompressor; };
  linearscan        = self.callPackage ~/src/linearscan {};
  linearscan-hoopl  = self.callPackage ~/src/linearscan-hoopl {};
  logging           = self.callPackage ~/src/logging {};
  monad-extras      = self.callPackage ~/src/monad-extras {};
  newartisans       = self.callPackage ~/doc/newartisans { yuicompressor = pkgs.yuicompressor; };
  parsec            = self.callPackage ~/oss/parsec {};
  parsec-free       = self.callPackage ~/src/parsec-free {};
  pipes-files       = self.callPackage ~/src/pipes-files {};
  pipes-fusion      = self.callPackage ~/src/pipes-fusion {};
  pushme            = self.callPackage ~/src/pushme {};
  rehoo             = self.callPackage ~/src/rehoo {};
  rest-client       = self.callPackage ~/src/rest-client {};
  simple-conduit    = self.callPackage ~/src/simple-conduit {};
  simple-mirror     = self.callPackage ~/src/hackage-mirror {};
  sizes             = self.callPackage ~/src/sizes {};
  streaming-tests   = self.callPackage ~/src/streaming-tests {};
  una               = self.callPackage ~/src/una {};

  git-gpush         = self.callPackage ~/src/gitlib/git-gpush {};
  git-monitor       = self.callPackage ~/src/gitlib/git-monitor {};
  gitlib            = self.callPackage ~/src/gitlib/gitlib {};
  gitlib-cmdline    = self.callPackage ~/src/gitlib/gitlib-cmdline { git = gitAndTools.git; };
  gitlib-cross      = self.callPackage ~/src/gitlib/gitlib-cross { git = gitAndTools.git; };
  gitlib-hit        = self.callPackage ~/src/gitlib/gitlib-hit {};
  gitlib-lens       = self.callPackage ~/src/gitlib/gitlib-lens {};
  gitlib-libgit2    = self.callPackage ~/src/gitlib/gitlib-libgit2 {};
  gitlib-s3         = self.callPackage ~/src/gitlib/gitlib-S3 {};
  gitlib-sample     = self.callPackage ~/src/gitlib/gitlib-sample {};
  gitlib-test       = self.callPackage ~/src/gitlib/gitlib-test {};
  hlibgit2          = dontCheck (self.callPackage ~/src/gitlib/hlibgit2 {});

  blaze-builder-enumerator  = doJailbreak super.blaze-builder-enumerator;
  lambdabot-haskell-plugins = doJailbreak super.lambdabot-haskell-plugins;

  ReadArgs          = dontCheck super.ReadArgs;
  apis              = dontCheck (self.callPackage ~/bae/spv-deliverable/rings-dashboard/mitll/brass-platform/apis {});
  bindings-DSL      = self.callPackage ~/oss/bindings-dsl {};
  compressed        = doJailbreak super.compressed;
  cryptohash-sha256 = self.callPackage ~/oss/hackage-security/cryptohash-sha256.nix {};
  docker-hs         = self.callPackage ~/oss/docker-hs {};
  ghc-mod           = doJailbreak super.ghc-mod;
  hackage-root-tool = self.callPackage ~/oss/hackage-security/hackage-root-tool {};
  hackage-security  = self.callPackage ~/oss/hackage-security/hackage-security {};
  hoogle            = doJailbreak super.hoogle;
  parameter-dsl     = self.callPackage ~/bae/spv-deliverable/rings-dashboard/mitll/brass-platform/parameter-dsl {};
  pipes             = self.callPackage ~/oss/pipes {};
  pipes-binary      = doJailbreak super.pipes-binary;
  pipes-safe        = self.callPackage ~/oss/pipes-safe {};
  pipes-shell       = self.callPackage ~/oss/pipes-shell {};
  swagger2          = dontHaddock (dontCheck super.swagger2);
  time-recurrence   = dontCheck (self.callPackage ~/oss/time-recurrence {});
  timeparsers       = dontCheck (self.callPackage ~/oss/timeparsers {});
  total             = doJailbreak super.total;
  STMonadTrans      = dontCheck super.STMonadTrans;
  cabal-install     = doJailbreak super.cabal-install;

  mkDerivation = pkg: super.mkDerivation (pkg // {
    # src = pkgs.fetchurl {
    #   url = "file:///Volumes/Hackage/package/${pkg.pname}-${pkg.version}.tar.gz";
    #   inherit (pkg) sha256;
    # };
    enableLibraryProfiling = libProf;
    enableExecutableProfiling = false;
  });
};

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
    ghc-core hlint pointfree hasktags
  ];
};

ghc710ProfEnv = pkgs.myEnvFun {
  name = "ghc710prof";
  buildInputs = with profiledHaskell7103Packages; [
    profiledHaskell7103Packages.ghc alex happy cabal-install
    ghc-core hlint pointfree hasktags
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
    (ghcWithHoogle (import ~/src/hoogle-local/package-list.nix))
    alex happy cabal-install
    ghc-core hlint pointfree hasktags
    simple-mirror ghc-mod
    # threadscope
    # timeplot splot
    # lambdabot djinn mueval
    idris
    jhc
    # liquidhaskell
    Agda # Agda-executable
  ];
};

ghc80ProfEnv = pkgs.myEnvFun {
  name = "ghc80prof";
  buildInputs = with profiledHaskell801Packages; [
    profiledHaskell801Packages.ghc alex happy cabal-install
    ghc-core hlint pointfree hasktags
  ];
};

boost_with_python3 = super.boost160.override {
  python = python3;
};

ledger_HEAD = super.callPackage ~/src/ledger {};
ledger_HEAD_python3 = super.callPackage ~/src/ledger {
  boost = self.boost_with_python3;
};

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

emacs = emacsHEAD;

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
    haskell801Packages.pushme
    haskell801Packages.sizes
    haskell801Packages.una

    aspell
    aspellDicts.en
    exiv2
    findutils
    gnugrep
    gnuplot
    gnused
    gnutar
    graphviz
    haskell801Packages.hours
    # imagemagick_light
    multitail
    less
    p7zip
    haskell801Packages.pandoc
    parallel
    pinentry
    pv
    ripgrep
    rlwrap
    silver-searcher
    haskell801Packages.simple-mirror
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

    haskell801Packages.git-monitor
    haskell801Packages.git-all

    pkgs.gitAndTools.hub
    pkgs.gitAndTools.gitFull
    pkgs.gitAndTools.gitflow
    pkgs.gitAndTools.git-imerge
  ];
};

networkToolsEnv = pkgs.buildEnv {
  name = "networkTools";
  paths = [
    cacert
    httrack
    # iperf
    mtr
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
  ];
};

pythonToolsEnv = pkgs.buildEnv {
  name = "pythonTools";
  paths = [
    python3
    python27
    pythonDocs.pdf_letter.python27
    pythonDocs.html.python27
    python27Packages.ipython
    python27Packages.pygments
    python27Packages.certifi
    # python3Packages.grako
  ];
};

idutils = super.stdenv.lib.overrideDerivation super.idutils (attrs: {
  doCheck = false;
});

buildToolsEnv = pkgs.buildEnv {
  name = "buildTools";
  paths = [ global idutils ctags htmlTidy autoconf automake114x libtool ];
};

langToolsEnv = pkgs.buildEnv {
  name = "langTools";
  paths = [
    clang llvm boost libcxx
    libxml2
    # isabelle
    ott
    gnumake
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

gameToolsEnv = pkgs.buildEnv {
  name = "gameTools";
  paths = [ # chessdb
    # crafty
    # eboard
    gnugo ];
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

};

allowUnfree = true;
allowBroken = true;

}
