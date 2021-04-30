{ ... }:

let darwin = import ./darwin rec {
      nixpkgs       = ./nixpkgs;
      configuration = ./config/darwin.nix;
      system        = builtins.currentSystem;
      pkgs          = import nixpkgs { inherit system; };
    }; in
{
  nix-darwin = darwin.system;
}
