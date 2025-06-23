{
  description = "Darwin configuration";

  inputs = {
    # nixpkgs.url = "git+file:///Users/johnw/Products/nixpkgs";
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
    betterfox = {
      url = "github:HeitorAugustoLN/betterfox-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # mcp-servers-nix = {
    #   url = "github:natsukium/mcp-servers-nix";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = inputs: with inputs; rec {
    darwinConfigurations =
      let
        overlays = with inputs; [
          (final: prev:
            let
              pkgs = (import nixpkgs { system = prev.system; }).extend (
                _final: prev: {
                  ld64 = prev.ld64.overrideAttrs (o: {
                    patches = o.patches ++ [./overlays/Dedupe-RPATH-entries.patch];
                  });
                  libarchive = prev.libarchive.overrideAttrs (_old: {
                    doCheck = false;
                  });
                }
              ); in {
                inherit (pkgs) emacs30;
              })
          nurpkgs.overlays.default
          # mcp-servers-nix.overlays.default
        ];
        configure = hostname: system: darwin.lib.darwinSystem {
          inherit inputs system;
          specialArgs = {
            inherit darwin system hostname inputs overlays;
          };
          modules = [
            ./config/darwin.nix
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                sharedModules = [
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
      };

    darwinPackages = darwinConfigurations."hera".pkgs;
  };
}
