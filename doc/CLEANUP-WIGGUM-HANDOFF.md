# Cleanup Programme: Completion Report and Session Handoff

Updated: 2026-08-07

## Purpose

This document is the current resume authority for completing Project 9's
`nix-config` cleanup epic. It records the exact repository checkpoint, the work
that remains, the interrupted scratch work, the host and authorization
boundaries, and the order in which completion evidence must be obtained.

The governing Definition of Done remains
[`CLEANUP-PLAN.md`](CLEANUP-PLAN.md). Its dated "Current checkpoint" is
historical; its governing rules, accepted decisions, verification matrix,
Definition of Done, and stop conditions remain binding. This handoff supersedes
every older cleanup handoff, runbook, transaction archive, host snapshot, and
scratch report as a statement of current intent. It does not itself authorize
an implementation edit, commit, GitHub mutation, host operation, publication,
activation, live mutable-state reconciliation, session control, or destructive
cleanup. The next session must wait for John to direct continuation before
acting on the work described here.

## Executive status

The project is substantially reduced, but it is not complete. There are two
qualification and operation boundaries, one deferred Project item, and one
final closeout boundary. The tracker-reconciliation boundary is complete:

1. Finish, freeze, qualify, authorize, and run the bounded mutable-state
   reconciliation for #127; then prove in two complete fleet cycles that Anvil,
   Ref, Perplexity, and PromptDeploy state is not recreated before closing
   #116, #124, and #127.
2. Finish #128's permanent bounded-memory Pi-session qualification. The
   implementation, exact fixture, 1 GiB scale, managed package, and downstream
   consumer gates passed on the base candidate; published follow-ups have
   narrower targeted evidence. The fresh eight-hour process/computation gate
   passed, but its sealed final checker failed a lexical `/var` versus
   `/private/var` retained-path predicate, so the eight-hour evidence remains
   incomplete and requires a corrected rerun. #128 can proceed independently
   of the fleet spine but explicitly blocks #121.
3. Keep #130's deferred PAL-restoration Todo visible; it is open but does not
   currently block the cleanup spine.
4. Run #121 once on one unchanged final candidate: reconcile documentation and
   comments, remove cleanup documents, run the final verification matrix,
   publish with separate authority, require same-commit CI and portable
   assurance, and close #98 last.

At this 2026-08-07 checkpoint, the formerly mixed working tree has been
separated with the Git surgeon workflow, rebased, and published as a
twenty-eight-commit signed series after `5593f2c7`. Commit `bad199f5` is the
published implementation and package-integrity tip before this evidence-only
handoff update. The single worktree was clean, network reads found both
`origin/main` and `github/main` at that commit, and its signature was good.
Normal CI run `31182626550` passed all four jobs on exact commit `bad199f5`.
Neither that CI result nor the soak evidence below establishes activation or
live-session continuity. At evidence checkpoint `686a7334`, normal CI run
`31178896021` and Portable Assurance run `31179553744` passed all four jobs
each. The portable native matrix includes the corrected Pi RSS gate but not
the capability-blocked Linux Codex-wrapper lane.

The last complete fleet activation proof remains the #126 boundary at
`e7dc846c`. Later successful builds, evaluations, and single-host checks must
not be described as proof that the current source is active on every host.

## Evidence vocabulary

The next session must keep these claims distinct:

- **Source proof** establishes what the checked-in repository contains.
- **Evaluation proof** establishes that a configuration evaluates.
- **Build proof** establishes that a closure can be realized.
- **Activation proof** identifies the generation and closure selected by a
  host.
- **Runtime proof** uses a fresh disposable client against that activated
  generation.
- **Fleet proof** records the required result independently for all eight host
  views.

No earlier class implies a later one. Historical hashes, counts, host routes,
generations, reachability, client lists, and residue matrices are diagnostic
baselines only. Refresh every volatile fact at the boundary where it matters.

## Current Project 9 state

Project 9 was refreshed through the explicitly selected `jwiegley` GitHub
account on 2026-08-07 after publication. It contained 124 unarchived issue
items: 117 Done, six In Progress, and one Todo:

