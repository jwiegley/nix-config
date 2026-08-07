# Pi eight-hour soak: manual resumption

This procedure resumes the synthetic eight-hour memory gate for GitHub issue
`#128`. The gate is deferred until John explicitly requests it; no agent or
background automation is to begin it merely because other Project 9 work has
finished. It exercises a disposable synthetic session and never opens, copies,
or modifies the live GLM session.

The 2026-08-07 run already passed the issue-level duration and adjusted-RSS
criterion. Its stricter auxiliary checker remained incomplete because macOS
reported `/var` where the checker expected the equivalent `/private/var` path.
When this procedure is next used, compare canonical path identity rather than
literal path spelling.

## Preconditions

Begin only in a dedicated eight-hour window and from a clean checkout of the
candidate to be tested. Use a Mac connected to AC power, leave its lid open,
and keep the test in the foreground under `caffeinate`. The benchmark uses a
monotonic elapsed-time clock, while the additional message and compaction floors
prove sustained work. Record the commit, bind the test script and package
derivation to that clean tree, confirm that `.#pi` evaluates from the same
candidate, and ensure that Node 24 is selected. Do not combine the run with a
Nix update, system switch, activation, or live-session operation.

Start a dedicated `zsh`, enable fail-closed execution, and set the package and
interpreter paths from the locked flake:

```zsh
set -euo pipefail
test -z "$(git status --porcelain=v1)"

PI_SOAK_COMMIT=$(git rev-parse HEAD)
PI_SOAK_SCRIPT=test/ai/pi-session-memory.check.mjs
test "$(git hash-object "$PI_SOAK_SCRIPT")" = \
  "$(git rev-parse "$PI_SOAK_COMMIT:$PI_SOAK_SCRIPT")"
PI_SOAK_SCRIPT_SHA256=$(shasum -a 256 "$PI_SOAK_SCRIPT" | awk '{print $1}')
PI_SOAK_PACKAGE=$(nix build --no-link --print-out-paths .#pi)
PI_SOAK_PACKAGE_DRV=$(nix eval --raw .#pi.drvPath)
PI_SOAK_SYSTEM=$(nix eval --raw --impure --expr builtins.currentSystem)
PI_SOAK_NODE=$(nix eval --raw --impure --expr \
  "(builtins.getFlake (toString ./.)).inputs.nix-config-ai.inputs.nixpkgs.legacyPackages.${PI_SOAK_SYSTEM}.nodejs_24.outPath")
PI_SOAK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/pi-eight-hour-soak.XXXXXX")

test -n "$PI_SOAK_COMMIT"
test -n "$PI_SOAK_SCRIPT_SHA256"
test -e "$PI_SOAK_PACKAGE_DRV"
test -x "$PI_SOAK_NODE/bin/node"
test -d "$PI_SOAK_PACKAGE/lib/node_modules/@earendil-works/pi-coding-agent"
command -v caffeinate >/dev/null
PI_SOAK_NODE_VERSION=$("$PI_SOAK_NODE/bin/node" --version)
[[ "$PI_SOAK_NODE_VERSION" == v24.* ]]

{
  printf 'commit=%s\n' "$PI_SOAK_COMMIT"
  printf 'script=%s\n' "$PI_SOAK_SCRIPT"
  printf 'script_sha256=%s\n' "$PI_SOAK_SCRIPT_SHA256"
  printf 'package=%s\n' "$PI_SOAK_PACKAGE"
  printf 'package_drv=%s\n' "$PI_SOAK_PACKAGE_DRV"
  printf 'node=%s\n' "$PI_SOAK_NODE"
  printf 'node_version=%s\n' "$PI_SOAK_NODE_VERSION"
} > "$PI_SOAK_ROOT/lineage.txt"
```

The reported Node version is to begin with `v24.`.

## Run

Run the test in one foreground shell. The command retains its disposable JSONL
and index for later inspection; it does not use a production session.

