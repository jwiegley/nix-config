{
  anvilMcp,
  python3,
  runCommand,
}:

runCommand "anvil-mcp-dedicated-smoke"
  {
    nativeBuildInputs = [
      anvilMcp
      anvilMcp.dedicatedEmacs
      python3
    ];
  }
  ''
    smoke_root=$(mktemp -d /tmp/anvil-mcp-smoke.XXXXXX)
    export HOME="$smoke_root/home"
    export ANVIL_EMACS_RUNTIME_ROOT="$smoke_root/runtime"
    export ANVIL_EMACS_STATE_ROOT="$smoke_root/state"
    mkdir -p "$HOME/org" "$ANVIL_EMACS_RUNTIME_ROOT" "$ANVIL_EMACS_STATE_ROOT"
    printf '%s\n' '* Headless Anvil' 'headlessorgneedle headlesssemanticneedle'       >"$HOME/org/smoke.org"

    pid_a=
    pid_b=
    cleanup() {
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
    }
    trap cleanup EXIT

    (
      sleep 1
      export ANVIL_EMACS_HOST=host-a
      exec ${anvilMcp}/bin/anvil-headless-emacs
    ) >"$TMPDIR/host-a.log" 2>&1 &
    pid_a=$!
    ANVIL_EMACS_HOST=host-b       ${anvilMcp}/bin/anvil-headless-emacs >"$TMPDIR/host-b.log" 2>&1 &
    pid_b=$!

    # Invoke the launcher before host-a has a socket. This proves that an MCP
    # client started during login or a service restart waits for readiness.
    if ! ${python3}/bin/python ${./headless-smoke.py}       ${anvilMcp}/bin/anvil-mcp; then
      cat "$TMPDIR/host-a.log" "$TMPDIR/host-b.log" >&2
      exit 1
    fi

    if [ ! -S "$ANVIL_EMACS_RUNTIME_ROOT/host-a/emacs/server" ]       || [ ! -S "$ANVIL_EMACS_RUNTIME_ROOT/host-b/emacs/server" ]; then
      cat "$TMPDIR/host-a.log" "$TMPDIR/host-b.log" >&2
      exit 1
    fi

    for cache in       "$ANVIL_EMACS_STATE_ROOT/host-a/tmp/anvil-schema-cache.el"       "$ANVIL_EMACS_STATE_ROOT/host-b/tmp/anvil-schema-cache.el"; do
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
    touch "$out"
  ''
