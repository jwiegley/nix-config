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
