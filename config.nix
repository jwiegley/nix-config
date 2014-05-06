{ pkgs }:

{ packageOverrides = self: with pkgs; rec {

ledger = self.callPackage /Users/johnw/Projects/ledger {};

myProjects = cp: (self: {
  bugs          = cp /Users/johnw/Projects/bugs {};
  consistent    = cp /Users/johnw/Projects/consistent {};
  findConduit   = cp /Users/johnw/Projects/find-conduit {};
  gitAll        = cp /Users/johnw/Projects/git-all {};
  hours         = cp /Users/johnw/Projects/hours {};
  loggingHEAD   = cp /Users/johnw/Projects/logging {};
  pushme        = cp /Users/johnw/Projects/pushme {};
  simpleMirror  = cp /Users/johnw/Projects/simple-mirror {};
  theseHEAD     = cp /Users/johnw/Projects/these {};
  tryhaskell    = cp /Users/johnw/Projects/tryhaskell {};

  gitlib        = cp /Users/johnw/Projects/gitlib/gitlib {};
  gitlibTest    = cp /Users/johnw/Projects/gitlib/gitlib-test {};
  hlibgit2      = cp /Users/johnw/Projects/gitlib/hlibgit2 {};
  gitlibLibgit2 = cp /Users/johnw/Projects/gitlib/gitlib-libgit2 {};
  gitMonitor    = cp /Users/johnw/Projects/gitlib/git-monitor {};

  shelly        = cp /Users/johnw/src/shelly {};
  shellyExtra   = cp /Users/johnw/src/shelly/shelly-extra {};

  newartisans   = cp /Users/johnw/src/newartisans {};

  lensHEAD      = cp /Users/johnw/src/lens {};

  conduitHEAD            = cp /Users/johnw/Projects/conduit/conduit {};
  conduitCombinatorsHEAD = cp /Users/johnw/Projects/conduit-combinators {};

  # The nixpkgs expression is too out-of-date to build with 7.8.2.
  hdevtools     = cp /Users/johnw/Projects/hdevtools {};
});

myDependencies = hsPkgs: with hsPkgs;
  pkgs.stdenv.lib.concatMap (self: self.propagatedUserEnvPkgs) [
    hdevtools
    
    bugs
    consistent
    findConduit
    gitAll
    hours
    loggingHEAD
    pushme
    simpleMirror
    theseHEAD
    tryhaskell
    
    #gitlib
    #gitlibTest
    #hlibgit2
    #gitlibLibgit2
    #gitMonitor

    shelly
    #shellyExtra

    lensHEAD
    
    conduitHEAD
    conduitCombinatorsHEAD
    
    newartisans
  ];

##############################################################################

haskellTools = ghcEnv: (([ 
    ghcEnv.ghc
    sloccount
    coq
  ]) ++ (with ghcEnv.hsPkgs; [
    #cabalBounds
    cabalInstall_1_20_0_1
    #codex
    ghcCore
    ghcMod
    hdevtools
    hlint
    (hoogleLocal ghcEnv.hsPkgs)
  ]) ++ (with haskellPackages_ghc782; [
    hobbes
    simpleMirror
  ]) ++ (with haskellPackages_ghc763; [
    Agda
    AgdaStdlib
    cabal2nix
    hasktags
    #hsenv
    lambdabot djinn mueval
    threadscope
  ]));

buildToolsEnv = pkgs.buildEnv {
    name = "buildTools";
    paths = [
      cmake ninja gnumake automake autoconf global
    ];
  };

emacsToolsEnv = pkgs.buildEnv {
    name = "emacsTools";
    paths = [
      emacs aspell aspellDicts.en
    ];
  };

gitToolsEnv = pkgs.buildEnv {
    name = "gitTools";
    paths = [
      git diffutils patchutils bup

      pkgs.gitAndTools.gitAnnex
      pkgs.gitAndTools.hub
      pkgs.gitAndTools.topGit

      haskellPackages.gitAll
    ];
  };

systemToolsEnv = pkgs.buildEnv {
    name = "systemTools";
    paths = [
      coreutils findutils gnused gnutar httrack iperf mosh mtr multitail
      p7zip parallel pdnsd gnupg pinentry pv rsync silver-searcher socat
      stow watch xz youtubeDL exiv2 gnuplot

      haskellPackages.pushme
      haskellPackages.sizes
      haskellPackages.una
    ];
  };

emailToolsEnv = pkgs.buildEnv {
    name = "emailTools";
    paths = [
      leafnode dovecot22 dovecot_pigeonhole fetchmail procmail w3m
    ];
  };

serviceToolsEnv = pkgs.myEnvFun {
    name = "serviceTools";
    buildInputs = [
      nginx postgresql redis
    ];
  };

# findConduitEnv = pkgs.myEnvFun {
#     name = "findConduit";
#     buildInputs = 
#          haskellPackages_ghc782.findConduit.propagatedUserEnvPkgs
#       ++ ghcEnv_782.nativeBuildInputs
#       ;
#   };

##############################################################################

emacs = pkgs.emacs24Macport;

ghc = self.ghc // {
    ghcHEAD = pkgs.callPackage /Users/johnw/Projects/ghc {};
  };

hoogleLocal = hsPkgs: hsPkgs.hoogleLocal.override {
    packages = myPackages hsPkgs;
  };

coq = self.coq.override {
    lablgtk = null;
  };

ghcTools = ghcEnv: pkgs.myEnvFun {
    name = ghcEnv.name;
    buildInputs = haskellTools ghcEnv
      ++ myPackages ghcEnv.hsPkgs
      ++ myDependencies ghcEnv.hsPkgs;
  };

haskellPackages_ghc763 =
  let callPackage = self.lib.callPackageWith haskellPackages_ghc763;
  in self.recurseIntoAttrs (self.haskellPackages_ghc763.override {
      extraPrefs = myProjects callPackage;
    });

ghcEnv_763 = ghcTools {
    name   = "ghc763";
    ghc    = ghc.ghc763;
    hsPkgs = haskellPackages_ghc763;
  };

haskellPackages_ghc782 =
  let callPackage = self.lib.callPackageWith haskellPackages_ghc782;
  in self.recurseIntoAttrs (self.haskellPackages_ghc782.override {
      extraPrefs = myProjects callPackage;
    });

ghcEnv_782 = ghcTools {
    name   = "ghc782";
    ghc    = ghc.ghc782;
    hsPkgs = haskellPackages_ghc782;
  };

haskellPackages_ghcHEAD =
  let callPackage = self.lib.callPackageWith haskellPackages_ghcHEAD;
  in self.recurseIntoAttrs (self.haskellPackages_ghcHEAD.override {
      extraPrefs = myProjects callPackage;
    });

ghcEnv_HEAD = ghcTools {
    name   = "ghcHEAD";
    ghc    = ghc.ghcHEAD;
    hsPkgs = haskellPackages_ghcHEAD;
  };

##############################################################################

myPackages = hsPkgs: with hsPkgs; [
    Boolean
    CCdelcont
    Crypto
    DAV
    HTTP
    HUnit
    IfElse
    MemoTrie
    MissingH
    MonadCatchIOTransformers
    QuickCheck
    abstractDeque
    abstractPar
    adjunctions
    aeson
    annotatedWlPprint
    ansiTerminal
    ansiWlPprint
    appar
    arithmoi
    asn1Encoding
    asn1Parse
    asn1Types
    async
    attempt
    attoparsec
    attoparsecConduit
    attoparsecEnumerator
    authenticate
    base16Bytestring
    base64Bytestring
    baseUnicodeSymbols
    basicPrelude
    bifunctors
    bindingsDSL
    blazeBuilder
    blazeBuilderConduit
    blazeBuilderEnumerator
    blazeHtml
    blazeMarkup
    blazeTextual
    byteable
    byteorder
    bytestringMmap
    caseInsensitive
    #categories
    cereal
    cerealConduit
    charset
    cheapskate
    chunkedData
    cipherAes
    cipherRc4
    classyPrelude
    classyPreludeConduit
    clientsession
    cmdargs
    comonad
    comonadTransformers
    #compdata
    composition
    cond
    conduit
    conduitCombinators
    conduitExtra
    configurator
    connection
    contravariant
    convertible
    cookie
    cpphs
    cprngAes
    cryptoApi
    cryptoCipherTypes
    cryptoNumbers
    cryptoPubkey
    cryptoPubkeyTypes
    cryptoRandom
    cryptohash
    cryptohashConduit
    cssText
    dataDefault
    dataDefaultClass
    dataDefaultInstancesBase
    dataDefaultInstancesContainers
    dataDefaultInstancesDlist
    dataDefaultInstancesOldLocale
    dataenc
    derive
    distributive
    dlist
    dlistInstances
    dns
    doctest
    doctestProp
    editDistance
    either
    #ekg
    emailValidate
    enclosedExceptions
    entropy
    enumerator
    errors
    esqueleto
    exceptions
    extensibleExceptions
    failure
    fastLogger
    feed
    fgl
    fileEmbed
    filepath
    fingertree
    free
    #geniplate
    ghcPaths
    gnuidn
    gnutls
    groups
    gsasl
    hamlet
    hashable
    hashtables
    haskeline
    haskellLexer
    haskellSrc
    haskellSrcExts
    haskellSrcMeta
    hfsevents
    hjsmin
    hslogger
    hspec
    hspecExpectations
    html
    httpClient
    httpClientTls
    httpConduit
    httpDate
    httpTypes
    hxt
    hxtCharproperties
    hxtRegexXmlschema
    hxtUnicode
    iproute
    json
    kanExtensions
    keys
    languageJava
    languageJavascript
    lens
    libxmlSax
    liftedAsync
    liftedBase
    linear
    listExtras
    mimeMail
    mimeTypes
    mmorph
    monadControl
    monadCoroutine
    monadLogger
    monadLoops
    monadPar
    monadParExtras
    monadStm
    monadloc
    monoidExtras
    mtl
    multimap
    network
    newtype
    numbers
    operational
    optparseApplicative
    parallel
    parallelIo
    parsec
    persistent
    persistentPostgresql
    persistentSqlite
    persistentTemplate
    pointed
    posixPaths
    prettyShow
    profunctors
    random
    #recursionSchemes
    reducers
    reflection
    regexApplicative
    regexBase
    regexCompat
    regexPosix
    resourcePool
    resourcet
    retry
    rex
    safe
    semigroupoids
    semigroups
    shake
    shakespeare
    shelly
    simpleReflect
    speculation
    split
    spoon
    stm
    stmChans
    stmConduit
    stmStats
    strict
    stringsearch
    systemFileio
    systemFilepath
    tagged
    tar
    temporary
    text
    these
    thyme
    time
    transformers
    transformersBase
    unixCompat
    unorderedContainers
    vector
    void
    wai
    warp
    xhtml
    xmlLens
    zlib
  ];

}; }
