# Nix-Managed Agents Wiggum Handoff

Updated: 2026-07-22

## Objective

Keep agent desired state declarative in Nix. Model definitions and selections are
authored in `llm-setup.el`, projected as deterministic nonsecret JSON, and rendered
by Nix for Claude Code, Codex, OpenCode, Droid, and Pi.

## Current scope decision

The user explicitly abandoned the migration/runbook/rollout system formerly described
by Tasks 12–13. Do not create migration machinery, ownership manifests, deployment
scripts, host rollout procedures, or Promptdeploy retirement automation. No host
activation or fleet rollout was performed in this lane.

Tasks 1–11 and the `llm-setup.el` model-registry projection are the completed
implementation boundary. Merging feature branches, updating consumer locks, or
activating a host requires a separate explicit request.

## Reference artifacts and authority

- Design: `doc/superpowers/specs/2026-07-22-nix-managed-agent-configuration-design.md`
- Main implementation plan: `doc/superpowers/plans/2026-07-22-nix-managed-agent-configuration.md`
- Model projection plan: `doc/superpowers/plans/2026-07-22-llm-setup-nix-model-registry.md`
- Progress ledger: `.superpowers/sdd/progress.md`

The design is authoritative only for the declarative architecture implemented by
Tasks 1–11. Every migration, runbook, rollout, rollback-window, and retirement
portion of that design is historical and superseded by the current scope decision.
The main plan is retained as historical design evidence. Its unchecked Tasks 9–11
boxes are stale; the implementation, smoke fixtures, and independent source audit
confirm those tasks are present. Its Tasks 12–13 are superseded and must not be
resumed implicitly.

## Published branches and revisions

- `ai-nix` branch `feat/nix-managed-agent-resources`:
  `0b9941324daca4fba248de3174d20cb299bc5ad8`.
  The Nix resource closure remains immutably pinned to reviewed revision
  `8fbb74948523979a166f39326ca14af4647d5f2d`; the later commit removes only a
  stale Promptdeploy-coupled test assertion.
- `llm-setup` branch `feat/nix-model-registry`:
  `821f8fa854f93fbad900271d4059899395ab8e57`.
- `dot-emacs` branch `feat/llm-setup-nix-model-registry`:
  `ae4a3cb8f4422ab97b269d1e2097263c04bb86ff`, whose
  `lisp/llm-setup` gitlink points exactly to `821f8fa854f93fbad900271d4059899395ab8e57`.
- `nix` branch `feat/nix-managed-agent-config`: model-registry implementation
  commit `75b072a30aeea1ea574b89c100dd4e01da17c356`; the final branch head also
  contains this closeout documentation.

All pushes are ordinary non-force pushes. Dirty main worktrees were preserved and no
feature branch was merged.

## Completed state

- `llm-setup-reset` no longer emits `models.yaml`. It retains the independent
  LiteLLM and llama-swap writers, publishes the Nix registry once, and updates GPTel.
- The registry contains 8 providers and 119 routes. GPT-5.6 Luna, Sol, and Terra each
  project once directly through `positron-openai` and once through LiteLLM.
- Nix validates the schema and renders model/provider/default data for every managed
  agent profile. Exact counts, route order, provider splits, and semantic hashes are
  smoke-gated.
- Home Manager owns exact immutable leaves, uses the previous generation for
  collision/tamper checks, and structurally guards Pi mutable state.
- DEVONthink/iTerm2 synchronization is Hera-only and digest-gated; an unchanged model
  exits before application probes or writes.
- Git Surgeon, Superpowers skills, Fractal, Pi Quiet, Pi MCP adapter, and Pi subagent
  are present in the declarative closure. `pi-openai-server-compaction` exists once
  in the pinned resource closure but is intentionally not linked while its upstream
  peer range excludes packaged Pi 0.82.0.
- `trade-journal`, `org-jw`, `renamer`, `hours`, `pushme`, and
  `git-monitor` remain Darwin-only and are absent from Linux selections.
- The smoke gate rejects reintroduction of `programs.promptdeploy`, and the current
  host configurations do not define it. Promptdeploy is not a steady-state package
  or activation dependency.

## Fresh verification

- `llm-setup`: 24/24 ERT tests, pre-commit checks, and
  `nix flake check -L path:.` passed.
- The registry exporter was run twice against the tracked Nix destination. Both runs
  preserved inode `1074660653`, mtime `1784780095`, size `20062`, and SHA-256
  `f590a61be069f84e8230854b04239219cc0dceb1863a57f8c91b31e939523164`.
- Nix focused `ai-home-manager-smoke`, full `nix flake check -L path:.`, and
  `lefthook run pre-commit --all-files` passed.
- `ai-nix`: focused resource check, all eight current Darwin flake checks, and
  lefthook passed. Native x86 CI was not restarted merely to rebuild GHC.
- Independent audits found no source-level blocker in Tasks 9–11 or the model
  projection.

## Preservation boundaries

- Preserve the staged user-owned `/Users/johnw/src/promptdeploy/models.yaml`; this
  lane did not edit or deploy Promptdeploy.
- Preserve dirty main worktrees in `nix`, `ai-nix`, and `dot-emacs`.
- Never read live credentials or secret-bearing expanded client configurations.
- Do not activate hosts, merge branches, close rollback windows, or revive Tasks
  12–13 without a new explicit request.
