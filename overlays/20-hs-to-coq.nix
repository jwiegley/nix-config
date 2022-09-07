self: pkgs: {

hs-to-coq = self.haskell.lib.justStaticExecutables
  (pkgs.callPackage (pkgs.fetchFromGitHub {
      owner = "plclub";
      repo = "hs-to-coq";
      rev = "e6401f6f054a2c1ff5e63a17ab8af2bcd5861c9c";
      sha256 = "0dfnvl2g10y87ln12mlw8q5frcim9vxqf7sfkaqhvbdk2nws1dn1";
    }) { ghcVersion = "ghc8107"; }).haskellPackages.hs-to-coq;
}
