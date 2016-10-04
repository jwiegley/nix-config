{ pkgs }: {

packageOverrides = super: let self = super.pkgs; in with self; rec {

myHaskellPackages = self: super: with pkgs.haskell.lib; {
  newartisans = self.callPackage ~/doc/newartisans {
    yuicompressor = pkgs.yuicompressor;
  };

  johnwiegley = self.callPackage ~/doc/johnwiegley {
    yuicompressor = pkgs.yuicompressor;
  };
  convert = self.callPackage ~/doc/johnwiegley/convert {};

  hsmedl = self.callPackage ~/bae/smedl/hsmedl {};
  bytestring-fiat = self.callPackage ~/src/bytestring/src {};

  emacs-bugs       = self.callPackage ~/src/emacs-bugs {};
  coq-haskell      = self.callPackage ~/src/coq-haskell {};
  linearscan       = self.callPackage ~/src/linearscan {};
  linearscan-hoopl = self.callPackage ~/src/linearscan-hoopl {};
  async-pool       = self.callPackage ~/src/async-pool {};
  c2hsc            = dontCheck (self.callPackage ~/src/c2hsc {});
  commodities      = self.callPackage ~/src/ledger/new/commodities {};
  consistent       = self.callPackage ~/src/consistent {};
  find-conduit     = self.callPackage ~/src/find-conduit {};
  fusion           = self.callPackage ~/src/fusion {};
  fuzzcheck        = self.callPackage ~/src/fuzzcheck {};
  ghc-issues       = self.callPackage ~/src/ghc-issues {};
  git-all          = self.callPackage ~/src/git-all {};
  github           = self.callPackage ~/src/github {};
  hierarchy        = self.callPackage ~/src/hierarchy {};
  hnix             = self.callPackage ~/src/hnix {};
  hours            = self.callPackage ~/src/hours {};
  ipcvar           = self.callPackage ~/src/ipcvar {};
  logging          = self.callPackage ~/src/logging {};
  monad-extras     = self.callPackage ~/src/monad-extras {};
  pipes-files      = self.callPackage ~/src/pipes-files {};
  pipes-fusion     = self.callPackage ~/src/pipes-fusion {};
  pushme           = self.callPackage ~/src/pushme {};
  rehoo            = self.callPackage ~/src/rehoo {};
  rest-client      = self.callPackage ~/src/rest-client {};
  simple-conduit   = self.callPackage ~/src/simple-conduit {};
  simple-mirror    = self.callPackage ~/src/hackage-mirror {};
  sizes            = self.callPackage ~/src/sizes {};
  streaming-tests  = self.callPackage ~/src/streaming-tests {};
  una              = self.callPackage ~/src/una {};

  # gitlib
  gitlib           = self.callPackage ~/src/gitlib/gitlib {};
  gitlib-test      = self.callPackage ~/src/gitlib/gitlib-test {};
  hlibgit2         = dontCheck (self.callPackage ~/src/gitlib/hlibgit2 {});
  gitlib-libgit2   = self.callPackage ~/src/gitlib/gitlib-libgit2 {};
  gitlib-cmdline   = self.callPackage ~/src/gitlib/gitlib-cmdline {
    git = gitAndTools.git;
  };
  gitlib-cross     = self.callPackage ~/src/gitlib/gitlib-cross {
    git = gitAndTools.git;
  };
  gitlib-hit       = self.callPackage ~/src/gitlib/gitlib-hit {};
  gitlib-lens      = self.callPackage ~/src/gitlib/gitlib-lens {};
  gitlib-s3        = self.callPackage ~/src/gitlib/gitlib-S3 {};
  gitlib-sample    = self.callPackage ~/src/gitlib/gitlib-sample {};
  git-monitor      = self.callPackage ~/src/gitlib/git-monitor {};
  git-gpush        = self.callPackage ~/src/gitlib/git-gpush {};

  # community packages
  pipes            = self.callPackage ~/oss/pipes {};
  # pipes-safe       = self.callPackage ~/oss/pipes-safe {};
  bindings-DSL     = self.callPackage ~/oss/bindings-dsl {};
  time-recurrence  = dontCheck (self.callPackage ~/oss/time-recurrence {});
  timeparsers      = dontCheck (self.callPackage ~/oss/timeparsers {});
  # scalpel          = self.callPackage ~/oss/scalpel {};
  docker-hs        = self.callPackage ~/oss/docker-hs {};
  apis             = dontCheck (self.callPackage ~/bae/spv-deliverable/rings-dashboard/mitll/brass-platform/apis {});
  parameter-dsl = self.callPackage ~/bae/spv-deliverable/rings-dashboard/mitll/brass-platform/parameter-dsl {};

  # systemFileio     = dontCheck super.systemFileio;
  # shake            = dontCheck super.shake;
  # singletons       = dontCheck super.singletons;

  hackage-root-tool = self.callPackage ~/oss/hackage-security/hackage-root-tool {};
  hackage-security  = self.callPackage ~/oss/hackage-security/hackage-security {};
  cryptohash-sha256 = self.callPackage ~/oss/hackage-security/cryptohash-sha256.nix {};
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

ghc710Env = pkgs.myEnvFun {
  name = "ghc710";
  buildInputs = with haskell7103Packages; [
    haskell7103Packages.ghc
    alex happy
    cabal-install
    ghc-core
    # ghc-mod
    hlint
    # hasktags
    pointfree
    # threadscope
    # timeplot splot
    # lambdabot djinn mueval
    # idris
    # liquidhaskell
    # Agda Agda-executable
  ];
};

haskell801Packages = super.haskell.packages.ghc801.override {
  overrides = myHaskellPackages;
};

profiledHaskell801Packages = super.haskell.packages.ghc801.override {
  overrides = self: super: myHaskellPackages self super // {
    mkDerivation = args: super.mkDerivation (args // {
      enableLibraryProfiling = true;
      enableExecutableProfiling = true;
    });
  };
};

ghc80Env = pkgs.myEnvFun {
  name = "ghc80";
  buildInputs = with haskell801Packages; [
    haskell801Packages.ghc
    alex happy
    cabal-install
    ghc-core
    # ghc-mod
    hlint
    simple-mirror
    hasktags
    pointfree
    # threadscope
    # timeplot splot
    # lambdabot djinn mueval
    # idris
    # liquidhaskell
    # Agda Agda-executable
  ];
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
    less
    # p7zip
    haskell801Packages.pandoc
    parallel
    pinentry
    pv
    # ripgrep
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
    #httrack
    iperf
    mtr
    openssh
    openssl
    # pdnsd does not build with IPv6 on Darwin
    (super.stdenv.lib.overrideDerivation pdnsd (attrs: { configureFlags = []; }))
    # dnscrypt-proxy
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
  ];
};

pythonToolsEnv = pkgs.buildEnv {
  name = "pythonTools";
  paths = [
    python3
    python27Full
    pythonDocs.pdf_letter.python27
    pythonDocs.html.python27
    python27Packages.ipython
    python27Packages.pygments
    python27Packages.certifi
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
    #isabelle
    #ott
    gnumake
    #compcert
    #verasco
    #sbcl
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
  paths = [
    chessdb craftyFull eboard gnugo
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

};

allowUnfree = true;
allowBroken = true;

}
