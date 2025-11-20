self: pkgs:

let
  srcs = [
    # "async-pool"
    # "bindings-DSL"
    # "c2hsc"
    "gitlib/gitlib"
    "gitlib/gitlib-test"
  [ "gitlib/gitlib-cmdline" { inherit (self) git; } ]
  [ "gitlib/hlibgit2" { inherit (self) git; } ]
    "gitlib/gitlib-libgit2"
    "gitlib/git-monitor"
    # NOTE: The following packages are now accessed via flake inputs:
    # "git-all" - inputs.git-all
    # "hakyll" - inputs.hakyll
    # "hours" - inputs.hours
    # "pushme" - inputs.pushme
    # "renamer" - inputs.renamer
    # "sizes" - inputs.sizes
    # "trade-journal" - inputs.trade-journal
    # "una" - inputs.una
    # "hnix"
    # "logging"
    # "monad-extras"
    # NOTE: org-jw packages removed - they use haskell.nix which is incompatible
    # with standard nixpkgs Haskell. Access them via the org-jw flake directly.
    # "org-jw/org-jw"
    # "org-jw/org-types"
    # "org-jw/flatparse-util"
    # "org-jw/org-cbor"
    # "org-jw/org-json"
    # "org-jw/org-data"
    # "org-jw/org-lint"
    # "org-jw/org-parse"
    # "org-jw/org-print"
    # "org-jw/org-filetags"
    # "org-jw/org-site"
    # "parsec-free"
    # "pipes-async"
    # "pipes-files"
    # "recursors"
    # "runmany"
    # "simple-amount"
  ];

  packageDrv = ghc:
    callPackage (usingWithHoogle self.haskell.packages.${ghc}) ghc;

  otherHackagePackages = ghc: hself: hsuper: with pkgs.haskell.lib; {
    # pushme is now accessed via flake input

    time-recurrence = unmarkBroken (doJailbreak
      (hself.callCabal2nix "time-recurrence" (pkgs.fetchFromGitHub {
        owner  = "jwiegley";
        repo   = "time-recurrence";
        rev    = "d1771331ffd495035cb7f1b2dd14cdf86b11d2fa";
        sha256 = "1l9vf5mzq2r22gph45jk1a4cl8i53ayinlwq1m8dbx3lpnzsjc09";
        # date = 2021-03-21T14:27:27-07:00;
      }) {}));
  };

  callPackage = hpkgs: ghc: path: args:
    filtered (
      if builtins.pathExists (path + "/flake.nix")
      then (import (path + "/default.nix")).default
      else
        if builtins.pathExists (path + "/default.nix")
        then hpkgs.callPackage path
               ({ pkgs = self;
                  compiler = ghc;
                  returnShellEnv = false; } // args)
                  else hpkgs.callCabal2nix (builtins.baseNameOf path) path args);

  myHaskellPackages = ghc: hself: hsuper:
    let fromSrc = arg:
      let
        path = if builtins.isList arg then builtins.elemAt arg 0 else arg;
        args = if builtins.isList arg then builtins.elemAt arg 1 else {};
      in {
        name  = builtins.baseNameOf path;
        value = callPackage hself ghc (/Users/johnw/src + "/${path}") args;
      };
    in builtins.listToAttrs (builtins.map fromSrc srcs);

  usingWithHoogle = hpkgs: hpkgs // rec {
    ghc = hpkgs.ghc // { withPackages = hpkgs.ghc.withHoogle; };
    ghcWithPackages = hpkgs.ghcWithHoogle;
  };

  overrideHask = ghc: hpkgs: hoverrides: hpkgs.override {
    overrides =
      pkgs.lib.composeExtensions hoverrides
        (pkgs.lib.composeExtensions (otherHackagePackages ghc)
           (pkgs.lib.composeExtensions (myHaskellPackages ghc)
              (hself: hsuper: {
                 developPackage =
                   { root
                   , name ? builtins.baseNameOf root
                   , source-overrides ? {}
                   , overrides ? self: super: {}
                   , modifier ? drv: drv
                   , returnShellEnv ? pkgs.lib.inNixShell }:
                   let
                     hpkgs =
                       (pkgs.lib.composeExtensions
                         (_: _: hself)
                         (pkgs.lib.composeExtensions
                           (hself.packageSourceOverrides source-overrides)
                           overrides)) {} hsuper;
                     drv =
                       hpkgs.callCabal2nix name root {};
                   in if returnShellEnv
                      then (modifier drv).env
                      else modifier drv;
               })));
  };

  # Common override for http2 compatibility with warp-3.4.9+
  # warp-3.4.9 requires http2 >= 5.3.11 for confReadNTimeout field
  http2Override = hself: hsuper: {
    time-manager = hself.callHackageDirect {
      pkg = "time-manager";
      ver = "0.2.4";
      sha256 = "176y8svag2fbmvicxgxkhv36gbaak2id3zbwaf40sbaqgpgpy2xh";
    } {};

    http-semantics = hself.callHackageDirect {
      pkg = "http-semantics";
      ver = "0.3.1";
      sha256 = "0ifzl14g5xfqd2cwhbyp726vqcksg3p55lmxs2v04qrsi0w5yvay";
    } {};

    network-run = hself.callHackageDirect {
      pkg = "network-run";
      ver = "0.5.0";
      sha256 = "0xacfhiq6yf1j5dr20h2smkfja7y3wkc91rsls0c23pi5kwf3ddx";
    } {};

    http2 = hself.callHackageDirect {
      pkg = "http2";
      ver = "5.3.11";
      sha256 = "02cxcy3icy094z9x4l3nr8mxng526fls7p94lx1b3shj7n66s1pp";
    } {};

    warp = pkgs.haskell.lib.compose.dontCheck (pkgs.haskell.lib.doJailbreak (hself.callCabal2nix "warp" (self.fetchFromGitHub {
      owner = "yesodweb";
      repo = "wai";
      rev = "5caae1ad3633e87c15e27863e593340c6385fa9d";
      sha256 = "1i53qfqr4krj97idmwwagrl9q3p1siy5p83h2zwsy1jp863jnb08";
    } + "/warp") {}));

    wai-extra = pkgs.haskell.lib.compose.dontCheck (pkgs.haskell.lib.doJailbreak (hself.callCabal2nix "wai-extra" (self.fetchFromGitHub {
      owner = "yesodweb";
      repo = "wai";
      rev = "5caae1ad3633e87c15e27863e593340c6385fa9d";
      sha256 = "1i53qfqr4krj97idmwwagrl9q3p1siy5p83h2zwsy1jp863jnb08";
    } + "/wai-extra") {}));
  };

  breakout = hsuper: names:
    builtins.listToAttrs
      (builtins.map
         (x: { name  = x;
               value = pkgs.haskell.lib.doJailbreak hsuper.${x}; })
         names);

  filtered = drv:
    drv.overrideAttrs
      (attrs: { src = self.haskellFilterSource [] attrs.src; });

