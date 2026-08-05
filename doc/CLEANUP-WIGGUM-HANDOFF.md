# Cleanup Wiggum Handoff

Updated: 2026-08-05

## Objective

Complete cleanup epic `jwiegley/nix-config#98` under the accepted Definition of
Done in [`CLEANUP-PLAN.md`](CLEANUP-PLAN.md).

## Authoritative state

- The authoritative checkout is `/Users/johnw/src/nix`, on `main`, and it is the
  only worktree. The worktree is clean. Signed local `80e194fc` is one commit
  ahead of both GitHub and Gitea at `9c5cd2a9`; it makes Hermes credential
  lookup ignore a stale inherited `GPG_TTY`, but it is not yet published or
  activated. The last complete fleet activation proof remains the #126 boundary
  at `e7dc846c`; later commits must not be described as fleet-active without host
  receipts.
- Signed `bf873fdf` replaces Copy Message's platform-specific clipboard
  subprocesses with Pi's portable clipboard API. The subsequent Pi provider,
  extension, catalog-refresh, and Hermes credential fixes are published through
  `b058721d`. Hera generation 1000 passed a fresh clean-environment
  `hermes/hermes-agent` request; this is not all-host activation evidence.
- Codex defaults to native OpenAI `gpt-5.6-sol`; local oMLX and llama-swap
  profiles remain opt-in.
- Pi advertises `openai-codex/gpt-5.6-sol` at 1,050,000 tokens and OpenRouter
  GLM at 1,048,576. Darwin additionally exposes the opt-in local DeepSeek and
  GLM routes at 262,144; Linux does not advertise unprovisioned loopback routes.
- oMLX and llama-swap are loopback-only. Re-probe live service health when it is
  material rather than treating this handoff as a health monitor.
- Do not stop, restart, or kill user sessions for cleanup.

## Project state

- Epic #98 remains In Progress.
- Done: #99-#108 and #110-#115, including #104's complete comment audit.
- #109 was closed as not planned after its compliant prototype added far more
  policy and test code than the renderer literals it removed.
- #116, #124, and #127 are In Progress. #117 is closed not-planned,
  superseded by #124. #118-#120 and #122-#126 are Done.
- #121 remains the final unchanged-candidate verification and cleanup closeout;
  it stays blocked on #116, #124, and #127. Together with epic #98, these are
  the only five non-Done Project 9 items as of the latest explicit-`jwiegley`
  account readback.

## Comment-audit boundary

The #104 closeout covered 176 retained files, 133 comment-bearing files, 921
entries, and 2,032 comment lines. The primary ledger audited 919 entries; a
two-entry supplement covered the five Pi paths after their owner boundary cleared.
All entries were valid. Generated locks/JSON, patches, keys/certificates,
proven-vendored files, and files later removed under C10 were explicit
exclusions at that boundary. Final closeout must cover retained additions made
after the audit rather than pretending the old denominator is current.

## Mutable-state holds

- #116: source producers are retired, but a newer eight-host structural probe
  found mutable Anvil residue: Hera has one Claude `skillUsage.anvil`; Vulcan
  has one Codex table and one manifest-owned Factory payload; VPS has two
  Claude entries, one Codex table, and three owned payloads; the shared NFS home
  has two Claude entries and three owned payloads. Clio's manifest names retired
  skills but its payload is absent. After reconciliation, two complete
  activation/fresh-client/structural-probe cycles and exact supported-generation
  IDs remain mandatory.
- #117 is superseded. #124 removes Ref, Perplexity, the legacy importer, and the
  temporary credential carrier. PromptDeploy source retirement is published at
  `4ee0401`; no shared password-store provisioning or mutation is needed. Exact
  manifest reconciliation must wait for a user-approved quiescent client window
  because those clients do not share a mutation lock.
- #118 is complete: published `8c3d4431` removed the one-shot migration; Hera
  generation 991 passed post-retirement path/session/fresh-Pi proof.
- #119 is complete. Hera, Clio, and all four shared-work hosts passed fresh
  Codex and steady-state log probes. Published commit `302e8de8` removes the
  old-directory migration after focused checks, fast gate, native build, and
  independent audit.
- #120 is complete: published `b5d31874` removed the stale-label guard; Hera 991
  and Clio 247 passed post-retirement old-label absence proof.
- #122 is complete. Published `f9be4d23` removes OpenCode package/cask
  selection, four profiles, renderer, preflight ownership, selectors, and
  OpenCode-only model default/schema plumbing. Focused catalog/preflight checks,
  generated-leaf and
  package absence probes, fast gate, a native system build, refreshed baselines,
  and independent audit pass. PromptDeploy `5dd6b34`/`d166509`/`6614a46`
  remove its target adapter, seven targets, model/MCP mappings, and Ponytail
  runtime with 2,782 tests and full coverage passing. Without reading contents,
  the inactive Hera, Vulcan, and shared-work `~/.config/opencode` directories
  were moved by same-filesystem rename to
  `~/dl/promptdeploy-retired-opencode-20260804`. The post-removal candidate is
  active on every reachable maintained host; `andoria-t2` shares the evaluated
  work profile but was down for the final direct probe.
- #124: signed `1ad23d7c` removes both live catalog entries, renderer
  credentials, the legacy Ref importer, the password-store carrier, and the
  Perplexity-bound web-searcher content. PromptDeploy no longer produces either
  service. The newest exact structural probe found Hera Pi cache entries for
  `Ref` and `perplexity`, plus three distinct project-scoped Ref entries in
  Clio's personal Claude state. No other live Ref/Perplexity member was found.
  Preserve every unrelated entry, including VPS `sequential-thinking`.
  Reconciliation remains a manual quiescent-window operation; never infer
  session quiescence from old session names.
