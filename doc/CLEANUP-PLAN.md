# Cleanup Phase Plan

- Status: active frozen Definition of Done
- Prepared: 2026-08-02
- Activated: 2026-08-03

Authority: John authorized implementation by directing completion of every cleanup
issue in Project 9. That authorization covers source edits and local signed commits
for these work units; it does not authorize push, publication, activation, history
rewrite, external-checkout edits, or session restart/termination.

## Objective

Make this repository materially smaller and easier to change without altering its
user-visible configuration, model routing, update behavior, or mutable agent state.
The cleanup is complete only when current documentation is true, ordinary gates are
green and remain below two minutes, obsolete migration machinery is retired on
evidence, and no cleanup worktree or branch remains.

The phase is deletion-led. Moving an expression to another directory without
removing complexity is not progress.

## Baseline

These observations were refreshed on 2026-08-03. They remain checkpoint evidence,
not enduring invariants; every work unit refreshes the state it relies upon.

- The reviewed commit is `cf2056ec0a3681d9ef95ede54b4c5574ad33b008`.
- Before the C0 branch, local `main`, fetched Gitea `origin/main`, and fetched
  GitHub `github/main` named that commit. The current signed C0 branch is one
  documentation commit atop that baseline and adds this plan and the Wiggum
  handoff.
- `ulimit -n 65536 && lefthook run pre-commit --all-files` passed in 57.7 seconds.
- `ulimit -n 65536 && make test` passed.
- GitHub's scheduled portable run `30788387383` passed evaluation/native checks on
  aarch64 Darwin, aarch64 Linux, and x86_64 Linux for the reviewed commit.
- GitHub’s normal CI run `30715313370` is red for the reviewed commit. The failing
  diagnostic is `coverage artifact tool identity drifted: nix`; this establishes
  the immediate failure, not by itself the case for deleting the subsystem.
- `/nix/var/nix/profiles/system` resolved to generation 984. `ssh clio` failed
  because `clio.lan` did not resolve, so no plan may assume Clio’s mutable state has
  converged.
- At `2026-08-03T07:15:18Z`, explicit-`jwiegley` `gh` queries reported 24 open
  repository issues, exactly cleanup #98-#121. Project 9 had 110 items: #98/#99
  In Progress and #100-#121 Todo.

Measured concentration:

| Area | Tracked lines | Current disposition |
|---|---:|---|
| Structural coverage implementation/tests | 3,944 | Delete after preserving independent contracts |
| Structural coverage generated/manifest data | 5,330 | Delete with its owner |
| Output-denominator implementation/tests | 325 | Retain, decoupled from the coverage manifest |
| Darwin value-surface machinery | 3,915 | Retain during cleanup; reassess only after the risky changes |
| Parity oracle plus currency guard | 3,194 | Keep the manual oracle; remove completed rename logic and hot-path policing |
| Consumer/rename group (including positive gates) | 3,243 | Prune rename-only parts after live verification; retain positive gates |
| Pi and retired-MCP migration implementation | 995 production lines | Delete only after the host matrix converges |
| Codex host-state wrapper | 1,705 | Preserve state handling; delete the duplicate CLI parser |

## Hard boundaries

- Do not add a framework, generator, service, dependency, or abstraction merely to
  organize existing code.
- Do not move package bodies from `overlays/` to `packages/` solely to satisfy the
  current prose. Narrow package overlays are idiomatic and cohesive; correct the
  ownership prose instead.
- Do not edit `~/src/nixos`, the VPS checkout, or a shared-work Home Manager
  checkout during source cleanup. Those checkouts are read-only verification
  targets unless John separately authorizes a consumer change.
- Do not switch any system, push, publish, rewrite history, revoke credentials,
  restart an agent, or terminate a session without explicit authorization for that
  action.
- Never inspect or print credential values. Host convergence probes report only
  booleans, path types, generations, and exact key-name presence/absence.
- Do not regenerate an evidence artifact merely to turn a gate green. Either the
  evidence remains independently useful, or it is deleted.
