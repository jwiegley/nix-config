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

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ledger = {
      url = "git+file:///Users/johnw/src/ledger/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    org-jw.url = "github:jwiegley/org-jw";
    # ledger.url = "github:ledger/ledger";
    rag-client.url = "github:jwiegley/rag-client";

    promptdeploy = {
      url = "git+file:///Users/johnw/src/promptdeploy?shallow=0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-ai.url = "git+file:///Users/johnw/src/git-ai/main";
    git-all.url = "git+file:///Users/johnw/src/git-all";
    gitlib.url = "git+file:///Users/johnw/src/gitlib?submodules=0";
    hakyll.url = "git+file:///Users/johnw/src/hakyll";
    hours.url = "git+file:///Users/johnw/src/hours";
    pushme.url = "git+file:///Users/johnw/src/pushme";
    renamer.url = "git+file:///Users/johnw/src/renamer";
    sizes.url = "git+file:///Users/johnw/src/sizes";
    trade-journal.url = "git+file:///Users/johnw/src/trade-journal";
    una.url = "git+file:///Users/johnw/src/una";
    gh-to-org.url = "git+file:///Users/johnw/src/gh-to-org";
    obr.url = "git+file:///Users/johnw/src/obr";
    org2jsonl.url = "git+file:///Users/johnw/src/org2jsonl";

    scripts = {
      url = "git+file:///Users/johnw/src/scripts";
      flake = false;
    };
    git-scripts = {
      url = "git+file:///Users/johnw/src/git-scripts";
      flake = false;
    };
    dirscan = {
      url = "git+file:///Users/johnw/src/dirscan";
      flake = false;
    };
    emacs-src = {
      url = "git+file:///Users/johnw/Databases/emacs";
      flake = false;
    };
    org2tc = {
      url = "github:jwiegley/org2tc";
      flake = false;
    };
  };

  outputs =
    inputs: with inputs; rec {
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
            (final: prev: {
              github-mcp-server =
                prev.callPackage (import "${inputs.nixpkgs}/pkgs/by-name/gi/github-mcp-server/package.nix")
                  { };
            })
          ];
          configure =
            hostname: system:
            darwin.lib.darwinSystem {
              specialArgs = {
                inherit
                  darwin
                  hostname
                  inputs
                  overlays
                  ;
              };
              modules = [
                { nixpkgs.hostPlatform = system; }
                ./config/darwin.nix
                home-manager.darwinModules.home-manager
                {
                  home-manager = {
                    useGlobalPkgs = true;
                    useUserPackages = true;
                    backupFileExtension = "hm-bak";
                    extraSpecialArgs = { inherit hostname inputs; };

                    users.johnw = import ./config/home.nix;
                  };
                }
              ];
            };
        in
        {
          hera = configure "hera" "aarch64-darwin";
          clio = configure "clio" "aarch64-darwin";
        };

      darwinPackages = darwinConfigurations."hera".pkgs;
    };
}
