# Cleanup Phase Plan

- Status: active accepted Definition of Done
- Prepared: 2026-08-03
- Accepted: 2026-08-03
- Scope: `jwiegley/nix-config` cleanup epic #98 and cleanup issues #99-#121.

## Outcome sought

Make the repository materially smaller, easier to understand, and cheaper to
verify while preserving user-visible behavior and mutable agent state. Cleanup is
deletion, not file movement, renamed abstractions, or more machinery for describing
machinery.

The repository's principal architecture is sound: root orchestration, shared Home
Manager configuration, fleet selection, client renderers, packages, and overlays
have distinct owners. The largest opportunities are dead metadata, duplicated CLI
and gate implementations, generated evidence that proves little, and finite
migrations that have not yet been retired.

## Current checkpoint

This is the state observed for the 2026-08-03 review. It is a frozen review
baseline, not a permanent invariant, and this section is never updated with later
resume state. After plan acceptance, subsequent mutable branch, revision,
worktree, test, and Project facts belong only in the handoff.

- Gitea `origin/main` and GitHub `github/main` both point to
  `cf2056ec0a3681d9ef95ede54b4c5574ad33b008`.
- Local `main` points to signed C0 commit
  `93845163d25c830a8e241c9c85d12dd648a00d09`.
- The primary checkout is `cleanup/c1a-python-tiers` at `65701d26`, eight signed
  exploratory C1a commits beyond local `main`.
- The primary checkout has five unrelated, user-owned Pi edits. They must not be
  staged, restored, rewritten, or absorbed into cleanup:
  `config/fleet/model-policy.nix`, `config/fleet/model-registry.json`,
  `config/fleet/renderers/pi.nix`, `packages/pi-gallery/default.nix`, and
  `test/ai/pi-gallery.nix`.
- `/private/tmp/wg-nix-cleanup/c1a-rewrite` is a second dirty worktree at local
  `main`, containing an uncommitted alternative C1a reconstruction. It is recovery
  material and must not be removed before its useful diff is preserved.
- Normal GitHub CI is red because structural coverage compares the runner's Nix
  tool identity. Scheduled portable assurance is green on the same remote commit.
