{
  description = "Portable Nix dev shell for AI CLI and MCP tooling";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-ai = {
      url = "github:git-ai-project/git-ai";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pal-mcp-server = {
      url = "github:BeehiveInnovations/pal-mcp-server";
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

      inherit (nixpkgs) lib;

      forAllSystems = lib.genAttrs systems;

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
        (import ./overlays/30-lazycodex.nix)
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
        ++ opt "lazycodex-ai"
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

      devToolPackages =
        pkgs: with pkgs; [
          deadnix
          findutils
          gawk
          git
          gnugrep
          gnused
          hyperfine
          jq
          lefthook
          nix
          nixfmt
          shellcheck
          shfmt
          statix
        ];

      qualityInputs = pkgs: rec {
        common = with pkgs; [
          bash
          coreutils
          findutils
          gawk
          git
          gnugrep
          gnused
          jq
        ];

        format =
          common
          ++ (with pkgs; [
            nixfmt
            shfmt
          ]);
        lint =
          common
          ++ (with pkgs; [
            deadnix
            shellcheck
            statix
          ]);
        test = common ++ (with pkgs; [ nix ]);
        build = common ++ (with pkgs; [ nix ]);
        coverage = common;
        profile =
          common
          ++ (with pkgs; [
            hyperfine
            nixfmt
          ]);
        fuzz = common ++ (with pkgs; [ nix ]);
        memory = common;
        all =
          common
          ++ (with pkgs; [
            deadnix
            hyperfine
            nix
            nixfmt
            shellcheck
            shfmt
            statix
          ]);
      };

      sourceForChecks = lib.cleanSourceWith {
        src = ./.;
        filter =
          path: _type:
          let
            name = builtins.baseNameOf path;
          in
          !(
            name == ".git"
            || name == ".direnv"
            || name == "build"
            || name == "result"
            || lib.hasPrefix "result-" name
          );
      };

      scriptRoot = ./scripts;

      mkScriptPackage =
        pkgs: name: scriptName: runtimeInputs:
        pkgs.writeShellApplication {
          name = "ai-nix-${name}";
          inherit runtimeInputs;
          text = ''
            exec ${pkgs.bash}/bin/bash ${scriptRoot}/${scriptName} "$@"
          '';
        };

      mkScriptApp =
        pkgs: name: scriptName: runtimeInputs:
        let
          package = mkScriptPackage pkgs name scriptName runtimeInputs;
        in
        {
          type = "app";
          program = "${package}/bin/ai-nix-${name}";
          meta.description = "Run the ai-nix ${name} target";
        };

      mkScriptCheck =
        pkgs: name: scriptName: runtimeInputs: extraEnv:
        pkgs.runCommand "ai-nix-${name}"
          {
            nativeBuildInputs = runtimeInputs;
          }
          ''
            export HOME=$TMPDIR
            export AI_NIX_ROOT=${sourceForChecks}
            export AI_NIX_OUTPUT_ROOT=$TMPDIR/build
            ${extraEnv}

            ${pkgs.bash}/bin/bash ${scriptRoot}/${scriptName}

            mkdir -p "$out"
            if [ -d "$AI_NIX_OUTPUT_ROOT" ]; then
              cp -R "$AI_NIX_OUTPUT_ROOT"/. "$out"/
            fi
            touch "$out/${name}.ok"
          '';
    in
    {
      overlays.default = lib.composeManyExtensions overlays;

      lib.aiPackagesFor = aiPackagesFor;

      devShells = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          default = pkgs.mkShell {
            packages = aiPackagesFor pkgs ++ devToolPackages pkgs;

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

      apps = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          inputs = qualityInputs pkgs;
          app =
            name: scriptName: runtimeInputs:
            mkScriptApp pkgs name scriptName runtimeInputs;
        in
        {
          format = app "format" "format.sh" inputs.format;
          format-check = app "format-check" "format-check.sh" inputs.format;
          lint = app "lint" "lint.sh" inputs.lint;
          test = app "test" "test.sh" inputs.test;
          build-check = app "build-check" "build-check.sh" inputs.build;
          no-warnings = app "no-warnings" "no-warnings.sh" inputs.build;
          coverage = app "coverage" "coverage.sh" inputs.coverage;
          coverage-check = app "coverage-check" "coverage-check.sh" (inputs.coverage ++ [ pkgs.jq ]);
          profile = app "profile" "profile.sh" inputs.profile;
          profile-check = app "profile-check" "profile-check.sh" inputs.profile;
          fuzz = app "fuzz" "fuzz.sh" inputs.fuzz;
          memory-check = app "memory-check" "memory-check.sh" inputs.memory;
          check = app "check" "check.sh" inputs.all;
          default = self.apps.${system}.check;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          inputs = qualityInputs pkgs;
          check =
            name: scriptName: runtimeInputs: extraEnv:
            mkScriptCheck pkgs name scriptName runtimeInputs extraEnv;
        in
        {
          build = self.packages.${system}.default;
          format = check "format" "format-check.sh" inputs.format "";
          lint = check "lint" "lint.sh" inputs.lint "";
          tests = check "tests" "test.sh" inputs.test ''
            export AI_NIX_TEST_SOURCE_ONLY=1
          '';
          coverage = check "coverage" "coverage-check.sh" (inputs.coverage ++ [ pkgs.jq ]) "";
          profile = check "profile" "profile-check.sh" inputs.profile ''
            export AI_NIX_PROFILE_RUNS=1
            export AI_NIX_PROFILE_WARMUP=0
          '';
          fuzz = check "fuzz" "fuzz.sh" inputs.fuzz ''
            export AI_NIX_FUZZ_ITERATIONS=2
          '';
          memory = check "memory" "memory-check.sh" inputs.memory "";
          no-warnings = check "no-warnings" "lint.sh" inputs.lint "";
        }
      );

      formatter = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        mkScriptPackage pkgs "format" "format.sh" (qualityInputs pkgs).format
      );
    };
}
