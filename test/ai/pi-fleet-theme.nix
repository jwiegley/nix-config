{
  bun,
  coreutils,
  diffutils,
  findutils,
  jq,
  lib,
  nodejs_22,
  piPackage,
  runCommand,
  sourceForChecks,
}:

runCommand "pi-fleet-theme-check"
  {
    nativeBuildInputs = [
      bun
      coreutils
      diffutils
      findutils
      nodejs_22
    ];
  }
  ''
    set -euo pipefail

    scratch="$TMPDIR/rpc-negative"
    mkdir -p \
      "$scratch/home" \
      "$scratch/agent/extensions/fleet-theme" \
      "$scratch/agent/themes" \
      "$scratch/project"
    cat >"$scratch/agent/extensions/fleet-theme/index.ts" <<'EOF'
    import fleetTheme from ${builtins.toJSON "${sourceForChecks}/config/ai/extensions/fleet-theme/index.ts"};

    export default function fleetThemeWithTestSentinel(pi) {
      fleetTheme(pi);
      pi.registerCommand("fleet-theme-test-loaded", {
        description: "Test-only auto-discovery sentinel",
        handler: async () => {},
      });
    }
    EOF
    cp ${lib.escapeShellArg "${sourceForChecks}/config/ai/themes/dark-tool-backgrounds.json"} \
      "$scratch/agent/themes/dark-tool-backgrounds.json"
    printf '%s' '{}' >"$scratch/agent/auth.json"
    chmod 600 "$scratch/agent/auth.json"
    HOME="$scratch/home" \
      PI_CODING_AGENT_DIR="$scratch/agent" \
      ${lib.getExe bun} test \
      ${lib.escapeShellArg "${sourceForChecks}/test/ai/extensions/fleet-theme/index.test.ts"}
    test ! -e "$scratch/agent/models-store.json" \
      || { echo "Fleet Theme created Pi core model-store state" >&2; exit 1; }
    printf '%s' '{}' >"$scratch/agent/models-store.json"
    chmod 600 "$scratch/agent/models-store.json"
    snapshot() {
      find "$scratch" -mindepth 1 -printf '%P|%y|%m|%l\n' | sort
      find "$scratch" -type f -print0 | sort -z | xargs -0 -r sha256sum
    }
    snapshot >"$TMPDIR/before"

    cat >"$TMPDIR/network-guard.cjs" <<'EOF'
    const fs = require("node:fs");
    const net = require("node:net");

    fs.writeFileSync(process.env.PI_NETWORK_GUARD_LOADED_FILE, "loaded\n");
    net.Socket.prototype.connect = function () {
      fs.appendFileSync(process.env.PI_NETWORK_ATTEMPT_FILE, "connect\n");
      throw new Error("network connection attempted before Pi became ready");
    };
    EOF
    : >"$TMPDIR/network-attempts"
    if NODE_OPTIONS="--require=$TMPDIR/network-guard.cjs" \
      PI_NETWORK_ATTEMPT_FILE="$TMPDIR/network-attempts" \
      PI_NETWORK_GUARD_LOADED_FILE="$TMPDIR/network-guard-loaded" \
      ${lib.getExe nodejs_22} -e 'require("node:net").connect(9, "127.0.0.1")' \
      >/dev/null 2>&1; then
      echo "network guard did not reject its positive control" >&2
      exit 1
    fi
    grep -Fx 'connect' "$TMPDIR/network-attempts" >/dev/null
    : >"$TMPDIR/network-attempts"
    rm -f "$TMPDIR/network-guard-loaded"

    printf '%s\n' '{"type":"get_commands"}' | (
      cd "$scratch/project"
      HOME="$scratch/home" \
      NODE_OPTIONS="--require=$TMPDIR/network-guard.cjs" \
      PI_CODING_AGENT_DIR="$scratch/agent" \
      PI_NETWORK_ATTEMPT_FILE="$TMPDIR/network-attempts" \
      PI_NETWORK_GUARD_LOADED_FILE="$TMPDIR/network-guard-loaded" \
      PI_OFFLINE=1 \
        timeout 60 ${lib.getExe piPackage} \
        --mode rpc --offline --no-session --no-context-files \
        --no-skills --no-prompt-templates --no-approve
    ) >"$TMPDIR/rpc.stdout" 2>"$TMPDIR/rpc.stderr" || {
      cat "$TMPDIR/rpc.stderr" >&2
      exit 1
    }
    test -s "$TMPDIR/network-guard-loaded"
    test ! -s "$TMPDIR/network-attempts"
    ${lib.getExe jq} -s -e '
      any(
        .[];
        .type == "response"
        and .command == "get_commands"
        and .success == true
        and any(.data.commands[]; .name == "fleet-theme-test-loaded")
      )
    ' "$TMPDIR/rpc.stdout" >/dev/null

    snapshot >"$TMPDIR/after"
    cmp "$TMPDIR/before" "$TMPDIR/after" || {
      diff -u "$TMPDIR/before" "$TMPDIR/after" >&2
      exit 1
    }

    mkdir -p "$out"
    touch "$out/passed"
  ''
