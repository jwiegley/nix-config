# Cleanup Wiggum Handoff

Updated: 2026-08-04

## Objective

Complete cleanup epic `jwiegley/nix-config#98` under the accepted Definition of
Done in [`CLEANUP-PLAN.md`](CLEANUP-PLAN.md).

## Authoritative state

- The authoritative checkout is `/Users/johnw/src/nix`, on `main`. It is the
  only worktree.
- The #124 source boundary is signed commit `1ad23d7c`, with accepted Darwin and
  package-parity baselines in `9c476513`. Publication and activation receipts
  are tracked separately on the issue.
- Hera runs Darwin generation 991. Agent Deck 1.11.0, oMLX 0.5.5, Pi 0.83.0,
  Claude Code 2.1.220, and Codex 0.146.0 are active.
- Codex defaults to native OpenAI `gpt-5.6-sol`; local oMLX and llama-swap
  profiles remain opt-in.
- Pi advertises `openai-codex/gpt-5.6-sol` at 1,050,000 tokens, local DeepSeek
  and local GLM at 262,144, and OpenRouter GLM at 1,048,576.
- oMLX and llama-swap listen only on loopback. The TLS gateway on port 8443 is
  healthy.
- Agent Deck retains all seven recorded sessions; the last fleet probe reported
  zero down sessions. Do not stop, restart, or kill user sessions for cleanup.

## Project state

- Epic #98 remains In Progress.
- Done: #99-#108 and #110-#115, including #104's complete comment audit.
- #109 was closed as not planned after its compliant prototype added far more
  policy and test code than the renderer literals it removed.
- #116 and #119 are In Progress. #118/#120 are Done. #117 is closed not-planned,
  superseded by #124.
- #122 (remove OpenCode) and #124 (remove Ref and Perplexity) are In Progress.
  #123 (retire the Nix model registry) remains Todo after #122. All three are
  subissues of #98 and block #121.
- #125 confines password-store, GnuPG, and Emacs to Hera/Clio after #120/#124.
  It remains a Todo subissue and blocks #121.
- #126 renames the AI-only `config/fleet/` tree back to `config/ai/` after
  #123/#125; it is a deferred Todo subissue and blocks #121.
- #121 remains the final unchanged-candidate verification and cleanup closeout.

## Comment-audit boundary

The #104 closeout covered 176 retained files, 133 comment-bearing files, 921
entries, and 2,032 comment lines. The primary ledger audited 919 entries; a
two-entry supplement covered the five Pi paths after their owner boundary cleared.
All entries were valid. Generated locks/JSON, patches, keys/certificates,
proven-vendored files, and the four whole files owned by pending C10 deletion
issues remain explicit exclusions.

## Mutable-state holds

- #116: all eight hosts completed cleanup-bearing activation and clean post-cycle
  probes. Vulcan used two repository-owned `./build` cycles; shared-work generation
  198 is resident/rooted everywhere and all four fresh Codex probes passed. VPS
  archived two differing Alexey artifacts unchanged under
  `/home/johnw/dl/nix-managed-preflight-vps-20260804-072726`, then completed two
  clean switch cycles. The finite cleanup and tombstones are removed in the
  current source candidate; focused/all-system checks, fast gate, and native build
  pass. Post-retirement fleet activation remains a separate gate.
- #117 is superseded. #124 removes Ref, Perplexity, the legacy importer, and the
  temporary credential carrier. PromptDeploy source retirement is published at
  `4ee0401`; no shared password-store provisioning or mutation is needed. Exact
  manifest reconciliation must wait for a user-approved quiescent client window
  because those clients do not share a mutation lock.
- #118 is complete: published `8c3d4431` removed the one-shot migration; Hera
  generation 991 passed post-retirement path/session/fresh-Pi proof.
- #119: Hera 990, Clio 245, and all four shared-work hosts passed fresh Codex and
  steady-state log probes. Published commit `302e8de8` removes the old-directory
  migration after focused checks, fast gate, native build, and independent audit.
- #120 is complete: published `b5d31874` removed the stale-label guard; Hera 991
  and Clio 247 passed post-retirement old-label absence proof.
- #122: published `f9be4d23` removes OpenCode package/cask selection, four
  profiles, renderer, preflight ownership, selectors, and OpenCode-only model
  default/schema plumbing. Focused catalog/preflight checks, generated-leaf and
  package absence probes, fast gate, a native system build, refreshed baselines,
  and independent audit pass. Host activation remains open.
- #124: signed `1ad23d7c` removes both live catalog entries, renderer
  credentials, the legacy Ref importer, the password-store carrier, and the
  Perplexity-bound web-searcher content. PromptDeploy no longer produces either
  service. A proposed activation-time JSON writer was rejected before commit:
  without a lock shared by the clients it could overwrite concurrent updates or
  discard the manifest evidence needed for declarative removal.
  Key-name-only probes found mutable Claude/Codex configs clean on Hera, VPS,
  Vulcan, and all four shared-work hosts; their current managed leaves and
  PromptDeploy manifests still reflect the pre-retirement generation, and
  Hera's Pi cache is stale. Clio timed out. Reconciliation must not run until
  John approves a quiescent window for Hera sessions `nix-review`, `ct`,
  `ares-main-review`, `local`, and `llm-setup`; andoria-t2 Claude review
  sessions; Vulcan session `nixos`; and any then-live Clio session.

## Concurrent work boundary

The five Pi Loop edits landed as signed commit `dec54ed8`; the primary checkout
had no unrelated dirty paths when #118 source retirement began. Continue to
refresh ownership before every shared-file edit.

## Authorization boundary

Authorized: accepted decisions D1-D7, local cleanup edits, signed commits, normal
dual-remote publication, cleanup-bearing lock updates/activations, and fresh
disposable Codex/Pi processes. Existing sessions must remain untouched.

The authorized `302e8de8` post-retirement activation completed on Hera 991 and
Clio 247. Not implicitly authorized: the later #116 no-producer fleet activation,
password-store mutation, history rewriting, force pushes, or moving/deleting other
user backups/state. Every `gh` invocation must explicitly select account `jwiegley`.
