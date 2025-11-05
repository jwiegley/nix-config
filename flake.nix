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

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    org-jw = {
      url = "github:jwiegley/org-jw";
    };
  };

  outputs = inputs: with inputs; rec {
    darwinConfigurations =
      let
        overlays = [
          # (final: prev:
          #   let
          #     # patchedNixpkgs = nixpkgs;
          #     patchedNixpkgs =
          #       (import nixpkgs { inherit (prev) system; }).applyPatches {
          #         name = "nixpkgs-unstable-patched";
          #         src = inputs.nixpkgs;
          #         patches = [
          #           (builtins.fetchurl {
          #             url = "https://github.com/NixOS/nixpkgs/pull/440348.diff";
          #             sha256 = "1pin02ljng9d01ywcbhlrlwr64chxs52f1fbvwdhyp4r17p1malp";
          #             # date = "2025-09-09T22:41:46-0700";
          #           })
          #         ];
          #       };
          #     pkgs = import patchedNixpkgs { inherit (prev) system; };
          #   in {
          #     inherit (pkgs)
          #       # 440348
          #       ttfautohint
          #       ;
          #   })
          inputs.mcp-servers-nix.overlays.default
          inputs.claude-code-nix.overlays.default
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
                backupFileExtension = "hm-bak";
                extraSpecialArgs = { inherit system hostname inputs; };

                users.johnw = import ./config/home.nix;
              };
            }
          ];
        };
      in {
        hera = configure "hera" "aarch64-darwin";
        clio = configure "clio" "aarch64-darwin";
      };

    darwinPackages = darwinConfigurations."hera".pkgs;
  };
}
