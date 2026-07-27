# Unified Fleet Configuration — Wiggum Handoff

**Plan:** `doc/UNIFIED-CONFIG-WIGGUM-PLAN.md` (frozen)
**Last updated:** 2026-07-27, session start
**Branch:** `main` in `~/src/nix`, 8 commits ahead of `origin/main`

## RESOLVED — concurrent autonomous writer in `~/src/nix`

**Escalated 2026-07-27; user chose worktree isolation. Never commit in `~/src/nix`
from this session.**

**Resolution.** All work for this task happens in a dedicated worktree:

```
/Users/johnw/src/nix          -> main                    (other session, untouched)
/Users/johnw/src/nix-design   -> design/unified-fleet    (this session)
```

Created with `git worktree add /Users/johnw/src/nix-design -b design/unified-fleet
8452497c` — branched from clean HEAD, so it does **not** carry the other session's
uncommitted work. A worktree has its own index and HEAD, so commits here cannot
race theirs. Integration into `main` is the user's call, later.

The two design documents were moved out of `~/src/nix/doc/` into the worktree, so
`~/src/nix` now contains *only* the other session's changes.

Another autonomous session is actively working in this repository:

- **PID 3343** — `claude --model claude-fable-5 --dangerously-skip-permissions
  --resume a92e4ed8-06af-4b74-95ec-382b44db31b4`, started Jul 25 08:08,
  **cwd `/Users/johnw/src/nix`**.
- It is mid-series on the source-catalog migration continuing commits
  `c4332fe6 → 598e1430 → 315291cc → 8a661b96`. Working files written at:
  `sources/pi.json` 11:31, `sources/ai.json` 12:10, `sources/anvil.json` 12:30,
  `sources/tools.json` 12:48 (staged, uncommitted).
- Its in-flight change refactors `mkSimpleGitHubBinary` from
  `version`/`rev`/`sha256` args to a `source` arg sourced from
  `packages/source-catalog.nix`, touching `config/zsh.nix` and seven overlays.

This session's working tree was **clean at 12:46:34** (session start); the
mutation appeared at 12:48. Both plausible internal causes were **eliminated**:

- The unit test suite does **not** mutate the tree — verified by cloning HEAD
  (`8452497c`) into a scratch dir and running `python3 -m unittest
  bin/update-overlay-test.py`: 20 tests pass, `git status` stays empty.
- The analysis workflow's agent transcripts were created at 12:53, *after* the
  12:48 mutation, and contain no mutating commands. The two `web-searcher`
  agents have only Perplexity/WebFetch tools and cannot write files.

**Action taken:** `doc/UNIFIED-CONFIG-WIGGUM-*.md` were briefly `git add`ed into
the shared index, which would have let the other session's next commit sweep them
up. They were unstaged with an explicitly path-scoped
`git restore --staged <those two files>`. The other session's staged
`sources/tools.json` and its nine unstaged working-tree edits were left exactly
as found. Nothing of theirs was reset, restored, stashed, or cleaned.

**Why this blocks committing:** `~/src/nix` has one index and one HEAD. Any
commit from this session races theirs, and either commit can capture the other's
files. Per the repository's own rule — preserve unrelated working-tree changes —
this session holds all commits in `~/src/nix` until the user decides.

Read-only analysis and design work continues safely and is unaffected.

## Tooling state

- Anvil MCP **available** on this host (dedicated backend; `git-status`,
  `file-batch`, `file-outline` probed successfully). Use progressive-disclosure
  reads and batched typed edits for the rest of the loop.
- Repos `~/src/nix`, `~/src/nixos`, `~/src/andoria` all had **clean** working
  trees at session start.
- `doc/observations/` does not exist → no partner observations outstanding.

## Progress

### Done

- Baseline recon of all three repositories.
- Confirmed cross-repo coupling inventory (see Findings below).
- Launched two `web-searcher` agents: flake/monorepo patterns, and host-variance
  plus secrets.
- Froze plan and Definition of Done.

### In flight

- `web-searcher` research (2 agents).

### Not started

- Deep per-dimension analysis workflow.
- PAL consensus.
- Design document.
- Migration plan.
- Baseline verification run (DoD-7).

## Findings so far (evidence-backed)

**F1 — `flake = false` erases the module API.** Both consumers reach into
`nix-config` internals by string path:
- `~/src/nixos/modules/users/home-manager/johnw.nix:24` hand-calls
  `import "${inputs.nix-config}/config/packages.nix"` with hand-assembled args.
- `~/src/nixos/overlays/default.nix:31,298,303,306` and
  `~/src/nixos/flake.nix:313,326` cherry-pick attributes out of *individual
  overlay files*, manually rebuilding `prevWithMyLib` because
  `overlays/00-lib.nix` is an undocumented prerequisite of `30-misc-tools.nix`.
  Overlay composition order is an implicit contract the consumer reproduces by
  hand.
