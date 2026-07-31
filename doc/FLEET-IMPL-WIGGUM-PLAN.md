# Fleet Programme Implementation — Frozen Plan and Definition of Done

**Created:** 2026-07-27
**Status:** FROZEN with respect to lowering the bar.
**Predecessor:** `doc/UNIFIED-CONFIG-WIGGUM-PLAN.md` (design phase, complete).
**Design corpus:** `doc/FLEET-DESIGN-PLAN.md`, `doc/FLEET-PROGRAMME-CROSS-STREAM.md`.
**Tracking:** [Fleet Configuration Programme](https://github.com/users/jwiegley/projects/9),
65 issues — `jwiegley/nix-config#16`–`#76`, `jwiegley/nixos-config#1`–`#4`.

## The ask

Implement the design. Track ongoing status in the relevant GitHub issue and close
each as it completes. Parallelize non-interfering work. Work on branches and
worktrees freely; at the end, rebase onto `main` and fast-forward merge back.

## Working constraints, inherited and binding

From `CLAUDE.md`, unchanged and not negotiable within this plan:

- **Signed commits only.** Stage explicit paths. Never hide unrelated work with
  `reset`/`restore`/`clean`/`stash` shortcuts. Never bypass hooks.
- **Push, force-push, every system or Home Manager activation (local or remote),
  and history rewrite each require explicit authorization for that action.**
  This plan does not carry that authorization. Worktree/branch creation and the
  terminal fast-forward merge into local `main` *are* authorized by the invocation.
- Never run `nix flake update` / `nix flake lock` under `sudo`.
- Do not display secret-bearing files or outputs; no SOPS decryption, no runtime
  secret files, no credential settings, no auth payloads.
- Fix root causes at the narrowest shared seam. Do not weaken or skip a failing
  gate to obtain green.

### Concurrency

`~/src/nix` has a **live concurrent autonomous writer** (a `pi` session, PID 28771,
committing to `main` and snapshotting every ~2 min). Therefore:

- All work happens in `/Users/johnw/src/nix-impl` on `impl/fleet-programme`.
- Never `git add` from the shared `~/src/nix` index.
- The terminal merge must re-check `main` immediately before `merge --ff-only`,
  and must abort rather than disturb another writer's uncommitted state.

## Authorization triage

Issues are separated by whether this session *can* finish them. This is a
statement of gating, not a reduction of scope.

| Class | Meaning | Disposition |
|---|---|---|
| **A — Landable** | Repo-local change in `~/src/nix`, verifiable by build/eval/test | Implement, verify, close |
| **B — External checkout** | Change in `~/src/nixos`, `~/src/vps`, `~/src/andoria`; those checkouts own their locks | Implement + verify by eval; **activation stays gated** |
| **C — Push-gated** | Cannot be verified or completed without publishing to a remote | Implement, verify locally, leave open with status |
| **D — Activation-gated** | Requires a system/HM switch on a live host | Prepare + rehearse, leave open with status |
| **E — Externally blocked** | Missing credential or upstream dependency | Document the block, leave open |

A class-C or class-D issue is **not** closed by this session. Its work is landed
and its issue carries a status comment naming exactly what authorization remains.

## Definition of Done

Exit only when all hold, each with cited evidence rather than assertion:

1. **DoD-1 — Stage 0 discharged.** The two armed consumers (`vulcan`,
   `vps`) no longer call overlay factories positionally. Evidence: the previously
   armed attribute paths evaluate at the new revision.
2. **DoD-2 — Every class-A issue is closed** with a status comment carrying its
   verification output, or is reclassified with a stated reason.
3. **DoD-3 — Every class-B/C/D/E issue carries a status comment** naming the work
   landed, the verification performed, and the precise authorization or
   dependency that remains. No issue is left silent.
4. **DoD-4 — Gates pass, output shown.** `nix flake check ./config/ai
   --all-systems --no-build`; `python3 -m unittest test/bin/update-overlay-test.py`;
   `make test`; `nix fmt` clean; `lefthook run pre-commit --all-files`.
5. **DoD-5 — Parity preserved.** No refactor changes the realized package set for
   `hera`, `clio`, or the work group except where an issue explicitly intends it.
   Evidence: drvPath or package-multiset comparison against a captured baseline.
6. **DoD-6 — Audited.** The final work commit passes an independent `fess` audit.
7. **DoD-7 — Observations drained.** No actionable `doc/observations/` entry
   outstanding at the last cleanup cycle.
8. **DoD-8 — Merged.** `impl/fleet-programme` rebased onto `main` and
   fast-forward merged into local `main`, with `main` verified unchanged by the
   concurrent writer across the merge. Not pushed.

## Never, under this plan

- Activate any system or Home Manager configuration, on any host.
- Push, force-push, or rewrite history on any remote.
- Weaken, skip, or delete a test to obtain green.
- Hardcode an output to satisfy a check.
- Close an issue whose acceptance criteria are not met by landed, verified work.

## Stop-and-escalate conditions

- The same gate fails 3 times without intervening progress.
- A rebase conflict cannot be resolved without guessing intent.
- A change would require activation or push to verify at all.
- The concurrent writer's state would have to be disturbed to proceed.
- A parity check fails and bisection does not localize the cause.

## Attempt counters

| Gate | Attempts | Status |
|---|---|---|
| `nix flake check ./config/ai --all-systems --no-build` | 0 | not yet run this phase |
| `python3 -m unittest test/bin/update-overlay-test.py` | 0 | not yet run this phase |
| `make test` | 0 | not yet run this phase |
| `nix fmt` clean | 0 | not yet run this phase |
| `lefthook run pre-commit --all-files` | 0 | not yet run this phase |
| Stage-0 unarm eval (vulcan) | 0 | not yet run |
| Stage-0 unarm eval (vps) | 0 | not yet run |
| drvPath parity baseline | 0 | not yet captured |

## Host facts — settled 2026-07-27, live evidence

Closed `#21`. These are inputs to the shared-`$HOME` work and are no longer open
questions:

- `/nix` is **host-local** on all four work machines (different backing devices;
  store populations differ by ~40k paths).
- Home Manager takes the **XDG profile branch**, `~/.local/state/nix/profiles`,
  which is **on the NFS `$HOME`** — so the four share **one profile symlink and one
  generation series**. Any machine's switch immediately repoints all four.
- **No automatic GC**: no nix/gc timers, no `min-free`/`max-free`/`auto-optimise`.
- `%l` expands live to the short hostname in a user unit; `Linger=yes` already set.
- **New:** intra-group Nix version skew — 2.33.3 / 2.33.3 / 2.34.6 / 2.34.7.
- **New:** `id -un` fails under non-interactive SSH on three of four (SSSD users);
  provisioning scripts must use `$USER` / `%u` / the literal.
