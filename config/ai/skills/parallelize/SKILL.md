---
name: parallelize
description: Offload safe, independent subtasks to concurrent subagents while continuing
  your own work as the coordinator, then integrate what they return. Use when mid-task
  and some work could run in parallel without conflicting -- research, generating
  a standalone new file, tests for a stable interface, docs, or isolated analysis
  -- to accelerate without races. The coordinator alone runs git and mutates shared
  state; subagents read freely but write only to isolated namespaces and hand back
  artifacts. Triggers include "parallelize this", "spin up subagents to help", "do
  these in parallel", "fan this out".
---
# Parallelize

Dispatch independent work to subagents that run CONCURRENTLY with your own, while you -- the coordinator -- remain the single owner of all shared state. Subagents read the codebase and write only inside their own isolated namespace, then hand back artifacts you integrate. You alone run git and mutate anything shared.

Use this when you are mid-task and some subtasks can safely run in parallel to accelerate you. It is neither the debugging fan-out of `dispatching-parallel-agents` nor the serial, self-committing loop of `subagent-driven-development` (see Relationship to sibling skills).

## The invariant

**The coordinator is the only actor that mutates shared state.** A subagent may READ anything, but may WRITE only inside a unique namespace you assign it. Everything outside that namespace is immutable to it, and you -- not the subagent -- perform every change to canonical state.

Shared state is far more than the working tree. A subagent must NOT, directly or as a side effect of any command:

- run git in any form -- add, commit, branch, rebase/restack, push, tag; subagents share your index and `index.lock`, so even a concurrent `git status` or `git add` can abort your commit or wedge the repo with a stale lock;
- edit files you are editing, or any file outside its namespace;
- install or update dependencies or lockfiles (`npm`/`pip`/`cargo`/`go` installs, `package-lock.json`, `poetry.lock`);
- write shared caches, build/test artifacts, or generated files (`.pytest_cache`, coverage, `dist/`, `target/`, `node_modules`);
- trigger side-effect writes outside its namespace: format/lint-on-save, an editor/LSP daemon, git hooks or pre-commit frameworks, or tool-dropped files like `.DS_Store`;
- bind a shared port, start a daemon or watcher, or leave a background process running;
- touch a shared database, container, cloud resource, global config, auto-loaded `.env`, or `.git` metadata;
- follow a symlink out of its namespace, or create obvious-named new top-level paths that could collide with you or a sibling.

If a task cannot finish without one of these, it is not parallelizable -- do it serially. Full enumeration and per-ecosystem isolation recipes: `references/parallelize-playbook.md`.

## When to use / when not to use

Parallelize when the work is largely READ-ONLY against shared state, produces a self-contained artifact, and you do not need the result for your very next step. Default posture: read-only fan-out is almost always safe; treat every task that writes as suspect until it passes the checklist.

Do NOT parallelize:

- trivial or small work (roughly a handful of files or fewer) -- inline is cheaper than the coordination overhead;
- anything you need right now to make your next edit (a serial dependency);
- work whose write set overlaps yours or another subagent's.

Cap concurrency at what you can review, roughly 3-5. The bottleneck is YOUR capacity to review and integrate returns, not compute. If candidates exceed the cap, dispatch one wave, integrate it, then dispatch the next -- do not fire everything at once.

## Safety checklist -- run before dispatching each task

Dispatch only if every answer is yes; any "no" or "unsure" keeps the task serial:

1. **Stable reads** -- it does not depend on state you will change, OR have already changed but not committed, before you integrate it. (A worktree cannot see your uncommitted edits -- see Isolation and integration.)
2. **Disjoint writes (two axes)** -- its write set is disjoint from your in-flight edits AND from every other concurrent subagent's, and stays disjoint for the whole dispatch (you freeze your own write set in step 1).
3. **Environmental isolation** -- it finishes while touching nothing shared: no git, installs, lockfiles, shared caches or build dirs, ports, daemons, hooks, or global config; every write, temp included, lands in its namespace (`TMPDIR` and tool caches redirected there).
4. **Self-contained artifact** -- it produces a complete file or report at a unique path inside its namespace, plus a short summary; it does not pass a large payload back through the conversation.
5. **Integration independence** -- you can keep working without blocking on its return.
6. **Verifiable and cleanable** -- you can inspect it, integrate it, test the end state, and remove its namespace afterward.

## Good candidates vs anti-patterns

