self: pkgs:

let
  srcs = [
    # "async-pool"
    # "bindings-DSL"
    # "c2hsc"
    # "git-all"
    "gitlib/gitlib"
    "gitlib/gitlib-test"
  [ "gitlib/gitlib-cmdline" { inherit (self.gitAndTools) git; } ]
  [ "gitlib/hlibgit2" { inherit (self.gitAndTools) git; } ]
    "gitlib/gitlib-libgit2"
    "gitlib/git-monitor"
    "hours"
    # "hnix"
    # "logging"
    # "monad-extras"
    "org-jw/org-jw"
    "org-jw/org-types"
    "org-jw/flatparse-util"
    "org-jw/org-cbor"
    "org-jw/org-json"
    "org-jw/org-data"
    "org-jw/org-lint"
    "org-jw/org-parse"
    "org-jw/org-print"
    "org-jw/org-filetags"
    "org-jw/org-site"
    # "parsec-free"
    # "pipes-async"
    # "pipes-files"
    "pushme"
    # "recursors"
    "renamer"
    # "runmany"
    # "simple-amount"
    "sizes"
    "trade-journal"
    "una"
  ];

  packageDrv = ghc:
    callPackage (usingWithHoogle self.haskell.packages.${ghc}) ghc;

  otherHackagePackages = ghc: hself: hsuper: with pkgs.haskell.lib; {
    pushme = unmarkBroken (doJailbreak hsuper.pushme);

    hakyll =  hself.callCabal2nix "hakyll" (pkgs.fetchFromGitHub {
      owner  = "jwiegley";
      repo   = "hakyll";
      rev    = "ff283e5e828fde378aab09bf45ed704fd920f700";
      sha256 = "sha256-1rQvA7DooclCpFZbjXUcU0ZC7UkSLuXOVLLL8BsZORI=";
    }) {};

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
        value = callPackage hself ghc (~/src + "/${path}") args;
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
    ghc94  = overrideHask "ghc94"  pkgs.haskell.packages.ghc94  (_hself: _hsuper: {});
    ghc96  = overrideHask "ghc96"  pkgs.haskell.packages.ghc96  (_hself: hsuper:
      with pkgs.haskell.lib; {
        system-fileio = unmarkBroken hsuper.system-fileio;
      });
    ghc98  = overrideHask "ghc98"  pkgs.haskell.packages.ghc98  (_hself: _hsuper: {});
    ghc910 = overrideHask "ghc910" pkgs.haskell.packages.ghc910 (_hself: _hsuper: {});
  };
};

haskellPackages_9_4  = self.haskell.packages.ghc94;
haskellPackages_9_6  = self.haskell.packages.ghc96;
haskellPackages_9_8  = self.haskell.packages.ghc98;
haskellPackages_9_10 = self.haskell.packages.ghc910;

ghcDefaultVersion    = "ghc98";
haskellPackages      = self.haskell.packages.${self.ghcDefaultVersion};

}
