{
  anvilMcp,
  bash,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  lib,
  python3,
  runCommand,
  unixtools,
  writeShellApplication,
}:

let
  inherit (anvilMcp) workerNames;
  hostAnvilMcp = anvilMcp.override { usePerAgentDaemon = false; };
  rolloverAnvilMcp = anvilMcp.override { generationSalt = "rollover"; };
  readinessCrashDaemon = writeShellApplication {
    name = "anvil-headless-emacs";
    runtimeInputs = [ coreutils ];
    text = ''
      sentinel="$ANVIL_EMACS_RUNTIME_DIR/.readiness-crashed-once"
      if [ ! -e "$sentinel" ]; then
        : >"$sentinel"
        exit 70
      fi
      exec ${anvilMcp}/bin/anvil-headless-emacs
    '';
  };
  readinessCrashAnvilMcp = anvilMcp.override {
    agentDaemonOverride = readinessCrashDaemon;
    generationSalt = "readiness-crash";
  };
  firstWorker = builtins.head workerNames;
  expectedWorkerCount = 2 * builtins.length workerNames;
  workerSpecsJson = builtins.toJSON anvilMcp.workerSpecs;
  timeoutPolicyJson = lib.escapeShellArg (builtins.toJSON anvilMcp.timeoutPolicy);