```zsh
test -z "$(git status --porcelain=v1)"
test "$(git rev-parse HEAD)" = "$PI_SOAK_COMMIT"
test "$(shasum -a 256 "$PI_SOAK_SCRIPT" | awk '{print $1}')" = \
  "$PI_SOAK_SCRIPT_SHA256"

PI_SOAK_STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if TMPDIR="$PI_SOAK_ROOT" \
  PI_CODING_AGENT_ROOT="$PI_SOAK_PACKAGE/lib/node_modules/@earendil-works/pi-coding-agent" \
  PI_SESSION_KEEP=1 \
  PI_SESSION_SOAK_MS=28800000 \
  PI_SESSION_PAYLOAD_BYTES=32768 \
  PI_SESSION_COMPACTION_EVERY=16 \
  PI_SESSION_MIN_COMPACTIONS=1500 \
  PI_SESSION_CHECKPOINT_EVERY=60 \
  PI_SESSION_INTERVAL_MS=1000 \
    caffeinate -ims "$PI_SOAK_NODE/bin/node" "$PI_SOAK_SCRIPT" soak \
    2>&1 | tee "$PI_SOAK_ROOT/soak.log"; then
  PI_SOAK_STATUS=0
else
  PI_SOAK_STATUS=$?
fi
PI_SOAK_FINISHED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s\n' "$PI_SOAK_STATUS" > "$PI_SOAK_ROOT/status"
printf 'started_at=%s\nfinished_at=%s\n' \
  "$PI_SOAK_STARTED_AT" "$PI_SOAK_FINISHED_AT" \
  >> "$PI_SOAK_ROOT/lineage.txt"
test "$PI_SOAK_STATUS" -eq 0
test -z "$(git status --porcelain=v1)"
test "$(git rev-parse HEAD)" = "$PI_SOAK_COMMIT"
test "$(shasum -a 256 "$PI_SOAK_SCRIPT" | awk '{print $1}')" = \
  "$PI_SOAK_SCRIPT_SHA256"
```

Do not restart a failed or interrupted run under the same evidence identity.
Retain the log and disposable session, diagnose the failure, and begin any
approved retry in a new directory.

## Acceptance

The command itself enforces the 128 MiB adjusted-growth ceiling. Accept the
issue-level computational soak gate only when all of the following hold:

- `PI_SOAK_STATUS` is `0`;
- the final JSON object has `mode` equal to `soak`;
- `durationMs` is at least `28800000`;
- `adjustedGrowth` is less than `134217728`;
- `messages` is at least `24000`; and
- `compactions` is at least `1500`.

Extract the final object without assuming that checkpoint lines are absent:

```zsh
jq -Rsc '
  split("\n") |
  map(fromjson? | select(.mode == "soak")) |
  if length == 1 then .[0] else error("expected one final soak object") end
' \
  "$PI_SOAK_ROOT/soak.log" > "$PI_SOAK_ROOT/final.json"
jq -e '
  .mode == "soak" and
  .durationMs >= 28800000 and
  .adjustedGrowth < 134217728 and
  .messages >= 24000 and
  .compactions >= 1500
' "$PI_SOAK_ROOT/final.json"
```

Retained-path identity and evidence hashes are a separate auxiliary provenance
layer. They protect the artifact lineage but are not additional issue-level
memory-acceptance criteria. Verify and record them without changing the
computational verdict:

```zsh
test "$(jq -r '.retainedPath | type' "$PI_SOAK_ROOT/final.json")" = string
PI_SOAK_RETAINED=$(jq -r .retainedPath "$PI_SOAK_ROOT/final.json")
PI_SOAK_ROOT_REAL=$(realpath "$PI_SOAK_ROOT")
PI_SOAK_RETAINED_REAL=$(realpath "$PI_SOAK_RETAINED")
[[ "$PI_SOAK_RETAINED_REAL" == "$PI_SOAK_ROOT_REAL"/* ]]
test -f "$PI_SOAK_RETAINED_REAL"
test -f "$PI_SOAK_RETAINED_REAL.index.sqlite"
shasum -a 256 \
  "$PI_SOAK_ROOT/lineage.txt" \
  "$PI_SOAK_ROOT/status" \
  "$PI_SOAK_ROOT/soak.log" \
  "$PI_SOAK_RETAINED_REAL" \
  "$PI_SOAK_RETAINED_REAL.index.sqlite"
```

Before reporting the result, record the commit, package and Node store paths,
start and finish times, exit status, final JSON, and SHA-256 digests of the log,
retained JSONL, and SQLite sidecar. Preserve the distinction between this
synthetic soak and the separate Linux, large-fixture, activation, and direct
GLM-session continuity gates. The soak proves only bounded synthetic growth.

Retain the evidence until review is complete. Its removal is a separate,
explicit cleanup action.
