self: pkgs: {

agda2hs =
  let haskellPackages = pkgs.haskell.packages.ghc8107;
  in haskellPackages.developPackage rec {
    name = "agda2hs";
    root = pkgs.fetchFromGitHub {
      owner = "agda";
      repo = "agda2hs";
      rev = "160478a51bc78b0fdab07b968464420439f9fed6";
      sha256 = "13k2lcljgq0f5zbbyyafx1pizw4ln60xi0x0n0p73pczz6wdpz79";
      # date = 2021-09-08T18:00:00+02:00;
    };

    source-overrides = {};
    overrides = self: super: with pkgs.haskell.lib; {};

    modifier = drv: pkgs.haskell.lib.overrideCabal drv (attrs: {
      buildTools = (attrs.buildTools or []) ++ [
        haskellPackages.cabal-install
      ];

      passthru = {
        nixpkgs = pkgs;
        inherit haskellPackages;
      };
    });
  };
}