- Preserve the Home Manager release-skew check, the pin-currency mechanism, signed
  publication checks, transactional updater refusal paths, mutable-state safety,
  and the direct portable compatibility contract.
- Do not delete a test because it is large. Delete it only when its asserted
  property is obsolete, self-referential, unobserved, or preserved by a smaller
  independent authority.
- For a retained golden/oracle failure, inspect the semantic diff first. An
  unexpected diff blocks the unit; an intended diff needs a written explanation
  at work-unit closeout before the golden may advance.
- Run expensive assurance once per unchanged final candidate. A corrective source
  edit invalidates the affected evidence and requires the relevant final check
  again. Scheduled portable assurance remains twice daily; ordinary commits run
  only the fast tier.

## Review decisions

These are deliberate choices, not deferred questions.

1. **Delete structural “coverage” only after separating its real contracts.** It
   records inventories and tool identities, currently observes zero of 98 Nix
   files dynamically, and does not run Python coverage. The narrow CI fix -- stop
   treating tool versions as artifact validity -- must be evaluated first, but it
   would retain 9,274 lines and the evidence-only refresh cycle. Preserve the
   independent output-denominator check and direct quality/test authorities, then
   delete only the unobserved/self-referential machinery.
2. **Do not relocate overlays wholesale.** That would change paths, tests, and
   imports without reducing behavior or maintenance burden. The architecture docs
   will describe the actual rule: reusable multi-package implementations may live
   in `packages/`; a narrowly owned package or compatibility override may live in
   its overlay. `overlays/10-emacs.nix`, `15-darwin-fixes.nix`, and grouped tool
   overlays are explicit broad exceptions organized around one integration domain,
   not examples of the “narrow package” rule. This phase deletes dead material and
   obvious repetition inside them; it does not bless or relocate them without a
   measured reuse/conflict benefit.
3. **Keep the Darwin value-surface gate through the risky work.** Git history shows
   that it caught authorization-identity and value-projection defects. Deleting it
   before wrapper/renderer cleanup would silently remove meaningful coverage.
4. **Keep parity manual, not mandatory.** Use it at package-selection or renderer
   work-unit closeout. Remove completed `config/ai` migration code from the oracle
   and stop running its currency bureaucracy on every ordinary commit.
5. **Retire finite migrations only from live evidence.** Clio’s present
   unreachability is a real blocker, not a reason to infer success.
6. **Let upstream CLIs validate their own grammar.** The Codex wrapper owns managed
   profile selection and state safety, not a second implementation of Codex’s
   complete Clap grammar.

## Execution discipline

- Use one short-lived work-unit branch and at most one extra worktree at a time.
  Read-only subagents may run in parallel; only the coordinator mutates the
  checkout. Merge and remove that branch/worktree before starting the next unit.
- One work unit equals one stated objective and normally one signed commit. A
  behavior change and its tests remain together; evidence-only follow-up commits
  are not allowed.
- Before each unit, rebase or fast-forward from current `main`.
- Every deletion begins with `rg` over tracked source, dynamic wiring, tests, docs,
  and known external consumers. “No textual caller” is not enough for Nix exports,
  plugin discovery, or generated paths.
- A unit is not Done until its focused proof passes and the worktree is clean.
- GitHub tracking uses one cleanup epic with native sub-issues at the atomic
  work-unit/subunit boundaries below. Native blocked-by links encode the dependency
  graph; bodies carry requirements, subtasks, verification, rollback, and
  authorization boundaries. Every `gh` invocation must use the `jwiegley` account
  explicitly. Update issue state at work-unit closeout, not after every commit.

## Work units

### C0. Establish truthful current authority

Objective: make the repository’s entry-point documentation describe the state that
actually exists before code cleanup begins.

Changes:

- Replace stale execution state in `doc/CURRENT-WORK.md` with the accepted cleanup
  order and the live blockers.
- Update `README.md`, `CLAUDE.md`, and `doc/ARCHITECTURE.md` to distinguish known
  canonical `config/fleet` consumer sources from the still-unverified live
  shared-work checkout.
