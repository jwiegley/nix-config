# Subagent-Driven Development Progress

Plan: `docs/superpowers/plans/2026-07-22-nix-managed-agent-configuration.md`
Design: `docs/superpowers/specs/2026-07-22-nix-managed-agent-configuration-design.md`

Planning gate: passed independent scope, security, and final fess review. Tasks 1–12 are approved for implementation; Task 13 remains separately fail-closed.

| Task | State | RED evidence | GREEN evidence | Review | Commit |
| --- | --- | --- | --- | --- | --- |
| 1. Static external resources | pending | — | — | — | — |
| 2. Pi extensions | pending | — | — | — | — |
| 3. Managed wrappers | pending | — | — | — | — |
| 4. Frozen oracle and canonical assets | pending | — | — | — | — |
| 5. Selectors and models | pending | — | — | — | — |
| 6. Claude and Codex renderers | pending | — | — | — | — |
| 7. OpenCode and Droid renderers | pending | — | — | — | — |
| 8. Pi renderer | pending | — | — | — | — |
| 9. Home Manager integration and activation guards | pending | — | — | — | — |
| 10. Hera model synchronization | pending | — | — | — | — |
| 11. Full fleet gates and ai-nix pin | pending | — | — | — | — |
| 12. Migration and rollback runbook | pending | — | — | — | — |
| 13. Fleet rollout, idempotence, and retirement | pending | — | — | — | — |

## Baseline evidence

- nix-config: evaluation/lint/format reached checks; unrelated existing `anvil-mcp-dedicated-smoke` initially hit the classified non-atomic empty-PID-marker race after its functional assertions. Store/worktree sources match. A fresh focused build then exited 0, including every unit/integration group and the final two-daemon smoke.
- ai-nix: full baseline `nix flake check -L path:.` exited 0; the existing Gradio derivation built and its 757 selected tests passed.

## Attempts

- Plan creation attempt 1 failed before writing because JavaScript interpolated a literal Nix `${...}` fragment.
- Plan creation attempt 2 copied the read-only skeleton successfully; final normalized plan will overwrite it.
- Planning review attempt 1 failed on secret-free oracle isolation, dangling-wrapper handling, exact link tamper checks, source pinning, missing adoption/capability evidence, hidden Sherlock/agent-deck scope, immutable dependency pinning, and consumer rollout reproducibility.
- Planning review attempt 2 resolved the original scope/security findings but found stale design authority, an unowned bridge contingency, impossible oracle filesystem wording, a contradictory credential-presence boundary, and incomplete ai-nix lint coverage.
- Bridge inspection proved unmodified `mcp-remote` unsafe for this contract because static-header 401s enter OAuth/browser state. The plan now pins it with one static-header-only patch, no replacement proxy.
- Planning review attempt 3 passed scope and security; the final fess audit found seven specification/test/documentation gaps. All seven were corrected and the independent fess re-review passed.