# Cleanup Wiggum Handoff

Updated: 2026-08-03

## Objective

Complete cleanup epic `jwiegley/nix-config#98` and all native sub-issues
`#99`-`#121` under the frozen Definition of Done in `doc/CLEANUP-PLAN.md`.

## Current authoritative state

- Source baseline: `cf2056ec0a3681d9ef95ede54b4c5574ad33b008`.
- Local `main`, fetched `origin/main`, and fetched `github/main` form the baseline
  at that commit. The current signed C0 branch is one documentation commit atop it.
- Checkout: `/Users/johnw/src/nix`; branch `cleanup/c0-doc-authority`; one worktree.
- Intentional C0 files include the formerly untracked cleanup plan and this
  handoff.
- Epic #98 and C0 #99 are In Progress; #100-#121 are Todo.
- GitHub snapshot observed at `2026-08-03T07:15:18Z`: 24 repository issues open,
  exactly #98-#121; Project 9 contains 110 items.
- Portable assurance run `30788387383` passed on the baseline on 2026-08-03.
- Normal CI run `30715313370` remains red from structural-coverage Nix identity
  drift.
- Hera active system profile: `system-984-link`.
- Clio remains DNS-unresolvable; this is a live blocker only for the issues whose
  bodies require Clio evidence.

## Work state

- Active unit: C0 / issue #99, truthful current documentation.
- The current local C0 commit is signed and changes exactly README, CLAUDE, the
  architecture/current-work docs, this handoff, and the frozen plan.
- Baseline fast gate passed in 57.7 seconds; full `make test` passed. The C0
  candidate passed post-edit in 61.91 seconds, and every commit/amend hook has
  remained below 120 seconds; links, references, typos, and `git diff --check`
  also passed.
- The first independent fess findings were corrected in the current amended
  commit. C0 is at the audit/closeout boundary: inspect the latest fess report,
  fix any real finding, or locally merge after a clean verdict.

## Issue/DAG invariants

- 23 native sub-issues under #98.
- 55 native blocked-by edges.
- Each issue body owns its requirements, subtasks, acceptance, verification,
  rollback, and authorization boundary.
- Move an issue to Done and close it only after its focused gate and independent
  fess audit pass.

## Stop counters

- repeated gate failure: 0/3
- unusable subagent output: 0/2
- unresolved destructive/intent-sensitive action: none

## Resume procedure

1. Re-read `doc/CLEANUP-PLAN.md` and this handoff fully.
2. Run `git status --short --branch` and compare fetched remote tips.
3. Check Project 9 status for #98-#121 with the explicit `jwiegley` account.
4. Resume the active issue named above; do not skip native blocked-by edges.
5. Run focused verification, commit signed with explicit paths, dispatch fess, and
   update the issue/project only after the audit is clean and publication state is
   represented honestly.