- Project 9 contains 24 open cleanup issues (#98-#121): #98-#100 are In Progress
  and #101-#121 are Todo. The graph has 23 subissues and 55 blocked-by edges.
- The repository has 411 tracked files. `test/` alone has 70 files and 41,384
  lines. The existing plan has 735 lines, and the cleanup issue bodies add roughly
  1,900 more lines of duplicated process.
- In the read-only timing run on 2026-08-03, the fast Python tier ran 13 modules
  and 232 cases in 61.95 seconds. Structural coverage consumed 27.23 seconds and
  parity-currency validation 6.83 seconds. Removing those from the hot path leaves
  about 28 seconds of Python work before format and lint time; remeasure at
  implementation closeout rather than treating these values as constants.

The current handoff and `CURRENT-WORK.md` are already stale about the branch,
worktree count, and local-main revision. Until closeout, subsequent mutable
checkpoint facts belong in one handoff only; `CURRENT-WORK.md` should be a short
pointer.

## Review verdict

The existing plan is safe but not yet simple enough to approve unchanged.

The blocking problems are:

1. It repairs and regenerates evidence that it proposes to delete shortly
   afterward.
2. It preserves an output-denominator ledger whose constants duplicate the flake
   outputs and the existing portable public-interface contract.
3. It makes speculative renderer and updater refactors mandatory even though they
   have weak deletion-to-risk ratios.
4. It does not reassess the 3,000-plus-line parity system or the 3,000-plus-line
   Darwin golden system after the risky work they temporarily protect.
5. It under-specifies the final documentation denominator and cleanup of its own
   plan and handoff.
6. Its issue graph and repeated acceptance text are now another synchronization
   burden.
7. It treats the exploratory C1a history as momentum rather than asking whether a
   smaller final change can replace it.

The path to approval is concrete: accept the decisions below, establish a clean
checkpoint, then execute the reduced phase graph one issue at a time.

## Governing rules

1. **Does it need to exist?** Delete obsolete code, data, tests, and prose before
   designing a replacement.
2. **One authority.** A generated inventory, baseline, or compatibility ledger is
   justified only when it is independent of the implementation and catches a
   user-visible regression that a smaller direct check cannot catch.
3. **One objective per commit.** An issue may contain a short ordered series of
   related commits, but each commit has one sentence of purpose and an explicit
   rollback boundary. Dependencies between commits are stated rather than hidden.
4. **Tests mechanize real expectations.** Preserve transaction rollback,
   credential non-disclosure, state ownership, signature trust, negative
   validation, and actual client behavior. Delete tests that only verify another
   test's registration, repeat source text, or validate a generated artifact's
   own bookkeeping.
5. **Fail loudly.** Discovery errors, missing tools, failed formatters, invalid
   state, and unsupported inputs remain failures rather than skips or fallbacks.
6. **Comments describe the current system.** Git owns incident history. A
   rationale stays only where a future maintainer needs it to avoid changing a
   non-obvious invariant.
7. **No speculative framework.** Do not create a renderer abstraction, audit
   database, generator, new dependency, or general migration framework.
8. **Live state gates state deletion.** A source search or successful build cannot
   prove that mutable homes or external consumers have converged.
9. **Verification is proportional.** Ordinary commits remain below 120 seconds.
   Full and independent review happens when an issue is ready to close, not on
   every intermediate commit.
10. **Authorization boundaries remain explicit.** Push, publication, activation,
    history rewrite, external-checkout edits, session restart, and deletion of
    user backups require their own authorization.

## Accepted decisions

### D1. Pare C1 down in the existing rewrite worktree

**Recommendation:** preserve the signed primary branch as recovery material and
use the existing uncommitted rewrite worktree to construct the smaller
quality/evidence candidate from local `main`. Strip interim projections and harness
work that Phase 1 deletes rather than reconstructing both branches again.

Alternative: finish and merge the eight-commit C1a branch, then perform C1b/C1c.
That saves short-term rework but carries hundreds of lines of harness tests and an
intermediate evidence lifecycle into history.

Before any destructive branch/worktree action, compare exact file and line deltas
for the pared candidate, the signed primary branch, and local `main`. Rebuild from
scratch only if that comparison demonstrates a smaller final change than editing
the rewrite worktree. Do not use sunk effort or an arbitrary line quota as the
decision.

Retiring or rewriting the current local branches is destructive Git work and waits
for explicit approval. Until then, both worktrees are preserved.

### D2. Delete structural coverage without repairing it

**Recommendation:** delete it directly. Its artifact records no Python dynamic
coverage and unknown Nix reach with zero reached files; its current CI failure is
tool-version identity drift, not a behavioral regression. Do not spend a work unit
proving that ignoring tool identity makes this self-referential artifact green.

Delete the report, report tests, manifest, generated baseline, host denominator,
and all hook/CI/flake wiring together.

### D3. Delete the root output-denominator ledger

**Recommendation:** delete `test/bin/output-denominators` and its tests with the
coverage manifest. Root outputs are already explicit in `flake.nix`; the portable
public interface has a separate compatibility contract. An added root output is
not itself a defect, and a missing consumed output fails its direct consumer.

This intentionally stops freezing the names and system placement of root-only
checks that no consumer invokes. Root packages and overlays remain protected by
the portable compatibility contract. This is a policy choice, not a claim that
the existing denominator comparison is self-validating. John explicitly accepted
this policy on 2026-08-03.

Alternative: retain a small explicit public-interface contract only if John wants
root output names frozen as an API. Do not create a new JSON schema or generated
artifact to preserve it.

### D4. Remove parity and Darwin currency bureaucracy after their risk window

**Recommendation:**

- After the #126 consumer cutover, remove the completed `config/fleet` to
  `config/ai` command-migration mode from parity.
- Until the last planned package/profile-selection change, retain one baseline and
  the existing compare path; use it only at the closeout of a selection-changing
  issue. Delete refresh-history and ordinary currency bureaucracy, but do not
  promise a baseline-free comparison the current tool cannot perform.
- After retirement of the old `config/fleet` consumer path and the last Phase 6 selection
  change, delete the parity tool, baseline, currency/history tests, and runbook.
  No parity claim remains after its comparison authority is removed.
- Keep Darwin value-surface comparison through the Codex-wrapper and host-policy
  changes. Then replace the broad golden with direct assertions only where that
  preserves the intended property. Before deleting the baseline writer, writer
  tests, or broad snapshot, dispose of every existing projected surface:

  | Surface | Required disposition before golden deletion |
  |---|---|
  | Users | Retain direct identity, home/shell/UID/GID, and authorized-key assertions, or explicitly abandon each |
  | Environment | Retain or explicitly abandon package names, `/etc` entries, variables, shells, and link paths |
  | Prometheus | Retain or explicitly abandon enablement, port, address, and collector assertions |
  | Homebrew | Retain or explicitly abandon brew/cask/tap/MAS sets and activation policy |
  | Nix | Retain or explicitly abandon settings, jobs, distributed builds, and builder/key identity |
  | System | Retain or explicitly abandon primary user, state version, defaults, and activation scripts |
  | Launchd | Retain or explicitly abandon agent/daemon names plus hashed service and script bodies |

  Retain the golden as a manual closeout diagnostic until this table is complete.
  John must explicitly accept every intentionally abandoned surface in the same
  issue/range that removes the golden. No coverage may disappear silently.

Alternative: keep either golden as a manual diagnostic, never as an ordinary
commit or pre-push requirement. Every retained golden must have a written failure
triage rule.

### D5. Drop speculative refactors from the completion gate

**Recommendation:** remove C5a and C6 from mandatory cleanup.

- Moving Pi/Droid renderer assertions into the catalog risks turning an
  independent negative check into self-validation. Revisit only if two genuinely
  identical implementations can be deleted.
- The five updater preparation flags are private to `bin/update`. Replacing them
  with `--prepare KIND` is reasonable, but touching a transactional 3,600-line
  updater and its 7,900-line test file is not justified by internal CLI aesthetics
  alone. Revisit only with a measured deletion or a real defect.
- Re-audit model policy after the concurrent Pi edits land. Preserve security
  allowlists as independent constraints; centralize only duplicated choices that
  actually drive output.

### D6. Collapse the tracker after the plan is accepted

**Recommendation:** retain issues as historical records but close superseded
micro-issues and execute through a small phase set. Replace the 55 micro-level
blocked-by edges with the smaller phase-level dependency graph; keep those
phase-level edges and predecessor notes in GitHub so ordering remains durable after
the cleanup plan leaves the working tree.

Suggested active issue mapping:

| Phase | Existing issues | Disposition |
|---|---|---|
| Checkpoint and quality/evidence reset | #99-#102 | One active implementation issue; others close as completed or superseded |
| Proven dead data and duplication | #103, #105-#107 | One issue with independent commits |
| Runtime simplification | #111 | Retain as its own high-risk issue |
| Optional renderer/model follow-up | #108-#109 | Re-audit after Pi changes; close if no net simplification |
| Optional updater follow-up | #110 | Defer or close unless a measured benefit appears |
| Consumer/parity retirement | #112-#115 | One proof issue followed by one deletion issue |
| Mutable migration retirement | #116-#120 | Keep separate because hosts, rollback, and reverts differ |
| Documentation and closeout | #104, #121 | Retain; C2a mechanical deletion moves earlier |

Reconcile GitHub issues and Project state after this accepted plan is activated.

### D7. Define the supported rollback horizon

Finite migrations cannot be retired while "an old generation" means every
generation ever retained. **Recommendation:** record an exact supported set of
generation IDs per host and prove that each contains the cleanup or independently
cannot reintroduce the retired state. A generic "current and previous known-good"
formula is insufficient when the previous generation predates the migration.
Older retained generations may remain available for forensic recovery but are not
supported activation targets after a migration is retired.

John accepted this exact-generation policy on 2026-08-03; every retirement must
still record the proven generation IDs for its own hosts.

## Reduced execution plan

### Phase 0. Stabilize the checkpoint

Objective: start cleanup from one truthful branch and one worktree without losing
the user's Pi changes or the useful C1a diff.

1. Preserve the five Pi edits in their own user-approved commit/branch or a
   checksum-verified patch.
2. Preserve a binary-safe patch and file list for both C1a variants.
3. Apply decision D1. Do not reset, rewrite, or remove either branch beforehand.
4. Correct `CLEANUP-WIGGUM-HANDOFF.md`; make `CURRENT-WORK.md` a pointer rather
   than a second mutable status record.
5. Reconcile Project 9 only after the accepted issue map is known.

Exit proof: one clean cleanup branch, at most one extra worktree, preserved Pi
work, exact recovery material, and truthful handoff.

### Phase 1. Reset gates and delete evidence bureaucracy

Objective: make the fast gate fast and truthful, with no generated evidence
maintenance.

Use one GitHub issue and the following commit boundaries:

1. tracked discovery and `fast`/`full` tiering;
2. evidence retirement: delete output denominators and structural coverage
   together because the former reads the latter's manifest;
3. root/portable gate cleanup; and
4. final hook/CI wiring.

Each boundary has one objective. Coupled evidence deletion rolls back in reverse
order; do not claim that a manifest consumer can be reverted independently of its
manifest.

Delete across those commits:

- structural coverage implementation, tests, manifest, baseline, and host probe;
- root output-denominator implementation and tests;
- all coverage and output-denominator wiring;
- duplicated root-flake formatting/linting checks that hand-list files;
- the portable source-only test that merely reparses Nix already parsed by the
  formatter, but only after a caller search and an explicit decision to change the
  public `checks.tests` output; update the compatibility contract in the same
  commit;
- unused portable script helpers and duplicate text-level gate-registration
  assertions. Retain Make build/switch/lock failure propagation and the policy
  check that scheduled assurance is manual/twice-daily rather than push/PR;
- the committed consumer-inventory artifact plus both of its exact-source currency
  checks (current-tree generator parity and `repoHead` object/file availability),
  and the quality tests for generated-revision bureaucracy. Git already archives
  the snapshot; retain the read-only scanner for Phase 4's fresh proof.

Simplify the retained `test/bin/quality` authority:

- two Python tiers only: `--python-tier fast` and `--python-tier full`; “ordinary”
  means `fast` everywhere else in this plan;
- fast discovers every tracked non-slow Python module;
- full discovers every tracked module exactly once (individual methods may
  intentionally exercise nested integration paths more than once);
- rename `oracle-currency-test.py` to `oracle-currency-slow-test.py` until Phase 4
  removes or justifies it; the roughly 28-second target assumes it is absent from
  fast;
- keep the Python budgets explicit: 120 seconds for fast and 900 seconds for full;
- delete the coverage-only `--tier pre-commit-core` alias and its test;
- tracked files, not `.` or generated/untracked trees, feed Nix, shell, and Python
  tools;
- shell discovery includes both Bash and POSIX `sh` (`bin/env-build` and
  `bin/runemacs` are currently missed); first determine whether `bin/env-build` is
  live, then delete it or add a narrow, documented SC2154 exception for variables
  injected by its calling environment -- never a blanket POSIX-shell exclusion;
- pre-push verifies signatures only;
- normal CI runs the same static/fast authority plus trusted-base signatures;
- scheduled assurance is described truthfully as portable evaluation plus its
  explicitly built smoke checks; it does not claim that `--no-build` executed
  derivation bodies.

Keep compact regression checks for fast/full selection; strict no-skip/no-empty
execution; failing test/tool/discovery propagation; leading-dash and spaced path
operands; tracked-but-absent staged renames; dangling tracked symlinks; POSIX-sh
discovery; tracked-versus-untracked Nix scope; Git-environment scrubbing; deadline
process cleanup; and trusted-base signature wiring. Use `--` or `./` operands in
the implementation rather than building a broad path-spelling matrix.

Exit proof:

- fast gate passes below 120 seconds, with a target below 60 seconds;
- full Python runs every module exactly once;
- no live structural-coverage implementation, artifact, or wiring remains;
- no output-denominator path remains;
- pre-push contains signatures only;
- normal CI is green after separately authorized publication;
- Phase 1 creates no regeneration or binding commit.

### Phase 2. Delete proven dead data and obvious duplication

Objective: take high-confidence cuts that do not change generated client behavior.

Independent commits, under one issue:

1. Delete catalog `selectorCoverage` and its now-private dependencies
   `secretCapabilities`, `secretServers`, `secretCarriers`, and `piSources` where
   caller search confirms they become unused. In separate commits, delete the
   `targetPaths` field/aggregate/self-check, item `name` mirrors, MCP `scope` and
   `enabled` fields, top-level item descriptions that no renderer reads, and the
   `profile.renderer` mirror after confirming no external export consumer. When
   deleting an unused description field, preserve any genuine operational
   rationale as a short present-tense comment at the decision it explains.
2. Delete renderer result channels with no consumer: `requiredEnvNames`,
   self-validated `companions`, and their private collectors/assertions. Retain
   actual rendered `files` and Pi's live mutable-state guard.
3. Make one portable formatter body serve rewrite/check modes. Keep Git-based
   tracked discovery in root `quality`, and keep an explicit-path/store-projection
   adapter for portable checks, whose immutable source has no `.git` directory.
4. Generalize the fail-closed credential launcher only enough to give each caller
   correct product diagnostics and environment overrides, or retain thin product
   wrappers. Delete `bin/codex-env` only when the final representation is smaller
   and both existing interfaces retain their non-disclosure/refusal behavior.
5. Delete the specifically audited mechanical debris: disabled
   `inputs.nixpkgs.follows` assignments in `flake.nix`; the disabled Rust
   environment block in `bin/de`; duplicate disabled builder assignments in
   `bin/u`; orphaned headers in `overlays/ai/30-agent-deck.nix`, `30-agnix.nix`,
   `30-claude-vault.nix`, `30-fractal.nix`, `30-lazycodex.nix`,
   `30-sherlock-db.nix`, and `30-vllm-mlx.nix`; and audited unused lambda bindings
   in `config/fractal.nix`, `config/home.nix`, `config/launchd.nix`,
   `config/xdg-symlinks.nix`, `config/zsh.nix`, and
   `overlays/30-misc-tools.nix`. Semantic narratives and mutable citations belong
   to Phase 7 rather than this mechanical commit.

Do not move packages between `overlays/` and `packages/`. Do not extract renderer
helpers unless at least two implementations disappear and total code falls.

Exit proof: focused parses/tests, generated leaves byte-identical where relevant,
fast gate green, and the named duplication/debris absent. Added regression tests
may make an individual commit net-positive; report the net change, but do not use
line count as a quota.

### Phase 3. Simplify the Codex wrapper at the real boundary

Objective: delete the repository's second implementation of Codex's changing CLI
grammar while preserving managed state and profiles.

Preserve:

- host-local SQLite/log separation and steady-state path validation;
- atomic, owner-checked runtime profile creation;
- managed-artifact classification;
- caller-profile conflict refusal;
- the documented bypass;
- credential non-disclosure.

Delete every command, option, positional count, enum, and invalid-combination
check that upstream Clap already owns. Detect only whether the upstream command
accepts a managed profile, reject an explicit conflicting caller profile, inject
`--profile nix-runtime`, and delegate all remaining syntax.

Derive that minimal command classification from the pinned Codex source's
`profile_v2_for_args` behavior, then probe the packaged binary's command/help
matrix. Do not replace the large parser with a smaller hand-maintained command
table whose authority is unexplained.

There is no arbitrary line target: remove all duplicate grammar not supported by
a concrete counterexample. A retained exception names that counterexample beside
the code.

Exit proof: wrapped and unwrapped malformed invocations have equivalent status;
new valid upstream syntax is not rejected; state/profile/credential tests pass;
real Codex homes and sessions are untouched.

### Phase 4. Prove consumers early and retire rename machinery

Objective: stop maintaining exact-source rename evidence as soon as the live world
no longer needs it.

Run read-only proof against authoritative Vulcan, VPS, and shared-work checkouts,
plus fresh GitHub and Gitea searches. Require paired root/portable revisions and
`dir=config/ai`; evaluate without activation.

If proof passes, delete together:

- the retained rename-only consumer scanner, stale negative probes, and rollback
  instructions; the committed inventory was already removed in Phase 1 and must
  not be recreated;
- completed parity rename mode and fixtures;
- the remaining parity tool, baseline, currency/history machinery, and
  `doc/PARITY-ORACLE-REFRESH.md` after the final selection-changing issue no longer
  needs them.

Retain the positive immutable-subflake archive/lock proof and the positive
cross-consumer lock/evaluation checks. Delete only their stale `config/fleet`
branches; those checks protect the supported `config/ai` interface
independently of the rename inventory.

If a host is unreachable or divergent, leave it pinned to its coherent old
revision and record one explicit blocker. Do not add a compatibility stub while
waiting.

Exit proof: authoritative consumers evaluate, no maintained `?dir=config/fleet`
reference remains, and no rename-only evidence machinery remains.

### Phase 5. Retire finite mutable-state migrations independently

Objective: remove one-shot migration code only when its own fleet and rollback
boundary is proven.

The 2026-08-03 read-only audit reported Hera observations against active system
generation 984, but no durable sanitized evidence record is part of this draft.
Treat every row as unverified for retirement until a fresh probe is recorded on
its GitHub issue. Unverified hosts are never implied clean.

| Migration | Current status | Required before deletion |
|---|---|---|
| Retired Anvil/MCP cleanup | Eight-host cleanup-bearing proof complete; source retired at `cc0f6718` | Activate the no-producer candidate on every managed host and repeat structural probes |
| Pi XDG migration | Source retired at `8c3d4431`; Hera 991 post-retirement path/session/Pi proof passed | Complete; retain declarative `~/.pi -> ~/.config/pi`, marker, and any `.pi-legacy-v1` backup |
| Codex legacy Ref importer | Source retired at signed Nix `1ad23d7c` and PromptDeploy `4ee0401` | Reconcile existing manifest/runtime entries during a user-approved quiescent client window; no credential migration |
| Codex log migration | Source retired at `302e8de8`; Hera 991 and Clio 247 post-retirement proof passed | Activate the no-migration candidate on all four shared-work Codex hosts and repeat log probes |
| Darwin gpg-agent handoff | Source retired at `b5d31874`; Hera 991 and Clio 247 post-retirement absence proof passed | Complete; retain Home Manager producer-disable and nix-darwin startup owner |
| Home Manager 25.11 SSH shim | Active compatibility, not finite cleanup | Retain until VPS and Vulcan upgrade and rendered behavior is proven equivalent |

Each successful retirement is its own signed, revertible commit. Probes print only
booleans, path types, key names, and generation identifiers. They never print
credential values. No session is restarted or killed by the cleanup agent.

Epic #98 remains open until every retained Phase 5 retirement issue passes. A
represented blocker is still a blocker, not closeout. Moving a blocked retirement
to a successor epic would be a separate scope decision by John; this plan does not
do so implicitly.

### Phase 6. Reassess remaining authorities

Objective: keep only mechanisms with a demonstrated present consumer.

After the Pi edits and prior deletions settle, perform bounded caller audits for:

- model registry/policy/validator layering;
- host registry and `host-options.nix` fields that do not drive runtime behavior;
- Pi/Codex model choices still duplicated in renderers;
- retained Darwin and parity goldens.

This phase is not permission to redesign them. A change proceeds only when it
removes an owner or duplicate representation, preserves an independent safety
constraint, and has a smaller final representation. Otherwise record "retained"
in the closeout and stop.

### Phase 7. Audit comments and documentation once

Objective: make retained prose true after the retained code shape is stable.

Denominator:

- primary docs means `README.md`, `CLAUDE.md`, and every retained `doc/*.md`;
- every retained first-party Nix, Python, Bash/POSIX shell, TypeScript,
  JavaScript, YAML, and owned Emacs Lisp file;
- explanatory comments in `Makefile`, `.gitattributes`, and other retained
  repository metadata;
- repository-owned agent/command/skill/prompt prose;
- provenance/equality verification, not rewriting, for imported agent assets and
  vendored `edit-env.el`, `rs-gnus-summary.el`, and `supercite.el`;
- `edit-var.el` remains in scope until provenance is established;
- Node-RED boilerplate is reported as template material.

At execution time, derive the candidate file list from `git ls-files`, record the
file/entry/comment-line counts in the closeout report, and list every exclusion
with its provenance. Do not add a tracked audit manifest or copy mutable counts
into this plan.

Prioritize safety-affecting rationales, dependency/version claims, cross-references,
and historical narratives. Three current dependency comments require behavioral
verification before prose edits: oMLX/Transformers compatibility in
`packages/ai-llm.nix`, mlx-audio/oMLX revision compatibility in
`packages/ai-python-extensions.nix`, and an ignored npm build failure in
`overlays/ai/30-ai-llm.nix` attributed to a Node version different from the one
actually supplied.

Delete unverifiable prose rather than weakening it. If that prose is the sole
justification for a behavior-changing exception such as `|| true`, a disabled
check, or a dependency relaxation, inability to verify the rationale blocks
retaining the exception: fix it or establish a truthful reason. Keep no mutable
line numbers, file-length claims, unexplained dead commented-out implementation,
or repeated incident history; live examples remain when they serve a current
reader.

At closeout, delete `doc/CLEANUP-PLAN.md` and
`doc/CLEANUP-WIGGUM-HANDOFF.md`. The review draft was deleted when this accepted
plan replaced it. Rewrite `doc/CURRENT-WORK.md` for the next active
programme and repair every inbound link in the same commit. Git is the archive for
the deleted cleanup documents.

Exit proof: bounded audit has no known stale, incorrect, misleading, or orphaned
first-party claim; all local Markdown links resolve; current architecture and
operator commands match the tree.

### Phase 8. Unchanged-candidate closeout

Run broad evidence once, after the last source correction:

1. Fast gate with elapsed time.
2. Full Python tier.
3. Only affected native/consumer/parity checks accumulated from issue closeouts.
4. Portable all-system evaluation.
5. Native system build without activation.
6. One independent review of the complete cleanup range.
7. After separately authorized publication, normal CI and scheduled portable
   assurance on the same commit.
8. Live Git status, signatures, remotes, worktrees, and branches.
9. Reconcile and close or supersede cleanup issues using the explicit `jwiegley`
   GitHub account.

Do not rerun full evidence after every commit. Run the independent audit once when
each issue is ready to close, and once over the unchanged final candidate.

Exit proof: one checkout at `~/src/nix`, one main branch, clean worktree, signed
history, remotes equal after authorized push, no cleanup documents, and no
remaining cleanup blocker.

## Per-unit verification

| Change | Required before commit | Required before issue close |
|---|---|---|
| Pure deletion/docs | Parse/link check and fast gate | Review touched claims |
| Shell/Python utility | Focused behavioral test and fast gate | Full tier only if transaction/security/state behavior changed |
| Catalog/renderer | Focused evaluation and fast gate | Generated-leaf comparison only for affected clients |
| Codex wrapper | Focused wrapper/security tests and fast gate | Packaged-binary differential probes and native wrapper check |
| Consumer retirement | Read-only authoritative searches/evaluation | Full positive/refusal consumer proof |
| Mutable migration retirement | Source search and focused migration tests | Complete live host matrix plus supported rollback proof |

No per-commit parity refresh, coverage refresh, broad comment audit, Darwin golden
refresh, or full expensive run is required.

## Definition of Done

The cleanup epic is complete only when:

- normal CI and scheduled portable assurance are green on the same published
  commit;
- ordinary verification is below 120 seconds and contains no generated evidence
  regeneration;
- structural coverage and root output-denominator machinery are absent;
- the Codex wrapper delegates CLI grammar upstream and retains only demonstrated
  state/profile/security responsibilities;
- no mandatory speculative renderer or updater refactor remains;
- every removed compatibility path has authoritative consumer or fleet proof;
- no production LiteLLM provider, `positron_openai/` model, or retired Anvil
  integration remains; migration tombstones disappear when their fleet proof
  passes;
- the native Codex default remains `gpt-5.6-sol`; local oMLX and llama-swap remain
  opt-in; Pi's managed context and declarative profile link remain correct;
- current docs and retained first-party comments have no known false claim;
- no new framework or dependency was added;
- user Pi edits and mutable agent data were preserved;
- all commits are signed, the tree is clean, issue states are truthful, and only
  `~/src/nix` remains as the checkout after authorized publication and cleanup.

Line deletion is reported by category but is not a quota. A smaller system that
loses a meaningful independent safety property is not a successful cleanup.

## Stop conditions

Stop rather than widen scope when:

- the accepted decision set is ambiguous;
- preserving or retiring C1a requires destructive Git action without approval;
- a deletion requires editing an external checkout;
- a generated client leaf changes outside an explicitly accepted behavior change;
- a meaningful regression/security/state test has no smaller replacement;
- a required host or authoritative consumer is unreachable;
- a probe risks printing a secret value;
- the fast gate exceeds 120 seconds twice with the same cause;
- activation, push, publication, history rewrite, backup deletion, or session
  restart becomes necessary.
