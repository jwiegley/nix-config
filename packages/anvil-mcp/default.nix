{
  agentDaemonOverride ? null,
  bash,
  callPackage,
  coreutils,
  diffutils,
  direnv,
  emacs ? null,
  emacs30-nox ? emacs,
  emacsPackages ? null,
  emacsPackagesFor,
  fetchFromGitHub,
  findutils,
  gawk,
  generationSalt ? "",
  git,
  gnugrep,
  gnused,
  hostname,
  lib,
  libffi,
  pkg-config,
  python3,
  ripgrep,
  runCommand,
  rustPlatform,
  stdenv,
  symlinkJoin,
  useDedicatedDarwinEmacs ? false,
  useHeadlessEmacs ? false,
  usePerAgentDaemon ? true,
  writeShellApplication,
  writeText,
  writeTextFile,
}:

let
  anvilSources = import ../source-catalog.nix "anvil";
  anvilSource = anvilSources.anvil-mcp;
  boundedSyncSeconds = 120;
  nelispSource = anvilSources.nelisp;
  nelispVersion = nelispSource.version;
  nelispRev = nelispSource.source.args.rev;
  standaloneAnvilSource = anvilSources.standalone-anvil;
  standaloneAnvilVersion = standaloneAnvilSource.version;
  standaloneAnvilRev = standaloneAnvilSource.source.args.rev;
  currentAnvilHash = anvilSource.source.args.hash;
  currentAnvilOwner = anvilSource.source.args.owner;
  currentAnvilRev = anvilSource.source.args.rev;
  currentAnvilVersion = anvilSource.version;
  anvilIdeSource = anvilSources.anvil-ide;

  # One ordered policy spans client startup, synchronous dispatch, the root
  # watchdog, the stdio bridge, and isolated async children.  The packaged
  # regression binds every generated artifact back to these values.
  timeoutPolicy = {
    asyncSeconds = 600;
    bridgeDispatchSeconds = 250;
    bridgeReadinessSeconds = 30;
    bridgeStartupDispatchSeconds = 20;
    clientStartupSeconds = 540;
    clientToolSeconds = 540;
    cooperativeSyncSeconds = boundedSyncSeconds;
    direnvExportSeconds = 60;
    direnvStatusSeconds = 20;
    emacsclientKillSeconds = 1;
    emacsclientProbeSeconds = 20;
    frameReadSeconds = 20;
    hostShellSeconds = boundedSyncSeconds;
    parentGuardReadySeconds = 10;
    requestParseSeconds = 20;
    runnerControlClockAllowanceSeconds = 2;
    runnerControlSeconds = 10;
    runnerDrainClockAllowanceSeconds = 2;
    runnerIdentitySeconds = 5;
    shellSyncSeconds = boundedSyncSeconds;
    supervisorReadySeconds = 120;
    watchdogDispatchSeconds = 225;
    watchdogHeartbeatSeconds = 45;
    watchdogPulseSeconds = 1;
    watchdogStartupSeconds = 120;
    workerSpawnSeconds = 30;
  };

  workerSpecs = [
    {
      lane = ":read";
      name = "anvil-worker-read-1";
    }
    {
      lane = ":read";
      name = "anvil-worker-read-2";
    }
    {
      lane = ":write";
      name = "anvil-worker-write-1";
    }
    {
      lane = ":batch";
      name = "anvil-worker-batch-1";
    }
  ];
  workerNames = builtins.map (spec: spec.name) workerSpecs;
  workerPoolSizes = {
    read = builtins.length (builtins.filter (spec: spec.lane == ":read") workerSpecs);
    write = builtins.length (builtins.filter (spec: spec.lane == ":write") workerSpecs);
    batch = builtins.length (builtins.filter (spec: spec.lane == ":batch") workerSpecs);
  };
  workerNamesElisp = "(" + lib.concatMapStringsSep " " (name: builtins.toJSON name) workerNames + ")";
  workerSpecsElisp =
    "("
    + lib.concatMapStringsSep " " (spec: "(${spec.lane} ${builtins.toJSON spec.name})") workerSpecs
    + ")";
  workerNamesShell = lib.concatMapStringsSep " " lib.escapeShellArg workerNames;
  workerSupervisorArgsShell = lib.concatMapStringsSep " " (
    name: "--worker-name=${lib.escapeShellArg name}"
  ) workerNames;

  nelispSrc = fetchFromGitHub nelispSource.source.args;

  nelispLispSrc = runCommand "nelisp-${nelispVersion}-lisp" { } ''
    mkdir -p "$out"
    cp -R ${nelispSrc}/src/. "$out/"
  '';

  standaloneAnvilSrc = fetchFromGitHub standaloneAnvilSource.source.args;

  currentAnvilSrc = fetchFromGitHub anvilSource.source.args;

  anvilIdeSrc = fetchFromGitHub anvilIdeSource.source.args;

  dedicatedDirenvNeutral = runCommand "anvil-direnv-neutral" { } ''
    mkdir -p "$out"
  '';

  # Extracted programs remain ordinary source files.  Only Nix-owned paths and
  # policy values are substituted into the eight templates.
  substituteProgram =
    name: src: replacements:
    runCommand name
      {
        inherit src;
        nativeBuildInputs = [ gnugrep ];
      }
      ''
        substitute "$src" "$out" ${
          lib.concatMapStringsSep " " (
            replacement:
            "--replace-fail ${lib.escapeShellArg replacement.from} ${lib.escapeShellArg replacement.to}"
          ) replacements
        }
        if grep -Eq '@[A-Z][A-Z0-9_]*@' "$out"; then
          echo "unsubstituted program placeholder in $src" >&2
          exit 1
        fi
      '';
  dedicatedCleanEnvironment = writeText "anvil-clean-environment.py" (
    builtins.readFile ./clean-environment.py
  );

  dedicatedCleanWrapper =
    {
      name,
      target,
    }:
    writeTextFile {
      name = "${name}-clean-entrypoint";
      destination = "/bin/${name}";
      executable = true;
      text =
        builtins.concatStringsSep "\n" [
          "#!${python3}/bin/python3 -I"
          "import runpy"
          "import sys"
          ""
          "cleaner = ${builtins.toJSON (toString dedicatedCleanEnvironment)}"
          "sys.argv = ["
          "    cleaner,"
          "    \"--direnv\","
          "    ${builtins.toJSON "${direnv}/bin/direnv"},"
          "    \"--parent-guard\","
          "    ${builtins.toJSON (toString dedicatedParentGuardLauncher)},"
          "    \"--neutral\","
          "    ${builtins.toJSON (toString dedicatedDirenvNeutral)},"
          "    \"--timeout-seconds\","
          "    ${builtins.toJSON (toString timeoutPolicy.direnvStatusSeconds)},"
          "    \"--\","
          "    ${builtins.toJSON target},"
          "    *sys.argv[1:],"
          "]"
          "runpy.run_path(cleaner, run_name=\"__main__\")"
        ]
        + "\n";
    };

  commonMeta = {
    description = "Cross-platform launcher for the Anvil MCP server";
    homepage = "https://github.com/zawatton/anvil.el";
    license = lib.licenses.gpl3Plus;
    mainProgram = "anvil-mcp";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };

  linuxRuntime = rustPlatform.buildRustPackage {
    pname = "anvil-runtime";
    version = nelispVersion;
    src = nelispSrc;

    cargoLock.lockFile = ./Cargo.lock;
    cargoBuildFlags = [
      "-p"
      "anvil-runtime"
      "--bin"
      "anvil-runtime"
    ];
    cargoTestFlags = [
      "-p"
      "anvil-runtime"
    ];

    patches = [
      ./no-placeholder-fallback.patch
      ./portable-c-char.patch
      ./standard-initialized-notification.patch
    ];

    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ libffi ];

    postInstall = ''
      rm -f "$out/bin/anvil-mcp-demo"
    '';

    meta = commonMeta // {
      description = "Emacs-free Anvil MCP runtime";
      platforms = [
        "aarch64-linux"
        "x86_64-linux"
      ];
    };
  };

  standalonePackage =
    (writeShellApplication {
      name = "anvil-mcp";
      runtimeInputs = [
        bash
        coreutils
        gnugrep
        gnused
      ];
      text = ''
        server_id=anvil

        while [ "$#" -gt 0 ]; do
          case "$1" in
            --server-id=*)
              server_id="''${1#--server-id=}"
              shift
              ;;
            --server-id)
              if [ "$#" -lt 2 ]; then
                echo "anvil-mcp: --server-id requires a value" >&2
                exit 2
              fi
              server_id="$2"
              shift 2
              ;;
            --help|-h)
              echo "usage: anvil-mcp [--server-id=anvil]"
              exit 0
              ;;
            --version)
              echo "anvil-mcp ${nelispVersion} (NeLisp standalone)"
              exit 0
              ;;
            *)
              echo "anvil-mcp: unsupported argument on Linux: $1" >&2
              exit 2
              ;;
          esac
        done

        if [ "$server_id" != anvil ]; then
          echo "anvil-mcp: Linux NeLisp exposes the standalone surface only; unsupported server id: $server_id" >&2
          exit 2
        fi

        export NELISP_SRC_DIR="${nelispLispSrc}"
        export ANVIL_EL_DIR="${standaloneAnvilSrc}"
        exec "${linuxRuntime}/bin/anvil-runtime" mcp serve
      '';
    }).overrideAttrs
      (_old: {
        pname = "anvil-mcp";
        version = nelispVersion;
        passthru = {
          backend = "nelisp";
          inherit
            linuxRuntime
            nelispLispSrc
            nelispRev
            nelispSrc
            nelispVersion
            standaloneAnvilRev
            standaloneAnvilSrc
            standaloneAnvilVersion
            ;
        };
        meta = commonMeta // {
          description = "Emacs-free Anvil MCP launcher";
          platforms = [
            "aarch64-linux"
            "x86_64-linux"
          ];
        };
      });

  dedicatedEmacs =
    assert lib.assertMsg (
      if stdenv.isDarwin then emacs != null else emacs30-nox != null
    ) "the dedicated Anvil backend requires an Emacs package";
    if stdenv.isDarwin then emacs else emacs30-nox;

  dedicatedEmacsPackages = emacsPackagesFor dedicatedEmacs;
  dedicatedRuntimeEmacs = dedicatedEmacsPackages.emacsWithPackages (epkgs: [
    epkgs.direnv
    epkgs.exec-path-from-shell
  ]);

  dedicatedSafeEmacsclientGuard = writeText "anvil-safe-emacsclient.py" (
    builtins.readFile ./safe-emacsclient.py
  );

  dedicatedSafeEmacsclient = writeShellApplication {
    name = "emacsclient";
    runtimeInputs = [ python3 ];
    text = ''
      exec "${python3}/bin/python3" -I -S \
        "${dedicatedSafeEmacsclientGuard}" \
        "${dedicatedRuntimeEmacs}/bin/emacsclient" "$@"
    '';
  };

  dedicatedLockedRuntimeInputs = [
    bash
    coreutils
    dedicatedSafeEmacsclient
    dedicatedRuntimeEmacs
    diffutils
    direnv
    findutils
    gawk
    git
    gnugrep
    gnused
    pythonWithPyMuPDF
    ripgrep
  ];
  dedicatedRequiredExecPath = map (package: "${lib.getBin package}/bin") (
    lib.remove dedicatedRuntimeEmacs dedicatedLockedRuntimeInputs
  );

  dedicatedAnvilBase =
    if stdenv.isDarwin then
      assert lib.assertMsg (
        emacsPackages != null && emacsPackages ? anvil
      ) "the dedicated Darwin backend requires emacsPackages.anvil";
      emacsPackages.anvil
    else
      (callPackage ../../overlays/emacs/builder.nix {
        emacs = dedicatedEmacs;
        name = "anvil";
        src = currentAnvilSrc;
      }).overrideAttrs
        (attrs: {
          installPhase = attrs.installPhase + ''
            install -m755 anvil-stdio.sh "$out/share/emacs/site-lisp"
            mkdir -p "$out/share/emacs/site-lisp/tests"
            install -m644 \
              tests/anvil-eval-async-isolation-test.el \
              tests/anvil-host-reentrancy-test.el \
              tests/anvil-offload-ownership-test.el \
              tests/anvil-server-unified-registry-test.el \
              tests/anvil-stdio-readiness-test.py \
              "$out/share/emacs/site-lisp/tests"
          '';
        });

  dedicatedAnvil = dedicatedAnvilBase.overrideAttrs (attrs: {
    installPhase = attrs.installPhase + ''
      substituteInPlace "$out/share/emacs/site-lisp/anvil-stdio.sh" \
        --replace-fail \
          'ANVIL_EMACSCLIENT_PROBE_TIMEOUT:-5' \
          'ANVIL_EMACSCLIENT_PROBE_TIMEOUT:-${toString timeoutPolicy.emacsclientProbeSeconds}' \
        --replace-fail \
          '"$ANVIL_EMACSCLIENT_PROBE_TIMEOUT" 5' \
          '"$ANVIL_EMACSCLIENT_PROBE_TIMEOUT" ${toString timeoutPolicy.emacsclientProbeSeconds}' \
        --replace-fail \
          'ANVIL_EMACSCLIENT_READINESS_TIMEOUT:-20' \
          'ANVIL_EMACSCLIENT_READINESS_TIMEOUT:-${toString timeoutPolicy.bridgeReadinessSeconds}' \
        --replace-fail \
          '"$ANVIL_EMACSCLIENT_READINESS_TIMEOUT" 20' \
          '"$ANVIL_EMACSCLIENT_READINESS_TIMEOUT" ${toString timeoutPolicy.bridgeReadinessSeconds}' \
        --replace-fail \
          'ANVIL_EMACSCLIENT_DISPATCH_TIMEOUT:-150' \
          'ANVIL_EMACSCLIENT_DISPATCH_TIMEOUT:-${toString timeoutPolicy.bridgeDispatchSeconds}' \
        --replace-fail \
          '"$ANVIL_EMACSCLIENT_DISPATCH_TIMEOUT" 150' \
          '"$ANVIL_EMACSCLIENT_DISPATCH_TIMEOUT" ${toString timeoutPolicy.bridgeDispatchSeconds}' \
        --replace-fail \
          'ANVIL_MCP_REQUEST_PARSE_TIMEOUT:-10' \
          'ANVIL_MCP_REQUEST_PARSE_TIMEOUT:-${toString timeoutPolicy.requestParseSeconds}' \
        --replace-fail \
          '"$ANVIL_MCP_REQUEST_PARSE_TIMEOUT" 10' \
          '"$ANVIL_MCP_REQUEST_PARSE_TIMEOUT" ${toString timeoutPolicy.requestParseSeconds}' \
        --replace-fail \
          'ANVIL_MCP_FRAME_READ_TIMEOUT:-10' \
          'ANVIL_MCP_FRAME_READ_TIMEOUT:-${toString timeoutPolicy.frameReadSeconds}' \
        --replace-fail \
          '"$ANVIL_MCP_FRAME_READ_TIMEOUT" 10' \
          '"$ANVIL_MCP_FRAME_READ_TIMEOUT" ${toString timeoutPolicy.frameReadSeconds}'
    '';
  });

  dedicatedAnvilIde = callPackage ../../overlays/emacs/builder.nix {
    emacs = dedicatedEmacs;
    name = "anvil-ide";
    src = anvilIdeSrc;
    buildInputs = [ dedicatedAnvil ];
    propagatedBuildInputs = [ dedicatedAnvil ];
  };

  pythonWithPyMuPDF = python3.withPackages (ps: [ ps.pymupdf ]);

  defaultRuntimeRoot =
    if stdenv.isLinux then "/run/user/$(id -u)/anvil" else "/tmp/anvil-emacs-$(id -u)";

  privateDirectoryFunctions = ''
    validate_host_component() {
      case "$1" in
        "" | "." | ".." | *[!A-Za-z0-9._-]*)
          echo "anvil-mcp: unsafe host component: $1" >&2
          return 64
          ;;
      esac
    }

    private_directory() {
      path="$1"
      label="$2"
      expected_uid=$(id -u)

      if [ -L "$path" ]; then
        echo "anvil-mcp: $label must not be a symbolic link: $path" >&2
        return 77
      fi

      if [ ! -e "$path" ]; then
        if ! (umask 077 && mkdir -- "$path"); then
          if [ ! -e "$path" ] && [ ! -L "$path" ]; then
            echo "anvil-mcp: failed to create $label: $path" >&2
            return 77
          fi
        fi
      fi

      if [ -L "$path" ]; then
        echo "anvil-mcp: $label must not be a symbolic link: $path" >&2
        return 77
      fi
      if [ ! -d "$path" ]; then
        echo "anvil-mcp: $label must be a directory: $path" >&2
        return 77
      fi

      owner_uid=$(stat -c '%u' -- "$path") || {
        echo "anvil-mcp: cannot inspect owner of $label: $path" >&2
        return 77
      }
      mode=$(stat -c '%a' -- "$path") || {
        echo "anvil-mcp: cannot inspect mode of $label: $path" >&2
        return 77
      }
      if [ "$owner_uid" != "$expected_uid" ]; then
        echo "anvil-mcp: $label must be owned by uid $expected_uid (found $owner_uid): $path" >&2
        return 77
      fi
      if [ "$mode" != 700 ]; then
        echo "anvil-mcp: $label must have mode 0700 (found $mode): $path" >&2
        return 77
      fi
    }
  '';

  dedicatedParentGuardLauncher = substituteProgram "anvil-parent-guard.py" ./parent-guard.py.in [
    {
      from = "@PARENT_GUARD_READY_SECONDS@";
      to = toString timeoutPolicy.parentGuardReadySeconds;
    }
  ];

  dedicatedAgentSupervisor = writeText "anvil-agent-supervisor.py" (
    builtins.readFile ./agent-supervisor.py
  );
  watchdogTestSupport = writeText "watchdog-test-support.py" (
    builtins.readFile ./watchdog-test-support.py
  );

  dedicatedChildShellSource = writeTextFile {
    name = "anvil-headless-child-shell.py";
    executable = true;
    text = ''
      #!${python3}/bin/python3 -I
      import errno
      import os
      import runpy
      import sys


      EXIT_SOFTWARE = 70
      GUARD = ${builtins.toJSON (toString dedicatedParentGuardLauncher)}


      def fail(message):
          print(f"anvil-mcp: {message}", file=sys.stderr)
          raise SystemExit(EXIT_SOFTWARE)


      real_shell = os.environ.pop("ANVIL_HEADLESS_REAL_SHELL", "")
      if not real_shell:
          fail("missing real shell for dedicated child")

      for descriptor in (8, 9):
          try:
              os.close(descriptor)
          except OSError as error:
              if error.errno != errno.EBADF:
                  fail(f"cannot close lock fd {descriptor}: {error}")

      sys.argv = [GUARD, "group", real_shell, *sys.argv[1:]]
      runpy.run_path(GUARD, run_name="__main__")
    '';
  };

  dedicatedChildShell = runCommand "anvil-headless-child-shell" { } ''
    mkdir -p "$out/bin"
    ln -s "${dedicatedChildShellSource}" \
      "$out/bin/anvil-headless-child-shell"
    "${python3}/bin/python3" -I -B \
      ${./child-shell-test.py} \
      "$out/bin/anvil-headless-child-shell" \
      "${dedicatedParentGuardLauncher}" \
      "${bash}/bin/bash"
  '';

  dedicatedEnvironmentInit =
    substituteProgram "anvil-headless-environment-init.el" ./headless-environment-init.el.in
      [
        {
          from = "@ANVIL_SITE_LISP_DIR@";
          to = "${dedicatedAnvil}/share/emacs/site-lisp";
        }
        {
          from = "@DEDICATED_EMACS_BIN_DIR@";
          to = "${dedicatedRuntimeEmacs}/bin";
        }
        {
          from = "@SAFE_EMACSCLIENT_BIN_DIR@";
          to = "${dedicatedSafeEmacsclient}/bin";
        }
        {
          from = "@DIRENV_BIN@";
          to = "${direnv}/bin/direnv";
        }
        {
          from = "@DIRENV_STATUS_TIMEOUT_SECONDS@";
          to = toString timeoutPolicy.direnvStatusSeconds;
        }
        {
          from = "@DIRENV_EXPORT_TIMEOUT_SECONDS@";
          to = toString timeoutPolicy.direnvExportSeconds;
        }
        {
          from = "@PYTHON3_BIN@";
          to = "${python3}/bin/python3";
        }
        {
          from = "@PARENT_GUARD_SCRIPT@";
          to = toString dedicatedParentGuardLauncher;
        }
        {
          from = "@REQUIRED_EXEC_PATH_ITEMS_ELISP@";
          to = lib.concatMapStringsSep "
        " builtins.toJSON dedicatedRequiredExecPath;
        }
        {
          from = "@CHILD_SHELL_BIN@";
          to = "${dedicatedChildShell}/bin/anvil-headless-child-shell";
        }
      ];

  dedicatedWorkerInit =
    substituteProgram "anvil-headless-worker-init.el" ./headless-worker-init.el.in
      [
        {
          from = "@EXPECTED_WORKER_NAMES_ELISP@";
          to = workerNamesElisp;
        }
        {
          from = "@ENVIRONMENT_INIT_FILE@";
          to = toString dedicatedEnvironmentInit;
        }
        {
          from = "@ANVIL_SITE_LISP_DIR@";
          to = "${dedicatedAnvil}/share/emacs/site-lisp";
        }
        {
          from = "@ANVIL_IDE_SITE_LISP_DIR@";
          to = "${dedicatedAnvilIde}/share/emacs/site-lisp";
        }
      ];

  dedicatedOffloadInit =
    substituteProgram "anvil-headless-offload-init.el" ./headless-offload-init.el.in
      [
        {
          from = "@ENVIRONMENT_INIT_FILE@";
          to = toString dedicatedEnvironmentInit;
        }
      ];

  dedicatedWorkerEmacs = writeShellApplication {
    name = "anvil-worker-emacs";
    text = ''
      # Fds 8/9 carry the root daemon's OFD locks.  Close the inherited
      # descriptions before starting the exact-PID worker containment guard.
      exec 8<&- 9<&-

      worker_name=
      for argument in "$@"; do
        case "$argument" in
          --daemon=* | --fg-daemon=*)
            worker_name="''${argument#*=}"
            ;;
        esac
      done
      worker_allowed=
      for expected_worker in ${workerNamesShell}; do
        if [ "$worker_name" = "$expected_worker" ]; then
          worker_allowed=1
          break
        fi
      done
      if [ -z "$worker_allowed" ]; then
        echo "anvil-mcp: missing or unexpected worker daemon name: $worker_name" >&2
        exit 70
      fi
      if [ -z "''${ANVIL_EMACS_STATE_DIR:-}" ]; then
        echo "anvil-mcp: worker requires ANVIL_EMACS_STATE_DIR" >&2
        exit 70
      fi
      worker_state_dir="$ANVIL_EMACS_STATE_DIR/workers/$worker_name"
      if [ ! -d "$worker_state_dir" ] || [ -L "$worker_state_dir" ]; then
        echo "anvil-mcp: unsafe worker state directory: $worker_state_dir" >&2
        exit 70
      fi

      export ANVIL_EMACS_WORKER=1
      exec "${python3}/bin/python3" -I -S "${dedicatedParentGuardLauncher}" \
        exact "${dedicatedRuntimeEmacs}/bin/emacs" \
        --quick "--init-directory=$worker_state_dir" "$@"
    '';
  };

  dedicatedOffloadEmacs = writeShellApplication {
    name = "anvil-offload-emacs";
    text = ''
      # The root owns daemon-lifetime OFD locks; an isolated async child must
      # not keep them alive after root replacement.
      exec 8<&- 9<&-

      if [ -z "''${ANVIL_HEADLESS_PARENT_PID:-}" ]; then
        echo "anvil-mcp: offload child requires a root parent identity" >&2
        exit 70
      fi
      if [ -z "''${ANVIL_EMACS_STATE_DIR:-}" ]; then
        echo "anvil-mcp: offload child requires ANVIL_EMACS_STATE_DIR" >&2
        exit 70
      fi

      export ANVIL_EMACS_WORKER=1
      exec "${python3}/bin/python3" -I -S "${dedicatedParentGuardLauncher}" \
        group "${dedicatedRuntimeEmacs}/bin/emacs" \
        --quick "--init-directory=$ANVIL_EMACS_STATE_DIR/offload" "$@"
    '';
  };

  dedicatedLockLauncher = substituteProgram "anvil-lock-launcher.py" ./lock-launcher.py.in [
    {
      from = "@WATCHDOG_STARTUP_SECONDS@";
      to = toString timeoutPolicy.watchdogStartupSeconds;
    }
    {
      from = "@WATCHDOG_HEARTBEAT_SECONDS@";
      to = toString timeoutPolicy.watchdogHeartbeatSeconds;
    }
    {
      from = "@WATCHDOG_DISPATCH_SECONDS@";
      to = toString timeoutPolicy.watchdogDispatchSeconds;
    }
    {
      from = "@WATCHDOG_PULSE_SECONDS@";
      to = toString timeoutPolicy.watchdogPulseSeconds;
    }
  ];
  dedicatedTelemetryInit =
    substituteProgram "anvil-headless-watchdog-telemetry.el" ./headless-watchdog-telemetry.el.in
      [
        {
          from = "@PYTHON3_BIN@";
          to = "${python3}/bin/python3";
        }
        {
          from = "@AGENT_SUPERVISOR_SCRIPT@";
          to = toString dedicatedAgentSupervisor;
        }
      ];

  dedicatedInit = substituteProgram "anvil-headless-init.el" ./headless-init.el.in [
    {
      from = "@TELEMETRY_INIT_FILE@";
      to = toString dedicatedTelemetryInit;
    }
    {
      from = "@COOPERATIVE_SYNC_TIMEOUT_SECONDS@";
      to = toString timeoutPolicy.cooperativeSyncSeconds;
    }
    {
      from = "@ASYNC_TIMEOUT_SECONDS@";
      to = toString timeoutPolicy.asyncSeconds;
    }
    {
      from = "@NELISP_LISP_DIR@";
      to = toString nelispLispSrc;
    }
    {
      from = "@SHELL_SYNC_TIMEOUT_SECONDS@";
      to = toString timeoutPolicy.shellSyncSeconds;
    }
    {
      from = "@WORKER_READ_POOL_SIZE@";
      to = toString workerPoolSizes.read;
    }
    {
      from = "@WORKER_WRITE_POOL_SIZE@";
      to = toString workerPoolSizes.write;
    }
    {
      from = "@WORKER_BATCH_POOL_SIZE@";
      to = toString workerPoolSizes.batch;
    }
    {
      from = "@WORKER_SPAWN_WAIT_SECONDS@";
      to = toString timeoutPolicy.workerSpawnSeconds;
    }
    {
      from = "@ENVIRONMENT_INIT_FILE@";
      to = toString dedicatedEnvironmentInit;
    }
    {
      from = "@PDF_PYTHON_BIN@";
      to = "${pythonWithPyMuPDF}/bin/python3";
    }
    {
      from = "@OFFLOAD_EMACS_BIN@";
      to = "${dedicatedOffloadEmacs}/bin/anvil-offload-emacs";
    }
    {
      from = "@OFFLOAD_INIT_FILE@";
      to = toString dedicatedOffloadInit;
    }
    {
      from = "@WORKER_EMACS_BIN@";
      to = "${dedicatedWorkerEmacs}/bin/anvil-worker-emacs";
    }
    {
      from = "@WORKER_INIT_FILE@";
      to = toString dedicatedWorkerInit;
    }
    {
      from = "@HOST_SHELL_TIMEOUT_SECONDS@";
      to = toString timeoutPolicy.hostShellSeconds;
    }
    {
      from = "@EXPECTED_WORKER_SPECS_ELISP@";
      to = workerSpecsElisp;
    }
  ];

  dedicatedLockedStage = writeShellApplication {
    name = "anvil-headless-emacs-locked";
    runtimeInputs = dedicatedLockedRuntimeInputs;
    inheritPath = false;
    text = ''
      ${privateDirectoryFunctions}

      if [ "$#" -ne 2 ]; then
        echo "anvil-mcp: locked stage requires runtime and state directories" >&2
        exit 70
      fi
      runtime_dir="$1"
      state_dir="$2"

      # Fds 8/9 carry OFD locks acquired by the launcher.  They survive
      # this exec chain into root Emacs.  Worker and shell wrappers close their
      # inherited descriptions immediately so they cannot prolong ownership.
      rm -rf -- "$runtime_dir/tmp" "$runtime_dir/workers"

      private_directory "$runtime_dir/emacs" "Emacs socket directory"
      private_directory "$runtime_dir/tmp" "host temporary directory"
      private_directory "$runtime_dir/workers" "worker runtime root"
      private_directory "$state_dir/cache" "host cache directory"
      private_directory "$state_dir/eln-cache" "host native-comp cache"
      private_directory "$state_dir/semantic" "host semantic state directory"
      private_directory "$state_dir/offload" "offload state directory"
      private_directory "$state_dir/offload/eln-cache" "offload native-comp cache"
      private_directory "$state_dir/workers" "worker state root"
      for worker in ${workerNamesShell}; do
        private_directory "$runtime_dir/workers/$worker" "$worker runtime directory"
        private_directory "$runtime_dir/workers/$worker/tmp" "$worker temporary directory"
        private_directory "$state_dir/workers/$worker" "$worker state directory"
        private_directory "$state_dir/workers/$worker/cache" "$worker cache directory"
        private_directory "$state_dir/workers/$worker/eln-cache" "$worker native-comp cache"
        private_directory "$state_dir/workers/$worker/server" "$worker server directory"
      done

      export XDG_RUNTIME_DIR="$runtime_dir"
      export XDG_CACHE_HOME="$state_dir/cache"
      export ANVIL_EMACS_STATE_DIR="$state_dir"
      # Make the root socket explicit in every root-owned child environment.
      # A nested anvil-mcp invocation then fails its per-agent socket-override
      # guard immediately instead of waiting recursively on this same root.
      export ANVIL_EMACS_SOCKET="$runtime_dir/emacs/server"
      export TMPDIR="$runtime_dir/tmp"
      export TMP="$TMPDIR"
      export TEMP="$TMPDIR"

      # Bind state before daemon/package startup.  Keeping HOME unchanged is
      # required for login-shell and direnv behavior, so redirect Emacs's
      # startup state explicitly instead of substituting a synthetic HOME.
      # The trusted state directory also prevents a caller's project cwd from
      # becoming the root daemon's immutable default directory.
      cd -- "$state_dir"
      exec "${dedicatedRuntimeEmacs}/bin/emacs" \
        --quick \
        "--init-directory=$state_dir" \
        --fg-daemon=server \
        --directory "${dedicatedAnvil}/share/emacs/site-lisp" \
        --directory "${dedicatedAnvilIde}/share/emacs/site-lisp" \
        --load "${dedicatedInit}"
    '';
  };

  dedicatedDaemonInner = writeShellApplication {
    name = "anvil-headless-emacs-inner";
    runtimeInputs = [
      bash
      coreutils
      hostname
      python3
    ];
    text = ''
      ${privateDirectoryFunctions}

      umask 077
      ${lib.optionalString stdenv.isDarwin ''
        if [ "''${ANVIL_EMACS_USE_SYSTEM_LOG:-}" = 1 ]; then
          exec > >(/usr/bin/logger -t anvil-headless-emacs) 2>&1
        fi
      ''}

      short_host="''${ANVIL_EMACS_HOST:-$(hostname -s)}"
      validate_host_component "$short_host"

      runtime_root="''${ANVIL_EMACS_RUNTIME_ROOT:-${defaultRuntimeRoot}}"
      state_root="''${ANVIL_EMACS_STATE_ROOT:-/var/tmp/anvil-emacs-$(id -u)}"
      runtime_dir="''${ANVIL_EMACS_RUNTIME_DIR:-}"
      state_dir="''${ANVIL_EMACS_STATE_DIR:-}"
      if [ -z "$runtime_dir" ] && [ -z "$state_dir" ]; then
        runtime_dir="$runtime_root/$short_host"
        state_dir="$state_root/$short_host"
      elif [ -z "$runtime_dir" ] || [ -z "$state_dir" ]; then
        echo "anvil-mcp: exact runtime and state directories must be set together" >&2
        exit 64
      fi
      "${python3}/bin/python3" -I -S "${dedicatedAgentSupervisor}" \
        --validate-host-sockets \
        --runtime-root "$runtime_root" \
        --state-root "$state_root" \
        --runtime-dir "$runtime_dir" \
        --state-dir "$state_dir" \
        --host "$short_host" \
        ${workerSupervisorArgsShell}
      lock_conflict_status="''${ANVIL_EMACS_LOCK_CONFLICT_STATUS:-75}"
      case "$lock_conflict_status" in
        0|75) ;;
        *)
          echo "anvil-mcp: ANVIL_EMACS_LOCK_CONFLICT_STATUS must be 0 or 75" >&2
          exit 64
          ;;
      esac

      private_directory "$runtime_root" "runtime root"
      private_directory "$runtime_dir" "host runtime directory"
      private_directory "$state_root" "state root"
      private_directory "$state_dir" "host state directory"

      # Preserve one service PID across Python, the locked shell stage, and
      # foreground Emacs while keeping the OFD lock descriptions open across exec.
      exec "${python3}/bin/python3" -I -S "${dedicatedLockLauncher}" \
        "$runtime_dir" "$state_dir" "$lock_conflict_status" \
        "${dedicatedLockedStage}/bin/anvil-headless-emacs-locked"
    '';
  };
  dedicatedDaemon = dedicatedCleanWrapper {
    name = "anvil-headless-emacs";
    target = "${dedicatedDaemonInner}/bin/anvil-headless-emacs-inner";
  };
  watchdogCapabilityDescendantInit = writeText "anvil-watchdog-capability-descendant.el" (
    builtins.readFile ./watchdog-capability-descendant.el
  );
  watchdogCapabilityRootInit =
    substituteProgram "anvil-watchdog-capability-root.el" ./watchdog-capability-root.el.in
      [
        {
          from = "@TELEMETRY_INIT_FILE@";
          to = toString dedicatedTelemetryInit;
        }
        {
          from = "@DEDICATED_EMACS_BIN@";
          to = "${dedicatedRuntimeEmacs}/bin/emacs";
        }
        {
          from = "@CAPABILITY_DESCENDANT_INIT_FILE@";
          to = toString watchdogCapabilityDescendantInit;
        }
      ];
  watchdogCapabilityLockedStage = writeShellApplication {
    name = "anvil-watchdog-capability-locked";
    runtimeInputs = [ dedicatedRuntimeEmacs ];
    text = ''
      if [ "$#" -ne 2 ]; then
        echo "anvil-mcp: watchdog capability stage requires runtime and state directories" >&2
        exit 64
      fi
      export XDG_RUNTIME_DIR="$1"
      export ANVIL_EMACS_STATE_DIR="$2"
      exec ${dedicatedRuntimeEmacs}/bin/emacs --batch -Q \
        -l ${watchdogCapabilityRootInit}
    '';
  };
  watchdogCapabilityDaemonInner = writeShellApplication {
    name = "anvil-watchdog-capability-daemon-inner";
    runtimeInputs = [ python3 ];
    text = ''
      runtime_dir="''${ANVIL_EMACS_RUNTIME_DIR:-}"
      state_dir="''${ANVIL_EMACS_STATE_DIR:-}"
      if [ -z "$runtime_dir" ] || [ -z "$state_dir" ]; then
        echo "anvil-mcp: watchdog capability daemon requires exact directories" >&2
        exit 64
      fi
      exec ${python3}/bin/python3 -I -S ${dedicatedLockLauncher} \
        "$runtime_dir" "$state_dir" 75 \
        ${watchdogCapabilityLockedStage}/bin/anvil-watchdog-capability-locked
    '';
  };
  watchdogCapabilityDaemon = dedicatedCleanWrapper {
    name = "anvil-watchdog-capability-daemon";
    target = "${watchdogCapabilityDaemonInner}/bin/anvil-watchdog-capability-daemon-inner";
  };
  dedicatedAgentDaemon = if agentDaemonOverride == null then dedicatedDaemon else agentDaemonOverride;
  # Compatible package rebuilds must not create a second root for one live
  # agent-deck session.  This value is a protocol epoch, not a closure hash;
  # generationSalt is reserved for tests and deliberate incompatible bumps.
  dedicatedGeneration = builtins.hashString "sha256" "anvil-agentdeck-session-protocol-v1|${generationSalt}";
  dedicatedLauncherInner = writeShellApplication {
    name = "anvil-mcp-inner";
    runtimeInputs = [
      bash
      coreutils
      dedicatedRuntimeEmacs
      gawk
      gnugrep
      gnused
      hostname
      python3
    ];
    text = ''
      ${privateDirectoryFunctions}

      if [ "''${ANVIL_MCP_LAUNCHER_GUARDED:-}" != "$$" ]; then
        export ANVIL_MCP_LAUNCHER_GUARDED="$$"
        ANVIL_HEADLESS_PARENT_PID="$PPID" \
          exec "${python3}/bin/python3" -I -S \
            "${dedicatedParentGuardLauncher}" external-group \
            "$0" "$@"
      fi
      unset ANVIL_MCP_LAUNCHER_GUARDED

      server_id=anvil
      socket="''${ANVIL_EMACS_SOCKET:-}"

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --server-id=*)
            server_id="''${1#--server-id=}"
            shift
            ;;
          --server-id)
            if [ "$#" -lt 2 ]; then
              echo "anvil-mcp: --server-id requires a value" >&2
              exit 2
            fi
            server_id="$2"
            shift 2
            ;;
          --socket=*)
            socket="''${1#--socket=}"
            shift
            ;;
          --socket)
            if [ "$#" -lt 2 ]; then
              echo "anvil-mcp: --socket requires a value" >&2
              exit 2
            fi
            socket="$2"
            shift 2
            ;;
          --help|-h)
            echo "usage: anvil-mcp [--server-id=anvil|emacs-eval] [--socket=PATH]"
            exit 0
            ;;
          --version)
            echo "anvil-mcp ${currentAnvilVersion} (anvil ${currentAnvilRev}; dedicated Emacs)"
            exit 0
            ;;
          *)
            echo "anvil-mcp: unsupported argument: $1" >&2
            exit 2
            ;;
        esac
      done

      case "$server_id" in
        anvil|emacs-eval)
          ;;
        *)
          echo "anvil-mcp: unsupported dedicated-Emacs server id: $server_id" >&2
          exit 2
          ;;
      esac

      # Scrub before either the per-agent or shared-daemon path.  The
      # supervisor repeats this for daemon and transport subprocesses.
      unset ALTERNATE_EDITOR

      ${lib.optionalString usePerAgentDaemon ''
        if [ -n "$socket" ]; then
          echo "anvil-mcp: --socket cannot override a per-agent daemon" >&2
          exit 64
        fi
        short_host="''${ANVIL_EMACS_HOST:-$(hostname -s)}"
        validate_host_component "$short_host"
        runtime_root="''${ANVIL_EMACS_RUNTIME_ROOT:-${defaultRuntimeRoot}}"
        state_root="''${ANVIL_EMACS_STATE_ROOT:-/var/tmp/anvil-emacs-$(id -u)}"
        exec "${python3}/bin/python3" -I -S "${dedicatedAgentSupervisor}" \
              --server-id "$server_id" \
              --generation "${dedicatedGeneration}" \
              --host "$short_host" \
              --runtime-root "$runtime_root" \
              --state-root "$state_root" \
              --daemon "${dedicatedAgentDaemon}/bin/anvil-headless-emacs" \
              --stdio "${dedicatedAnvil}/share/emacs/site-lisp/anvil-stdio.sh" \
              --emacsclient "${dedicatedRuntimeEmacs}/bin/emacsclient" \
              --python "${python3}/bin/python3" \
              --parent-guard "${dedicatedParentGuardLauncher}" \
              ${workerSupervisorArgsShell} \
              --grace-seconds "''${ANVIL_AGENT_GRACE_SECONDS:-5}" \
              --ready-seconds "''${ANVIL_AGENT_READY_SECONDS:-${toString timeoutPolicy.supervisorReadySeconds}}"
      ''}

      if [ -z "$socket" ]; then
        short_host="''${ANVIL_EMACS_HOST:-$(hostname -s)}"
        validate_host_component "$short_host"
        runtime_root="''${ANVIL_EMACS_RUNTIME_ROOT:-${defaultRuntimeRoot}}"
        state_root="''${ANVIL_EMACS_STATE_ROOT:-/var/tmp/anvil-emacs-$(id -u)}"
        "${python3}/bin/python3" -I -S "${dedicatedAgentSupervisor}" \
          --validate-host-sockets \
          --runtime-root "$runtime_root" \
          --state-root "$state_root" \
          --host "$short_host" \
          ${workerSupervisorArgsShell}
        runtime_dir="$runtime_root/$short_host"
        private_directory "$runtime_root" "runtime root"
        private_directory "$runtime_dir" "host runtime directory"
        socket="$runtime_dir/emacs/server"
      fi

      "${python3}/bin/python3" -I -S "${dedicatedAgentSupervisor}" \
        --validate-explicit-socket \
        --socket "$socket"
      if [ -L "$socket" ]; then
        echo "anvil-mcp: Emacs socket must not be a symbolic link: $socket" >&2
        exit 77
      fi
      if [ -e "$socket" ] && [ ! -S "$socket" ]; then
        echo "anvil-mcp: Emacs socket path must be a socket: $socket" >&2
        exit 77
      fi
      if [ -S "$socket" ]; then
        socket_owner=$(stat -c '%u' -- "$socket") || {
          echo "anvil-mcp: cannot inspect Emacs socket owner: $socket" >&2
          exit 77
        }
        current_uid=$(id -u)
        if [ "$socket_owner" != "$current_uid" ]; then
          echo "anvil-mcp: Emacs socket must be owned by uid $current_uid (found $socket_owner): $socket" >&2
          exit 77
        fi
      fi

      # The bridge owns bounded readiness retries; avoid an unguarded duplicate
      # emacsclient probe in the launcher.
      export ANVIL_MCP_PARENT_GUARD="${dedicatedParentGuardLauncher}"
      export ANVIL_MCP_PARENT_GUARD_PYTHON="${python3}/bin/python3"
      # Shared dedicated daemons need the same final-registry predicate on
      # every request as per-agent daemons; the upstream bridge validates the
      # mode and constructs the fixed predicate from this server ID.
      export ANVIL_MCP_READINESS_MODE=headless
      exec "${dedicatedAnvil}/share/emacs/site-lisp/anvil-stdio.sh" \
        "--socket=$socket" \
        "--server-id=$server_id"
    '';
  };
  dedicatedLauncher = dedicatedCleanWrapper {
    name = "anvil-mcp";
    target = "${dedicatedLauncherInner}/bin/anvil-mcp-inner";
  };

  dedicatedPackage = symlinkJoin {
    name = "anvil-mcp-${currentAnvilVersion}";
    pname = "anvil-mcp";
    version = currentAnvilVersion;
    paths = [
      dedicatedLauncher
      dedicatedDaemon
    ];
    passthru = {
      backend = "dedicated-emacs";
      inherit
        currentAnvilHash
        currentAnvilOwner
        currentAnvilRev
        currentAnvilSrc
        currentAnvilVersion
        dedicatedAnvil
        dedicatedAnvilIde
        dedicatedChildShell
        dedicatedCleanEnvironment
        dedicatedDaemon
        dedicatedDaemonInner
        dedicatedDirenvNeutral
        dedicatedEmacs
        dedicatedEnvironmentInit
        dedicatedInit
        dedicatedTelemetryInit
        dedicatedLauncherInner
        dedicatedLockLauncher
        dedicatedLockedStage
        dedicatedParentGuardLauncher
        dedicatedOffloadEmacs
        dedicatedOffloadInit
        dedicatedRuntimeEmacs
        dedicatedSafeEmacsclient
        dedicatedSafeEmacsclientGuard
        dedicatedAgentSupervisor
        direnv
        git
        dedicatedWorkerEmacs
        dedicatedWorkerInit
        workerNames
        timeoutPolicy
        workerPoolSizes
        workerSpecs
        watchdogTestSupport
        watchdogCapabilityDaemon
        ;
      dedicatedAgentSupervisorSmoke = ./agent-supervisor-smoke.py;
      dedicatedAgentSupervisorTest = ./agent-supervisor-test.py;
      dedicatedCleanEnvironmentTest = ./clean-environment-test.py;
      dedicatedPersistentBridgeSoak = ./persistent-bridge-soak.py;
    };
    meta = commonMeta // {
      description = "Dedicated-Emacs Anvil MCP launcher";
    };
  };

  interactiveDarwinPackage =
    assert lib.assertMsg (emacs != null) "anvil-mcp on Darwin requires pkgs.emacs";
    assert lib.assertMsg (
      emacsPackages != null && emacsPackages ? anvil
    ) "anvil-mcp on Darwin requires the custom emacsPackages.anvil package";
    (writeShellApplication {
      name = "anvil-mcp";
      runtimeInputs = [
        coreutils
        emacs
        gawk
        python3
        gnugrep
        gnused
      ];
      text = ''
        if [ "''${ANVIL_MCP_LAUNCHER_GUARDED:-}" != "$$" ]; then
          export ANVIL_MCP_LAUNCHER_GUARDED="$$"
          ANVIL_HEADLESS_PARENT_PID="$PPID" \
            exec "${python3}/bin/python3" -I -S \
              "${dedicatedParentGuardLauncher}" external-group \
              "$0" "$@"
        fi
        unset ANVIL_MCP_LAUNCHER_GUARDED

        server_id=anvil
        socket="''${ANVIL_EMACS_SOCKET:-/tmp/johnw-emacs/server}"

        while [ "$#" -gt 0 ]; do
          case "$1" in
            --server-id=*)
              server_id="''${1#--server-id=}"
              shift
              ;;
            --server-id)
              if [ "$#" -lt 2 ]; then
                echo "anvil-mcp: --server-id requires a value" >&2
                exit 2
              fi
              server_id="$2"
              shift 2
              ;;
            --socket=*)
              socket="''${1#--socket=}"
              shift
              ;;
            --socket)
              if [ "$#" -lt 2 ]; then
                echo "anvil-mcp: --socket requires a value" >&2
                exit 2
              fi
              socket="$2"
              shift 2
              ;;
            --help|-h)
              echo "usage: anvil-mcp [--server-id=anvil|emacs-eval] [--socket=PATH]"
              exit 0
              ;;
            --version)
              echo "anvil-mcp ${currentAnvilVersion} (interactive Emacs)"
              exit 0
              ;;
            *)
              echo "anvil-mcp: unsupported argument on Darwin: $1" >&2
              exit 2
              ;;
          esac
        done

        case "$server_id" in
          anvil|emacs-eval)
            ;;
          *)
            echo "anvil-mcp: unsupported interactive-Emacs server id: $server_id" >&2
            exit 2
            ;;
        esac

        # The MCP bridge must never launch an interactive fallback editor.
        unset ALTERNATE_EDITOR

        export ANVIL_MCP_PARENT_GUARD="${dedicatedParentGuardLauncher}"
        export ANVIL_MCP_PARENT_GUARD_PYTHON="${python3}/bin/python3"
        exec "${dedicatedAnvil}/share/emacs/site-lisp/anvil-stdio.sh" \
          "--socket=$socket" \
          "--server-id=$server_id"
      '';
    }).overrideAttrs
      (_old: {
        pname = "anvil-mcp";
        version = currentAnvilVersion;
        passthru = {
          backend = "interactive-emacs";
          inherit
            currentAnvilHash
            currentAnvilOwner
            currentAnvilRev
            currentAnvilVersion
            ;
        };
        meta = commonMeta // {
          description = "Interactive-Emacs Anvil MCP launcher";
          platforms = [ "aarch64-darwin" ];
        };
      });
in
assert anvilSource.source.fetcher == "fetchFromGitHub";
assert anvilIdeSource.source.fetcher == "fetchFromGitHub";
assert nelispSource.source.fetcher == "fetchFromGitHub";
assert standaloneAnvilSource.source.fetcher == "fetchFromGitHub";
if stdenv.isLinux then
  if useHeadlessEmacs then dedicatedPackage else standalonePackage
else if stdenv.isDarwin then
  if useDedicatedDarwinEmacs then dedicatedPackage else interactiveDarwinPackage
else
  throw "anvil-mcp is supported only on Darwin and Linux"
