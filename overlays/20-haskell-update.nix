self: pkgs: {

# haskell = pkgs.haskell // {
#   packages = pkgs.haskell.packages // rec {
#     ghc8107 = with pkgs.haskell.lib;
#       pkgs.haskell.packages.ghc8107.override (attrs: {
#         overrides = pkgs.lib.composeExtensions
#           (attrs.overrides or (self: super: {}))
#           (hself: hsuper: {
#              lens = dontCheck hsuper.lens;
#            });
#       });
#   };
# };

# haskellPackages_8_10 = self.haskell.packages.ghc8107;

}
