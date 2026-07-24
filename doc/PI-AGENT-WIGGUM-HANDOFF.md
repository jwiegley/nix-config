# Pi Agent Wiggum Handoff

> Historical checkpoint: superseded by `AI-NIX-REINTEGRATION-WIGGUM-HANDOFF.md`. Repository paths and versions below are retained as evidence of the 2026-07-14 state, not as current operating instructions.

Updated: 2026-07-14

## Current state

- Frozen target and done criteria: `doc/PI-AGENT-WIGGUM-PLAN.md`.
- Hera is `aarch64-darwin`; Pi was absent from the activated `PATH` at the
  start of this work.
- The pinned `numtide/llm-agents.nix` input already exports `pi` 0.80.6 for
  `aarch64-darwin`. It wraps the official Earendil npm artifact with Bun,
  supplies `fd` and `ripgrep`, sets `PI_PACKAGE_DIR`, and disables Pi's
  version check and telemetry. A local derivation is unnecessary.
- Baseline package build succeeded at
  `/nix/store/4i302lchfqmhzcgdb1hymxamd35fbxxb-pi-0.80.6`; isolated
  `pi --version` and `pi --help` both succeeded.
- `ai-nix` commit `a1ce90eb3a7df576734992235c4938e92315000c`
  adds `agent "pi"` to the aggregate and documents it. The commit passed an
  independent Pi-only fess audit and is published on `main`.
- Hera's complete Darwin configuration built and switched successfully. The
  activated `/etc/profiles/per-user/johnw/bin/pi` resolves to
  `/nix/store/ri2hac4mfry1zcqv1hq9l1psnwf02kpj-pi-0.80.6/bin/pi`; isolated
  offline version, help, and model-registry smokes passed.
- The parent lock now pins the published `ai-nix` commit. A second complete
  Hera build with `NO_AI_NIX_OVERRIDE=1` succeeded.
- The article-specific multi-model research profile is optional and is not
  being installed. Pi already discovers portable skills from
  `~/.agents/skills/` without a generated settings file.

## Repository and tooling state

- `/Users/johnw/src/nix` and `/Users/johnw/src/ai-nix` began on `main` at
  their respective `origin/main` commits. A live HTTPS check confirmed the
  `ai-nix` remote after its SSH smart-card fetch was refused.
- Unrelated working-tree changes appeared after the initial clean check. They
  belong to another agent and must not be inspected, edited, staged, or
  committed by this work.
- Anvil is available through a dedicated Emacs daemon. Its modified-buffer
  checks cover only that isolated daemon, not a separate interactive Emacs.
- PAL is not registered on this host, so no PAL consensus call is available.
- `ai-nix` format, lint, source tests, and flake evaluation passed. Its full
  aggregate build reached an unrelated existing `cohere-melody` native-module
  import failure through `omlx`; the Pi derivation and both Hera builds passed,
  and this work did not modify that out-of-scope package.

## Next actions

1. Commit and independently audit the `nix` logical unit, handling only
   Pi-related observations.
2. Push the parent commit normally and verify both remote `main` refs.
3. Recheck every applicable frozen done criterion.

## Stop-and-escalate counters

- Repeated failing signature: none (0/3).
- Unresolved destructive or intent-sensitive action: none.
