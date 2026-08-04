# Cleanup Wiggum Handoff

Updated: 2026-08-03

## Objective

Complete cleanup epic `jwiegley/nix-config#98` under the accepted Definition of
Done in [`CLEANUP-PLAN.md`](CLEANUP-PLAN.md).

## Authoritative state

- The authoritative checkout is `/Users/johnw/src/nix`, on `main`. It is the
  only worktree.
- Published Gitea and GitHub `main` match the local branch before the active
  comment-audit edits. Every published cleanup commit is signed.
- Hera runs Darwin generation 987. Agent Deck 1.11.0, oMLX 0.5.5, Pi 0.83.0,
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
- Done: #99-#108 and #110-#115.
- #109 was closed as not planned after its compliant prototype added far more
  policy and test code than the renderer literals it removed.
- The current candidate completes #104's retained first-party comment audit.
- #116-#120 remain Todo. #119 and #120 have explicit HOLD evidence recorded on
  their issues; do not present those gates as complete.
- #121 is the final unchanged-candidate verification and cleanup closeout.

## Comment-audit boundary

The corrected retained first-party denominator for #104 is 174 files, 131
comment-bearing files, 933 entries, and 2,731 comment lines. Exclusions are
explicit: generated locks/JSON, patch files, keys/certificates, six
proven-vendored files, and the four whole files owned by pending C10 deletion
issues. The bundled extractor undercounts Nix indented strings and shell heredocs,
so its manifest must be reconciled with that line-audited denominator.

## Mutable-state holds

- #116 Anvil convergence requires current two-cycle evidence on every managed
  host and supported rollback proof.
- #117 Ref importer retirement remains blocked by #116 and fresh sanitized
  connectivity evidence for each Codex host class.
- #118 Pi migration retirement must preserve `~/.pi -> ~/.config/pi` and the
  user backup. Generation evidence exists; fresh-session acceptance still must
  be established without forcing a user session restart.
- #119 Codex log migration has clean path/residue probes, but lacks fresh Codex
  sessions on five hosts and a prior shared closure resident across all four
  shared-work machines.
- #120 gpg-agent handoff has producer and current-label absence proof, but Clio
  still lacks the separately authorized additional activation cycle.

## Concurrent work boundary

An unrelated working-tree edit may appear while cleanup proceeds. Do not stage,
rewrite, or delete it. In particular, a concurrent Pi Loop renderer edit appeared
after `8f303b93`; it is not part of #104 and bypasses the support-only safety
boundary established for the upstream extension. Report it separately.

## Authorization boundary

Authorized: accepted decisions D1-D7, local cleanup edits, signed commits, and
normal dual-remote publication through `bin/publish`.

Not implicitly authorized: another host activation, a user-session restart,
consumer-repository edits, history rewriting, force pushes, or deletion of user
backups/state. Every `gh` invocation must explicitly select account `jwiegley`.