- #127: the five unique homes currently contain 10/10/4/6/7 PromptDeploy
  artifacts (Hera/Clio/Vulcan/VPS/shared), 2/1/1/3/2 mutable configs, and
  0/0/1/3/3 manifest-owned Anvil payloads. Exact transaction R6 is frozen below
  `/private/tmp/wg-project9` at production/test/driver/C/C-test/contract hashes
  `14689fdf`, `8cd870a2`, `9c879024`, `2fcaafd4`, `bcc38188`, and `daad050c`.
  Its warning-strict Darwin run passed all 77 methods with the seven expected
  Linux-only skips. Vulcan and VPS independently passed all 67 transaction and
  all 10 C-attestor methods with zero skips, failures, or errors; each real ext4
  probe issued exactly `0x00080040` to set NODUMP and `0x00080000` to clear it
  while preserving EXTENT and exact metadata equality. Hardened C compilation,
  silent empty-input refusal, source-only test-driver exclusion, stable hashes,
  and exact scratch cleanup passed on both hosts. Fresh independent correctness
  and security reviews are GO only for the next separately authorized controlled
  privileged qualification. That matrix must begin with an out-of-band root
  watchdog proving bounded timeout/interruption cleanup and zero surviving
  sudo/helper descendants, then cover exact sudo policy, hidden `trusted.*`
  refusal, namespace/LSM and mount assumptions, protected-descriptor syscall
  traces, receipt/drift cases, and end-to-end recovery. No production package or
  closure exists for this one-off candidate, no privileged invocation or live
  mutation occurred, and source-tree exclusion is not closure proof. Shared-NFS
  apply remains refused. Private recovery archive
  `~/dl/wg-project9-promptdeploy-r6-qualified-20260805.tar.gz` is mode 0600 with
  SHA-256 `b9ee0f0a7c167a67dbe5eb64dc252dd05f74e7d7034e8785a6d8348235e4d8a6`;
  retain it until #127 closes, then remove it only with explicit approval. A
  sanitized mount-source observation suggests a server-local snapshot or
  transaction may be a backend-exact alternative, but no access, filesystem,
  snapshot, or mutation authority has been established.
- #123 is complete. Published `llm-setup` commit `0e8966b` removes the Nix
  registry writer from reset. Signed Nix `eb0da1d4` deletes the three
  registry/policy files and 1,027 lines overall; `f6c4d705` records the exact
  baseline deltas. Pi now
  discovers local models at startup, Codex keeps native OpenAI as its default,
  and Droid intentionally receives no Nix-generated `customModels`. Focused
  catalog/preflight/wrapper/Pi checks, the 22-second fast gate, generated-leaf
  probes, and a native Hera system build pass. Runtime acceptance completed on
  Hera without restarting an existing agent session.
- #125 is complete. Signed `f2bc2dbb` makes the existing
  `isDarwinWorkstation` capability the sole host-eligibility gate for Emacs,
  password-store, GnuPG/OpenPGP, desktop email/signing, and pass helpers.
  `852bbc94` reduces its named-host proof to a
  compact direct contract; `5d4d2c06` records only the 16 intended Linux
  package removals; `1b2539cf` also gates Pinentry and restores broad runtime
  reference checks without duplicating host policy. Hera and Clio value surfaces
  are otherwise byte-identical, both Darwin systems build, and the focused check
  passes on Darwin, ARM Linux,
  and x86 Linux. Reachable-host runtime acceptance is complete; no mutable
  password, key, Emacs, mail, or credential data was read or changed.
- #126 is complete. Signed `8120b84a` atomically moves all 182 tracked
  portable-tree files to `config/ai/` and updates every live source, lock,
  updater, check, CI, and current-documentation reference. `config/ai.nix`
  remains the distinct Home
  Manager integration module. `2eb23dbf` records the reverse command migration
  with zero package deltas and an otherwise byte-identical Darwin surface.
  Root/portable all-system evaluation plus 26 gate and 95 updater workflow tests
  pass. At `e7dc846c`, Vulcan, VPS, and shared-work pair the root and
  `dir=config/ai` inputs at the same revision and evaluate to their active
  closure; Hera and Clio likewise evaluate to their active system closure.

- Copy Message is restored in signed `b21590fd`, and the portable clipboard
  correction is published in `bf873fdf`. The older direct probe covered seven
  reachable hosts while `andoria-t2` was down; do not convert that historical
  result into a claim that every later source revision is active everywhere.

## Concurrent work boundary

There is no uncommitted source candidate. Frozen transaction R6 and its native
qualification/review evidence live only below `/private/tmp/wg-project9`; they
are not repository code and have not touched a live home. Continue to refresh
checkout ownership before every shared-file edit and do not infer live
activation from source state.

## Authorization boundary

Authorized: accepted decisions D1-D7, local cleanup edits, signed commits, normal
dual-remote publication, cleanup-bearing lock updates/activations, and fresh
disposable Codex/Pi processes. Existing sessions must remain untouched.

The combined #116/#124/#127 reconciliation requires a freshly confirmed window
in which every Claude, Codex, Pi, Factory/Droid, and OpenCode client is quiescent
on Hera, Clio, Vulcan, VPS, and all four shared-work hosts for the complete
preflight, prepare, apply, verification, and possible recovery interval. It also
requires separate current confirmation that each manifest-claimed Anvil payload
on Vulcan, VPS, and the shared home is owned stale state that may be archived.
Never infer either fact from old session names, and do not stop a session to make
it true. The #116 runtime horizon does not authorize stopping sessions. Not
implicitly authorized: privileged Linux attestor invocation, filer access or
snapshot/mutation, password-store mutation, history rewriting, force pushes, or
moving/deleting other user backups/state. Every `gh` invocation must explicitly
select account `jwiegley`.
