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
    asyncSeconds = 300;
    bridgeDispatchSeconds = 150;
    bridgeReadinessSeconds = 20;
    bridgeStartupDispatchSeconds = 20;
    clientStartupSeconds = 210;
    clientToolSeconds = 210;
    cooperativeSyncSeconds = boundedSyncSeconds;
    emacsclientKillSeconds = 1;
    emacsclientProbeSeconds = 5;
    frameReadSeconds = 10;
    hostShellSeconds = boundedSyncSeconds;
    parentGuardReadySeconds = 5;
    requestParseSeconds = 10;
    shellSyncSeconds = boundedSyncSeconds;
    supervisorReadySeconds = 120;
    watchdogDispatchSeconds = 135;
    watchdogHeartbeatSeconds = 45;
    watchdogPulseSeconds = 1;
    watchdogStartupSeconds = 120;
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

  dedicatedAnvil =
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
              tests/anvil-offload-ownership-test.el \
              tests/anvil-server-unified-registry-test.el \
              "$out/share/emacs/site-lisp/tests"
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
    if stdenv.isLinux then "/run/user/$(id -u)/anvil-emacs" else "/tmp/anvil-emacs-$(id -u)";

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


    def guard_linux(root_pid, target_pid, group, ready_fd, commit_fd, state):
        root_fd = os.pidfd_open(root_pid, 0)
        target_fd = os.pidfd_open(target_pid, 0)
        poller = select.poll()
        poller.register(root_fd, select.POLLIN)
        poller.register(target_fd, select.POLLIN)
        poller.register(commit_fd, select.POLLIN | select.POLLHUP | select.POLLERR)
        if any(
            descriptor in (root_fd, target_fd)
            for descriptor, _event in poller.poll(0)
        ):
            raise RuntimeError("root or target exited before guard readiness")
        install_guard_signal_handlers(target_pid, group, state)
        os.write(ready_fd, b"R")
        while True:
            events = poller.poll()
            if any(descriptor == target_fd for descriptor, _event in events):
                terminate_target(target_pid, group, state)
                os._exit(0)
            if any(descriptor == root_fd for descriptor, _event in events):
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


    def guard_darwin(root_pid, target_pid, group, ready_fd, commit_fd, state):
        queue = select.kqueue()
        flags = select.KQ_EV_ADD | select.KQ_EV_ENABLE
        changes = [
            select.kevent(
                root_pid,
                filter=select.KQ_FILTER_PROC,
                flags=flags,
                fflags=select.KQ_NOTE_EXIT,
            ),
            select.kevent(
                target_pid,
                filter=select.KQ_FILTER_PROC,
                flags=flags,
                fflags=select.KQ_NOTE_EXIT,
            ),
            select.kevent(
                commit_fd,
                filter=select.KQ_FILTER_READ,
                flags=flags,
            ),
        ]
        queue.control(changes, 0, 0)
        initial = queue.control(None, 3, 0)
        if any(
            event.filter == select.KQ_FILTER_PROC
            and event.ident in (root_pid, target_pid)
            for event in initial
        ):
            raise RuntimeError("root or target exited before guard readiness")
        install_guard_signal_handlers(target_pid, group, state)
        os.write(ready_fd, b"R")
        while True:
            events = queue.control(None, 3, None)
            if any(
                event.filter == select.KQ_FILTER_PROC
                and event.ident == target_pid
                for event in events
            ):
                terminate_target(target_pid, group, state)
                os._exit(0)
            if any(
                event.filter == select.KQ_FILTER_PROC
                and event.ident == root_pid
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


    def run_guard(root_pid, target_pid, group, ready_fd, commit_fd):
        state = {"committed": False}
        try:
            # close_lock_fds() already ran before os.pipe(); calling it again
            # could close a protocol FD that reused descriptor 8 or 9.
            close_guard_descriptors(ready_fd, commit_fd)
            if sys.platform.startswith("linux"):
                guard_linux(
                    root_pid,
                    target_pid,
                    group,
                    ready_fd,
                    commit_fd,
                    state,
                )
            elif sys.platform == "darwin":
                guard_darwin(
                    root_pid,
                    target_pid,
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
            group,
            ready_write,
            commit_read,
        )
        os._exit(0)

    os.close(ready_write)
    os.close(commit_read)

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

    readable, _, _ = select.select(
        [ready_read], [], [], READY_TIMEOUT_SECONDS
    )
    ready = os.read(ready_read, 1) if readable else b""
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

    readable, _, _ = select.select(
        [ready_read], [], [], READY_TIMEOUT_SECONDS
    )
    acknowledged = os.read(ready_read, 1) if readable else b""
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
      (let ((environment process-environment)
            (stderr-tempfile (make-temp-file "anvil-direnv-stderr")))
        (unwind-protect
            (with-current-buffer (get-buffer-create direnv--output-buffer-name)
              (erase-buffer)
              (let* ((default-directory directory)
                     (process-environment environment)
                     (exit-code
                      (call-process
                       anvil-headless--direnv-executable nil
                       `(t ,stderr-tempfile) nil "export" "json")))
                (unless (and (integerp exit-code) (zerop exit-code))
                  ;; Do not copy stderr into the error: envrc output may
                  ;; contain project secrets.  The caller needs only a
                  ;; fail-closed result.
                  (error "direnv export failed"))
                (unless (zerop (buffer-size))
                  (goto-char (point-min))
                  (let ((json-key-type 'string)
                        (json-object-type 'alist))
                    (prog1 (json-read-object)
                      (skip-chars-forward " \t\r\n")
                      (unless (eobp)
                        (error "direnv export returned trailing output")))))))
          (delete-file stderr-tempfile))))

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
      '("DIRENV_DIFF" "DIRENV_DIR" "DIRENV_FILE" "DIRENV_WATCHES"))

    (defun anvil-headless--environment-with (environment name value)
      "Return a copy of ENVIRONMENT with NAME set to VALUE."
      (let ((process-environment (copy-sequence environment)))
        (setenv name value)
        process-environment))

    (defun anvil-headless--snapshot-baseline-environment ()
      "Freeze this daemon's imported login environment before any request."
      (let ((environment (copy-sequence process-environment)))
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
              anvil-headless--baseline-exec-path (copy-sequence exec-path)
              anvil-headless--baseline-shell-file-name shell-file-name
              anvil-headless--baseline-shell-command-switch
              shell-command-switch))
      (unless (and (listp anvil-headless--baseline-process-environment)
                   (listp anvil-headless--baseline-exec-path)
                   (stringp anvil-headless--baseline-shell-file-name)
                   (stringp anvil-headless--baseline-shell-command-switch))
        (error "Anvil could not snapshot its baseline environment")))

    (defun anvil-headless--strip-direnv-bookkeeping ()
      "Remove direnv's internal state from the current process environment."
      (dolist (name anvil-headless--direnv-bookkeeping-variables)
        (setenv name nil)))

    (defun anvil-headless--direnv-allowed-p (directory)
      "Return non-nil only when DIRECTORY has an explicitly allowed envrc."
      (condition-case nil
          (with-temp-buffer
            (let ((default-directory
                   (file-name-as-directory (expand-file-name directory)))
                  (coding-system-for-read 'utf-8-unix))
              (when
                  (zerop
                   (call-process
                    anvil-headless--direnv-executable nil (list t nil) nil
                    "status" "--json"))
                (let* ((document
                        (json-parse-string
                         (buffer-string)
                         :object-type 'hash-table
                         :array-type 'list
                         :null-object nil
                         :false-object nil))
                       (state (and (hash-table-p document)
                                   (gethash "state" document)))
                       (found (and (hash-table-p state)
                                   (gethash "foundRC" state))))
                  (and (hash-table-p found)
                       (eql (gethash "allowed" found) 0))))))
        (error nil)))

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
      (if (not (anvil-headless--direnv-allowed-p directory))
          (anvil-headless--restore-immutable-direnv-baseline)
        (condition-case nil
            (progn
              (let ((inhibit-message t)
                    (message-log-max nil)
                    (direnv-always-show-summary nil))
                (direnv-update-directory-environment directory))
              ;; Close the allow-hash race: if status changed while export
              ;; ran, discard the entire update rather than only its marker.
              (if (anvil-headless--direnv-allowed-p directory)
                  t
                (anvil-headless--restore-immutable-direnv-baseline)
                (when fail-on-export-error
                  (error "Allowed direnv environment changed during export"))
                nil))
          (error
           (anvil-headless--restore-immutable-direnv-baseline)
           (when fail-on-export-error
             (error "Allowed direnv environment failed to load"))
           nil))))

    (defun anvil-headless--direnv-update-current-buffer ()
      "Give a visited local file its own allowed direnv environment."
      (when-let ((directory (direnv--directory)))
        (unless (file-remote-p directory)
          (unless (and anvil-headless--baseline-process-environment
                       anvil-headless--baseline-exec-path)
            (error "Anvil baseline environment is unavailable"))
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
          (if (equal direnv--active-directory directory)
              ;; Recheck an already-loaded buffer: a newly blocked envrc must
              ;; lose both user variables and direnv bookkeeping immediately.
              (unless (anvil-headless--direnv-allowed-p directory)
                (anvil-headless--restore-immutable-direnv-baseline))
            (anvil-headless--apply-direnv-if-allowed directory)))))

    ;; `change-major-mode-after-body-hook' runs before the mode's own hook,
    ;; so Eglot, Flycheck, and similar mode-hook clients see the project env.
    ;; Refresh again before file-local variables and after visiting as guards
    ;; against modes that change `default-directory'.
    (add-hook 'change-major-mode-after-body-hook
              #'anvil-headless--direnv-update-current-buffer)
    (add-hook 'before-hack-local-variables-hook
              #'anvil-headless--direnv-update-current-buffer)
    (add-hook 'find-file-hook
              #'anvil-headless--direnv-update-current-buffer)

    (defun anvil-headless--direnv-around-host-run
        (original command coding cwd timeout)
      "Run ORIGINAL with a baseline-derived, allowed child environment."
      (unless (and anvil-headless--baseline-process-environment
                   anvil-headless--baseline-exec-path)
        (error "Anvil baseline environment is unavailable"))
      (let ((real-shell anvil-headless--baseline-shell-file-name)
            (child-process-environment
             (copy-sequence
              anvil-headless--baseline-process-environment))
            (child-exec-path
             (copy-sequence anvil-headless--baseline-exec-path)))
        (when (and cwd
                   (not (file-remote-p cwd))
                   (file-directory-p (expand-file-name cwd)))
          (with-temp-buffer
            (setq default-directory
                  (file-name-as-directory
                   (file-truename (expand-file-name cwd))))
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
          (funcall original command coding cwd timeout))))

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
    import math
    import os
    import signal
    import stat
    import sys
    import time

    EXIT_SOFTWARE = 70
    EXIT_CONFIG = 77
    LOCK_NAME = ".anvil-headless-emacs.lock"
    PULSE_NAME = ".anvil-root-pulse"
    LEASE_NAME = ".anvil-root-async-lease"
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


    def kill_parent_if(parent_pid, verifier):
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
        refresh_seconds,
        pulse_seconds,
        startup_seconds,
        normal_seconds,
        dispatch_seconds,
    ):
        try:
            null_fd = os.open(os.devnull, os.O_RDWR)
            for target in (0, 1, 2):
                os.dup2(null_fd, target)
            if null_fd > 2:
                os.close(null_fd)
            close_monitor_descriptors((pulse_entry[1], lease_entry[1]))

            poll_seconds = min(0.5, max(0.05, pulse_seconds / 2.0))
            started = time.monotonic()
            last_poll = started
            last_progress = None
            dispatch_started = None
            armed = False
            (
                pulse_generation,
                lease_generation,
                lease_state,
            ) = monitor_snapshot(pulse_entry, lease_entry)
            next_refresh = 0.0

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

                try:
                    validate_lock_files(lock_identities)
                    (
                        current_pulse,
                        current_lease,
                        current_lease_state,
                    ) = monitor_snapshot(pulse_entry, lease_entry)
                except BaseException:
                    def still_broken():
                        validate_lock_files(lock_identities)
                        monitor_snapshot(pulse_entry, lease_entry)
                        return False

                    kill_parent_if(parent_pid, still_broken)
                    continue

                if current_lease != lease_generation:
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

                        kill_parent_if(parent_pid, startup_still_expired)
                else:
                    if current_pulse != pulse_generation:
                        pulse_generation = current_pulse
                        last_progress = now

                    # Heartbeat and dispatch deadlines are independent.  A
                    # non-yielding handler stops the pulse; a recursive wait
                    # can keep timers alive but cannot outlive its dispatch.
                    heartbeat_expired = deadline_expired(
                        now, last_progress, normal_seconds
                    )
                    dispatch_expired = (
                        lease_state == "active"
                        and deadline_expired(
                            now, dispatch_started, dispatch_seconds
                        )
                    )
                    if heartbeat_expired or dispatch_expired:
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

                        kill_parent_if(parent_pid, activity_still_expired)

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

                        kill_parent_if(parent_pid, refresh_still_broken)
                    next_refresh = now + refresh_seconds
                time.sleep(poll_seconds)
        except BaseException:
            kill_parent_if(parent_pid, lambda: True)
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

    runtime_lock = acquire_lock(runtime_dir, 8, "runtime", lock_conflict_status)
    state_lock = acquire_lock(state_dir, 9, "state", lock_conflict_status)
    pulse_entry = open_monitor_file(
        runtime_dir, PULSE_NAME, b"pulse:boot\n", 0o600
    )
    lease_entry = open_monitor_file(
        runtime_dir, LEASE_NAME, b"lease\n", 0o400
    )
    os.environ["ANVIL_EMACS_WATCHDOG_PULSE_FILE"] = pulse_entry[0]
    os.environ["ANVIL_EMACS_WATCHDOG_LEASE_FILE"] = lease_entry[0]
    os.environ["ANVIL_EMACS_WATCHDOG_PULSE_SECONDS"] = str(pulse_seconds)

    parent_pid = os.getpid()
    try:
        monitor_pid = os.fork()
    except OSError as error:
        fail(f"cannot start root watchdog monitor: {error}")
    if monitor_pid == 0:
        monitor(
            parent_pid,
            (runtime_lock, state_lock),
            state_dir,
            pulse_entry,
            lease_entry,
            refresh_seconds,
            pulse_seconds,
            startup_seconds,
            normal_seconds,
            dispatch_seconds,
        )

    os.close(pulse_entry[1])
    os.close(lease_entry[1])
    try:
        os.execv(locked_stage, [locked_stage, runtime_dir, state_dir])
    except OSError as error:
        fail(f"cannot exec locked stage {locked_stage}: {error}")
  '';
  dedicatedInit = writeText "anvil-headless-init.el" ''
        ;;; anvil-headless-init.el --- Dedicated Anvil root -*- lexical-binding: t; -*-

        (defvar anvil-eval-timeout)
        (defvar anvil-eval-async-timeout)
        (defvar anvil-host--default-timeout)
        (defvar anvil-shell-filter-max-sync-timeout)
        (defvar anvil-worker-read-pool-size)
        (defvar anvil-worker-write-pool-size)
        (defvar anvil-worker-batch-pool-size)
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
        (declare-function anvil-headless--snapshot-baseline-environment nil ())
        (declare-function anvil-worker-kill "anvil-worker" ())
        (defvar anvil-headless--watchdog-pulse-file nil)
        (defvar anvil-headless--watchdog-lease-file nil)
        (defvar anvil-headless--watchdog-pulse-seconds nil)
        (defvar anvil-headless--watchdog-pulse-counter 0)
        (defvar anvil-headless--watchdog-timer nil)
        (defvar anvil-headless--watchdog-sync-dispatch-depth 0)

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
                anvil-shell-filter-max-sync-timeout ${toString timeoutPolicy.shellSyncSeconds}
                anvil-worker-read-pool-size ${toString workerPoolSizes.read}
                anvil-worker-write-pool-size ${toString workerPoolSizes.write}
                anvil-worker-batch-pool-size ${toString workerPoolSizes.batch}
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
              (anvil-headless--watchdog-arm))
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
      exec "${dedicatedRuntimeEmacs}/bin/emacs" \
        --quick \
        "--init-directory=$state_dir" \
        --fg-daemon=server \
        --directory "${dedicatedAnvil}/share/emacs/site-lisp" \
        --directory "${dedicatedAnvilIde}/share/emacs/site-lisp" \
        --load "${dedicatedInit}"
    '';
  };

  dedicatedDaemon = writeShellApplication {
    name = "anvil-headless-emacs";
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
  dedicatedAgentDaemon = if agentDaemonOverride == null then dedicatedDaemon else agentDaemonOverride;
  dedicatedGeneration = builtins.hashString "sha256" "${dedicatedAgentSupervisor}|${dedicatedParentGuardLauncher}|${dedicatedAgentDaemon}|${dedicatedAnvil}|${dedicatedAnvilIde}|${dedicatedOffloadEmacs}|${dedicatedOffloadInit}|${dedicatedSafeEmacsclient}|${generationSalt}";
  dedicatedLauncher = writeShellApplication {
    name = "anvil-mcp";
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
            echo "anvil-mcp ${currentAnvilVersion} (dedicated Emacs)"
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
        private_directory "$runtime_root" "runtime root"
        private_directory "$runtime_root/$short_host" "host runtime directory"
        private_directory "$state_root" "state root"
        private_directory "$state_root/$short_host" "host state directory"
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
              --grace-seconds "''${ANVIL_AGENT_GRACE_SECONDS:-5}" \
              --ready-seconds "''${ANVIL_AGENT_READY_SECONDS:-${toString timeoutPolicy.supervisorReadySeconds}}"
      ''}

      if [ -z "$socket" ]; then
        short_host="''${ANVIL_EMACS_HOST:-$(hostname -s)}"
        validate_host_component "$short_host"
        runtime_root="''${ANVIL_EMACS_RUNTIME_ROOT:-${defaultRuntimeRoot}}"
        runtime_dir="$runtime_root/$short_host"
        private_directory "$runtime_root" "runtime root"
        private_directory "$runtime_dir" "host runtime directory"
        socket="$runtime_dir/emacs/server"
      fi

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
      exec "${dedicatedAnvil}/share/emacs/site-lisp/anvil-stdio.sh" \
        "--socket=$socket" \
        "--server-id=$server_id"
    '';
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
        dedicatedDaemon
        dedicatedEmacs
        dedicatedEnvironmentInit
        dedicatedInit
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
        ;
      dedicatedAgentSupervisorSmoke = ./agent-supervisor-smoke.py;
      dedicatedAgentSupervisorTest = ./agent-supervisor-test.py;
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
        exec "${emacsPackages.anvil}/share/emacs/site-lisp/anvil-stdio.sh" \
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
