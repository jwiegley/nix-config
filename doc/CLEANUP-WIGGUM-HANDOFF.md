# Cleanup Wiggum Handoff

Updated: 2026-08-04

## Objective

Complete cleanup epic `jwiegley/nix-config#98` under the accepted Definition of
Done in [`CLEANUP-PLAN.md`](CLEANUP-PLAN.md).

## Authoritative state

- The authoritative checkout is `/Users/johnw/src/nix`, on `main`. It is the
  only worktree.
- The last fully activated fleet boundary is `e7dc846c`. GitHub and Gitea
  published that exact revision; Hera, Clio, Vulcan, VPS, and the shared-work
  profile evaluated to their active closure at the completed #126 cutover.
- Published candidate `c7d48838` restores Pi profile contracts and refreshes
  the Pi inventory. The current source-only follow-up replaces Copy Message's
  platform-specific clipboard subprocesses with Pi's portable clipboard API;
  it also corrects the inventory's agent totals and platform-specific
  verification recipe. Do not treat the clipboard repair as live until
  publication and activation receipts are recorded.
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
- #116 and #124 are In Progress. #117 is closed not-planned, superseded by
  #124. #118-#120 and #122-#126 are Done.
- #121 remains the final unchanged-candidate verification and cleanup closeout;
  it stays blocked on #116 and #124.

## Comment-audit boundary

The #104 closeout covered 176 retained files, 133 comment-bearing files, 921
entries, and 2,032 comment lines. The primary ledger audited 919 entries; a
two-entry supplement covered the five Pi paths after their owner boundary cleared.
All entries were valid. Generated locks/JSON, patches, keys/certificates,
proven-vendored files, and files later removed under C10 were explicit
exclusions at that boundary. Final closeout must cover retained additions made
after the audit rather than pretending the old denominator is current.

## Mutable-state holds

- #116: source and current-state probes are clean across the reachable fleet;
  the retained `anvil` string in the Pi gallery test is a negative prohibition,
  not a producer. The remaining gate is the required two-cycle runtime horizon
  after the convergence machinery was retired. Do not close the issue from a
  source grep or one clean probe.
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
  service. A proposed activation-time JSON writer was rejected before commit:
  without a lock shared by the clients it could overwrite concurrent updates or
  discard the manifest evidence needed for declarative removal.
  Fleet probes now establish that Ref is absent everywhere. Perplexity remains
  only in Hera's Pi cache and the mutable Claude configurations on Vulcan and
  VPS; preserve VPS's unrelated `context7` and `sequential-thinking` entries.
  Clio is clean. Reconciliation remains a manual quiescent-window operation;
  never infer session quiescence from this handoff's old session names.
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

- Copy Message is restored in signed commit `b21590fd`, included in the gallery
  on every Pi profile, and registered on all seven reachable hosts. That probe
  exposed a real headless-Linux failure in upstream's private clipboard-command
  list; the current source candidate delegates to Pi's OSC-52-capable portable
  clipboard helper and adds handler-level success and failure tests.
  `andoria-t2` was down, so shared-profile evaluation covers its source
  projection but not a direct runtime probe.

## Concurrent work boundary

The Copy Message restoration and Pi fleet-contract repair are published as a
signed logical series through `c7d48838`; the portable-clipboard and inventory
follow-up is the only current source candidate. Continue to refresh checkout
ownership before every shared-file edit and do not infer live activation from
source state.

## Authorization boundary

Authorized: accepted decisions D1-D7, local cleanup edits, signed commits, normal
dual-remote publication, cleanup-bearing lock updates/activations, and fresh
disposable Codex/Pi processes. Existing sessions must remain untouched.

Mutable #124 reconciliation still requires a freshly confirmed quiescent window;
the #116 runtime horizon does not authorize stopping sessions. Not implicitly
authorized: password-store mutation, history rewriting, force pushes, or
moving/deleting other user backups/state. Every `gh` invocation must explicitly
select account `jwiegley`.
