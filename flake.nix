{
  description = "Darwin configuration";

  inputs = {
    nix-config-ai.url = "path:./config/ai";

    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    ledger = {
      url = "github:ledger/ledger";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    org-jw = {
      url = "github:jwiegley/org-jw";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    rag-client = {
      url = "github:jwiegley/rag-client";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    git-all = {
      url = "git+file:///Users/johnw/src/git-all";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    gitlib = {
      url = "git+file:///Users/johnw/src/gitlib?submodules=0";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    hakyll = {
      url = "git+file:///Users/johnw/src/hakyll";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    hours = {
      url = "git+file:///Users/johnw/src/hours";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    pushme = {
      url = "git+file:///Users/johnw/src/pushme";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    renamer = {
      url = "git+file:///Users/johnw/src/renamer";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    sizes = {
      url = "git+file:///Users/johnw/src/sizes";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    trade-journal = {
      url = "git+file:///Users/johnw/src/trade-journal";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    una = {
      url = "git+file:///Users/johnw/src/una";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    gh-to-org = {
      url = "git+file:///Users/johnw/src/gh-to-org";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    obr = {
      url = "git+file:///Users/johnw/src/obr";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    org2jsonl = {
      url = "git+file:///Users/johnw/src/org2jsonl";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

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
      inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
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
    rootInputs:
    let
      portableInputs = rootInputs.nix-config-ai.lib.inputSet;
      inputs = rootInputs // portableInputs;
    in
    with inputs;
    let
      rootSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      aiSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs rootSystems;
      portableAiDefinition = import ./flake-ai.nix portableInputs;
      portableAi = import ./test/ai/compatibility-check.nix {
        inputs = portableInputs;
        actual = portableAiDefinition;
      };
      stockPkgsFor = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }
      );
      pkgsFor = forAllSystems (
        system:
        if system == "aarch64-darwin" then
          import nixpkgs {
            inherit system;
            overlays = [
              ((import ./overlays/10-emacs.nix) {
                hours = inputs.hours or null;
                emacsSrc = inputs.emacs-src or null;
              })
            ];
          }
        else
          stockPkgsFor.${system}
      );
      agentTestPkgsFor = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = import ./config/overlays.nix { inherit inputs; };
        }
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

      packages = nixpkgs.lib.genAttrs aiSystems (
        system:
        portableAi.packages.${system}
        // {
          anvil-mcp = pkgsFor.${system}.callPackage ./packages/anvil-mcp { };
        }
        // nixpkgs.lib.optionalAttrs (system == "aarch64-darwin") {
          anvil-mcp-dedicated = pkgsFor.${system}.callPackage ./packages/anvil-mcp {
            useDedicatedDarwinEmacs = true;
          };
        }
        // nixpkgs.lib.optionalAttrs (nixpkgs.lib.hasSuffix "-linux" system) {
          anvil-mcp-headless = pkgsFor.${system}.callPackage ./packages/anvil-mcp {
            useHeadlessEmacs = true;
          };
        }
      );

      inherit (portableAi) apps overlays;

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
            {
              username,
              hostname,
              system,
              nixManagedAiHomeClass ? null,
            }:
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
        // nixpkgs.lib.optionalAttrs (builtins.elem system aiSystems) {
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
                      git
                      nix
                      python3
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
                    ruff check \
                      ${src}/bin/agent-deck-litellm-env-test.py \
                      ${src}/bin/codex-litellm-test.py \
                      ${src}/bin/update-overlay \
                      ${src}/bin/update-overlay-test.py \
                      ${src}/packages/anvil-mcp
                    echo "Running Agent Deck LiteLLM environment wrapper tests..."
                    python3 ${src}/bin/agent-deck-litellm-env-test.py
                    echo "Running codex-litellm tests..."
                    python3 ${src}/bin/codex-litellm-test.py
                    echo "Running update-overlay tests..."
                    python3 ${src}/bin/update-overlay-test.py
                    touch $out
                  '';

              ai-home-manager-contract = pkgs.callPackage ./test/ai/home-manager-contract.nix {
                inherit inputs src;
                aiFlake = portableAi;
                agentResources = agentTestPkgsFor.${system}.agent-resources;
                homeManagerLib = home-manager.lib;
                piGallery = agentTestPkgsFor.${system}.pi-gallery;
                testPkgsFor = agentTestPkgsFor;
              };
              ai-lock-coherence = pkgs.callPackage ./test/ai/lock-coherence.nix { inherit src; };
              ai-managed-preflight = pkgs.callPackage ./test/ai/managed-preflight.nix {
                inherit src;
                homeManagerLib = home-manager.lib;
              };
            }
            // pkgs.lib.optionalAttrs (pkgs.stdenv.isLinux || system == "aarch64-darwin") {
              anvil-home-manager = pkgs.callPackage ./packages/anvil-mcp/home-manager-smoke.nix {
                homeManagerLib = home-manager.lib;
                inherit inputs;
                testPkgs = agentTestPkgsFor.${system};
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
              darwin-overrides-inactive = pkgs.callPackage ./test/ai/overlay-isolation.nix {
                inherit inputs;
                configured = agentTestPkgsFor.${system};
              };
              anvil-mcp = pkgs.callPackage ./packages/anvil-mcp/smoke.nix {
                anvilMcp = packages.${system}.anvil-mcp;
              };
              anvil-mcp-headless = pkgs.callPackage ./packages/anvil-mcp/headless-smoke.nix {
                anvilMcp = packages.${system}.anvil-mcp-headless;
              };
            }
            // pkgs.lib.optionalAttrs (system == "aarch64-darwin") {
              gpg-agent-handoff = pkgs.callPackage ./test/darwin/gpg-agent-handoff.nix {
                inherit darwinConfigurations;
              };
              anvil-mcp-dedicated = pkgs.callPackage ./packages/anvil-mcp/headless-smoke.nix {
                anvilMcp = packages.${system}.anvil-mcp-dedicated;
              };
            }
          );
        in
        forAllSystems (
          system:
          nixpkgs.lib.optionalAttrs (builtins.elem system aiSystems) portableAi.checks.${system}
          // rootChecks.${system}
        );
    };
}
