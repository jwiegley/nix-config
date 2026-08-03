# Cleanup Wiggum Handoff

Updated: 2026-08-03

## Objective

Complete cleanup epic `jwiegley/nix-config#98` and its cleanup issues under the
accepted Definition of Done in `doc/CLEANUP-PLAN.md`.

## Current authoritative state

- `doc/CLEANUP-PLAN.md` is the accepted plan. John explicitly accepted decisions
  D1-D7 on 2026-08-03.
- Local `main` contains completed, audited Phase 1 and issues #107, #103, #105,
  #106, #110-#113, and #115 through `650252b9`, including John's signed
  flake-lock update and #120's proof-only HOLD record. Fetched Gitea and GitHub
  `main` remain
  `cf2056ec0a3681d9ef95ede54b4c5574ad33b008`.
- Proof-only #119 checkout used for this audit:
  `/private/tmp/wg-nix-cleanup/c10d-codex-log`, branch
  `cleanup/c10d-codex-log`. Its signed record is ready for integration and
  removal; no construction checkout remains afterward. Issue #119 returns to
  Todo on HOLD and has no retirement change.
- Superseded Phase 1 branches/worktrees were removed after their refs and dirty
  state were captured in the standalone recovery package.
- The primary `/Users/johnw/src/nix` checkout is on `main` and contains John's
  concurrent dependency/model/Pi/oMLX work. Cleanup must not stage, restore,
  rewrite, or absorb these visible paths:
  `config/fleet/model-policy.nix`,
  `config/fleet/model-registry.json`,
  `config/fleet/models.nix`,
  `config/fleet/renderers/codex.nix`,
  `config/fleet/renderers/pi.nix`,
  `flake/ai.nix`,
  `overlays/ai/30-agent-resources.nix`,
  `overlays/ai/patches/omlx-host-vm-info64-count.patch`,
  `packages/pi-gallery/default.nix`,
  `packages/pi-gallery/manifest.nix`,
  `sources/pi.json`,
  `test/ai/overlays/omlx-host-vm-info64-count.py`,
  `test/ai/pi-gallery.nix`,
  `test/ai/pi-tool-renderer-wrapper.test.mjs`, plus `sources/ai.json`. John's
  committed `flake.lock` update is already part of local `main` and must remain
  intact.
- Primary-only runtime state `.pi/goals` appeared during the active Wiggum goal.
  Treat it as mutable state: do not read its contents, stage it, or remove it.
- Primary-only untracked `packages/pi-gallery/providers/` appeared concurrently.
  Treat the entire subtree as user-owned: do not read, stage, or remove it.
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
- Hera generation 986 is active after a full no-link system build and successful
  switch. oMLX 0.5.5 is running; Pi 0.83.0, Claude Code 2.1.220, and Codex 0.146.0
  match the candidate and their prior installed versions. The live Pi leaf keeps
  `gpt-5.6-sol` under `openai-codex` at 1,050,000 tokens and local DeepSeek V4 at
  1,048,576. Codex defaults to native OpenAI; its oMLX and llama-swap profiles
  remain opt-in.
- C3a/#105 commit `d56df05c` makes `format.sh` own both write and `--check`
  modes while reducing `format-check.sh` to a four-line compatibility adapter.
  Exact base/candidate Nix and shell fixtures match in write mode; each check
  backend preserves status, output, and file bytes; unknown modes fail with
  status 2. Both public apps, the portable format derivation, and the fast tier
  pass. Final independent verdict: PASS at
  `/private/tmp/wg-nix-c3a-commit-fess.iRqiiC/report.md`.
- C3b/#106 commit `0f6b58b3` makes `agent-deck-env` the sole fail-closed MCP
  credential launcher, deletes `codex-env` and its duplicate test, and preserves
  Codex diagnostics through one fixed wrapper label. The independent audit found
  that an early export exposed Ref to the Perplexity helper; the amended launcher
  now unsets both ambient keys, invokes both helpers without either exported, and
  exports only after both succeed. Hostile-ambient regression coverage, the
  focused suite, actual packaged Hera Codex wrapper, native wrapper check, and
  fast tier pass. Final independent verdict: PASS at
  `/private/tmp/c3b-amended-fess-report.md`.
- C7/#111 commit `147a5681` replaces the 1,438-line copied Codex grammar and its
  537-line mirrored test matrix with the pinned parser's command/profile boundary
  and packaged differential probes. The final wrapper delegates option values,
  combinations, and positional counts upstream while retaining host-local state,
  managed artifacts, atomic runtime profiles, caller-profile refusal, the
  explicit bypass, and legacy Ref import. Counterexample audits established MCP
  delimiter/payload, generated help, greedy image, prompt-before-command,
  lone-dash, nested exec, platform sandbox, and SQLite/guard isolation behavior.
  Final independent verdict: PASS at
  `/private/tmp/wg-nix-c7-147a5681-final-fess-report.md`.
- Implementation commit `147a5681` passed the full closeout unchanged: 13 Python
  modules and 316 tests in 236 seconds, portable all-system evaluation, immutable
  subflake, Darwin value surface, four consumer evaluations with zero skips, and
  all 27 local signatures. The subsequent closeout documentation passed the fast
  hook.
- C8a/#112 commit `1d8551c0` deletes the one-time config/ai-to-config/fleet
  parity command-migration environment, validator, refresh branch, CLI mode,
  private test, and two now-unused scanner exemptions. The committed parity JSON
  remains byte-identical historical evidence; `--commands`, strict command
  equality, compare/refresh behavior, and all 28 currency tests remain. The
  rename scanner reserved for #115 remained until `2faa1af0` retired it.
