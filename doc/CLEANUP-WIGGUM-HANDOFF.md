# Cleanup Wiggum Handoff

Updated: 2026-08-03

## Objective

Complete cleanup epic `jwiegley/nix-config#98` and its cleanup issues under the
accepted Definition of Done in `doc/CLEANUP-PLAN.md`.

## Current authoritative state

- `doc/CLEANUP-PLAN.md` is the accepted plan. John explicitly accepted decisions
  D1-D7 on 2026-08-03.
- Local `main` contains completed, audited Phase 1 through `aae7f379`, including
  John's signed flake-lock update. Fetched Gitea and GitHub `main` remain
  `cf2056ec0a3681d9ef95ede54b4c5574ad33b008`.
- Active construction checkout:
  `/private/tmp/wg-nix-cleanup/c4-catalog-dead-metadata`, branch
  `cleanup/c4-catalog-dead-metadata`. Issue #107 is complete, signed, audited,
  and ready for a local fast-forward into `main`.
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
  are byte-identical. All 702 Hera generated-home leaf comparison hashes are
  identical (311 unique): store-backed regular/directory sources were hashed by
  content, while mutable external/symlink sources were compared by path/type
  identity. Managed preflight and the fast tier pass. Final independent audit
  verdict: PASS at
  `/private/tmp/wg-nix-c4-fess.BU0yVL/report.md`.

## Active work unit

Phase 2, next boundary: delete the specifically audited dead commented-out
implementation under cleanup issue #103. Begin after #107 is fast-forwarded,
closed Done, and its worktree/branch is removed.

## Project state

Cleanup epic #98 remains In Progress. Issues #99-#102 and #114 are closed with
their Project items Done. Issue #107 is ready to close Done after local
fast-forward. The remaining cleanup issues stay Todo until their accepted work
units begin.

Every `gh` invocation must select account `jwiegley` explicitly.

## Authorization boundary

Authorized:

- accepted plan decisions D1-D7;
- local source edits and signed cleanup commits;
- the completed VPS checkout fast-forward and no-activation verification;
- truthful GitHub issue/Project reconciliation after focused proof.

Not authorized:

- pushing or publishing nix-config cleanup commits;
- activating Hera, Clio, VPS, Vulcan, or shared-work configurations;
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
2. Verify the #107 worktree is clean and commit `60708a90` has a good signature.
3. Preserve every user-owned dependency/Pi path named above and stage only
   explicit cleanup paths.
4. Fast-forward local `main`, remove the completed #107 worktree/branch, and
   preserve John's dirty paths.
5. Close #107 Done, then move #103 In Progress using the explicit `jwiegley`
   account.
6. Start #103 from a fresh short-lived branch/worktree based on current local
   `main`.
7. Do not push or activate without separate authorization.
