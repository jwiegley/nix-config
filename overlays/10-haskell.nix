self: pkgs: rec {

z3-debug = true;

##############################################################################
# Haskell

myHaskellPackageDefs = super:
  with super; let pkg = super.callPackage; in rec {

  # Personal packages
  async-pool       = pkg ~/src/async-pool {};
  bindings-DSL     = pkg ~/oss/bindings-DSL {};
  bytestring-fiat  = pkg ~/src/bytestring/extract {};
  c2hsc            = pkg ~/src/c2hsc {};
  categorical      = pkg ~/src/categorical {};
  commodities      = pkg ~/src/ledger4/commodities {};
  consistent       = pkg ~/src/consistent {};
  coq-haskell      = pkg ~/src/coq-haskell {};
  extract          = pkg ~/src/bytestring/extract {};
  fuzzcheck        = pkg ~/src/fuzzcheck {};
  git-all          = pkg ~/src/git-all {};
  git-du           = pkg ~/src/git-du {};
  git-monitor      = pkg ~/src/gitlib/git-monitor {};
  gitlib           = pkg ~/src/gitlib/gitlib {};
  gitlib-cmdline   = pkg ~/src/gitlib/gitlib-cmdline { git = pkgs.gitAndTools.git; };
  gitlib-hit       = pkg ~/src/gitlib/gitlib-hit {};
  gitlib-libgit2   = pkg ~/src/gitlib/gitlib-libgit2 {};
  gitlib-test      = pkg ~/src/gitlib/gitlib-test {};
  hierarchy        = pkg ~/src/hierarchy {};
  hlibgit2         = pkg ~/src/gitlib/hlibgit2 { git = pkgs.gitAndTools.git; };
  hnix             = pkg ~/src/hnix {};
  hours            = pkg ~/src/hours {};
  ipcvar           = pkg ~/src/ipcvar {};
  linearscan       = pkg ~/src/linearscan {};
  linearscan-hoopl = pkg ~/src/linearscan-hoopl {};
  logging          = pkg ~/src/logging {};
  monad-extras     = pkg ~/src/monad-extras {};
  parsec-free      = pkg ~/src/parsec-free {};
  pipes-async      = pkg ~/src/pipes-async {};
  pipes-files      = pkg ~/src/pipes-files {};
  pushme           = pkg ~/src/pushme {};
  recursors        = pkg ~/src/recursors {};
  runmany          = pkg ~/src/runmany {};
  simple-mirror    = pkg ~/src/hackage-mirror {};
  sitebuilder      = pkg ~/doc/sitebuilder { yuicompressor = pkgs.yuicompressor; };
  sizes            = pkg ~/src/sizes {};
  una              = pkg ~/src/una {};
  z3-generate-api  = pkg ~/src/z3-generate-api { };
  z3cat            = pkg ~/src/z3cat {};

  putting-lenses-to-work = pkg ~/doc/papers/putting-lenses-to-work {};

  # Open Source
  concat-classes   = pkg ~/oss/concat/classes {};
  concat-examples  = pkg ~/oss/concat/examples {};
  concat-graphics  = pkg ~/oss/concat/graphics {};
  concat-inline    = pkg ~/oss/concat/inline {};
  concat-plugin    = pkg ~/oss/concat/plugin {};
  freer-effects    = pkg ~/oss/freer-effects {};
  hs-to-coq        = pkg ~/oss/hs-to-coq/hs-to-coq {};

  z3 = pkg ~/src/haskell-z3 {
    z3 = if z3-debug
      then pkgs.z3.overrideDerivation (attrs: {
        src = ~/oss/z3;
        configurePhase = ''
          ${pkgs.python2.interpreter} scripts/mk_make.py --prefix=$out \
            --python --pypkgdir=$out/${pkgs.python2.sitePackages} -d
          cd build
        '';
      })
      else pkgs.z3;
  };

  # BAE packages
  comparator          = pkg ~/bae/autofocus-deliverable/xhtml/comparator {};
  generator           = pkg ~/bae/autofocus-deliverable/xhtml/generator {};
  harness             = pkg ~/bae/autofocus-deliverable/rings-dashboard/mitll-harness {};
  rings-dashboard     = pkg ~/bae/autofocus-deliverable/rings-dashboard {};
  rings-dashboard-api = pkg ~/bae/autofocus-deliverable/rings-dashboard/rings-dashboard-api {};
  solver              = pkg ~/bae/concerto/solver {};
};

haskellPackage_8_0_overrides = libProf: mypkgs: self: super:
  with pkgs.haskell.lib; with super; let pkg = callPackage; in mypkgs // rec {

  Agda                      = dontHaddock super.Agda;
  blaze-builder-enumerator  = doJailbreak super.blaze-builder-enumerator;
  Cabal                     = super.Cabal_1_24_2_0;
  cabal-helper              = super.cabal-helper.override {
    cabal-install = cabal-install;
    Cabal = Cabal;
  };
  categorical               = dontCheck mypkgs.categorical;
  commodities               = doJailbreak mypkgs.commodities;
  compressed                = doJailbreak super.compressed;
  concat-classes            = dontHaddock mypkgs.concat-classes;
  concat-examples           = dontHaddock (dontCheck mypkgs.concat-examples);
  concat-graphics           = dontCheck mypkgs.concat-graphics;
  concat-inline             = dontHaddock mypkgs.concat-inline;
  concat-plugin             = dontHaddock mypkgs.concat-plugin;
  concurrent-output         = doJailbreak super.concurrent-output;
  consistent                = dontCheck mypkgs.consistent;
  derive-storable           = dontCheck super.derive-storable;
  diagrams-graphviz         = doJailbreak super.diagrams-graphviz;
  diagrams-rasterific       = doJailbreak super.diagrams-rasterific;
  ghc-compact               = null;
  hakyll                    = doJailbreak super.hakyll;
  heap                      = dontCheck super.heap;
  hierarchy                 = doJailbreak super.hierarchy;
  hlibgit2                  = doJailbreak super.hlibgit2;
  ipcvar                    = dontCheck super.ipcvar;
  linearscan-hoopl          = dontCheck super.linearscan-hoopl;
  liquidhaskell             = doJailbreak super.liquidhaskell;
  pipes-binary              = doJailbreak super.pipes-binary;
  pipes-files               = dontCheck (doJailbreak super.pipes-files);
  pipes-zlib                = dontCheck (doJailbreak super.pipes-zlib);
  recursors                 = doJailbreak super.recursors;
  runmany                   = doJailbreak super.runmany;
  sbvPlugin                 = doJailbreak super.sbvPlugin;
  shelly                    = dontCheck super.shelly;
  text-show                 = dontCheck super.text-show;
  time-recurrence           = doJailbreak super.time-recurrence;
  timeparsers               = doJailbreak (dontCheck (pkg ~/oss/timeparsers {}));
  units                     = super.units.override { th-desugar = th-desugar_1_6; };
  z3cat                     = dontCheck mypkgs.z3cat;

  cabal-install = callPackage
    ({ mkDerivation, array, async, base, base16-bytestring, binary
     , bytestring, Cabal, containers, cryptohash-sha256, directory
     , filepath, hackage-security, hashable, HTTP, mtl, network
     , network-uri, pretty, process, QuickCheck, random, regex-posix
     , stm, tagged, tar, tasty, tasty-hunit, tasty-quickcheck, time
     , unix, zlib
     }:
     mkDerivation {
       pname = "cabal-install";
       version = "1.24.0.2";
       sha256 = "1q0gl3i9cpg854lcsiifxxginnvhp2bpx19wkkzpzrd072983j1a";
       revision = "1";
       editedCabalFile = "0v112hvvppa31sklpzg54vr0hfidy1334kg5p3jc0gbgl8in1n90";
       isLibrary = false;
       isExecutable = true;
       executableHaskellDepends = [
         array async base base16-bytestring binary bytestring Cabal
         containers cryptohash-sha256 directory filepath hackage-security
         hashable HTTP mtl network network-uri pretty process random stm tar
         time unix zlib
       ];
       testHaskellDepends = [
         array async base binary bytestring Cabal containers directory
         filepath hackage-security hashable HTTP mtl network network-uri
         pretty process QuickCheck random regex-posix stm tagged tar tasty
         tasty-hunit tasty-quickcheck time unix zlib
       ];
       doCheck = false;
       postInstall = ''
         mkdir $out/etc
         mv bash-completion $out/etc/bash_completion.d
       '';
       homepage = "http://www.haskell.org/cabal/";
       description = "The command-line interface for Cabal and Hackage";
       license = pkgs.stdenv.lib.licenses.bsd3;
       maintainers = with pkgs.stdenv.lib.maintainers; [ peti ];
     }) { Cabal = Cabal; };

  th-desugar_1_6 = callPackage
    ({ mkDerivation, base, containers, hspec, HUnit, mtl, syb
     , template-haskell, th-expand-syns, th-lift, th-orphans
     }:
     mkDerivation {
       pname = "th-desugar";
       version = "1.6";
       sha256 = "0kv3gxvr7izvg1s86p92b5318bv7pjghig2hx9q21cg9ppifry68";
       revision = "2";
       editedCabalFile = "0rimjzkqky6sq4yba7vqra7hj29903f9xsn2g8rc23abrm35vds3";
       libraryHaskellDepends = [
         base containers mtl syb template-haskell th-expand-syns th-lift
         th-orphans
       ];
       testHaskellDepends = [
         base containers hspec HUnit mtl syb template-haskell th-expand-syns
         th-lift th-orphans
       ];
       homepage = "https://github.com/goldfirere/th-desugar";
       description = "Functions to desugar Template Haskell";
       license = stdenv.lib.licenses.bsd3;
     }) {};

  singletons = dontCheck (doJailbreak (callPackage
    ({ mkDerivation, base, Cabal, containers, directory, filepath, mtl
     , process, syb, tasty, tasty-golden, template-haskell, th-desugar
     }:
     mkDerivation {
       pname = "singletons";
       version = "2.2";
       sha256 = "1bwcsp1x8bivmvkv8a724lsnwyjharhb0x0hl0isp3jgigh0dg9k";
       libraryHaskellDepends = [
         base containers mtl syb template-haskell th-desugar
       ];
       testHaskellDepends = [
         base Cabal directory filepath process tasty tasty-golden
       ];
       homepage = "http://www.github.com/goldfirere/singletons";
       description = "A framework for generating singleton types";
       license = stdenv.lib.licenses.bsd3;
     }) { th-desugar = th-desugar_1_6; }));

  # lens-family 1.2.2 requires GHC 8.2 or higher
  lens-family = callPackage
    ({ mkDerivation, base, containers, lens-family-core, mtl
     , transformers
     }:
     mkDerivation {
       pname = "lens-family";
       version = "1.2.1";
       sha256 = "1dwsrli94i8vs1wzfbxbxh49qhn8jn9hzmxwgd3dqqx07yx8x0s1";
       libraryHaskellDepends = [
         base containers lens-family-core mtl transformers
       ];
       description = "Lens Families";
       license = stdenv.lib.licenses.bsd3;
     }) {};

  lens-family-core = callPackage
    ({ mkDerivation, base, containers, transformers }:
     mkDerivation {
       pname = "lens-family-core";
       version = "1.2.1";
       sha256 = "190r3n25m8x24nd6xjbbk9x0qhs1mw22xlpsbf3cdp3cda3vkqwm";
       libraryHaskellDepends = [ base containers transformers ];
       description = "Haskell 98 Lens Families";
       license = stdenv.lib.licenses.bsd3;
     }) {};

  haskell-src-exts-simple_1_20_0_0 =
    super.haskell-src-exts-simple_1_20_0_0.override {
      haskell-src-exts = super.haskell-src-exts_1_20_1;
    };

  lambdabot-haskell-plugins = doJailbreak (
    super.lambdabot-haskell-plugins.override {
      haskell-src-exts-simple = haskell-src-exts-simple_1_20_0_0;
    });

  ghc-mod = dontCheck (doJailbreak (callPackage
    ({ mkDerivation, base, binary, bytestring, Cabal, cabal-helper
     , containers, criterion, deepseq, directory, djinn-ghc, doctest
     , extra, fclabels, filepath, ghc, ghc-boot, ghc-paths
     , ghc-syb-utils, haskell-src-exts, hlint, hspec, monad-control
     , monad-journal, mtl, old-time, optparse-applicative, pipes
     , process, safe, semigroups, shelltest, split, syb
     , template-haskell, temporary, text, time, transformers
     , transformers-base
     }:
     mkDerivation {
       pname = "ghc-mod";
       version = "5.9.0.0";
       src = pkgs.fetchFromGitHub {
         owner = "DanielG";
         repo = "ghc-mod";
         rev = "0f281bea89edf8f11c82c5359ee2b3ce19888b99";
         sha256 = "0f70nrlqgizsrya1x5kgxib7hxc0ip18b7nh62jclny1fq4r02vm";
       };
       isLibrary = true;
       isExecutable = true;
       enableSeparateDataOutput = true;
       setupHaskellDepends = [
         base Cabal containers directory filepath process template-haskell
         transformers
       ];
       libraryHaskellDepends = [
         base binary bytestring cabal-helper containers deepseq directory
         djinn-ghc extra fclabels filepath ghc ghc-boot ghc-paths
         ghc-syb-utils haskell-src-exts hlint monad-control monad-journal
         mtl old-time optparse-applicative pipes process safe semigroups
         split syb template-haskell temporary text time transformers
         transformers-base
       ];
       executableHaskellDepends = [
         base binary deepseq directory fclabels filepath ghc monad-control
         mtl old-time optparse-applicative process semigroups split time
       ];
       testHaskellDepends = [
         base cabal-helper containers directory doctest fclabels filepath
         ghc ghc-boot hspec monad-journal mtl process split temporary
         transformers
       ];
       testToolDepends = [ shelltest ];
       benchmarkHaskellDepends = [
         base criterion directory filepath temporary
       ];
       homepage = "https://github.com/DanielG/ghc-mod";
       description = "Happy Haskell Hacking";
       license = pkgs.stdenv.lib.licenses.agpl3;
       hydraPlatforms = pkgs.stdenv.lib.platforms.none;
     }) { shelltest = null;
          Cabal = Cabal;
          cabal-helper = cabal-helper; }));

  recurseForDerivations = true;

  mkDerivation = args: super.mkDerivation (args // {
    enableLibraryProfiling = libProf;
    enableExecutableProfiling = false;
  });
};

