{
  description = "Darwin configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rycee-nurpkgs = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nurpkgs = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # arkenfox = {
    #   url = "github:dwarfmaster/arkenfox-nixos";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    betterfox = {
      url = "github:HeitorAugustoLN/betterfox-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: with inputs; rec {
    darwinConfigurations =
      let configure = hostname: system: darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit hostname inputs; };
        modules = [
          ./config/darwin.nix
          home-manager.darwinModules.home-manager
          # arkenfox.hmModules.default
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              sharedModules = [
                # inputs.arkenfox.hmModules.default
                inputs.betterfox.homeManagerModules.betterfox
              ];
              users.johnw = import ./config/home.nix;

              backupFileExtension = "hm-bak";
              extraSpecialArgs = { inherit hostname inputs; };
            };
          }
        ];
      };
      in {
        hera   = configure "hera"   "aarch64-darwin";
        clio   = configure "clio"   "aarch64-darwin";
        athena = configure "athena" "aarch64-darwin";
        vulcan = configure "vulcan" "x86_64-darwin";
      };

    darwinPackages = darwinConfigurations."hera".pkgs;
  };
}
