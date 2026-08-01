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
      jq
      nodejs_22
    ];
  }
  ''
    set -euo pipefail

    theme=${lib.escapeShellArg "${sourceForChecks}/config/fleet/themes/dark-tool-backgrounds.json"}
    extension=${lib.escapeShellArg "${sourceForChecks}/config/fleet/extensions/fleet-theme/index.ts"}
    expected=03ecec59f47f49b6562f95101d58ae6338377e0d9b84b6410e065f28e2c18d5a

    test "$(sha256sum "$theme" | cut -d ' ' -f 1)" = "$expected"
    jq -e '
      (keys | sort) == ["$schema", "colors", "export", "name", "vars"]
      and .name == "dark-tool-backgrounds"
      and (.colors | length) == 52
    ' "$theme" >/dev/null

    (
      cd ${sourceForChecks}/test/ai/extensions/fleet-theme
      bun test index.test.ts
    )

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