haskellPackage_8_2_overrides = libProf: mypkgs: self: super:
  with pkgs.haskell.lib; with super; let pkg = callPackage; in mypkgs // rec {

  Agda                     = dontHaddock super.Agda;
  blaze-builder-enumerator = doJailbreak super.blaze-builder-enumerator;
  compressed               = doJailbreak super.compressed;
  commodities              = doJailbreak mypkgs.commodities;
  consistent               = doJailbreak (dontCheck mypkgs.consistent);
  derive-storable          = dontCheck super.derive-storable;
  diagrams-graphviz        = doJailbreak super.diagrams-graphviz;
  diagrams-rasterific      = doJailbreak super.diagrams-rasterific;
  git-annex                = dontCheck super.git-annex;
  hakyll                   = doJailbreak super.hakyll;
  heap                     = dontCheck super.heap;
  hierarchy                = doJailbreak super.hierarchy;
  ipcvar                   = dontCheck super.ipcvar;
  lattices                 = doJailbreak super.lattices;
  linearscan-hoopl         = dontCheck super.linearscan-hoopl;
  pandoc-citeproc          = pkg ~/oss/pandoc-citeproc {};
  pipes-binary             = doJailbreak super.pipes-binary;
  pipes-files              = dontCheck (doJailbreak super.pipes-files);
  pipes-zlib               = dontCheck (doJailbreak super.pipes-zlib);
  posix-paths              = doJailbreak super.posix-paths;
  recursors                = doJailbreak super.recursors;
  runmany                  = doJailbreak super.runmany;
  shelly                   = dontCheck (doJailbreak super.shelly);
  text-icu                 = dontCheck super.text-icu;
  text-show                = dontCheck super.text-show;
  these                    = doJailbreak super.these;
  time-recurrence          = doJailbreak super.time-recurrence;
  timeparsers              = doJailbreak (dontCheck (pkg ~/oss/timeparsers {}));

  cabal-helper = doJailbreak (callPackage
    ({ mkDerivation, base, bytestring, Cabal, cabal-install, containers
     , directory, extra, filepath, ghc-prim, mtl, process
     , template-haskell, temporary, transformers, unix, utf8-string
     , semigroupoids, unix-compat
     }:
     mkDerivation {
       pname = "cabal-helper";
       version = "4bfc6b";
       src = pkgs.fetchFromGitHub {
         owner = "DanielG";
         repo = "cabal-helper";
         rev = "4bfc6b916fcc696a5d82e7cd35713d6eabcb0533";
         sha256 = "1a8231as0wdvi0q73ha9lc0qrx23kmcwf910qaicvmdar5p2b15m";
       };
       isLibrary = true;
       isExecutable = true;
       setupHaskellDepends = [
         base Cabal containers directory filepath process template-haskell
         transformers semigroupoids unix-compat
       ];
       libraryHaskellDepends = [
         base Cabal directory filepath ghc-prim mtl process transformers
         semigroupoids unix-compat
       ];
       executableHaskellDepends = [
         base bytestring Cabal directory filepath ghc-prim mtl process
         template-haskell temporary transformers utf8-string semigroupoids
         unix-compat
       ];
       testHaskellDepends = [
         base bytestring Cabal directory extra filepath ghc-prim mtl process
         template-haskell temporary transformers unix utf8-string
         semigroupoids unix-compat
       ];
       testToolDepends = [ cabal-install ];
       doCheck = false;
       description = "Simple interface to some of Cabal's configuration state used by ghc-mod";
       license = pkgs.stdenv.lib.licenses.agpl3;
       hydraPlatforms = pkgs.stdenv.lib.platforms.none;
     }) {});

  haskell-src-exts-simple_1_20_0_0 =
    super.haskell-src-exts-simple_1_20_0_0.override {
      haskell-src-exts = super.haskell-src-exts_1_20_1;
    };

  lambdabot-haskell-plugins =
    super.lambdabot-haskell-plugins.override {
      haskell-src-exts-simple = haskell-src-exts-simple_1_20_0_0;
    };

  ghc-mod = dontCheck (doJailbreak (callPackage
    ({ mkDerivation, base, binary, bytestring, Cabal, cabal-helper
     , containers, criterion, deepseq, directory, djinn-ghc, doctest
     , extra, fclabels, filepath, ghc, ghc-boot, ghc-paths
     , ghc-syb-utils, haskell-src-exts, hlint, hspec, monad-control
     , monad-journal, mtl, old-time, optparse-applicative, pipes
     , process, safe, semigroups, shelltest, split, syb
     , template-haskell, temporary, text, time, transformers
     , transformers-base
     }:
     mkDerivation {
       pname = "ghc-mod";
       version = "5.9.0.0";
       src = pkgs.fetchFromGitHub {
         owner = "DanielG";
         repo = "ghc-mod";
         rev = "c3530f75d5c539c91ed0b8d38e90d66cbaa66a35";
         sha256 = "1q7sz50da645x7ysqy8k1m09adidqp62vf8v7zin69yv76fsz9nn";
       };
       isLibrary = true;
       isExecutable = true;
       enableSeparateDataOutput = true;
       setupHaskellDepends = [
         base Cabal containers directory filepath process template-haskell
         transformers cabal-doctest
       ];
       libraryHaskellDepends = [
         base binary bytestring cabal-helper containers deepseq directory
         djinn-ghc extra fclabels filepath ghc ghc-boot ghc-paths
         ghc-syb-utils haskell-src-exts hlint monad-control monad-journal
         mtl old-time optparse-applicative pipes process safe semigroups
         split syb template-haskell temporary text time transformers
         transformers-base
       ];
       executableHaskellDepends = [
         base binary deepseq directory fclabels filepath ghc monad-control
         mtl old-time optparse-applicative process semigroups split time
       ];
       testHaskellDepends = [
         base cabal-helper containers directory doctest fclabels filepath
         ghc ghc-boot hspec monad-journal mtl process split temporary
         transformers
       ];
       testToolDepends = [ shelltest ];
       benchmarkHaskellDepends = [
         base criterion directory filepath temporary
       ];
       homepage = "https://github.com/DanielG/ghc-mod";
       description = "Happy Haskell Hacking";
       license = pkgs.stdenv.lib.licenses.agpl3;
       hydraPlatforms = pkgs.stdenv.lib.platforms.none;
     }) { cabal-helper = cabal-helper;
          shelltest = null; }));

  recurseForDerivations = true;

  mkDerivation = args: super.mkDerivation (args // {
    # libraryHaskellDepends =
    #   if builtins.hasAttr "libraryHaskellDepends" args
    #   then args.libraryHaskellDepends
    #          ++ [ pkgs.darwin.apple_sdk.frameworks.Cocoa ]
    #   else [ pkgs.darwin.apple_sdk.frameworks.Cocoa ];
    enableLibraryProfiling = libProf;
    enableExecutableProfiling = false;
  });
};

