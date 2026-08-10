{
  coreutils,
  diffutils,
  findutils,
  lib,
  nodejs_22,
  piPackage,
  runCommand,
  sourceForChecks,
}:

runCommand "pi-fleet-theme-check"
  {
    nativeBuildInputs = [
      coreutils
      diffutils
      findutils
      nodejs_22
    ];
  }
  ''
    set -euo pipefail

    extension=${lib.escapeShellArg "${sourceForChecks}/config/ai/extensions/fleet-theme/index.ts"}

    scratch="$TMPDIR/rpc-negative"
    mkdir -p "$scratch/home" "$scratch/agent" "$scratch/project"
    printf '%s' '{}' >"$scratch/agent/auth.json"
    chmod 600 "$scratch/agent/auth.json"
    snapshot() {
      find "$scratch" -mindepth 1 -printf '%P|%y|%m|%l\n' | sort
      find "$scratch" -type f -print0 | sort -z | xargs -0 -r sha256sum
    }
    snapshot >"$TMPDIR/before"

    printf '%s\n' '{"type":"get_commands"}' | (
      cd "$scratch/project"
      HOME="$scratch/home" \
      PI_CODING_AGENT_DIR="$scratch/agent" \
      PI_OFFLINE=1 \
        timeout 60 ${lib.getExe piPackage} \
        --mode rpc --offline --no-session --no-context-files \
        --no-extensions --no-skills --no-prompt-templates --no-approve \
        --extension "$extension"
    ) >"$TMPDIR/rpc.stdout" 2>"$TMPDIR/rpc.stderr" || {
      cat "$TMPDIR/rpc.stderr" >&2
      exit 1
    }

    snapshot >"$TMPDIR/after"
    cmp "$TMPDIR/before" "$TMPDIR/after" || {
      diff -u "$TMPDIR/before" "$TMPDIR/after" >&2
      exit 1
    }

    mkdir -p "$out"
    touch "$out/passed"
  ''