- Correct the overlay/package ownership rule; do not move code to preserve false
  prose.
- Keep `doc/RENAME-ROLLBACK.md` until C9 proves every authoritative consumer has
  moved.
- Remove fragile local line-number references and replace them with symbol/path
  references.

Proof:

- Every local Markdown link resolves.
- Every current-state claim is backed by the current tree, Git/GitHub state, or an
  explicitly identified live-state gap.
- Fast tier passes.

Rollback: revert this documentation-only commit.

### C1. Decouple real contracts, then retire structural coverage

Objective: preserve independently meaningful contracts before deleting the
unobserved/self-referential evidence system. CI becoming green is a consequence,
not the premise.

#### C1a. Decouple Python tiers

- Replace the JSON-owned Python tier map with two conventions:
  `*-slow-test.py` runs only in the full/closeout tier; every other
  `test/bin/*-test.py` runs in the fast tier.
- Rename the three current slow suites (`gates`, `publish`, `update-overlay`) to
  the slow suffix. Keep `update-overlay-essential-test.py` fast.
- Keep exactly two Python budgets in `test/bin/quality`: 120 seconds for fast and
  900 seconds for full. Remove `pre-push`, `ci-on-demand`, and manifest parsing.

Proof:

- The quality self-test proves every tracked `test/bin/*-test.py` runs exactly once
  in full and exactly the non-slow set runs in fast.
- Fast and full tiers pass before any coverage file is deleted.

Rollback: one tier-convention commit.

#### C1b. Decouple output denominators

Extract only the checks/packages/overlays public-output contract needed by
`test/bin/output-denominators` into a small standalone contract. Keep the gate and
its negative tests in the full/closeout tier.

Proof: output-denominator tests still fail for an added, absent, or
system-misplaced root check/package/overlay, and the live gate passes before the
coverage manifest is touched.

Rollback: one output-contract commit.

#### C1c. Delete only structural coverage

First evaluate the narrow repair at `coverage-report`’s tool-identity comparison:
ignore tool-version drift and run the current check. Record whether that makes CI
green and whether it changes any observed reach. Unless it discovers meaningful
runtime evidence, proceed with deletion because the subsystem still observes no
Python dynamic coverage and zero current Nix-file reach.

Delete:

- `test/bin/coverage-report`
- `test/bin/coverage-report-test.py`
- `test/baseline/coverage-*.json`
- `test/coverage/manifest.json`
- `test/coverage/host-denominator.nix`

Then:

- Remove `coverage` and `coverage-live` from `test/bin/quality`, `Makefile`,
  Lefthook, CI, flake checks/dev dependencies, and gate wiring tests.
- Keep `output-denominators`, now independent of the deleted manifest.
- Reduce pre-push to signature verification. Full tests belong to work-unit
  closeout, not the push hot path.
- Regenerate the consumer inventory once, in this unit, only because it records
  paths being deleted. Do not create a separate evidence commit.

Complete property disposition:

| Manifest property | Disposition |
|---|---|
| `schema` and artifact/tool/source provenance | Delete with the artifact; these prove artifact identity, not product behavior |
| `budgetsSeconds` | Preserve as the two explicit fast/full quality budgets |
| `pythonInventory` | Replace with tracked-file discovery and the slow suffix convention |
| `shellOwnership` | Preserve actual lint/format/unit-test authorities; intentionally drop the manually curated gap ledger and make no behavioral-coverage claim |
| `gateDenominator.qualitySuites` | `test/bin/quality --list` remains the executable authority |
| `gateDenominator.topLevelChecks` | Preserve through the standalone output-denominator contract |
| negative-gate recipes | Retain their executable negative tests; delete duplicate manifest narration |
| `outputApplicability` checks/packages/overlays | Preserve through `output-denominators` |
| app/top-level output narration not consumed by that gate | Intentionally drop; portable compatibility and direct flake evaluation remain |
| `declaredSystems` | Flake system definitions and scheduled portable matrix remain the owners |
| `hosts` | `config/hosts/registry.nix` remains the owner |
| `evaluationRoots` | Direct Darwin, portable, immutable, and consumer gates remain; delete duplicate recipes |
| `nixFileReach` | Delete the unobserved claim; no replacement coverage claim is made |
| `blindSpots` | Delete the derived ledger; retained tools/tests state their own bounded evidence and the final report names remaining gaps |