haskellPackage_HEAD_overrides = libProf: mypkgs: self: super:
  with pkgs.haskell.lib; with super; let pkg = callPackage; in mypkgs // rec {

  Agda                     = dontHaddock super.Agda;
  blaze-builder-enumerator = doJailbreak super.blaze-builder-enumerator;
  compressed               = doJailbreak super.compressed;
  consistent               = doJailbreak (dontCheck mypkgs.consistent);
  derive-storable          = dontCheck super.derive-storable;
  diagrams-graphviz        = doJailbreak super.diagrams-graphviz;
  diagrams-rasterific      = doJailbreak super.diagrams-rasterific;
  hakyll                   = doJailbreak super.hakyll;
  hierarchy                = doJailbreak super.hierarchy;
  ipcvar                   = dontCheck super.ipcvar;
  lattices                 = doJailbreak super.lattices;
  linearscan-hoopl         = dontCheck super.linearscan-hoopl;
  pandoc-citeproc          = pkg ~/oss/pandoc-citeproc {};
  pipes-binary             = doJailbreak super.pipes-binary;
  pipes-files              = dontCheck (doJailbreak super.pipes-files);
  pipes-zlib               = dontCheck (doJailbreak super.pipes-zlib);
  posix-paths              = doJailbreak super.posix-paths;
  recursors                = doJailbreak super.recursors;
  shelly                   = doJailbreak super.shelly;
  text-icu                 = dontCheck super.text-icu;
  these                    = doJailbreak super.these;
  time-recurrence          = doJailbreak super.time-recurrence;
  timeparsers              = doJailbreak (dontCheck (pkg ~/oss/timeparsers {}));

  mkDerivation = args: super.mkDerivation (args // {
    enableLibraryProfiling = libProf;
    enableExecutableProfiling = false;
  });
};

