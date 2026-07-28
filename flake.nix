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
      url = "github:jwiegley/git-all/a3dc16f5a45dbd7fda347d9b58dd713b654a7031";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    gitlib = {
      url = "github:jwiegley/gitlib/119009b2cf1866e0c776f8e9ebcfed46f914d314?submodules=0";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    hakyll = {
      url = "github:jwiegley/hakyll/023b4124ab791e3b436b554434be42f2f86a2f7b";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    hours = {
      url = "github:jwiegley/hours/a5874f56f7c62ad841d8830176e9c4a54710f43a";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    pushme = {
      url = "github:jwiegley/pushme/f8ea0cc7c47a7ea8e6d3755f58284b0b8a9ad42d";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    renamer = {
      url = "github:jwiegley/renamer/971df26662ef4af621dafce1f9527c0c97c080b0";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    sizes = {
      url = "github:jwiegley/sizes/821d3d5d4fd071ffd49d3a499a4140712ea610c9";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    trade-journal = {
      url = "github:jwiegley/trade-journal/4531503f65cad5c7a744cc382188b71cf3fc21a1";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    una = {
      url = "github:jwiegley/una/745f2efc7a9e9fe0981017eeff7500eaaf7fd320";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    gh-to-org = {
      url = "github:jwiegley/gh-to-org/4126e800315afabdaa5c5821e3c4fc54824bc123";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    obr = {
      url = "github:jwiegley/obr/fcbbce29aef9605e9e07c3031a013cbb64ee0c04";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
      #
      # obr's own committed flake.lock pins its org2jsonl input at a local
      # filesystem URL under this machine's home directory, and Nix folds that
      # transitive lock into this repo's closure. That single node was the only
      # reason this lock was not 100% fetchable by an external consumer.
      #
      # The literal URL is deliberately not written here: the purity gate in
      # bin/update-overlay-test.py forbids that scheme appearing in flake.nix at
      # all, and it is right to — a comment quoting it is indistinguishable from
      # a declaration using it.
      #
      # Point it at the org2jsonl this repo already declares. A `follows` is used
      # rather than pinning obr to a newer revision whose lock happens to be
      # clean, because `follows` keeps the property true regardless of obr's
      # future lock hygiene — the leak cannot come back through an obr bump.
      inputs.org2jsonl.follows = "org2jsonl";
    };

    org2jsonl = {
      url = "github:jwiegley/org2jsonl/59521f99a490703d4d02f9b0f312a92ec9135ba8";
      # inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    scripts = {
      url = "github:jwiegley/scripts/3bfc546d418fd0324c481b4dcfe0d4fe42ab3af1";
      flake = false;
    };

    git-scripts = {
      url = "github:jwiegley/git-scripts/27614fb2b4937aab09ca2701e8dd0a0f7c760fb7";
      flake = false;
    };

    dirscan = {
      url = "github:jwiegley/dirscan/8e03e1bbd32d2f924deb858070f9c6a152e8e319";
      inputs.nixpkgs.follows = "nix-config-ai/nixpkgs";
    };

    emacs-src = {
      url = "github:emacs-mirror/emacs/0f086c307c12b74aeedfba07cfe5b57ef2f99808";
      flake = false;
    };

    org2tc = {
      url = "github:jwiegley/org2tc";
      flake = false;
    };

    stock-trader = {
      url = "git+ssh://gitea/johnw/stock-trader.git?rev=51d7895348a44681d8a450d8e21a725278eecfe5";
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

      # `nix fmt` must format the tree, not read stdin.
      #
      # This was previously the raw `nixfmt` package. `nix fmt` execs the
      # formatter verbatim without injecting any paths, so with no arguments
      # nixfmt fell back to reading stdin: a bare `nix fmt` formatted nothing,
      # and `nix fmt -- --check` died with "unexpected end of input". The gate
      # only ever passed because lefthook and CI called nixfmt directly with a
      # file list, never through `nix fmt`.
      #
      # With no path arguments this delegates to bin/quality, so `nix fmt`,
      # `make format` and the pre-commit hook are the same operation over the
      # same discovered file set (jwiegley/nix-config#46). It deliberately runs
      # the working tree's bin/quality rather than a store copy: a formatter
      # should use the tool as it currently exists in the tree it is formatting,
      # and a store copy would silently format with a stale version after an
      # edit. With explicit path arguments it dispatches by extension, matching
      # the portable subflake's format.sh.
      formatter = forAllSystems (
        system:
        let
          pkgs = stockPkgsFor.${system};
        in
        pkgs.writeShellApplication {
          name = "nix-config-format";
          runtimeInputs = with pkgs; [
            nixfmt
            shfmt
            git
          ];
          text = ''
            # Whole-tree modes, both delegated so there is one discovery.
            #   nix fmt              → rewrite
            #   nix fmt -- --check   → check only, rewrite nothing
            mode=--fix
            if [ "$#" -eq 1 ] && [ "$1" = "--check" ]; then
              mode=--check-only
              shift
            fi

            if [ "$#" -gt 0 ]; then
              nix_files=()
              shell_files=()
              for path in "$@"; do
                case "$path" in
                # An unrecognized flag must NOT be silently ignored. Exiting 0
                # having formatted nothing is a fake pass, and a formatter that
                # lies about success is worse than one that is merely broken.
                -*)
                  echo "nix fmt: unrecognized option: $path" >&2
                  echo "         Supported: no arguments (format the tree)," >&2
                  echo "         --check (check the tree), or explicit paths." >&2
                  exit 2
                  ;;
                *.nix) nix_files+=("$path") ;;
                *.sh | *.bash) shell_files+=("$path") ;;
                *)
                  echo "nix fmt: no formatter for: $path" >&2
                  exit 2
                  ;;
                esac
              done
              if [ "''${#nix_files[@]}" -gt 0 ]; then
                nixfmt "''${nix_files[@]}"
              fi
              if [ "''${#shell_files[@]}" -gt 0 ]; then
                shfmt -i 4 -w "''${shell_files[@]}"
              fi
              exit 0
            fi

            root=$(git rev-parse --show-toplevel 2>/dev/null) || {
              echo "nix fmt: not inside a git work tree, and no paths were given." >&2
              echo "         Pass explicit paths, or run from the repository." >&2
              exit 2
            }
            cd "$root"
            [ -x bin/quality ] || {
              echo "nix fmt: $root/bin/quality is missing or not executable." >&2
              exit 2
            }
            if [ "$mode" = --fix ]; then
              exec bin/quality --fix nix-format shell-format
            fi
            exec bin/quality nix-format shell-format
          '';
        }
      );

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
              home-manager-release-skew = pkgs.callPackage ./test/home-manager-release-skew.nix {
                inherit src;
                homeManagerReleaseLib = home-manager-release.lib;
              };
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
