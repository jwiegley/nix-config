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
      url = "github:jwiegley/pal-mcp-server";
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
        (import ./overlays/30-agent-deck.nix)
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

      patchAgentPackage =
        pkgs: name: package:
        if name == "codex" then
          let
            codexWrapper = pkgs.writeShellScript "codex" ''
              set -euo pipefail
              umask 077

              # $HOME (and so ~/.codex) is shared over NFS across hosts.
              # Concurrent cross-host writers corrupt SQLite databases, so
              # keep CODEX_HOME shared and move only the conflict-prone
              # state -- the SQLite databases and the fixed-name tui log --
              # to machine-local disk.  Everything else (config, auth,
              # sessions, history, prompts) stays shared.
              codex_shared_home="''${CODEX_HOME:-''${HOME:?}/.codex}"
              codex_uid="$(${pkgs.coreutils}/bin/id -u)"
              codex_local_root="/var/tmp/codex-$codex_uid"
              export CODEX_SQLITE_HOME="''${CODEX_SQLITE_HOME:-$codex_local_root/sqlite}"

              # /var/tmp is world-writable: fail closed, and loudly, if the
              # local root cannot be created or is not a plain directory we
              # own (pre-creation / symlink planting by another local user).
              # Falling back to the shared home would silently reintroduce
              # the cross-host corruption this wrapper exists to prevent.
              # The root is validated and locked down to 700 before anything
              # is created beneath it.
              if ! ${pkgs.coreutils}/bin/mkdir -p "$codex_local_root"; then
                echo "codex: cannot create host-local state under $codex_local_root" >&2
                exit 1
              fi
              if [ -L "$codex_local_root" ] || [ ! -d "$codex_local_root" ] \
                || [ "$(${pkgs.coreutils}/bin/stat -c %u "$codex_local_root")" != "$codex_uid" ]; then
                echo "codex: refusing $codex_local_root: not a directory owned by uid $codex_uid" >&2
                exit 1
              fi
              ${pkgs.coreutils}/bin/chmod 700 "$codex_local_root" 2>/dev/null || true
              if ! ${pkgs.coreutils}/bin/mkdir -p \
                  "$codex_local_root/sqlite" "$codex_local_root/log" \
                || [ -L "$codex_local_root/sqlite" ] || [ -L "$codex_local_root/log" ]; then
                echo "codex: cannot create state directories under $codex_local_root" >&2
                exit 1
              fi
              ${pkgs.coreutils}/bin/chmod 700 \
                "$codex_local_root/sqlite" "$codex_local_root/log" 2>/dev/null || true

              # One-time seed per host: carry accumulated memories from the
              # shared home into this host's local databases.  The mkdir is
              # an atomic mutex so concurrent first runs seed at most once,
              # and the temp-copy + no-clobber mv means no codex ever
              # observes a partially copied file.  The mutex is released
              # after every attempt: the file-existence guard prevents
              # steady-state re-seeding, while a transiently failed copy
              # (NFS stall) can retry on the next launch.  Only the main DB
              # file is copied: it is self-consistent as of its last
              # checkpoint, whereas a -wal/-shm trio copied from a live NFS
              # database can be mutually inconsistent.  (A torn copy of a
              # concurrently-written main file is possible during the
              # transition window; codex detects and rebuilds a bad DB.)
              # The state DB rebuilds itself from shared rollout files;
              # logs and goals start fresh.
              if [ -f "$codex_shared_home/memories_1.sqlite" ] \
                && [ ! -e "$CODEX_SQLITE_HOME/memories_1.sqlite" ] \
                && ${pkgs.coreutils}/bin/mkdir "$CODEX_SQLITE_HOME/.memories-seed-lock" 2>/dev/null; then
                codex_seed_tmp="$CODEX_SQLITE_HOME/.memories_1.sqlite.seed.$$"
                trap '${pkgs.coreutils}/bin/rm -f "$codex_seed_tmp" 2>/dev/null;
                      ${pkgs.coreutils}/bin/rmdir "$CODEX_SQLITE_HOME/.memories-seed-lock" 2>/dev/null' \
                  EXIT INT TERM
                if ${pkgs.coreutils}/bin/cp \
                    "$codex_shared_home/memories_1.sqlite" "$codex_seed_tmp" 2>/dev/null; then
                  ${pkgs.coreutils}/bin/mv -n \
                    "$codex_seed_tmp" "$CODEX_SQLITE_HOME/memories_1.sqlite" 2>/dev/null || true
                fi
                ${pkgs.coreutils}/bin/rm -f "$codex_seed_tmp" 2>/dev/null || true
                ${pkgs.coreutils}/bin/rmdir "$CODEX_SQLITE_HOME/.memories-seed-lock" 2>/dev/null || true
                trap - EXIT INT TERM
              fi

              # The tui appends to a fixed-name, lock-free log and unlinks it
              # on startup; cross-host that tears lines and litters .nfs*
              # files.  Point the shared log path at machine-local disk.
              codex_log_dir="$codex_shared_home/log"
              if [ -d "$codex_log_dir" ] && [ ! -L "$codex_log_dir" ]; then
                ${pkgs.coreutils}/bin/rmdir "$codex_log_dir" 2>/dev/null \
                  || ${pkgs.coreutils}/bin/mv "$codex_log_dir" "$codex_log_dir.pre-host-state.$$" 2>/dev/null \
                  || true
              fi
              if [ ! -e "$codex_log_dir" ] && [ ! -L "$codex_log_dir" ]; then
                ${pkgs.coreutils}/bin/ln -s "$codex_local_root/log" "$codex_log_dir" 2>/dev/null || true
              fi

              exec -a codex @codex_unwrapped@ "$@"
            '';
          in
          pkgs.symlinkJoin {
            name = "${package.name or name}-host-state";
            paths = [ package ];
            postBuild = ''
              rm -f "$out/bin/codex"
              install -m 0755 ${codexWrapper} "$out/bin/codex"
              substituteInPlace "$out/bin/codex" \
                --replace-fail '@codex_unwrapped@' "${package}/bin/codex"
            '';
            meta = package.meta or { };
          }
        else if
          name == "gemini-cli" && (package.version or null) == "0.49.0" && package ? overrideAttrs
        then
          package.overrideAttrs (
            old:
            let
              postPatch =
                builtins.replaceStrings [ "\nnode " ] [ "\n${pkgs.lib.getExe pkgs.nodejs} " ]
                  old.postPatch;
            in
            {
              inherit postPatch;
              # llm-agents.nix 0.49.0 runs a Node script in postPatch. That
              # postPatch also runs inside fetchNpmDeps, whose default build
              # inputs do not include nodejs.
              npmDeps = pkgs.fetchNpmDeps {
                name = "${old.pname}-${old.version}-npm-deps-aligned";
                inherit (old) src;
                inherit postPatch;
                hash = old.npmDepsHash;
                fetcherVersion = old.npmDepsFetcherVersion;
                nativeBuildInputs = [ pkgs.nodejs ];
              };
            }
          )
        else
          package;

      optAgent =
        pkgs: name:
        let
          system = pkgs.stdenv.hostPlatform.system;
          agentPackages = llm-agents.packages.${system} or { };
        in
        if agentPackages ? ${name} then [ (patchAgentPackage pkgs name agentPackages.${name}) ] else [ ];

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
          agent = optAgent pkgs;
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
        ++ agent "pi"
        ++ opt "agent-deck"
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

      lib = {
        inherit aiPackagesFor patchAgentPackage;
      };

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
