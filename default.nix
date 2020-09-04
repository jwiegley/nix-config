{ nixpkgs       ? ./nixpkgs
, system        ? builtins.currentSystem
, pkgs          ? import nixpkgs { inherit system; }
, configuration ? ./config/darwin.nix
, darwin        ? import ./darwin { inherit nixpkgs configuration system pkgs; }
, home-manager  ? import ./home-manager/home-manager/home-manager.nix {
    inherit pkgs;
    confPath = ./config/home.nix;
    confAttr = "";
  }
}: {
  nix-darwin = darwin.system;
  home-manager = home-manager.activationPackage;
}