| Issue | Remaining purpose |
|---|---|
| [#98](https://github.com/jwiegley/nix-config/issues/98) | Parent cleanup epic; close last. |
| [#116](https://github.com/jwiegley/nix-config/issues/116) | Prove fleet-wide Anvil convergence and supported rollback horizon. |
| [#121](https://github.com/jwiegley/nix-config/issues/121) | Run final unchanged-candidate verification and remove cleanup debris. |
| [#124](https://github.com/jwiegley/nix-config/issues/124) | Prove Ref and Perplexity removal from every client and mutable home. |
| [#127](https://github.com/jwiegley/nix-config/issues/127) | Reconcile retired PromptDeploy state and uniquely owned stale payloads. |
| [#128](https://github.com/jwiegley/nix-config/issues/128) | Implement permanent bounded-memory Pi sessions; an independent explicit blocker for #121. |
| [#130](https://github.com/jwiegley/nix-config/issues/130) | Todo: restore PAL MCP; explicitly deferred and not a blocker for current work. |

The effective dependency order is:

```text
#127 bounded reconciliation
  -> #116 two-cycle Anvil convergence
  -> #124 two-cycle Ref/Perplexity closeout
  -> #121 unchanged-candidate closeout
  -> #98 epic closeout

#128 bounded-memory Pi sessions
  -> #121 unchanged-candidate closeout

#130 restore PAL MCP (deferred Todo; no dependency edge into this closeout)
```

The #116 and #124 runtime probes and activation cycles should be combined where
their evidence boundaries agree, but their issue-specific acceptance results
must remain explicit. #128 can proceed independently of that spine but must land
before #121 under its current issue-body authority; GitHub's native dependency
API does not encode that prose edge. The Codex-wrapper correction associated
with closed #111 must remain in the unchanged candidate. Its corrected closeout
is recorded in
[#111 comment 5217376659](https://github.com/jwiegley/nix-config/issues/111#issuecomment-5217376659),
and [#121 comment 5217377344](https://github.com/jwiegley/nix-config/issues/121#issuecomment-5217377344)
carries the correction and its unproved Linux/activation boundaries forward.
#130 is a real open Project item but its body explicitly defers it and says not
to block current work on a live PAL dependency; do not silently count it Done
or invent a cleanup dependency.

Every future `gh` command must explicitly select the `jwiegley` account. A safe
read pattern is:

```sh
GH_TOKEN="$(gh auth token --hostname github.com --user jwiegley)" \
  gh issue view 127 --repo jwiegley/nix-config
```

Do not use an ambient or ambiguous GitHub account.

[#127 comment 5217378220](https://github.com/jwiegley/nix-config/issues/127#issuecomment-5217378220)
now supersedes the earlier eight-file, 47/106/15-test checkpoint. It identifies
the frozen thirteen-member R3 archive, preserves the exact eight qualification
plus twelve observation receipt taxonomy, and explicitly states that the
status correction does not authorize running the operator or any later live
action.

## Completed repository work

The current source and signed history establish the following completed
boundaries:

- #99-#108, #110, and #112-#115 are complete. Structural coverage, root output
  denominators, parity/currency evidence machinery, dead selector metadata,
  mechanical Nix debris, and the `config/fleet` compatibility surface have
  been removed or reduced according to the accepted plan.
- #111 is tracker-closed and its corrective source is published to both remotes
  as signed commit `ea0327cf`. Its corrected closeout and #121 carry-forward are
  posted in comments `5217376659` and `5217377344`.
- #109 was closed as not planned after its compliant implementation proved
  larger and more complex than the duplication it would replace.
- #104 completed the prior comment audit. Its denominator is not the final
  denominator: retained files changed after that audit and must be covered once
  more during #121.
- #117 was superseded by #124. #118-#120 and #122-#126 are closed.
- The portable configuration owner is `config/ai/`. `config/ai.nix` is the
  separate Home Manager integration module.
- OpenCode has intentionally been restored as a package only. It is selected in
  `config/packages.nix` and `flake/ai.nix`, but has no restored fleet profile,
  renderer, model registry, or MCP configuration. The #127 transaction must
  preserve `~/.config/opencode` and every unrelated descendant.
- Current production source contains no PromptDeploy, Anvil, Ref/Perplexity
  MCP, Context7/context-hub, memory-vault, or LiteLLM producer or integration.
  The retained Anvil occurrence in `test/ai/pi-gallery.nix` is an intentional
  negative guard. The generic word `perplexity` in the transcript vocabulary is
  a model metric, not the retired service.
- Native OpenAI Codex remains the default. Local oMLX and llama-swap routes are
  opt-in. Pi obtains `gpt-5.6-sol` through `openai-codex`.
- Starship now renders the simple hostname on every machine followed by the
  current directory and prompt character; commit `77e13163` removed the user,
  cloud, Git, duration, and remote-only hostname distinctions.
- CM repository configuration can no longer persist provider credentials.
  Signed commits `16a90c8d`, `0a682e44`, `13fe2a90`, and `a1067f19` restore the
  environment-only guard and exercise its portable failure behavior.
- Prime Agent managed settings are authoritative for package and resource
  resolution. Signed commits `096de97e` and `e3b191c4` fix the built-in
  `skill-creator` collision and add bounded end-to-end runtime coverage.
- The repository's anti-snapshot testing policy is documented in
  [`test/README.md`](../test/README.md): configuration rosters, source-spelling
  mirrors, and completed-migration inventories are not desired tests.
- Current operator and architecture references are
  [`README.md`](../README.md), [`ARCHITECTURE.md`](ARCHITECTURE.md), and
  [`bin/README.md`](../bin/README.md).

These are source statements only. They do not prove that mutable homes are
clean, that every host has activated current source, or that fresh clients
cannot recreate retired state.

Do not delete recovery refs or ignored paths merely to make the repository look
smaller. The checkout contains non-branch recovery namespaces under
`refs/branchless`, `refs/pi-checkpoints`, `refs/snapshots`, `refs/wiggum`, and
`refs/notes`, plus ignored agent/build/recovery material. They are not extra
branches or worktrees. `git clean -X` is prohibited without separate explicit
authority.

## Remaining work at a glance

| Stage | State | Completion boundary |
|---|---|---|
| R3 reconciliation source | Frozen and reviewed offline | The exact thirteen-member archive passes a 400-test fresh-extract validation on Darwin; this is not host or live-use authority. |
| Qualification helpers | Complete offline | The hash-bound helper trio is frozen in the reviewed archive. |
| Freeze builder | Fixed and reviewed | Four focused normal/optimized tests and Ruff pass; two Pyright annotation findings are outside its accepted historical gate and remain recorded rather than silently changing reviewed bytes. |
| Final transaction archive | Complete offline | The mode-`0600`, 96,845-byte archive and an independently reproduced copy have SHA-256 `e21886f2...9437d`. |
| Final transaction runbook | Draft | Contains 57 placeholders and is explicitly non-executable. |
| Host qualification | Missing | The private hash-bound operator bundle has independent fess GO; the archive has not run on any required host/view. |
| Owner/live gates | Missing | Fresh metadata, payload, Clio-link, quiescence, reachability, and one-runner authority are required. |
| Live reconciliation | Not run | No live mutable state was changed by the halted lane. |
| Two-cycle fleet proof | Not run | Required before #116/#124/#127 close. |
| Codex wrapper correction | Published and tracker-reconciled | Commit `ea0327cf` passes the Darwin wrapper and pre-commit gates and is on both remotes; comments `5217376659` and `5217377344` correct #111 and carry its evidence ceiling into #121. The Linux wrapper lane remains capability-blocked before wrapper execution. |
| #128 bounded-memory Pi sessions | Qualification in progress; corrected soak rerun required | Base implementation `e2c002e0`, published follow-ups `11f8de49`, `32489eb8`, `adda9631`, and package-integrity tip `bad199f5`; historical exact-fixture, full-suite, 1 GiB-scale, managed-package, and consumer gates passed at their recorded candidates. The eight-hour process gate exited zero and met the growth ceiling, but its sealed retained-path predicate failed, so that evidence is incomplete. Linux profiling, current-candidate gates, activation, and direct existing-session resumption also remain open. |
| Prime Agent managed settings | Published and locally qualified | Commits `096de97e` and `e3b191c4` pass 199 selected package tests, both Prime integration selectors, managed preflight, host behavior, pre-commit, a Hera system build without activation, and normal CI. Portable Assurance run `31179553744` also passes at evidence checkpoint `686a7334`; neither build nor CI establishes activation. |
| #130 PAL restoration | Deferred Todo | Open Project item with no cleanup dependency edge; retain as explicit deferred work rather than miscounting it as Done. |
| #121/#98 closeout | Blocked | Begins only after the preceding boundaries are complete. |

## #128 bounded-memory Pi checkpoint

Base implementation commit `e2c002e0` replaces eager active-session
materialization with a disposable SQLite index and deferred message source
while retaining the JSONL file as the durable authority. It also migrates
automatic Pi extensions to bounded pages, iterators, or targeted lookups;
bounded tree previews do not hydrate full records, and explicit export/legacy
APIs retain exact recall. Published follow-ups `11f8de49`, `32489eb8`, and
`adda9631` make the RSS gate portable, refresh the bounded-history patch for
the current pi-subagents source, and update pi-subagents to 0.42.1.

Historical verification for the `e2c002e0` candidate before its clean rebase
is:

- coding-agent: 191 files passed, 1,864 tests passed, 48 skipped;
- agent core: 18 files passed, 246 tests passed, one skipped;
- exact historical fixture: 90,084,344 bytes, 203,163 lines, source SHA-256
  `c083e1f5e74b67c9fabbd4abcc2a8b036399400edfc5645056a4b021ed304ffa`;
  forward and reverse hashes matched and the source remained unchanged;
- 1 GiB scale: 1,074,007,601 indexed bytes, 64 compactions, 40,402,944 bytes
  of adjusted RSS growth against the 128 MiB ceiling;
- compiled Bun binary and managed Nix package RPC/session smokes passed;
- `aarch64-darwin` Pi, Pi gallery, agent-resources, and agent-wrapper builds
  passed, including the packaged deferred-agent-core contract; and
- the full repository pre-commit tier passed all seven suites.

At the earlier published checkpoint `2543b5cc`, the targeted pi-subagents
package build, Pi gallery check, and pre-commit tier passed before publication.
At published evidence checkpoint `686a7334`, the focused pi-subagents updater,
package, Pi gallery check, all seven pre-commit suites, normal CI run
`31178896021`, and Portable Assurance run `31179553744` pass. All four Portable
Assurance jobs are green, including the `aarch64-linux` native Pi gallery/RSS
lane. This verifies the `11f8de49` 32,505,856-byte portable ceiling at that
checkpoint; ancestor run `31161435108` failed the lane at 29,884,416 bytes
against the former 29,360,128-byte ceiling. These source/build checks do not
substitute for the open soak, direct large-session resumption, activation, or
promotion evidence.

The current package-integrity candidate regenerates the pi-subagents patch
against the exact normalized 0.42.1 release source instead of relying on
header-only hunk adjustments. Package construction now uses
`--backup-if-mismatch` and fails if patch backup or reject artifacts remain;
the Pi gallery check independently rejects those artifacts across every
packaged root outside `node_modules`. That invariant exposed the same issue in
pi-goal-x, whose bounded-history patch now runs before the child-process guard
substitution and has the same fail-closed artifact check. Focused pi-subagents
and pi-goal-x builds applied without offset or fuzz diagnostics, their realized
roots contain no `.orig` or `.rej` files, and both package trees are otherwise
byte-identical to their prior effective outputs. The full `aarch64-darwin` Pi
gallery check passes, including all seven pi-subagents bounded-history tests.
These are package/source checks, not soak, activation, direct-resumption, or
promotion evidence.

The fresh eight-hour process/computation gate reported `durationMs` 28,800,471
and subsequently exited zero. Its final object reported 26,893 messages, 1,681
compactions,
32,768-byte payloads, 888,276,251 history bytes, first- and last-quarter
adjusted-RSS medians of 92,307,020 and 94,355,018 bytes, 2,047,998 bytes of
adjusted growth against the strict 134,217,728-byte ceiling, 94,470,144 bytes
maximum RSS, and 94,470,144 bytes final process RSS. This establishes only the
narrow computational gate: the final envelope had no remaining unified-tool
`session_id` field, recorded exit status zero, and byte-bound the final
`mode: "soak"` object.

The pre-outcome final checker, sealed before final completion, nevertheless
failed. The process emitted its retained path with macOS's `/var` spelling,
while the sealed checklist required literal equality with the equivalent
`/private/var` spelling. `realpath` and exact device/inode/size/mode/mtime
receipts prove that both spellings identify the same JSONL and sidecar, so no
artifact substitution or corruption occurred. Changing the locked
string-equality predicate after seeing the result would be invalid. Both
independent adjudications agree that the raw process assertions passed, the
sealed Section-2 checker failed, and the eight-hour evidence is incomplete.
The final evidence record uses **SCRIPT GATE: PASS** only for the narrow
computational gate, then records **SEALED SECTION-2 CHECKER: FAIL**,
**EIGHT-HOUR EVIDENCE: INCOMPLETE**, and **ISSUE #128: OPEN**. A corrected,
independently reviewed rerun is required.

The private evidence bundle `pi128-soak-20260807.SEMrTR` preserves same-device,
distinct-inode APFS clones and 24 hash-bound evidence files. Its manifest
SHA-256 is
`c30f01808c30701d3d66195c72ee7e821d934c4ca00f615cefd7ab0f75cc3aca`.
The 888,276,251-byte JSONL has SHA-256
`0abe5058da30c740889b63e374a0ba30c2bb58a482e1c7add76deb65eaae95af`
and exactly 28,577 complete records; the 113,143,808-byte SQLite sidecar has
SHA-256
`51d3f3299659c303c3b4bc6f254ae3e0372a20f4baa287a6f459299a965fae05`
and 28,576 indexed entries. The cloned sidecar passed immutable `quick_check`,
schema version 7, exact source offset/identity/parent/type/count checks, and the
whole-JSONL prefix-chain verifier; no journal, WAL, or shared-memory sidecar was
present. These successful checks preserve useful evidence but do not override
the sealed predicate failure.

Session 32017 launched from then-unstaged #128 worktree bytes based on
downstream `56c8412e` and upstream Pi v0.83.0 commit
`845d6ff1f6643aba440341cce877ce1c43ebbc39`. The unchanged bytes were staged
and serialized seven seconds later as patch SHA-256
`4bdb9524839764bf9639740be782e0719168d885332e5cf2b70da16c95f7494a`,
then captured as `d42c6a08` and rebased/published as `e2c002e0`. Rechecks match
the launched Node, source, loaded module, two dist NARs, check-script, and patch
identities, with no post-launch files in either dist tree. Current repository
tip `bad199f5` is a separate package-integrity identity, not the launch tree.
The source scratch remains `/private/tmp/pi128-upstream.qhiEdH`; never push it
to its upstream remote. The run did not activate a generation, profile Linux,
or open or resume the existing large GLM-5.2 session. Linux profiling,
current-candidate gates, the corrected soak rerun, reviewed upstream/pin work,
authorized deployment, and direct live-session continuity remain open; #128
continues to block #121.

## Prime Agent managed-settings checkpoint

The `make switch` failure was a package-manager precedence bug rather than a
Nix module collision. Prime's scalar getters used effective managed settings,
but `DefaultPackageManager.resolve()` still read raw global and project files.
The renderer's managed exclusion of bundled `skill-creator` was therefore
ignored, and Prime tried to load the bundled and shared resources together.

Signed commit `096de97e` makes managed package and resource policy
authoritative, reapplies it after runtime overrides, validates the current
schema fail closed, keeps reloads transactional, deep-merges target-owned
nested settings, and rejects persistence through managed read-only entries.
It also bounds retry-timer arithmetic and defaults the managed-settings
environment only when a real file or symlink exists. Signed commit `e3b191c4`
repairs and bounds the existing full-turn synthetic provider, MCP, RLM
lifecycle, and daemon coverage, then extends it with exact-socket shutdown,
missing/dangling policy, and managed-package-list probes while retaining the
existing package-collision check.

The exact `e3b191c4` implementation passed:

- the Prime package build with four selected test files and 199/199 tests;
- both `config/ai` and repository-root Prime integration selectors;
- `ai-managed-preflight` and `host-behavior`;
- all seven pre-commit lanes, including 49 fast Python tests; and
- `darwinConfigurations.hera.system` without activation.

Independent partner and fess reviews were GO with no P1-P3 findings. Preserve
the evidence ceiling: this is not the complete upstream suite; the IPython
check proves bridge wiring but does not invoke a kernel; and the RLM check
proves completion, registry retention, and deletion but not child response
content. Build success does not establish activation on Hera or any fleet host.

## #127 current offline source checkpoint

The reviewed ten-Python-file source remains under:

```text
/private/tmp/wg-project9-next/live-kit-r3-src
```

The authoritative offline artifact is now the explicit thirteen-member archive
at
`/private/tmp/wg-project9-next/frozen-r3-v2.zqIyWi/wg-project9-r3.tar.gz`.
It is mode `0600`, 96,845 bytes, single-link, and has SHA-256
`e21886f2cd687964cdb6615ee230e673ca934bb3ad24c26b36e5185d33d9437d`.
The matching record is
`freeze-record-authoritative.json`, SHA-256
`3307737d29e8027c8a1ea1d1c41adfecd5212c378d13e1f51733d93ccff3ff1a`.
Use only the ten explicit Python members and three helpers recorded there. Do
not recursively archive a source directory; the scratch tree also contains
caches, bytecode, and superseded verification material.

| Relative member | SHA-256 |
|---|---|
| `minimal-config-edit/cleanup.py` | `444e0af3327816b990e4dd33792e7a815892fab52cdbcd46c6ffe7438086706f` |
| `minimal-config-edit/editors.py` | `4421e0b32748e7dededc67c604b95b9f9aaf79cab650b5077b03ea7eae4d08e5` |
| `minimal-config-edit/test_cleanup.py` | `7b5b458b5430195c21fa3905579ecc17d9823b0754c805173c77fc2544d4674d` |
| `minimal-whole-move/manifest.py` | `e481cc48e67e7ff2adb9b6a51d6e97a82d6faeb04b9a6efa30f157a33102a406` |
| `minimal-whole-move/whole_move.py` | `b2d0501378a6d42c28cde1e158c680f797d7840646dafe59e579a42f05415d56` |
| `minimal-whole-move/test_whole_move.py` | `19207b0ea27f789314d6d2f44828478757d220800e917c8ba38f496f810fb41b` |
| `minimal-coordinator/coordinate.py` | `fa3e481205dac4558be7cc0bf6b0c10b2a4d40b9c51656389c672bf61e4f7ce4` |
| `minimal-coordinator/test_coordinate.py` | `70cc8a181dc7a2f5c445f82b69c2f490a4505f8877b067ae1dcd740b56202e8f` |
| `final-probes/verify_absence.py` | `76f98ef1b6af625ebc35afcd5539ae160cb27e90cc049d417b7a997eb6dca4dd` |
| `final-probes/test_verify_absence.py` | `2be7a13ae562c2331916d1a17790f2f578c38be1781596df40f9927f5338b225` |

A fresh recheck during preparation of this handoff passed these exact bytes,
normally and with `python -O`:

- 62 config-editor tests in each mode;
- 107 whole-object tests in each mode;
- 15 coordinator tests in each mode; and
- 16 final-verifier tests in each mode.

The total is 400 test executions. The final fresh-extract receipt is
`local-darwin-validation.json`, SHA-256
`859601f6c48e0ea8576e5c69979c40e1d65081f0161f8bd7941a174901af293a`.
An independent reproduction produced the same archive SHA-256. Independent
review at
`/private/tmp/wg-project9-next/reviews/integrated-r3.md`, direct SHA-256
`d929bbe603d7613ba096b7d2504a264518671da32c12dfc88e1b04282339990c`,
is GO for this ten-file source boundary and expressly is not approval for a
live transaction. The scratch-audit report, written after this review file's
recorded mtime, contains a different digest. Direct OpenSSL and `shasum` results
agree on the digest above, so the older value is treated as a transcription
error and must not be copied.

The R3 source corrects four material defects in predecessor kits:

- it accepts the real three-link Home Manager root topology;
- it follows the managed Factory generation-file chain;
- it permits physical-entry deduplication only for the exact canonical/legacy
  Codex config pair; and
- it treats OpenCode selectively, retaining the root and unrelated descendants
  while identifying only exact nested PromptDeploy objects and separately
  manifest-proven stale Anvil payloads.

There is no `--approve-opencode` production mode. Do not reintroduce one.

### Final helper trio

Reviewed source directory:

```text
/private/tmp/wg-project9-next/helpers-r3-v2-bounded
```

| File | Final SHA-256 | State |
|---|---|---|
| `qualify_helpers.sh` | `28f81a40bc81093c622b76c6195541371160f1e8b741a7461bf209f768c4b600` | Frozen and independently reviewed. |
| `qualify_linux.sh` | `56dbc7d5a3f029f91cabe4a9c2bd38bf0afbcb29ae90245d4ef304ac639d5778` | Frozen and hash-binds the other helpers. |
| `receive_qualify_linux.sh` | `6e82d092a104333be1236dc720251e387ac7435efb6c64e866b956f00d6c30c2` | Frozen and independently reviewed. |

The helper trio is a member of the archive above. Do not substitute the older
`helpers-r3-candidate` bytes or update an embedded hash in place.

### Final freeze builder

The interrupted builder is:

```text
/private/tmp/wg-project9-next/freeze-builder-r3/freeze_kit.py
```

Its reviewed SHA-256 is
`f2d1591f64e0cca971c8a226a8ea37c4afef9374e118cd0d414efc6dbc0bc902`;
the test SHA-256 is
`7b60656375f2c93ae563c3bfeb77cff862135593198e160cb21780813f869ef0`.
Four focused tests pass normally and under `python -O`; Ruff check and format
also pass, and independent review is GO. Pyright reports two historical
annotation errors in these reviewed bytes. Pyright was not an accepted builder
gate; do not mutate the frozen builder merely to turn that additional
diagnostic green. The deterministic reproduction archive matches the
authoritative archive SHA-256.

### Draft runbook

The current draft is:

```text
/private/tmp/wg-project9-next/runbook-r3-draft.md
```

SHA-256:
`13675ca020e4dd4a567d802b7e8f287ee9963b6c05531928fcf7806ec6601d4c`.
Its transaction and recovery order are useful, but it contains 57 placeholders
for the archive, hashes, counts, reviews, host receipts, route, preflight
results, and Clio operation. It is explicitly non-executable. Fill it only from
the new frozen archive and fresh receipts; never copy literals from an older
runbook.

Because `/private/tmp` is ephemeral, verify these hashes immediately on resume.
If any differ, stop and repeat the affected review. Preserve the scratch tree
until its work is either integrated or deliberately archived; it also contains
the isolated Codex build evidence.

## #127 host-qualification operator

The remaining pre-live boundary is real-host qualification of the exact frozen
archive. The private operator source is:

```text
/private/tmp/wg-project9-next/qualification-operator-v2
```

Its current exact identities are:

| File | Size | SHA-256 |
|---|---:|---|
| `README.md` | 5,023 | `8b00bb20c9f9e42257808f11ad82275bb645346a6f601a1dd7293643909467d6` |
| `operator_bootstrap.py` | 7,964 | `00ae0eaa6cb1fd9f5623169bb4ff7eb08f76cefc66501ad2c055eb2bb9d851b1` |
| `run_host.py` | 10,264 | `b17fa937d17c39d1d9514a91980dffe89e75d8c1c2320639e7177701f045ce7d` |
| `observe_shared.py` | 12,150 | `3a5ce7bea16eaa59c3fc89e10b7e2922826139799dda0d4c865c0337cb33cf09` |
| `qualify_archive.py` | 76,780 | `ba4b8d8b5732e05bf32766978acbe4dbda3a5bcc68d43984007097e21805c68a` |
| `wg-project9-r3.tar.gz` | 96,845 | `e21886f2cd687964cdb6615ee230e673ca934bb3ad24c26b36e5185d33d9437d` |

The validation test at
`/private/tmp/wg-project9-next/qualification-operator-v2-validation/test_operator_bundle.py`
has SHA-256
`8ea3cc03ef35ddca6bdc06b3a52d52dbfe5fc7b04584add3e05903c573daf59d`.
Its 19 tests pass normally and under `python -O`; Ruff check/format, Pyright,
shell syntax, ShellCheck, and captured-bootstrap hash verification pass.

The operator qualifies all eight views serially and produces eight
qualification receipts. For each shared-NFS source it then observes the exact
residue paths from each of the other three shared views, producing twelve
cross-view receipts. Entry points execute from retained, hash-verified file
descriptors; qualification receipts use exclusive creation and are streamed
back from that same descriptor; every shared observation proves its current
view is NFS both before and after absence checks. The first fess audit correctly
returned NO-GO on the pre-repair bootstrap, receipt, and NFS-proof design. The
second audit is GO for the exact repaired hashes and found no new defect; it is
not live host evidence.

Do not run this block as an agent, through `sudo`, or in parallel. John must run
the reviewed operator sheet from one ordinary Hera shell. Stop on any
unreachable host, hash or shape mismatch, wrong test/skip vector, non-NFS
shared view, missing receipt, or residue. Preserve all inbound bundles and
receipts. The exact operator received independent fess GO in
`/private/tmp/wg-project9-resume/audit/operator-bundle-fess-v2.md`, SHA-256
`399dffdb441b2cff00a58764f6625e38bc06988f453e176aa13f6cf81bdb2d8d`.
Only after all twenty receipts pass review may the runbook's 57
placeholders be filled and independently reviewed. Host qualification is not
live reconciliation authority.

## Old archives and evidence

Every existing Project 9 archive is superseded and evidence-only. Preserve it;
do not execute, extend, mix, overwrite, or delete it without separate approval.

| Archive in `~/dl` | SHA-256 | Members | Reason it is not executable |
|---|---|---:|---|
| `wg-project9-promptdeploy-r6-qualified-20260805.tar.gz` | `b9ee0f0a7c167a67dbe5eb64dc252dd05f74e7d7034e8785a6d8348235e4d8a6` | 61 | Rejected broad/privileged attestor design. |
| `wg-project9-minimal-reconcile-qualified-20260805.tar.gz` | `f6bc9a09357ad91f14eb7dc8913dbf96bd2532d6c53f3902b895af0c6fb53304` | 11 | Lacks final probes; old alias and OpenCode semantics. |
| `wg-project9-live-kit-20260805.tar.gz` | `f108e84f9bb9991a43d7eadf845daca399ea67d91a8ff9646d257d82f293cd75` | 13 | Predecessor alias and OpenCode semantics. |
| `wg-project9-live-kit-20260805-r2.tar.gz` | `5ab08f29d9163fb44e530e81a49bb67b7a2266d6bcc1bd853ea31d525da4a940` | 13 | Interim alias candidate. |
| `wg-project9-live-kit-20260805-r3.tar.gz` | `840e15cb3b5167212019297422295b5b20d12317baf9c6c306134b6d397434e4` | 13 | Still predates current alias-r2 and selective OpenCode handling. |

The historical `/private/tmp/wg-project9` tree explains the evolution from
broader privileged designs to the bounded ordinary-user transaction. It is
provenance, not an executable input. In particular, privileged hidden-metadata
attestation is neither required by the open issues nor sufficient for the
shared NFS home. Do not revive that lane.

## Host ownership and activation matrix

| Host/view | Authoritative source and activation | Mutable transaction role |
|---|---|---|
| Hera | `~/src/nix`; `make switch` | First write authority; unique APFS home. |
| Clio | `~/src/nix`; fast-forward, then `make switch` | Second write authority; unique APFS home; exact one-link prerequisite. |
| Vulcan | `/etc/nixos`; local `./build build`, then `./build` | Third write authority; unique ext4 home. Never bypass its build lock. |
| VPS | `/etc/nixos`; local `./build build`, then `./build` | Fourth write authority; unique ext4 home. Never bypass its build lock. |
| andoria-08 | Shared `~/.config/home-manager`; coordinated rollout | Sole write authority for the shared NFS home; fifth and final write. |
| andoria-t2 | Same shared source and generation | Read-only transaction view. |
| delphi-3bd4 | Same shared source and generation | Read-only transaction view. |
| gpu-server | Same shared source and generation | Read-only transaction view. |

The shared work home is one physical mutable surface. Prepare and mutate it
exactly once through andoria-08, then verify it independently from all four
views. Qualification is nevertheless required on every view because one mount
view does not prove another's availability or semantics. A shared-work rollout
must realize the candidate once, keep both candidate and previous closures
resident on all four hosts, retain the previous closure as the rollback/GC
root, and activate all four coherently.

The most recent user report says direct `ssh vps` from Hera works, but the final
runbook must refresh and freeze that route. Likewise, past statements that
Clio was reachable or andoria-t2 was down are historical. Reachability is a
live precondition, not a property of this document.

Publishing the root repository does not deploy an external consumer. Vulcan,
VPS, and shared-work consumers must pin the root input and `dir=config/ai`
input to the same revision and update them together from their own authoritative
checkouts. Never overwrite an authoritative checkout from a secondary clone.

## Clio's exact prerequisite

The metadata-only diagnosis on Clio found this bounded condition:

- `~/.factory` is the intended managed alias to `~/.config/factory` and follows
  the current Home Manager chain.
- `~/.config/factory/mcp.json` is a user-owned dangling symlink into an absent
  old Hera Home Manager output.
- The same retired output explains 55 other dangling Factory links, but the
  tree also contains mutable state, regular files, and unrelated valid plugin
  links.

The #127 prerequisite is therefore an archival rename of exactly the one
`mcp.json` symlink, not a Factory cleanup:

1. Freshly validate its UID, owner, type, exact retired root and same-relative
   target, target absence, and object identity without printing the target.
2. Revalidate the live `.factory` alias and current Home Manager chain.
3. Under the continuous-quiescence and single-runner gates, exclusively create
   a private mode-`0700` run directory and rename only that symlink to its exact
   recorded recovery name.
4. Prove the live name is absent, the archived symlink retains its original
   identity, and `.factory` remains valid.
5. Restore that exact symlink on any subsequent failure and verify its original
   identity. Retain it after success until separate deletion approval.

Do not touch the other 55 dangling links, any parent directory, settings,
plugins, regular files, or mutable Factory state. A helper refusal caused by the
current dangling link is correct; do not weaken the helper to make Clio pass.

## Historical mutable-state baseline

The last sanitized structural survey found the following classes. This is a
map of what the next session may encounter, not permission to mutate them and
not a substitute for fresh preflight:

- Hera had one Claude `skillUsage.anvil` entry. Its Pi cache also retained Ref
  and Perplexity service entries.
- Clio's PromptDeploy manifest named retired skills whose payload was absent;
  three distinct project-scoped Ref entries remained in personal Claude state.
- Vulcan had one Codex Anvil table and one manifest-owned Factory payload.
- VPS had two Claude Anvil entries, one Codex Anvil table, and three
  manifest-owned payloads. Its unrelated `sequential-thinking` entry must
  remain.
- The shared NFS home had two Claude Anvil entries and three manifest-owned
  payloads.

The old five-home matrices, ordered Hera/Clio/Vulcan/VPS/shared, were 10/10/4/6/7
PromptDeploy artifacts, 2/1/1/3/2 mutable configs, and 0/0/1/3/3
manifest-owned Anvil payloads. The last known payload authority was therefore
one on Vulcan, three on VPS, and three on shared NFS. A difference is not an
invitation to adjust the runbook: it stops the operation and requires renewed
classification and authority.

No service-specific mutable member was reported elsewhere in that survey.
Generic uses of the words `ref` and `perplexity`, unrelated MCP servers, and
user-managed credentials are outside the deletion set.

## Fresh authority required for the live transaction

All of these gates are conjunctive and must remain true from the first live
preflight through accepted postflight or verified recovery:

1. **Frozen kit:** one reviewed thirteen-member archive, one completed runbook,
   and matching qualification receipts for all eight views under both umasks.
2. **Reachability:** all eight hosts/views remain reachable through frozen,
   authorized routes.
3. **Visible-metadata acceptance:** John explicitly accepts preservation of
   bytes, type and symlink target, ownership, mode, mtime, user-visible ACLs,
   xattrs and flags, plus original-inode recovery. The operation does not claim
   to preserve atime, ctime, birth time, parent timestamps, allocation layout,
   root-only invisible metadata, or transient link-count topology.
4. **Exact Anvil-payload authority:** freshly prove and obtain permission for
   exactly one manifest-owned stale payload on Vulcan, three on VPS, and three
   in the shared home. Any count, path class, type, ownership, or staleness
   mismatch stops the operation.
5. **Exact Clio-link authority:** obtain fresh permission for only the one-link
   operation above.
6. **Continuous quiescence:** every Claude, Codex, Pi, Factory/Droid, and
   OpenCode client on all eight hosts is inactive for the whole interval. Do
   not infer this from old session names, Agent Deck absence, or an earlier
   snapshot. Do not stop, kill, restart, attach to, or otherwise disturb a user
   session to manufacture the window.
7. **One ordinary-shell runner:** exactly one non-agent shell executes the
   transaction. No agent client may be the runner. No second coordinator,
   activation, PromptDeploy process, or mutable-state writer may overlap it.
8. **Fresh structural matrix:** freeze value-free `C` config counts, `W`
   whole-object counts, and preflight JSON for all eight views. Historical
   `10/10/4/6/7`, `2/1/1/3/2`, and `0/0/1/3/3` matrices are not authority.
9. **Private staging:** use new private paths, one new valid run ID, exact
   archive verification, qualified interpreters, and collision refusal on all
   five write authorities.
10. **No expansion:** no privileged attestor, filer or snapshot access,
    password-store or credential mutation, PromptDeploy invocation, history
    rewrite, force push, backup deletion, broad Factory cleanup, or unrelated
    state movement.

No live configuration, retired payload, user secret, or session was changed by
the halted work. The live operation remains entirely pending.

## Fixed transaction and recovery order

The write order is Hera, Clio, Vulcan, VPS, then the shared home through
andoria-08. Never overlap writes or mutate the shared home through another view.

1. Reconfirm every owner gate immediately before the window.
2. Archive the one authorized Clio dangling symlink.
3. Run value-free absence preflight on all eight views and require the frozen
   matrix; all four shared views must describe the same physical state.
4. Run `prepare` and `status` on all five write authorities before applying any
   authority.
5. Run `apply` and `status` serially in the fixed order.
6. Require fully applied state with zero `other` and `ambiguous` objects.
7. Run postflight on all eight views. Require the frozen nonzero
   `configs_present=C`, zero PromptDeploy objects, and zero retired members.
8. Prove unrelated state unchanged, especially the OpenCode root and unrelated
   descendants and VPS `sequential-thinking`.
9. Reconfirm continuous quiescence.

Any refusal, unexpected exit/count/JSON, host loss, quiescence breach, or
preservation failure ends forward progress. Recover every prepared authority in
exact reverse order: shared home through andoria-08, VPS, Vulcan, Clio, Hera.
Restore the archived Clio link last, or first if no home was prepared. Do not
retry `apply`, improvise a manual edit, release quiescence, or activate anything
while recovery is incomplete. Retain all checkpoints and recovery archives.

## Closing #116, #124, and #127

The mutable transaction alone closes no issue. After a successful transaction
and with separate activation authority:

1. Run two complete activation cycles on every host through the authoritative
   source and host-specific driver above.
2. Use only fresh disposable clients. Never restart an existing session.
3. After each cycle, run sanitized structural probes on all eight views.
4. Prove Anvil, Ref, Perplexity, and PromptDeploy state is absent and not
   recreated. Prove unrelated MCP, OpenCode, Factory, prompt, command, skill,
   agent, and user-owned state remains.
5. Record host identity, exact system generation and closure, and exact Home
   Manager generation and closure for every result.
6. Publish the supported rollback allowlist as host plus generation IDs and
   closures. Older retained generations remain forensic rollback material, not
   supported generations, unless independently proved.
7. Run an independent issue-closeout review. Close #127 first, then #116, then
   #124, with distinct acceptance evidence for each.

Password-store entries are user-managed and out of scope. Do not inspect,
copy, print, provision, rotate, or delete them.

## Codex wrapper correction checkpoint

Published commit `ea0327cf` contains the isolated design's tracked Nix
integration.
`flake/ai/wrappers/codex.nix` is 267 lines rather than 819 and no longer owns a
copy of Codex's CLI grammar. The tracked upstream patch asks the Clap graph for
one of four policy tokens before Codex initialization:

```text
manage
delegate
conflict-profile
conflict-ignore-user-config
```

The private protocol is consistently
`CODEX_INTERNAL_WRAPPER_POLICY_PROBE=v1`. The wrapper fails closed on nonzero,
empty, unknown, multiline, non-newline-terminated, or NUL-bearing responses and
unsets the private variable on ordinary execution. HUP, INT, and TERM terminate
with status 129, 130, and 143 while `EXIT` cleanup removes the private response
file. Packaging and runtime tests share the exact byte-response checker. The
test candidate includes raw-versus-wrapped malformed-input, root/exec help, and
root/exec version differentials while retaining state, profile, security, PID,
exit-code, descriptor, malformed-response, and interrupted-probe coverage.

Signed commit `ea0327cf` is the rebased source identity for this correction. The
final-byte `aarch64-darwin.agent-wrappers` derivation passed its packaging
handshake plus Claude, Codex, and bridge contracts. Independent Rust review of
the current patch is GO after zero-fuzz application, formatting,
warnings-as-errors Clippy, and five focused tests; its report is
`/private/tmp/wg-project9-resume/audit/codex-probe-rust-review-v2.md`, SHA-256
`3e7aa7b5c827a653996efe4ecfe854f03a48bc8d9c23136db5c6a9360bc03520`.
Independent Bash review is PASS with no remaining scoped finding; its report is
`/private/tmp/wg-project9-resume/audit/codex-wrapper-bash-review-v2.md`, SHA-256
`4a8d0a0e42ca813fa99d9cd2261a85f04bd718c1e4b7c623562ffa5b2a6fffc6`.
The final independent fess audit is GO for this exact Darwin/offline boundary;
its report is
`/private/tmp/wg-project9-resume/audit/codex-wrapper-fess-v2.md`, SHA-256
`3c840b50627caf8add34ffa6e07597c3711886762b4b8231c82b535b7eb0226f`.
It does not close the Linux capability or activation gates. Portable Assurance
is green at later evidence checkpoint `686a7334`, but it is not the future
unchanged-final-candidate #121 run and does not execute the Linux wrapper lane.

The `x86_64-linux.agent-wrappers` check did not reach wrapper execution. The
configured native `root@nix-builder` SSH master was unavailable; the fallback
emulated builder then crashed Node/V8 under QEMU while generating `pnpm`
completions. Treat that lane as capability-blocked, not passed or code-failed.
The bounded pre-commit tier now passes formatting, Nix lint, dead-code, shell,
and all five Python-test lanes. The earlier
`config/ai/renderers/pi.nix:79` assignment-style warning was corrected with
`inherit` before the series was committed.

The correction is committed and published but has not been established as
active on the fleet. It must remain part of the unchanged candidate tested by
#121. Comments `5217376659` and `5217377344` now reconcile the #111 closeout and
carry this evidence ceiling forward.

## #121 unchanged-candidate closeout

Begin this phase only after the reconciliation, two-cycle fleet proof, #128,
and the Codex wrapper correction are complete.

1. Derive a final requirement/evidence matrix from #98, #121, every retained
   child issue, and the governing plan. Closed status is not evidence.
2. Derive the final retained-file/comment denominator from `git ls-files`.
   Re-audit additions and changes since #104, verify every local Markdown link,
   and correct or delete every stale or unverifiable claim.
3. Ensure `README.md`, `ARCHITECTURE.md`, `bin/README.md`, `test/README.md`, the
   Pi extension guide, and operator commands match the final tree and behavior.
4. Delete `doc/CLEANUP-PLAN.md` and this handoff, rewrite
   `doc/CURRENT-WORK.md` for the next programme, and repair inbound links in the
   same commit. Git is the archive.
5. Produce the actual before/after LOC and dependency report separated into
   code, tests, data, and prose. The current raw baseline-to-HEAD estimate is
   net minus 24,258 text lines; recalculate and categorize it at the final
   commit rather than copying that estimate.
6. On one unchanged source candidate, run exactly once:

   - the mandatory fast gate with elapsed time, at most 120 seconds;
   - the full Python tier;
   - affected native AI and consumer checks accumulated by issue closeouts;
   - portable all-system evaluation;
   - the required Darwin/native system build without activation;
   - one independent full-range review; and
   - one final fess audit.

7. With separate publication authority, publish the signed candidate. Require
   normal CI and scheduled Portable Assurance green on that same commit.
8. Network-read both remote tips; verify the entire cleanup range is signed;
   require a clean tree, one worktree, one local branch, truthful issue
   relationships and statuses, and no cleanup blocker.
9. Close #121, then #98. Do not declare success merely because source searches
   are clean.

## Safe first actions for the next session

Start with read-only ownership and drift checks:

```sh
cd /Users/johnw/src/nix
pwd
git status --short --branch
git worktree list --porcelain
git for-each-ref --format='%(refname:short) %(objectname)' refs/heads
git log -1 --show-signature --format=fuller HEAD
git ls-remote origin refs/heads/main
git ls-remote github refs/heads/main
```

On this machine, GitHub SSH is expected to use the local GPG agent socket:

```sh
SSH_AUTH_SOCK=/Users/johnw/.config/gnupg/S.gpg-agent.ssh \
  ssh -T git@github.com
```

GitHub's successful "no shell access" response is expected. Do not treat its
PTY warning as authentication failure. Do not run or paste `git remote -v` in a
shared transcript; use remote names and `git ls-remote` without displaying
configured URLs.

Before #127 host qualification, hash-check the authoritative freeze record,
archive, operator sheet, bootstrap, host runner, observer, and launcher against
the digests recorded above. Reread these files as current authority:

```text
/private/tmp/wg-project9-next/frozen-r3-v2.zqIyWi/freeze-record-authoritative.json
/private/tmp/wg-project9-next/qualification-operator-v2/README.md
/private/tmp/wg-project9-next/runbook-r3-draft.md
```

The older packaging report is architecture-only and contains obsolete scope and
test literals; it is not current authority. Before wrapper work, refresh the
five current in-tree artifact hashes listed above rather than the old isolated
prototype.
Before reusing #128's final process result, require private manifest SHA-256
`c30f01808c30701d3d66195c72ee7e821d934c4ca00f615cefd7ab0f75cc3aca`
and revalidate its final envelope, final object, cloned JSONL/index, validator
output, lineage receipt, and two path-adjudication reports. Preserve the
incomplete verdict. Use a separately reviewed corrected protocol for the rerun;
do not normalize the old final object or relabel it accepted.
Before any GitHub mutation, refresh #98, #111, #116, #121, #124, #127, and
Project 9 through the explicit account. Before any host operation, refresh
reachability, routes, authoritative checkout revision, paired consumer inputs,
active generations/closures, filesystem and UID, current client state, and
transaction counts.

## Non-goals and prohibitions

- Do not execute any old archive or placeholder-bearing runbook.
- Do not mix reviewed source with helpers or receipts from another version.
- Do not run PromptDeploy as a reconciliation tool.
- Do not print config values, credentials, environment values, command
  arguments, symlink targets, transaction payloads, or session transcripts.
- Do not inspect or mutate password-store entries.
- Do not delete the separate PromptDeploy source repository or Git history.
- Do not stop, restart, kill, or attach to user sessions.
- Do not make an agent client the live transaction runner.
- Do not bypass Vulcan's or VPS's local `./build` lock driver.
- Do not use evaluation or build success as activation proof.
- Do not use one shared-NFS view as proof for all four.
- Do not delete backups, old archives, checkpoints, ignored agent material,
  recovery refs, or scratch evidence without explicit authority.
- Do not turn unrelated observations in `doc/SECURITY.md` or `bin/README.md`
  into cleanup scope unless an accepted issue requires them.
- Do not add a framework or dependency merely to organize the cleanup.
- Do not regenerate evidence on every commit. Run expensive evidence once per
  issue-ready unchanged candidate and once at final closeout.

## Stop conditions

Stop without mutation when any of the following is true:

- a reviewed source, helper, patch, or archive hash differs;
- archive member order, type, mode, count, or test vector differs;
- a required host/view is unavailable or a route is uncertain;
- Clio's exact dangling-link identity or target shape differs;
- a mutable config, payload count, type, ownership, or staleness result differs;
- a relevant client is active or more than one runner exists;
- a probe could reveal a secret or configuration value;
- recovery cannot be completed and verified on every prepared home;
- a source edit would be needed after final evidence has begun;
- the fast gate exceeds 120 seconds twice for the same cause; or
- push, activation, session restart, destructive cleanup, consumer mutation, or
  another separately authorized action becomes necessary.

Report the exact boundary rather than softening it into success.

## Completion checklist

- [x] Refresh repository, remotes, signatures, Project 9, and issue truth.
- [x] Revalidate the ten R3 Python members and 400-test vector.
- [x] Finish, test, review, and hash-bind the three qualification helpers.
- [x] Fix and review the freeze builder.
- [x] Create and independently review one new exact thirteen-member archive.
- [ ] Qualify that archive on all eight host views under umasks `077` and `027`.
- [ ] Complete and review the placeholder-free runbook.
- [ ] Obtain all fresh live owner gates and one ordinary-shell runner.
- [ ] Perform the Clio one-link prerequisite and bounded transaction, or recover
      the complete fleet unit on any failure.
- [ ] Perform two authorized activation/fresh-client/probe cycles on all hosts.
- [ ] Close #127, then #116, then #124 with distinct evidence.
- [x] Integrate the upstream Codex policy probe and delete duplicate wrapper
      grammar in a signed commit.
- [x] Publish the Codex correction to both remotes.
- [x] Reconcile the misleading #111 closure.
- [x] Preserve and independently adjudicate the first completed eight-hour
      #128 run as evidence-incomplete after its sealed retained-path predicate
      failed.
- [ ] Run and accept the corrected, independently reviewed eight-hour #128
      protocol on one exact launch lineage.
- [ ] Complete and close #128's bounded-memory Pi-session work.
- [ ] Run #121 once on an unchanged candidate, remove cleanup documents, and
      publish only with separate authority.
- [ ] Require same-commit CI and Portable Assurance, reconcile Git and Project
      state, close #121, and close #98 last.
- [ ] Keep deferred #130 explicit on the Project until its separate PAL
      dependency and completion authority are available; do not count it Done.

Until every box is satisfied, the cleanup programme remains in progress.