myHaskellPackages = haskellPackages: with haskellPackages; [
  # HFuse
  # liquidhaskell
  # threadscope
  Boolean
  HTTP
  HUnit
  IfElse
  MemoTrie
  MissingH
  Network-NineP
  QuickCheck
  abstract-deque
  abstract-par
  adjunctions
  aeson
  alex
  amqp
  async
  async-pool
  attempt
  attoparsec
  attoparsec-conduit
  attoparsec-enumerator
  base
  base-unicode-symbols
  base16-bytestring
  base64-bytestring
  basic-prelude
  bench
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
  bytestring
  bytestring-mmap
  bytestring-show
  c2hsc
  cabal-helper
  cabal-install
  cabal2nix
  case-insensitive
  cassava
  categories
  cereal
  cereal-conduit
  charset
  checkers
  chunked-data
  classy-prelude
  classy-prelude-conduit
  cmdargs
  commodities
  comonad
  comonad-transformers
  composition
  compressed
  cond
  conduit
  conduit-combinators
  conduit-extra
  configurator
  connection
  consistent
  constraints
  containers
  contravariant
  convertible
  cpphs
  criterion
  cryptohash
  css-text
  curl
  data-checked
  data-default
  data-default-class
  data-fix
  derive-storable
  diagrams
  diagrams-builder
  diagrams-core
  diagrams-graphviz
  diagrams-lib
  diagrams-svg
  directory
  distributive
  djinn
  dlist
  dlist-instances
  dns
  doctest
  doctest-prop
  either
  enclosed-exceptions
  errors
  exceptions
  extensible-exceptions
  failure
  fast-logger
  fgl
  file-embed
  filemanip
  filepath
  fingertree
  fmlist
  foldl
  free
  free-vl
  freer-effects
  fsnotify
  fuzzcheck
  generic-lens
  ghc-core
  ghc-mod
  ghc-paths
  gitlib
  gitlib-cmdline
  gitlib-libgit2
  gitlib-sample
  gitlib-test
  graphviz
  groups
  hakyll
  hamlet
  happy
  hashable
  hashtables
  haskell-lexer
  haskell-src
  haskell-src-exts
  hasktags
  hdevtools
  here
  hierarchy
  hlibgit2
  hlint
  hnix
  hpack
  hslogger
  hspec
  hspec-expectations
  hspec-megaparsec
  hspec-smallcheck
  hspec-wai
  html
  http-client
  http-client-tls
  http-date
  http-media
  http-types
  interpolate
  io-memoize
  io-storage
  io-streams
  ipcvar
  json
  json-stream
  kan-extensions
  kdt
  keys
  lambdabot
  language-c
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
  linearscan
  linearscan-hoopl
  list-extras
  list-t
  logging
  logict
  machinecell
  machines
  megaparsec
  mime-mail
  mime-types
  mmorph
  monad-control
  monad-coroutine
  monad-extras
  monad-logger
  monad-loops
  monad-par
  monad-par-extras
  monad-stm
  monadloc
  mono-traversable
  monoid-extras
  mtl
  mueval
  multimap
  network
  network-simple
  newtype
  numbers
  operational
  optparse-applicative
  pandoc
  parallel
  parallel-io
  parsec
  parsers
  pcre-heavy
  pipes
  pipes-async
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
  pipes-text
  pipes-zlib
  pointed
  pointfree
  posix-paths
  postgresql-simple
  pretty-show
  process
  process-extras
  profunctors
  quickcheck-instances
  random
  recursors
  reducers
  reflection
  regex-applicative
  regex-base
  regex-compat
  regex-posix
  resourcet
  retry
  safe
  sbv
  sbvPlugin
  scalpel
  scientific
  scotty
  semigroupoids
  semigroups
  semiring-simple
  servant
  servant-blaze
  servant-client
  servant-docs
  servant-foreign
  servant-js
  servant-server
  shake
  shakespeare
  shelly
  silently
  simple-reflect
  smallcheck
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
  stylish-haskell
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
  text-show
  these
  thyme
  time
  time-recurrence
  timeparsers
  timeplot
  tls
  total
  transformers
  transformers-base
  trifecta
  turtle
  uniplate
  unix-compat
  unordered-containers
  uuid
  vector
  vector-sized
  void
  wai
  warp
  weigh
  x509
  x509-store
  x509-system
  yaml
  z3
  z3-generate-api
  zippers
  zlib
];

