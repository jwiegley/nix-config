{
  anvilMcp,
  coreutils,
  lib,
  python3,
  runCommand,
  stdenv,
}:

runCommand "anvil-mcp-dedicated-smoke"
  {
    nativeBuildInputs = [
      anvilMcp
      anvilMcp.dedicatedEmacs
      coreutils
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
    ${lib.optionalString stdenv.isLinux ''
      install -d -m 0700 \
        "$ANVIL_EMACS_RUNTIME_ROOT" \
        "$ANVIL_EMACS_RUNTIME_ROOT/host-b" \
        "$ANVIL_EMACS_RUNTIME_ROOT/host-b/tmp"
      touch "$ANVIL_EMACS_RUNTIME_ROOT/host-b/tmp/stale-before-start"
    ''}

    pid_a=
    pid_b=
    cleanup() {
      status=$?
      set +e
      for host in host-a host-b; do
        socket="$ANVIL_EMACS_RUNTIME_ROOT/$host/emacs/server"
        if [ -S "$socket" ]; then
          ${anvilMcp.dedicatedEmacs}/bin/emacsclient             -s "$socket" -e '(kill-emacs)' >/dev/null 2>&1 || true
        fi
      done
      if [ -n "$pid_a" ]; then kill "$pid_a" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_b" ]; then kill "$pid_b" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_a" ]; then wait "$pid_a" >/dev/null 2>&1 || true; fi
      if [ -n "$pid_b" ]; then wait "$pid_b" >/dev/null 2>&1 || true; fi
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
    if ! ${python3}/bin/python ${./headless-smoke.py}       ${anvilMcp}/bin/anvil-mcp; then
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

    ${lib.optionalString stdenv.isLinux ''
      if [ -e "$ANVIL_EMACS_RUNTIME_ROOT/host-b/tmp/stale-before-start" ]; then
        echo "host runtime temp was not pruned after taking the state lock" >&2
        exit 1
      fi
      assert_status duplicate-state-lock "holds the state lock" 75 \
        env ANVIL_EMACS_HOST=host-a \
        ANVIL_EMACS_RUNTIME_ROOT="$ANVIL_EMACS_RUNTIME_ROOT" \
        ANVIL_EMACS_STATE_ROOT="$ANVIL_EMACS_STATE_ROOT" \
        ${anvilMcp}/bin/anvil-headless-emacs
    ''}

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

    worker_pids="$smoke_root/worker-pids"
    : >"$worker_pids"
    for host in host-a host-b; do
      for worker in \
        anvil-worker-read-1 \
        anvil-worker-read-2 \
        anvil-worker-write-1 \
        anvil-worker-batch-1; do
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
    if [ "$(wc -l <"$worker_pids" | tr -d '[:space:]')" -ne 8 ] \
      || [ "$(sort -u "$worker_pids" | wc -l | tr -d '[:space:]')" -ne 8 ]; then
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
    touch "$out"
  ''
