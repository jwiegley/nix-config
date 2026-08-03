# Cleanup Wiggum Handoff

Updated: 2026-08-03

## Objective

Complete cleanup epic `jwiegley/nix-config#98` and its cleanup issues under the
accepted Definition of Done in `doc/CLEANUP-PLAN.md`.

## Current authoritative state

- `doc/CLEANUP-PLAN.md` is the accepted plan. John explicitly accepted decisions
  D1-D7 on 2026-08-03.
- Local `main` contains John's signed flake-lock update `59ac2a88` plus the
  signed updater-fixture isolation fix `3ab97a35` atop C0; the accepted-plan
  documentation commit is the next local-main change. Fetched Gitea and GitHub
  `main` remain
  `cf2056ec0a3681d9ef95ede54b4c5574ad33b008`.
- Active construction checkout:
  `/private/tmp/wg-nix-cleanup/c1a-rewrite`, branch
  `cleanup/c1a-rewrite`. After the accepted-plan commit, rebase its preserved C1
  net onto current local `main` before Phase 1 implementation.
- The signed exploratory recovery branch remains
  `cleanup/c1a-python-tiers@65701d26ba30d410765bcb93713b35c7a19c8ecb`
  and is also captured in the standalone recovery package.
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
- The untracked review draft in the primary checkout is superseded by the
  accepted plan and may be removed only after the accepted-plan commit exists.

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

## Active work unit

Phase 1: reset the quality gates and delete evidence bureaucracy.

Accepted policy:

1. Keep only `fast` and `full` Python tiers with 120/900-second budgets.
2. Preserve fail-closed tracked discovery, exact module execution, strict
   no-skip/no-empty behavior, path safety, process cleanup, signature trust,
   consumer refusal, and updater rollback coverage.
3. Delete structural coverage and the root output-denominator system together.
4. Delete the committed consumer inventory and exact-source currency machinery;
   retain the read-only scanner only until Phase 4.
5. Remove coverage from pre-push/CI; pre-push verifies signatures only.
6. Do not replay generated projection or exploratory checkpoint commits.
7. Run full/independent audit only at issue closeout, not after every intermediate
   commit.

The next implementation boundary is to pare the existing rewrite worktree to that
accepted minimum before any commit.

## Project state

Cleanup epic #98 and issues #99/#100 remain In Progress. C9a issue #114 passed its
live and focused positive gates, was independently reviewed, and is now closed
Completed with its Project item Done. The remaining cleanup issues stay Todo until
their accepted work units begin.

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
- unusable subagent output: 0/2
- GPG signing cache locked: 0/3; John unlocked macOS pinentry and signed commit
  `3ab97a35` succeeded
- unresolved destructive or intent-sensitive action: none

## Resume procedure

1. Read `doc/CLEANUP-PLAN.md` and this handoff fully.
2. Verify both worktrees and the recovery-package checksums.
3. Preserve every user-owned dependency/Pi path named above and stage only
   explicit cleanup paths.
4. Pare Phase 1 in the rewrite worktree according to the active-work-unit list.
5. Run focused quality tests, the fast tier, then the full tier once at issue
   closeout.
6. Commit the accepted-plan/current-state documentation separately from Phase 1
   implementation, signed and with explicit paths.
7. Dispatch an independent audit after each completed issue, then reconcile its
   GitHub state using the explicit `jwiegley` account.
8. Do not push or activate without separate authorization.