haskPkgs = haskellPackages_8_2;
haskellPackages = haskPkgs;

mkHaskellPackages = hpkgs: hoverrides: hpkgs.override {
  overrides = self: super: hoverrides (myHaskellPackageDefs super) self super;
};

haskellPackages_HEAD = mkHaskellPackages pkgs.haskell.packages.ghcHEAD
  (haskellPackage_HEAD_overrides false);
profiledHaskellPackages_HEAD = mkHaskellPackages pkgs.haskell.packages.ghcHEAD
  (haskellPackage_HEAD_overrides true);

haskellPackages_8_2 = mkHaskellPackages pkgs.haskell.packages.ghc822
  (haskellPackage_8_2_overrides false);
profiledHaskellPackages_8_2 = mkHaskellPackages pkgs.haskell.packages.ghc822
  (haskellPackage_8_2_overrides true);

haskellPackages_8_0 = mkHaskellPackages pkgs.haskell.packages.ghc802
  (haskellPackage_8_0_overrides false);
profiledHaskellPackages_8_0 = mkHaskellPackages pkgs.haskell.packages.ghc802
  (haskellPackage_8_0_overrides true);

ghcHEADProfEnv = pkgs.myEnvFun {
  name = "ghcHEADprof";
  buildInputs = with pkgs.haskell.lib; with haskellPackages_HEAD; [
    (ghcWithHoogle myHaskellPackages)
  ];
};

