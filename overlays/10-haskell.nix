self: pkgs:

let
  srcs = [
    "async-pool"
    # "bindings-DSL"
    "c2hsc"
    "git-all"
    "gitlib/git-monitor"
    "gitlib/gitlib"
  [ "gitlib/gitlib-cmdline" { inherit (self.gitAndTools) git; } ]
    "gitlib/gitlib-libgit2"
    "gitlib/gitlib-test"
  # [ "gitlib/hlibgit2" { inherit (self.gitAndTools) git; } ]
    "hierarchy"
    "hours"
    # "hnix"
    "logging"
    "monad-extras"
    "parsec-free"
    "pipes-async"
    "pipes-files"
    "pushme"
    "recursors"
    "runmany"
    # "simple-amount"
    "sitebuilder"
    "sizes"
    "una"
  ];

  packageDrv = ghc:
    callPackage (usingWithHoogle self.haskell.packages.${ghc}) ghc;

  otherHackagePackages = ghc: hself: hsuper: with pkgs.haskell.lib; {
    nix-diff = doJailbreak hsuper.nix-diff;

    pipes-text = unmarkBroken hsuper.pipes-text;

    gitlib = unmarkBroken
      (hself.callCabal2nix "gitlib" ~/src/gitlib/gitlib {});

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
      if builtins.pathExists (path + "/default.nix")
      then hpkgs.callPackage path
             ({ pkgs = self;
                compiler = ghc;
                returnShellEnv = false; } // args)
      else hpkgs.callCabal2nix hpkgs (builtins.baseNameOf path) path args);

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
    ghc884  = overrideHask "ghc884"  pkgs.haskell.packages.ghc884  (_hself: _hsuper: {});
    ghc8107 = overrideHask "ghc8107" pkgs.haskell.packages.ghc8107 (_hself: _hsuper: {});
    ghc902  = overrideHask "ghc902"  pkgs.haskell.packages.ghc902  (_hself: _hsuper: {});
    ghc924  = overrideHask "ghc924"  pkgs.haskell.packages.ghc924  (_hself: _hsuper: {});
    ghc941  = overrideHask "ghc941"  pkgs.haskell.packages.ghc941  (_hself: _hsuper: {});
  };
};

haskellPackages_8_8  = self.haskell.packages.ghc884;
haskellPackages_8_10 = self.haskell.packages.ghc8107;
haskellPackages_9_0  = self.haskell.packages.ghc902;
haskellPackages_9_2  = self.haskell.packages.ghc924;
haskellPackages_9_4  = self.haskell.packages.ghc941;

ghcDefaultVersion    = "ghc8107";
haskellPackages      = self.haskell.packages.${self.ghcDefaultVersion};

}
