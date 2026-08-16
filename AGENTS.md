# CLAUDE.md

This file provides guidance to coding agents working in this repository.

## Start here

1. Read `README.md` and `doc/ARCHITECTURE.md`.
2. Read the active work item with `obr show <id>`; `doc/PLAN.org` is the tracked
   issue surface. Do not infer current work from old plans or handoffs; Git
   history preserves them.
3. Confirm `git status` and load the current direnv environment.

When GitHub work is explicitly authorized, select the `jwiegley` account for every
`gh` invocation without changing the global active account:

```bash
GH_TOKEN="$(gh auth token --hostname github.com --user jwiegley)" gh <command>
```

When a bounded workflow needs multiple isolated signing steps, reuse one private
workflow-scoped signer home and agent for those steps. Keep verification homes
separate and keyless, verify the exact signer and payload identity, and tear the
signer session down on success or failure. Never create a new signing home for
each step or disturb the long-lived login agent.

## Commands

```bash
# Baseline/focused tests
test/bin/unittest-strict.py test/bin/update-overlay-slow-test.py
nix flake check ./config/ai --all-systems --no-build
make test

# Darwin build without activation
./build system

# Package builds
./build pkg PACKAGE
./build python PACKAGE
./build haskell PACKAGE

# Formatting and repository hooks
nix fmt
lefthook run pre-commit --all-files
```

Never use `nix develop` to run commands for agent work. Do not install dependencies ad hoc. Add missing tools to the Nix environment, regenerate it with `de`, and reload direnv.

Never run `nix flake update` or `nix flake lock` under `sudo`; root and user fetcher caches can diverge and produce local-input NAR hash mismatches during activation. Run `make verify-inputs`, then `make lock-local` as the regular user to repair local locks. Only the final system activation command uses root.

## Architecture invariants

- Root implementation is owned here; portable AI is the `config/ai` subflake from the same revision.
- The root repository's portable core is `config/ai`; every supported consumer
  uses that path from the same revision. The #126 lock cutover is complete; no
  compatibility route exists at the retired path.
- `config/ai/catalog.nix` owns profiles/resources/selection; `config/ai/renderers/` are concrete client adapters.
- `packages/` owns reusable package sets and multi-consumer implementations. Overlays own ordered exposure, narrow compatibility fixes, and cohesive integration-specific package definitions; they must not hide host selection or unrelated implementation channels.
- Mutable agent state is not Nix-owned. Nix owns generated leaves only.
- Pi and Codex credentials stay environment-only. Never add request-time secret values to argv, config, logs, or generated files.
- Exact client behavior—model routing, headers, bindings, immutable gallery, session identity—is verified behaviorally, not inferred from source alone.

## Host ownership

- Hera/Clio: build from each host's `~/src/nix`; use nix-darwin.
- Shared-work Linux: build from each authoritative `~/.config/home-manager`; do not copy Hera's checkout over it.
- Vulcan: build from authoritative `/etc/nixos`; obey `/etc/nixos/.nixos-build` locking.
- VPS: parked/manual only. Build from authoritative `/etc/nixos`, obey its
  `.nixos-build` lock, and pass `--max-jobs 1 --cores 1` to both build and switch.
- Preserve existing local commits, lock updates, tmux sessions, and unrelated working-tree changes.

## Git and deployment

- Signed commits only.
- Stage explicit paths; never hide unrelated work with reset/restore/clean/stash shortcuts.
- Do not bypass hooks.
- Build and verify before activation.
- Push, force-push, every system/Home Manager activation (local or remote), and history rewrite require explicit authorization for that action.
- For long work, follow Wiggum: one logical unit, signed commit, independent fess audit, partner-observation cleanup, local currency checkpoint, durable handoff update.

## Security

Do not display secret-bearing files or outputs. In particular, never decrypt SOPS content, read runtime secret files, dump credential settings, or print API/auth payloads. Prefer structural metadata and field-targeted checks.

Discover executables only with `direnv exec . command -v <name>`. Never
recursively search home, filesystem roots, mounted volumes, Photos, Music, or
other TCC-protected locations for a command. Add a missing tool to `flake.nix`,
regenerate the environment with `de`, and reload direnv instead. When reporting
a refused or accidental discovery attempt, identify the initiating command but
redact private paths, arguments, and payloads.

## Quality bar

- Fix root causes at the narrowest shared seam.
- Keep tests that protect behavior, security, lifecycle, concurrency, and state ownership.
- Do not weaken or skip a failing gate to obtain green.
- Delete obsolete compatibility only after all maintained consumers are searched.
- Keep current authority separate from historical evidence; Git is the default archive.

<!-- obr-agent-instructions-v1 -->

---

## Obr Workflow Integration

This project uses [obr](https://github.com/jwiegley/obr) for issue tracking.
Issues live in `PLAN.org` — an Org-mode file tracked in git, at `doc/`,
`docs/`, or the project root. `.obr/` is a per-machine cache (SQLite plus
metadata) that ignores itself; never commit anything under it. obr never
commits, pushes, pulls, or installs hooks: exporting and committing are
separate, explicit steps. (A few read-only commands do shell out to git to
report what it sees — `vcs-status`, `changelog`, `orphans` — and none of them
write.)

### Essential Commands

```bash
# View ready issues (open, unblocked, not deferred)
obr ready

# List and search
obr list --status=open # All open issues
obr show <id>          # Full issue details with dependencies
obr search "keyword"   # Full-text search

# Create and update
obr create "Title" -d "..." --type=task --priority=2
obr q "Title"          # Quick capture: create and print only the id
obr update <id> --status=in_progress
obr close <id> --reason="Completed"
obr close <id1> <id2>  # Close multiple issues at once

# Write the tracked surface
obr sync --flush-only  # Write PLAN.org from the database
obr sync --status      # Check whether DB and PLAN.org agree
```

### Workflow Pattern

1. **Start**: Run `obr ready` to find actionable work
2. **Claim**: Use `obr update <id> --status=in_progress`
3. **Work**: Implement the task
4. **Complete**: Use `obr close <id> --reason="..."`
5. **Record**: Run `obr sync --flush-only`, then commit `PLAN.org` with the code

### Key Concepts

- **Dependencies**: Issues can block other issues. `obr ready` shows only open, unblocked work.
- **Priority**: P0=critical, P1=high, P2=medium, P3=low, P4=backlog (use numbers 0-4, not words)
- **Types**: task, bug, feature, epic, chore, docs, question
- **Blocking**: `obr dep add <issue> <depends-on>` to add dependencies
- **Recording discovered work**: create an issue the moment you find work you are not doing now, and link it (`--deps discovered-from:<id>`)

### Session Protocol

**Before ending any session, run this checklist:**

```bash
obr sync --flush-only   # Write issue changes to PLAN.org
git status              # Check what changed
git add <files>         # Stage code changes AND PLAN.org together
git commit -m "..."     # One commit: the change and its issue state
```

### Best Practices

- Check `obr ready` at session start to find available work
- Record dependencies at creation time — they are what make `obr ready` meaningful
- Update status as you work (in_progress → closed)
- Use descriptive titles and set appropriate priority/type
- Commit `PLAN.org` together with the code that changes it; its diff is the review trail
- A fresh clone rebuilds the cache with: `obr init && obr sync --import-only --rebuild`

<!-- end-obr-agent-instructions -->