ghc82Env = pkgs.myEnvFun {
  name = "ghc82";
  buildInputs = with pkgs.haskell.lib; with haskellPackages_8_2; [
    (ghcWithHoogle myHaskellPackages)
  ];
};

ghc82ProfEnv = pkgs.myEnvFun {
  name = "ghc82prof";
  buildInputs = with pkgs.haskell.lib; with profiledHaskellPackages_8_2; [
    (ghcWithHoogle myHaskellPackages)
  ];
};

ghc80Env = pkgs.myEnvFun {
  name = "ghc80";
  buildInputs = with pkgs.haskell.lib; with haskellPackages_8_0; [
    (ghcWithHoogle (pkgs: myHaskellPackages pkgs ++ (with pkgs; [
       Agda
       # idris
       categorical
       concat-inline
       concat-classes
       concat-plugin
       concat-examples
       concat-graphics
       singletons
       units
       z3cat
     ])))

    splot
  ];
};

ghc80ProfEnv = pkgs.myEnvFun {
  name = "ghc80prof";
  buildInputs = with pkgs.haskell.lib; with profiledHaskellPackages_8_0; [
    (ghcWithHoogle (pkgs: myHaskellPackages pkgs ++ (with pkgs; [
       categorical
       concat-inline
       concat-classes
       concat-plugin
       concat-examples
       concat-graphics
       singletons
       units
       z3cat
     ])))

    splot
  ];
};

haskellFilterSource = paths: src: builtins.filterSource (path: type:
    let baseName = baseNameOf path; in
    !( type == "directory"
       && builtins.elem baseName ([".git" ".cabal-sandbox" "dist"] ++ paths))
    &&
    !( type == "unknown"
       || pkgs.stdenv.lib.hasSuffix ".hdevtools.sock" path
       || pkgs.stdenv.lib.hasSuffix ".sock" path
       || pkgs.stdenv.lib.hasSuffix ".hi" path
       || pkgs.stdenv.lib.hasSuffix ".hi-boot" path
       || pkgs.stdenv.lib.hasSuffix ".o" path
       || pkgs.stdenv.lib.hasSuffix ".o-boot" path
       || pkgs.stdenv.lib.hasSuffix ".dyn_o" path
       || pkgs.stdenv.lib.hasSuffix ".p_o" path))
  src;

}
