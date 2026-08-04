{
  description = "Darwin configuration";

  inputs = {
    nix-config-ai.url = "path:./config/fleet";

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
    };

    rag-client = {
      url = "github:jwiegley/rag-client";
    };

    git-all = {
      url = "github:jwiegley/git-all";
    };

    gitlib = {
      url = "github:jwiegley/gitlib?submodules=0";
    };

    hours = {
      url = "github:jwiegley/hours";
    };

    pushme = {
      url = "github:jwiegley/pushme";
    };

    renamer = {
      url = "github:jwiegley/renamer";
    };

    sizes = {
      url = "github:jwiegley/sizes";
    };

    trade-journal = {
      url = "github:jwiegley/trade-journal";
    };

    una = {
      url = "github:jwiegley/una";
    };

    gh-to-org = {
      url = "github:jwiegley/gh-to-org";
    };

    obr = {
      url = "github:jwiegley/obr";
      #
      # obr's own committed flake.lock pins its org2jsonl input at a local
      # filesystem URL under this machine's home directory, and Nix folds that
      # transitive lock into this repo's closure. That single node was the only
      # reason this lock was not 100% fetchable by an external consumer.
      #
      # The literal URL is deliberately not written here: the purity gate in
      # test/bin/update-overlay-slow-test.py forbids that scheme appearing in flake.nix at
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
      url = "github:jwiegley/org2jsonl";
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
      portableAiDefinition = import ./flake/ai.nix portableInputs;
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

      packages = nixpkgs.lib.genAttrs aiSystems (system: portableAi.packages.${system});

      inherit (portableAi) apps overlays;

      # Shared home-manager module for cross-platform use.
      # NixOS hosts import this via: inputs.nix-config (flake = false)
      # and then: imports = [ "${inputs.nix-config}/config/johnw.nix" ];
      homeManagerModules.johnw = import ./config/johnw.nix;

      # Generic standalone Home Manager configurations used for evaluation and
      # smoke tests. Their synthetic hostname keeps concrete named-host gates
      # false; explicit home classes select personal-linux or shared-work fixture
      # behavior.
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
                      homeClass = nixManagedAiHomeClass;
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

      # Whole-tree rewrite/check modes delegate to the working tree's quality
      # formatter. Explicit paths dispatch directly to nixfmt or shfmt.
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
            [ -x test/bin/quality ] || {
              echo "nix fmt: $root/test/bin/quality is missing or not executable." >&2
              exit 2
            }
            if [ "$mode" = --fix ]; then
              exec test/bin/quality --fix nix-format shell-format
            fi
            exec test/bin/quality nix-format shell-format
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
              python3
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
              ai-lock-coherence = pkgs.callPackage ./test/ai/lock-coherence.nix { inherit src; };
              home-manager-release-skew = pkgs.callPackage ./test/home-manager-release-skew.nix {
                inherit src;
                homeManagerReleaseLib = home-manager-release.lib;
              };
              darwin-value-surface = pkgs.callPackage ./test/darwin/darwin-value-surface.nix {
                inherit darwinConfigurations;
              };
              ai-managed-preflight = pkgs.callPackage ./test/ai/managed-preflight.nix {
                inherit src;
                homeManagerLib = home-manager.lib;
              };
              ai-catalog-transport = pkgs.callPackage ./test/ai/catalog-transport.nix {
                inherit src;
              };
            }
            // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
              darwin-overrides-inactive = pkgs.callPackage ./test/ai/overlay-isolation.nix {
                inherit inputs;
                configured = agentTestPkgsFor.${system};
              };
            }
            // pkgs.lib.optionalAttrs (system == "aarch64-darwin") {
              gpg-agent-handoff = pkgs.callPackage ./test/darwin/gpg-agent-handoff.nix {
                inherit darwinConfigurations;
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
