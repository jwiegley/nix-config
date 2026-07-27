# Architecture Remediation Journal

Append-only durable learnings for the architecture-remediation Wiggum loop. Decisions and current task state belong in the plan/handoff; this file records evidence that should survive compaction.

## 2026-07-26 — Audit synthesis and loop entry

- The audit found 22 actionable architecture/maintainability findings, with update authority, Darwin leakage, and root navigability as P0.
- The built-in codebase-audit workflow was unavailable. A custom planning workflow exposed a missing documented `cwd` global, then exhausted its token budget after five lanes. The user waived PAL and directed implementation to continue; the coordinator froze a direct evidence-based plan instead of retrying orchestration.
- Anvil is a dedicated Emacs backend (`ANVIL_EMACS_STATE_DIR` is set), so its buffer checks do not prove the state of a separate interactive Emacs; no modified repository buffers were visible in the dedicated backend.
- Current repository baseline is clean `main` at `a36d3f51d92158e4e055e3baca85044f575e25a6`.
- Significant deletion candidates remain conditional until maintained external consumers are searched. Git history is sufficient archive only after live decisions and authorizations are migrated.

## 2026-07-26 — WU0 baseline

- `python3 -m unittest -v bin/update-overlay-test.py`: 4/4 passed.
- `nix flake check ./config/ai --all-systems --no-build`: all portable outputs evaluated; only `lib` remains an intentionally unchecked output warning.
- Core Darwin contracts `agent-resources`, `agent-wrappers`, `ai-home-manager-contract`, and `pi-gallery` built successfully.
- `./build system` completed successfully for Hera.
- Non-hidden `doc/observations/*.md`: zero.
- Existing auxiliary worktrees were inventoried and left untouched; one prunable stale worktree record exists and is not part of WU1.

## 2026-07-26 — WU0 fess and partner cleanup

- Fess audit target: signed commit `4f25975fe32262bfc85c27f6bba5083e148dc425`.
- Auditor verdict: FAIL with seven documentation/process findings. Disposition: all accepted and fixed in the cleanup commit—WU0 evidence completed, authorization made explicit, WU6/WU7 contract prerequisites moved ahead of implementation movement, audit approval recorded, finding IDs corrected, mandatory CI contracts enumerated, and durable fess verdict fields required.
- Fleet baseline: Hera repo `4f25975f`, Darwin system `sbcyp...`, HM 41; Clio repo `a36d3f5`, Darwin system `wpgfc...`, HM 220; Andoria-08/T2, Delphi, and GPU repo `ae0156cd`, HM 192; Vulcan repo `a999d89b`, NixOS system `118cx...`.
- Partner observation `2026-07-27T00:28:18.461Z` restored a previously lost TMUX socket-parent finding. Resolution: disable Home Manager `programs.tmux.secureSocket`, remove global `TMUX_TMPDIR`, default the Agent Deck package and remote helper to `/tmp`, retain `AGENTDECK_TMUX_TMPDIR` as calibration override, and remove all `/run/user/$uid`/linger dependence.
- Verification: focused `ai-home-manager-contract` passed; `darwinConfigurations.hera.pkgs.agent-deck` built; independent partner-cleanup reviewer returned PASS.
- The first package build command used a nonexistent root `packages.aarch64-darwin.agent-deck` output after the contract had passed. This was a verification-command error, not a code failure; the correct Darwin package attribute passed on the next attempt.
