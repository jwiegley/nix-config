# AI/Nix Reintegration Wiggum Handoff

Updated: 2026-07-23

## Current state

- Wiggum is active for `docs/AI-NIX-REINTEGRATION-WIGGUM-PLAN.md`.
- Implementation is isolated at `/Users/johnw/src/nix.worktrees/ai-nix-reintegration` on `feat/ai-nix-reintegration`, based on `ea92bc4093bf55fe3e8f336c1f36a09cc497d4b5`. The standalone `ai-nix` checkout remains clean at `34a0a4d24548f7430ff5c9555f15d8fbda9f541d`.
- The primary `/Users/johnw/src/nix` checkout has a concurrent, unrelated modification to `config/ai/model-registry.json`; do not stage, overwrite, or copy that file into this branch unless its owner commits it and the branch is deliberately updated.
- The user approved the MCP/extension architecture and clarified that parity is the union of Claude Code and Codex MCPs per machine, applied to every other agent tool on that machine.
- The mandatory PAL gate is resolved in favor of a thin portable `config/ai` subflake with one root-owned implementation tree.
- The worktree has its own allowed direnv using copied ignored `.envrc` and `.envrc.cache`; no dependency was installed. A fresh `direnv exec . nix flake check --print-build-logs` passes at the baseline.
- Anvil is available through a dedicated Emacs daemon. Its modified-file buffer set was empty before this documentation batch; that does not prove a separate interactive Emacs has no unsaved buffers.

## Established findings

- `ai-nix` has unrelated Git ancestry, but the original AI overlays lived in this repository until `bf2c73e363296c94794ef2268996ce7a8d7a8ce6` (`Remove vendored AI overlays`) on 2026-06-17. The preceding commits `c3ed3c0` and `295e383` introduced the split.
- The standalone tree contains 11 maintained overlays, 5 patches, `agent-resources`, wrapper/package-selection logic embedded in its flake, and substantive resource/wrapper/bridge/overlay tests. Generated `build/`, `result`, `.envrc.cache`, the old lock, and synthetic coverage/profile/fuzz/memory reports must not migrate.
- The root flake currently declares many `git+file:///Users/johnw/...` inputs and a private local CA file, so it cannot directly replace portable `ai-nix` outputs for remote consumers without an architecture change.
- Production consumers include Vulcan (`aarch64-linux`), Andoria’s four-host shared profile (`x86_64-linux`), and VPS (`x86_64-linux`), plus an auxiliary Git-AI VM configuration. Consumers rely on both raw `nix-config` source paths and `ai-nix` flake outputs.
- MCP target deltas are frozen: Clio/Hera OpenCode gain Drafts and PAL; shared-work OpenCode gains PAL; Vulcan OpenCode gains `drafts-hera` and PAL; Hera Droid gains DEVONthink, Drafts, Memory Vault, and stock-trader; Hera Pi gains those four plus PAL. Target-only entries remain.
- The existing `auto-compact-resume` Bun suite passes 12/12 before migration.
- `pi-subagent` uses Node `spawn()` to launch independent headless Pi RPC children; it does not create tmux panes. Separate tmux orchestration remains possible for acceptance testing.
- `pi-btw` was planned in future-work documents but was never implemented or installed, including on the `feat/pi-extra-extensions` branch. Treat it as an explicit missing extension, not lost content.
- Fresh tmux lifecycle evidence for the installed Anvil artifact is under `/tmp/wg-anvil-lifecycle/evidence-20260723T231407Z`: clean shutdown removed the test daemon and both instance trees in 1 second; SIGKILL of only the test client removed them in 5 seconds. Only empty mode-0600 session-gate locks remain, as designed. The live profile selects resilience artifact `39f9c59bfc51379db6243b1be20edca1ea783c2b`, although `main` still pins `01eecf6348e7e9e6462bddd89b1cbc03c157a7d6`. A pre-existing orphan stdio process from an older store artifact was observed and left untouched.
- LiteLLM attribution is resolved without reading prompts or secrets. The apparent requester `10.0.2.100` is the synthetic `tap0` address inside each rootless Podman namespace, not another machine. The eight 2026-07-23 Opus 4.7 requests came from Vulcan's `stock-trader.service`, which is deliberately pinned to Claude Agent SDK 0.1.30 and that model route. Historical Haiku requests comprise four DEVONthink calls and 27 OpenCode calls outside the initially queried July 16-24 window. `hera_vibe_proxy_credential` is LiteLLM's outbound credential name on both model deployments; the inbound LiteLLM key alias was `default`.

## Architecture gate resolution

The existing password-store LiteLLM credential was mapped only in a temporary child environment to PAL's OpenAI-compatible custom provider. No resolved credential entered disk, argv, output, or logs. Both required participants completed successfully; raw evidence is under `/tmp/wg-pal-litellm-20260723` while that temporary directory exists.

`gpt-5.5-pro` selected the thin in-repository portable subflake. `gemini-3.1-pro-preview` selected caller-supplied `flake = false` inputs to avoid a second lock. Final synthesis selects the subflake because frozen criterion 5 requires preserving the existing flake output contract; the caller-supplied-only design cannot satisfy that criterion. The selected invariants are frozen in the plan.

## Exact resume point

1. Commit only the two Wiggum documents as the architecture/baseline checkpoint; do not include the primary checkout's concurrent model-registry change.
2. Start the red-green compatibility oracle work unit before migrating production Nix code. The oracle must capture the old `ai-nix` output/package contract, history ancestry, and one-repository command behavior.
3. Import the standalone history through a real unrelated-history merge point, then move maintained content to the canonical root-owned implementation tree while retaining the portable `config/ai` export boundary.
4. Keep the root on the old `ai-nix` input until the local portable subflake passes the compatibility oracle; then switch root composition and scripts.
5. Package `auto-compact-resume` and implement MCP parity under failing renderer/selection tests before production changes.
6. After implementation and consumer verification, start fresh tmux sessions for every applicable configured tool/host combination and write the comprehensive prompts/commands/agents/skills/MCP/extensions gap audit under `~/dl`, carrying forward the `pi-subagent` and missing `pi-btw` evidence.

## Stop-and-escalate counters

- PAL consensus gate: cleared after one blocked attempt; both required models completed through the existing LiteLLM endpoint.
- Repeated build/test failure signature: none (0/3). The first Anvil lifecycle harness run had one harness-only stdin-liveness failure; after correcting the scratch harness, both lifecycle cases passed.
- Unusable subagent output: none (0/2).
- Destructive/irreversible action: none attempted. Standalone repository retirement remains gated and no shared history was rewritten or pushed.
