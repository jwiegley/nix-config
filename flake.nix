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

    ledger.url = "github:ledger/ledger";
    # ledger = {
    #   url = "git+file:///Users/johnw/src/ledger/main";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    org-jw.url = "github:jwiegley/org-jw";
    rag-client.url = "github:jwiegley/rag-client";

    promptdeploy = {
      url = "git+file:///Users/johnw/src/promptdeploy?shallow=0&submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-ai.url = "git+file:///Users/johnw/work/git-ai/git-ai/main";
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
    pal-mcp-server = {
      url = "git+file:///Users/johnw/src/pal-mcp-server";
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

      # Shared home-manager module for cross-platform use.
      # NixOS hosts import this via: inputs.nix-config (flake = false)
      # and then: imports = [ "${inputs.nix-config}/config/johnw.nix" ];
      homeManagerModules.johnw = import ./config/johnw.nix;

      # Standalone home-manager configurations for Linux hosts.
      # Usage:
      #   home-manager switch --flake ~/src/nix#johnw@aarch64-linux
      #   home-manager switch --flake ~/src/nix#jwiegley@x86_64-linux
      homeConfigurations =
        let
          mkLinuxHome =
            username: hostname: system:
            home-manager.lib.homeManagerConfiguration {
              pkgs = import nixpkgs {
                inherit system;
                overlays = import ./config/overlays.nix { inherit inputs; };
              };
              extraSpecialArgs = { inherit hostname inputs; };
              modules = [
                (
                  args:
                  let
                    packages = import ./config/packages.nix args;
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
          # vulcan, vps
          "johnw@aarch64-linux" = mkLinuxHome "johnw" "linux" "aarch64-linux";
          # andoria-*, delphi-*
          "jwiegley@x86_64-linux" = mkLinuxHome "jwiegley" "linux" "x86_64-linux";
        };

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
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
          pkgs = import nixpkgs { inherit system; };
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
                ruff check ${src}/bin/update-overlay
                touch $out
              '';
        }
      );
    };
}
