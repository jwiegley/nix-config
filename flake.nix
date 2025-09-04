{
  description = "Darwin configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # nixpkgs.url = "git+file:///Users/johnw/Products/nixpkgs";

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
    #betterfox = {
    #  url = "github:HeitorAugustoLN/betterfox-nix";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #};
    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: with inputs; rec {
    darwinConfigurations =
      let
        overlays = [
          (final: prev:
            let
              # patchedNixpkgs = nixpkgs;
              patchedNixpkgs =
                (import nixpkgs { inherit (prev) system; }).applyPatches {
                  name = "nixpkgs-unstable-patched";
                  src = inputs.nixpkgs;
                  patches = [
                    (builtins.fetchurl {
                      url = "https://github.com/NixOS/nixpkgs/pull/417516.diff";
                      sha256 = "0r3n2pdaq4fm8vdwzh4wnnqdy8svp2pny03jfk55zig9pvgacr93";
                      # date = "2025-08-28T11:57:35-0700";
                    })
                    ./overlays/emacs/patches/emacs30-macport.patch
                  ];
                };
              pkgs = import patchedNixpkgs { inherit (prev) system; };
            in {
              inherit (pkgs)
                # 417516
                llama-swap
                # 423799
                elpaPackages
                melpaPackages
                manualPackages
                elpaBuild
                melpaBuild
                trivialBuild
                emacs30
                emacs30-macport
                ;
            })
          nurpkgs.overlays.default
          mcp-servers-nix.overlays.default
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
                #sharedModules = [
                #  inputs.betterfox.homeManagerModules.betterfox
                #];
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
