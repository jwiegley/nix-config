# Cleanup Wiggum Handoff

Updated: 2026-08-03

## Objective

Complete cleanup epic `jwiegley/nix-config#98` and its cleanup issues under the
accepted Definition of Done in `doc/CLEANUP-PLAN.md`.

## Current authoritative state

- `doc/CLEANUP-PLAN.md` is the accepted plan. John explicitly accepted decisions
  D1-D7 on 2026-08-03.
- Local `main` contains completed, audited Phase 1 and issue #107 through
  `eda3ef61`, including John's signed flake-lock update. Fetched Gitea and GitHub
  `main` remain `cf2056ec0a3681d9ef95ede54b4c5574ad33b008`.
- Active construction checkout:
  `/private/tmp/wg-nix-cleanup/c2a-dead-comments`, branch
  `cleanup/c2a-dead-comments`. Issue #103 implementation commit `9d9baf0a` is
  signed and independently audited; the signed closeout is at branch HEAD. The
  work unit is ready for local fast-forward into `main`.
- Superseded Phase 1 branches/worktrees were removed after their refs and dirty
  state were captured in the standalone recovery package.
- The primary `/Users/johnw/src/nix` checkout is on `main` and contains John's
  concurrent dependency/Pi work. Cleanup must not stage, restore, rewrite, or
  absorb these visible paths:
  `config/fleet/model-policy.nix`,
  `config/fleet/model-registry.json`,
  `config/fleet/renderers/pi.nix`,
  `packages/pi-gallery/default.nix`, and
  `test/ai/pi-gallery.nix`, plus `sources/ai.json`. John's committed
  `flake.lock` update is already part of local `main` and must remain intact.
- Standalone recovery package:
  `/private/tmp/wg-nix-phase0.yr3oHd`. Its relative `SHA256SUMS`, complete Git
  bundle, patches, rewrite tar, Pi patch, runbook, signature/ref evidence, and
  fresh-clone restore smoke all pass.

## Completed and independently established

- C0 documentation commit `93845163` is signed and passed its final independent
  audit.
- John's `59ac2a88` lock update was observed and preserved as user-owned work.
- Updater synthetic commits now explicitly disable GPG signing inside disposable
  test repositories; the focused 37-test suite and the 64-second fast gate pass.
- The cleanup plan received independent premise, architecture, gate, and
  documentation review before John accepted it.
- The signed C1 branch and uncommitted rewrite candidate are behaviorally
  equivalent. Sixteen of eighteen logical path effects are byte-identical; the
  two differences are only exact-source bindings in the coverage and consumer
  inventory artifacts.
- The minimal C1 analysis preserves fast/full discovery, failure propagation,
  path/process safety, explicit budgets, and slow-suite naming while discarding
  at least 84.9% of exploratory patch churn.
- C9a authoritative consumer proof now passes:
  - Vulcan uses paired `config/fleet` revision `93b023c49d6f` and evaluates.
  - All four shared-work hosts expose one clean, byte-identical checkout using
    paired `config/fleet` revision `1029a6594e0a`; evaluation passed on
    `gpu-server`.
  - John authorized the VPS consumer update. `/etc/nixos` was fast-forwarded,
    without a new commit or push, from `0452c61f` to signed upstream
    `9167ffad`. It now uses paired `config/fleet` revision
    `166ade2c2e25`.
  - VPS metadata, flake check, evaluation, and full no-link NixOS build passed.
    Its lock, active system, and system profile remained unchanged; no activation
    occurred.
  - Explicit-`jwiegley` GitHub search found no external maintained
    `dir=config/ai` consumer. Bounded Gitea/local searches found no additional
    operational consumer.
- Sanitized C9a evidence is
  `/private/tmp/wg-nix-c9a-evidence.md`.
- Phase 1 is implemented as six signed commits from `5a22d898` through
  `9afc639e`:
  - fail-closed fast/full selection and four slow-suite renames;
  - the audit-driven minimal-helper and prose corrections;
  - deletion of structural coverage, root output denominators, committed
    consumer inventory, and their writers/wiring;
  - deletion of duplicate root/portable gates and unused helpers; and
  - restoration of `make expensive` as a superset of native AI checks.
