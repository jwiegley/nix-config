{
  anvilMcp,
  coreutils,
  findutils,
  lib,
  python3,
  runCommand,
}:

let
  inherit (anvilMcp) workerNames;
  firstWorker = builtins.head workerNames;
  expectedWorkerCount = 2 * builtins.length workerNames;
  workerSpecsJson = builtins.toJSON anvilMcp.workerSpecs;
in
runCommand "anvil-mcp-dedicated-smoke"
  {
    nativeBuildInputs = [
      anvilMcp
      anvilMcp.dedicatedEmacs
      coreutils
      findutils
      python3
    ];
  }
  ''
    smoke_root=$(mktemp -d /tmp/anvil-mcp-smoke.XXXXXX)
    export HOME="$smoke_root/home"
    export ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/runtime"
    export ANVIL_EMACS_STATE_ROOT="$smoke_root/state"
    install -d -m 0700 "$HOME" "$HOME/org"
    printf '%s\n' '* Headless Anvil' 'headlessorgneedle headlesssemanticneedle'       >"$HOME/org/smoke.org"

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
      if [ -n "$pid_a" ]; then wait "$pid_a" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_b" ]; then wait "$pid_b" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_restart" ]; then wait "$pid_restart" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_crash" ]; then wait "$pid_crash" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_crash_restart" ]; then wait "$pid_crash_restart" >/dev/null 2>&1 || true; fi
      rm -rf "$smoke_root"
      return "$status"
    }
    trap cleanup EXIT

    assert_status() {
      label="$1"
      expected="$2"
      wanted_status="$3"
      shift 3
      log="$smoke_root/$label.log"
      if ${coreutils}/bin/timeout 5 "$@" >"$log" 2>&1; then
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
      exec ${anvilMcp}/bin/anvil-headless-emacs
    ) >"$smoke_root/host-a.log" 2>&1 &
    pid_a=$!
    ANVIL_EMACS_HOST=host-b       ${anvilMcp}/bin/anvil-headless-emacs >"$smoke_root/host-b.log" 2>&1 &
    pid_b=$!

    # Invoke the launcher before host-a has a socket. This proves that an MCP
    # client started during login or a service restart waits for readiness.
    if ! ${python3}/bin/python ${./headless-smoke.py} \
      ${anvilMcp}/bin/anvil-mcp ${lib.escapeShellArg workerSpecsJson}; then
      cat "$smoke_root/host-a.log" "$smoke_root/host-b.log" >&2
      exit 1
    fi

    if [ ! -S "$ANVIL_EMACS_RUNTIME_ROOT/host-a/emacs/server" ]       || [ ! -S "$ANVIL_EMACS_RUNTIME_ROOT/host-b/emacs/server" ]; then
      cat "$smoke_root/host-a.log" "$smoke_root/host-b.log" >&2
      exit 1
    fi

    install -d -m 0755 "$smoke_root/responsive-open/host-a/emacs"
    ln -s "$ANVIL_EMACS_RUNTIME_ROOT/host-a/emacs/server" \
      "$smoke_root/responsive-open/host-a/emacs/server"
    assert_rejected responsive-unsafe-root "must have mode 0700" \
      env ANVIL_EMACS_HOST=host-a \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/responsive-open" \
      ${anvilMcp}/bin/anvil-mcp

    install -d -m 0700 \
      "$smoke_root/responsive-symlink" \
      "$smoke_root/responsive-symlink/host-a" \
      "$smoke_root/responsive-symlink/host-a/emacs"
    ln -s "$ANVIL_EMACS_RUNTIME_ROOT/host-a/emacs/server" \
      "$smoke_root/responsive-symlink/host-a/emacs/server"
    assert_rejected responsive-symlink-socket "must not be a symbolic link" \
      env ANVIL_EMACS_HOST=host-a \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/responsive-symlink" \
      ${anvilMcp}/bin/anvil-mcp

    install -d -m 0700 \
      "$smoke_root/responsive-wrong-type" \
      "$smoke_root/responsive-wrong-type/host-a" \
      "$smoke_root/responsive-wrong-type/host-a/emacs"
    touch "$smoke_root/responsive-wrong-type/host-a/emacs/server"
    assert_rejected responsive-wrong-socket-type "must be a socket" \
      env ANVIL_EMACS_HOST=host-a \
      ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/responsive-wrong-type" \
      ${anvilMcp}/bin/anvil-mcp

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
    if ! ${anvilMcp.dedicatedEmacs}/bin/emacsclient -s "$restart_socket" \
      -e "(progn (run-at-time 0.1 nil #'kill-emacs) t)" >/dev/null; then
      echo "failed to stop restarted daemon" >&2
      cat "$smoke_root/host-a-restart.log" >&2
      exit 1
    fi
    if ! wait "$pid_restart"; then
      echo "restarted daemon exited unsuccessfully" >&2
      cat "$smoke_root/host-a-restart.log" >&2
      exit 1
    fi
    pid_restart=

    # A tool-spawned child may inherit fds 8/9 and outlive a crashed daemon,
    # but POSIX process locks themselves must not survive the fork.  Verify the
    # descriptors identify the exact runtime and state lock files, SIGKILL the
    # service-root Emacs, then prove a fresh daemon can start while that child
    # is alive.
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
    if ! kill -0 "$crash_child_pid" 2>/dev/null; then
      echo "tool child died before lock reacquisition completed" >&2
      exit 1
    fi
    kill "$crash_child_pid" >/dev/null 2>&1 || true
    crash_child_pid=

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
