inputs@{
  nixpkgs,
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

  overlays = import ../overlays/ai { inherit inputs; };

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
      import ./ai/wrappers/codex.nix { inherit pkgs name package; }
    else if name == "droid" then
      import ./ai/wrappers/droid.nix { inherit pkgs name package; }
    else if name == "pi" then
      assert package ? overrideAttrs;
      package.overrideAttrs (old: {
        preInstall = ''
          patch -p1 --fuzz=0 < ${../overlays/ai/patches/pi-system-prompt-no-docs.patch}
          substituteInPlace dist/core/system-prompt.js \
            --replace-fail '//# sourceMappingURL=system-prompt.js.map' ""
          rm -f dist/core/system-prompt.js.map
          patch -p1 --fuzz=0 < ${../overlays/ai/patches/pi-tool-renderer-wrapper.patch}
          for openai_api in \
            node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js \
            node_modules/@earendil-works/pi-ai/dist/api/openai-responses.js
          do
            substituteInPlace "$openai_api" \
              --replace-fail \
                '        defaultHeaders: headers,' \
                $'        defaultHeaders: headers,\n        timeout:\n            model.provider === "omlx" || model.provider === "llama-cpp-local"\n                ? 7_200_000\n                : undefined,'
          done
          substituteInPlace dist/core/http-dispatcher.js \
            --replace-fail \
              'DEFAULT_HTTP_IDLE_TIMEOUT_MS = 300_000' \
              'DEFAULT_HTTP_IDLE_TIMEOUT_MS = 7_200_000'
          ${pkgs.nodejs_22}/bin/node \
            ${../test/ai/pi-tool-renderer-wrapper.test.mjs} "$PWD"
        ''
        + (old.preInstall or "");

        # Bun's compiled Linux executable names the dynamic loader as a
        # shared dependency. Invoking it normally mixes the Nix loader with
        # the host libc and segfaults; retain the matching loader wrapper.
        postInstall =
          (old.postInstall or "")
          + pkgs.lib.optionalString pkgs.stdenv.isLinux (
            let
              dynamicLinker = pkgs.stdenv.cc.bintools.dynamicLinker;
            in
            ''
              mv "$out/libexec/pi/pi" "$out/libexec/pi/pi.bin"
              makeWrapper ${pkgs.lib.escapeShellArg dynamicLinker} "$out/libexec/pi/pi" \
                --add-flags ${pkgs.lib.escapeShellArg "--library-path ${builtins.dirOf dynamicLinker}"} \
                --add-flags ${pkgs.lib.escapeShellArg "--argv0 pi"} \
                --add-flags "$out/libexec/pi/pi.bin"
            ''
          );

        passthru = (old.passthru or { }) // {
          toolRendererWrapperAbi = 1;
        };
      })
    else
      package;

  canonicalPiPackages = forAllSystems (
    system:
    let
      pkgs = mkPkgs system;
    in
    patchAgentPackage pkgs "pi" inputs.llm-agents.packages.${system}.pi
  );

  optAgent =
    pkgs: name:
    let
      system = pkgs.stdenv.hostPlatform.system;
      agentPackages = llm-agents.packages.${system} or { };
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
      ../config/fleet
      ../flake
      ../overlays/ai
      ../packages/agent-resources.nix
      ../packages/ai-package-policy.nix
      ../packages/ai-llm.nix
      ../packages/ai-mcp.nix
      ../packages/ai-python-extensions.nix
      ../packages/llm-mlx.nix
      ../packages/pi-gallery
      ../packages/source-catalog.nix
      ../sources/ai.json
      ../sources/pi.json
      ../test/ai/scripts
      ../test/ai/agent-resources.nix
      ../test/ai/agent-wrappers.nix
      ../test/ai/agent-wrappers.sh
      ../test/ai/compatibility-check.nix
      ../test/ai/compatibility-contract.nix
      ../test/ai/extensions/auto-compact-resume
      ../test/ai/extensions/fleet-theme
      ../test/ai/input-projection-parity.nix
      ../test/ai/overlays
      ../test/ai/node-runtime-guard.cjs
      ../test/ai/pi-gallery.nix
      ../test/ai/pi-fleet-theme.nix
      ../test/ai/pi-tool-renderer-wrapper.test.mjs
      ../test/ai/recording-https-bridge-oracle.py
      ../test/ai/run-bridge-oracle.sh
    ];
  };

  scriptRoot = ../test/ai/scripts;

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
    pkgs.pi-gallery.packages
    // {
      default = mkAiToolchain pkgs;
      pi = canonicalPiPackages.${system};
      inherit (pkgs)
        agent-http-header-bridge
        agent-resources
        pi-gallery
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
        name: scriptName: runtimeInputs:
        mkScriptApp pkgs name scriptName runtimeInputs;
    in
    rec {
      format = app "format" "format.sh" qualityDeps.format;
      format-check = app "format-check" "format-check.sh" qualityDeps.format;
      lint = app "lint" "lint.sh" qualityDeps.lint;
      test = app "test" "test.sh" qualityDeps.test;
      build-check = app "build-check" "build-check.sh" qualityDeps.build;
      no-warnings = app "no-warnings" "no-warnings.sh" qualityDeps.build;
      check = app "check" "check.sh" qualityDeps.all;
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
      fractal-smoke = pkgs.callPackage ../test/ai/overlays/plasma-fractal-smoke.nix { };
      input-projection-parity = pkgs.callPackage ../test/ai/input-projection-parity.nix {
        inherit inputs;
      };
      llama-cpp-platform-compat = pkgs.callPackage ../test/ai/overlays/llama-cpp-platform-compat.nix { };
      llm-agents-nixpkgs-independent =
        let
          portableLock = builtins.fromJSON (builtins.readFile ../config/fleet/flake.lock);
          llmAgentsNode = portableLock.nodes.${portableLock.nodes.root.inputs.llm-agents};
        in
        if builtins.isString llmAgentsNode.inputs.nixpkgs then
          pkgs.runCommand "llm-agents-nixpkgs-independent" { } "touch $out"
        else
          throw "llm-agents must retain its independent nixpkgs input";
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
        agentHttpHeaderBridge = pkgs.agent-http-header-bridge or null;
        agentHttpHeaderBridgeOutput = pkgs.agent-http-header-bridge or null;
        mcpRemote = inputs.mcp-remote or null;
      };
      pi-gallery = pkgs.callPackage ../test/ai/pi-gallery.nix {
        inherit sourceForChecks;
        piPackage = canonicalPiPackages.${system};
        upstreamPiPackage = inputs.llm-agents.packages.${system}.pi;
        piPackages = pkgs.pi-gallery.packages // {
          inherit (pkgs) agent-resources pi-gallery;
          pi = canonicalPiPackages.${system};
        };
      };
      pi-fleet-theme = pkgs.callPackage ../test/ai/pi-fleet-theme.nix {
        inherit sourceForChecks;
        piPackage = canonicalPiPackages.${system};
      };
      format = check "format" "format-check.sh" qualityDeps.format "";
      lint = check "lint" "lint.sh" qualityDeps.lint "";
      tests = check "tests" "test.sh" qualityDeps.test ''
        export AI_NIX_TEST_SOURCE_ONLY=1
      '';
    }
  );

  formatter = forAllSystems (
    system:
    let
      pkgs = mkPkgs system;
    in
    mkScriptPackage pkgs "format" "format.sh" (qualityInputs pkgs).format
  );
}
