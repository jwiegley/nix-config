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

    promptdeploy = {
      url = "github:jwiegley/promptdeploy/4c9b2c1c10df5048b239051d79c3df00b1d0276b";
      inputs = {
        flake-utils.follows = "git-all/flake-utils";
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    ai-nix = {
      url = "github:jwiegley/ai-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-ai.follows = "ai-nix/git-ai";
    llm-agents.follows = "ai-nix/llm-agents";

    ledger.url = "github:ledger/ledger";
    # ledger = {
    #   url = "git+file:///Users/johnw/src/ledger/main";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    org-jw.url = "github:jwiegley/org-jw";
    rag-client.url = "github:jwiegley/rag-client";
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
      inputs.nixpkgs.follows = "nixpkgs";
    };
    emacs-src = {
      url = "git+file:///Users/johnw/Databases/emacs";
      flake = false;
    };
    org2tc = {
      url = "github:jwiegley/org2tc";
      flake = false;
    };
    stock-trader = {
      url = "git+file:///Users/johnw/src/stock-trader";
      flake = false;
    };
    vulcan-crt = {
      url = "file:///Users/johnw/.config/curl/vulcan-root-ca.crt";
      flake = false;
    };
  };

  outputs =
    inputs:
    with inputs;
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      stockPkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
      pkgsFor = forAllSystems (
        system:
        if system == "aarch64-darwin" then
          import nixpkgs {
            inherit system;
            overlays = [
              (_final: _prev: { inherit inputs; })
              (import ./overlays/10-emacs.nix)
            ];
          }
        else
          stockPkgsFor.${system}
      );
    in
    rec {
      darwinConfigurations =
        let
          configure =
            hostname: system:
            darwin.lib.darwinSystem {
              specialArgs = {
                inherit
                  darwin
                  hostname
                  inputs
                  vulcan-crt
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

      packages = {
        "aarch64-darwin" = {
          anvil-mcp = pkgsFor."aarch64-darwin".callPackage ./packages/anvil-mcp { };
          anvil-mcp-dedicated = pkgsFor."aarch64-darwin".callPackage ./packages/anvil-mcp {
            useDedicatedDarwinEmacs = true;
          };
        };
        "aarch64-linux" = {
          anvil-mcp = pkgsFor."aarch64-linux".callPackage ./packages/anvil-mcp { };
          anvil-mcp-headless = pkgsFor."aarch64-linux".callPackage ./packages/anvil-mcp {
            useHeadlessEmacs = true;
          };
        };
        "x86_64-linux" = {
          anvil-mcp = pkgsFor."x86_64-linux".callPackage ./packages/anvil-mcp { };
          anvil-mcp-headless = pkgsFor."x86_64-linux".callPackage ./packages/anvil-mcp {
            useHeadlessEmacs = true;
          };
        };
      };

      # Shared home-manager module for cross-platform use.
      # NixOS hosts import this via: inputs.nix-config (flake = false)
      # and then: imports = [ "${inputs.nix-config}/config/johnw.nix" ];
      homeManagerModules.johnw = import ./config/johnw.nix;

      # Generic standalone Home Manager configurations used for evaluation and
      # smoke tests.  Their synthetic hostname is deliberately "linux", so
      # host-gated features retain their defaults.  Real machines switch their
      # own flakes: /etc/nixos on NixOS hosts such as Vulcan and VPS, and
      # ~/.config/home-manager on the shared-home Andoria/Delphi/GPU hosts.
      homeConfigurations =
        let
          mkLinuxHome =
            username: hostname: system:
            home-manager.lib.homeManagerConfiguration {
              pkgs = import nixpkgs {
                inherit system;
                # Match nixpkgs.config.allowUnfree in config/darwin.nix;
                # without it the package-list (graphite-cli et al.) refuses
                # to evaluate on the standalone Linux surface.
                config.allowUnfree = true;
                overlays = import ./config/overlays.nix {
                  inherit vulcan-crt inputs;
                };
              };
              extraSpecialArgs = { inherit hostname inputs; };
              modules = [
                (
                  {
                    pkgs,
                    hostname,
                    inputs,
                    ...
                  }:
                  let
                    packages = import ./config/packages.nix {
                      inherit hostname inputs pkgs;
                    };
                  in
                  {
                    imports = [ ./config/johnw.nix ];
                    targets.genericLinux.enable = true;
                    home = {
                      inherit username;
                      homeDirectory = "/home/${username}";
                      stateVersion = "23.11";
                      packages = packages.package-list;
                    };
                  }
                )
              ];
            };
        in
        {
          # Generic ARM64 Linux evaluation surface (not a host switch target).
          "johnw@aarch64-linux" = mkLinuxHome "johnw" "linux" "aarch64-linux";
          # Generic AMD64 Linux evaluation surface (not a host switch target).
          "jwiegley@x86_64-linux" = mkLinuxHome "jwiegley" "linux" "x86_64-linux";
        };

      formatter = forAllSystems (system: stockPkgsFor.${system}.nixfmt);

      devShells = forAllSystems (
        system:
        let
          pkgs = stockPkgsFor.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              statix
              deadnix
              nixfmt
              shellcheck
              shfmt
              ruff
              lefthook
            ];
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = stockPkgsFor.${system};
          src = builtins.path {
            path = ./.;
            name = "nix-config-src";
            filter =
              path: type:
              let
                baseName = baseNameOf path;
              in
              !(
                baseName == "result"
                || baseName == ".git"
                || baseName == ".DS_Store"
                || baseName == ".claude"
                || baseName == ".worktrees"
              );
          };
        in
        {
          formatting =
            pkgs.runCommand "check-formatting"
              {
                nativeBuildInputs = with pkgs; [
                  nixfmt
                  shfmt
                  findutils
                ];
              }
              ''
                echo "Checking Nix formatting..."
                find ${src} -name '*.nix' | xargs nixfmt --check
                echo "Checking shell formatting..."
                for f in $(find ${src}/bin -maxdepth 1 -type f) ${src}/build; do
                  if head -1 "$f" | grep -q bash; then
                    shfmt -i 4 -d "$f"
                  fi
                done
                touch $out
              '';

          linting =
            pkgs.runCommand "check-linting"
              {
                nativeBuildInputs = with pkgs; [
                  statix
                  deadnix
                  shellcheck
                  ruff
                  findutils
                ];
              }
              ''
                echo "Running statix..."
                statix check ${src}
                echo "Running deadnix..."
                deadnix --no-lambda-arg --no-lambda-pattern-names --no-underscore --fail ${src}
                echo "Running shellcheck..."
                for f in $(find ${src}/bin -maxdepth 1 -type f) ${src}/build; do
                  if head -1 "$f" | grep -q bash; then
                    shellcheck --severity=warning "$f"
                  fi
                done
                echo "Running ruff..."
                ruff check ${src}/bin/update-overlay ${src}/packages/anvil-mcp
                touch $out
              '';

        }
        // pkgs.lib.optionalAttrs (pkgs.stdenv.isLinux || system == "aarch64-darwin") {
          anvil-home-manager = pkgs.callPackage ./packages/anvil-mcp/home-manager-smoke.nix {
            homeManagerLib = home-manager.lib;
            inherit inputs;
            testPkgs = pkgsFor.${system};
          };
          anvil-mcp-persistent-soak = pkgs.callPackage ./packages/anvil-mcp/persistent-bridge-soak.nix {
            anvilMcp =
              if pkgs.stdenv.isLinux then
                packages.${system}.anvil-mcp-headless
              else
                packages.${system}.anvil-mcp-dedicated;
          };
        }
        // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          anvil-mcp = pkgs.callPackage ./packages/anvil-mcp/smoke.nix {
            anvilMcp = packages.${system}.anvil-mcp;
          };
          anvil-mcp-headless = pkgs.callPackage ./packages/anvil-mcp/headless-smoke.nix {
            anvilMcp = packages.${system}.anvil-mcp-headless;
          };
        }
        // pkgs.lib.optionalAttrs (system == "aarch64-darwin") {
          anvil-mcp-dedicated = pkgs.callPackage ./packages/anvil-mcp/headless-smoke.nix {
            anvilMcp = packages.${system}.anvil-mcp-dedicated;
          };
        }
      );
    };
}
