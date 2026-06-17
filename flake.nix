{
  description = "Portable Nix dev shell for AI CLI and MCP tooling";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/3e41b24abd260e8f71dbe2f5737d24122f972158";

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix/6fadaf0ecad1e971e6582c09ac90330a6f73dd92";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix/9bbc8a186eb5fa1e570179a61d870b7cb929a578";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-ai = {
      url = "github:git-ai-project/git-ai/4a9b16f24f11a38e315310fb4dad4c55e3f695fd";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pal-mcp-server = {
      url = "github:BeehiveInnovations/pal-mcp-server/7afc7c1cc96e23992c8f105f960132c657883bb1";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      mcp-servers-nix,
      llm-agents,
      git-ai,
      ...
    }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      overlays = [
        (_final: _prev: { inherit inputs; })
        mcp-servers-nix.overlays.default
        git-ai.overlays.default
        (_final: prev: {
          github-mcp-server =
            prev.callPackage (import "${inputs.nixpkgs}/pkgs/by-name/gi/github-mcp-server/package.nix")
              { };
        })
        (import ./overlays/30-ai-python.nix)
        (import ./overlays/30-ai-llm.nix)
        (import ./overlays/30-ai-mcp.nix)
        (import ./overlays/30-agnix.nix)
        (import ./overlays/30-claude-vault.nix)
        (import ./overlays/30-sherlock-db.nix)
        (import ./overlays/30-vllm-mlx.nix)
      ];

      mkPkgs =
        system:
        import nixpkgs {
          inherit system overlays;
          config.allowUnfree = true;
        };

      optPkg =
        pkgs: name:
        if pkgs ? ${name} && pkgs.lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.${name} then
          [ pkgs.${name} ]
        else
          [ ];

      optAgent =
        system: name:
        let
          agentPackages = llm-agents.packages.${system} or { };
        in
        if agentPackages ? ${name} then [ agentPackages.${name} ] else [ ];

      pythonAiEnv =
        pkgs:
        pkgs.python3.withPackages (
          ps:
          with ps;
          [
            hf-xet
            huggingface-hub
            llm
            openai
            python-dotenv
            requests
            tiktoken
          ]
          ++ pkgs.lib.optionals (pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64 && ps ? llm-mlx) [
            llm-mlx
          ]
          ++ pkgs.lib.optionals (pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64 && ps ? mlx-speech) [
            mlx-speech
          ]
        );

      aiPackagesFor =
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
          inherit (pkgs) lib;
          opt = optPkg pkgs;
          agent = optAgent system;
          appleSilicon = pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64;
          gitAiPackages = git-ai.packages.${system} or { };
        in
        [
          (lib.hiPrio (pythonAiEnv pkgs))
          (lib.hiPrio pkgs.llama-cpp)
          pkgs.nodejs_22
          pkgs.openmpi
          pkgs.qdrant
          pkgs.uv
        ]
        ++ lib.optionals (gitAiPackages ? minimal) [ gitAiPackages.minimal ]
        ++ agent "claude-code"
        ++ agent "ccusage"
        ++ agent "codex"
        ++ agent "droid"
        ++ agent "gemini-cli"
        ++ agent "mcporter"
        ++ agent "opencode"
        ++ opt "agnix"
        ++ opt "claude-replay"
        ++ opt "claude-vault"
        ++ opt "context-hub"
        ++ opt "context7-mcp"
        ++ opt "gguf-tools"
        ++ opt "github-mcp-server"
        ++ opt "guidellm"
        ++ opt "hfdownloader"
        ++ opt "llama-swap"
        ++ opt "openai-whisper"
        ++ opt "pal-mcp-server"
        ++ opt "playwright-mcp"
        ++ opt "qdrant-web-ui"
        ++ opt "rustdocs-mcp-server"
        ++ opt "sherlock-db"
        ++ lib.optionals (pkgs ? mcp-server-sequential-thinking) [
          (lib.hiPrio pkgs.mcp-server-sequential-thinking)
        ]
        ++ lib.optionals pkgs.stdenv.isDarwin (opt "drafts-mcp-server")
        ++ lib.optionals appleSilicon (opt "mlx-lm" ++ opt "mtplx" ++ opt "omlx" ++ opt "vllm-mlx");
    in
    {
      overlays.default = nixpkgs.lib.composeManyExtensions overlays;

      lib.aiPackagesFor = aiPackagesFor;

      devShells = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          default = pkgs.mkShell {
            packages = aiPackagesFor pkgs;

            shellHook = ''
              export DISABLE_AUTOUPDATER="1"
              export ET_NO_TELEMETRY="1"
              export FACTORY_AUTO_UPDATE="false"
              export HF_HUB_ENABLE_HF_TRANSFER="1"
              export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              export REQUESTS_CA_BUNDLE="''${REQUESTS_CA_BUNDLE:-$SSL_CERT_FILE}"
            '';
          };
        }
      );

      packages = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          default = pkgs.buildEnv {
            name = "ai-nix-toolchain";
            paths = aiPackagesFor pkgs;
            ignoreCollisions = true;
          };
        }
      );

      formatter = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        pkgs.writeShellApplication {
          name = "ai-nix-fmt";
          runtimeInputs = [
            pkgs.findutils
            pkgs.nixfmt
          ];
          text = ''
            if [ "$#" -eq 0 ]; then
              mapfile -t nix_files < <(find . -name '*.nix' -not -path './.git/*')
              set -- "''${nix_files[@]}"
            fi

            exec nixfmt "$@"
          '';
        }
      );
    };
}