- The historical artifact's direct current comparison remains non-green for
  known pre-#112 selection/version changes (agent-browser, Droid, mtplx,
  SearxNG, and portable Pi/nix-scripts). It was not regenerated to manufacture a
  green result. A temporary artifact derived at `1d8551c0` self-compared cleanly,
  and a valid one-package mutation was rejected exactly. Independent closeout
  ruling: PASS at
  `/private/tmp/wg-nix-c8a-closeout-decision-fess-report.md`.
- The unchanged implementation passed the fast gate and the 13-module full tier:
  315 tests, zero failures, 329 seconds within the 900-second budget.
- C8b/#113 was already implemented by signed Phase 1 commit `5a22d898`:
  tracked filename discovery excludes `*-slow-test.py` from fast and includes it
  in full. Current proof selects 9 fast and 13 full modules, with
  `oracle-currency-slow-test.py` present only in full; no lefthook, Make, or
  GitHub Actions path invokes parity derivation. The fast tier passed 9/9, and
  #112's unchanged full-tier run executed all 28 currency tests without a skip
  or failure. Independent no-op verdict: PASS at
  `/private/tmp/wg-nix-c8b-noop-fess-report.md`.
- C9b/#115 commit `2faa1af0` deletes the retired config/ai throwing subflake,
  rename-only consumer scanner, rollback runbook, stale negative consumer and
  immutable branches, and their fixtures/registrations. Positive config/fleet
  portable, immutable, and consumer checks remain; the neutral immutable fixture
  still proves exact archived bytes without naming retired machinery. The
  operational old-path sweep is empty outside historical parity and cleanup-plan
  prose. Final independent verdict: PASS at
  `/private/tmp/wg-nix-c9b-2faa1af0-final-fess-report.md`.
- Exact #115 closeout passed: immutable subflake, portable all-system evaluation,
  strict supported consumers (3 ran, 0 skipped), 26 retained gate regressions,
  fast gate, and full Python (13 modules, 312 tests, 280 seconds, zero failures).
- C6/#110 closes as not planned under accepted decision D5. All five hidden
  preparation flags are private between `bin/update` and `bin/update-overlay`;
  each has one production caller. The closeout audit exercised 10 flag pairs,
  five candidate restrictions, and five version-arity refusals; the retained
  suite covers routing, rollback, and isolation. No defect or measured net
  deletion warrants replacing that private interface. Independent verdict: PASS
  at
  `/private/tmp/fess-c6-issue-110-5b7bd01b.md`.
- C10e/#120 pre-deletion proof established that Hera generations 985/986 and
  Clio 239/240 each contain the handoff and no retired producer; the retired
  launchd label is absent in both live user domains on both hosts. Those exact
  generation sets satisfy the D7 rollback shape. Retirement remains blocked:
  generation links do not prove Hera 985 or Clio 239 actually completed
  activation, so the required two-cycle execution evidence is missing. The guard
  stays intact until durable evidence is found or one additional activation per
  host is separately authorized. Independent verdict: HOLD at
  `/private/tmp/wg-nix-c10e-predeletion-fess.md`.
- C10d/#119 pre-deletion proof established exact canonical Codex log symlinks,
  real local targets, and zero migration residue on Hera, Clio, and all four
  shared-work hosts. Hera 985/986, Clio 240/241, and shared current HM196 contain
  the migration. Retirement remains blocked: Clio and the four shared-work hosts
  have no fresh Codex process, and prior HM195 is not resident on andoria-t2, so
  it is not a fleet-valid rollback closure. The migration stays intact until
  fresh sessions on those five hosts and a resident prior shared closure are
  separately authorized/proven. Independent verdict: HOLD at
  `/private/tmp/wg-nix-c10d-predeletion-fess.md`.

## Active work unit

Fast-forward this proof-only #119 record and remove its worktree/branch. Leave
#119 Todo until its fresh-session and shared rollback evidence is supplied.

## Project state

Cleanup epic #98 remains In Progress. Issues #99-#103, #105-#107, #111, #112,
#110-#115 are closed with their Project items Done except optional #108/#109,
which remain Todo behind concurrent Pi/model work. Issue #120 is Todo on HOLD.
Issue #119 is also Todo on HOLD. The remaining cleanup issues stay Todo until
their accepted work units begin.

Every `gh` invocation must select account `jwiegley` explicitly.

## Authorization boundary

Authorized:

- accepted plan decisions D1-D7;
- local source edits and signed cleanup commits;
- the completed VPS checkout fast-forward and no-activation verification;
- the completed one-time Hera generation 986 activation John requested in this
  turn; this was consumed authorization, not standing activation authority;
- truthful GitHub issue/Project reconciliation after focused proof.

Not authorized:

- pushing or publishing nix-config cleanup commits;
- any further activation of Hera, Clio, VPS, Vulcan, or shared-work
  configurations;
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
2. Preserve every concurrent path, primary-only Pi provider subtree, and
   `.pi/goals` state named above; stage only explicit cleanup paths.
3. Fast-forward this documentation-only proof record and remove its temporary
   worktree/branch.
4. Do not resume #119 without authorized fresh sessions on Clio/shared-work and
   a resident, migration-containing prior shared closure.
5. Do not push, perform another activation, edit a consumer, or restart sessions
   without separate authorization.
