{ version ? "0.0" }:

let
  darwin = import <darwin> {};

  home-manager = import ./home-manager/home-manager/home-manager.nix {
    confPath = ./config/home.nix;
    confAttr = "";
  };

in darwin.pkgs.buildEnv rec {
  name = "nix-config-${version}";
  paths = [
    darwin.system
    home-manager.activationPackage
    darwin.pkgs.allEnvs
  ];
  ignoreCollisions = true;
}
