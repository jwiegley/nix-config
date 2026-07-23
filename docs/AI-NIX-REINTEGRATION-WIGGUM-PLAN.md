# AI/Nix Reintegration Wiggum Plan

Status: Definition of Done frozen on 2026-07-23. The mandatory PAL architecture gate is resolved in favor of a thin portable subflake within this repository. These completion criteria may be extended but not reduced.

## Goal

Return the maintained contents and published capabilities of `~/src/ai-nix` to `~/src/nix`, their repository of origin, so one repository manages John’s host and home configuration while remaining consumable by Vulcan, Andoria, VPS, and other current Linux consumers. Complete the already approved Pi extension packaging and per-machine MCP parity work in the same declarative configuration.

## Frozen Definition of Done

1. Preserve the complete maintained `ai-nix` Git history in the unified repository, with the 2026-06-17 extraction/removal history documented and traceable.
2. Integrate every maintained overlay, patch, package, resource derivation, substantive test, and public package/library output from `ai-nix`; do not migrate generated outputs, caches, the old lock file, or synthetic no-signal QA reports.
3. Retain one canonical package inventory, overlay implementation, CI workflow, hook configuration, and active update workflow.
4. Remove all live dependencies on a sibling `~/src/ai-nix` checkout from the root flake, Home Manager modules, build helpers, `update-agents`, `update-overlay`, `upgrade`, and installed scripts.
5. Keep the unified source consumable by Hera and Clio directly and by Vulcan, Andoria, VPS, and current auxiliary consumers, preserving all observed flake outputs, raw source import paths, package names, wrapper behavior, resource layouts, supported systems, and downstream overlay ordering.
6. Update every authoritative downstream consumer flake and regenerate its lock through its own direnv environment; historical records retain explicit archival context rather than receiving misleading bulk rewrites.
7. Move `auto-compact-resume` source, tests, and corrected design documentation under `config/ai/extensions/auto-compact-resume`; Nix installs only runtime `index.ts` at `~/.pi/agent/extensions/auto-compact-resume`.
8. Enforce per-machine MCP parity: every MCP available to Claude Code and/or Codex on a machine is also available to OpenCode, Droid, and Pi on that machine. Preserve target-only MCPs.
9. Generalize Pi HTTP MCP rendering for optional headers with OAuth disabled, and Droid rendering so secret-header HTTP uses the existing bridge while headerless Memory Vault uses native HTTP.
10. Add exact regression oracles for extension packaging, every changed MCP selection, header/credential behavior, and one-repository update commands. Follow red-green TDD for behavior changes.
11. Read command environments from each current working tree’s direnv; never use `nix develop` or install dependencies on the fly. If environment dependencies change, regenerate with `de`, re-read direnv, and retry.
12. Preserve secrets and private CA boundaries; never read or decrypt `secrets.yaml`, expose credentials, or make local-only inputs silently break remote consumers.
13. Each logical work unit is committed, independently fess-audited, partner observations are cleaned up, and the branch is locally current with its base. No push or shared-history rewrite occurs without a human gate.
14. The full root build/check suite, focused extension tests, cross-platform evaluations, wrapper/resource tests, and every affected consumer evaluation pass with fresh evidence.
15. A final literal-reference audit leaves no live `ai-nix`, `AI_NIX`, sibling-path, retired CLI-flag, or old-URL dependency except intentional compatibility aliases and clearly marked historical records.
16. `~/src/ai-nix` and its worktrees are retired only after their clean/branch/unintegrated-work state is proven and all source/history is recoverable from the unified repository; use a reversible archive step before deletion.
17. The final work commit passes fess, no actionable partner observation remains, and parity checks prove both the old `ai-nix` contract and the approved per-machine MCP contract.

## Planned Work Units

1. Resolve the portability/history architecture through mandatory PAL consensus.
2. Establish the feature branch, baseline checks, compatibility oracle, and history-preserving merge point.
3. Integrate AI overlays, patches, package/resource derivations, helper library, tests, and output compatibility.
4. Convert the root configuration and operational scripts to one-repository behavior.
5. Package `auto-compact-resume` and implement MCP parity with renderer support.
6. Update and verify downstream consumer flakes and locks.
7. Consolidate active documentation, CI, and hooks; mark historical records accurately.
8. Run full cross-platform and consumer verification, audits, partner cleanup, and local restack.
9. Reversibly archive the standalone checkout and remove live user-state references after proving recoverability.

## Selected Architecture

Use a thin portable subflake under `config/ai` within this repository. Remote AI consumers use the repository directory flake, while the host-local root flake and the portable subflake import one canonical implementation tree. The subflake is an export and input boundary only: it must not acquire a separate package inventory, implementation copy, CI workflow, documentation hierarchy, or update workflow. Its lock records only portable AI inputs; the root lock remains authoritative for Hera and Clio host configuration.

The two-model PAL workflow completed successfully through LiteLLM on 2026-07-23. `gpt-5.5-pro` recommended the thin subflake; `gemini-3.1-pro-preview` recommended caller-supplied `flake = false` inputs. The final synthesis selects the subflake because frozen criterion 5 requires preserving all observed `ai-nix` flake outputs. The caller-supplied-only design would intentionally remove that contract and spread compatible-input coordination across every consumer. Making the root flake portable remains rejected because its machine-local application inputs and private CA are valid host concerns whose refactoring would add risk unrelated to AI portability.

The selected boundary has these invariants:

- The portable subflake contains only remote-safe AI inputs and preserves the existing `overlays`, `lib`, `packages`, `checks`, `apps`, `formatter`, and `devShells` contracts where currently published.
- AI overlays, package constructors, patches, resources, and tests have one implementation location in the root repository and are imported by both flake surfaces.
- The portable input graph contains no root-only `git+file` input, private CA, credential, or host configuration.
- The root composes each AI overlay exactly once and preserves caller overlay ordering.
- Flake-true AI and flake-false source consumers pin the same repository revision during migration; each downstream retains its own lock.
- Active CI, hooks, update commands, package inventory, and maintenance documentation remain root-owned.
- The standalone `ai-nix` checkout is not retired until compatibility, history recoverability, downstream locks, and the final literal-reference audit all pass.