- Phase 1 removed 11,980 net lines relative to local `main`. The final mandatory
  hook passes in about 31 seconds.
- Final Phase 1 evidence on one unchanged candidate:
  - full Python: 14 modules, 319 raw cases, 0 failures, 275 seconds within the
    900-second budget;
  - portable all-system evaluation, immutable subflake, strict consumers
    (4 evaluations, 0 skips), all 10 local signatures, and Darwin value surface
    passed;
  - native `agent-resources`, `agent-wrappers`, `pi-gallery`, and
    `pi-fleet-theme` checks passed.
- Final audit report:
  `/private/tmp/wg-nix-phase1-final-fess.QAfPMm/report.md`; verdict PASS after
  corrective commit `7daf8957`.
- The complete Phase 1 range has eight good signatures, a clean worktree, and a
  net diff of 517 additions and 12,504 deletions across 35 files.
- C4/#107 commit `60708a90` deletes 149 lines of unused selector-coverage
  evidence and its private construction. Refreshed repository, live-consumer,
  local-consumer, and explicit-GitHub searches found no named or dynamic external
  consumer.
- Pre/post catalog profiles, item shapes, validation, and per-profile selections
  are byte-identical. All 702 Hera leaf keys and comparison values are identical:
  655 regular/directory sources were content-hashed, and the five managed-AI
  symlink source paths are exactly identical. No target-byte claim is made for 42
  unrelated symlinks. Managed preflight and the fast tier pass. Final independent
  audit verdict: PASS at
  `/private/tmp/wg-nix-c4-fess.BU0yVL/report.md`.
- C2a/#103 commit `9d9baf0a` deletes 191 lines of mechanically inert comments
  across 14 files. Every removed nonblank line was a comment; six policy-bearing
  cask rationales remain for the later semantic prose audit. The targeted comment
  manifest has no pending entries, the Darwin value surface and fast tier pass,
  and the final independent verdict is PASS at
  `/private/tmp/wg-nix-c2a-commit-fess.fMETux/report.md`.

## Active work unit

Fast-forward issue #103 locally. Then close it Done, remove its worktree/branch,
and begin issue #105 from current local `main` after the separately authorized
Hera dependency activation is verified.

## Project state

Cleanup epic #98 remains In Progress. Issues #99-#102, #107, and #114 are closed
with their Project items Done. Issue #103 is In Progress and ready to close Done
after local fast-forward. The remaining cleanup issues stay Todo until their
accepted work units begin.

Every `gh` invocation must select account `jwiegley` explicitly.

## Authorization boundary

Authorized:

- accepted plan decisions D1-D7;
- local source edits and signed cleanup commits;
- the completed VPS checkout fast-forward and no-activation verification;
- one Hera activation of the current dependency candidate after its build passes;
- truthful GitHub issue/Project reconciliation after focused proof.

Not authorized:

- pushing or publishing nix-config cleanup commits;
- activating Clio, VPS, Vulcan, or shared-work configurations;
- restarting or terminating user sessions;
- force-pushing or rewriting published history;
- further external-checkout edits without a new need inside the accepted plan.

## Stop counters

- repeated gate failure: 0/3
- unusable subagent output: 1/2; the first commit-1 audit attempt produced no
  report, and its bounded retry succeeded
- GPG signing cache locked: 0/3; John unlocked macOS pinentry and signed commit
  `3ab97a35` succeeded
- unresolved destructive or intent-sensitive action: none

## Resume procedure

1. Read `doc/CLEANUP-PLAN.md` and this handoff fully.
2. Verify issue #103 commit `9d9baf0a` and its closeout commit have good
   signatures and the worktree is clean.
3. Preserve every user-owned dependency/Pi path named above and stage only
   explicit cleanup paths.
4. Fast-forward local `main`, remove the completed #103 worktree/branch, and
   preserve John's dirty paths.
5. Close #103 Done using the explicit `jwiegley` account.
6. Build and activate the current Hera dependency candidate, then verify oMLX,
   Pi, Claude Code, and Codex from the active profile. Do not push.
7. Start #105 from a fresh short-lived branch/worktree based on current local
   `main`.
