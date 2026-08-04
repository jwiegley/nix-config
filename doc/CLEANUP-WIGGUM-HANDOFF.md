# Cleanup Wiggum Handoff

Updated: 2026-08-03

## Objective

Complete cleanup epic `jwiegley/nix-config#98` under the accepted Definition of
Done in [`CLEANUP-PLAN.md`](CLEANUP-PLAN.md).

## Authoritative state

- The authoritative checkout is `/Users/johnw/src/nix`, on `main`. It is the
  only worktree.
- Published Gitea, GitHub, and local `main` match signed commit `c4c57b63`.
- Hera runs Darwin generation 988. Agent Deck 1.11.0, oMLX 0.5.5, Pi 0.83.0,
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
- #116 is In Progress. #117-#120 remain Todo with current HOLD evidence recorded
  on their issues.
- New user-requested cleanup issues #122 (remove OpenCode) and #123 (retire the
  Nix model registry) are Todo, are subissues of #98, and block #121. #123 is
  ordered after #122; #122 is ordered after #116.
- #121 remains the final unchanged-candidate verification and cleanup closeout.

## Comment-audit boundary

The #104 closeout covered 176 retained files, 133 comment-bearing files, 921
entries, and 2,032 comment lines. The primary ledger audited 919 entries; a
two-entry supplement covered the five Pi paths after their owner boundary cleared.
All entries were valid. Generated locks/JSON, patches, keys/certificates,
proven-vendored files, and the four whole files owned by pending C10 deletion
issues remain explicit exclusions.

## Mutable-state holds

- #116: Hera 988, Clio 243, and shared-work 197 are clean and contain the full
  cleanup. Vulcan 2405 and VPS 124 predate it and still contain retired Anvil,
  managed query-MCP, and PromptDeploy state. Their authoritative locks must be
  updated and activated before the fleet's two-cycle proof can begin.
- #117: published commits `1aefe2b1` and `c4c57b63` give Hera, Clio, and
  shared-work the source-backed fail-closed credential carrier. Shared-work's
  password store lacks both required Ref and Perplexity entries; provisioning,
  activation, and fresh sanitized Ref connections remain external gates.
- #118: Hera's path state is clean and generations 987/988 preserve the XDG
  migration and declarative link. Candidate activation and a user-started fresh
  Pi/session-preservation check remain outstanding.
- #119: all six Codex hosts have the correct local log link and no residue;
  shared-work generations 196/197 are resident on all four machines. Fresh Codex
  sessions remain outstanding on Clio and the four shared-work members.
- #120: the old launchd label is absent in both domains on Hera and Clio, and
  Hera 987/988 plus Clio 242/243 postdate the handoff. Clio still needs its
  separately authorized additional activation cycle.

## Concurrent work boundary

Five concurrent Pi Loop files remain user-owned and dirty: `config/fleet/preflight.nix`,
`config/fleet/renderers/pi.nix`, `packages/pi-gallery/default.nix`,
`test/ai/managed-preflight.nix`, and `test/ai/pi-gallery.nix`. Do not stage,
rewrite, delete, or absorb them. The shared test file overlaps #116/#118 source
deletions, so those edits must serialize after the Pi owner commits.

## Authorization boundary

Authorized: accepted decisions D1-D7, local cleanup edits, signed commits, and
normal dual-remote publication through `bin/publish`.

Not implicitly authorized: host activation, fresh client launch, consumer-repository
or lock edits, shared password-store provisioning, history rewriting, force pushes,
or deletion of user backups/state. Never restart or kill an existing session.
Every `gh` invocation must explicitly select account `jwiegley`.