Proof:

- `test/bin/quality --list` contains no coverage suite and still contains
  `output-denominators`.
- Fast tier passes within 120 seconds; full tier and output denominators pass.
- The local equivalent of each GitHub CI job passes; after authorized publication,
  normal CI is green on the same commit.
- The consumer inventory is current without a separate evidence-only commit.

Rollback: one coverage-deletion commit restores every removed artifact and gate;
C1a/C1b remain independently useful.

Expected reduction, reported rather than used as a quota: 3,944 implementation/test
lines and 5,330 generated/manifest lines, with a small standalone output contract
added and no dependency added.

### C2. Remove dead prose and commented-out implementation

Objective: comments describe what is; Git describes what used to be.

#### C2a. Mechanical dead-comment deletion

- Delete inert ZFS, PostgreSQL, MAS, registry, cask, Coq HEAD, Initsplit,
  pdf-tools, Proof General, timestamp, and default-setting blocks already proven
  to be commented-out code.

Proof: Nix parsing/evaluation and the fast tier are unchanged; no semantic comment
judgment is mixed into this commit.

#### C2b. Semantic comment audit

The tracker schedules this after C3-C8 so it audits the retained post-refactor
source rather than producing immediately stale prose evidence.

- Replace stale `homeClass`, portable-definition, and shared-work line-number
  citations with stable symbol/path references.
- Shorten historical incident narratives in `test/bin/quality`, Lefthook, CI,
  publication tools, and retained tests to the current invariant and the reason it
  is non-obvious.
- Do not rewrite third-party or vendored Emacs comments blindly. First establish
  provenance. Exclude a vendored file explicitly, or clean it only if this
  repository owns the implementation.
- Do not repair prose inside files scheduled for deletion in C9; delete the file
  once its retirement gate passes.

Audit denominator:

- Every tracked `*.nix` file.
- Every Python and shell source discovered by `test/bin/quality`, including
  extensionless `bin/` and `test/bin/` programs.
- Tracked first-party YAML, TypeScript, JavaScript, and Emacs Lisp source.
- Exclude generated locks/JSON, patches, keys/certificates, and a third-party Emacs
  file only after provenance is established and recorded in the audit result.
- Agent/command/skill/prompt prose is reviewed as documentation in C0/C11 rather
  than misclassified as source comments.

Proof:

- No retained first-party file contains unexplained dead commented-out
  implementation; a deliberate example or disabled alternative names its live
  purpose.
- No retained comment refers to a mutable local line number.
- `TODO`/`FIXME` markers are either removed or state a still-live condition and
  owner; template examples and vendored source are reported separately.
- A bounded comment audit over retained first-party source has no
  STALE/INCORRECT/MISLEADING/ORPHANED verdict.
- Fast tier passes.

Rollback: C2a and C2b revert independently. No runtime value should change.

### C3. Apply the small obvious deduplications

Objective: remove duplicated code where the replacement already exists.

Each subunit is an independent signed commit; they are grouped here only because
they are low-risk and may share one review session.

#### C3a. One formatter implementation

- Make `test/ai/scripts/format.sh --check` own both formatting modes; delete the
  duplicate `format-check.sh` body and pass `--check` from the app/check wrapper.

Proof: both public app names produce the same writes/diffs as before, then the fast
tier passes.

#### C3b. One credential launcher

- Use the generic command-executing credential launcher for Codex; delete
  `bin/codex-env` and merge its non-disclosure/refusal cases into the surviving
  launcher test. Preserve fail-closed behavior and first-line-only credential
  loading.

