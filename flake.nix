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
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    kadena-nix = {
      url = "github:kadena-io/kadena-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: with inputs; rec {
    darwinConfigurations =
      let configure = hostname: system: darwin.lib.darwinSystem {
        # pkgs = import nixpkgs {
        #   inherit system;
        #   config = {
        #     allowUnfree = true;
        #     allowBroken = false;
        #     allowInsecure = false;
        #     allowUnsupportedSystem = false;

        #     permittedInsecurePackages = [
        #       "python-2.7.18.7"
        #       "libressl-3.4.3"
        #     ];
        #   };

        #   overlays =
        #     let path = ./overlays; in with builtins;
        #     map (n: import (path + ("/" + n)))
        #         (filter (n: match ".*\\.nix" n != null ||
        #                     pathExists (path + ("/" + n + "/default.nix")))
        #                 (attrNames (readDir path)))
        #       ++ [ (import ./config/envs.nix) ];
        # };
        inherit system;
        specialArgs = { inherit hostname inputs; };
        modules = [
          ./config/darwin.nix
          home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              # useUserPackages = true;
              users.johnw = import ./config/home.nix;
              extraSpecialArgs = { inherit hostname inputs; };
            };
          }
        ];
      };
      in {
        vulcan = configure "vulcan" "x86_64-darwin";
        hermes = configure "hermes" "x86_64-darwin";
        athena = configure "athena" "aarch64-darwin";
      };

    darwinPackages = darwinConfigurations."vulcan".pkgs;
  };
}
