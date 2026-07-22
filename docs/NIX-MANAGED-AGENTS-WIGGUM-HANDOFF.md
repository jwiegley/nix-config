# Nix-Managed Agents Wiggum Handoff

Updated: 2026-07-22

## Objective

Replace promptdeploy as the active desired-state mechanism for Claude Code, Codex, OpenCode, Droid, and Pi with immutable `ai-nix` resources/wrappers and exact Home Manager leaves, then execute the reviewed fleet migration and verify idempotence.

## Authoritative artifacts

- Design: `docs/superpowers/specs/2026-07-22-nix-managed-agent-configuration-design.md`
- Implementation plan: `docs/superpowers/plans/2026-07-22-nix-managed-agent-configuration.md`
- Progress ledger: `.superpowers/sdd/progress.md`

## Recorded authority

- The user explicitly approved continuing the active implementation objective on 2026-07-22; earlier turns explicitly authorized ordinary commits and pushes in changed repositories.
- Host mutation, rollback-window closure, and promptdeploy retirement remain fail-closed: authority must be recorded here immediately before execution, the command must run locally on the affected host, and no deployment SSH/rsync path may be introduced.

## Worktrees and branches

- nix-config: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config`, branch `feat/nix-managed-agent-config`, based on design commit `e5e08e2b20229646e34f3dde570f345c4df85361`.
- ai-nix: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources`, branch `feat/nix-managed-agent-resources`, based on `0610fd1283cf5ee52a5c71cbc8411a647b37dd7c`.
- promptdeploy: `/Users/johnw/src/promptdeploy`, read-only oracle. Preserve dirty `models.yaml`; do not edit or deploy from the historical Pi branch.

## Preservation boundaries

- Preserve user changes on nix-config main: `config/packages.nix` and `docs/PI-AGENT-WIGGUM-PLAN.md`.
- Preserve promptdeploy `models.yaml` exactly as the frozen authoritative dirty input.
- Never read `.env` or live secret-bearing client configuration.
- Do not add a generic deployment, ownership-manifest, reconciliation, remote-copy, or runtime-install framework.
- GPTel and git-ai remain untouched.

## Current state

- Approved design is committed in nix-config.
- Task 1 is committed in ai-nix as `651cf6593cf4b7a3c4202e35dd495353d389f4c5`: the immutable skill-resource package contains the exact 22-name set and passed focused/full gates plus independent scope, security, and fess review. The nix-config implementation worktree remains at its approved planning commit.
- Task 2 source authority was recorded before implementation: pi-mcp-adapter `82724dccc13a49310530898f922bafff12b7f3fe` (`2.11.0`, Pi `./index.ts`, bin `cli.js`, lock `156cd7b65090cb5600651b40563dea3974fbeeaa7dbb6346f3deb0e9e0528bd0`) and pi-subagent `70248dcf7c8a5ca74497e817a699f009c55e6917` (`3.0.0`, main/Pi `index.ts`, lock `a7fbb2c6c10ee6af111dcf7a10064770cc360e818b6f424854c231ed6872d5ff`). Current Pi `0.81.1` satisfies all four `>=0.80.5` peers.
- Task 2's no-installer boundary covers packaging, Home Manager activation, registration, and initial extension discovery. The exact unmodified adapter retains its explicit operational `npx` MCP-launch/cache behavior and optional global Glimpse discovery; prohibiting those later configured behaviors would require an out-of-scope upstream patch.
- Task 2 is committed in ai-nix as `47f7a52ce140e0f5cccef18e0e5e9c617c0f0504`: both immutable Pi extension roots passed the focused/public/full gates and an isolated explicit-root offline RPC smoke. The build asserts each pristine upstream lock hash before normalizing three adapter dev-only entries that lack integrity in the build copy; the packaged closure remains production-only.
- Task 3 pre-RED inspection corrected pinned-client premises: Codex `0.144.6` effectively applies profile-v2 only on its explicit runtime surfaces, its `mcp` command discards a selected profile before operating on base config, and same-directory `hooks.json` is global across layers. The design/plan now require a fixed version-asserted recognizer, one managed Codex TOML artifact with inline hooks, the proven nonnetworked `debug prompt-input` oracle, and unchanged delegation elsewhere.
- Promptdeploy, ai-nix, and nix-config inventories were completed read-only under `/tmp/wg-nix-managed-ai/`.
- The corrected 13-task plan passed independent scope, security, and final fess review; Tasks 1–12 are approved to begin.
- Baseline ai-nix `nix flake check -L path:.` completed successfully, including the existing Gradio build and 757-test suite.
- Baseline nix-config evaluation passed. The unrelated existing `anvil-mcp-dedicated-smoke` initially failed only after its functional assertions, when a non-atomic probe left an empty PID marker. Store/worktree hashes match. A fresh focused `nix build -L 'path:.#checks.aarch64-darwin.anvil-mcp-dedicated'` then exited 0, including all unit/integration groups and the final two-daemon smoke.
- PAL/consensus review tools are unavailable in this session; independent read-only subagents provide the required review separation.

## Operating discipline

- Use Anvil first in nix-config and recheck modified file-backed Emacs buffers before each edit batch.
- Execute tasks serially; use parallel agents only for isolated read-only review or `/tmp` artifacts.
- For every logical work commit: RED test, expected failure, minimal GREEN, focused/full verification, task review, and fess audit.
- Keep promptdeploy outside the steady-state closure. The secret-free oracle is an explicit exception to normal promptdeploy shell practice because installed `de` loads `.env` and invokes `nix develop`; oracle commands instead use the named `#promptdeploy` app under an allowlisted `env -i`, synthetic empty HOME, and `--no-write-lock-file`; every state-reading/writing command also uses a non-symlinked `--target-root`, while read-only `validate` is the sole parser-required exception.
- Use path flakes and the local ai-nix override until the reviewed ai-nix revision is published and pinned.

## Resume point

Begin Task 3 in the ai-nix worktree by recording the five required non-target derivation paths, then add the parsing-complete wrapper/bridge RED check; preserve Task 2 commit `47f7a52ce140e0f5cccef18e0e5e9c617c0f0504` as the review boundary.
