# Set the variable NIX_PATH to point to the directory where you've cloned the
# nixpkgs repository.  Then you can run one of two commands:
#
#   nix-build -A crashEnv
#
# This puts a script called 'load-env-crashEnv' into ./result/bin.  Running
# that script puts you into a shell where you can use all of the crash-related
# binaries.
#
#   nix-shell -A crash.safeIsa
#
# This puts you into a shell where you can work on a crash component.  The
# only special thing to note is that instead of calling 'cabal configure', you
# must use:
#
#   eval "$configurePhase"
#
# You are free to use "cabal build" for building, and "cabal test".  Do not
# use "cabal install", as it won't put the binaries anywhere that you will
# find them.  It's best to use what you build directly from the ./dist/build
# directory.
#
# If you ever need to configure again, or if cabal build tries to configure
# again, you must first run:
#
#   unset GHC_PACKAGE_PATH

{ pkgs ? (import <nixpkgs> { config = {
    allowUnfree = true;         # because we haven't set license params
    allowBroken = true;
  };})
}:

let
  haskellPkgs = pkgs.haskell.packages.ghc784;

  inherit (pkgs) stdenv;
  inherit (pkgs.haskell.lib) dontCheck dontHaddock;

  callPackage = stdenv.lib.callPackageWith
    (pkgs // haskellPkgs // haskellDeps // crash);

  crash = {
    safe-isa           = callPackage ./isa/tools/safe-isa {};
    safe-sim           = callPackage ./isa/tools/safe-sim {};
    safe-lib           = callPackage ./isa/code/safelib/safe-lib {};
    safe-isa-tests     = callPackage ./isa/code/IsaTests/safe-isa-tests {};
    safe-meld          = callPackage ./isa/tools/safe-meld {};
    safe-meld-lib      = dontHaddock (callPackage ./isa/tools/safe-meld-lib {});
    safe-scripts       = dontCheck (callPackage ./isa/tools/safe-scripts {});
    safe-lang-support  = callPackage ./external/safe-lang-support {};
    tempest-compiler   = dontHaddock (callPackage ./tempest/tempest-compiler {});
    simple-pat-server  = callPackage ./applications/simple-pat/src/PATServer/haskell {};
    meld-core          = dontCheck (callPackage ./external/meld-core {});
    breeze-compiler    = callPackage ./external/breeze/breeze-compiler {};
    breeze-core        = callPackage ./external/breeze/breeze-core {};
    breeze-interpreter = callPackage ./external/breeze/breeze-interpreter/src {};
    linearscan         = callPackage ./external/linearscan {};
    linearscan-hoopl   = dontCheck (callPackage ./external/linearscan-hoopl {});
  };

  # Build the SAFE tools with some specific dependencies.  If we move to GHC
  # 7.8 and more modern libraries, we can delete some or all of these.
  haskellDeps = pkgs.recurseIntoAttrs rec {
    unbound = haskellPkgs.unbound.override {
      binary = haskellPkgs.binary_0_7_4_0;
    };
    test-framework-hunit = haskellPkgs.test-framework-hunit.override {
      HUnit = HUnit;
    };
    regexpr = haskellPkgs.regexpr.override {
      HUnit = HUnit;
    };
    unbound-generics = callPackage ./nix/unbound-generics-0.0.3.nix {};
    generic-deriving = dontHaddock haskellPkgs.generic-deriving;
    tasty-ant-xml = haskellPkgs.tasty-ant-xml.override {
      generic-deriving = generic-deriving;
    };
    scientific = haskellPkgs.scientific.override {
      tasty-ant-xml = tasty-ant-xml;
    };
    quickcheck-instances = haskellPkgs.quickcheck-instances.override {
      scientific = scientific;
    };
    attoparsec = haskellPkgs.attoparsec.override {
      scientific = scientific;
    };
    these = haskellPkgs.these.override {
      quickcheck-instances = quickcheck-instances;
    };
    data-partition = callPackage ./nix/data-partition-0.2.0.1.nix {};
    either-unwrap = dontCheck (callPackage ./nix/either-unwrap-1.1.nix {});
    polyparse = callPackage ./nix/polyparse-1.9.nix {};
    lens-action = callPackage ./nix/lens-action-0.2.0.2.nix {};
    HUnit = callPackage ./nix/Hunit-1.2.5.2.nix {};
    cpphs = haskellPkgs.cpphs.override {
      polyparse = callPackage ./nix/polyparse-1.9.nix {};
    };
    optparse-applicative = callPackage ./nix/optparse-applicative-0.7.0.nix {
      HUnit = HUnit;
    };
    syb = callPackage ./nix/syb-0.4.4.nix {};
  };

in {
  crash = crash;
  deps  = haskellDeps;
  pkgs  = haskellPkgs;

  tempest = crash.tempest-compiler;

  crashEnv = with haskellPkgs; with crash; pkgs.myEnvFun {
    name = "crash";
    buildInputs = stdenv.lib.attrValues crash ++ [
      ghc cabal-install alex happy
    ];
  };

  # This is all you need to run the Isa-Tests:
  #
  #   nix-build -j4 -A crash-Test-Env
  #   ./result/bin/load-env-crash-Test
  #   cd src
  #   make clean
  #   make -j8
  #   cd ../isa/code/Isa-Tests
  #   make clean
  #   make asms-fast
  #   make safe-sim-fast

  crashTestEnv = with haskellPkgs; with crash; pkgs.myEnvFun {
    name = "crashTest";
    buildInputs = [ safe-isa safe-sim safe-scripts ] ++ [
      ghc cabal-install alex happy
    ];
  };
}
