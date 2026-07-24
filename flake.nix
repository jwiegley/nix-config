{
  description = "Darwin configuration";

  inputs = {
    agent-browser-source = {
      url = "github:vercel-labs/agent-browser/1ed371f3af472cc0d6cd8fdaea75d1a085ff7534";
      flake = false;
    };

    # nixpkgs.url = "git+file:///Users/johnw/Products/nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    rust-overlay = {
      url = "github:oxalica/rust-overlay/47759faaddf38fadaf172151ca9df8adae9c0b2e";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents.url = "github:numtide/llm-agents.nix";

    bigpowers = {
      url = "github:danielvm-git/bigpowers/960ab5283e7b7766f02fbf8703da5bb6e997159d";
      flake = false;
    };

    ponytail = {
      url = "github:DietrichGebert/ponytail/16f29800fd2681bdf24f3eb4ccffe38be3baec6b";
      flake = false;
    };

    translate-tool = {
      url = "github:jwiegley/translate-tool/bffdb7ba3e5db603ea1390fee555354c1d45d642";
      flake = false;
    };

    pi-mcp-adapter = {
      url = "github:nicobailon/pi-mcp-adapter/82724dccc13a49310530898f922bafff12b7f3fe";
      flake = false;
    };

    pi-hashline-edit-pro = {
      url = "github:YuGiMob/pi-hashline-edit-pro/5d97f2a0d8aaa0e06a637583845263ed2ca455f1";
      flake = false;
    };

    pi-web-access = {
      url = "github:nicobailon/pi-web-access/7bdc30a65cf77273eb9c0034647b373bda4060d7";
      flake = false;
    };

    pi-lens = {
      url = "github:apmantza/pi-lens/2ea8691a25e3a39bf944e0d1c5ed4178c50b55da";
      flake = false;
    };

    pi-dynamic-workflows = {
      url = "github:QuintinShaw/pi-dynamic-workflows/6d866e16396ca487dfde2591dd4d4e7ab04e9ba1";
      flake = false;
    };

    pi-agent-browser-native = {
      url = "github:fitchmultz/pi-agent-browser-native/211a012c9b199d758768e8ba729f35e11e661f65";
      flake = false;
    };

    lean-ctx = {
      url = "github:yvgude/lean-ctx/54e0a66bcbb9a6695e45848d3ea97a491a0b5275";
      flake = false;
    };

    pi-openai-server-compaction = {
      url = "github:algal/pi-openai-server-compaction/c6d593087709e9481223dc6c6c2269b371b5e055";
      flake = false;
    };

    pi-quiet = {
      url = "github:zenspc/pi-extensions/b281afef4e61188e7aa76aaa114ba505274fa7bc";
      flake = false;
    };

    pi-subagent = {
      url = "github:mjakl/pi-subagent/70248dcf7c8a5ca74497e817a699f009c55e6917";
      flake = false;
    };

    mcp-remote = {
      url = "github:geelen/mcp-remote/02619aff36e79803d7c894e8c8ae7b34b2d11f8c";
      flake = false;
    };

    git-ai = {
      url = "github:git-ai-project/git-ai";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pal-mcp-server = {
      url = "github:jwiegley/pal-mcp-server";
      flake = false;
    };

    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
      rootSystems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      aiSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs rootSystems;
      portableInputs = {
        inherit (inputs)
          agent-browser-source
          bigpowers
          git-ai
          lean-ctx
          llm-agents
          mcp-remote
          mcp-servers-nix
          nixpkgs
          pal-mcp-server
          pi-agent-browser-native
          pi-dynamic-workflows
          pi-hashline-edit-pro
          pi-lens
          pi-mcp-adapter
          pi-openai-server-compaction
          pi-quiet
          pi-subagent
          pi-web-access
          ponytail
          rust-overlay
          translate-tool
          ;
      };
      portableAiDefinition = import ./packages/ai-flake-outputs.nix portableInputs;
      portableAi = import ./tests/ai/compatibility-check.nix {
        inputs = portableInputs;
        actual = portableAiDefinition;
      };
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

      inherit (portableAi) apps;

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

              ai-home-manager-smoke = pkgs.callPackage ./packages/ai-home-manager-smoke.nix {
                inherit inputs src;
                aiFlake = portableAi;
                agentResources = agentTestPkgsFor.${system}.agent-resources;
                homeManagerLib = home-manager.lib;
                piGallery = agentTestPkgsFor.${system}.pi-gallery;
                testPkgsFor = agentTestPkgsFor;
              };
              ai-managed-preflight-smoke = pkgs.callPackage ./packages/ai-managed-preflight-smoke.nix {
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
        in
        forAllSystems (
          system:
          nixpkgs.lib.optionalAttrs (builtins.elem system aiSystems) portableAi.checks.${system}
          // rootChecks.${system}
        );
    };
}