| Good candidates (read-mostly, isolated output) | Anti-patterns (shared-state races) |
|---|---|
| Research, investigation, codebase Q&A | A subagent that runs git or commits |
| Generating a standalone NEW file you wire in later | Two subagents editing the same file or conceptual module |
| Tests for an already-stable interface | Integration-heavy refactor (rename touching many files) |
| Drafting docs or comments | `npm`/`pip install`, lockfile or dependency updates |
| Isolated analysis or benchmark in its own dir | Building/testing in the shared tree or writing shared caches |
| Data extraction or transformation to a new file | Starting a server/daemon or binding a fixed port |
| Reviewing a subset of files (read-only) | A task needing output for your NEXT edit, or reading your uncommitted edits |
| Prototyping in a throwaway location | Secrets handling; interactive or unbounded tasks; a subagent spawning subagents |

## Subagent brief -- the four required parts

Each subagent starts fresh with none of your context, so state everything explicitly. A good brief has four parts (fill-in template and worked examples in `references/parallelize-playbook.md`):

1. **Objective** -- one clear sentence of what to produce and how it fits the larger goal.
2. **Output** -- the exact UNIQUE path inside its namespace to write to (never a canonical source path), and the instruction to return only a short summary plus that path.
3. **Inputs / guidance** -- which files to read and what to search for; and, because a worktree cannot see your uncommitted work, the current content of any file you have changed but not committed that it must build on.
4. **Explicit boundaries (negative scope)** -- what NOT to touch: name your in-flight files and each sibling subagent's files, and restate the hard rules (no git, no installs, no servers, write only inside its namespace). This negative-scope line is the single largest quality lever -- it is what prevents duplicated work and silent collisions.

## Coordinator procedure

1. State the goal and FREEZE your own in-flight write set for the dispatch window.
2. Enumerate candidate subtasks; run each through the safety checklist; keep only those that pass.
3. Assign each surviving task a non-overlapping id and an isolated namespace named `wg-<short-id>/<task>`, located OUTSIDE the working tree (a sibling dir or scratch/temp path) or gitignored -- never a plain in-tree dir that your `git status` would surface.
4. Write a complete four-part brief per task.
5. Dispatch a wave together (at most 3-5) so they run concurrently.
6. Continue your own work -- but stay within your frozen write set; do not start editing a file you handed to a subagent.
7. As each returns: re-verify its write set stayed disjoint AND that you did not wander into it; scan for stray writes outside its namespace; then integrate its artifact yourself. Place a new file directly; for a rewrite of an existing file, re-diff against the version the subagent started from and merge -- never blind-overwrite, since the subagent may have read a stale copy.
8. After integrating, run the full build and tests ONCE against the end state -- do not trust per-subagent self-reports.
9. Commit as atomic logical units. You are the only actor that runs git; stage explicit paths, never `git add -A` while a namespace exists.
10. Only after everything is integrated and green, remove each worktree with `git worktree remove <path>` (it refuses if work is un-integrated -- treat a refusal as "not yet integrated, do not force"), then `git worktree prune`. Delete plain scratch dirs only after integration, never before. Never `rm -rf` a worktree.

## Isolation and integration

- A worktree is checked out at a committed ref and CANNOT see your uncommitted or unstaged edits. This skill runs while you are mid-edit, so that is the common case, not an edge case: before dispatching a worktree-based subagent, commit or stash what it must read, paste the changed files' current content into its brief, or keep the task read-only against the live working tree instead.
- For worktree creation and detection mechanics, defer to `using-git-worktrees`. This skill adds the concurrency layer: the stable `wg-<short-id>/<task>` prefix (from `fix-all`) so parallel isolates are easy to find and clean up, kept outside the tree or gitignored; plus unique build/output/cache/temp dirs and unique ports, DB, and resource names per subagent.
- Isolation is not free: a worktree still needs its own dependency install and its own build dir, and YOU still own all merge and integration bookkeeping.
- Prefer NEW files over rewrites, and complete files over patches. A subagent writes a finished artifact into its namespace; you place or merge it. Do not rely on LLM-generated diffs -- they hallucinate line numbers and fail silently -- but do not blind-overwrite either (step 7).
- Optionally route the integrated change through `requesting-code-review` before committing.

## Relationship to sibling skills

- **`dispatching-parallel-agents`** owns the raw dispatch mechanic (multiple dispatches in one turn run in parallel) and the independence test, framed around debugging multiple failures with the dispatcher idle while workers run. `parallelize` differs in that you keep editing concurrently and remain the sole mutator of shared state with exclusive git ownership -- the discipline that skill does not cover.
- **`subagent-driven-development`** also targets independent tasks, but runs them one implementer at a time, each committing its own work behind a per-task review gate. `parallelize` runs disjoint workers concurrently and never lets a worker commit -- you are the sole integrator and committer. Prefer it for a review-gated commit per task; prefer `parallelize` when the work is provably disjoint and you want concurrency.
- **`using-git-worktrees`** owns the worktree creation and detection mechanics this skill builds on.
- **`fix-all`** is the source of the `wg-<id>/<task>` prefix and the "nothing orphaned" cleanup guarantee.