Proof: tests assert exact argv forwarding, environment-only secret transport,
non-disclosure, and refusal before command execution.

Retain `bin/update --no-switch`, `bin/update --no-brew`, and the explicit
`bin/update-overlay --no-build` rejection. They are user-visible CLI compatibility,
a repository search cannot prove the absence of human callers, and their few lines
do not justify an unrequested break.

Rollback: C3a and C3b revert independently.

### C4. Delete unused catalog evidence

Objective: remove data that has no consumer.

Changes:

- Delete `selectorCoverage` and its private `secretCapabilities` construction from
  `config/fleet/catalog.nix`; current source has no consumer beyond the export.

Proof:

- Source search confirms no external or dynamic consumer.
- `catalog.profiles`, `catalog.items`, selection, validation, and every generated
  leaf are unchanged.
- Focused catalog/preflight evaluation and the fast tier pass.

Rollback: one deletion-only commit.

### C5. Reduce renderer policy duplication

Objective: keep client policy in one owner without creating a renderer framework.

#### C5a. Move transport-selection invariants into catalog policy

- Move Pi’s exact selected provider/MCP/header invariants to the catalog/model
  policy that owns selection, with negative tests showing that an undeclared
  expansion still fails. Keep the renderer’s exact Hera-profile assertion unless
  this unit explicitly adds another supported Pi profile; broadening support is not
  cleanup.
- Replace Droid’s `Ref`/`context7` name restriction only after catalog validation
  owns the allowed header-bearing transport set. Retain the one-header,
  typed-environment, bridge-argv, and negative invalid-name/shape checks.

Proof: transport leaves remain byte-identical and equivalent negative fixtures
reject every previously rejected provider/MCP/header/profile state.

#### C5b. Centralize Pi/Codex local-model choices

- Put unavoidable Pi/Codex local model choices in the existing model policy rather
  than duplicating model IDs in renderers. Do not introduce a generic renderer
  framework.
- Do not extract helpers unless at least two byte-identical implementations are
  deleted and the resulting total line count falls.

Proof:

- Pre/post generated Pi, Codex, Droid, Claude, and OpenCode leaves are byte-identical.
- Pre/post negative fixtures reject the same invalid provider, MCP, header, and
  unsupported-profile states; moving an invariant must not broaden accepted input.
- Pi still exposes the same local providers, router, context/output limits, MCP
  set, commands, skills, and extensions.
- Codex still defaults to native `gpt-5.6-sol`; oMLX and llama-swap remain opt-in.
- No LiteLLM provider or `positron_openai/` model appears.
- Focused wrapper, Pi gallery, preflight, and Darwin value-surface checks pass.

Rollback: split transport generalization and model-policy moves into independently
revertible commits. Catalog deletion is C4 and is not part of this work unit.

### C6. Collapse updater preparation modes

Objective: keep one transactional updater without five hidden boolean modes.

Changes:

- Replace `--prepare-fixed-inputs`, `--prepare-npm-flake-inputs`,
  `--prepare-npm-locks`, `--prepare-pypi-artifacts`, and
  `--prepare-github-projections` with `--prepare KIND` and `argparse` choices.
- Replace the repeated shell invocations in `bin/update` with one small helper.
- Use a data table for kind selection and dispatch instead of repeated boolean
  expressions.
- Delete tests for impossible boolean combinations. Retain one positive and one
  candidate-only/refusal case per preparation kind, transaction rollback, target
  isolation, and exact-path ownership.

Proof:

- Inventory JSON is byte-identical.
- A dry run leaves the worktree byte-clean.
- Every preparation kind retains positive, failure, and rollback coverage.
- Essential and full updater suites pass.
- No real update, lock rewrite, commit, publication, or activation is used as a
  test.

Rollback: one updater/test commit.

### C7. Delete the duplicate Codex CLI parser

Objective: retain managed profile/state behavior while delegating syntax validation
to the packaged Codex CLI.

Preserve:

