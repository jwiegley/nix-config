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
  anvilSource = import ./source.nix;
  boundedSyncSeconds = 120;
  nelispVersion = "0.5.1";
  nelispRev = "f753209d53b372933b829345fe4373acad67bcb5";
  standaloneAnvilVersion = "1.1.1";
  standaloneAnvilRev = "d50ce32b71c5fa46da3aa661481c8be44fee4f97";
  currentAnvilHash = anvilSource.hash;
  currentAnvilOwner = anvilSource.owner;
  currentAnvilRev = anvilSource.rev;
  currentAnvilVersion = anvilSource.version;
  anvilIdeSource = anvilSource.ide;

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

  nelispSrc = fetchFromGitHub {
    owner = "zawatton";
    repo = "nelisp";
    rev = nelispRev;
    hash = "sha256-m90HzB7fNnibaIDFaPr8RufhMS86PQJWTEHKopxh32Q=";
  };

  nelispLispSrc = runCommand "nelisp-${nelispVersion}-lisp" { } ''
    mkdir -p "$out"
    cp -R ${nelispSrc}/src/. "$out/"
  '';

  standaloneAnvilSrc = fetchFromGitHub {
    owner = "zawatton";
    repo = "anvil.el";
    rev = standaloneAnvilRev;
    hash = "sha256-88fItj7oPUnV1mWF8RFMcJJ1WbxLECmJ2yyd520cFWk=";
  };

  currentAnvilSrc = fetchFromGitHub {
    inherit (anvilSource)
      hash
      owner
      repo
      rev
      ;
  };

  anvilIdeSrc = fetchFromGitHub {
    inherit (anvilIdeSource)
      hash
      owner
      repo
      rev
      ;
  };

  dedicatedDirenvNeutral = runCommand "anvil-direnv-neutral" { } ''
    mkdir -p "$out"
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

  dedicatedSafeEmacsclientGuard = writeText "anvil-safe-emacsclient.py" ''
    import getopt
    import os
    import stat
    import sys

    SHORT_OPTIONS = "nqueHVtca:F:w:s:f:d:T:"
    LONG_OPTIONS = [
        "no-wait",
        "quiet",
        "suppress-output",
        "eval",
        "help",
        "version",
        "tty",
        "nw",
        "no-window-system",
        "create-frame",
        "reuse-frame",
        "alternate-editor=",
        "frame-parameters=",
        "socket-name=",
        "server-file=",
        "display=",
        "parent-id=",
        "timeout=",
        "tramp=",
    ]
    LONG_NAMES = tuple(option.removesuffix("=") for option in LONG_OPTIONS)
    SHORT_OPTION_NAMES = frozenset(SHORT_OPTIONS.replace(":", ""))
    TERMINAL_OPTIONS = frozenset(("-H", "--help", "-V", "--version"))
    EXIT_USAGE = 64
    EXIT_RECURSION = 69


    def delegate(real_client, arguments):
        os.execv(real_client, [real_client, *arguments])


    def normalize_long_only(argument):
        """Normalize getopt_long_only's single-dash long-option syntax."""
        if not argument.startswith("-") or argument.startswith("--"):
            return argument
        candidate = argument[1:].split("=", 1)[0]
        if len(candidate) == 1 and candidate in SHORT_OPTION_NAMES:
            return argument
        if candidate in LONG_NAMES:
            return f"-{argument}"
        matches = [name for name in LONG_NAMES if name.startswith(candidate)]
        if len(matches) == 1:
            return f"-{argument}"
        return argument


    def canonical_socket(target):
        """Resolve TARGET using the same local-socket rules as Emacsclient."""
        if "/" in target:
            return os.path.realpath(target)
        xdg_runtime = os.environ.get("XDG_RUNTIME_DIR")
        if xdg_runtime is not None:
            return os.path.realpath(f"{xdg_runtime}/emacs/{target}")
        temporary = os.environ.get("TMPDIR")
        if temporary is None and sys.platform == "darwin":
            try:
                temporary = os.confstr(65537)
            except (OSError, ValueError):
                temporary = None
        if temporary is None:
            temporary = "/tmp"
        return os.path.realpath(
            f"{temporary}/emacs{os.geteuid()}/{target}"
        )


    def same_socket(candidate, root_socket):
        """Compare socket identity, returning None when root is unverifiable."""
        root = os.path.realpath(root_socket)
        if candidate == root:
            return True
        try:
            root_info = os.stat(root, follow_symlinks=False)
        except OSError:
            # Losing the authoritative path must not turn a same-root alias
            # into an apparently safe peer target.  The caller fails closed
            # for this indeterminate state.
            return None
        if not stat.S_ISSOCK(root_info.st_mode):
            return None
        try:
            candidate_info = os.stat(candidate, follow_symlinks=False)
        except OSError:
            return False
        if not stat.S_ISSOCK(candidate_info.st_mode):
            return False
        return (candidate_info.st_dev, candidate_info.st_ino) == (
            root_info.st_dev,
            root_info.st_ino,
        )


    def terminal_precedes_parse_error(arguments):
        """Return whether real getopt exits for help/version before an error."""
        for end in range(1, len(arguments) + 1):
            try:
                options, _operands = getopt.gnu_getopt(
                    arguments[:end], SHORT_OPTIONS, LONG_OPTIONS
                )
            except getopt.GetoptError as error:
                if end < len(arguments) and "requires argument" in str(error):
                    continue
                return False
            if any(option in TERMINAL_OPTIONS for option, _value in options):
                return True
        return False


    def main():
        if len(sys.argv) < 2:
            raise SystemExit(EXIT_USAGE)
        real_client = sys.argv[1]
        arguments = sys.argv[2:]
        root_socket = os.environ.get("ANVIL_EMACS_SOCKET")
        if not root_socket:
            delegate(real_client, arguments)

        # Emacsclient uses getopt_long_only: in addition to ordinary short
        # clusters and double-dash long options it accepts exact or unique
        # long names after one dash (`-socket-name', `-so', and `-nw').
        parse_arguments = [normalize_long_only(arg) for arg in arguments]
        try:
            options, _operands = getopt.gnu_getopt(
                parse_arguments,
                SHORT_OPTIONS,
                LONG_OPTIONS,
            )
        except getopt.GetoptError:
            if terminal_precedes_parse_error(parse_arguments):
                delegate(real_client, arguments)
            print(
                "anvil-mcp: refusing an emacsclient invocation whose options "
                "cannot be checked safely",
                file=sys.stderr,
            )
            raise SystemExit(EXIT_USAGE)

        socket_values = []
        server_file_values = []
        for option, value in options:
            if option in ("-s", "--socket-name"):
                socket_values.append(value)
            elif option in ("-f", "--server-file"):
                server_file_values.append(value)
            elif option in TERMINAL_OPTIONS:
                delegate(real_client, arguments)

        socket_name = (
            socket_values[-1]
            if socket_values
            else os.environ.get("EMACS_SOCKET_NAME")
        )
        if socket_name is not None:
            effective_socket = canonical_socket(socket_name)
        else:
            server_file = (
                server_file_values[-1]
                if server_file_values
                else os.environ.get("EMACS_SERVER_FILE")
            )
            if server_file is not None:
                delegate(real_client, arguments)
            # A guarded child with no explicit selector is attempting the
            # authoritative active root, regardless of its direnv runtime.
            effective_socket = os.path.realpath(root_socket)

        same_root = same_socket(effective_socket, root_socket)
        if same_root is not False:
            print(
                "anvil-mcp: refusing recursive or unverifiable emacsclient "
                "call from the active Anvil root",
                file=sys.stderr,
            )
            raise SystemExit(EXIT_RECURSION)
        delegate(real_client, arguments)


    if __name__ == "__main__":
        main()
  '';

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

  dedicatedParentGuardLauncher = writeText "anvil-parent-guard.py" ''
    import ctypes
    import errno
    import os
    import select
    import signal
    import sys
    import time

    EXIT_SOFTWARE = 70
    READY_TIMEOUT_SECONDS = ${toString timeoutPolicy.parentGuardReadySeconds}.0


    def fail(message):
        print(f"anvil-mcp: parent guard: {message}", file=sys.stderr)
        raise SystemExit(EXIT_SOFTWARE)


    def close_lock_fds():
        for descriptor in (8, 9):
            try:
                os.close(descriptor)
            except OSError as error:
                if error.errno != errno.EBADF:
                    fail(f"cannot close lock fd {descriptor}: {error}")


    def validate_parent_pid(raw):
        if not raw or not raw.isascii() or not raw.isdecimal():
            fail("ANVIL_HEADLESS_PARENT_PID must be a decimal PID")
        parent_pid = int(raw)
        if parent_pid <= 1:
            fail("ANVIL_HEADLESS_PARENT_PID must be greater than one")
        if os.getppid() != parent_pid:
            fail(
                f"expected owner pid {parent_pid}, "
                f"found parent pid {os.getppid()}"
            )
        return parent_pid


    def validate_bridge_pid(raw):
        if raw is None:
            return None
        if not raw or not raw.isascii() or not raw.isdecimal():
            fail("ANVIL_HEADLESS_BRIDGE_PID must be a decimal PID")
        bridge_pid = int(raw)
        if bridge_pid <= 1:
            fail("ANVIL_HEADLESS_BRIDGE_PID must be greater than one")
        return bridge_pid


    def install_linux_parent_death_signal(expected_parent):
        libc = ctypes.CDLL(None, use_errno=True)
        if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0:
            error = ctypes.get_errno()
            fail(f"prctl(PR_SET_PDEATHSIG) failed: {os.strerror(error)}")
        if os.getppid() != expected_parent:
            os.kill(os.getpid(), signal.SIGKILL)


    def terminate_group(target_pid):
        try:
            # The PGID remains allocated while any non-detached member
            # survives, even after the shell leader itself has exited.
            os.killpg(target_pid, signal.SIGKILL)
        except OSError:
            pass


    def terminate_target(target_pid, group, state):
        if group and state["committed"]:
            # The guard itself anchors this PGID after the R/C/A handshake, so
            # it cannot disappear or be reused when the target leader exits.
            terminate_group(target_pid)
            return
        # Before commitment the target is blocked before exec and has no
        # program descendants, so only its exact PID is safe to signal.
        try:
            os.kill(target_pid, signal.SIGKILL)
        except OSError:
            pass


    def close_guard_descriptors(ready_fd, commit_fd):
        preserved = sorted({ready_fd, commit_fd})
        null_fd = os.open(os.devnull, os.O_RDWR)
        for descriptor in (0, 1, 2):
            os.dup2(null_fd, descriptor)
        if null_fd > 2 and null_fd not in preserved:
            os.close(null_fd)
        try:
            descriptor_limit = int(os.sysconf("SC_OPEN_MAX"))
        except (OSError, TypeError, ValueError):
            descriptor_limit = 65536
        descriptor_limit = max(256, min(descriptor_limit, 1048576))
        first = 3
        for descriptor in preserved:
            if first < descriptor:
                os.closerange(first, descriptor)
            first = descriptor + 1
        os.closerange(first, descriptor_limit)


    def install_guard_signal_handlers(target_pid, group, state):
        handled = (signal.SIGINT, signal.SIGHUP, signal.SIGTERM)
        if hasattr(signal, "pthread_sigmask"):
            signal.pthread_sigmask(signal.SIG_UNBLOCK, handled)

        def stop_guard(_signum, _frame):
            terminate_target(target_pid, group, state)
            os._exit(0)

        for signum in handled:
            signal.signal(signum, stop_guard)


    def acknowledge_group_commit(target_pid, group, ready_fd, commit_fd, state):
        try:
            marker = os.read(commit_fd, 1)
        except OSError as error:
            raise RuntimeError(f"cannot read group commitment: {error}") from error
        if marker != b"C":
            raise RuntimeError("target did not commit its process group")
        if group and os.getpgrp() != target_pid:
            raise RuntimeError("guard did not enter the committed target group")
        state["committed"] = group
        try:
            os.write(ready_fd, b"A")
        except OSError as error:
            raise RuntimeError(f"cannot acknowledge group commitment: {error}") from error
        os.close(commit_fd)
        os.close(ready_fd)


    def guard_linux(
        root_pid,
        target_pid,
        bridge_pid,
        group,
        ready_fd,
        commit_fd,
        state,
    ):
        root_fd = os.pidfd_open(root_pid, 0)
        target_fd = os.pidfd_open(target_pid, 0)
        bridge_fd = os.pidfd_open(bridge_pid, 0) if bridge_pid is not None else None
        poller = select.poll()
        poller.register(root_fd, select.POLLIN)
        poller.register(target_fd, select.POLLIN)
        if bridge_fd is not None:
            poller.register(bridge_fd, select.POLLIN)
        poller.register(commit_fd, select.POLLIN | select.POLLHUP | select.POLLERR)
        lifecycle_fds = {root_fd, target_fd}
        if bridge_fd is not None:
            lifecycle_fds.add(bridge_fd)
        if any(
            descriptor in lifecycle_fds
            for descriptor, _event in poller.poll(0)
        ):
            raise RuntimeError(
                "bridge, root, or target exited before guard readiness"
            )
        install_guard_signal_handlers(target_pid, group, state)
        os.write(ready_fd, b"R")
        while True:
            events = poller.poll()
            if any(descriptor in lifecycle_fds for descriptor, _event in events):
                terminate_target(target_pid, group, state)
                os._exit(0)
            if any(descriptor == commit_fd for descriptor, _event in events):
                poller.unregister(commit_fd)
                acknowledge_group_commit(
                    target_pid,
                    group,
                    ready_fd,
                    commit_fd,
                    state,
                )


    def guard_darwin(
        root_pid,
        target_pid,
        bridge_pid,
        group,
        ready_fd,
        commit_fd,
        state,
    ):
        queue = select.kqueue()
        flags = select.KQ_EV_ADD | select.KQ_EV_ENABLE
        lifecycle_pids = {root_pid, target_pid}
        if bridge_pid is not None:
            lifecycle_pids.add(bridge_pid)
        changes = [
            select.kevent(
                process_pid,
                filter=select.KQ_FILTER_PROC,
                flags=flags,
                fflags=select.KQ_NOTE_EXIT,
            )
            for process_pid in lifecycle_pids
        ] + [
            select.kevent(
                commit_fd,
                filter=select.KQ_FILTER_READ,
                flags=flags,
            ),
        ]
        queue.control(changes, 0, 0)
        initial = queue.control(None, len(changes), 0)
        if any(
            event.filter == select.KQ_FILTER_PROC
            and event.ident in lifecycle_pids
            for event in initial
        ):
            raise RuntimeError(
                "bridge, root, or target exited before guard readiness"
            )
        install_guard_signal_handlers(target_pid, group, state)
        os.write(ready_fd, b"R")
        while True:
            events = queue.control(None, len(changes), None)
            if any(
                event.filter == select.KQ_FILTER_PROC
                and event.ident in lifecycle_pids
                for event in events
            ):
                terminate_target(target_pid, group, state)
                os._exit(0)
            if any(
                event.filter == select.KQ_FILTER_READ
                and event.ident == commit_fd
                for event in events
            ):
                queue.control(
                    [
                        select.kevent(
                            commit_fd,
                            filter=select.KQ_FILTER_READ,
                            flags=select.KQ_EV_DELETE,
                        )
                    ],
                    0,
                    0,
                )
                acknowledge_group_commit(
                    target_pid,
                    group,
                    ready_fd,
                    commit_fd,
                    state,
                )


    def run_guard(
        root_pid,
        target_pid,
        bridge_pid,
        group,
        ready_fd,
        commit_fd,
    ):
        state = {"committed": False}
        try:
            # close_lock_fds() already ran before os.pipe(); calling it again
            # could close a protocol FD that reused descriptor 8 or 9.
            close_guard_descriptors(ready_fd, commit_fd)
            if sys.platform.startswith("linux"):
                guard_linux(
                    root_pid,
                    target_pid,
                    bridge_pid,
                    group,
                    ready_fd,
                    commit_fd,
                    state,
                )
            elif sys.platform == "darwin":
                guard_darwin(
                    root_pid,
                    target_pid,
                    bridge_pid,
                    group,
                    ready_fd,
                    commit_fd,
                    state,
                )
            else:
                raise RuntimeError(f"unsupported platform: {sys.platform}")
        except BaseException:
            terminate_target(target_pid, group, state)
            for descriptor in (ready_fd, commit_fd):
                try:
                    os.close(descriptor)
                except OSError:
                    pass
            os._exit(EXIT_SOFTWARE)


    if len(sys.argv) < 3 or sys.argv[1] not in (
        "exact",
        "group",
        "external-group",
    ):
        fail(
            "usage: anvil-parent-guard.py "
            "exact|group|external-group PROGRAM [ARG ...]"
        )

    signal.signal(signal.SIGCHLD, signal.SIG_DFL)
    close_lock_fds()
    mode = sys.argv[1]
    external_owner = mode == "external-group"
    program_argv = sys.argv[2:]
    target_pid = os.getpid()
    root_pid = validate_parent_pid(
        os.environ.pop("ANVIL_HEADLESS_PARENT_PID", None)
    )
    bridge_pid = validate_bridge_pid(
        os.environ.pop("ANVIL_HEADLESS_BRIDGE_PID", None)
    )

    if sys.platform.startswith("linux"):
        if not hasattr(os, "pidfd_open"):
            fail("Linux requires pidfd_open")
        # PR_SET_PDEATHSIG tracks the particular parent thread which created
        # this process. That is correct for our single-threaded Python daemon
        # parents, but not for multithreaded Codex/Tokio. External owners use
        # the guard's pidfd for process-wide death notification instead.
        if not external_owner:
            install_linux_parent_death_signal(root_pid)
    elif sys.platform != "darwin" or not hasattr(select, "kqueue"):
        fail(f"unsupported platform: {sys.platform}")

    group = mode in ("group", "external-group")
    ready_read, ready_write = os.pipe()
    commit_read, commit_write = os.pipe()
    handshake_deadline = time.monotonic() + READY_TIMEOUT_SECONDS
    try:
        guard_pid = os.fork()
    except OSError as error:
        for descriptor in (ready_read, ready_write, commit_read, commit_write):
            os.close(descriptor)
        fail(f"cannot fork guard: {error}")

    if guard_pid == 0:
        os.close(ready_read)
        os.close(commit_write)
        run_guard(
            root_pid,
            target_pid,
            bridge_pid,
            group,
            ready_write,
            commit_read,
        )
        os._exit(0)

    os.close(ready_write)
    os.close(commit_read)

    def read_handshake_marker():
        remaining = handshake_deadline - time.monotonic()
        if remaining <= 0:
            return b""
        readable, _, _ = select.select([ready_read], [], [], remaining)
        if not readable or time.monotonic() >= handshake_deadline:
            return b""
        marker = os.read(ready_read, 1)
        if time.monotonic() >= handshake_deadline:
            return b""
        return marker

    def abort_guard(message):
        for descriptor in (ready_read, commit_write):
            try:
                os.close(descriptor)
            except OSError:
                pass
        terminate_target(guard_pid, False, {"committed": False})
        try:
            os.waitpid(guard_pid, 0)
        except ChildProcessError:
            pass
        fail(message)

    ready = read_handshake_marker()
    if ready != b"R":
        abort_guard("guard did not become ready")
    if os.getppid() != root_pid:
        os.kill(os.getpid(), signal.SIGKILL)

    # The target cannot exec until the monitor acknowledges commitment.  The
    # monitor starts in this process's inherited group, so it remains movable
    # by its exact unreaped parent until it joins and anchors target_pid.
    if group and os.getpgrp() != target_pid:
        try:
            os.setpgid(0, 0)
        except OSError as error:
            abort_guard(f"cannot establish target process group: {error}")
    if group and os.getpgrp() != target_pid:
        abort_guard("target is not its process-group leader")
    if group:
        try:
            os.setpgid(guard_pid, target_pid)
            guard_group = os.getpgid(guard_pid)
        except OSError as error:
            abort_guard(f"cannot anchor target process group: {error}")
        if guard_group != target_pid:
            abort_guard("guard did not anchor the target process group")

    try:
        written = os.write(commit_write, b"C")
    except OSError as error:
        abort_guard(f"cannot commit target process group: {error}")
    os.close(commit_write)
    if written != 1:
        abort_guard("target process-group commitment was incomplete")

    acknowledged = read_handshake_marker()
    os.close(ready_read)
    if acknowledged != b"A":
        abort_guard("guard did not acknowledge target process group")
    if os.getppid() != root_pid:
        os.kill(os.getpid(), signal.SIGKILL)

    try:
        os.execvpe(program_argv[0], program_argv, os.environ)
    except OSError as error:
        terminate_target(guard_pid, False, {"committed": False})
        fail(f"cannot exec {program_argv[0]}: {error}")
  '';

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

  dedicatedEnvironmentInit = writeText "anvil-headless-environment-init.el" ''
        ;;; anvil-headless-environment-init.el --- Project environment support -*- lexical-binding: t; -*-

        (require 'exec-path-from-shell)
        (require 'direnv)
        (add-to-list 'load-path "${dedicatedAnvil}/share/emacs/site-lisp")
        (require 'anvil-host)
        (setq direnv-always-show-summary nil)

        ;; These variables are defined by the packaged anvil-host source.  Bare
        ;; declarations make the bindings below dynamic under lexical compilation.
        (defvar anvil-host-child-process-environment)
        (defvar anvil-host-child-exec-path)
        (defvar anvil-host-child-shell-file-name)
        (defvar anvil-host-child-shell-command-switch)

        (defvar anvil-headless--baseline-process-environment nil)
        (defvar anvil-headless--baseline-exec-path nil)
        (defvar anvil-headless--baseline-shell-file-name nil)
        (defvar anvil-headless--baseline-shell-command-switch nil)
        (defvar anvil-headless--baseline-default-directory nil)
        (defvar anvil-headless--ready nil)
        (defvar anvil-server--running)
        (defvar anvil-server--tools)

        (defun anvil-headless--ready-p (&optional server-id)
          "Return non-nil when SERVER-ID's complete tool surface is ready."
          (and anvil-headless--ready
               (boundp 'anvil-server--running)
               anvil-server--running
               (boundp 'anvil-server--tools)
               (hash-table-p anvil-server--tools)
               (let* ((server-id (or server-id "anvil"))
                      (required-tool
                       (cond
                        ((equal server-id "anvil") "emacs-eval")
                        ((equal server-id "emacs-eval") "file-read")))
                      (registry
                       (and required-tool
                            (gethash server-id anvil-server--tools))))
                 (and (hash-table-p registry)
                      (gethash required-tool registry)
                      t))))

        (defconst anvil-headless--root-socket
          (let ((socket (getenv "ANVIL_EMACS_SOCKET")))
            (unless (and (stringp socket)
                         (not (string= socket ""))
                         (file-name-absolute-p socket))
              (error "Anvil root socket environment is missing or invalid"))
            (expand-file-name socket))
          "Authoritative root socket, captured before project environments run.")

        (defconst anvil-headless--emacs-bin-directory
          (file-name-as-directory "${dedicatedRuntimeEmacs}/bin")
          "Directory containing the dedicated Emacs and emacsclient binaries.")

        (defconst anvil-headless--safe-client-bin-directory
          (file-name-as-directory "${dedicatedSafeEmacsclient}/bin")
          "Directory containing the same-root recursion guard.")

        (defconst anvil-headless--direnv-executable
          "${direnv}/bin/direnv"
          "Pinned direnv executable for the dedicated Anvil environment.")

        (defconst anvil-headless--direnv-status-timeout
          ${toString timeoutPolicy.direnvStatusSeconds}
          "Maximum seconds for one pinned direnv status query.")

        (defconst anvil-headless--direnv-export-timeout
          ${toString timeoutPolicy.direnvExportSeconds}
          "Maximum seconds for one pinned direnv environment export.")

        (defconst anvil-headless--direnv-export-max-stdout-bytes
          (* 4 1024 1024)
          "Maximum bytes retained from one direnv environment export.")

        (defconst anvil-headless--direnv-status-max-stdout-bytes
          (* 1024 1024)
          "Maximum bytes retained from one direnv status query.")

        (defconst anvil-headless--direnv-max-stderr-bytes
          (* 256 1024)
          "Maximum diagnostic bytes retained from one direnv subprocess.")

        (defconst anvil-headless--environment-max-output-chunks 4096
          "Maximum filter fragments retained from one environment stream.")

        (defun anvil-headless--capture-bounded-output (state limit chunk)
          "Append binary CHUNK to STATE without retaining more than LIMIT bytes."
          (let ((size (string-bytes chunk))
                (used (aref state 1)))
            (if (or (aref state 2)
                    (>= (aref state 3)
                        anvil-headless--environment-max-output-chunks)
                    (> size (- limit used)))
                (aset state 2 t)
              (aset state 0 (cons chunk (aref state 0)))
              (aset state 1 (+ used size))
              (aset state 3 (1+ (aref state 3))))))

        (defun anvil-headless--check-output-limits
            (stdout-state stderr-state)
          "Signal a content-free error if either bounded output STATE overflowed."
          (cond
           ((aref stdout-state 2)
            (error "Anvil environment stdout exceeded its capture limit"))
           ((aref stderr-state 2)
            (error "Anvil environment stderr exceeded its capture limit"))))

        (defun anvil-headless--run-process-responsive
            (program arguments directory timeout stdout-limit stderr-limit)
          "Run PROGRAM with ARGUMENTS in DIRECTORY within TIMEOUT seconds.
    Retain at most STDOUT-LIMIT and STDERR-LIMIT bytes and return
    (EXIT STDOUT STDERR) without exposing output or project bindings.
    This function prepares the environment consumed by anvil-host--run and must
    therefore use the lower-level transaction helpers instead of recursing through
    the direnv advice on that function."
          (unless (and anvil-headless--baseline-process-environment
                       anvil-headless--baseline-exec-path
                       anvil-headless--baseline-default-directory)
            (error "Anvil baseline environment is unavailable"))
          (unless (and (numberp timeout) (> timeout 0))
            (error "Anvil environment timeout must be positive"))
          (dolist (limit (list stdout-limit stderr-limit))
            (unless (and (integerp limit) (>= limit 0))
              (error "Anvil environment byte limits must be nonnegative integers")))
          ;; Capture the caller's project state before installing the daemon
          ;; baseline around any operation that can yield to an unrelated callback.
          (let* ((child-directory
                  (file-name-as-directory (expand-file-name directory)))
                 (child-environment
                  (let ((process-environment
                         (copy-sequence process-environment)))
                    (setenv "ANVIL_HEADLESS_PARENT_PID"
                            (number-to-string (emacs-pid)))
                    (copy-sequence process-environment)))
                 (child-exec-path (copy-sequence exec-path))
                 (outer-inhibit-quit inhibit-quit))
            (let ((default-directory
                   anvil-headless--baseline-default-directory)
                  (process-environment
                   (copy-sequence
                    anvil-headless--baseline-process-environment))
                  (exec-path
                   (copy-sequence anvil-headless--baseline-exec-path))
                  (shell-file-name
                   anvil-headless--baseline-shell-file-name)
                  (shell-command-switch
                   anvil-headless--baseline-shell-command-switch)
                  (anvil-host-child-process-environment nil)
                  (anvil-host-child-exec-path nil)
                  (anvil-host-child-shell-file-name nil)
                  (anvil-host-child-shell-command-switch nil))
              (let ((resources (anvil-host--resource-state)))
                (when (aref resources 3)
                  (error "Anvil environment submission is already active"))
                (let ((inhibit-quit t))
                  (aset resources 3 t)
                  (unwind-protect
                      (let ((inhibit-quit outer-inhibit-quit))
                        (anvil-headless--run-process-responsive-transaction
                         program arguments child-directory child-environment
                         child-exec-path timeout stdout-limit stderr-limit))
                    (aset resources 3 nil)))))))

        (defun anvil-headless--run-process-responsive-transaction
            (program arguments child-directory child-environment child-exec-path
                     timeout stdout-limit stderr-limit)
          "Run one guarded environment subprocess transaction."
          (anvil-host--resource-state)
          (when (anvil-host--cleanup-active-p)
            (error "Anvil host cleanup is already active"))
          (unless (anvil-host--retired-empty-p)
            (anvil-host--retry-retired-processes))
          (when (or (anvil-host--cleanup-active-p)
                    (not (anvil-host--retired-empty-p)))
            (error "Anvil retained host cleanup has not converged"))
          (anvil-host--retired-table)
          (let* ((process-name
                  (anvil-host--unique-process-name
                   "anvil-environment-process-"))
                 (stderr-name
                  (anvil-host--unique-process-name
                   "anvil-environment-stderr-"))
                 (stdout-state (vector nil 0 nil 0))
                 (stderr-state (vector nil 0 nil 0))
                 (stdout-filter
                  (lambda (_process chunk)
                    (unwind-protect
                        (anvil-headless--capture-bounded-output
                         stdout-state stdout-limit chunk)
                      (anvil-host--scrub-code-conversion-work-buffer))))
                 (stderr-filter
                  (lambda (_process chunk)
                    (unwind-protect
                        (anvil-headless--capture-bounded-output
                         stderr-state stderr-limit chunk)
                      (anvil-host--scrub-code-conversion-work-buffer))))
                 stderr-constructor-started-p
                 stderr-constructor-before
                 stderr-constructor-processes
                 stderr-constructor-complete-p
                 stderr-constructor-invalid-p
                 main-constructor-started-p
                 main-constructor-before
                 main-constructor-processes
                 main-constructor-complete-p
                 main-constructor-invalid-p
                 process
                 stderr-process)
            (unwind-protect
                (progn
                  ;; A pipe process needs a buffer anchor at construction time.
                  ;; The captured constructor cannot yield through runtime advice;
                  ;; detach the anchor immediately and keep bytes only in lexical
                  ;; filter state.
                  (let ((default-directory
                         anvil-headless--baseline-default-directory)
                        (process-environment
                         (copy-sequence
                          anvil-headless--baseline-process-environment))
                        (exec-path
                         (copy-sequence anvil-headless--baseline-exec-path))
                        (shell-file-name
                         anvil-headless--baseline-shell-file-name)
                        (shell-command-switch
                         anvil-headless--baseline-shell-command-switch)
                        (anvil-host-child-process-environment nil)
                        (anvil-host-child-exec-path nil)
                        (anvil-host-child-shell-file-name nil)
                        (anvil-host-child-shell-command-switch nil))
                    (setq stderr-constructor-before
                          (funcall anvil-host--process-list-primitive)
                          stderr-constructor-started-p t)
                    (setq stderr-process
                          (funcall anvil-host--make-pipe-process-primitive
                           :name stderr-name
                           :buffer (current-buffer)
                           :coding 'binary
                           :noquery t
                           :sentinel #'ignore
                           :filter stderr-filter))
                    (setq stderr-constructor-processes
                          (anvil-host--new-processes-since
                           stderr-constructor-before)
                          stderr-constructor-complete-p t))
                  (let ((valid
                         (and
                          (processp stderr-process)
                          (not (memq stderr-process
                                     stderr-constructor-before))
                          (eq
                           (funcall anvil-host--process-filter-primitive
                                    stderr-process)
                           stderr-filter))))
                    (setq stderr-constructor-invalid-p (not valid))
                    (anvil-host--detach-constructor-processes
                     (if valid
                         (cl-remove-if-not
                          (lambda (candidate)
                            (anvil-host--process-matches-constructor-p
                             candidate stderr-name stderr-filter))
                          stderr-constructor-processes)
                       stderr-constructor-processes))
                    (unless valid
                      (if (memq stderr-process stderr-constructor-before)
                          (error
                           "Anvil pipe constructor returned a preexisting process")
                        (error
                         "Anvil pipe constructor returned an invalid process"))))
                  ;; The parent guard owns the complete direnv process group.
                  ;; Project-specific bindings exist only for this captured spawn.
                  (let ((default-directory child-directory)
                        (process-environment child-environment)
                        (exec-path child-exec-path)
                        (shell-file-name
                         anvil-headless--baseline-shell-file-name)
                        (shell-command-switch
                         anvil-headless--baseline-shell-command-switch))
                    (setq main-constructor-before
                          (funcall anvil-host--process-list-primitive)
                          main-constructor-started-p t)
                    (setq process
                          (funcall anvil-host--make-process-primitive
                           :name process-name
                           :buffer nil
                           :stderr stderr-process
                           :filter stdout-filter
                           :command
                           (append
                            (list "${python3}/bin/python3" "-I" "-B"
                                  "${dedicatedParentGuardLauncher}"
                                  "group" program)
                            arguments)
                           :coding '(binary . binary)
                           :connection-type 'pipe
                           :noquery t
                           :sentinel #'ignore))
                    (setq main-constructor-processes
                          (anvil-host--new-processes-since
                           main-constructor-before)
                          main-constructor-complete-p t))
                  (let ((valid
                         (and
                          (processp process)
                          (not (memq process main-constructor-before))
                          (eq
                           (funcall anvil-host--process-filter-primitive
                                    process)
                           stdout-filter))))
                    (setq main-constructor-invalid-p (not valid))
                    (anvil-host--detach-constructor-processes
                     (if valid
                         (cl-remove-if-not
                          (lambda (candidate)
                            (anvil-host--process-matches-constructor-p
                             candidate process-name stdout-filter))
                          main-constructor-processes)
                       main-constructor-processes))
                    (unless valid
                      (cond
                       ((not (processp process))
                        (error "Anvil environment process did not start"))
                       ((memq process main-constructor-before)
                        (error
                         "Anvil process constructor returned a preexisting process"))
                       (t
                        (error
                         "Anvil process constructor returned an invalid process")))))
                  ;; Every event-loop yield runs under the immutable daemon
                  ;; baseline, so unrelated callbacks cannot inherit a project's
                  ;; direnv state.
                  (let ((default-directory
                         anvil-headless--baseline-default-directory)
                        (process-environment
                         (copy-sequence
                          anvil-headless--baseline-process-environment))
                        (exec-path
                         (copy-sequence anvil-headless--baseline-exec-path))
                        (shell-file-name
                         anvil-headless--baseline-shell-file-name)
                        (shell-command-switch
                         anvil-headless--baseline-shell-command-switch)
                        (anvil-host-child-process-environment nil)
                        (anvil-host-child-exec-path nil)
                        (anvil-host-child-shell-file-name nil)
                        (anvil-host-child-shell-command-switch nil))
                    (condition-case error
                        (funcall
                         anvil-host--process-send-eof-primitive process)
                      (error
                       (when (process-live-p process)
                         (signal (car error) (cdr error)))))
                    ;; The immutable baseline bindings above remain in
                    ;; force while all process output is serviced.  This keeps
                    ;; Emacs server sockets and foreign helper filters responsive
                    ;; without exposing the child environment to callbacks.
                    (let ((deadline (+ (float-time) timeout)))
                      (while (and (process-live-p process)
                                  (< (float-time) deadline))
                        (funcall
                         anvil-host--accept-process-output-primitive
                         process 0.05 nil nil)
                        (anvil-headless--check-output-limits
                         stdout-state stderr-state)
                        (when (and (processp stderr-process)
                                   (process-live-p stderr-process))
                          (funcall
                           anvil-host--accept-process-output-primitive
                           stderr-process 0 nil nil)
                          (anvil-headless--check-output-limits
                           stdout-state stderr-state)))
                      (when (process-live-p process)
                        (error
                         "Anvil environment process timed out after %ss"
                         timeout)))
                    (when (and (processp stderr-process)
                               (process-live-p stderr-process))
                      (let ((deadline (+ (float-time) 0.25)))
                        (while (and (process-live-p stderr-process)
                                    (< (float-time) deadline))
                          (funcall
                           anvil-host--accept-process-output-primitive
                           stderr-process 0.02 nil nil)
                          (anvil-headless--check-output-limits
                           stdout-state stderr-state)
                          (funcall
                           anvil-host--accept-process-output-primitive
                           process 0 nil nil)
                          (anvil-headless--check-output-limits
                           stdout-state stderr-state))))
                    (funcall anvil-host--accept-process-output-primitive
                             process 0.01 nil nil)
                    (anvil-headless--check-output-limits
                     stdout-state stderr-state))
                  (list
                   (process-exit-status process)
                   (anvil-host--decode-output
                    (apply #'concat (nreverse (aref stdout-state 0)))
                    'utf-8-unix)
                   (anvil-host--decode-output
                    (apply #'concat (nreverse (aref stderr-state 0)))
                    'utf-8-unix)))
              ;; Recover exact post-snapshot children on every exit, including
              ;; constructor throws and queued quits, before releasing the public
              ;; submission guard.
              (let ((inhibit-quit t)
                    (default-directory
                     anvil-headless--baseline-default-directory)
                    (process-environment
                     (copy-sequence
                      anvil-headless--baseline-process-environment))
                    (exec-path
                     (copy-sequence anvil-headless--baseline-exec-path))
                    (shell-file-name
                     anvil-headless--baseline-shell-file-name)
                    (shell-command-switch
                     anvil-headless--baseline-shell-command-switch)
                    (anvil-host-child-process-environment nil)
                    (anvil-host-child-exec-path nil)
                    (anvil-host-child-shell-file-name nil)
                    (anvil-host-child-shell-command-switch nil))
                (let* ((processes
                        (anvil-host--transaction-processes
                         process process-name stdout-filter
                         main-constructor-started-p main-constructor-before
                         main-constructor-complete-p
                         main-constructor-invalid-p
                         main-constructor-processes))
                       (stderr-processes
                        (anvil-host--transaction-processes
                         stderr-process stderr-name stderr-filter
                         stderr-constructor-started-p
                         stderr-constructor-before
                         stderr-constructor-complete-p
                         stderr-constructor-invalid-p
                         stderr-constructor-processes))
                       (metadata
                        (anvil-host--candidate-metadata
                         processes stderr-processes)))
                  (anvil-host--retire-resources metadata))))))
        ;; Append only known packaged tools after login/project paths.  Do not
        ;; resurrect arbitrary PATH entries inherited from launchd or a caller.
        (defconst anvil-headless--required-exec-path
          '(${lib.concatMapStringsSep "\n        " builtins.toJSON dedicatedRequiredExecPath}))

        (defun anvil-headless--restore-required-exec-path (&rest _args)
          "Restore packaged tools and immutable recursion-guard state."
          (let* ((normalized
                  (delete-dups
                   (mapcar
                    (lambda (directory)
                      (if (stringp directory)
                          (directory-file-name directory)
                        directory))
                    exec-path)))
                 (emacs-bin
                  (directory-file-name anvil-headless--emacs-bin-directory))
                 (safe-client-bin
                  (directory-file-name
                   anvil-headless--safe-client-bin-directory)))
            (setq exec-path
                  (cons safe-client-bin
                        (cons emacs-bin
                              (delete safe-client-bin
                                      (delete emacs-bin normalized))))))
          (dolist (directory anvil-headless--required-exec-path)
            (unless (member directory exec-path)
              (setq exec-path (append exec-path (list directory)))))
          (let ((path (mapconcat #'identity exec-path
                                 path-separator)))
            (setenv "PATH" path)
            (setenv "ANVIL_EMACS_SOCKET" anvil-headless--root-socket)
            (when (boundp 'eshell-path-env)
              (if (local-variable-p 'process-environment)
                  (setq-local eshell-path-env path)
                (setq-default eshell-path-env path)))))

        ;; Workers inherit the root daemon's already-imported login environment.
        ;; Avoid launching four more interactive login shells during staggered
        ;; worker startup.
        (unless (equal (getenv "ANVIL_EMACS_WORKER") "1")
          (setq exec-path-from-shell-arguments '("-l"))
          (exec-path-from-shell-initialize))
        (anvil-headless--restore-required-exec-path)
        (setq direnv--executable anvil-headless--direnv-executable)

        (defun anvil-headless--direnv-export-checked (directory)
          "Run one pinned direnv export for DIRECTORY and reject every failure."
          (let* ((result
                  (anvil-headless--run-process-responsive
                   anvil-headless--direnv-executable '("export" "json")
                   directory anvil-headless--direnv-export-timeout
                   anvil-headless--direnv-export-max-stdout-bytes
                   anvil-headless--direnv-max-stderr-bytes))
                 (exit-code (nth 0 result))
                 (stdout (nth 1 result)))
            (unless (and (integerp exit-code) (zerop exit-code))
              ;; Do not copy stderr into the error: envrc output may contain
              ;; project secrets.  The caller needs only a fail-closed result.
              (error "direnv export failed"))
            ;; Parse directly from the lexical string.  In particular, never copy
            ;; the complete project environment into direnv's persistent output
            ;; buffer where a reentrant MCP callback could inspect it.
            (let ((document
                   (json-parse-string
                    stdout
                    :object-type 'hash-table
                    :array-type 'list
                    :null-object nil
                    :false-object nil))
                  environment)
              (unless (hash-table-p document)
                (error "direnv export returned an invalid environment"))
              (maphash
               (lambda (name value)
                 (unless (and (stringp name)
                              (or (null value) (stringp value)))
                   (error "direnv export returned an invalid environment"))
                 (push (cons name value) environment))
               document)
              (nreverse environment))))

        (advice-add 'direnv--export
                    :override #'anvil-headless--direnv-export-checked)

        (defun anvil-headless--guard-direnv-update (original &rest args)
          "Run ORIGINAL and restore immutable guard controls even on failure."
          (unwind-protect
              (apply original args)
            (anvil-headless--restore-required-exec-path)))

        (advice-add 'direnv-update-directory-environment
                    :around #'anvil-headless--guard-direnv-update)

        (defconst anvil-headless--direnv-bookkeeping-variables
          '("DIRENV_DIFF" "DIRENV_DIR" "DIRENV_FILE" "DIRENV_WATCHES"
            "DIRENV_DUMP_FILE_PATH"))

        (defun anvil-headless--environment-with (environment name value)
          "Return a copy of ENVIRONMENT with NAME set to VALUE."
          (let ((process-environment (copy-sequence environment)))
            (setenv name value)
            process-environment))

        (defun anvil-headless--snapshot-baseline-environment ()
          "Freeze the cleaner-restored login environment before any request."
          (let ((environment (copy-sequence process-environment))
                (baseline-exec-path (copy-sequence exec-path))
                (baseline-default-directory
                 (file-name-as-directory
                  (file-truename
                   (expand-file-name user-emacs-directory)))))
            (setq environment
                  (anvil-headless--environment-with
                   environment "ANVIL_EMACS_SOCKET"
                   anvil-headless--root-socket))
            (dolist (name
                     (append
                      '("ANVIL_HEADLESS_PARENT_PID"
                        "ANVIL_HEADLESS_REAL_SHELL")
                      anvil-headless--direnv-bookkeeping-variables))
              (setq environment
                    (anvil-headless--environment-with
                     environment name nil)))
            (setq anvil-headless--baseline-process-environment environment
                  anvil-headless--baseline-exec-path baseline-exec-path
                  anvil-headless--baseline-shell-file-name shell-file-name
                  anvil-headless--baseline-shell-command-switch
                  shell-command-switch
                  anvil-headless--baseline-default-directory
                  baseline-default-directory)
            ;; A request evaluated in a buffer without local bindings must see the
            ;; same immutable baseline as new buffers, workers, and offload children.
            (set-default 'process-environment (copy-sequence environment))
            (set-default 'exec-path (copy-sequence baseline-exec-path))
            (set-default 'default-directory baseline-default-directory)
            (kill-local-variable 'process-environment)
            (kill-local-variable 'exec-path)
            (kill-local-variable 'default-directory))
          (unless (and (listp anvil-headless--baseline-process-environment)
                       (listp anvil-headless--baseline-exec-path)
                       (stringp anvil-headless--baseline-shell-file-name)
                       (stringp anvil-headless--baseline-shell-command-switch)
                       (stringp anvil-headless--baseline-default-directory)
                       (file-directory-p
                        anvil-headless--baseline-default-directory))
            (error "Anvil could not snapshot its baseline environment")))

        (defun anvil-headless--strip-direnv-bookkeeping ()
          "Remove direnv's internal state from the current process environment."
          (dolist (name anvil-headless--direnv-bookkeeping-variables)
            (setenv name nil)))

        (defun anvil-headless--canonical-direnv-directory (directory)
          "Return DIRECTORY in one stable, physical directory form."
          (file-name-as-directory
           (file-truename (expand-file-name directory))))

        (defun anvil-headless--direnv-allowed-p
            (directory &optional fail-on-error)
          "Return non-nil only when DIRECTORY has an explicitly allowed envrc.
    When FAIL-ON-ERROR is non-nil, signal a generic error if pinned direnv status
    cannot complete or return valid JSON."
          (condition-case nil
              (let* ((result
                      (anvil-headless--run-process-responsive
                       anvil-headless--direnv-executable '("status" "--json")
                       directory anvil-headless--direnv-status-timeout
                       anvil-headless--direnv-status-max-stdout-bytes
                       anvil-headless--direnv-max-stderr-bytes))
                     (exit-code (nth 0 result)))
                (unless (and (integerp exit-code) (zerop exit-code))
                  (error "direnv status failed"))
                (let* ((document
                        (json-parse-string
                         (nth 1 result)
                         :object-type 'hash-table
                         :array-type 'list
                         :null-object nil
                         :false-object nil))
                       (state (and (hash-table-p document)
                                   (gethash "state" document)))
                       (found (and (hash-table-p state)
                                   (gethash "foundRC" state))))
                  (and (hash-table-p found)
                       (eql (gethash "allowed" found) 0))))
            (error
             (when fail-on-error
               (error "direnv status failed"))
             nil)))

        (defun anvil-headless--restore-direnv-baseline
            (environment executable-path active-directory)
          "Restore pre-update ENVIRONMENT, EXECUTABLE-PATH, and ACTIVE-DIRECTORY."
          (setq-local process-environment environment)
          (setq-local exec-path executable-path)
          (setq-local direnv--active-directory active-directory)
          (anvil-headless--strip-direnv-bookkeeping)
          nil)

        (defun anvil-headless--restore-immutable-direnv-baseline ()
          "Restore this buffer to the daemon's immutable login environment."
          (unless (and anvil-headless--baseline-process-environment
                       anvil-headless--baseline-exec-path)
            (error "Anvil baseline environment is unavailable"))
          (anvil-headless--restore-direnv-baseline
           (copy-sequence anvil-headless--baseline-process-environment)
           (copy-sequence anvil-headless--baseline-exec-path)
           nil))

        (defun anvil-headless--apply-direnv-if-allowed
            (directory &optional fail-on-export-error)
          "Apply DIRECTORY's envrc only while its pinned status remains allowed."
          (let (committed)
            (unwind-protect
                (condition-case nil
                    (if (not (anvil-headless--direnv-allowed-p
                              directory fail-on-export-error))
                        nil
                      (let ((inhibit-message t)
                            (message-log-max nil)
                            (direnv-always-show-summary nil))
                        (direnv-update-directory-environment directory))
                      ;; Close the allow-hash race.  No project environment is
                      ;; committed until the second pinned status succeeds.
                      (if (anvil-headless--direnv-allowed-p
                           directory fail-on-export-error)
                          (progn
                            (setq committed t)
                            t)
                        (when fail-on-export-error
                          (error
                           "Allowed direnv environment changed during export"))
                        nil))
                  (error
                   (when fail-on-export-error
                     (error "Allowed direnv environment failed to load"))
                   nil))
              ;; The initial status, export, and final status form one transaction.
              ;; Error, quit, and tagged exits all restore the immutable baseline
              ;; while the original nonlocal exit remains in flight.
              (unless committed
                (anvil-headless--restore-immutable-direnv-baseline)))))

        (defun anvil-headless--retain-active-direnv-if-allowed (directory)
          "Keep the active env for DIRECTORY only after a fresh allowed status."
          (let (verified)
            (unwind-protect
                (when (anvil-headless--direnv-allowed-p directory)
                  (setq verified t))
              (unless verified
                (anvil-headless--restore-immutable-direnv-baseline)))
            verified))

        (defun anvil-headless--direnv-update-current-buffer ()
          "Keep only a freshly verified local direnv environment in this buffer."
          (unless (and anvil-headless--baseline-process-environment
                       anvil-headless--baseline-exec-path)
            (error "Anvil baseline environment is unavailable"))
          (let (committed)
            (unwind-protect
                (let ((directory (direnv--directory)))
                  (when (and directory (not (file-remote-p directory)))
                    ;; Darwin exposes the same path through /tmp and /private/tmp.
                    ;; Canonicalize before comparing with direnv's retained state
                    ;; so repeated visit hooks do not export the envrc twice.
                    (setq directory
                          (anvil-headless--canonical-direnv-directory directory))
                    (unless (local-variable-p 'process-environment)
                      (setq-local process-environment
                                  (copy-sequence
                                   anvil-headless--baseline-process-environment)))
                    (unless (local-variable-p 'exec-path)
                      (setq-local exec-path
                                  (copy-sequence
                                   anvil-headless--baseline-exec-path)))
                    (unless (local-variable-p 'direnv--active-directory)
                      (setq-local direnv--active-directory nil))
                    (when
                        (if (equal direnv--active-directory directory)
                            ;; Recheck an already-loaded buffer: a newly blocked
                            ;; envrc or nonlocal status exit loses project state.
                            (anvil-headless--retain-active-direnv-if-allowed
                             directory)
                          (anvil-headless--apply-direnv-if-allowed directory))
                      (setq committed t))))
              ;; Missing/remote discovery and every nonlocal exit fail closed.
              (unless committed
                (anvil-headless--restore-immutable-direnv-baseline)))
            committed))

        (defun anvil-headless--direnv-update-before-mode-hook ()
          "Prepare the project environment before the real major-mode hook."
          ;; `normal-mode' first runs this hook in a provisional
          ;; `fundamental-mode', then discards every buffer-local value before
          ;; selecting the file's real mode.  Export only for that real mode;
          ;; genuinely fundamental files are refreshed by the visit hooks below.
          (unless (eq major-mode 'fundamental-mode)
            (anvil-headless--direnv-update-current-buffer)))

        ;; `change-major-mode-after-body-hook' runs before the mode's own hook,
        ;; so Eglot, Flycheck, and similar mode-hook clients see the project env.
        ;; Refresh again before file-local variables and after visiting as guards
        ;; against modes that change `default-directory'.
        (add-hook 'change-major-mode-after-body-hook
                  #'anvil-headless--direnv-update-before-mode-hook)
        (add-hook 'before-hack-local-variables-hook
                  #'anvil-headless--direnv-update-current-buffer)
        (add-hook 'find-file-hook
                  #'anvil-headless--direnv-update-current-buffer)

        (defun anvil-headless--direnv-around-host-run
            (original command coding cwd timeout &optional max-output)
          "Run ORIGINAL with a baseline-derived, allowed child environment."
          (unless (and anvil-headless--baseline-process-environment
                       anvil-headless--baseline-exec-path)
            (error "Anvil baseline environment is unavailable"))
          (let ((effective-cwd (or cwd default-directory))
                (real-shell anvil-headless--baseline-shell-file-name)
                (child-process-environment
                 (copy-sequence
                  anvil-headless--baseline-process-environment))
                (child-exec-path
                 (copy-sequence anvil-headless--baseline-exec-path)))
            (when (and effective-cwd
                       (not (file-remote-p effective-cwd))
                       (file-directory-p (expand-file-name effective-cwd)))
              (with-temp-buffer
                (setq default-directory
                      (file-name-as-directory
                       (file-truename (expand-file-name effective-cwd))))
                (setq-local process-environment child-process-environment)
                (setq-local exec-path child-exec-path)
                (setq-local direnv--active-directory nil)
                (anvil-headless--apply-direnv-if-allowed default-directory t)
                (anvil-headless--restore-required-exec-path)
                (setq child-process-environment
                      (copy-sequence process-environment)
                      child-exec-path (copy-sequence exec-path))))
            ;; Inject guard controls after direnv so an envrc cannot spoof them.
            (setq child-process-environment
                  (anvil-headless--environment-with
                   child-process-environment
                   "ANVIL_HEADLESS_PARENT_PID"
                   (number-to-string (emacs-pid))))
            (setq child-process-environment
                  (anvil-headless--environment-with
                   child-process-environment
                   "ANVIL_HEADLESS_REAL_SHELL" real-shell))
            (setq child-process-environment
                  (anvil-headless--environment-with
                   child-process-environment
                   "ANVIL_EMACS_SOCKET" anvil-headless--root-socket))
            ;; These special variables remain dynamically visible while ORIGINAL
            ;; waits, but the anvil-host implementation applies them only inside
            ;; make-process.  Root callbacks keep their baseline environment.
            (let ((anvil-host-child-process-environment
                   child-process-environment)
                  (anvil-host-child-exec-path child-exec-path)
                  (anvil-host-child-shell-file-name
                   "${dedicatedChildShell}/bin/anvil-headless-child-shell")
                  (anvil-host-child-shell-command-switch
                   anvil-headless--baseline-shell-command-switch))
              (funcall original command coding cwd timeout max-output))))

        (with-eval-after-load 'anvil-host
          (advice-add 'anvil-host--run
                      :around #'anvil-headless--direnv-around-host-run))
  '';

  dedicatedWorkerInit = writeText "anvil-headless-worker-init.el" ''
    ;;; anvil-headless-worker-init.el --- Isolated Anvil worker -*- lexical-binding: t; -*-

    (defvar anvil-server-schema-cache-file)
    (declare-function anvil-headless--snapshot-baseline-environment nil ())

    (let* ((expected-worker-names '${workerNamesElisp})
           (runtime-root (getenv "XDG_RUNTIME_DIR"))
           (state-root (getenv "ANVIL_EMACS_STATE_DIR"))
           (worker-name (format "%s" (or (daemonp) "worker")))
           (state-dir
            (and state-root
                 (expand-file-name
                  (concat "workers/" worker-name "/") state-root)))
           (temp-dir
            (and runtime-root
                 (expand-file-name
                  (concat "workers/" worker-name "/tmp/") runtime-root)))
           (cache-dir
            (and state-dir (expand-file-name "cache/" state-dir))))
      (unless (member worker-name expected-worker-names)
        (error "Unexpected Anvil worker daemon name: %s" worker-name))
      (unless (and state-dir temp-dir)
        (error "Anvil workers require state and runtime directories"))
      (make-directory temp-dir t)
      (make-directory cache-dir t)
      (setenv "TMPDIR" temp-dir)
      (setenv "TMP" temp-dir)
      (setenv "TEMP" temp-dir)
      (setenv "XDG_CACHE_HOME" cache-dir)
      (setq native-comp-jit-compilation nil
            user-emacs-directory (file-name-as-directory state-dir)
            package-user-dir (expand-file-name "elpa" state-dir)
            custom-file (expand-file-name "custom.el" state-dir)
            temporary-file-directory (file-name-as-directory temp-dir)
            anvil-server-schema-cache-file
            (expand-file-name "anvil-schema-cache.el" temp-dir))
      (when (fboundp 'startup-redirect-eln-cache)
        (startup-redirect-eln-cache
         (expand-file-name "eln-cache/" state-dir))))

    (load "${dedicatedEnvironmentInit}" nil nil t)
    (anvil-headless--snapshot-baseline-environment)
    (add-to-list 'load-path "${dedicatedAnvil}/share/emacs/site-lisp")
    (add-to-list 'load-path "${dedicatedAnvilIde}/share/emacs/site-lisp")
    (require 'anvil-server)
    (require 'anvil-server-commands)

    (defun anvil-headless-worker--eval (expression)
      "Evaluate EXPRESSION in this isolated Anvil worker.

    MCP Parameters:
      expression - Emacs Lisp expression as a string"
      (anvil-server-with-error-handling
        (let ((result (eval (read expression) t)))
          (format "%S" result))))

    (anvil-server-register-tool #'anvil-headless-worker--eval
      :id "eval"
      :description "Evaluate Emacs Lisp on the isolated Anvil worker"
      :server-id "worker")
    (anvil-server-start)
    (with-temp-file (expand-file-name "worker.pid" user-emacs-directory)
      (insert (number-to-string (emacs-pid)) "\n"))
  '';

  dedicatedOffloadInit = writeText "anvil-headless-offload-init.el" ''
    ;;; anvil-headless-offload-init.el --- One-shot async child -*- lexical-binding: t; -*-

    (declare-function anvil-headless--snapshot-baseline-environment nil ())

    (let* ((runtime-root (getenv "XDG_RUNTIME_DIR"))
           (state-root (getenv "ANVIL_EMACS_STATE_DIR"))
           (state-dir
            (and state-root (expand-file-name "offload/" state-root)))
           (temp-dir
            (and runtime-root (expand-file-name "tmp/" runtime-root))))
      (unless (and state-dir temp-dir
                   (file-directory-p state-dir)
                   (file-directory-p temp-dir))
        (error "Anvil offload requires private state and runtime directories"))
      (setq native-comp-jit-compilation nil
            user-emacs-directory (file-name-as-directory state-dir)
            package-user-dir (expand-file-name "elpa" state-dir)
            custom-file (expand-file-name "custom.el" state-dir)
            temporary-file-directory (file-name-as-directory temp-dir))
      (when (fboundp 'startup-redirect-eln-cache)
        (startup-redirect-eln-cache
         (expand-file-name "eln-cache/" state-dir))))

    ;; Avoid a second login-shell import.  The root passes its immutable
    ;; already-imported baseline, while each request carries project context
    ;; separately and binds it only around the submitted form.
    (setenv "ANVIL_EMACS_WORKER" "1")
    (load "${dedicatedEnvironmentInit}" nil nil t)
    (anvil-headless--snapshot-baseline-environment)
  '';

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

  dedicatedLockLauncher = writeText "anvil-lock-launcher.py" ''
    import ctypes
    import errno
    import fcntl
    import json
    import math
    import os
    import re
    import secrets
    import signal
    import socket
    import stat
    import sys
    import time

    EXIT_SOFTWARE = 70
    EXIT_CONFIG = 77
    LOCK_NAME = ".anvil-headless-emacs.lock"
    PULSE_NAME = ".anvil-root-pulse"
    LEASE_NAME = ".anvil-root-async-lease"
    ACTIVITY_NAME = ".anvil-root-activity.sock"
    UNIX_SOCKET_PATH_BYTES = 103 if sys.platform == "darwin" else 107
    ACTIVITY_MAX_BYTES = 1024
    EVENT_MAX_BYTES = 512
    RUN_ID_PATTERN = re.compile(r"[0-9a-f]{32}")
    TOOL_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,127}")
    ACTIVITY_PHASES = frozenset((
        "startup",
        "parse",
        "dispatch",
        "tool-call",
        "result-encode",
        "response-write",
        "idle",
    ))
    ACTIVITY_METHODS = frozenset((
        "none",
        "initialize",
        "notifications/initialized",
        "ping",
        "tools/list",
        "tools/call",
        "resources/list",
        "resources/read",
        "resources/templates/list",
        "other",
    ))
    WATCHDOG_CAUSES = frozenset((
        "startup-timeout",
        "heartbeat-timeout",
        "dispatch-timeout",
        "lock-integrity-failure",
        "monitor-state-invalid",
        "durable-refresh-failure",
        "monitor-internal-error",
    ))
    ACTIVITY_KEYS = frozenset((
        "schema_version",
        "run_id",
        "daemon_pid",
        "sequence",
        "phase",
        "method",
        "tool",
        "phase_started_unix_ms",
        "observed_at_unix_ms",
    ))
    EVENT_KEYS = frozenset((
        "schema_version",
        "run_id",
        "daemon_pid",
        "cause",
        "phase",
        "method",
        "tool",
        "observed_at_unix_ms",
        "daemon_uptime_ms",
        "heartbeat_age_ms",
        "heartbeat_limit_ms",
        "dispatch_age_ms",
        "dispatch_limit_ms",
    ))
    DEFAULT_REFRESH_SECONDS = 6 * 60 * 60
    DEFAULT_STARTUP_SECONDS = ${toString timeoutPolicy.watchdogStartupSeconds}
    DEFAULT_NORMAL_SECONDS = ${toString timeoutPolicy.watchdogHeartbeatSeconds}
    DEFAULT_DISPATCH_SECONDS = ${toString timeoutPolicy.watchdogDispatchSeconds}
    DEFAULT_PULSE_SECONDS = ${toString timeoutPolicy.watchdogPulseSeconds}


    def fail(message, status=EXIT_SOFTWARE):
        print(f"anvil-mcp: {message}", file=sys.stderr)
        raise SystemExit(status)


    def ofd_lock_bytes():
        if sys.platform == "darwin":
            class Flock(ctypes.Structure):
                _fields_ = [
                    ("l_start", ctypes.c_longlong),
                    ("l_len", ctypes.c_longlong),
                    ("l_pid", ctypes.c_int),
                    ("l_type", ctypes.c_short),
                    ("l_whence", ctypes.c_short),
                ]

            command = getattr(fcntl, "F_OFD_SETLK", 90)
        elif sys.platform.startswith("linux"):
            class Flock(ctypes.Structure):
                _fields_ = [
                    ("l_type", ctypes.c_short),
                    ("l_whence", ctypes.c_short),
                    ("l_start", ctypes.c_longlong),
                    ("l_len", ctypes.c_longlong),
                    ("l_pid", ctypes.c_int),
                ]

            command = getattr(fcntl, "F_OFD_SETLK", 37)
        else:
            fail(f"open-file-description locks unsupported on {sys.platform}")

        lock = Flock()
        lock.l_type = fcntl.F_WRLCK
        lock.l_whence = os.SEEK_SET
        return command, bytes(lock)


    def acquire_lock(directory, target_fd, kind, conflict_status):
        lock_path = os.path.join(directory, LOCK_NAME)
        if not hasattr(os, "O_NOFOLLOW"):
            fail("this platform lacks O_NOFOLLOW", EXIT_CONFIG)
        flags = os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW
        try:
            source_fd = os.open(lock_path, flags, 0o600)
        except OSError as error:
            fail(f"cannot open {kind} lock file {lock_path}: {error}", EXIT_CONFIG)

        try:
            info = os.fstat(source_fd)
            if not stat.S_ISREG(info.st_mode):
                os.close(source_fd)
                fail(f"{kind} lock must be a regular file: {lock_path}", EXIT_CONFIG)
            if info.st_uid != os.getuid():
                os.close(source_fd)
                fail(
                    f"{kind} lock must be owned by uid {os.getuid()}: {lock_path}",
                    EXIT_CONFIG,
                )
            os.fchmod(source_fd, 0o600)
            if source_fd == target_fd:
                os.set_inheritable(target_fd, True)
            else:
                os.dup2(source_fd, target_fd, inheritable=True)
                os.close(source_fd)
        except OSError as error:
            fail(f"cannot prepare {kind} lock file {lock_path}: {error}")

        command, lock_data = ofd_lock_bytes()
        try:
            fcntl.fcntl(target_fd, command, lock_data)
        except OSError as error:
            if error.errno in (errno.EACCES, errno.EAGAIN):
                fail(
                    f"another dedicated daemon holds the {kind} lock: {directory}",
                    conflict_status,
                )
            fail(f"cannot acquire {kind} lock {lock_path}: {error}")
        return lock_path, (info.st_dev, info.st_ino)


    def positive_seconds(name, default):
        raw = os.environ.get(name, str(default))
        try:
            value = float(raw)
        except ValueError:
            fail(f"{name} must be numeric", EXIT_CONFIG)
        if not math.isfinite(value) or value <= 0:
            fail(f"{name} must be positive and finite", EXIT_CONFIG)
        return value


    def strict_json_object(raw):
        """Decode one strict UTF-8 JSON object without duplicate keys."""
        if isinstance(raw, bytes):
            text = raw.decode("utf-8", errors="strict")
        elif isinstance(raw, str):
            text = raw
        else:
            raise ValueError("JSON frame must be bytes or text")

        def reject_constant(value):
            raise ValueError(f"non-finite JSON constant: {value}")

        def unique_object(pairs):
            result = {}
            for key, value in pairs:
                if key in result:
                    raise ValueError(f"duplicate JSON key: {key}")
                result[key] = value
            return result

        value = json.loads(
            text,
            object_pairs_hook=unique_object,
            parse_constant=reject_constant,
        )
        if not isinstance(value, dict):
            raise ValueError("JSON frame must be an object")
        return value


    def canonical_json_line(value):
        return (
            json.dumps(
                value,
                ensure_ascii=False,
                allow_nan=False,
                sort_keys=True,
                separators=(",", ":"),
            )
            + "\n"
        ).encode("utf-8", errors="strict")


    def frame_object(value, maximum_bytes):
        if isinstance(value, (bytes, str)):
            encoded = value if isinstance(value, bytes) else value.encode("utf-8")
            if len(encoded) > maximum_bytes:
                raise ValueError("JSON frame exceeds byte ceiling")
            if encoded.endswith(b"\n"):
                encoded = encoded[:-1]
            if b"\n" in encoded or b"\r" in encoded:
                raise ValueError("JSON frame contains an embedded newline")
            value = strict_json_object(encoded)
        elif not isinstance(value, dict):
            raise ValueError("JSON frame must be an object")
        if len(canonical_json_line(value)) > maximum_bytes:
            raise ValueError("JSON frame exceeds byte ceiling")
        return value


    def exact_nonnegative_integer(value, field, positive=False):
        if isinstance(value, bool) or not isinstance(value, int):
            raise ValueError(f"{field} must be an integer")
        if value < (1 if positive else 0):
            raise ValueError(f"{field} is out of range")
        return value


    def validate_run_id(value):
        if not isinstance(value, str) or RUN_ID_PATTERN.fullmatch(value) is None:
            raise ValueError("run_id must be 32 lowercase hexadecimal characters")
        return value


    def validate_tool(value):
        if value is not None and (
            not isinstance(value, str) or TOOL_PATTERN.fullmatch(value) is None
        ):
            raise ValueError("tool is not telemetry-safe")
        return value


    def validate_activity(value, expected_run_id, expected_pid, last_sequence):
        value = frame_object(value, ACTIVITY_MAX_BYTES)
        if set(value) != ACTIVITY_KEYS:
            raise ValueError("activity frame has the wrong key set")
        if type(value["schema_version"]) is not int or value["schema_version"] != 1:
            raise ValueError("unsupported activity schema")
        validate_run_id(value["run_id"])
        if value["run_id"] != expected_run_id:
            raise ValueError("activity run_id mismatch")
        exact_nonnegative_integer(value["daemon_pid"], "daemon_pid", True)
        if value["daemon_pid"] != expected_pid:
            raise ValueError("activity daemon_pid mismatch")
        exact_nonnegative_integer(value["sequence"], "sequence")
        if value["sequence"] <= last_sequence:
            raise ValueError("activity sequence did not advance")
        if not isinstance(value["phase"], str) or value["phase"] not in ACTIVITY_PHASES:
            raise ValueError("invalid activity phase")
        if not isinstance(value["method"], str) or value["method"] not in ACTIVITY_METHODS:
            raise ValueError("invalid activity method")
        validate_tool(value["tool"])
        exact_nonnegative_integer(
            value["phase_started_unix_ms"], "phase_started_unix_ms"
        )
        exact_nonnegative_integer(
            value["observed_at_unix_ms"], "observed_at_unix_ms"
        )
        return value


    def validate_watchdog_event(value, expected_run_id, expected_pid):
        value = frame_object(value, EVENT_MAX_BYTES)
        if set(value) != EVENT_KEYS:
            raise ValueError("watchdog event has the wrong key set")
        if type(value["schema_version"]) is not int or value["schema_version"] != 1:
            raise ValueError("unsupported watchdog event schema")
        validate_run_id(value["run_id"])
        if value["run_id"] != expected_run_id:
            raise ValueError("watchdog event run_id mismatch")
        exact_nonnegative_integer(value["daemon_pid"], "daemon_pid", True)
        if value["daemon_pid"] != expected_pid:
            raise ValueError("watchdog event daemon_pid mismatch")
        if not isinstance(value["cause"], str) or value["cause"] not in WATCHDOG_CAUSES:
            raise ValueError("invalid watchdog cause")
        if not isinstance(value["phase"], str) or value["phase"] not in ACTIVITY_PHASES | {"unknown"}:
            raise ValueError("invalid watchdog phase")
        if not isinstance(value["method"], str) or value["method"] not in ACTIVITY_METHODS:
            raise ValueError("invalid watchdog method")
        validate_tool(value["tool"])
        for field in ("observed_at_unix_ms", "daemon_uptime_ms"):
            exact_nonnegative_integer(value[field], field)
        for age_field, limit_field in (
            ("heartbeat_age_ms", "heartbeat_limit_ms"),
            ("dispatch_age_ms", "dispatch_limit_ms"),
        ):
            age = value[age_field]
            limit = value[limit_field]
            if (age is None) != (limit is None):
                raise ValueError(
                    f"{age_field} and {limit_field} must have matching nullness"
                )
            if age is not None:
                exact_nonnegative_integer(age, age_field)
                exact_nonnegative_integer(limit, limit_field)
        return value


    def select_deadline_cause(
        now,
        heartbeat_anchor,
        heartbeat_limit,
        dispatch_anchor,
        dispatch_limit,
    ):
        deadlines = []
        if heartbeat_anchor is not None:
            deadline = heartbeat_anchor + heartbeat_limit
            if now >= deadline:
                deadlines.append((deadline, "heartbeat-timeout"))
        if dispatch_anchor is not None:
            deadline = dispatch_anchor + dispatch_limit
            if now >= deadline:
                deadlines.append((deadline, "dispatch-timeout"))
        if not deadlines:
            return None
        return min(deadlines, key=lambda item: item[0])[1]


    def write_watchdog_event(descriptor, event):
        """Best-effort one atomic nonblocking write of EVENT."""
        try:
            if os.fpathconf(descriptor, "PC_PIPE_BUF") < EVENT_MAX_BYTES:
                return False
            candidate = dict(event)
            payload = canonical_json_line(candidate)
            if len(payload) > EVENT_MAX_BYTES and candidate.get("tool") is not None:
                candidate["tool"] = None
                payload = canonical_json_line(candidate)
            validate_watchdog_event(
                candidate,
                candidate.get("run_id"),
                candidate.get("daemon_pid"),
            )
            if len(payload) > EVENT_MAX_BYTES:
                return False
            return os.write(descriptor, payload) == len(payload)
        except BaseException:
            return False


    def validate_event_descriptor(descriptor):
        if isinstance(descriptor, bool) or not isinstance(descriptor, int):
            fail("watchdog event descriptor must be an integer", EXIT_CONFIG)
        if descriptor <= 9:
            fail("watchdog event descriptor must be above 9", EXIT_CONFIG)
        try:
            info = os.fstat(descriptor)
            flags = fcntl.fcntl(descriptor, fcntl.F_GETFL)
            pipe_buf = os.fpathconf(descriptor, "PC_PIPE_BUF")
        except OSError as error:
            fail(f"invalid watchdog event descriptor: {error}", EXIT_CONFIG)
        if not stat.S_ISFIFO(info.st_mode):
            fail("watchdog event descriptor is not a pipe", EXIT_CONFIG)
        if flags & os.O_ACCMODE != os.O_WRONLY:
            fail("watchdog event descriptor is not write-only", EXIT_CONFIG)
        if not flags & os.O_NONBLOCK:
            fail("watchdog event descriptor is blocking", EXIT_CONFIG)
        if pipe_buf < EVENT_MAX_BYTES:
            fail("watchdog event pipe has insufficient atomic capacity", EXIT_CONFIG)
        return descriptor


    def private_nonblocking_pipe():
        read_descriptor = None
        write_descriptor = None
        high_descriptor = None
        try:
            read_descriptor, write_descriptor = os.pipe()
            high_descriptor = fcntl.fcntl(write_descriptor, fcntl.F_DUPFD, 10)
            os.close(write_descriptor)
            write_descriptor = None
            os.set_blocking(read_descriptor, False)
            os.set_blocking(high_descriptor, False)
            return read_descriptor, high_descriptor
        except BaseException:
            for descriptor in (read_descriptor, write_descriptor, high_descriptor):
                if descriptor is not None:
                    try:
                        os.close(descriptor)
                    except OSError:
                        pass
            raise


    def configure_watchdog_capabilities(environment):
        marker_name = "ANVIL_EMACS_WATCHDOG_SUPERVISED"
        descriptor_name = "ANVIL_EMACS_WATCHDOG_EVENT_FD"
        run_name = "ANVIL_EMACS_WATCHDOG_RUN_ID"
        present = tuple(name in environment for name in (
            marker_name,
            descriptor_name,
            run_name,
        ))
        if present == (False, False, False):
            try:
                discard_descriptor, event_descriptor = private_nonblocking_pipe()
            except BaseException as error:
                fail(f"cannot create compatibility watchdog pipe: {error}")
            run_id = secrets.token_hex(16)
            environment[run_name] = run_id
            return {
                "supervised": False,
                "run_id": run_id,
                "event_fd": event_descriptor,
                "discard_fd": discard_descriptor,
            }
        if present != (True, True, True) or environment.get(marker_name) != "1":
            fail("incomplete watchdog supervisor capabilities", EXIT_CONFIG)
        run_id = environment[run_name]
        try:
            validate_run_id(run_id)
        except ValueError as error:
            fail(str(error), EXIT_CONFIG)
        raw_descriptor = environment[descriptor_name]
        if not raw_descriptor.isascii() or not raw_descriptor.isdecimal():
            fail("watchdog event descriptor must be decimal", EXIT_CONFIG)
        event_descriptor = validate_event_descriptor(int(raw_descriptor))
        environment.pop(marker_name, None)
        environment.pop(descriptor_name, None)
        return {
            "supervised": True,
            "run_id": run_id,
            "event_fd": event_descriptor,
            "discard_fd": None,
        }


    def validate_activity_socket_path(runtime_dir):
        path = os.path.join(runtime_dir, ACTIVITY_NAME)
        if not os.path.isabs(runtime_dir) or os.path.normpath(runtime_dir) != runtime_dir:
            fail("watchdog runtime directory must be absolute and normalized", EXIT_CONFIG)
        encoded = os.fsencode(path)
        if len(encoded) > UNIX_SOCKET_PATH_BYTES:
            fail(
                "watchdog activity socket exceeds the platform Unix socket limit",
                EXIT_CONFIG,
            )
        return path


    def open_activity_directory(path):
        directory = os.path.dirname(path)
        descriptor = os.open(
            directory,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
        info = os.fstat(descriptor)
        if (
            not stat.S_ISDIR(info.st_mode)
            or info.st_uid != os.getuid()
            or stat.S_IMODE(info.st_mode) != 0o700
        ):
            os.close(descriptor)
            raise OSError(errno.EPERM, "unsafe activity socket directory")
        return descriptor, os.path.basename(path)


    def activity_entry_identity(directory_fd, name):
        info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        if (
            not stat.S_ISSOCK(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_nlink != 1
            or stat.S_IMODE(info.st_mode) != 0o600
        ):
            raise OSError(errno.EPERM, "unsafe activity socket entry")
        return info.st_dev, info.st_ino


    def safe_unlink_activity(path, expected_identity):
        directory_fd = None
        try:
            directory_fd, name = open_activity_directory(path)
            try:
                identity = activity_entry_identity(directory_fd, name)
            except FileNotFoundError:
                return True
            if identity != tuple(expected_identity):
                return False
            os.unlink(name, dir_fd=directory_fd)
            return True
        except OSError:
            return False
        finally:
            if directory_fd is not None:
                os.close(directory_fd)


    def prepare_activity_listener(runtime_dir):
        path = validate_activity_socket_path(runtime_dir)
        directory_fd = None
        listener = None
        identity = None
        try:
            directory_fd, name = open_activity_directory(path)
            try:
                stale_identity = activity_entry_identity(directory_fd, name)
            except FileNotFoundError:
                stale_identity = None
            if stale_identity is not None:
                os.unlink(name, dir_fd=directory_fd)

            listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            listener.setblocking(False)
            listener.bind(path)
            os.chmod(path, 0o600, follow_symlinks=False)
            identity = activity_entry_identity(directory_fd, name)
            listener.listen(1)
            return listener, (path, identity)
        except BaseException:
            if listener is not None:
                listener.close()
            if identity is not None:
                safe_unlink_activity(path, identity)
            fail("cannot prepare watchdog activity socket", EXIT_CONFIG)
        finally:
            if directory_fd is not None:
                os.close(directory_fd)


    def accept_activity_connection(listener, activity_entry):
        try:
            connection, _address = listener.accept()
        except BlockingIOError:
            return None
        connection.setblocking(False)
        if not safe_unlink_activity(activity_entry[0], activity_entry[1]):
            connection.close()
            raise RuntimeError("watchdog activity socket identity changed")
        listener.close()
        return connection


    def drain_activity_connection(
        connection,
        pending,
        expected_run_id,
        expected_pid,
        last_sequence,
        activity,
    ):
        if connection is None:
            return None, b"", activity, last_sequence
        buffer = pending
        budget = 4096
        try:
            while budget > 0:
                try:
                    chunk = connection.recv(min(4096, budget))
                except BlockingIOError:
                    break
                if not chunk:
                    connection.close()
                    return None, b"", activity, last_sequence
                budget -= len(chunk)
                buffer += chunk
                while b"\n" in buffer:
                    frame, buffer = buffer.split(b"\n", 1)
                    if len(frame) + 1 > ACTIVITY_MAX_BYTES:
                        raise ValueError("activity frame exceeds byte ceiling")
                    candidate = validate_activity(
                        frame,
                        expected_run_id,
                        expected_pid,
                        last_sequence,
                    )
                    activity = candidate
                    last_sequence = candidate["sequence"]
                if len(buffer) > ACTIVITY_MAX_BYTES:
                    raise ValueError("activity partial frame exceeds byte ceiling")
        except (OSError, UnicodeError, ValueError, json.JSONDecodeError):
            connection.close()
            return None, b"", activity, last_sequence
        return connection, buffer, activity, last_sequence


    def file_generation(info):
        return info.st_mtime_ns, info.st_ctime_ns


    def compensate_scheduler_gap(
        now,
        last_poll,
        poll_seconds,
        started,
        last_progress,
        dispatch_started,
    ):
        elapsed_since_poll = now - last_poll
        if elapsed_since_poll <= 3.0 * poll_seconds:
            return started, last_progress, dispatch_started
        unexpected_gap = max(0.0, elapsed_since_poll - poll_seconds)
        return tuple(
            None if anchor is None else anchor + unexpected_gap
            for anchor in (started, last_progress, dispatch_started)
        )


    def deadline_expired(now, anchor, seconds):
        return anchor is not None and now - anchor >= seconds


    def open_monitor_file(directory, name, initial, mode):
        path = os.path.join(directory, name)
        directory_fd = None
        descriptor = None
        try:
            directory_fd = os.open(
                directory,
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
            )
            directory_info = os.fstat(directory_fd)
            if (
                not stat.S_ISDIR(directory_info.st_mode)
                or directory_info.st_uid != os.getuid()
                or stat.S_IMODE(directory_info.st_mode) != 0o700
            ):
                raise OSError(errno.EPERM, "unsafe monitor directory")

            try:
                stale_info = os.stat(
                    name,
                    dir_fd=directory_fd,
                    follow_symlinks=False,
                )
            except FileNotFoundError:
                pass
            else:
                if (
                    not stat.S_ISREG(stale_info.st_mode)
                    or stale_info.st_uid != os.getuid()
                    or stale_info.st_nlink != 1
                ):
                    raise OSError(errno.EPERM, "unsafe stale monitor file")
                try:
                    os.unlink(name, dir_fd=directory_fd)
                except FileNotFoundError:
                    pass

            descriptor = os.open(
                name,
                os.O_RDWR
                | os.O_CREAT
                | os.O_EXCL
                | os.O_NOFOLLOW,
                mode,
                dir_fd=directory_fd,
            )
            info = os.fstat(descriptor)
            path_info = os.stat(
                name,
                dir_fd=directory_fd,
                follow_symlinks=False,
            )
            if (
                not stat.S_ISREG(info.st_mode)
                or info.st_uid != os.getuid()
                or info.st_nlink != 1
                or not stat.S_ISREG(path_info.st_mode)
                or path_info.st_uid != os.getuid()
                or path_info.st_nlink != 1
                or (path_info.st_dev, path_info.st_ino)
                != (info.st_dev, info.st_ino)
            ):
                raise OSError(errno.EPERM, "unsafe new monitor file")
            os.fchmod(descriptor, mode)
            written = os.write(descriptor, initial)
            if written != len(initial):
                raise OSError(errno.EIO, "short watchdog state write")
            os.fsync(descriptor)
            info = os.fstat(descriptor)
            os.set_inheritable(descriptor, False)
            return (
                path,
                descriptor,
                (info.st_dev, info.st_ino),
                file_generation(info),
            )
        except OSError as error:
            if descriptor is not None:
                try:
                    os.close(descriptor)
                except OSError:
                    pass
            fail(f"cannot prepare watchdog state {path}: {error}", EXIT_CONFIG)
        finally:
            if directory_fd is not None:
                try:
                    os.close(directory_fd)
                except OSError:
                    pass


    def validate_lock_files(lock_identities):
        for lock_path, expected in lock_identities:
            info = os.stat(lock_path, follow_symlinks=False)
            if (
                not stat.S_ISREG(info.st_mode)
                or info.st_uid != os.getuid()
                or (info.st_dev, info.st_ino) != expected
            ):
                raise RuntimeError(f"lock identity changed: {lock_path}")


    def monitor_file_info(entry):
        path, descriptor, expected, _initial = entry
        descriptor_info = os.fstat(descriptor)
        path_info = os.stat(path, follow_symlinks=False)
        if (
            not stat.S_ISREG(descriptor_info.st_mode)
            or descriptor_info.st_uid != os.getuid()
            or descriptor_info.st_nlink != 1
            or not stat.S_ISREG(path_info.st_mode)
            or path_info.st_uid != os.getuid()
            or (descriptor_info.st_dev, descriptor_info.st_ino) != expected
            or (path_info.st_dev, path_info.st_ino) != expected
        ):
            raise RuntimeError(f"watchdog identity changed: {path}")
        return descriptor_info


    def monitor_file_generation(entry):
        return file_generation(monitor_file_info(entry))


    def lease_state_from_info(info):
        mode = stat.S_IMODE(info.st_mode)
        if mode == 0o600:
            return "active"
        if mode == 0o400:
            return "idle"
        raise RuntimeError(f"invalid async lease mode: {mode:o}")


    def monitor_snapshot(pulse_entry, lease_entry):
        pulse_info = monitor_file_info(pulse_entry)
        lease_info = monitor_file_info(lease_entry)
        return (
            file_generation(pulse_info),
            file_generation(lease_info),
            lease_state_from_info(lease_info),
        )


    def close_monitor_descriptors(keep):
        candidates = None
        for descriptor_root in ("/dev/fd", "/proc/self/fd"):
            try:
                candidates = [
                    int(name)
                    for name in os.listdir(descriptor_root)
                    if name.isdecimal()
                ]
                break
            except OSError:
                continue
        if candidates is not None:
            for descriptor in candidates:
                if descriptor >= 3 and descriptor not in keep:
                    try:
                        os.close(descriptor)
                    except OSError as error:
                        if error.errno != errno.EBADF:
                            raise
            return

        try:
            descriptor_limit = int(os.sysconf("SC_OPEN_MAX"))
        except (OSError, TypeError, ValueError):
            descriptor_limit = 65536
        descriptor_limit = max(256, min(descriptor_limit, 65536))
        cursor = 3
        for descriptor in sorted(set(keep)):
            if descriptor < 3:
                continue
            os.closerange(cursor, min(descriptor, descriptor_limit))
            cursor = descriptor + 1
        if cursor < descriptor_limit:
            os.closerange(cursor, descriptor_limit)


    def refresh_durable_state(state_root):
        directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        entry_flags = (
            os.O_RDONLY
            | os.O_NOFOLLOW
            | getattr(os, "O_NONBLOCK", 0)
        )

        def open_owned_entry(directory_fd, name, expected, flags, display):
            try:
                descriptor = os.open(name, flags, dir_fd=directory_fd)
            except FileNotFoundError:
                return None
            except OSError as error:
                if error.errno in (errno.ELOOP, errno.ENOTDIR):
                    return None
                raise
            info = os.fstat(descriptor)
            if info.st_uid != os.getuid():
                os.close(descriptor)
                raise RuntimeError(f"durable state owner changed: {display}")
            if (info.st_dev, info.st_ino) != expected:
                # Volatile state such as a SQLite WAL may be recreated
                # between lstat and open.  The opened fd is still confined
                # by O_NOFOLLOW; skip the new generation until next refresh.
                os.close(descriptor)
                return None
            return descriptor

        def walk_directory(path, directory_fd):
            info = os.fstat(directory_fd)
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
                raise RuntimeError(f"unsafe durable state directory: {path}")
            os.utime(directory_fd)
            try:
                with os.scandir(directory_fd) as entries:
                    names = [entry.name for entry in entries]
            except FileNotFoundError:
                return

            for name in names:
                display = os.path.join(path, name)
                try:
                    info = os.stat(
                        name,
                        dir_fd=directory_fd,
                        follow_symlinks=False,
                    )
                except FileNotFoundError:
                    continue
                if stat.S_ISLNK(info.st_mode):
                    continue
                if info.st_uid != os.getuid():
                    raise RuntimeError(
                        f"durable state owner changed: {display}"
                    )
                expected = (info.st_dev, info.st_ino)
                if stat.S_ISDIR(info.st_mode):
                    child_fd = open_owned_entry(
                        directory_fd,
                        name,
                        expected,
                        directory_flags,
                        display,
                    )
                    if child_fd is None:
                        continue
                    try:
                        walk_directory(display, child_fd)
                    finally:
                        os.close(child_fd)
                elif stat.S_ISREG(info.st_mode):
                    child_fd = open_owned_entry(
                        directory_fd,
                        name,
                        expected,
                        entry_flags,
                        display,
                    )
                    if child_fd is None:
                        continue
                    try:
                        child_info = os.fstat(child_fd)
                        if stat.S_ISREG(child_info.st_mode):
                            os.utime(child_fd)
                    finally:
                        os.close(child_fd)

        try:
            root_fd = os.open(state_root, directory_flags)
        except FileNotFoundError:
            return
        try:
            walk_directory(state_root, root_fd)
        finally:
            os.close(root_fd)


    def build_watchdog_event(
        cause,
        run_id,
        parent_pid,
        monitor_started,
        now,
        activity,
        last_progress,
        normal_seconds,
        dispatch_started,
        dispatch_seconds,
    ):
        def elapsed_ms(anchor):
            if anchor is None:
                return None
            return max(0, int((now - anchor) * 1000))

        return {
            "schema_version": 1,
            "run_id": run_id,
            "daemon_pid": parent_pid,
            "cause": cause,
            "phase": activity.get("phase", "unknown"),
            "method": activity.get("method", "none"),
            "tool": activity.get("tool"),
            "observed_at_unix_ms": max(0, int(time.time() * 1000)),
            "daemon_uptime_ms": max(0, int((now - monitor_started) * 1000)),
            "heartbeat_age_ms": elapsed_ms(last_progress),
            "heartbeat_limit_ms": (
                int(normal_seconds * 1000) if last_progress is not None else None
            ),
            "dispatch_age_ms": elapsed_ms(dispatch_started),
            "dispatch_limit_ms": (
                int(dispatch_seconds * 1000)
                if dispatch_started is not None
                else None
            ),
        }


    def kill_parent_if(
        parent_pid,
        verifier,
        event_descriptor,
        event_factory,
        activity_entry,
    ):
        if os.getppid() != parent_pid:
            os._exit(0)
        try:
            still_failed = verifier()
        except BaseException:
            still_failed = True
        if not still_failed:
            return False
        if os.getppid() != parent_pid:
            os._exit(0)
        try:
            safe_unlink_activity(activity_entry[0], activity_entry[1])
        except BaseException:
            pass
        try:
            write_watchdog_event(event_descriptor, event_factory())
        except BaseException:
            pass
        try:
            os.kill(parent_pid, signal.SIGKILL)
        except OSError:
            pass
        os._exit(0)


    def monitor(
        parent_pid,
        lock_identities,
        state_root,
        pulse_entry,
        lease_entry,
        event_descriptor,
        discard_descriptor,
        run_id,
        activity_listener,
        activity_entry,
        refresh_seconds,
        pulse_seconds,
        startup_seconds,
        normal_seconds,
        dispatch_seconds,
    ):
        poll_seconds = min(0.5, max(0.05, pulse_seconds / 2.0))
        monitor_started = time.monotonic()
        started = monitor_started
        last_poll = started
        last_progress = None
        dispatch_started = None
        armed = False
        pulse_generation = None
        lease_generation = None
        lease_state = None
        next_refresh = 0.0
        activity_connection = None
        activity_pending = b""
        activity_sequence = 0
        observed_at_unix_ms = max(0, int(time.time() * 1000))
        activity = {
            "schema_version": 1,
            "run_id": run_id,
            "daemon_pid": parent_pid,
            "sequence": 0,
            "phase": "startup",
            "method": "none",
            "tool": None,
            "phase_started_unix_ms": observed_at_unix_ms,
            "observed_at_unix_ms": observed_at_unix_ms,
        }

        def kill_for(cause, verifier):
            def event_factory():
                return build_watchdog_event(
                    cause,
                    run_id,
                    parent_pid,
                    monitor_started,
                    time.monotonic(),
                    activity,
                    last_progress,
                    normal_seconds,
                    dispatch_started,
                    dispatch_seconds,
                )

            return kill_parent_if(
                parent_pid,
                verifier,
                event_descriptor,
                event_factory,
                activity_entry,
            )

        try:
            signal.signal(signal.SIGPIPE, signal.SIG_IGN)
            null_fd = os.open(os.devnull, os.O_RDWR)
            for target in (0, 1, 2):
                os.dup2(null_fd, target)
            if null_fd > 2:
                os.close(null_fd)
            kept_descriptors = {
                pulse_entry[1],
                lease_entry[1],
                event_descriptor,
                activity_listener.fileno(),
            }
            if discard_descriptor is not None:
                kept_descriptors.add(discard_descriptor)
            close_monitor_descriptors(kept_descriptors)

            while os.getppid() == parent_pid:
                now = time.monotonic()
                (
                    started,
                    last_progress,
                    dispatch_started,
                ) = compensate_scheduler_gap(
                    now,
                    last_poll,
                    poll_seconds,
                    started,
                    last_progress,
                    dispatch_started,
                )
                last_poll = now

                if activity_connection is None and activity_listener is not None:
                    activity_connection = accept_activity_connection(
                        activity_listener,
                        activity_entry,
                    )
                    if activity_connection is not None:
                        activity_listener = None
                if activity_connection is not None:
                    (
                        activity_connection,
                        activity_pending,
                        activity,
                        activity_sequence,
                    ) = drain_activity_connection(
                        activity_connection,
                        activity_pending,
                        run_id,
                        parent_pid,
                        activity_sequence,
                        activity,
                    )

                try:
                    validate_lock_files(lock_identities)
                except BaseException:
                    def lock_still_broken():
                        validate_lock_files(lock_identities)
                        return False

                    kill_for("lock-integrity-failure", lock_still_broken)
                    continue

                try:
                    (
                        current_pulse,
                        current_lease,
                        current_lease_state,
                    ) = monitor_snapshot(pulse_entry, lease_entry)
                except BaseException:
                    def monitor_state_still_broken():
                        monitor_snapshot(pulse_entry, lease_entry)
                        return False

                    kill_for("monitor-state-invalid", monitor_state_still_broken)
                    continue

                if pulse_generation is None:
                    pulse_generation = current_pulse
                    lease_generation = current_lease
                    lease_state = current_lease_state
                elif current_lease != lease_generation:
                    lease_generation = current_lease
                    lease_state = current_lease_state
                    if armed:
                        last_progress = now
                    dispatch_started = (
                        now if lease_state == "active" else None
                    )
                else:
                    lease_state = current_lease_state

                if not armed:
                    if current_pulse != pulse_generation:
                        armed = True
                        pulse_generation = current_pulse
                        last_progress = now
                        if lease_state == "active":
                            dispatch_started = now
                    elif deadline_expired(
                        now, started, startup_seconds
                    ):
                        snapshot = (
                            current_pulse,
                            current_lease,
                            current_lease_state,
                        )

                        def startup_still_expired():
                            validate_lock_files(lock_identities)
                            latest = monitor_snapshot(
                                pulse_entry, lease_entry
                            )
                            return (
                                latest == snapshot
                                and deadline_expired(
                                    time.monotonic(),
                                    started,
                                    startup_seconds,
                                )
                            )

                        kill_for("startup-timeout", startup_still_expired)
                else:
                    if current_pulse != pulse_generation:
                        pulse_generation = current_pulse
                        last_progress = now

                    # Heartbeat and dispatch deadlines are independent.  A
                    # non-yielding handler stops the pulse; a recursive wait
                    # can keep timers alive but cannot outlive its dispatch.
                    deadline_cause = select_deadline_cause(
                        now,
                        last_progress,
                        normal_seconds,
                        dispatch_started if lease_state == "active" else None,
                        dispatch_seconds,
                    )
                    if deadline_cause is not None:
                        snapshot = (
                            current_pulse,
                            current_lease,
                            current_lease_state,
                        )

                        def activity_still_expired():
                            validate_lock_files(lock_identities)
                            latest = monitor_snapshot(
                                pulse_entry, lease_entry
                            )
                            return (
                                latest == snapshot
                                and (
                                    deadline_expired(
                                        time.monotonic(),
                                        last_progress,
                                        normal_seconds,
                                    )
                                    or (
                                        lease_state == "active"
                                        and deadline_expired(
                                            time.monotonic(),
                                            dispatch_started,
                                            dispatch_seconds,
                                        )
                                    )
                                )
                            )

                        kill_for(deadline_cause, activity_still_expired)

                if now >= next_refresh:
                    try:
                        for lock_path, _expected in lock_identities:
                            os.utime(lock_path, follow_symlinks=False)
                        refresh_durable_state(state_root)
                    except BaseException:
                        def refresh_still_broken():
                            validate_lock_files(lock_identities)
                            refresh_durable_state(state_root)
                            return False

                        kill_for("durable-refresh-failure", refresh_still_broken)
                    next_refresh = now + refresh_seconds
                time.sleep(poll_seconds)
        except BaseException:
            try:
                kill_for("monitor-internal-error", lambda: True)
            except BaseException:
                try:
                    os.kill(parent_pid, signal.SIGKILL)
                except OSError:
                    pass
                os._exit(0)
        os._exit(0)


    if len(sys.argv) != 5:
        fail(
            "usage: anvil-lock-launcher.py RUNTIME_DIR STATE_DIR "
            "CONFLICT_STATUS LOCKED_STAGE"
        )

    runtime_dir, state_dir, status_text, locked_stage = sys.argv[1:]
    try:
        lock_conflict_status = int(status_text)
    except ValueError:
        fail(f"invalid lock conflict status: {status_text}")
    if lock_conflict_status not in (0, 75):
        fail(f"invalid lock conflict status: {lock_conflict_status}")

    refresh_seconds = positive_seconds(
        "ANVIL_EMACS_LOCK_REFRESH_SECONDS", DEFAULT_REFRESH_SECONDS
    )
    startup_seconds = positive_seconds(
        "ANVIL_EMACS_WATCHDOG_STARTUP_SECONDS", DEFAULT_STARTUP_SECONDS
    )
    normal_seconds = positive_seconds(
        "ANVIL_EMACS_WATCHDOG_NORMAL_SECONDS", DEFAULT_NORMAL_SECONDS
    )
    dispatch_seconds = positive_seconds(
        "ANVIL_EMACS_WATCHDOG_DISPATCH_SECONDS", DEFAULT_DISPATCH_SECONDS
    )
    pulse_seconds = positive_seconds(
        "ANVIL_EMACS_WATCHDOG_PULSE_SECONDS", DEFAULT_PULSE_SECONDS
    )
    if normal_seconds < 3.0 * pulse_seconds:
        fail(
            "ANVIL_EMACS_WATCHDOG_NORMAL_SECONDS must be at least "
            "three pulse intervals",
            EXIT_CONFIG,
        )
    if startup_seconds < 3.0 * pulse_seconds:
        fail(
            "ANVIL_EMACS_WATCHDOG_STARTUP_SECONDS must be at least "
            "three pulse intervals",
            EXIT_CONFIG,
        )
    try:
        runtime_info = os.stat(runtime_dir, follow_symlinks=False)
        state_info = os.stat(state_dir, follow_symlinks=False)
    except OSError as error:
        fail(f"cannot compare runtime and state directories: {error}", EXIT_CONFIG)
    if (runtime_info.st_dev, runtime_info.st_ino) == (
        state_info.st_dev,
        state_info.st_ino,
    ):
        fail("runtime and state directories must be distinct", EXIT_CONFIG)

    capabilities = configure_watchdog_capabilities(os.environ)
    runtime_lock = acquire_lock(runtime_dir, 8, "runtime", lock_conflict_status)
    state_lock = acquire_lock(state_dir, 9, "state", lock_conflict_status)
    activity_listener, activity_entry = prepare_activity_listener(runtime_dir)
    pulse_entry = open_monitor_file(
        runtime_dir, PULSE_NAME, b"pulse:boot\n", 0o600
    )
    lease_entry = open_monitor_file(
        runtime_dir, LEASE_NAME, b"lease\n", 0o400
    )
    os.environ["ANVIL_EMACS_WATCHDOG_PULSE_FILE"] = pulse_entry[0]
    os.environ["ANVIL_EMACS_WATCHDOG_LEASE_FILE"] = lease_entry[0]
    os.environ["ANVIL_EMACS_WATCHDOG_PULSE_SECONDS"] = str(pulse_seconds)
    os.environ["ANVIL_EMACS_WATCHDOG_ACTIVITY_SOCKET"] = activity_entry[0]
    os.environ["ANVIL_EMACS_WATCHDOG_RUN_ID"] = capabilities["run_id"]

    parent_pid = os.getpid()
    try:
        monitor_pid = os.fork()
    except OSError as error:
        activity_listener.close()
        safe_unlink_activity(activity_entry[0], activity_entry[1])
        fail(f"cannot start root watchdog monitor: {error}")
    if monitor_pid == 0:
        monitor(
            parent_pid,
            (runtime_lock, state_lock),
            state_dir,
            pulse_entry,
            lease_entry,
            capabilities["event_fd"],
            capabilities["discard_fd"],
            capabilities["run_id"],
            activity_listener,
            activity_entry,
            refresh_seconds,
            pulse_seconds,
            startup_seconds,
            normal_seconds,
            dispatch_seconds,
        )

    os.close(pulse_entry[1])
    os.close(lease_entry[1])
    os.close(capabilities["event_fd"])
    if capabilities["discard_fd"] is not None:
        os.close(capabilities["discard_fd"])
    activity_listener.close()
    try:
        os.execv(locked_stage, [locked_stage, runtime_dir, state_dir])
    except OSError as error:
        fail(f"cannot exec locked stage {locked_stage}: {error}")
  '';
  dedicatedTelemetryInit = writeText "anvil-headless-watchdog-telemetry.el" ''
    ;;; anvil-headless-watchdog-telemetry.el --- Root activity -*- lexical-binding: t; -*-

    (require 'json)
    (declare-function anvil-headless--run-process-responsive nil
                      (program arguments directory timeout
                               stdout-limit stderr-limit))

    (defconst anvil-headless--watchdog-probe-python
      "${python3}/bin/python3")
    (defconst anvil-headless--watchdog-probe-supervisor
      "${dedicatedAgentSupervisor}")
    (defconst anvil-headless--watchdog-probe-runtime-directory
      (let ((runtime (getenv "XDG_RUNTIME_DIR")))
        (when (and (stringp runtime)
                   (file-name-absolute-p runtime))
          (condition-case nil
              (directory-file-name (file-truename runtime))
            (error nil)))))
    (defconst anvil-headless--watchdog-probe-agent-key
      (when anvil-headless--watchdog-probe-runtime-directory
        (let ((candidate
               (file-name-nondirectory
                anvil-headless--watchdog-probe-runtime-directory)))
          (and (string-match-p "\\`[0-9a-f]\\{32\\}\\'" candidate)
               candidate))))

    (defconst anvil-headless--watchdog-telemetry-socket
      (getenv "ANVIL_EMACS_WATCHDOG_ACTIVITY_SOCKET"))
    (defconst anvil-headless--watchdog-telemetry-run-id
      (getenv "ANVIL_EMACS_WATCHDOG_RUN_ID"))
    (setenv "ANVIL_EMACS_WATCHDOG_ACTIVITY_SOCKET" nil)
    (setenv "ANVIL_EMACS_WATCHDOG_RUN_ID" nil)

    (defvar anvil-headless--watchdog-telemetry-process nil)
    (defvar anvil-headless--watchdog-telemetry-disabled nil)
    (defvar anvil-headless--watchdog-telemetry-diagnosed nil)
    (defvar anvil-headless--watchdog-telemetry-sequence 0)
    (defvar anvil-headless--watchdog-telemetry-phase-started-ms 0)
    (defvar anvil-headless--watchdog-telemetry-last-transition nil)
    (defvar anvil-headless--watchdog-telemetry-method "none")
    (defvar anvil-headless--watchdog-telemetry-tool nil)

    (defun anvil-headless--watchdog-probe-summary-p (summary)
      "Return non-nil when SUMMARY is one complete bounded status line."
      (save-match-data
        (and
         (stringp summary)
         (<= (string-bytes summary) 256)
         (string-match
          (concat
           "\\`root-restarts=\\(0\\|[1-9][0-9]*\\)"
           " cause=\\(none\\|startup-timeout\\|heartbeat-timeout"
           "\\|dispatch-timeout\\|lock-integrity-failure"
           "\\|monitor-state-invalid\\|durable-refresh-failure"
           "\\|monitor-internal-error\\)"
           " phase=\\(unknown\\|startup\\|parse\\|dispatch\\|tool-call"
           "\\|result-encode\\|response-write\\|idle\\)"
           " tool=\\(none\\|[A-Za-z0-9][A-Za-z0-9._/-]\\{0,127\\}\\)\n\\'")
          summary)
         (or (not (equal (match-string 2 summary) "none"))
             (and (equal (match-string 3 summary) "unknown")
                  (equal (match-string 4 summary) "none"))))))

    (defun anvil-headless--watchdog-probe-root-summary ()
      "Return a validated root summary or the constant unavailable marker."
      (condition-case nil
          (if (not (and anvil-headless--watchdog-probe-runtime-directory
                        anvil-headless--watchdog-probe-agent-key
                        (fboundp 'anvil-headless--run-process-responsive)))
              "unavailable"
            (let ((result
                   (anvil-headless--run-process-responsive
                    anvil-headless--watchdog-probe-python
                    (list
                     "-I" "-S" anvil-headless--watchdog-probe-supervisor
                     "--probe-summary"
                     "--runtime-dir"
                     anvil-headless--watchdog-probe-runtime-directory
                     "--agent-key"
                     anvil-headless--watchdog-probe-agent-key)
                    anvil-headless--watchdog-probe-runtime-directory
                    2 257 0)))
              (if (and (listp result)
                       (= (length result) 3)
                       (integerp (nth 0 result))
                       (= (nth 0 result) 0)
                       (equal (nth 2 result) "")
                       (anvil-headless--watchdog-probe-summary-p
                        (nth 1 result)))
                  (substring (nth 1 result) 0 -1)
                "unavailable")))
        (error "unavailable")))

    (defun anvil-headless--watchdog-probe-around
        (original &rest arguments)
      "Append one bounded root status line to the worker probe result."
      (concat (apply original arguments)
              "\nroot-summary="
              (anvil-headless--watchdog-probe-root-summary)))

    (defun anvil-headless--watchdog-probe-install ()
      "Install the root status extension on the worker probe once."
      (when (and (fboundp 'anvil-worker--tool-probe)
                 (not (advice-member-p
                       #'anvil-headless--watchdog-probe-around
                       'anvil-worker--tool-probe)))
        (advice-add 'anvil-worker--tool-probe
                    :around #'anvil-headless--watchdog-probe-around)))

    (defconst anvil-headless--watchdog-telemetry-methods
      '("none"
        "initialize"
        "notifications/initialized"
        "ping"
        "tools/list"
        "tools/call"
        "resources/list"
        "resources/read"
        "resources/templates/list"
        "other"))

    (defun anvil-headless--watchdog-telemetry-disable ()
      "Disable activity telemetry with one constant diagnostic."
      (unless anvil-headless--watchdog-telemetry-disabled
        (setq anvil-headless--watchdog-telemetry-disabled t)
        (when anvil-headless--watchdog-telemetry-process
          (condition-case nil
              (delete-process anvil-headless--watchdog-telemetry-process)
            (error nil)))
        (setq anvil-headless--watchdog-telemetry-process nil))
      (unless anvil-headless--watchdog-telemetry-diagnosed
        (setq anvil-headless--watchdog-telemetry-diagnosed t)
        (message "Anvil watchdog telemetry disabled")))

    (defun anvil-headless--watchdog-telemetry-connect ()
      "Connect once to the private watchdog activity endpoint."
      (unless anvil-headless--watchdog-telemetry-disabled
        (if (not (and
                  (stringp anvil-headless--watchdog-telemetry-socket)
                  (stringp anvil-headless--watchdog-telemetry-run-id)
                  (string-match-p
                   "\\`[0-9a-f]\\{32\\}\\'"
                   anvil-headless--watchdog-telemetry-run-id)))
            (anvil-headless--watchdog-telemetry-disable)
          (condition-case nil
              (setq anvil-headless--watchdog-telemetry-process
                    (make-network-process
                     :name "anvil-watchdog-activity"
                     :family 'local
                     :service anvil-headless--watchdog-telemetry-socket
                     :coding '(utf-8-unix . utf-8-unix)
                     :noquery t
                     :buffer nil))
            (error
             (anvil-headless--watchdog-telemetry-disable))))))

    (defun anvil-headless--watchdog-telemetry-now-ms ()
      (max 0 (floor (* 1000 (float-time)))))

    (defun anvil-headless--watchdog-telemetry-method (method)
      (if (and (stringp method)
               (member method
                       anvil-headless--watchdog-telemetry-methods))
          method
        "other"))

    (defun anvil-headless--watchdog-telemetry-tool-p (tool)
      (and (stringp tool)
           (string-match-p
            "\\`[A-Za-z0-9][A-Za-z0-9._/-]\\{0,127\\}\\'"
            tool)))

    (defun anvil-headless--watchdog-telemetry-object-alist-p (value)
      "Return non-nil when VALUE is a proper object-style alist."
      (let ((rest value)
            (valid t))
        (while (and valid (consp rest))
          (unless (consp (car rest))
            (setq valid nil))
          (setq rest (cdr rest)))
        (and valid (null rest))))

    (defun anvil-headless--watchdog-telemetry-registered-tool
        (tool server-id)
      (when (anvil-headless--watchdog-telemetry-tool-p tool)
        (let* ((resolved-id
                (if (fboundp 'anvil-server--resolve-id)
                    (anvil-server--resolve-id server-id)
                  server-id))
               (table (and (boundp 'anvil-server--tools)
                           (gethash resolved-id anvil-server--tools))))
          (and table (gethash tool table) tool))))

    (defun anvil-headless--watchdog-telemetry-send (frame)
      (unless anvil-headless--watchdog-telemetry-disabled
        (condition-case nil
            (if (and anvil-headless--watchdog-telemetry-process
                     (process-live-p
                      anvil-headless--watchdog-telemetry-process))
                (process-send-string
                 anvil-headless--watchdog-telemetry-process frame)
              (anvil-headless--watchdog-telemetry-disable))
          (error
           (anvil-headless--watchdog-telemetry-disable)))))

    (defun anvil-headless--watchdog-telemetry-emit (phase)
      "Emit PHASE unless its semantic transition is a duplicate."
      (let ((transition
             (list phase
                   anvil-headless--watchdog-telemetry-method
                   anvil-headless--watchdog-telemetry-tool)))
        (unless (equal transition
                       anvil-headless--watchdog-telemetry-last-transition)
          (let ((now (anvil-headless--watchdog-telemetry-now-ms)))
            (setq anvil-headless--watchdog-telemetry-last-transition
                  transition
                  anvil-headless--watchdog-telemetry-phase-started-ms now
                  anvil-headless--watchdog-telemetry-sequence
                  (1+ anvil-headless--watchdog-telemetry-sequence))
            (let* ((json-encoding-pretty-print nil)
                   (frame
                    (concat
                     (json-encode
                      `((schema_version . 1)
                        (run_id . ,anvil-headless--watchdog-telemetry-run-id)
                        (daemon_pid . ,(emacs-pid))
                        (sequence . ,anvil-headless--watchdog-telemetry-sequence)
                        (phase . ,phase)
                        (method . ,anvil-headless--watchdog-telemetry-method)
                        (tool . ,anvil-headless--watchdog-telemetry-tool)
                        (phase_started_unix_ms
                         . ,anvil-headless--watchdog-telemetry-phase-started-ms)
                        (observed_at_unix_ms . ,now)))
                     "\n")))
              (if (<= (string-bytes
                       (encode-coding-string frame 'utf-8-unix t))
                      1024)
                  (anvil-headless--watchdog-telemetry-send frame)
                (anvil-headless--watchdog-telemetry-disable)))))))

    (defun anvil-headless--watchdog-telemetry-process-jsonrpc
        (original &rest arguments)
      (setq anvil-headless--watchdog-telemetry-method "none"
            anvil-headless--watchdog-telemetry-tool nil)
      (anvil-headless--watchdog-telemetry-emit "parse")
      (unwind-protect
          (apply original arguments)
        (setq anvil-headless--watchdog-telemetry-method "none"
              anvil-headless--watchdog-telemetry-tool nil)
        (anvil-headless--watchdog-telemetry-emit "idle")))

    (defun anvil-headless--watchdog-telemetry-dispatch
        (original request &rest arguments)
      (setq anvil-headless--watchdog-telemetry-method
            (anvil-headless--watchdog-telemetry-method
             (alist-get 'method request))
            anvil-headless--watchdog-telemetry-tool nil)
      (anvil-headless--watchdog-telemetry-emit "dispatch")
      (apply original request arguments))

    (defun anvil-headless--watchdog-telemetry-tool-call
        (original id params method-metrics server-id)
      (setq anvil-headless--watchdog-telemetry-method "tools/call"
            anvil-headless--watchdog-telemetry-tool
            (anvil-headless--watchdog-telemetry-registered-tool
             (and
              (anvil-headless--watchdog-telemetry-object-alist-p params)
              (alist-get 'name params))
             server-id))
      (anvil-headless--watchdog-telemetry-emit "tool-call")
      (funcall original id params method-metrics server-id))

    (defun anvil-headless--watchdog-telemetry-result
        (original &rest arguments)
      (anvil-headless--watchdog-telemetry-emit "result-encode")
      (apply original arguments))

    (defun anvil-headless--watchdog-telemetry-response
        (original &rest arguments)
      (anvil-headless--watchdog-telemetry-emit "response-write")
      (apply original arguments))

    (defun anvil-headless--watchdog-telemetry-add-advice
        (function advice)
      (when (and (fboundp function)
                 (not (advice-member-p advice function)))
        (advice-add function :around advice)))

    (defun anvil-headless--watchdog-telemetry-install ()
      (anvil-headless--watchdog-telemetry-add-advice
       'anvil-server-process-jsonrpc
       #'anvil-headless--watchdog-telemetry-process-jsonrpc)
      (anvil-headless--watchdog-telemetry-add-advice
       'anvil-server--validate-and-dispatch-request
       #'anvil-headless--watchdog-telemetry-dispatch)
      (anvil-headless--watchdog-telemetry-add-advice
       'anvil-server--handle-tools-call
       #'anvil-headless--watchdog-telemetry-tool-call)
      (dolist (function
               '(anvil-server--enforce-inline-result-limit
                 anvil-server--sanitize-tool-error))
        (anvil-headless--watchdog-telemetry-add-advice
         function #'anvil-headless--watchdog-telemetry-result))
      (dolist (function
               '(anvil-server--jsonrpc-response
                 anvil-server--jsonrpc-error
                 anvil-server--jsonrpc-response-from-result-json))
        (anvil-headless--watchdog-telemetry-add-advice
         function #'anvil-headless--watchdog-telemetry-response)))

    (with-eval-after-load 'anvil-server
      (anvil-headless--watchdog-telemetry-install))
    (with-eval-after-load 'anvil-worker
      (anvil-headless--watchdog-probe-install))
    (anvil-headless--watchdog-telemetry-connect)

    (provide 'anvil-headless-watchdog-telemetry)
    ;;; anvil-headless-watchdog-telemetry.el ends here
  '';

  dedicatedInit = writeText "anvil-headless-init.el" ''
        ;;; anvil-headless-init.el --- Dedicated Anvil root -*- lexical-binding: t; -*-

        (defvar anvil-eval-timeout)
        (defvar anvil-eval-async-timeout)
        (defvar anvil-eval-nelisp-source-directory)
        (defvar anvil-host--default-timeout)
        (defvar anvil-shell-filter-max-sync-timeout)
        (defvar anvil-worker-read-pool-size)
        (defvar anvil-worker-write-pool-size)
        (defvar anvil-worker-batch-pool-size)
        (defvar anvil-worker-eager-spawn)
        (defvar anvil-worker-spawn-wait)
        (defvar anvil-server-schema-cache-file)
        (defvar anvil-org-allowed-files-enabled)
        (defvar org-directory)
        (defvar org-agenda-files)
        (defvar anvil-semantic-roots)
        (defvar anvil-semantic-db-path)
        (defvar anvil-pdf-python)
        (defvar anvil-offload-emacs-bin)
        (defvar anvil-offload-init-files)
        (defvar anvil-offload-spawn-environment-function)
        (defvar anvil-offload-max-frame-bytes)
        (defvar anvil-worker-emacs-bin)
        (defvar anvil-worker-init-file)
        (defvar anvil-optional-modules)
        (defvar anvil-server-autostart-on-request)
        (defvar anvil-worker--pool)
        (defvar anvil-modules)
        (defvar anvil--loaded-modules)
        (defvar anvil-headless--baseline-process-environment)
        (defvar anvil-headless--baseline-exec-path)
        (defvar anvil-headless--ready)
        (declare-function anvil-headless--snapshot-baseline-environment nil ())
        (declare-function anvil-worker-kill "anvil-worker" ())
        (defvar anvil-headless--watchdog-pulse-file nil)
        (defvar anvil-headless--watchdog-lease-file nil)
        (defvar anvil-headless--watchdog-pulse-seconds nil)
        (defvar anvil-headless--watchdog-pulse-counter 0)
        (defvar anvil-headless--watchdog-timer nil)
        (defvar anvil-headless--watchdog-sync-dispatch-depth 0)

        (load "${dedicatedTelemetryInit}" nil nil t)

        (let* ((runtime-dir (getenv "XDG_RUNTIME_DIR"))
               (state-dir (getenv "ANVIL_EMACS_STATE_DIR"))
               (temp-dir (and runtime-dir (expand-file-name "tmp/" runtime-dir)))
               (org-root
                (file-name-as-directory
                 (expand-file-name
                  (or (getenv "ANVIL_EMACS_ORG_ROOT") "~/org")))))
          (unless (and state-dir temp-dir (file-directory-p state-dir))
            (error "Anvil requires existing state and runtime directories"))
          (make-directory temp-dir t)
          (setq native-comp-jit-compilation nil
                anvil-eval-timeout ${toString timeoutPolicy.cooperativeSyncSeconds}
                anvil-eval-async-timeout ${toString timeoutPolicy.asyncSeconds}
                anvil-eval-nelisp-source-directory "${nelispLispSrc}"
                anvil-shell-filter-max-sync-timeout ${toString timeoutPolicy.shellSyncSeconds}
                anvil-worker-read-pool-size ${toString workerPoolSizes.read}
                anvil-worker-write-pool-size ${toString workerPoolSizes.write}
                anvil-worker-batch-pool-size ${toString workerPoolSizes.batch}
                anvil-worker-eager-spawn nil
                anvil-worker-spawn-wait ${toString timeoutPolicy.workerSpawnSeconds}
                user-emacs-directory (file-name-as-directory state-dir)
                package-user-dir (expand-file-name "elpa" state-dir)
                custom-file (expand-file-name "custom.el" state-dir)
                temporary-file-directory (file-name-as-directory temp-dir)
                anvil-server-schema-cache-file
                (expand-file-name "anvil-schema-cache.el" temp-dir)
                anvil-org-allowed-files-enabled nil
                org-directory org-root
                org-agenda-files
                (and (file-directory-p org-root) (list org-root))
                anvil-semantic-roots
                (and (file-directory-p org-root) (list org-root))
                anvil-semantic-db-path
                (expand-file-name "semantic/index.db" state-dir))
          (when (fboundp 'startup-redirect-eln-cache)
            (startup-redirect-eln-cache
             (expand-file-name "eln-cache/" state-dir))))

        (defun anvil-headless--watchdog-write (path value)
          "Write VALUE to the existing watchdog file at PATH without replacing it."
          (unless (and (stringp path)
                       (file-regular-p path)
                       (not (file-symlink-p path)))
            (error "Unsafe Anvil watchdog file: %S" path))
          (let ((coding-system-for-write 'utf-8-unix)
                (create-lockfiles nil))
            (write-region value nil path nil 'silent)))

        (defun anvil-headless--watchdog-pulse ()
          "Record one root event-loop progress pulse, failing closed on error."
          (condition-case err
              (progn
                (setq anvil-headless--watchdog-pulse-counter
                      (1+ anvil-headless--watchdog-pulse-counter))
                (anvil-headless--watchdog-write
                 anvil-headless--watchdog-pulse-file
                 (format "pulse:%d\n"
                         anvil-headless--watchdog-pulse-counter)))
            (error
             (message "Anvil watchdog pulse failed: %s"
                      (error-message-string err))
             (kill-emacs 70))))

        (defun anvil-headless--watchdog-set-lease-state (active)
          "Set the fixed lease inode to ACTIVE or idle without rewriting it."
          (let ((path anvil-headless--watchdog-lease-file)
                (mode (if active #o600 #o400)))
            (unless (and (stringp path)
                         (file-regular-p path)
                         (not (file-symlink-p path)))
              (error "Unsafe Anvil watchdog lease file: %S" path))
            (set-file-modes path mode)
            (unless (and (file-regular-p path)
                         (not (file-symlink-p path))
                         (= (logand (or (file-modes path) 0) #o777) mode))
              (error "Anvil watchdog lease mode transition failed: %S" path))))

        (defun anvil-headless--watchdog-refresh-lease-state ()
          "Reflect synchronous request activity in the diagnostic lease."
          (anvil-headless--watchdog-set-lease-state
           (> anvil-headless--watchdog-sync-dispatch-depth 0)))

        (defun anvil-headless--watchdog-sync-dispatch (original &rest args)
          "Run synchronous JSON-RPC dispatch through ORIGINAL under a lease."
          (setq anvil-headless--watchdog-sync-dispatch-depth
                (1+ anvil-headless--watchdog-sync-dispatch-depth))
          (let ((lease-entered nil))
            (unwind-protect
                (progn
                  (anvil-headless--watchdog-refresh-lease-state)
                  (setq lease-entered t)
                  (apply original args))
              (setq anvil-headless--watchdog-sync-dispatch-depth
                    (max 0 (1- anvil-headless--watchdog-sync-dispatch-depth)))
              (when lease-entered
                (condition-case err
                    (anvil-headless--watchdog-refresh-lease-state)
                  (error
                   (message "Anvil synchronous watchdog cleanup failed: %s"
                            (error-message-string err))
                   (kill-emacs 70)))))))

        (defun anvil-headless--watchdog-arm ()
          "Arm the external root watchdog after the MCP server is ready."
          (setq anvil-headless--watchdog-sync-dispatch-depth 0
                anvil-headless--watchdog-pulse-file
                (getenv "ANVIL_EMACS_WATCHDOG_PULSE_FILE")
                anvil-headless--watchdog-lease-file
                (getenv "ANVIL_EMACS_WATCHDOG_LEASE_FILE")
                anvil-headless--watchdog-pulse-seconds
                (string-to-number
                 (or (getenv "ANVIL_EMACS_WATCHDOG_PULSE_SECONDS") "")))
          (unless (and anvil-headless--watchdog-pulse-file
                       anvil-headless--watchdog-lease-file
                       (> anvil-headless--watchdog-pulse-seconds 0))
            (error "Anvil watchdog environment is incomplete"))
          (anvil-headless--watchdog-set-lease-state nil)
          (anvil-headless--watchdog-pulse)
          (setq anvil-headless--watchdog-timer
                (run-at-time
                 anvil-headless--watchdog-pulse-seconds
                 anvil-headless--watchdog-pulse-seconds
                 #'anvil-headless--watchdog-pulse)))

        (require 'anvil)
        (require 'anvil-server-commands)
        (require 'anvil-worker)

        ;; Keep the direct typed registry diagnostic-only while publishing a
        ;; union through the stable deployed id.  The typed modules register under
        ;; "emacs-eval"; the eval/IDE modules use `anvil-server-id'.
        (setq anvil-server-id "anvil")

        (defun anvil-headless--mirror-registry-table
            (registry-symbol source-id target-id)
          "Copy SOURCE-ID entries in REGISTRY-SYMBOL into TARGET-ID.
    Signal on collisions so the unified surface cannot silently replace a tool,
    resource, or template already owned by the primary registry."
          (let* ((registry (symbol-value registry-symbol))
                 (source (gethash source-id registry)))
            (when source
              (let ((target
                     (or (gethash target-id registry)
                         (let ((table
                                (make-hash-table :test (hash-table-test source))))
                           (puthash target-id table registry)
                           table))))
                (maphash
                 (lambda (key value)
                   (when (gethash key target)
                     (error "Anvil registry collision for %S in %s"
                            key registry-symbol))
                   (puthash key value target))
                 source)))))

        (defun anvil-headless--publish-unified-registry ()
          "Mirror the direct typed surface into the stable Anvil registry."
          (unless (gethash "emacs-eval" anvil-server--tools)
            (error "Anvil direct typed registry is missing"))
          (dolist (registry-symbol
                   '(anvil-server--tools
                     anvil-server--resources
                     anvil-server--resource-templates))
            (anvil-headless--mirror-registry-table
             registry-symbol "emacs-eval" "anvil"))
          (anvil-server--tools-list-cache-invalidate "anvil"))

        (defun anvil-headless--with-parent-pid-for-worker
            (original &rest args)
          "Spawn a worker from immutable root login environment snapshots."
          (unless (and anvil-headless--baseline-process-environment
                       anvil-headless--baseline-exec-path)
            (error "Anvil worker baseline environment is unavailable"))
          (let ((process-environment
                 (copy-sequence
                  anvil-headless--baseline-process-environment))
                (exec-path
                 (copy-sequence anvil-headless--baseline-exec-path))
                (default-directory
                 (file-name-as-directory user-emacs-directory)))
            (setenv "ANVIL_HEADLESS_REAL_SHELL" nil)
            (setenv "ANVIL_HEADLESS_PARENT_PID" nil)
            (setenv "ANVIL_HEADLESS_PARENT_PID"
                    (number-to-string (emacs-pid)))
            (apply original args)))

        (defun anvil-headless--offload-spawn-environment ()
          "Return the immutable root baseline for one isolated async child."
          (unless anvil-headless--baseline-process-environment
            (error "Anvil offload baseline environment is unavailable"))
          (let ((process-environment
                 (copy-sequence anvil-headless--baseline-process-environment)))
            ;; Inject containment controls after removing project-derived values.
            (setenv "ANVIL_HEADLESS_PARENT_PID" (number-to-string (emacs-pid)))
            (setenv "ANVIL_HEADLESS_REAL_SHELL" nil)
            (setenv "ANVIL_EMACS_WORKER" "1")
            process-environment))

        (condition-case err
            (progn
              (load "${dedicatedEnvironmentInit}" nil nil t)
              (anvil-headless--snapshot-baseline-environment)
              (setq anvil-pdf-python "${pythonWithPyMuPDF}/bin/python3"
                    anvil-offload-emacs-bin
                    "${dedicatedOffloadEmacs}/bin/anvil-offload-emacs"
                    anvil-offload-init-files (list "${dedicatedOffloadInit}")
                    anvil-offload-spawn-environment-function
                    #'anvil-headless--offload-spawn-environment
                    anvil-offload-max-frame-bytes (* 2 1024 1024)
                    anvil-worker-emacs-bin "${dedicatedWorkerEmacs}/bin/anvil-worker-emacs"
                    anvil-worker-init-file "${dedicatedWorkerInit}"
                    anvil-optional-modules
                    '(ide elisp sexp semantic sqlite pdf cron state shell-filter
                          context)
                    anvil-server-autostart-on-request t)

              (unless (and (fboundp 'sqlite-available-p)
                           (sqlite-available-p))
                (error "Anvil requires Emacs SQLite support"))
              (dolist (program '("emacs" "emacsclient"))
                (unless (executable-find program)
                  (error "Anvil requires %s on PATH" program)))
              (unless (zerop
                       (call-process anvil-pdf-python nil nil nil
                                     "-c" "import fitz"))
                (error "Anvil requires PyMuPDF"))

              (unless (fboundp 'anvil-worker--spawn-worker)
                (error "Anvil worker spawn function is unavailable"))
              (advice-add 'anvil-worker--spawn-worker
                          :around
                          #'anvil-headless--with-parent-pid-for-worker)
              (advice-add 'anvil-server-process-jsonrpc
                          :around
                          #'anvil-headless--watchdog-sync-dispatch)
              (anvil-enable)
              ;; anvil-enable loads anvil-host, whose defconst resets this
              ;; value.  Set the packaged policy only after module loading.
              (setq anvil-host--default-timeout
                    ${toString timeoutPolicy.hostShellSeconds})
              (anvil-headless--publish-unified-registry)
              (let (actual-worker-specs)
                (dolist (lane '(:read :write :batch))
                  (let ((pool (plist-get anvil-worker--pool lane)))
                    (dotimes (index (length pool))
                      (push (list lane (plist-get (aref pool index) :name))
                            actual-worker-specs))))
                (setq actual-worker-specs (nreverse actual-worker-specs))
                (unless (equal actual-worker-specs '${workerSpecsElisp})
                  (error "Anvil worker roster drifted: actual=%S expected=%S"
                         actual-worker-specs '${workerSpecsElisp})))
              (dolist (module (append anvil-modules anvil-optional-modules))
                (unless (memq module anvil--loaded-modules)
                  (error "Anvil failed to load required module: %s" module)))
              (add-hook 'kill-emacs-hook #'anvil-worker-kill)
              (anvil-server-start)
              (anvil-headless--watchdog-arm)
              ;; The supervisor probes this final publication, not the socket:
              ;; daemon-mode Emacs exposes its server before init is complete.
              (setq anvil-headless--ready t))
          (error
           (message "Anvil headless startup failed: %s"
                    (error-message-string err))
           (kill-emacs 70)))
  '';

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
  watchdogCapabilityDescendantInit = writeText "anvil-watchdog-capability-descendant.el" ''
    ;;; anvil-watchdog-capability-descendant.el --- Test capability hygiene -*- lexical-binding: t; -*-

    (require 'json)

    (let ((result (getenv "ANVIL_TEST_DESCENDANT_RESULT"))
          (root-socket-identities
           (json-parse-string
            (or (getenv "ANVIL_TEST_ROOT_SOCKET_IDENTITIES") "[]")
            :array-type 'list))
          (event-pipe-inode
           (string-to-number
            (or (getenv "ANVIL_TEST_EVENT_PIPE_INODE") "0")))
          (capability-keys
           '("ANVIL_EMACS_WATCHDOG_SUPERVISED"
             "ANVIL_EMACS_WATCHDOG_EVENT_FD"
             "ANVIL_EMACS_WATCHDOG_ACTIVITY_SOCKET"
             "ANVIL_EMACS_WATCHDOG_RUN_ID"))
          inherited-root-socket-fds
          inherited-event-pipe-fds)
      (unless (and result (file-name-absolute-p result))
        (error "Missing absolute descendant result path"))
      (dotimes (offset 1021)
        (let* ((descriptor (+ 3 offset))
               (attributes
                (ignore-errors
                  (file-attributes (format "/dev/fd/%d" descriptor) 'string)))
               (modes (and attributes (file-attribute-modes attributes))))
          (when (and (stringp modes) (> (length modes) 0))
            (let ((identity (file-attribute-file-identifier attributes)))
              (cond
               ((eq (aref modes 0) ?p)
                (when (= (nth 0 identity) event-pipe-inode)
                  (push descriptor inherited-event-pipe-fds)))
               ((eq (aref modes 0) ?s)
                (when (member (list (nth 0 identity) (nth 1 identity))
                              root-socket-identities)
                  (push descriptor inherited-root-socket-fds))))))))
      (with-temp-file result
        (insert
         (json-serialize
          `((present_keys
             . ,(vconcat
                 (delq nil
                       (mapcar
                        (lambda (name) (and (getenv name) name))
                        capability-keys))))
            (inherited_root_socket_fds
             . ,(vconcat (nreverse inherited-root-socket-fds)))
            (inherited_event_pipe_fds
             . ,(vconcat (nreverse inherited-event-pipe-fds)))
            (scan_first . 3)
            (scan_last . 1023))))))
  '';
  watchdogCapabilityRootInit = writeText "anvil-watchdog-capability-root.el" ''
    ;;; anvil-watchdog-capability-root.el --- Test the real root boundary -*- lexical-binding: t; -*-

    (load "${dedicatedTelemetryInit}" nil nil t)
    (unless (process-live-p anvil-headless--watchdog-telemetry-process)
      (error "Root telemetry socket did not connect"))
    (let (socket-identities)
      (dotimes (offset 1021)
        (let* ((descriptor (+ 3 offset))
               (attributes
                (ignore-errors
                  (file-attributes (format "/dev/fd/%d" descriptor) 'string)))
               (modes (and attributes (file-attribute-modes attributes))))
          (when (and (stringp modes)
                     (> (length modes) 0)
                     (eq (aref modes 0) ?s))
            (let ((identity (file-attribute-file-identifier attributes)))
              (push (vector (nth 0 identity) (nth 1 identity))
                    socket-identities)))))
      (unless socket-identities
        (error "Root telemetry connection exposed no socket identity"))
      (setenv "ANVIL_TEST_ROOT_SOCKET_IDENTITIES"
              (json-serialize (vconcat socket-identities)))
      (with-temp-buffer
        (let ((status
               (call-process
                "${dedicatedRuntimeEmacs}/bin/emacs" nil (list t t) nil
                "--batch" "-Q" "-l" "${watchdogCapabilityDescendantInit}")))
          (unless (eq status 0)
            (error "Real Emacs descendant failed: %S: %s"
                   status (buffer-string))))))
    ;; Inject a causally ordered monitor failure only after the descendant has
    ;; proved that no root capability leaked.  Lock validation runs on every
    ;; monitor iteration and does not depend on pulse baselining.
    (let* ((runtime (getenv "XDG_RUNTIME_DIR"))
           (lock (expand-file-name ".anvil-headless-emacs.lock" runtime))
           (replacement
            (make-temp-file
             (expand-file-name ".anvil-test-lock-replacement-" runtime))))
      (unwind-protect
          (progn
            (set-file-modes replacement #o600)
            (rename-file replacement lock t))
        (when (file-exists-p replacement)
          (delete-file replacement))))
    (while t
      (sleep-for 60))
  '';
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
  dedicatedGeneration = builtins.hashString "sha256" "${dedicatedAgentSupervisor}|${dedicatedParentGuardLauncher}|${dedicatedAgentDaemon}|${dedicatedCleanEnvironment}|${dedicatedDirenvNeutral}|${dedicatedAnvil}|${dedicatedAnvilIde}|${dedicatedOffloadEmacs}|${dedicatedOffloadInit}|${dedicatedSafeEmacsclient}|${generationSalt}";
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
if stdenv.isLinux then
  if useHeadlessEmacs then dedicatedPackage else standalonePackage
else if stdenv.isDarwin then
  if useDedicatedDarwinEmacs then dedicatedPackage else interactiveDarwinPackage
else
  throw "anvil-mcp is supported only on Darwin and Linux"
