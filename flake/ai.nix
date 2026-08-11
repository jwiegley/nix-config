inputs@{
  nixpkgs,
  llm-agents,
  git-ai,
  ...
}:
let
  checkManifest = import ../test/check-manifest.nix;
  inherit (checkManifest) systems;

  inherit (nixpkgs) lib;

  forAllSystems = lib.genAttrs systems;

  overlays = import ../overlays/ai { inherit inputs; };
  toolingOverlays = [
    (import ../overlays/00-lib.nix)
    (
      _final: prev:
      lib.optionalAttrs (!(prev ? gogcli)) {
        gogcli = inputs.nixpkgs.legacyPackages.${prev.stdenv.hostPlatform.system}.gogcli;
      }
    )
    ((import ../overlays/30-data-tools.nix) { })
    (import ../overlays/30-markless.nix)
    (import ../overlays/30-misc-tools.nix)
    ((import ../overlays/30-text-tools.nix) { })
    ((import ../overlays/30-user-scripts.nix) { })
  ];
  toolsOverlay = lib.composeManyExtensions toolingOverlays;

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
    if name == "claude-code" then
      import ./ai/wrappers/claude.nix { inherit pkgs name package; }
    else if name == "codex" then
      let
        policyResponseChecker = pkgs.writeShellScript "codex-wrapper-policy-response-check" ''
          set -euo pipefail

          if [ "$#" -ne 2 ]; then
            exit 64
          fi
          ${pkgs.coreutils}/bin/printf '%s\n' "$1" \
            | ${pkgs.diffutils}/bin/cmp -s - "$2"
        '';

        probedPackage = package.overrideAttrs (old: {
          preBuild = ''
            if [ -f cli/src/main.rs ]; then
              patch -p1 --fuzz=0 < ${../overlays/ai/patches/codex-argv-policy-probe.patch}
            fi
          ''
          + (old.preBuild or "");

          postInstall =
            (old.postInstall or "")
            + pkgs.lib.optionalString (!((old.passthru or { }).wrapperPolicyProbeTestDouble or false)) ''
              codex_policy_probe_handshake() {
                local expected=$1
                local actual_file
                shift

                actual_file=$(mktemp)
                trap 'rm -f "$actual_file"' EXIT
                trap 'exit 129' HUP
                trap 'exit 130' INT
                trap 'exit 143' TERM
                if ! CODEX_INTERNAL_WRAPPER_POLICY_PROBE=v1 \
                    "$out/bin/codex" "$@" >"$actual_file" 2>/dev/null; then
                  printf '%s\n' 'codex: build-time wrapper-policy probe failed' >&2
                  exit 1
                fi

                if ! ${policyResponseChecker} "$expected" "$actual_file"; then
                  printf '%s\n' 'codex: build-time wrapper-policy probe returned an invalid response' >&2
                  exit 1
                fi
                rm -f "$actual_file"
                trap - EXIT HUP INT TERM
              }

              codex_policy_probe_handshake delegate --version
              codex_policy_probe_handshake manage
              codex_policy_probe_handshake conflict-profile --profile build-probe
              codex_policy_probe_handshake conflict-ignore-user-config \
                exec --ignore-user-config task
            '';

          passthru = (old.passthru or { }) // {
            wrapperPolicyProbeAbi = 1;
            wrapperPolicyResponseChecker = policyResponseChecker;
          };
        });
      in
      import ./ai/wrappers/codex.nix {
        inherit pkgs name;
        package = probedPackage;
      }
    else if name == "pi" then
      import ./ai/wrappers/pi.nix { inherit pkgs package; }
    else
      package;

  # Per-agent packaging feeds. Every agent comes from the floating llm-agents
  # feed unless a reviewed pin names another substrate for it.
  agentFeeds = {
    pi = inputs.pi-llm-agents;
  };

  canonicalPiPackages = forAllSystems (
    system:
    let
      pkgs = mkPkgs system;
    in
    patchAgentPackage pkgs "pi" agentFeeds.pi.packages.${system}.pi
  );

  optAgent =
    pkgs: name:
    let
      system = pkgs.stdenv.hostPlatform.system;
      feed = agentFeeds.${name} or llm-agents;
      agentPackages = feed.packages.${system} or { };
    in
    if agentPackages ? ${name} then [ (patchAgentPackage pkgs name agentPackages.${name}) ] else [ ];

  aiPackagePolicy = import ../packages/ai-package-policy.nix { inherit lib; };

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
      optMany = names: lib.concatMap opt names;
      agent = optAgent pkgs;
      appleSilicon = pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64;
      supportsGradio6 = aiPackagePolicy.supportsGradio6 pkgs.python313Packages;
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
    ++ agent "git-surgeon"
    ++ agent "mcporter"
    ++ agent "opencode"
    ++ agent "pi"
    ++ lib.optionals (aiPackagePolicy.supportsAiperf pkgs.python313Packages) (opt "aiperf")
    ++ optMany (aiPackagePolicy.groups.common ++ aiPackagePolicy.groups.portableOnly)
    ++ lib.optionals (pkgs ? mcp-server-sequential-thinking) [
      (lib.hiPrio pkgs.mcp-server-sequential-thinking)
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin (opt "drafts-mcp-server")
    ++ lib.optionals appleSilicon (opt "mlx-lm" ++ opt "mtplx" ++ opt "omlx")
    ++ lib.optionals (appleSilicon && supportsGradio6) (opt "vllm-mlx");

  mkAiToolchain =
    pkgs:
    pkgs.buildEnv {
      name = "ai-nix-toolchain";
      paths = aiPackagesFor pkgs;
      ignoreCollisions = true;
    };

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
    all =
      common
      ++ (with pkgs; [
        deadnix
        nix
        nixfmt
        shellcheck
        shfmt
        statix
      ]);
  };

  sourceForChecks = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../config/ai
      ../flake
      ../overlays/ai
      ../packages/agent-resources/pi-mcp-adapter-xdg-config-home.patch
      ../packages/agent-resources.nix
      ../packages/ai-package-policy.nix
      ../packages/ai-llm.nix
      ../packages/ai-mcp.nix
      ../packages/ai-python-extensions.nix
      ../packages/llm-mlx.nix
      ../packages/prime-agent
      ../packages/prime-agent.nix
      ../packages/pi-gallery
      ../packages/source-catalog.nix
      ../sources/ai.json
      ../sources/pi.json
      ../test/ai
    ];
  };

  scriptRoot = ../test/ai/scripts;

  mkScriptPackage =
    pkgs: name: scriptName: runtimeInputs: extraEnv:
    pkgs.writeShellApplication {
      name = "ai-nix-${name}";
      inherit runtimeInputs;
      text = ''
        ${extraEnv}
        exec ${pkgs.bash}/bin/bash ${scriptRoot}/${scriptName} "$@"
      '';
    };

  mkScriptApp =
    pkgs: name: scriptName: runtimeInputs: extraEnv:
    let
      package = mkScriptPackage pkgs name scriptName runtimeInputs extraEnv;
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
  overlays = {
    default = lib.composeManyExtensions overlays;
    tools = toolsOverlay;
  };

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
      toolPkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ toolsOverlay ];
      };
    in
    pkgs.pi-gallery.packages
    // {
      default = mkAiToolchain pkgs;
      inherit (toolPkgs) nix-scripts;
      pi = canonicalPiPackages.${system};
      inherit (pkgs)
        agent-resources
        pi-gallery
        prime-agent
        plasma-fractal
        plasma-wiki
        ;
    }
  );

  apps = forAllSystems (
    system:
    let
      pkgs = mkPkgs system;
      qualityDeps = qualityInputs pkgs;
      app =
        name: scriptName: runtimeInputs: extraEnv:
        mkScriptApp pkgs name scriptName runtimeInputs extraEnv;
      lintRoot = "export AI_NIX_LINT_ROOT=${sourceForChecks}";
    in
    rec {
      format = app "format" "format.sh" qualityDeps.format "";
      format-check = app "format-check" "format-check.sh" qualityDeps.format "";
      lint = app "lint" "lint.sh" qualityDeps.lint lintRoot;
      test = app "test" "test.sh" qualityDeps.test "";
      build-check = app "build-check" "build-check.sh" qualityDeps.build "";
      no-warnings = app "no-warnings" "no-warnings.sh" qualityDeps.build "";
      check = app "check" "check.sh" qualityDeps.all lintRoot;
      default = check;
    }
  );

  checks = forAllSystems (
    system:
    let
      pkgs = mkPkgs system;
      qualityDeps = qualityInputs pkgs;
      check =
        name: scriptName: runtimeInputs: extraEnv:
        mkScriptCheck pkgs name scriptName runtimeInputs extraEnv;
    in
    rec {
      build = mkAiToolchain pkgs;
      agent-deck-go-compat = pkgs.callPackage ../test/ai/overlays/agent-deck-go-compat.nix { };
      agent-deck-runtime-lifecycle = pkgs.agent-deck;
      fractal-smoke = pkgs.callPackage ../test/ai/overlays/plasma-fractal-smoke.nix { };
      llama-cpp-platform-compat = pkgs.callPackage ../test/ai/overlays/llama-cpp-platform-compat.nix { };
      llm-agents-nixpkgs-independent =
        let
          portableLock = builtins.fromJSON (builtins.readFile ../config/ai/flake.lock);
          independentNixpkgs =
            name: builtins.isString portableLock.nodes.${portableLock.nodes.root.inputs.${name}}.inputs.nixpkgs;
        in
        if
          builtins.all independentNixpkgs [
            "llm-agents"
            "pi-llm-agents"
          ]
        then
          pkgs.runCommand "llm-agents-nixpkgs-independent" { } "touch $out"
        else
          throw "every llm-agents feed must retain its independent nixpkgs input";
      agent-resources = pkgs.callPackage ../test/ai/agent-resources.nix {
        inherit (inputs)
          ponytail
          translate-tool
          ;
        gitSurgeonSource = inputs.llm-agents.packages.${system}.git-surgeon.src;
        sourceOnlyResources = pkgs.callPackage ../packages/agent-resources.nix {
          inputs = inputs // {
            llm-agents = builtins.removeAttrs inputs.llm-agents [ "packages" ];
          };
        };
        piMcpAdapter = inputs.pi-mcp-adapter;
        piOpenaiServerCompaction = inputs.pi-openai-server-compaction;
        piQuiet = inputs.pi-quiet;
        piPackage = canonicalPiPackages.${system};
      };
      agent-wrappers = pkgs.callPackage ../test/ai/agent-wrappers.nix {
        inherit patchAgentPackage;
        claudePackage = inputs.llm-agents.packages.${system}.claude-code;
        codexPackage = inputs.llm-agents.packages.${system}.codex;
      };
      pi-gallery = pkgs.callPackage ../test/ai/pi-gallery.nix {
        inherit sourceForChecks;
        piPackage = canonicalPiPackages.${system};
        upstreamPiPackage = agentFeeds.pi.packages.${system}.pi;
        piPackages = pkgs.pi-gallery.packages // {
          inherit (pkgs) agent-resources pi-gallery;
          pi = canonicalPiPackages.${system};
        };
      };
      prime-agent = pkgs.callPackage ../test/ai/prime-agent.nix { inherit pkgs; };
      pi-extension-tests = pkgs.callPackage ../test/ai/pi-extension-tests.nix {
        inherit sourceForChecks;
      };
      pi-fleet-theme = pkgs.callPackage ../test/ai/pi-fleet-theme.nix {
        inherit sourceForChecks;
        piPackage = canonicalPiPackages.${system};
      };
      pi-session-replacement = pkgs.callPackage ../test/ai/pi-session-replacement.nix {
        src = sourceForChecks;
        piPackage = canonicalPiPackages.${system};
      };
      format = check "format" "format-check.sh" qualityDeps.format "";
      lint = check "lint" "lint.sh" qualityDeps.lint "";
    }
    // lib.optionalAttrs (pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64) {
      llm-mlx-plugin = pkgs.python3Packages.llm-mlx.passthru.tests.llm-plugin;
    }
  );

  formatter = forAllSystems (
    system:
    let
      pkgs = mkPkgs system;
    in
    mkScriptPackage pkgs "format" "format.sh" (qualityInputs pkgs).format ""
  );
}