- `~/src/andoria/flake.nix:406,432` does the same for `johnw.nix` and
  `packages.nix`.

**F2 — Each consumer fetches `nix-config` twice, with independently drifting
revisions.** Once as `flake = false` (whole tree) and once as a real flake at
`?dir=config/ai`:
- `~/src/nixos/flake.nix:48` + `:111`
- `~/src/andoria/flake.nix` (`nix-config` + `nix-config-ai`)
`test/ai/lock-coherence.nix` exists to police exactly this drift, but only
inside `nix-config` itself — the consumers have no such check.

**F3 — The stated closure rationale is largely stale, and the real constraint is
different.** `flake.lock` has 431 nodes: 426 `github:`, **1** `git+file://`,
**1** `git+ssh://`, 2 `path:`. The single `git+file://`
(`file:///Users/johnw/src/org2jsonl`) is **transitive**, leaked by the `obr`
input's own lock — the root's own `org2jsonl` is `github:`. `stock-trader` is
`git+ssh://gitea` (LAN-only). So consuming `nix-config` as a *real flake* is
blocked by exactly **two** tractable inputs, not by architecture. Furthermore
the constraint is about **lock-time input resolution**, not closure size: flake
outputs are lazily evaluated, so building one `homeConfigurations` attribute
never realizes `darwinConfigurations.hera`. *(Mechanism to be confirmed in
research — DoD-2.)*

**F4 — The work fleet has no build-time host identity.** `~/src/andoria/flake.nix:71`
hardcodes `hostname = "andoria-08"` and exports a single
`homeConfigurations.jwiegley`, yet serves four machines. True identity is
recovered at *runtime* by shelling out to `hostname` (agent-deck wrapper at
`flake.nix:371`, activation at `:529`). `config/johnw.nix:63` acknowledges this:
the comment states the shared flake "supplies `andoria-08` on every NFS client".
Consequently the build-time decision
`johnw.anvil.useHeadlessEmacs = lib.mkDefault (lib.elem hostname dedicatedAnvilLinuxHosts)`
is evaluated against a knowingly wrong hostname on 3 of 4 work machines.

**F5 — `inputs` is an unchecked, duck-typed contract.** The core accepts the
consumer's entire `inputs` attrset and probes it (`inputs ? git-ai`,
`inputs.foo or null`, `pkgs ? my-scripts`). Consumers must reverse-engineer the
required set; `~/src/andoria/flake.nix` carries the comment "PAL MCP server
source (needed by nix-config overlay 30-ai-mcp.nix)". `packages.nix`'s
`userPackageInputAllowlist` is the right instinct at the wrong layer.

**F6 — Version skew forces shims in consumers.** Vulcan pins HM `release-25.11`
while `nix-config` tracks HM master. The core uses master-only
`programs.ssh.settings`, so vulcan carries `ssh-settings-compat.nix`, plus a
fake `options.programs.git-ai` freeform stub to satisfy an *unconditional*
assignment in the core for an *optional* input.

**F7 — Variance by override rather than by parameter.** Per-host `lib.mkForce`
undoes core defaults: GPG signing disabled on vulcan, vps, and andoria;
`EDITOR`, `gh` editor, and git editor re-forced to vim on servers. The core
defaults to workstation behavior and every server fights it.

**F9 — The no-external-filesystem invariant test is one level too shallow.**
`bin/update-overlay-test.py:872` (`test_root_inputs_do_not_reference_external_filesystems`)
iterates only `lock["nodes"]["root"]["inputs"]`, so it validates *root* inputs
and never walks the transitive closure. The `obr` → `org2jsonl` →
`file:///Users/johnw/src/org2jsonl` leak from F3 therefore passes the test today.
Deepening this test to walk every node in `flake.lock` would both catch the
existing leak and turn "consumable as a real flake" into an enforced invariant —
this is the natural gate for the migration.

**F8 — Host-specific overlays stranded in a leaf repo.** `~/src/andoria/flake.nix`
carries ~250 lines of overlay fixes (git-branchless, libsecret, qdrant,
eternal-terminal, graphite-cli FHS, mitmproxy, optuna, pytest-postgresql,
mlx-speech). Most are **x86_64-linux** fixes, not andoria-specific, so any other
Linux host needing the same Python env would have to duplicate them.

## How to resume

1. Re-read `doc/UNIFIED-CONFIG-WIGGUM-PLAN.md` and this file in full.
2. Re-run baseline: `nix flake check ./config/ai --all-systems --no-build`.
3. Check `doc/observations/` for actionable entries.
4. Continue from the first unchecked item under "Not started".

## Attempt counters

See the plan's counter table. All at 0 as of this update.
