{
  description = "Darwin configuration";

  inputs = {
    nix-config-ai.url = "path:./config/ai";

    obr.url = "github:jwiegley/obr";

    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    # Pinned OLDER home-manager, used only by the release-skew gate
    # (checks.<system>.home-manager-release-skew). The shared core must evaluate
    # against both this and master; consumers pin release-25.11 while this repo
    # tracks master, and that asymmetry is what made vulcan carry a local ssh
    # compat shim. Follows the same nixpkgs, so it adds one lock node and no
    # second nixpkgs. See jwiegley/nix-config#29.
    home-manager-release = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    ledger = {
      url = "github:ledger/ledger";
    };

    org-jw = {
      url = "github:jwiegley/org-jw";
      flake = false;
    };

    rag-client = {
      url = "github:jwiegley/rag-client";
      flake = false;
    };

    git-all = {
      url = "github:jwiegley/git-all";
      flake = false;
    };

    gitlib = {
      url = "github:jwiegley/gitlib?submodules=0";
      flake = false;
    };

    libgit2-src = {
      url = "github:jwiegley/libgit2/1dbd0b6fe7752657416fc1c69600fbe9c6e04d61";
      flake = false;
    };

    hours = {
      url = "github:jwiegley/hours";
      flake = false;
    };

    pushme = {
      url = "github:jwiegley/pushme";
      flake = false;
    };

    renamer = {
      url = "github:jwiegley/renamer";
      flake = false;
    };

    sizes = {
      url = "github:jwiegley/sizes";
      flake = false;
    };

    trade-journal = {
      url = "github:jwiegley/trade-journal";
      flake = false;
    };

    una = {
      url = "github:jwiegley/una";
      flake = false;
    };

    gh-to-org = {
      url = "github:jwiegley/gh-to-org";
      flake = false;
    };

    org2jsonl = {
      url = "github:jwiegley/org2jsonl";
      flake = false;
    };

    scripts = {
      url = "github:jwiegley/scripts";
      flake = false;
    };

    git-scripts = {
      url = "github:jwiegley/git-scripts";
      flake = false;
    };

    dirscan = {
      url = "github:jwiegley/dirscan";
      inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    emacs-src = {
      url = "github:emacs-mirror/emacs";
      flake = false;
    };

    org2tc = {
      url = "github:jwiegley/org2tc";
      flake = false;
    };

    stock-trader = {
      url = "git+ssh://gitea@gitea.vulcan.lan:2222/johnw/stock-trader.git";
      flake = false;
    };

    vulcan-crt = {
      url = "path:./config/certs";
      flake = false;
    };
  };

  outputs =
    rootInputs:
    let
      portableInputs = rootInputs.nix-config-ai.lib.inputSet;
      inputs = rootInputs // portableInputs;
    in
    with inputs;
    let
      checkManifest = import ./test/check-manifest.nix;
      rootSystems = checkManifest.systems;
      forAllSystems = nixpkgs.lib.genAttrs rootSystems;
      # The subflake input already evaluates flake/ai.nix through
      # test/ai/compatibility-check.nix, whose per-system guard fail-closes
      # any read of a system's outputs and installs
      # `checks.<system>.compatibility-contract`. Re-importing flake/ai.nix
      # here would evaluate the whole portable flake a second time for
      # identical results.
      portableAi = rootInputs.nix-config-ai;
      stockPkgsFor = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }
      );
      pythonTestEnvFor = forAllSystems (
        system:
        stockPkgsFor.${system}.python3.withPackages (
          pythonPackages: with pythonPackages; [
            packaging
            pyyaml
          ]
        )
      );
      agentTestPkgsFor = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = import ./config/overlays.nix { inherit inputs; };
        }
      );
      hostRegistry = import ./config/hosts/registry.nix;
      mkLinuxHome =
        {
          username,
          hostname,
          system,
          nixManagedAiHomeClass ? null,
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            # Match nixpkgs.config.allowUnfree in config/darwin.nix; without
            # it the package-list (graphite-cli et al.) cannot evaluate.
            config.allowUnfree = true;
            overlays = import ./config/overlays.nix {
              inherit vulcan-crt inputs;
            };
          };
          extraSpecialArgs = {
            inherit hostname inputs;
          }
          // nixpkgs.lib.optionalAttrs (nixManagedAiHomeClass != null) {
            inherit nixManagedAiHomeClass;
          };
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
                  inherit
                    hostname
                    inputs
                    nixManagedAiHomeClass
                    pkgs
                    ;
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

      # Private, evaluation-only fixtures for registry hosts whose real Home
      # Manager modules live in external NixOS repositories. Keeping them out
      # of `homeConfigurations` makes them unavailable as activation targets.
      nixosHomeEvaluationFixtures = nixpkgs.lib.mapAttrs (
        hostname: host:
        mkLinuxHome {
          inherit hostname;
          inherit (host) username system;
        }
      ) (nixpkgs.lib.filterAttrs (_: host: host.activation == "nixos-module") hostRegistry.hosts);
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

      packages = forAllSystems (
        system:
        portableAi.packages.${system}
        // {
          obr = rootInputs.obr.packages.${system}.default;
          python-test-env = pythonTestEnvFor.${system};
        }
      );

      inherit (portableAi)
        apps
        formatter
        overlays
        ;

      # Shared home-manager module for cross-platform use.
      # NixOS hosts import this via: inputs.nix-config (flake = false)
      # and then: imports = [ "${inputs.nix-config}/config/johnw.nix" ];
      homeManagerModules.johnw = import ./config/johnw.nix;

      # Generic standalone Home Manager configurations used for evaluation and
      # smoke tests. Their synthetic hostname keeps concrete named-host gates
      # false; explicit home classes select personal-linux or shared-work fixture
      # behavior.
      homeConfigurations = {
        # Generic ARM64 Linux evaluation surface (not a host switch target).
        "johnw@aarch64-linux" = mkLinuxHome {
          username = "johnw";
          hostname = "linux";
          system = "aarch64-linux";
          nixManagedAiHomeClass = "personal-linux";
        };
        # Generic AMD64 Linux evaluation surface (not a host switch target).
        "jwiegley@x86_64-linux" = mkLinuxHome {
          username = "jwiegley";
          hostname = "linux";
          system = "x86_64-linux";
          nixManagedAiHomeClass = "shared-work";
        };
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = stockPkgsFor.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              coreutils
              statix
              deadnix
              nixfmt
              shellcheck
              shfmt
              go
              golangci-lint
              ruff
              yq
              pythonTestEnvFor.${system}
              lefthook
            ];
          };
        }
        // {
          ai = portableAi.devShells.${system}.default;
        }
      );

      checks =
        let
          rootChecks = forAllSystems (
            system:
            let
              pkgs = stockPkgsFor.${system};
              src = self.outPath;
            in
            {
              ai-lock-coherence = pkgs.callPackage ./test/ai/lock-coherence.nix { inherit src; };
              home-manager-release-skew = pkgs.callPackage ./test/home-manager-release-skew.nix {
                inherit src;
                homeManagerLib = home-manager.lib;
                homeManagerReleaseLib = home-manager-release.lib;
              };
              agent-deck = pkgs.callPackage ./test/home/agent-deck.nix {
                inherit
                  darwinConfigurations
                  homeConfigurations
                  ;
                homeManagerLib = home-manager.lib;
                stockDarwinPkgs = stockPkgsFor."aarch64-darwin";
              };
              claude-mem-pin = pkgs.callPackage ./test/home/claude-mem-pin.nix {
                inherit darwinConfigurations;
              };
              host-behavior = pkgs.callPackage ./test/home/host-behavior.nix {
                inherit
                  darwinConfigurations
                  homeConfigurations
                  nixosHomeEvaluationFixtures
                  ;
              };
              managed-agent-package-selection = pkgs.callPackage ./test/home/managed-agent-package-selection.nix {
                inherit inputs src;
                configured = agentTestPkgsFor.${system};
              };
              obr-ownership = pkgs.callPackage ./test/home/obr-ownership.nix {
                inherit inputs src;
                rootObr = packages.${system}.obr;
              };
              model-sync-state = pkgs.callPackage ./test/ai/model-sync.nix {
                inherit src;
                homeManagerLib = home-manager.lib;
              };
              python-package-fixes = pkgs.callPackage ./test/overlays/python-package-fixes.nix {
                configured = agentTestPkgsFor.${system};
              };
              pi-blackhole-policy = pkgs.callPackage ./test/home/pi-blackhole-policy.nix {
                inherit
                  darwinConfigurations
                  homeConfigurations
                  nixosHomeEvaluationFixtures
                  ;
              };
              syncthing = pkgs.callPackage ./test/home/syncthing.nix {
                inherit
                  darwinConfigurations
                  homeConfigurations
                  nixosHomeEvaluationFixtures
                  ;
              };
              ai-managed-preflight = pkgs.callPackage ./test/ai/managed-preflight.nix {
                inherit src;
                homeManagerLib = home-manager.lib;
              };
              ai-catalog-transport = pkgs.callPackage ./test/ai/catalog-transport.nix {
                inherit src;
                codexPackage = inputs.nix-config-ai.packages.${system}.codex;
                configured = agentTestPkgsFor.${system};
                droidPackage = inputs.nix-config-ai.packages.${system}.droid;
              };
              ai-mcp-registry = pkgs.callPackage ./test/ai/mcp-registry.nix {
                inherit src;
                configured = agentTestPkgsFor.${system};
              };
              coq-overlay = pkgs.callPackage ./test/coq-overlay.nix {
                configured = agentTestPkgsFor.${system};
              };
              edit-env = pkgs.callPackage ./test/overlays/edit-env.nix { };
            }
            // pkgs.lib.optionalAttrs (system == "aarch64-darwin") {
              emacs-head = pkgs.callPackage ./test/overlays/emacs-head.nix {
                inherit darwinConfigurations;
                configured = agentTestPkgsFor.${system};
              };
              pi-node-ca = pkgs.callPackage ./test/home/pi-node-ca.nix {
                inherit darwinConfigurations;
              };
              pi-enabled-models-migration = pkgs.callPackage ./test/home/pi-enabled-models-migration.nix {
                piPackage = portableAi.packages.${system}.pi;
              };
              omlx-proxy-boundary = pkgs.callPackage ./test/home/omlx-proxy.nix {
                inherit darwinConfigurations;
              };
              service-credentials = pkgs.callPackage ./test/home/service-credentials.nix {
                inherit darwinConfigurations src;
              };
              samba-darwin-fixup = pkgs.callPackage ./test/overlays/samba-darwin-fixup.nix { };
            }
            // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
              darwin-overrides-inactive = pkgs.callPackage ./test/ai/overlay-isolation.nix {
                inherit inputs;
                configured = agentTestPkgsFor.${system};
              };
            }
          );
        in
        forAllSystems (
          system:
          let
            declared = portableAi.checks.${system} // rootChecks.${system};
          in
          assert checkManifest.validateDeclared {
            flake = "root";
            inherit declared system;
          };
          declared
        );
    };
}