in {

haskellFilterSource = paths: src: pkgs.lib.cleanSourceWith {
  inherit src;
  filter = path: type:
    let baseName = baseNameOf path; in
    !( type == "directory"
       && builtins.elem baseName ([".git" ".cabal-sandbox" "dist"] ++ paths))
    &&
    !( type == "unknown"
       || baseName == "cabal.sandbox.config"
       || baseName == "result"
       || pkgs.lib.hasSuffix ".hdevtools.sock" path
       || pkgs.lib.hasSuffix ".sock" path
       || pkgs.lib.hasSuffix ".hi" path
       || pkgs.lib.hasSuffix ".hi-boot" path
       || pkgs.lib.hasSuffix ".o" path
       || pkgs.lib.hasSuffix ".dyn_o" path
       || pkgs.lib.hasSuffix ".dyn_p" path
       || pkgs.lib.hasSuffix ".o-boot" path
       || pkgs.lib.hasSuffix ".p_o" path);
};

haskell = pkgs.haskell // {
  packages = pkgs.haskell.packages // rec {
    ghc94  = overrideHask "ghc94"  pkgs.haskell.packages.ghc94
      (pkgs.lib.composeExtensions http2Override
        (_hself: _hsuper: {}));

    ghc96  = overrideHask "ghc96"  pkgs.haskell.packages.ghc96
      (pkgs.lib.composeExtensions http2Override
        (_hself: hsuper:
          with pkgs.haskell.lib; {
            system-fileio = unmarkBroken hsuper.system-fileio;
          }));

    ghc98  = overrideHask "ghc98"  pkgs.haskell.packages.ghc98
      (pkgs.lib.composeExtensions http2Override
        (_hself: _hsuper: {}));

    ghc910 = overrideHask "ghc910" pkgs.haskell.packages.ghc910
      (pkgs.lib.composeExtensions http2Override
        (_hself: _hsuper: {}));

    ghc912 = overrideHask "ghc912" pkgs.haskell.packages.ghc912
      (pkgs.lib.composeExtensions http2Override
        (_hself: _hsuper: {}));
  };
};

haskellPackages_9_4  = self.haskell.packages.ghc94;
haskellPackages_9_6  = self.haskell.packages.ghc96;
haskellPackages_9_8  = self.haskell.packages.ghc98;
haskellPackages_9_10 = self.haskell.packages.ghc910;
haskellPackages_9_12 = self.haskell.packages.ghc912;

ghcDefaultVersion    = "ghc910";
haskellPackages      = self.haskell.packages.${self.ghcDefaultVersion};

}
