{
  description = "Darwin configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ nixpkgs, home-manager, darwin, ... }: {
    darwinConfigurations =
      let configure = hostname: system: darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit hostname; };
        modules = [
          ./config/darwin.nix
          home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              # useUserPackages = true;
              users.johnw = import ./config/home.nix;
              extraSpecialArgs = { inherit hostname; };
            };
          }
        ];
      };
      in {
        vulcan = configure "vulcan" "x86_64-darwin";
        hermes = configure "hermes" "x86_64-darwin";
        athena = configure "athena" "aarch64-darwin";
      };
  };
}
