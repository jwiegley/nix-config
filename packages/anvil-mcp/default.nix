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
        patches = [ ../../overlays/emacs/patches/anvil-worker-pool.patch ];
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
      exec "$real_shell" "$@"
    '';
  };

  dedicatedEnvironmentInit = writeText "anvil-headless-environment-init.el" ''
    ;;; anvil-headless-environment-init.el --- Project environment support -*- lexical-binding: t; -*-

    (require 'exec-path-from-shell)
    (require 'direnv)
    (require 'json)
    (require 'seq)
    (setq direnv-always-show-summary nil)

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

    (defun anvil-headless--direnv-update-current-buffer ()
      "Give a visited local file its own direnv-derived process environment."
      (when-let ((directory (direnv--directory)))
        (unless (file-remote-p directory)
          (unless (local-variable-p 'process-environment)
            (setq-local process-environment
                        (copy-sequence
                         (default-value 'process-environment))))
          (unless (local-variable-p 'exec-path)
            (setq-local exec-path
                        (copy-sequence (default-value 'exec-path))))
          (unless (local-variable-p 'direnv--active-directory)
            (setq-local direnv--active-directory nil))
          (unless (equal direnv--active-directory directory)
            (direnv-update-directory-environment directory)))))

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
      "Run ORIGINAL with CWD's buffer-local direnv and closed lock fds."
      (let ((real-shell (or shell-file-name "/bin/sh"))
            (child-process-environment (copy-sequence process-environment))
            (child-exec-path (copy-sequence exec-path)))
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
            ;; direnv.el treats a blocked or missing envrc as an unchanged
            ;; environment.  Keep its diagnostic chatter out of MCP results.
            (condition-case nil
                (let ((inhibit-message t)
                      (message-log-max nil)
                      (direnv-always-show-summary nil))
                  (direnv-update-directory-environment default-directory))
              (error nil))
            (anvil-headless--restore-required-exec-path)
            (setq child-process-environment
                  (copy-sequence process-environment)
                  child-exec-path (copy-sequence exec-path))))
        (let ((process-environment child-process-environment)
              (exec-path child-exec-path)
              (shell-file-name
               "${dedicatedChildShell}/bin/anvil-headless-child-shell"))
          (setenv "ANVIL_HEADLESS_REAL_SHELL" real-shell)
          (funcall original command coding cwd timeout))))

    (with-eval-after-load 'anvil-host
      (advice-add 'anvil-host--run
                  :around #'anvil-headless--direnv-around-host-run))
  '';

  dedicatedWorkerInit = writeText "anvil-headless-worker-init.el" ''
    ;;; anvil-headless-worker-init.el --- Isolated Anvil worker -*- lexical-binding: t; -*-

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
      # descriptions before worker Emacs starts so only the root owns them.
      exec 8<&- 9<&-
      export ANVIL_EMACS_WORKER=1
      exec "${dedicatedRuntimeEmacs}/bin/emacs" "$@"
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
    DEFAULT_REFRESH_SECONDS = 6 * 60 * 60


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


    def heartbeat_fail_closed(parent_pid):
        # Do not signal a stale or reused PID after the heartbeat is reparented.
        if os.getppid() == parent_pid:
            try:
                os.kill(parent_pid, signal.SIGKILL)
            except OSError:
                pass
        os._exit(0)


    def heartbeat(parent_pid, lock_identities, refresh_seconds):
        try:
            null_fd = os.open(os.devnull, os.O_RDWR)
            for target in (0, 1, 2):
                os.dup2(null_fd, target)
            if null_fd > 2:
                os.close(null_fd)
            # Close the OFD-lock descriptions at 8 and 9, plus any other
            # daemon/service descriptors inherited before exec.
            os.closerange(3, 256)
            next_refresh = 0.0
            poll_seconds = min(1.0, max(0.05, refresh_seconds))
            while os.getppid() == parent_pid:
                now = time.monotonic()
                refresh_due = now >= next_refresh
                for lock_path, expected in lock_identities:
                    info = os.stat(lock_path, follow_symlinks=False)
                    if (
                        not stat.S_ISREG(info.st_mode)
                        or (info.st_dev, info.st_ino) != expected
                    ):
                        heartbeat_fail_closed(parent_pid)
                    if refresh_due:
                        os.utime(lock_path, follow_symlinks=False)
                if refresh_due:
                    next_refresh = now + refresh_seconds
                time.sleep(poll_seconds)
        except BaseException:
            heartbeat_fail_closed(parent_pid)
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

    try:
        refresh_seconds = float(
            os.environ.get(
                "ANVIL_EMACS_LOCK_REFRESH_SECONDS",
                str(DEFAULT_REFRESH_SECONDS),
            )
        )
    except ValueError:
        fail("ANVIL_EMACS_LOCK_REFRESH_SECONDS must be numeric", EXIT_CONFIG)
    if not math.isfinite(refresh_seconds) or refresh_seconds <= 0:
        fail(
            "ANVIL_EMACS_LOCK_REFRESH_SECONDS must be positive and finite",
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
    parent_pid = os.getpid()
    try:
        heartbeat_pid = os.fork()
    except OSError as error:
        fail(f"cannot start lock refresh heartbeat: {error}")
    if heartbeat_pid == 0:
        heartbeat(parent_pid, (runtime_lock, state_lock), refresh_seconds)

    try:
        os.execv(locked_stage, [locked_stage, runtime_dir, state_dir])
    except OSError as error:
        fail(f"cannot exec locked stage {locked_stage}: {error}")
  '';
  dedicatedInit = writeText "anvil-headless-init.el" ''
    ;;; anvil-headless-init.el --- Dedicated Anvil root -*- lexical-binding: t; -*-

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

    (require 'anvil)
    (require 'anvil-server-commands)

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

    (advice-add 'anvil-server-register-tool
                :around #'anvil-headless--mirror-typed-tool)
    (advice-add 'anvil-server-unregister-tool
                :around #'anvil-headless--mirror-typed-unregister)
    (anvil-headless--mirror-existing-typed-tools)

    (condition-case err
        (progn
          (load "${dedicatedEnvironmentInit}" nil nil t)
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
          (add-hook 'kill-emacs-hook #'anvil-worker-kill)
          (anvil-server-start))
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
      runtime_dir="$runtime_root/$short_host"
      state_root="''${ANVIL_EMACS_STATE_ROOT:-/var/tmp/anvil-emacs-$(id -u)}"
      state_dir="$state_root/$short_host"
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
        direnv
        dedicatedWorkerEmacs
        dedicatedWorkerInit
        workerNames
        workerPoolSizes
        workerSpecs
        ;
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
