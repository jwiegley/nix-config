# Parallelize -- playbook and reference

Supporting material for the `parallelize` skill: the full subagent brief template, resource-isolation recipes per ecosystem, worked examples, and the evidence base. Load this when writing a brief or setting up isolation.

## Full subagent brief template

Fill every section. The subagent has none of your context -- it starts blank.

```text
OBJECTIVE
  One sentence: exactly what to produce, and how it fits the larger goal.

OUTPUT
  Write your result ONLY inside your namespace, e.g. wg-<id>/<task>/result.<ext>
  -- a unique path OUTSIDE the repo working tree (or gitignored), never a canonical
  source path like src/foo.ts.
  Return ONLY a 2-4 sentence summary plus that path. Do NOT paste file contents back.

INPUTS / GUIDANCE
  Read: the files and dirs to read for context.
  Find: what to grep or search for.
  Already decided (do not revisit): interfaces, names, and choices already made.
  Uncommitted context: the current content of any file the coordinator has changed
  but not committed that you must build on (a worktree cannot see those edits).

BOUNDARIES (do NOT cross)
  - Do NOT run git at all (no add/commit/branch/rebase/push/tag/status); you share
    the coordinator's index and lock.
  - Do NOT install or update dependencies or lockfiles.
  - Do NOT start a server, bind a port, or leave a background process.
  - Do NOT trigger writes outside your namespace: format-on-save, git hooks, LSP daemons.
  - Write ONLY inside your namespace. Do NOT modify: the coordinator's in-flight files,
    or any file owned by a sibling subagent (list them explicitly).
  - If you cannot finish without crossing a boundary, STOP and report why.

VERIFICATION
  Before returning, confirm: how the subagent should self-check its artifact.
```

The BOUNDARIES block is the highest-leverage part. Name the coordinator's in-flight files and each sibling subagent's files explicitly -- a subagent cannot infer what to avoid.

## What counts as shared state (never mutate from a subagent)

| Category | Examples |
|---|---|
| Version control | `.git/`, index, `index.lock`, refs, worktree metadata; any git subcommand |
| Source tree | any file the coordinator or a sibling is editing |
| Dependencies | `node_modules`, `.venv`, `package-lock.json`, `poetry.lock`, `Cargo.lock` |
| Build/test artifacts | `dist/`, `target/`, `build/`, `.pytest_cache`, coverage, snapshots |
| Caches | `~/.cache`, `~/.npm`, language and tool caches |
| Side-effect writes | format/lint-on-save, editor/LSP daemons, git hooks, pre-commit frameworks, `.DS_Store` |
| Services and ports | dev servers, daemons, watchers, fixed ports |
| Data stores | shared databases, Redis, containers, message queues |
| Global / config | `~/.gitconfig`, global tool settings, environment, secrets, auto-loaded `.env` |
| Paths | symlinks that escape the namespace; predictable shared temp paths |
| Cloud | any remote or cloud resource write |

## Isolation recipes

Give each subagent its own everything, and redirect caches and temp into its namespace so nothing leaks into shared state. Let `NS` be the assigned namespace (outside the working tree or gitignored), e.g. `wg-<id>/<task>`.

- Generic (required): the subagent writes only under `$NS`; set `TMPDIR=$NS/tmp` so temp files cannot collide with the coordinator or a sibling.
- Node: only inside a coordinator-provisioned worktree, set `npm_config_cache=$NS/.npm`; a bare subagent must not run `npm install` at all, since that rewrites the shared lockfile and store.
- Python: run tests only inside a coordinator-provisioned worktree with its own venv; set `XDG_CACHE_HOME=$NS/.cache` and `PYTEST_ADDOPTS=-p no:cacheprovider` so caches stay local.
- Rust: `CARGO_TARGET_DIR=$NS/target`.
- Go: `GOCACHE=$NS/.gocache`.
- Servers: prefer not to delegate server-run tasks. If truly unavoidable, bind an ephemeral port (`PORT=0`), capture the assigned port, and guarantee teardown even on error (trap/finally) -- a leaked listener violates the no-daemon rule.

## Worked examples

### Safe -- generate a standalone new file

Task: write a new Stripe adapter implementing an already-agreed interface.
The subagent writes to `wg-<id>/<task>/stripe.ts` (its namespace), reads the rest of the tree read-only, and returns a summary plus that path. The coordinator places it at `src/adapters/stripe.ts`, wires it in, and commits. Safe because the artifact never lands at a canonical path from the subagent and nothing else touches the new file.

### Safe -- read-only analysis

Task: audit every call site of `deprecatedFn` and produce a migration report to `$NS/report.md`.
Pure read; the output is a report at a unique path; the coordinator decides what to do with it. Several of these can fan out at once.

### Unsafe -- "just add the dependency and update the tests"

The install rewrites the shared lockfile and `node_modules`, and running the suite writes shared caches -- both race the coordinator and other subagents. Keep it serial, or give the subagent a coordinator-provisioned worktree with its own install.

### Unsafe -- rename a core function

It touches many files, guaranteeing overlap with the coordinator and merge conflicts. This is integration-heavy; the coordinator does it serially.

## Evidence base

- Orchestrator-worker with a single synthesizing lead is a validated pattern; the lead is a deliberate synchronous bottleneck and the sole integrator. (Anthropic, "How we built our multi-agent research system.")
- The largest single quality lift was a four-part brief with explicit negative scope; vague briefs cause duplicated work and silent gaps. (ibid.)
- Subagents should write to the filesystem and return lightweight references, not large payloads through the conversation, which loses fidelity. (ibid.)
- Reviewer and coordinator capacity, not compute, is the real bottleneck; roughly 3-5 concurrent workers is the practical ceiling, past which output piles up unreviewed. (Practitioner consensus; Simon Willison; Firecrawl.)
- Coding parallelizes less than research; mutate tasks create compounding state dependencies, so read-only fan-out is the natural fit, and verifying the end state beats trusting per-subagent self-reports. (Anthropic.)
- Git worktrees isolate write collisions but not coordination, dependency setup, or merge tracking; the coordinator still owns integration bookkeeping. (Firecrawl.)
