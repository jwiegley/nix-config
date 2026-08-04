# Cleanup Wiggum Handoff

Updated: 2026-08-04

## Objective

Complete cleanup epic `jwiegley/nix-config#98` under the accepted Definition of
Done in [`CLEANUP-PLAN.md`](CLEANUP-PLAN.md).

## Authoritative state

- The authoritative checkout is `/Users/johnw/src/nix`, on `main`. It is the
  only worktree.
- Published Gitea and GitHub `main` match `302e8de8`; local `main` carries the
  active #116 source-retirement candidate.
- Hera runs Darwin generation 990. Agent Deck 1.11.0, oMLX 0.5.5, Pi 0.83.0,
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
- #116 and #118-#120 are In Progress. #117 is closed not-planned, superseded by
  #124.
- New user-requested cleanup issues #122 (remove OpenCode) and #123 (retire the
  Nix model registry) are Todo, are subissues of #98, and block #121. #123 is
  ordered after #122; #122 is ordered after #116.
- #124 removes Ref and Perplexity from every client after #116/#122. #125 confines
  password-store, GnuPG, and Emacs to Hera/Clio after #120/#124. Both are Todo
  subissues and block #121.
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
  temporary credential carrier. No shared password-store provisioning is needed.
- #118: published commit `8c3d4431` removes the one-shot migration and private
  fixtures after Hera's generation-990/fresh-Pi proof. Post-retirement activation
  remains.
- #119: Hera 990, Clio 245, and all four shared-work hosts passed fresh Codex and
  steady-state log probes. Published commit `302e8de8` removes the old-directory
  migration after focused checks, fast gate, native build, and independent audit.
- #120: both Darwin hosts completed the pre-retirement activation/absence proof.
  Published commit `b5d31874` removes the stale-label guard and dedicated test;
  both Darwin builds pass. Post-retirement activation is not yet authorized.

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