- Host-local SQLite/log separation and one-time state movement.
- Managed-artifact classification.
- Atomic, owner-checked runtime profile creation.
- Explicit caller-profile conflict refusal.
- The bypass escape hatch.

Delete:

- The wrapper’s second implementation of every Codex command, option,
  positional-argument count, and invalid-combination rule.

Replacement:

- Identify only whether the top-level command is one of the upstream commands to
  which profiles apply (including `debug prompt-input`).
- Detect an explicit caller profile and refuse the managed-profile conflict.
- Refresh the runtime profile, prepend `--profile nix-runtime`, and let Codex’s
  Clap parser accept or reject everything else.
- Bypass profile injection for commands that upstream says do not accept it.

Proof:

- Derive the supported-command set from the pinned Codex source’s
  `profile_v2_for_args` behavior before editing.
- Probe the actual packaged binary’s top-level command/help matrix.
- Compare wrapped and unwrapped exit status for malformed invocations; the wrapper
  may add only the documented managed-profile conflict.
- Retain focused tests for `--`, prompt text that resembles an option, explicit
  profiles, bypass, partial artifacts, runtime-profile path attacks, and state
  migration failure.
- Build the agent-wrapper check and run the focused wrapper suite without touching
  the real Codex home or SQLite state.

Rollback: one isolated wrapper/test commit. Do not activate it until the focused
proof and full closeout gate pass.

Target: remove at least 700 wrapper lines. If upstream behavior makes that unsafe,
stop and record the concrete counterexample; do not merely move the parser.

### C8. Remove completed parity-rename bureaucracy

Objective: retain parity as a deliberate manual comparison, not a per-commit
artifact-maintenance programme.

#### C8a. Remove completed rename-migration logic

- Delete the one-time `config/ai` to `config/fleet` command-migration mode from
  `test/bin/parity-baseline` and its tests.

Proof: the retained oracle passes, a synthetic multiset change fails, and no
rename-migration mode/fixture remains.

#### C8b. Move currency validation to closeout

- Move `oracle-currency-test.py` out of the fast tier, but retain it in full
  closeout. `parity-baseline --check` requires `HEAD == baselineRev` and therefore
  does not replace the cheap ancestor/filename/count/history/current-command guard.
  Delete the guard only if those properties first move into a smaller cheap
  current-HEAD mode with equivalent negative tests.
- Keep one parity artifact and `doc/PARITY-ORACLE-REFRESH.md` while package/profile
  selection remains a supported invariant.
- Run parity only for a change capable of changing selection, and no more than once
  at that work unit’s closeout.

Proof:

- The retained oracle passes its direct check.
- A synthetic changed package multiset still fails.
- No ordinary hook or normal CI job derives the parity artifact; cheap currency
  validation runs only at full/work-unit closeout.

Rollback: restore the currency guard if the direct oracle cannot fail closed.

### C9. Verify consumers, then retire rename machinery

Objective: delete the finished `config/ai` rename programme after proving the live
world no longer needs it.

#### C9a. Prove every maintained consumer uses `config/fleet`

Required evidence:

- Vulcan authoritative `/etc/nixos`: paired root/portable inputs resolve to one
  revision and portable `dir=config/fleet`.
- VPS authoritative `/etc/nixos`: same.
- Shared-work authoritative `~/.config/home-manager`: same; the local Andoria
  checkout is only a proxy and is insufficient.
- GitHub code search, using the explicit `jwiegley` account, finds no maintained
  `?dir=config/ai` consumer.
- Gitea/local consumer search finds no maintained `?dir=config/ai` consumer.
- Each changed/verified consumer evaluates without activation.

This is read-only evidence gathering; it edits or activates no consumer.

#### C9b. Retire `config/ai` compatibility machinery

After C8a and C9a pass, delete:

- `config/ai/flake.nix`
- Rename-only portions or the whole of `test/bin/consumer-inventory` and its
  committed artifact, according to whether any non-rename consumer contract remains
  independently useful.
- The stale-stub negative branch in `test/bin/cross-consumer-eval`.
- The stale-path branch in `test/bin/immutable-subflake-check`, retaining the
  positive immutable `config/fleet` proof.
