{
  bash,
  callPackage,
  coreutils,
  diffutils,
  emacs ? null,
  emacs30-nox ? emacs,
  emacsPackages ? null,
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

  nelispSrc = fetchFromGitHub {
    owner = "zawatton";
    repo = "nelisp";
    rev = nelispRev;
    hash = "sha256-m90HzB7fNnibaIDFaPr8RufhMS86PQJWTEHKopxh32Q=";
  };

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

    cargoLock.lockFile = "${nelispSrc}/Cargo.lock";
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

        export NELISP_SRC_DIR="${nelispSrc}/src"
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

  dedicatedWorkerInit = writeText "anvil-headless-worker-init.el" ''
    ;;; anvil-headless-worker-init.el --- Isolated Anvil worker

    (let* ((state-root (getenv "ANVIL_EMACS_STATE_DIR"))
           (worker-name (format "%s" (or (daemonp) "worker")))
           (state-dir
            (and state-root
                 (expand-file-name
                  (concat "workers/" worker-name "/") state-root)))
           (temp-dir
            (and state-dir (expand-file-name "tmp/" state-dir)))
           (cache-dir
            (and state-dir (expand-file-name "cache/" state-dir))))
      (unless state-dir
        (error "ANVIL_EMACS_STATE_DIR is required for Anvil workers"))
      (make-directory temp-dir t)
      (make-directory cache-dir t)
      (setenv "TMPDIR" temp-dir)
      (setenv "TMP" temp-dir)
      (setenv "TEMP" temp-dir)
      (setenv "XDG_CACHE_HOME" cache-dir)
      (setq user-emacs-directory (file-name-as-directory state-dir)
            package-user-dir (expand-file-name "elpa" state-dir)
            custom-file (expand-file-name "custom.el" state-dir)
            temporary-file-directory (file-name-as-directory temp-dir)
            anvil-server-schema-cache-file
            (expand-file-name "anvil-schema-cache.el" temp-dir))
      (when (fboundp 'startup-redirect-eln-cache)
        (startup-redirect-eln-cache
         (expand-file-name "eln-cache/" state-dir))))

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
  '';

  dedicatedInit = writeText "anvil-headless-init.el" ''
    (let* ((state-dir (getenv "ANVIL_EMACS_STATE_DIR"))
           (temp-dir (and state-dir (expand-file-name "tmp/" state-dir)))
           (org-root
            (file-name-as-directory
             (expand-file-name
              (or (getenv "ANVIL_EMACS_ORG_ROOT") "~/org")))))
      (unless (and state-dir (file-directory-p state-dir))
        (error "ANVIL_EMACS_STATE_DIR must name an existing directory"))
      (make-directory temp-dir t)
      (setq user-emacs-directory (file-name-as-directory state-dir)
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
          (setq anvil-pdf-python "${pythonWithPyMuPDF}/bin/python3"
                anvil-worker-emacs-bin "${dedicatedEmacs}/bin/emacs"
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

  dedicatedDaemon = writeShellApplication {
    name = "anvil-headless-emacs";
    runtimeInputs = [
      bash
      coreutils
      dedicatedEmacs
      diffutils
      findutils
      gawk
      git
      gnugrep
      gnused
      hostname
      pythonWithPyMuPDF
      ripgrep
    ];
    text = ''
      short_host="''${ANVIL_EMACS_HOST:-$(hostname -s)}"

      runtime_root="''${ANVIL_EMACS_RUNTIME_ROOT:-${defaultRuntimeRoot}}"
      runtime_dir="$runtime_root/$short_host"
      state_root="''${ANVIL_EMACS_STATE_ROOT:-/var/tmp/anvil-emacs-$(id -u)}"
      state_dir="$state_root/$short_host"

      install -d -m 0700         "$runtime_dir"         "$state_dir"         "$state_dir/cache"         "$state_dir/tmp"

      export XDG_RUNTIME_DIR="$runtime_dir"
      export XDG_CACHE_HOME="$state_dir/cache"
      export ANVIL_EMACS_STATE_DIR="$state_dir"
      export TMPDIR="$state_dir/tmp"
      export TMP="$TMPDIR"
      export TEMP="$TMPDIR"

      exec "${dedicatedEmacs}/bin/emacs"         --quick         --fg-daemon=server         --directory "${dedicatedAnvil}/share/emacs/site-lisp"         --directory "${dedicatedAnvilIde}/share/emacs/site-lisp"         --load "${dedicatedInit}"
    '';
  };

  dedicatedLauncher = writeShellApplication {
    name = "anvil-mcp";
    runtimeInputs = [
      bash
      coreutils
      dedicatedEmacs
      gawk
      gnugrep
      gnused
      hostname
    ];
    text = ''
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
        runtime_root="''${ANVIL_EMACS_RUNTIME_ROOT:-${defaultRuntimeRoot}}"
        socket="$runtime_root/$short_host/emacs/server"
      fi

      ready=
      for _ in $(seq 1 120); do
        if [ -S "$socket" ]           && "${dedicatedEmacs}/bin/emacsclient" -s "$socket" -e t >/dev/null 2>&1; then
          ready=1
          break
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
        dedicatedDaemon
        dedicatedEmacs
        dedicatedInit
        dedicatedWorkerInit
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
