{
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
}:

let
  nelispVersion = "0.5.1";
  nelispRev = "f753209d53b372933b829345fe4373acad67bcb5";
  standaloneAnvilVersion = "1.1.1";
  standaloneAnvilRev = "d50ce32b71c5fa46da3aa661481c8be44fee4f97";
  currentAnvilVersion = "1.3.0";
  currentAnvilRev = "574568a95a2bd8fceca6c9cd3bec0f94ecf0e6a9";
  anvilIdeRev = "0e6130457ac2bdc6c6db2eebeba67a5223231190";

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
    owner = "zawatton";
    repo = "anvil.el";
    rev = currentAnvilRev;
    hash = "sha256-z/wYZKkXyE3/7d6MSZ4RJpXcxBGyMdrx6Ndid7Yz5iw=";
  };

  anvilIdeSrc = fetchFromGitHub {
    owner = "zawatton";
    repo = "anvil-ide.el";
    rev = anvilIdeRev;
    hash = "sha256-L9heDjSvttZQyCxUq9n104YnhelL8XtivHOl2ln+2aI=";
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

  dedicatedLockedRuntimeInputs = [
    bash
    coreutils
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
        patches = [
          # Load-bearing order: host-child bindings target the issue-53 host.
          ../../overlays/emacs/patches/anvil-issue-53-hang-fixes.patch
          ../../overlays/emacs/patches/anvil-worker-pool.patch
          ../../overlays/emacs/patches/anvil-host-child-bindings.patch
          ../../overlays/emacs/patches/anvil-root-watchdog.patch
          ../../overlays/emacs/patches/anvil-stdio-at-most-once.patch
        ];
        src = currentAnvilSrc;
      }).overrideAttrs
        (attrs: {
          installPhase = attrs.installPhase + ''
            install -m755 anvil-stdio.sh "$out/share/emacs/site-lisp"
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
    READY_TIMEOUT_SECONDS = 5.0


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


    def terminate_target(target_pid, group):
        try:
            if group:
                # The PGID remains allocated while any non-detached member
                # survives, even after the shell leader itself has exited.
                os.killpg(target_pid, signal.SIGKILL)
            else:
                os.kill(target_pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        except OSError:
            pass


    def move_guard_out_of_target_group(target_pid):
        guard_pid = os.getpid()
        if os.getpgrp() != guard_pid:
            os.setpgid(0, 0)
        if os.getpgrp() != guard_pid or os.getpgrp() == target_pid:
            raise RuntimeError("guard does not own a distinct process group")


    def close_guard_descriptors(ready_fd):
        null_fd = os.open(os.devnull, os.O_RDWR)
        for descriptor in (0, 1, 2):
            os.dup2(null_fd, descriptor)
        if null_fd > 2 and null_fd != ready_fd:
            os.close(null_fd)
        try:
            descriptor_limit = int(os.sysconf("SC_OPEN_MAX"))
        except (OSError, TypeError, ValueError):
            descriptor_limit = 65536
        descriptor_limit = max(256, min(descriptor_limit, 1048576))
        os.closerange(3, ready_fd)
        os.closerange(ready_fd + 1, descriptor_limit)


    def install_guard_signal_handlers(target_pid, group):
        handled = (signal.SIGINT, signal.SIGHUP, signal.SIGTERM)
        if hasattr(signal, "pthread_sigmask"):
            signal.pthread_sigmask(signal.SIG_UNBLOCK, handled)

        def stop_guard(_signum, _frame):
            terminate_target(target_pid, group)
            os._exit(0)

        for signum in handled:
            signal.signal(signum, stop_guard)


    def guard_linux(root_pid, target_pid, group, ready_fd):
        root_fd = os.pidfd_open(root_pid, 0)
        target_fd = os.pidfd_open(target_pid, 0)
        poller = select.poll()
        poller.register(root_fd, select.POLLIN)
        poller.register(target_fd, select.POLLIN)
        if poller.poll(0):
            raise RuntimeError("root or target exited before guard readiness")
        install_guard_signal_handlers(target_pid, group)
        os.write(ready_fd, b"R")
        os.close(ready_fd)
        while True:
            for descriptor, _event in poller.poll():
                if descriptor == root_fd:
                    terminate_target(target_pid, group)
                    os._exit(0)
                if descriptor == target_fd:
                    if group:
                        terminate_target(target_pid, True)
                    os._exit(0)


    def guard_darwin(root_pid, target_pid, group, ready_fd):
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
        ]
        queue.control(changes, 0, 0)
        if queue.control(None, 2, 0):
            raise RuntimeError("root or target exited before guard readiness")
        install_guard_signal_handlers(target_pid, group)
        os.write(ready_fd, b"R")
        os.close(ready_fd)
        while True:
            for event in queue.control(None, 2, None):
                if event.ident == root_pid:
                    terminate_target(target_pid, group)
                    os._exit(0)
                if event.ident == target_pid:
                    if group:
                        terminate_target(target_pid, True)
                    os._exit(0)


    def run_guard(root_pid, target_pid, group, ready_fd):
        try:
            close_guard_descriptors(ready_fd)
            close_lock_fds()
            move_guard_out_of_target_group(target_pid)
            if sys.platform.startswith("linux"):
                guard_linux(root_pid, target_pid, group, ready_fd)
            elif sys.platform == "darwin":
                guard_darwin(root_pid, target_pid, group, ready_fd)
            else:
                raise RuntimeError(f"unsupported platform: {sys.platform}")
        except BaseException:
            terminate_target(target_pid, group)
            try:
                os.close(ready_fd)
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
    if group and os.getpgrp() != target_pid:
        try:
            os.setpgid(0, 0)
        except OSError as error:
            fail(f"cannot establish target process group: {error}")
    if group and os.getpgrp() != target_pid:
        fail("target is not its process-group leader")

    ready_read, ready_write = os.pipe()
    try:
        guard_pid = os.fork()
    except OSError as error:
        fail(f"cannot fork guard: {error}")

    if guard_pid == 0:
        os.close(ready_read)
        run_guard(root_pid, target_pid, group, ready_write)
        os._exit(0)

    os.close(ready_write)
    readable, _, _ = select.select(
        [ready_read], [], [], READY_TIMEOUT_SECONDS
    )
    ready = os.read(ready_read, 1) if readable else b""
    os.close(ready_read)
    if ready != b"R":
        terminate_target(guard_pid, False)
        try:
            os.waitpid(guard_pid, 0)
        except ChildProcessError:
            pass
        fail("guard did not become ready")
    if os.getppid() != root_pid:
        os.kill(os.getpid(), signal.SIGKILL)

    try:
        os.execvpe(program_argv[0], program_argv, os.environ)
    except OSError as error:
        terminate_target(guard_pid, False)
        fail(f"cannot exec {program_argv[0]}: {error}")
  '';

  dedicatedAgentSupervisor = writeText "anvil-agent-supervisor.py" (
    builtins.readFile ./agent-supervisor.py
  );

  dedicatedChildShell = writeShellApplication {
    name = "anvil-headless-child-shell";
    text = ''
      real_shell="''${ANVIL_HEADLESS_REAL_SHELL:-}"
      if [ -z "$real_shell" ]; then
        echo "anvil-mcp: missing real shell for dedicated child" >&2
        exit 70
      fi
      exec 8<&- 9<&-
      unset ANVIL_HEADLESS_REAL_SHELL
      exec "${python3}/bin/python3" -I -S "${dedicatedParentGuardLauncher}" \
        group "$real_shell" "$@"
    '';
  };

  dedicatedEnvironmentInit = writeText "anvil-headless-environment-init.el" ''
    ;;; anvil-headless-environment-init.el --- Project environment support -*- lexical-binding: t; -*-

    (require 'exec-path-from-shell)
    (require 'direnv)
    ;; json-parse-string decodes the pinned direnv status gate below.
    (require 'json)
    (setq direnv-always-show-summary nil)

    ;; These variables are defined by the packaged anvil-host patch.  Bare
    ;; declarations make the bindings below dynamic under lexical compilation.
    (defvar anvil-host-child-process-environment)
    (defvar anvil-host-child-exec-path)
    (defvar anvil-host-child-shell-file-name)
    (defvar anvil-host-child-shell-command-switch)

    (defvar anvil-headless--baseline-process-environment nil)
    (defvar anvil-headless--baseline-exec-path nil)
    (defvar anvil-headless--baseline-shell-file-name nil)
    (defvar anvil-headless--baseline-shell-command-switch nil)

    (defconst anvil-headless--emacs-bin-directory
      (file-name-as-directory "${dedicatedRuntimeEmacs}/bin")
      "Directory containing the dedicated Emacs and emacsclient binaries.")

    (defconst anvil-headless--direnv-executable
      "${direnv}/bin/direnv"
      "Pinned direnv executable for the dedicated Anvil environment.")

    ;; Append only known packaged tools after login/project paths.  Do not
    ;; resurrect arbitrary PATH entries inherited from launchd or a caller.
    (defconst anvil-headless--required-exec-path
      '(${lib.concatMapStringsSep "\n        " builtins.toJSON dedicatedRequiredExecPath}))

    (defun anvil-headless--restore-required-exec-path (&rest _args)
      "Keep dedicated Emacs and packaged tools reachable after PATH changes."
      (let* ((normalized
              (delete-dups
               (mapcar
                (lambda (directory)
                  (if (stringp directory)
                      (directory-file-name directory)
                    directory))
                exec-path)))
             (emacs-bin
              (directory-file-name anvil-headless--emacs-bin-directory)))
        (setq exec-path (cons emacs-bin (delete emacs-bin normalized))))
      (dolist (directory anvil-headless--required-exec-path)
        (unless (member directory exec-path)
          (setq exec-path (append exec-path (list directory)))))
      (let ((path (mapconcat #'identity exec-path
                             path-separator)))
        (setenv "PATH" path)
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
    (advice-add 'direnv-update-directory-environment
                :after #'anvil-headless--restore-required-exec-path)

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

    (defun anvil-headless--apply-direnv-if-allowed (directory)
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
                (anvil-headless--restore-immutable-direnv-baseline)))
          (error
           (anvil-headless--restore-immutable-direnv-baseline)))))

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
            (anvil-headless--apply-direnv-if-allowed default-directory)
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
        ;; These special variables remain dynamically visible while ORIGINAL
        ;; waits, but the anvil-host patch applies their values only inside
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

  dedicatedWorkerEmacs = writeShellApplication {
    name = "anvil-worker-emacs";
    text = ''
      # Fds 8/9 carry the root daemon's OFD locks.  Close the inherited
      # descriptions before starting the exact-PID worker containment guard.
      exec 8<&- 9<&-
      export ANVIL_EMACS_WORKER=1
      exec "${python3}/bin/python3" -I -S "${dedicatedParentGuardLauncher}" \
        exact "${dedicatedRuntimeEmacs}/bin/emacs" "$@"
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
    DEFAULT_STARTUP_SECONDS = 120
    DEFAULT_NORMAL_SECONDS = 45
    DEFAULT_ASYNC_SECONDS = 600
    DEFAULT_PULSE_SECONDS = 1


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
        lease_started,
    ):
        elapsed_since_poll = now - last_poll
        if elapsed_since_poll <= 3.0 * poll_seconds:
            return started, last_progress, lease_started
        unexpected_gap = max(0.0, elapsed_since_poll - poll_seconds)
        return tuple(
            None if anchor is None else anchor + unexpected_gap
            for anchor in (started, last_progress, lease_started)
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
        async_seconds,
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
            lease_started = None
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
                    lease_started,
                ) = compensate_scheduler_gap(
                    now,
                    last_poll,
                    poll_seconds,
                    started,
                    last_progress,
                    lease_started,
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
                    lease_started = now if lease_state == "active" else None
                else:
                    lease_state = current_lease_state

                if not armed:
                    if current_pulse != pulse_generation:
                        armed = True
                        pulse_generation = current_pulse
                        last_progress = now
                        if lease_state == "active":
                            lease_started = now
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

                    deadline_start = (
                        lease_started
                        if lease_state == "active"
                        else last_progress
                    )
                    deadline_seconds = (
                        async_seconds
                        if lease_state == "active"
                        else normal_seconds
                    )
                    if deadline_expired(
                        now, deadline_start, deadline_seconds
                    ):
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
                                and deadline_expired(
                                    time.monotonic(),
                                    deadline_start,
                                    deadline_seconds,
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
    async_seconds = positive_seconds(
        "ANVIL_EMACS_WATCHDOG_ASYNC_SECONDS", DEFAULT_ASYNC_SECONDS
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
    if async_seconds < normal_seconds:
        fail(
            "ANVIL_EMACS_WATCHDOG_ASYNC_SECONDS must not be shorter "
            "than the normal deadline",
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
            async_seconds,
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
    (defvar anvil-eval-async-active-function)
    (defvar anvil-eval-async-idle-function)
    (defvar anvil-eval-async-cleanup-failure-function)
    (defvar anvil-headless--watchdog-pulse-file nil)
    (defvar anvil-headless--watchdog-lease-file nil)
    (defvar anvil-headless--watchdog-pulse-seconds nil)
    (defvar anvil-headless--watchdog-pulse-counter 0)
    (defvar anvil-headless--watchdog-timer nil)

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
            anvil-eval-timeout 120
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

    (defun anvil-headless--watchdog-async-active (_job-id)
      "Extend the watchdog lease while an async job is evaluating."
      (anvil-headless--watchdog-set-lease-state t))

    (defun anvil-headless--watchdog-async-idle (_job-id)
      "Return the watchdog lease to idle after an async job."
      (anvil-headless--watchdog-set-lease-state nil))

    (defun anvil-headless--watchdog-cleanup-failed (job-id error-data)
      "Fail the dedicated daemon closed after JOB-ID cleanup ERROR-DATA."
      (message "Anvil async watchdog cleanup failed for %s: %S"
               job-id error-data)
      (kill-emacs 70))

    (defun anvil-headless--watchdog-arm ()
      "Arm the external root watchdog after the MCP server is ready."
      (setq anvil-headless--watchdog-pulse-file
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

    ;; Keep promptdeploy's one universal "anvil" registration complete in
    ;; dedicated mode.  The upstream split "emacs-eval" registry remains
    ;; intact for direct diagnostics and the existing Darwin typed server.
    (defvar anvil-headless--registering-tool nil)

    (defun anvil-headless--mirror-typed-tool (original handler &rest args)
      (let ((outermost (not anvil-headless--registering-tool))
            (anvil-headless--registering-tool t))
        (let ((result (apply original handler args)))
          (when (and outermost
                     (equal (plist-get args :server-id) "emacs-eval"))
            (let* ((tool-id (plist-get args :id))
                   (typed-tools
                    (anvil-server--get-server-tools "emacs-eval"))
                   (tool (gethash tool-id typed-tools))
                   (main-tools
                    (anvil-server--get-server-tools "anvil")))
              (unless tool
                (error "Anvil typed tool disappeared after registration: %s"
                       tool-id))
              (puthash tool-id (copy-sequence tool) main-tools)
              (anvil-server--tools-list-cache-invalidate "anvil")))
          result)))

    (defun anvil-headless--mirror-typed-unregister
        (original tool-id &optional server-id)
      (let ((result (funcall original tool-id server-id)))
        (when (equal server-id "emacs-eval")
          (funcall original tool-id "anvil"))
        result))

    (defun anvil-headless--mirror-existing-typed-tools ()
      (let ((typed-tools
             (anvil-server--get-server-tools "emacs-eval"))
            (main-tools
             (anvil-server--get-server-tools "anvil")))
        (maphash
         (lambda (tool-id tool)
           (anvil-server--ref-counted-register
            tool-id (copy-sequence tool) main-tools))
         typed-tools)
        (anvil-server--tools-list-cache-invalidate "anvil")))

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
             (copy-sequence anvil-headless--baseline-exec-path)))
        (setenv "ANVIL_HEADLESS_REAL_SHELL" nil)
        (setenv "ANVIL_HEADLESS_PARENT_PID" nil)
        (setenv "ANVIL_HEADLESS_PARENT_PID"
                (number-to-string (emacs-pid)))
        (apply original args)))

    (advice-add 'anvil-server-register-tool
                :around #'anvil-headless--mirror-typed-tool)
    (advice-add 'anvil-server-unregister-tool
                :around #'anvil-headless--mirror-typed-unregister)
    (anvil-headless--mirror-existing-typed-tools)

    (condition-case err
        (progn
          (load "${dedicatedEnvironmentInit}" nil nil t)
          (anvil-headless--snapshot-baseline-environment)
          (setq anvil-pdf-python "${pythonWithPyMuPDF}/bin/python3"
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
          (anvil-enable)
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
          (setq anvil-eval-async-active-function
                #'anvil-headless--watchdog-async-active
                anvil-eval-async-idle-function
                #'anvil-headless--watchdog-async-idle
                anvil-eval-async-cleanup-failure-function
                #'anvil-headless--watchdog-cleanup-failed)
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
      export TMPDIR="$runtime_dir/tmp"
      export TMP="$TMPDIR"
      export TEMP="$TMPDIR"

      exec "${dedicatedRuntimeEmacs}/bin/emacs"         --quick         --fg-daemon=server         --directory "${dedicatedAnvil}/share/emacs/site-lisp"         --directory "${dedicatedAnvilIde}/share/emacs/site-lisp"         --load "${dedicatedInit}"
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
        ANVIL_HEADLESS_PARENT_PID="$PPID" \
          exec "${python3}/bin/python3" -I -S \
            "${dedicatedParentGuardLauncher}" external-group \
            "${python3}/bin/python3" -I -S "${dedicatedAgentSupervisor}" \
              --server-id "$server_id" \
              --host "$short_host" \
              --runtime-root "$runtime_root" \
              --state-root "$state_root" \
              --daemon "${dedicatedDaemon}/bin/anvil-headless-emacs" \
              --stdio "${dedicatedAnvil}/share/emacs/site-lisp/anvil-stdio.sh" \
              --emacsclient "${dedicatedRuntimeEmacs}/bin/emacsclient" \
              --python "${python3}/bin/python3" \
              --parent-guard "${dedicatedParentGuardLauncher}" \
              --grace-seconds "''${ANVIL_AGENT_GRACE_SECONDS:-5}" \
              --ready-seconds "''${ANVIL_AGENT_READY_SECONDS:-120}"
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

      ready=
      for _ in $(seq 1 120); do
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
          if [ "$socket_owner" != "$(id -u)" ]; then
            echo "anvil-mcp: Emacs socket must be owned by uid $(id -u) (found $socket_owner): $socket" >&2
            exit 77
          fi
          if "${dedicatedRuntimeEmacs}/bin/emacsclient" -s "$socket" -e t >/dev/null 2>&1; then
            ready=1
            break
          fi
        fi
        sleep 0.25
      done
      if [ -z "$ready" ]; then
        echo "anvil-mcp: dedicated Emacs did not become ready at $socket" >&2
        exit 69
      fi

      exec "${dedicatedAnvil}/share/emacs/site-lisp/anvil-stdio.sh"         "--socket=$socket"         "--server-id=$server_id"
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
        dedicatedRuntimeEmacs
        dedicatedAgentSupervisor
        direnv
        dedicatedWorkerEmacs
        dedicatedWorkerInit
        workerNames
        workerPoolSizes
        workerSpecs
        ;
      dedicatedAgentSupervisorSmoke = ./agent-supervisor-smoke.py;
      dedicatedAgentSupervisorTest = ./agent-supervisor-test.py;
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
        gnugrep
        gnused
      ];
      text = ''
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

        exec "${emacsPackages.anvil}/share/emacs/site-lisp/anvil-stdio.sh"           "--socket=$socket"           "--server-id=$server_id"
      '';
    }).overrideAttrs
      (_old: {
        pname = "anvil-mcp";
        version = currentAnvilVersion;
        passthru = {
          backend = "interactive-emacs";
          inherit currentAnvilRev currentAnvilVersion;
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
