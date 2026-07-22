# Subagent-Driven Development Progress

Plan: `docs/superpowers/plans/2026-07-22-nix-managed-agent-configuration.md`
Design: `docs/superpowers/specs/2026-07-22-nix-managed-agent-configuration-design.md`

Planning gate: passed independent scope, security, and final fess review. Tasks 1–12 are approved for implementation; Task 13 remains separately fail-closed.

| Task | State | RED evidence | GREEN evidence | Review | Commit |
| --- | --- | --- | --- | --- | --- |
| 1. Static external resources | complete | Missing `pkgs.agent-resources` at evaluation | Focused check, public package build, and full `nix flake check -L path:.` exited 0; exact 22-name manifest passed | Scope, security, and fess PASS | ai-nix `651cf6593cf4b7a3c4202e35dd495353d389f4c5` |
| 2. Pi extensions | complete | Missing `pi-extensions/pi-mcp-adapter` and `pi-extensions/pi-subagent`; all Task 1 assertions remained green | Focused check `/nix/store/mv17wd7bf1v4wzx6pg4q83hyari9p5bx-agent-resources-check`, public package `/nix/store/rwa7n4cn1fgr5wy454vciy33qymcfg7g-agent-resources`, full `nix flake check -L path:.`, and explicit-root offline Pi RPC smoke passed | Scope, security, and fess PASS | ai-nix `47f7a52ce140e0f5cccef18e0e5e9c617c0f0504` |
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
- Task 1 RED setup first exposed an unquoted zsh flake-reference glob and then a test-only Nix string parse error; quoting the reference and replacing the empty `read -d` literal produced the required missing-`pkgs.agent-resources` RED.
- Task 1 GREEN iteration corrected only temporary expected-tree permissions. Independent review then caught Statix's one-target CLI contract; separate lint invocations fixed it. The final focused check, public package build, full flake gate, and three re-reviews all passed.
- Task 2 source authority was independently reverified before implementation. pi-mcp-adapter: rev `82724dccc13a49310530898f922bafff12b7f3fe`, NAR `sha256-JjYS9tPSoVuubdmHTqTNNYfDJOc9CBPvVbIxvdJWi7M=`, version `2.11.0`, Pi entrypoint `./index.ts`, bin `cli.js`, lock SHA-256 `156cd7b65090cb5600651b40563dea3974fbeeaa7dbb6346f3deb0e9e0528bd0`. pi-subagent: rev `70248dcf7c8a5ca74497e817a699f009c55e6917`, NAR `sha256-TyeqNoz5RLRlDWY4rcZbOY/UCHOMiNIjuGsW2xZoTEE=`, version `3.0.0`, main/Pi entrypoint `index.ts`, lock SHA-256 `a7fbb2c6c10ee6af111dcf7a10064770cc360e818b6f424854c231ed6872d5ff`. Its four Pi peers require `>=0.80.5`; current llm-agents Pi is `0.81.1`.
- Task 2 boundary clarification: the no-installer guarantee applies to packaging, activation, registration, and initial discovery. The exact pinned adapter intentionally retains later configured `npx` MCP-launch/cache behavior and optional global Glimpse discovery; banning those would require a separate upstream patch and is not part of this task.
- Task 2 RED reported only the missing `pi-mcp-adapter` and `pi-subagent` roots after every Task 1 resource assertion passed.
- Task 2 GREEN asserted the pristine upstream lock hashes before normalizing three adapter dev-only lock entries missing integrity in the build copy, then passed the focused/public/full gates and manual offline RPC smoke. Pi loaded both explicit roots, exposed `mcp` and `mcp-auth`, left the auth sentinel unchanged, and invoked no failing installer/discovery shim.