in
runCommand "anvil-mcp-dedicated-smoke"
  {
    nativeBuildInputs = [
      anvilMcp
      anvilMcp.dedicatedEmacs
      coreutils
      findutils
      gnugrep
      gnused
      hostAnvilMcp
      python3
      readinessCrashAnvilMcp
      rolloverAnvilMcp
    ];
  }
  ''
    smoke_root=$(mktemp -d /tmp/anvil-mcp-smoke.XXXXXX)
    export HOME="$smoke_root/home"
    export ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/runtime"
    export ANVIL_EMACS_STATE_ROOT="$smoke_root/state"
    export ANVIL_EMACS_LOCK_REFRESH_SECONDS=0.2
    export ANVIL_PER_AGENT_LAUNCHER="${anvilMcp}/bin/anvil-mcp"
    export SHELL="${bash}/bin/bash"
    # Host-daemon tests below use an explicit package variant; the per-agent
    # launcher has no identity-dependent fallback path.
    install -d -m 0700 "$HOME" "$HOME/org"
    printf '%s\n' '* Headless Anvil' 'headlessorgneedle headlesssemanticneedle'       >"$HOME/org/smoke.org"

    install -d -m 0700 "$HOME/login-bin"
    printf '%s\n' '#!/bin/sh' 'printf login-shell-command' \
      >"$HOME/login-bin/anvil-login-shell"
    chmod 0700 "$HOME/login-bin/anvil-login-shell"
    printf '%s\n' \
      'case "$-" in *i*) exit 42 ;; esac' \
      'export PATH="$HOME/login-bin:$PATH"' \
      >"$HOME/.bash_profile"

    install -d -m 0700 \
      "$HOME/direnv-a" "$HOME/direnv-a/bin" \
      "$HOME/direnv-b" "$HOME/direnv-b/bin" \
      "$HOME/direnv-c" "$HOME/direnv-c/bin" \
      "$HOME/direnv-unset" "$HOME/direnv-unset/bin" \
      "$HOME/direnv-spoof" "$HOME/direnv-spoof/bin" \
      "$HOME/direnv-blocked" \
      "$HOME/direnv-plain"
    printf '%s\n' \
      'export ANVIL_DIRENV_MARKER=project-a' \
      'PATH_add "$PWD/bin"' \
      >"$HOME/direnv-a/.envrc"
    printf '%s\n' \
      'export ANVIL_DIRENV_MARKER=project-b' \
      'PATH_add "$PWD/bin"' \
      >"$HOME/direnv-b/.envrc"
    printf '%s\n' \
      'export ANVIL_DIRENV_MARKER=project-c' \
      'export PATH="$PWD/bin"' \
      >"$HOME/direnv-c/.envrc"
    printf '%s\n' \
      'unset ANVIL_EMACS_SOCKET' \
      'export ANVIL_DIRENV_MARKER=project-unset' \
      'PATH_add "$PWD/bin"' \
      >"$HOME/direnv-unset/.envrc"
    printf '%s\n' \
      'export ANVIL_EMACS_SOCKET="$PWD/spoofed-root"' \
      'export ANVIL_DIRENV_MARKER=project-spoof' \
      'PATH_add "$PWD/bin"' \
      >"$HOME/direnv-spoof/.envrc"
    printf '%s\n' 'export ANVIL_DIRENV_MARKER=blocked' \
      >"$HOME/direnv-blocked/.envrc"
    printf '%s\n' '#!/bin/sh' 'printf project-a-command' \
      >"$HOME/direnv-a/bin/anvil-direnv-a"
    printf '%s\n' '#!/bin/sh' 'printf project-b-command' \
      >"$HOME/direnv-b/bin/anvil-direnv-b"
    printf '%s\n' '#!/bin/sh' 'printf project-c-command' \
      >"$HOME/direnv-c/bin/anvil-direnv-c"
    printf '%s\n' '#!/bin/sh' 'printf project-unset-command' \
      >"$HOME/direnv-unset/bin/anvil-direnv-unset"
    printf '%s\n' '#!/bin/sh' 'printf project-spoof-command' \
      >"$HOME/direnv-spoof/bin/anvil-direnv-spoof"
    chmod 0700 \
      "$HOME/direnv-a/bin/anvil-direnv-a" \
      "$HOME/direnv-b/bin/anvil-direnv-b" \
      "$HOME/direnv-c/bin/anvil-direnv-c" \
      "$HOME/direnv-unset/bin/anvil-direnv-unset" \
      "$HOME/direnv-spoof/bin/anvil-direnv-spoof"
    touch \
      "$HOME/direnv-a/visited.txt" \
      "$HOME/direnv-b/visited.txt" \
      "$HOME/direnv-c/visited.txt" \
      "$HOME/direnv-unset/visited.txt" \
      "$HOME/direnv-spoof/visited.txt"
    (
      cd "$HOME/direnv-a"
      ${anvilMcp.direnv}/bin/direnv allow >/dev/null
    )
    (
      cd "$HOME/direnv-b"
      ${anvilMcp.direnv}/bin/direnv allow >/dev/null
    )
    (
      cd "$HOME/direnv-c"
      ${anvilMcp.direnv}/bin/direnv allow >/dev/null
    )
    (
      cd "$HOME/direnv-unset"
      ${anvilMcp.direnv}/bin/direnv allow >/dev/null
    )
    (
      cd "$HOME/direnv-spoof"
      ${anvilMcp.direnv}/bin/direnv allow >/dev/null
    )

    ${coreutils}/bin/timeout 60 \
      ${python3}/bin/python3 -I -B -u ${./watchdog-test.py} \
      ${anvilMcp.dedicatedLockLauncher}
    ${coreutils}/bin/timeout 60 \
      ${python3}/bin/python3 -I -B -u ${./timeout-ordering-test.py} \
      ${anvilMcp.dedicatedLockLauncher} \
      ${anvilMcp.dedicatedAnvil}/share/emacs/site-lisp/anvil-stdio.sh \
      ${anvilMcp.dedicatedInit} \
      ${anvilMcp.dedicatedAnvil}/share/emacs/site-lisp/anvil-shell-filter.el \
      ${./default.nix} \
      ${timeoutPolicyJson}
    ${coreutils}/bin/timeout 60 \
      ${python3}/bin/python3 -I -B -u ${./stdio-reconnect-test.py} \
      ${anvilMcp.dedicatedAnvil}/share/emacs/site-lisp/anvil-stdio.sh
    ${coreutils}/bin/timeout 120 \
      ${python3}/bin/python3 -I -B -u ${./stdio-postdispatch-test.py} \
      ${anvilMcp.dedicatedAnvil}/share/emacs/site-lisp/anvil-stdio.sh \
      ${bash}/bin/bash \
      ${anvilMcp.dedicatedParentGuardLauncher} \
      ${python3}/bin/python3
    ${coreutils}/bin/timeout 60 \
      ${python3}/bin/python3 -I -B -u ${./stdio-concurrency-test.py} \
      ${anvilMcp.dedicatedAnvil}/share/emacs/site-lisp/anvil-stdio.sh
    ${coreutils}/bin/timeout 60 \
      ${python3}/bin/python3 -I -B -u ${./alternate-editor-test.py} \
      ${anvilMcp.dedicatedAnvil}/share/emacs/site-lisp/anvil-stdio.sh \
      ${anvilMcp.dedicatedRuntimeEmacs}/bin/emacsclient
    ${coreutils}/bin/timeout 60 \
      ${python3}/bin/python3 -I -B -u ${./safe-emacsclient-test.py} \
      ${anvilMcp.dedicatedSafeEmacsclientGuard} \
      ${anvilMcp.dedicatedSafeEmacsclient}/bin/emacsclient

    init_compile_dir="$smoke_root/init-byte-compile"
    install -d -m 0700 "$init_compile_dir"
    install -m 0600 ${anvilMcp.dedicatedEnvironmentInit} \
      "$init_compile_dir/anvil-headless-environment-init.el"
    install -m 0600 ${anvilMcp.dedicatedWorkerInit} \
      "$init_compile_dir/anvil-headless-worker-init.el"
    install -m 0600 ${anvilMcp.dedicatedOffloadInit} \
      "$init_compile_dir/anvil-headless-offload-init.el"
    install -m 0600 ${anvilMcp.dedicatedInit} \
      "$init_compile_dir/anvil-headless-init.el"
    TMPDIR="$init_compile_dir" TMP="$init_compile_dir" TEMP="$init_compile_dir" \
      ${coreutils}/bin/timeout 60 \
      ${anvilMcp.dedicatedRuntimeEmacs}/bin/emacs --quick --batch \
      --directory "${anvilMcp.dedicatedAnvil}/share/emacs/site-lisp" \
      --directory "${anvilMcp.dedicatedAnvilIde}/share/emacs/site-lisp" \
      --eval '(setq byte-compile-error-on-warn t)' \
      --funcall batch-byte-compile \
      "$init_compile_dir/anvil-headless-environment-init.el" \
      "$init_compile_dir/anvil-headless-worker-init.el" \
      "$init_compile_dir/anvil-headless-offload-init.el" \
      "$init_compile_dir/anvil-headless-init.el"
    for source in "$init_compile_dir"/*.el; do
      test -f "$source"c
    done
    rm -rf "$init_compile_dir"

    worker_pool_test_tmp="$smoke_root/worker-pool-test-tmp"
    install -d -m 0700 "$worker_pool_test_tmp"
    TMPDIR="$worker_pool_test_tmp" \
      TMP="$worker_pool_test_tmp" \
      TEMP="$worker_pool_test_tmp" \
      ${anvilMcp.dedicatedEmacs}/bin/emacs --quick --batch \
      --directory "${anvilMcp.dedicatedAnvil}/share/emacs/site-lisp" \
      --load ${./worker-pool-test.el} \
      --funcall ert-run-tests-batch-and-exit
    rm -rf "$worker_pool_test_tmp"

    hang_test_tmp="$smoke_root/hang-regression-test"
    install -d -m 0700 "$hang_test_tmp"
    install -m 0600 ${./anvil-hang-regression-test.el} \
      "$hang_test_tmp/anvil-hang-regression-test.el"
    install -m 0600 ${./anvil-offload-stub.el} \
      "$hang_test_tmp/anvil-offload-stub.el"
    PATH="${coreutils}/bin:${bash}/bin:/usr/bin:/bin" \
      TMPDIR="$hang_test_tmp" TMP="$hang_test_tmp" TEMP="$hang_test_tmp" \
      ${coreutils}/bin/timeout 60 \
      ${anvilMcp.dedicatedEmacs}/bin/emacs --quick --batch \
      --directory "${anvilMcp.dedicatedAnvil}/share/emacs/site-lisp" \
      --directory "$hang_test_tmp" \
      --load "$hang_test_tmp/anvil-hang-regression-test.el" \
      --funcall ert-run-tests-batch-and-exit
    rm -rf "$hang_test_tmp"

    install -d -m 0700 \
      "$ANVIL_EMACS_RUNTIME_ROOT" \
      "$ANVIL_EMACS_RUNTIME_ROOT/host-b" \
      "$ANVIL_EMACS_RUNTIME_ROOT/host-b/tmp" \
      "$ANVIL_EMACS_RUNTIME_ROOT/host-b/workers" \
      "$ANVIL_EMACS_RUNTIME_ROOT/host-b/workers/stale-before-start"
    touch "$ANVIL_EMACS_RUNTIME_ROOT/host-b/tmp/stale-before-start"
    touch "$ANVIL_EMACS_RUNTIME_ROOT/host-b/workers/stale-before-start/sentinel"

    pid_a=
    pid_b=
    pid_restart=
    pid_crash=
    pid_crash_restart=
    crash_child_pid=
    classic_lock_pid=
    tamper_watchdog=
    agent_home=
    agent_runtime_root=
    agent_state_root=
    cleanup() {
      status=$?
      set +e
      for host in host-a host-b host-crash; do
        socket="$ANVIL_EMACS_RUNTIME_ROOT/$host/emacs/server"
        if [ -S "$socket" ]; then
          ${anvilMcp.dedicatedEmacs}/bin/emacsclient             -s "$socket" -e '(kill-emacs)' >/dev/null 2>&1 || true
        fi
      done
      if [ -n "$pid_a" ]; then kill "$pid_a" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_b" ]; then kill "$pid_b" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_restart" ]; then kill "$pid_restart" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_crash" ]; then kill "$pid_crash" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_crash_restart" ]; then kill "$pid_crash_restart" >/dev/null 2>&1 || true; fi
      if [ -n "$crash_child_pid" ]; then kill "$crash_child_pid" >/dev/null 2>&1 || true; fi
      if [ -n "$classic_lock_pid" ]; then kill "$classic_lock_pid" >/dev/null 2>&1 || true; fi
      if [ -n "$tamper_watchdog" ]; then kill "$tamper_watchdog" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_a" ]; then wait "$pid_a" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_b" ]; then wait "$pid_b" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_restart" ]; then wait "$pid_restart" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_crash" ]; then wait "$pid_crash" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_crash_restart" ]; then wait "$pid_crash_restart" >/dev/null 2>&1 || true; fi
      if [ -n "$tamper_watchdog" ]; then wait "$tamper_watchdog" >/dev/null 2>&1 || true; fi
      rm -rf "$agent_home" "$agent_runtime_root" "$agent_state_root" "$smoke_root"
      return "$status"
    }
    trap cleanup EXIT

    ANVIL_AGENT_SUPERVISOR=${anvilMcp.dedicatedAgentSupervisor} \
      ${python3}/bin/python3 -I -B -u \
      ${anvilMcp.dedicatedAgentSupervisorTest}
    # Keep Darwin Unix-domain worker socket names under its 104-byte
    # limit while preserving the full HOST/agents/KEY hierarchy.
    # A distinct empty HOME proves root and worker startup never create
    # ~/.emacs.d while preserving HOME for login-shell and direnv behavior.
    agent_home="$smoke_root/agent-home"
    install -d -m 0700 "$agent_home"
    agent_runtime_root=$(mktemp -d /tmp/ar.XXXXXX)
    agent_state_root=$(mktemp -d /tmp/as.XXXXXX)
    agent_alternate_editor="$smoke_root/agent-alternate-editor"
    agent_alternate_editor_marker="$smoke_root/agent-alternate-editor-used"
    printf '%s\n' \
      '#!${bash}/bin/bash' \
      'touch "$ANVIL_ALTERNATE_EDITOR_MARKER"' \
      >"$agent_alternate_editor"
    chmod 0700 "$agent_alternate_editor"
    # The real smoke forces a watchdog restart while both bridges stay live.
    # A transport regression would invoke this harmless marker executable.
    ${coreutils}/bin/env -u XDG_CONFIG_HOME \
      HOME="$agent_home" \
      ANVIL_EMACS_RUNTIME_ROOT="$agent_runtime_root" \
      ANVIL_EMACS_STATE_ROOT="$agent_state_root" \
      ALTERNATE_EDITOR="$agent_alternate_editor" \
      ANVIL_ALTERNATE_EDITOR_MARKER="$agent_alternate_editor_marker" \
      ${python3}/bin/python3 -I -B -u \
      ${anvilMcp.dedicatedAgentSupervisorSmoke} \
      ${anvilMcp}/bin/anvil-mcp \
      ${anvilMcp.dedicatedAgentSupervisor} \
      ${rolloverAnvilMcp}/bin/anvil-mcp \
      ${readinessCrashAnvilMcp}/bin/anvil-mcp
    if [ -e "$agent_alternate_editor_marker" ]; then
      echo "agent supervisor smoke invoked ALTERNATE_EDITOR" >&2
      exit 1
    fi
    (
      soak_home=$(mktemp -d /tmp/ah.XXXXXX)
      soak_runtime_root=$(mktemp -d /tmp/ar.XXXXXX)
      soak_state_root=$(mktemp -d /tmp/as.XXXXXX)
      trap 'rm -rf "$soak_home" "$soak_runtime_root" "$soak_state_root"' EXIT
      ${coreutils}/bin/env -u XDG_CONFIG_HOME \
        HOME="$soak_home" \
        SHELL="${bash}/bin/bash" \
        ANVIL_EMACS_RUNTIME_ROOT="$soak_runtime_root" \
        ANVIL_EMACS_STATE_ROOT="$soak_state_root" \
        ANVIL_PERSISTENT_SOAK_CYCLES=25 \
        ANVIL_PERSISTENT_SOAK_HEALTHY_SECONDS=${toString anvilMcp.timeoutPolicy.clientToolSeconds} \
        ${coreutils}/bin/timeout 1200 \
        ${python3}/bin/python3 -I -B -u \
        ${anvilMcp.dedicatedPersistentBridgeSoak} \
        ${anvilMcp}/bin/anvil-mcp \
        ${anvilMcp.dedicatedAgentSupervisor} \
        ${anvilMcp.dedicatedAgentSupervisorSmoke} \
        ${anvilMcp.git}/bin/git \
        ${anvilMcp.direnv}/bin/direnv \
        ${unixtools.ps}/bin/ps
    )
    ${coreutils}/bin/timeout 300 \
      ${python3}/bin/python3 -I -B -u ${./legacy-migration-test.py} \
      ${hostAnvilMcp}/bin/anvil-headless-emacs \
      ${hostAnvilMcp}/bin/anvil-mcp \
      ${anvilMcp}/bin/anvil-headless-emacs \
      ${anvilMcp}/bin/anvil-mcp \
      ${anvilMcp.dedicatedRuntimeEmacs}/bin/emacsclient
    rm -rf "$agent_runtime_root" "$agent_state_root"
    agent_runtime_root=
    agent_state_root=
    agent_home=

    assert_status() {
      label="$1"
      expected="$2"
      wanted_status="$3"
      shift 3
      log="$smoke_root/$label.log"
      timeout_seconds="''${ANVIL_SMOKE_ASSERT_TIMEOUT:-5}"
      case "$timeout_seconds" in
        "" | *[!0-9]*)
          echo "invalid smoke assertion timeout: $timeout_seconds" >&2
          return 1
          ;;
      esac
      if [ "$timeout_seconds" -le 0 ]; then
        echo "invalid smoke assertion timeout: $timeout_seconds" >&2
        return 1
      fi
      if ${coreutils}/bin/timeout "$timeout_seconds" "$@" >"$log" 2>&1; then
        echo "$label unexpectedly succeeded" >&2
        cat "$log" >&2
        return 1
      else
        status=$?
      fi
      if [ "$status" -eq 124 ]; then
        echo "$label timed out instead of failing closed" >&2
        cat "$log" >&2
        return 1
      fi
      if [ "$status" -ne "$wanted_status" ]; then
        echo "$label exited $status instead of $wanted_status" >&2
        cat "$log" >&2
        return 1
      fi
      if ! grep -F "$expected" "$log" >/dev/null; then
        echo "$label did not report $expected" >&2
        cat "$log" >&2
        return 1
      fi
    }

    assert_rejected() {
      label="$1"
      expected="$2"
      shift 2
      assert_status "$label" "$expected" 77 "$@"
    }

    bad_home="$smoke_root/bad-login-home"
    install -d -m 0700 \
      "$bad_home" "$bad_home/org" \
      "$smoke_root/bad-login-runtime" "$smoke_root/bad-login-state"
    printf '%s\n' 'exit 1' >"$bad_home/.bash_profile"
    ANVIL_SMOKE_ASSERT_TIMEOUT=20 \
      assert_status login-shell-failure "headless startup failed" 70 \
      env HOME="$bad_home" SHELL="${bash}/bin/bash" \
      ANVIL_EMACS_HOST=bad-login \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/bad-login-runtime" \
      ANVIL_EMACS_STATE_ROOT="$smoke_root/bad-login-state" \
      ${anvilMcp}/bin/anvil-headless-emacs

    install -d -m 0700 "$smoke_root/runtime-link-target"
    ln -s "$smoke_root/runtime-link-target" "$smoke_root/runtime-link"
    assert_rejected runtime-symlink "must not be a symbolic link" \
      env ANVIL_EMACS_HOST=hostile \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/runtime-link" \
      ANVIL_EMACS_STATE_ROOT="$smoke_root/unused-state" \
      ${anvilMcp}/bin/anvil-headless-emacs

    install -d -m 0755 "$smoke_root/runtime-open"
    assert_rejected runtime-mode "must have mode 0700" \
      env ANVIL_EMACS_HOST=hostile \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/runtime-open" \
      ANVIL_EMACS_STATE_ROOT="$smoke_root/unused-state" \
      ${anvilMcp}/bin/anvil-headless-emacs

    assert_rejected runtime-owner "must be owned by uid" \
      env ANVIL_EMACS_HOST=hostile \
      ANVIL_EMACS_RUNTIME_ROOT=${anvilMcp} \
      ANVIL_EMACS_STATE_ROOT="$smoke_root/unused-state" \
      ${anvilMcp}/bin/anvil-headless-emacs

    install -d -m 0700 "$smoke_root/state-test-runtime"
    install -d -m 0700 "$smoke_root/state-link-target"
    ln -s "$smoke_root/state-link-target" "$smoke_root/state-link"
    assert_rejected state-symlink "must not be a symbolic link" \
      env ANVIL_EMACS_HOST=hostile \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/state-test-runtime" \
      ANVIL_EMACS_STATE_ROOT="$smoke_root/state-link" \
      ${anvilMcp}/bin/anvil-headless-emacs

    install -d -m 0755 "$smoke_root/state-open"
    assert_rejected state-mode "must have mode 0700" \
      env ANVIL_EMACS_HOST=hostile \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/state-test-runtime" \
      ANVIL_EMACS_STATE_ROOT="$smoke_root/state-open" \
      ${anvilMcp}/bin/anvil-headless-emacs

    assert_rejected state-owner "must be owned by uid" \
      env ANVIL_EMACS_HOST=hostile \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/state-test-runtime" \
      ANVIL_EMACS_STATE_ROOT=${anvilMcp} \
      ${anvilMcp}/bin/anvil-headless-emacs

    install -d -m 0700 \
      "$smoke_root/hostile-lock-runtime" \
      "$smoke_root/hostile-lock-runtime/hostile" \
      "$smoke_root/hostile-lock-state"
    touch "$smoke_root/lock-symlink-target"
    ln -s "$smoke_root/lock-symlink-target" \
      "$smoke_root/hostile-lock-runtime/hostile/.anvil-headless-emacs.lock"
    assert_rejected runtime-lock-symlink "cannot open runtime lock file" \
      env ANVIL_EMACS_HOST=hostile \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/hostile-lock-runtime" \
      ANVIL_EMACS_STATE_ROOT="$smoke_root/hostile-lock-state" \
      ${anvilMcp}/bin/anvil-headless-emacs

    install -d -m 0700 \
      "$smoke_root/nonregular-lock-runtime" \
      "$smoke_root/nonregular-lock-runtime/hostile" \
      "$smoke_root/nonregular-lock-state"
    mkfifo "$smoke_root/nonregular-lock-runtime/hostile/.anvil-headless-emacs.lock"
    assert_rejected runtime-lock-nonregular "lock must be a regular file" \
      env ANVIL_EMACS_HOST=hostile \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/nonregular-lock-runtime" \
      ANVIL_EMACS_STATE_ROOT="$smoke_root/nonregular-lock-state" \
      ${anvilMcp}/bin/anvil-headless-emacs

    install -d -m 0700 \
      "$smoke_root/refresh-runtime" \
      "$smoke_root/refresh-state"
    for invalid_refresh in nan inf; do
      assert_rejected "lock-refresh-$invalid_refresh" "must be positive and finite" \
        env ANVIL_EMACS_HOST=hostile \
        ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/refresh-runtime" \
        ANVIL_EMACS_STATE_ROOT="$smoke_root/refresh-state" \
        ANVIL_EMACS_LOCK_REFRESH_SECONDS="$invalid_refresh" \
        ${anvilMcp}/bin/anvil-headless-emacs
    done

    install -d -m 0700 "$smoke_root/identical-roots"
    assert_rejected identical-roots "runtime and state directories must be distinct" \
      env ANVIL_EMACS_HOST=hostile \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/identical-roots" \
      ANVIL_EMACS_STATE_ROOT="$smoke_root/identical-roots" \
      ${anvilMcp}/bin/anvil-headless-emacs

    install -d -m 0700 \
      "$smoke_root/exec-runtime" "$smoke_root/exec-state"
    assert_status locked-stage-exec "cannot exec locked stage" 70 \
      ${python3}/bin/python3 -I -S ${anvilMcp.dedicatedLockLauncher} \
      "$smoke_root/exec-runtime" "$smoke_root/exec-state" 75 \
      "$smoke_root/nonexistent-locked-stage"

    classic_lock_script="$smoke_root/classic-lock.py"
    printf '%s\n' \
      'import fcntl' \
      'import os' \
      'import sys' \
      'import time' \
      'fd = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT, 0o600)' \
      'fcntl.lockf(fd, fcntl.LOCK_EX)' \
      'open(sys.argv[2], "w", encoding="utf-8").close()' \
      'time.sleep(30)' \
      >"$classic_lock_script"
    install -d -m 0700 \
      "$smoke_root/classic-runtime" \
      "$smoke_root/classic-runtime/legacy" \
      "$smoke_root/classic-state"
    classic_ready="$smoke_root/classic-lock.ready"
    ${python3}/bin/python3 "$classic_lock_script" \
      "$smoke_root/classic-runtime/legacy/.anvil-headless-emacs.lock" \
      "$classic_ready" &
    classic_lock_pid=$!
    for _ in $(seq 1 100); do
      if [ -e "$classic_ready" ]; then break; fi
      sleep 0.02
    done
    if [ ! -e "$classic_ready" ]; then
      echo "classic POSIX lock holder did not become ready" >&2
      exit 1
    fi
    assert_status mixed-classic-ofd-lock "holds the runtime lock" 75 \
      env ANVIL_EMACS_HOST=legacy \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/classic-runtime" \
      ANVIL_EMACS_STATE_ROOT="$smoke_root/classic-state" \
      ${anvilMcp}/bin/anvil-headless-emacs
    kill "$classic_lock_pid"
    wait "$classic_lock_pid" >/dev/null 2>&1 || true
    classic_lock_pid=

    install -d -m 0700 \
      "$smoke_root/nested-runtime" \
      "$smoke_root/nested-state" \
      "$smoke_root/nested-state/hostile" \
      "$smoke_root/nested-state/hostile/workers" \
      "$smoke_root/nested-state-target"
    ln -s "$smoke_root/nested-state-target" \
      "$smoke_root/nested-state/hostile/workers/${firstWorker}"
    assert_rejected worker-state-symlink "must not be a symbolic link" \
      env ANVIL_EMACS_HOST=hostile \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/nested-runtime" \
      ANVIL_EMACS_STATE_ROOT="$smoke_root/nested-state" \
      ${anvilMcp}/bin/anvil-headless-emacs

    install -d -m 0700 \
      "$smoke_root/nested-mode-runtime" \
      "$smoke_root/nested-mode-state" \
      "$smoke_root/nested-mode-state/hostile" \
      "$smoke_root/nested-mode-state/hostile/workers"
    install -d -m 0755 \
      "$smoke_root/nested-mode-state/hostile/workers/${firstWorker}"
    assert_rejected worker-state-mode "must have mode 0700" \
      env ANVIL_EMACS_HOST=hostile \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/nested-mode-runtime" \
      ANVIL_EMACS_STATE_ROOT="$smoke_root/nested-mode-state" \
      ${anvilMcp}/bin/anvil-headless-emacs

    (
      sleep 1
      export ANVIL_EMACS_HOST=host-a
      export ALTERNATE_EDITOR="$agent_alternate_editor"
      export ANVIL_ALTERNATE_EDITOR_MARKER="$agent_alternate_editor_marker"
      # Use the packaged heartbeat and dispatch deadlines for this ordinary
      # transcript.  The dedicated supervisor smoke separately injects a
      # non-yielding request under accelerated deadlines and proves recovery;
      # shortening this transcript instead turns host-wide macOS loader
      # scheduling into a false root-hang signal.
      export ANVIL_EMACS_WATCHDOG_PULSE_SECONDS=0.5
      exec ${anvilMcp}/bin/anvil-headless-emacs
    ) >"$smoke_root/host-a.log" 2>&1 &
    pid_a=$!
    ANVIL_EMACS_HOST=host-b       ${anvilMcp}/bin/anvil-headless-emacs >"$smoke_root/host-b.log" 2>&1 &
    pid_b=$!

    # Invoke the launcher before host-a has a socket. This proves that an MCP
    # client started during login or a service restart waits for readiness.
    if ! ${python3}/bin/python -I ${./headless-smoke.py} \
      ${hostAnvilMcp}/bin/anvil-mcp \
      ${lib.escapeShellArg workerSpecsJson} \
      ${toString anvilMcp.timeoutPolicy.clientToolSeconds}; then
      cat "$smoke_root/host-a.log" "$smoke_root/host-b.log" >&2
      exit 1
    fi

    if [ ! -S "$ANVIL_EMACS_RUNTIME_ROOT/host-a/emacs/server" ]       || [ ! -S "$ANVIL_EMACS_RUNTIME_ROOT/host-b/emacs/server" ]; then
      cat "$smoke_root/host-a.log" "$smoke_root/host-b.log" >&2
      exit 1
    fi

    # Exercise the worker-side client inside a daemon that actually inherited
    # a hostile editor.  The deliberately absent worker socket must fail closed
    # through the centralized `-a false' argv and never invoke the marker.
    root_socket="$ANVIL_EMACS_RUNTIME_ROOT/host-a/emacs/server"
    daemon_has_hostile_editor=$(
      ${anvilMcp.dedicatedEmacs}/bin/emacsclient -a false -s "$root_socket" \
        -e "(equal (getenv \"ALTERNATE_EDITOR\") \"$agent_alternate_editor\")"
    )
    if [ "$daemon_has_hostile_editor" != t ]; then
      echo "host daemon did not inherit the hostile ALTERNATE_EDITOR fixture" >&2
      exit 1
    fi
    missing_worker_socket="$ANVIL_EMACS_RUNTIME_ROOT/host-a/workers/missing-alternate-editor"
    rm -f -- "$missing_worker_socket"
    missing_worker_status=$(
      ${anvilMcp.dedicatedEmacs}/bin/emacsclient -a false -s "$root_socket" \
        -e "(let ((server-use-tcp nil)) (apply #'call-process \"emacsclient\" nil nil nil (append (anvil-worker--emacsclient-server-args \"$missing_worker_socket\") (list \"-e\" \"t\"))))"
    )
    if [ -e "$agent_alternate_editor_marker" ]; then
      echo "daemon-side worker client invoked ALTERNATE_EDITOR" >&2
      exit 1
    fi
    case "$missing_worker_status" in
      "" | 0)
        echo "missing worker socket did not fail closed: $missing_worker_status" >&2
        exit 1
        ;;
    esac

    runtime_lock="$ANVIL_EMACS_RUNTIME_ROOT/host-a/.anvil-headless-emacs.lock"
    state_lock="$ANVIL_EMACS_STATE_ROOT/host-a/.anvil-headless-emacs.lock"
    host_state="$ANVIL_EMACS_STATE_ROOT/host-a"
    semantic_dir="$host_state/semantic"
    semantic_index="$semantic_dir/index.db"
    if [ ! -d "$host_state" ] || [ -L "$host_state" ] \
      || [ ! -d "$semantic_dir" ] || [ -L "$semantic_dir" ] \
      || [ ! -f "$semantic_index" ] || [ -L "$semantic_index" ]; then
      echo "durable semantic state is missing or unsafe" >&2
      ls -ld "$host_state" "$semantic_dir" "$semantic_index" >&2 || true
      exit 1
    fi
    semantic_identity=$(stat -c '%d:%i' -- "$semantic_index")
    refresh_cutoff=$(date +%s)
    touch -t 197001010000 \
      "$runtime_lock" "$state_lock" "$host_state" "$semantic_dir" "$semantic_index"
    heartbeat_targets_refreshed=
    for _ in $(seq 1 50); do
      heartbeat_targets_refreshed=1
      for target in \
        "$runtime_lock" "$state_lock" "$host_state" "$semantic_dir" "$semantic_index"; do
        if ! target_mtime=$(stat -c %Y -- "$target") \
          || [ "$target_mtime" -lt "$refresh_cutoff" ]; then
          heartbeat_targets_refreshed=
          break
        fi
      done
      if [ -n "$heartbeat_targets_refreshed" ]; then
        break
      fi
      if ! kill -0 "$pid_a" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
    if [ -z "$heartbeat_targets_refreshed" ]; then
      echo "watchdog heartbeat did not refresh locks and durable state" >&2
      stat \
        "$runtime_lock" "$state_lock" "$host_state" "$semantic_dir" "$semantic_index" \
        >&2 || true
      exit 1
    fi
    if [ "$(stat -c '%d:%i' -- "$semantic_index")" != "$semantic_identity" ]; then
      echo "durable-state refresh replaced the semantic index" >&2
      exit 1
    fi
    if ! ${anvilMcp.dedicatedEmacs}/bin/emacsclient \
      -s "$ANVIL_EMACS_RUNTIME_ROOT/host-a/emacs/server" -e t >/dev/null; then
      echo "durable-state refresh disrupted the root daemon" >&2
      exit 1
    fi

    install -d -m 0755 "$smoke_root/responsive-open/host-a/emacs"
    ln -s "$ANVIL_EMACS_RUNTIME_ROOT/host-a/emacs/server" \
      "$smoke_root/responsive-open/host-a/emacs/server"
    assert_rejected responsive-unsafe-root "must have mode 0700" \
      env ANVIL_EMACS_HOST=host-a \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/responsive-open" \
      ${hostAnvilMcp}/bin/anvil-mcp

    install -d -m 0700 \
      "$smoke_root/responsive-symlink" \
      "$smoke_root/responsive-symlink/host-a" \
      "$smoke_root/responsive-symlink/host-a/emacs"
    ln -s "$ANVIL_EMACS_RUNTIME_ROOT/host-a/emacs/server" \
      "$smoke_root/responsive-symlink/host-a/emacs/server"
    assert_rejected responsive-symlink-socket "must not be a symbolic link" \
      env ANVIL_EMACS_HOST=host-a \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/responsive-symlink" \
      ${hostAnvilMcp}/bin/anvil-mcp

    install -d -m 0700 \
      "$smoke_root/responsive-wrong-type" \
      "$smoke_root/responsive-wrong-type/host-a" \
      "$smoke_root/responsive-wrong-type/host-a/emacs"
    touch "$smoke_root/responsive-wrong-type/host-a/emacs/server"
    assert_rejected responsive-wrong-socket-type "must be a socket" \
      env ANVIL_EMACS_HOST=host-a \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/responsive-wrong-type" \
      ${hostAnvilMcp}/bin/anvil-mcp

    if [ -e "$ANVIL_EMACS_RUNTIME_ROOT/host-b/tmp/stale-before-start" ]; then
      echo "host runtime temp was not pruned after taking both daemon locks" >&2
      exit 1
    fi
    if [ -e "$ANVIL_EMACS_RUNTIME_ROOT/host-b/workers/stale-before-start" ]; then
      echo "stale worker runtime was not pruned after taking both daemon locks" >&2
      exit 1
    fi

    touch "$ANVIL_EMACS_RUNTIME_ROOT/host-a/tmp/live-sentinel"
    assert_status duplicate-runtime-lock "holds the runtime lock" 75 \
      env ANVIL_EMACS_HOST=host-a \
      ANVIL_EMACS_RUNTIME_ROOT="$ANVIL_EMACS_RUNTIME_ROOT" \
      ANVIL_EMACS_STATE_ROOT="$smoke_root/different-state" \
      ${anvilMcp}/bin/anvil-headless-emacs
    if [ ! -e "$ANVIL_EMACS_RUNTIME_ROOT/host-a/tmp/live-sentinel" ]; then
      echo "runtime-lock rejection pruned live daemon state" >&2
      exit 1
    fi

    launchd_conflict_log="$smoke_root/launchd-lock-conflict.log"
    if ! ${coreutils}/bin/timeout 5 env \
      ANVIL_EMACS_HOST=host-a \
      ANVIL_EMACS_RUNTIME_ROOT="$ANVIL_EMACS_RUNTIME_ROOT" \
      ANVIL_EMACS_STATE_ROOT="$smoke_root/launchd-state" \
      ANVIL_EMACS_LOCK_CONFLICT_STATUS=0 \
      ${anvilMcp}/bin/anvil-headless-emacs \
      >"$launchd_conflict_log" 2>&1; then
      echo "launchd-style lock contention did not exit successfully" >&2
      cat "$launchd_conflict_log" >&2
      exit 1
    fi
    if ! grep -F "holds the runtime lock" "$launchd_conflict_log" >/dev/null; then
      echo "launchd-style contention did not report the held lock" >&2
      cat "$launchd_conflict_log" >&2
      exit 1
    fi
    if [ ! -e "$ANVIL_EMACS_RUNTIME_ROOT/host-a/tmp/live-sentinel" ]; then
      echo "launchd-style contention pruned live daemon state" >&2
      exit 1
    fi

    alternate_runtime="$smoke_root/alternate-runtime"
    install -d -m 0700 \
      "$alternate_runtime" \
      "$alternate_runtime/host-a" \
      "$alternate_runtime/host-a/tmp"
    touch "$alternate_runtime/host-a/tmp/live-sentinel"
    assert_status duplicate-state-lock "holds the state lock" 75 \
      env ANVIL_EMACS_HOST=host-a \
      ANVIL_EMACS_RUNTIME_ROOT="$alternate_runtime" \
      ANVIL_EMACS_STATE_ROOT="$ANVIL_EMACS_STATE_ROOT" \
      ${anvilMcp}/bin/anvil-headless-emacs
    if [ ! -e "$alternate_runtime/host-a/tmp/live-sentinel" ]; then
      echo "state-lock rejection pruned the alternate runtime" >&2
      exit 1
    fi

    for cache in       "$ANVIL_EMACS_RUNTIME_ROOT/host-a/tmp/anvil-schema-cache.el"       "$ANVIL_EMACS_RUNTIME_ROOT/host-b/tmp/anvil-schema-cache.el"; do
      if [ ! -f "$cache" ]; then
        echo "missing isolated schema cache: $cache" >&2
        exit 1
      fi
    done
    if [ -e "$TMPDIR/anvil-runtime/anvil-schema-cache.el" ]; then
      echo "shared schema cache was created under TMPDIR" >&2
      exit 1
    fi
    if [ ! -f "$ANVIL_EMACS_STATE_ROOT/host-a/semantic/index.db" ]; then
      echo "missing host-local semantic index" >&2
      exit 1
    fi
    if [ -d "$HOME/.emacs.d" ]; then
      leaked_entry=$(find "$HOME/.emacs.d" -mindepth 1 -print -quit)
      if [ -n "$leaked_entry" ]; then
        echo "Emacs state leaked into HOME: $leaked_entry" >&2
        find "$HOME/.emacs.d" -print >&2
        exit 1
      fi
    fi

    for tree in "$ANVIL_EMACS_RUNTIME_ROOT" "$ANVIL_EMACS_STATE_ROOT"; do
      bad_link=$(find -P "$tree" -type l -print -quit)
      if [ -n "$bad_link" ]; then
        echo "mutable Anvil tree contains a symbolic link: $bad_link" >&2
        exit 1
      fi
      bad_owner=$(find -P "$tree" -type d ! -uid "$(id -u)" -print -quit)
      if [ -n "$bad_owner" ]; then
        echo "mutable Anvil directory has the wrong owner: $bad_owner" >&2
        exit 1
      fi
      bad_mode=$(find -P "$tree" -type d ! -perm 0700 -print -quit)
      if [ -n "$bad_mode" ]; then
        echo "mutable Anvil directory is not mode 0700: $bad_mode" >&2
        exit 1
      fi
    done

    worker_pids="$smoke_root/worker-pids"
    : >"$worker_pids"
    for host in host-a host-b; do
      for worker in ${lib.escapeShellArgs workerNames}; do
        pid_file="$ANVIL_EMACS_STATE_ROOT/$host/workers/$worker/worker.pid"
        if [ ! -f "$pid_file" ]; then
          echo "missing worker PID snapshot: $pid_file" >&2
          exit 1
        fi
        worker_pid=$(cat "$pid_file")
        case "$worker_pid" in
          "" | *[!0-9]*)
            echo "invalid worker PID in $pid_file: $worker_pid" >&2
            exit 1
            ;;
        esac
        if ! kill -0 "$worker_pid" 2>/dev/null; then
          echo "worker $worker_pid is not alive before shutdown" >&2
          exit 1
        fi
        printf '%s\n' "$worker_pid" >>"$worker_pids"
      done
    done
    if [ "$(wc -l <"$worker_pids" | tr -d '[:space:]')" -ne ${toString expectedWorkerCount} ] \
      || [ "$(sort -u "$worker_pids" | wc -l | tr -d '[:space:]')" -ne ${toString expectedWorkerCount} ]; then
      echo "worker PIDs are missing or shared across hosts" >&2
      cat "$worker_pids" >&2
      exit 1
    fi

    shutdown_root() {
      host="$1"
      root_pid="$2"
      socket="$ANVIL_EMACS_RUNTIME_ROOT/$host/emacs/server"
      if ! ${anvilMcp.dedicatedEmacs}/bin/emacsclient -s "$socket" \
        -e "(progn (run-at-time 0.1 nil #'kill-emacs) t)" >/dev/null; then
        echo "failed to request clean shutdown for $host" >&2
        cat "$smoke_root/$host.log" >&2
        return 1
      fi
      if ! wait "$root_pid"; then
        echo "$host root daemon exited unsuccessfully" >&2
        cat "$smoke_root/$host.log" >&2
        return 1
      fi
    }

    shutdown_root host-a "$pid_a"
    pid_a=
    shutdown_root host-b "$pid_b"
    pid_b=

    for _ in $(seq 1 100); do
      surviving=
      while IFS= read -r worker_pid; do
        if kill -0 "$worker_pid" 2>/dev/null; then
          surviving=1
        fi
      done <"$worker_pids"
      if [ -z "$surviving" ]; then
        break
      fi
      sleep 0.1
    done
    while IFS= read -r worker_pid; do
      if kill -0 "$worker_pid" 2>/dev/null; then
        echo "worker $worker_pid survived root-daemon shutdown" >&2
        ps -p "$worker_pid" -o pid=,ppid=,stat=,command= >&2 || true
        exit 1
      fi
    done <"$worker_pids"

    ANVIL_EMACS_HOST=host-a \
      ${anvilMcp}/bin/anvil-headless-emacs \
      >"$smoke_root/host-a-restart.log" 2>&1 &
    pid_restart=$!
    restart_ready=
    restart_socket="$ANVIL_EMACS_RUNTIME_ROOT/host-a/emacs/server"
    for _ in $(seq 1 120); do
      if [ -S "$restart_socket" ] \
        && ${anvilMcp.dedicatedEmacs}/bin/emacsclient \
          -s "$restart_socket" -e t >/dev/null 2>&1; then
        restart_ready=1
        break
      fi
      sleep 0.25
    done
    if [ -z "$restart_ready" ]; then
      echo "daemon failed to reacquire locks after clean shutdown" >&2
      cat "$smoke_root/host-a-restart.log" >&2
      exit 1
    fi

    for lock_path in "$runtime_lock" "$state_lock"; do
      old_identity=$(stat -c '%d:%i' -- "$lock_path")
      replacement="$lock_path.replacement"
      touch "$replacement"
      chmod 0600 "$replacement"
      mv -f -- "$replacement" "$lock_path"
      new_identity=$(stat -c '%d:%i' -- "$lock_path")
      if [ "$old_identity" = "$new_identity" ]; then
        echo "lock-path replacement did not change inode: $lock_path" >&2
        exit 1
      fi
    done

    tamper_done="$smoke_root/lock-tamper.done"
    (
      sleep 5
      if [ ! -e "$tamper_done" ]; then
        kill -TERM "$pid_restart" >/dev/null 2>&1 || true
      fi
    ) &
    tamper_watchdog=$!
    if wait "$pid_restart"; then
      tamper_status=0
    else
      tamper_status=$?
    fi
    touch "$tamper_done"
    kill "$tamper_watchdog" >/dev/null 2>&1 || true
    wait "$tamper_watchdog" >/dev/null 2>&1 || true
    tamper_watchdog=
    pid_restart=
    if [ "$tamper_status" -ne 137 ]; then
      echo "lock heartbeat exited root with status $tamper_status instead of SIGKILL" >&2
      cat "$smoke_root/host-a-restart.log" >&2
      exit 1
    fi
    if ${anvilMcp.dedicatedEmacs}/bin/emacsclient -s "$restart_socket" \
      -e t >/dev/null 2>&1; then
      echo "replaced-lock root remained connectable after heartbeat failure" >&2
      exit 1
    fi

    ANVIL_EMACS_HOST=host-a \
      ${anvilMcp}/bin/anvil-headless-emacs \
      >"$smoke_root/host-a-lock-recovery.log" 2>&1 &
    pid_restart=$!
    restart_ready=
    for _ in $(seq 1 120); do
      if [ -S "$restart_socket" ] \
        && ${anvilMcp.dedicatedEmacs}/bin/emacsclient \
          -s "$restart_socket" -e t >/dev/null 2>&1; then
        restart_ready=1
        break
      fi
      if ! kill -0 "$pid_restart" 2>/dev/null; then
        break
      fi
      sleep 0.25
    done
    if [ -z "$restart_ready" ]; then
      echo "daemon failed to reacquire locks after lock-path replacement" >&2
      cat "$smoke_root/host-a-lock-recovery.log" >&2
      exit 1
    fi
    actual_restart_pid=$(${anvilMcp.dedicatedEmacs}/bin/emacsclient \
      -s "$restart_socket" -e '(emacs-pid)')
    if [ "$actual_restart_pid" != "$pid_restart" ]; then
      echo "replacement service PID $pid_restart is not root Emacs PID $actual_restart_pid" >&2
      exit 1
    fi
    assert_status replaced-lock-exclusive "holds the runtime lock" 75 \
      env ANVIL_EMACS_HOST=host-a \
      ANVIL_EMACS_RUNTIME_ROOT="$ANVIL_EMACS_RUNTIME_ROOT" \
      ANVIL_EMACS_STATE_ROOT="$ANVIL_EMACS_STATE_ROOT" \
      ${anvilMcp}/bin/anvil-headless-emacs

    if [ -L "$state_lock" ] || [ ! -f "$state_lock" ]; then
      echo "state lock is missing or unsafe before deletion test" >&2
      exit 1
    fi
    rm -f -- "$state_lock"
    if [ -e "$state_lock" ] || [ -L "$state_lock" ]; then
      echo "state lock deletion did not remove the directory entry" >&2
      exit 1
    fi

    deletion_done="$smoke_root/lock-deletion.done"
    (
      sleep 5
      if [ ! -e "$deletion_done" ]; then
        kill -TERM "$pid_restart" >/dev/null 2>&1 || true
      fi
    ) &
    tamper_watchdog=$!
    if wait "$pid_restart"; then
      deletion_status=0
    else
      deletion_status=$?
    fi
    touch "$deletion_done"
    kill "$tamper_watchdog" >/dev/null 2>&1 || true
    wait "$tamper_watchdog" >/dev/null 2>&1 || true
    tamper_watchdog=
    pid_restart=
    if [ "$deletion_status" -ne 137 ]; then
      echo "deleted-lock heartbeat exited root with status $deletion_status instead of SIGKILL" >&2
      cat "$smoke_root/host-a-lock-recovery.log" >&2
      exit 1
    fi
    if ${anvilMcp.dedicatedEmacs}/bin/emacsclient -s "$restart_socket" \
      -e t >/dev/null 2>&1; then
      echo "deleted-lock root remained connectable after heartbeat failure" >&2
      exit 1
    fi

    ANVIL_EMACS_HOST=host-a \
      ${anvilMcp}/bin/anvil-headless-emacs \
      >"$smoke_root/host-a-lock-deletion-recovery.log" 2>&1 &
    pid_restart=$!
    restart_ready=
    for _ in $(seq 1 120); do
      if [ -S "$restart_socket" ] \
        && ${anvilMcp.dedicatedEmacs}/bin/emacsclient \
          -s "$restart_socket" -e t >/dev/null 2>&1; then
        restart_ready=1
        break
      fi
      if ! kill -0 "$pid_restart" 2>/dev/null; then
        break
      fi
      sleep 0.25
    done
    if [ -z "$restart_ready" ]; then
      echo "daemon failed to reacquire locks after state-lock deletion" >&2
      cat "$smoke_root/host-a-lock-deletion-recovery.log" >&2
      exit 1
    fi
    actual_restart_pid=$(${anvilMcp.dedicatedEmacs}/bin/emacsclient \
      -s "$restart_socket" -e '(emacs-pid)')
    if [ "$actual_restart_pid" != "$pid_restart" ]; then
      echo "deletion-recovery PID $pid_restart is not root Emacs PID $actual_restart_pid" >&2
      exit 1
    fi
    for lock_path in "$runtime_lock" "$state_lock"; do
      if [ -L "$lock_path" ] || [ ! -f "$lock_path" ] \
        || [ "$(stat -c %u -- "$lock_path")" != "$(id -u)" ] \
        || [ "$(stat -c %a -- "$lock_path")" != 600 ]; then
        echo "recreated lock is missing or unsafe: $lock_path" >&2
        stat "$lock_path" >&2 || true
        exit 1
      fi
    done
    assert_status deleted-state-lock-exclusive "holds the state lock" 75 \
      env ANVIL_EMACS_HOST=host-a \
      ANVIL_EMACS_RUNTIME_ROOT="$alternate_runtime" \
      ANVIL_EMACS_STATE_ROOT="$ANVIL_EMACS_STATE_ROOT" \
      ${anvilMcp}/bin/anvil-headless-emacs

    if ! ${anvilMcp.dedicatedEmacs}/bin/emacsclient -s "$restart_socket" \
      -e "(progn (run-at-time 0.1 nil #'kill-emacs) t)" >/dev/null; then
      echo "failed to stop deletion-recovery daemon" >&2
      cat "$smoke_root/host-a-lock-deletion-recovery.log" >&2
      exit 1
    fi
    if ! wait "$pid_restart"; then
      echo "deletion-recovery daemon exited unsuccessfully" >&2
      cat "$smoke_root/host-a-lock-deletion-recovery.log" >&2
      exit 1
    fi
    pid_restart=

    # An arbitrary root-spawned child can inherit the OFD lock descriptions.
    # Verify this fails closed after a root SIGKILL: a replacement is rejected
    # until the child exits.  Dedicated workers and shell tools are separately
    # required to close these descriptors before running user work.
    crash_child_script="$smoke_root/lock-child.py"
    printf '%s\n' \
      'import os' \
      'import stat' \
      'import sys' \
      'import time' \
      'for fd, lock_path in ((8, sys.argv[3]), (9, sys.argv[4])):' \
      '    fd_info = os.fstat(fd)' \
      '    path_info = os.stat(lock_path, follow_symlinks=False)' \
      '    if not stat.S_ISREG(fd_info.st_mode):' \
      '        raise SystemExit(70)' \
      '    if (fd_info.st_dev, fd_info.st_ino) != (path_info.st_dev, path_info.st_ino):' \
      '        raise SystemExit(70)' \
      'with open(sys.argv[1], "w", encoding="utf-8") as pid_file:' \
      '    pid_file.write(f"{os.getpid()}\n")' \
      'open(sys.argv[2], "w", encoding="utf-8").close()' \
      'time.sleep(30)' \
      >"$crash_child_script"

    ANVIL_EMACS_HOST=host-crash \
      ${anvilMcp}/bin/anvil-headless-emacs \
      >"$smoke_root/host-crash.log" 2>&1 &
    pid_crash=$!
    crash_socket="$ANVIL_EMACS_RUNTIME_ROOT/host-crash/emacs/server"
    crash_ready=
    for _ in $(seq 1 120); do
      if [ -S "$crash_socket" ] \
        && ${anvilMcp.dedicatedEmacs}/bin/emacsclient \
          -s "$crash_socket" -e t >/dev/null 2>&1; then
        crash_ready=1
        break
      fi
      if ! kill -0 "$pid_crash" 2>/dev/null; then
        break
      fi
      sleep 0.25
    done
    if [ -z "$crash_ready" ]; then
      echo "crash-test daemon failed to become ready" >&2
      cat "$smoke_root/host-crash.log" >&2
      exit 1
    fi

    crash_child_pid_file="$smoke_root/lock-child.pid"
    crash_child_ready_file="$smoke_root/lock-child.ready"
    if ! ${anvilMcp.dedicatedEmacs}/bin/emacsclient -s "$crash_socket" \
      -e "(make-process :name \"anvil-lock-child\" :command '(\"${python3}/bin/python\" \"$crash_child_script\" \"$crash_child_pid_file\" \"$crash_child_ready_file\" \"$ANVIL_EMACS_RUNTIME_ROOT/host-crash/.anvil-headless-emacs.lock\" \"$ANVIL_EMACS_STATE_ROOT/host-crash/.anvil-headless-emacs.lock\") :connection-type 'pipe :noquery t)" \
      >/dev/null; then
      echo "failed to start the crash-test child" >&2
      exit 1
    fi
    for _ in $(seq 1 100); do
      if [ -f "$crash_child_ready_file" ]; then
        break
      fi
      sleep 0.02
    done
    if [ ! -f "$crash_child_ready_file" ] || [ ! -f "$crash_child_pid_file" ]; then
      echo "crash-test child did not inherit the exact lock-file descriptors" >&2
      exit 1
    fi
    crash_child_pid=$(cat "$crash_child_pid_file")
    case "$crash_child_pid" in
      "" | *[!0-9]*)
        echo "invalid crash-test child PID: $crash_child_pid" >&2
        exit 1
        ;;
    esac
    if ! kill -0 "$crash_child_pid" 2>/dev/null; then
      echo "crash-test child is not alive before daemon crash" >&2
      exit 1
    fi

    actual_emacs_pid=$(${anvilMcp.dedicatedEmacs}/bin/emacsclient \
      -s "$crash_socket" -e '(emacs-pid)')
    if [ "$actual_emacs_pid" != "$pid_crash" ]; then
      echo "service PID $pid_crash is not root Emacs PID $actual_emacs_pid" >&2
      exit 1
    fi
    kill -KILL "$actual_emacs_pid"
    wait "$pid_crash" >/dev/null 2>&1 || true
    pid_crash=
    if ! kill -0 "$crash_child_pid" 2>/dev/null; then
      echo "tool child did not survive the root-daemon crash" >&2
      exit 1
    fi
    assert_status inherited-ofd-lock "holds the runtime lock" 75 \
      env ANVIL_EMACS_HOST=host-crash \
      ANVIL_EMACS_RUNTIME_ROOT="$ANVIL_EMACS_RUNTIME_ROOT" \
      ANVIL_EMACS_STATE_ROOT="$ANVIL_EMACS_STATE_ROOT" \
      ${anvilMcp}/bin/anvil-headless-emacs

    kill "$crash_child_pid"
    for _ in $(seq 1 100); do
      if ! kill -0 "$crash_child_pid" 2>/dev/null; then break; fi
      sleep 0.02
    done
    if kill -0 "$crash_child_pid" 2>/dev/null; then
      echo "crash-test child did not release inherited OFD locks" >&2
      exit 1
    fi
    crash_child_pid=

    ANVIL_EMACS_HOST=host-crash \
      ${anvilMcp}/bin/anvil-headless-emacs \
      >"$smoke_root/host-crash-restart.log" 2>&1 &
    pid_crash_restart=$!
    crash_restart_ready=
    for _ in $(seq 1 120); do
      if [ -S "$crash_socket" ] \
        && ${anvilMcp.dedicatedEmacs}/bin/emacsclient \
          -s "$crash_socket" -e t >/dev/null 2>&1; then
        crash_restart_ready=1
        break
      fi
      if ! kill -0 "$pid_crash_restart" 2>/dev/null; then
        break
      fi
      sleep 0.25
    done
    if [ -z "$crash_restart_ready" ]; then
      echo "fresh daemon failed to reacquire locks after SIGKILL" >&2
      cat "$smoke_root/host-crash-restart.log" >&2
      exit 1
    fi
    if ! ${anvilMcp.dedicatedEmacs}/bin/emacsclient -s "$crash_socket" \
      -e "(progn (run-at-time 0.1 nil #'kill-emacs) t)" >/dev/null; then
      echo "failed to stop the crash-test replacement daemon" >&2
      exit 1
    fi
    if ! wait "$pid_crash_restart"; then
      echo "crash-test replacement daemon exited unsuccessfully" >&2
      cat "$smoke_root/host-crash-restart.log" >&2
      exit 1
    fi
    pid_crash_restart=

    touch "$out"
  ''