- `doc/RENAME-ROLLBACK.md` and every instruction that tells current consumers to
  migrate.

Proof:

- `rg` finds no operational `?dir=config/ai` reference; historical test fixtures
  are gone with their owner.
- Positive portable and consumer evaluations pass.
- Full closeout tier passes.

Rollback: revert the deletion. Do not delete or rewrite any consumer checkout as
part of this unit.

### C10. Verify mutable homes, then retire finite migrations

Objective: remove one-shot state migration only after it has done its job everywhere.

Host matrix:

| Evidence | Hera | Clio | Andoria-08/T2, Delphi, GPU | VPS | Vulcan |
|---|---:|---:|---:|---:|---:|
| Active generation contains retired-MCP cleanup | required | required | each host | required | required |
| No mutable Codex/Claude/Pi/manifest Anvil key remains | required | required | shared home plus each local root | required | required |
| No URL-query credential remains in managed mutable MCP state | required | required | shared home plus each local root | required | required |
| A second activation/client cycle does not reintroduce retired state | required | required | each host | required | required |
| Codex legacy Ref import is no longer needed | required | required | each Codex host | n/a | n/a |
| Codex log path is host-local and migration leftovers are absent | required | required | each Codex host | n/a | n/a |
| Pi profile marker, final directory, and `.pi` symlink are correct | required | n/a | n/a | n/a | n/a |
| Old generation capable of reintroducing retired layout is outside rollback horizon | required | required | each host | required | required |

All probes print only pass/fail and path type. Existing sessions are not restarted or
killed.

Each retirement is a separate signed commit.

#### C10a. Retire MCP convergence

After the complete fleet matrix is green, delete
`config/fleet/retired-mcp-cleanup.{nix,py}`, catalog tombstones, activation, and
migration-only tests. Remove `simplejson` and `tomlkit` from this cleanup program’s
closure if no other repository consumer remains.

#### C10b. Retire the Codex legacy Ref importer

After every Codex host launches normally using the environment/password-store path,
has no native legacy `Ref` table, and connects without displaying a value, delete
`codex_import_legacy_ref_api_key` and its fake legacy-output cases.

#### C10c. Retire Pi XDG migration

After Hera has two successful post-migration generations, the completion marker is
regular, `.config/pi/agent` is real, `.pi` resolves to `.config/pi`, no staging or
temporary destination-backup path remains, and a fresh Pi preserves sessions,
delete
`config/pi-profile-migration.nix` and its activation/test cases. Retain the
declarative `~/.pi -> ~/.config/pi` link. `.pi-legacy-v1` is a preserved user
backup, not transient staging; its presence neither blocks retirement nor
authorizes deletion.

#### C10d. Retire Codex log-directory migration

After Hera, Clio, and every shared-work Codex host has the expected host-local log
symlink, no `log.pre-host-state.*` residue, and a fresh session works, delete only
the old-directory migration branch and its failure test. Keep symlink validation,
SQLite isolation, and memory seeding.

#### C10e. Retire Darwin gpg-agent handoff when both hosts permit it

First prove no supported current module can emit the old label: every managed home
must keep Home Manager `gpg-agent.enable = false`, source search must find no other
producer, and every generation in the supported rollback horizon must postdate the
handoff. Then require two Hera and Clio activations to report both old launchd
labels absent before deleting the guard and its dedicated test. Absence observations
alone are insufficient. Clio currently blocks this retirement.

The Home Manager 25.11 SSH translation is not a finite cleanup candidate today.
Keep it until both VPS and Vulcan use a Home Manager that exposes
`programs.ssh.settings`, native builds/activations pass, and rendered SSH/Wi-Fi
ordering remains equivalent.

Proof:

- The source contains no Anvil production, prompt, command, skill, manifest, cache,
  or test fixture reference.
- Generated agent leaves remain unchanged except for removal of migration-only
  activation code.
