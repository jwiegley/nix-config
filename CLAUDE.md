# CLAUDE.md

This file provides guidance to coding agents working in this repository.

## Start here

1. Read `README.md` and `doc/ARCHITECTURE.md`.
2. Read the active work item named by the task. Fleet and architecture work is tracked issue-by-issue in the [Fleet Configuration Programme](https://github.com/users/jwiegley/projects/9); each issue carries its own evidence, acceptance criteria, verification commands, rollback, and authorization. [GitHub issue #15](https://github.com/jwiegley/nix-config/issues/15) is the archived 2026-audit record — historical evidence, not current authority. Issues concerning only vulcan's NixOS configuration live in [jwiegley/nixos-config](https://github.com/jwiegley/nixos-config/issues).
3. Confirm `git status` and load the current direnv environment.

## Commands

```bash
# Baseline/focused tests
python3 -m unittest -v bin/update-overlay-test.py
nix flake check ./config/fleet --all-systems --no-build
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

- Root implementation is owned here; portable AI is the `config/fleet` subflake from the same revision.
- The root repository's portable core is `config/fleet`. Until #47's separately authorized consumer URL moves land, external consumers still declare paired root and legacy `?dir=config/ai` inputs; locking that legacy path at or beyond the rename must fail with the throwing-stub message. Move both paired lock nodes coherently in each authoritative checkout.
- `config/fleet/catalog.nix` owns profiles/resources/selection; `config/fleet/renderers/` are concrete client adapters.
- `packages/` owns package implementation. Overlays should expose or narrowly override packages, not hide unrelated package bodies.
- Mutable agent state is not Nix-owned. Nix owns generated leaves only.
- Pi and Codex credentials stay environment-only. Never add request-time secret values to argv, config, logs, or generated files.
- Exact client behavior—model routing, headers, bindings, immutable gallery, session identity—is verified behaviorally, not inferred from source alone.

## Host ownership

- Hera/Clio: build from each host's `~/src/nix`; use nix-darwin.
- Shared-work Linux: build from each authoritative `~/.config/home-manager`; do not copy Hera's checkout over it.
- Vulcan/VPS: build from authoritative `/etc/nixos`; obey `/etc/nixos/.nixos-build` locking.
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

## Quality bar

- Fix root causes at the narrowest shared seam.
- Keep tests that protect behavior, security, lifecycle, concurrency, and state ownership.
- Do not weaken or skip a failing gate to obtain green.
- Delete obsolete compatibility only after all maintained consumers are searched.
- Keep current authority separate from historical evidence; Git is the default archive.