- Fast and full tiers pass; native Hera build passes without activation.
- A fresh session/runtime check is requested from John if needed; the agent does not
  restart it itself.

Rollback: revert source deletion. Preserve user backups until John separately
authorizes their removal.

Blocker rule: if any host is unreachable or ambiguous, C9/C10 remain blocked and the
cleanup phase is not reported complete.

### C11. Close out and remove the plan

Objective: prove the smaller repository, publish only with authorization, and leave
no cleanup debris.

Final verification, once per unchanged candidate. Any corrective source edit
invalidates the affected evidence and requires the relevant step again:

1. Fast tier, with elapsed time recorded and below 120 seconds.
2. Full issue-closeout tier.
3. Portable all-system no-build check.
4. Native AI checks used by `make test`.
5. `./build system` without activation.
6. One final expensive assurance run; do not duplicate the twice-daily portable
   workflow.
7. Current-head normal CI and portable assurance green after authorized publication.
8. Current documentation/comment audit and local-link check.
9. Git status, signature, remotes, worktrees, and branches checked from live state.
10. GitHub cleanup checklist reconciled and closed using the explicit `jwiegley`
    account.

Then:

- Update `doc/CURRENT-WORK.md` for the next phase.
- Delete this plan; Git history is its archive.
- Rebase/fast-forward into `main` only with authorization.
- Remove the cleanup branch/worktree and verify only `~/src/nix` remains.

## Per-unit gate policy

| Change type | Per-commit gate | Work-unit closeout |
|---|---|---|
| Documentation/comment only | Link/reference check plus fast tier | Comment audit of touched retained files |
| Shell/Python utility | Focused unit test plus fast tier | Full tier if transaction/security behavior changed |
| Nix catalog/renderer | Focused eval/build plus fast tier | Generated-leaf comparison and relevant native check |
| Updater | Essential updater tests plus fast tier | Full updater suite and clean dry run |
| Migration retirement | Source search plus fast tier | Complete live matrix, full tier, native build |
| Package/profile selection | Focused eval plus fast tier | One parity comparison |

No commit receives an evidence artifact refresh as its own follow-up commit.

## Definition of Done

The cleanup phase is complete only when all of the following hold:

- Normal CI and scheduled portable assurance are green on the same current commit.
- Fast mandatory verification is at most 120 seconds.
- The structural coverage system is absent; the independent output-denominator
  contract remains a full/closeout check.
- Current docs contain no known false current-state or ownership claim.
- Retained first-party comments contain no known stale, incorrect, misleading, or
  orphaned claim, and no unexplained dead commented-out implementation remains.
- The Codex wrapper delegates syntax validation upstream; if a concrete upstream
  counterexample requires retained parsing, only the demonstrated minimum remains
  and its reason is recorded.
- Updater preparation has one mode selector, not five booleans.
- Renderer output is unchanged while duplicated client policy has one owner.
- No production LiteLLM reference or `positron_openai/` model exists.
- No Anvil reference remains after the live migration matrix permits retirement.
- No completed `config/ai` rename machinery remains after live consumer proof.
- No new dependency or framework was added.
- Every retained large mechanism has a current rationale and a named manual or
  automated invocation boundary.
- All commits are signed; the worktree is clean; both remotes agree; one branch and
  one worktree remain.
- No user session was killed or restarted by the cleanup agent.

The closeout report separates implementation, tests, generated data, and prose in
its before/after counts. No line-deletion quota is a success criterion; useful code
is not removed to improve the scoreboard. Successful migration retirement should
also remove the cleanup program’s `simplejson`/`tomlkit` dependency.

## Stop conditions

Stop and ask John rather than widening scope when:

- a deletion would require editing Vulcan, VPS, or shared-work source;
- a generated leaf changes outside an explicitly intended policy move;
- a test with demonstrated regression value has no smaller replacement;
- Clio or another required host remains unreachable for C9/C10;
- a credential-bearing check cannot be expressed without exposing values;
- the fast tier exceeds 120 seconds twice with the same signature;
- a real update, activation, push, or session restart appears necessary.
