# Pi Agent Wiggum Plan

Status: frozen on 2026-07-14. These completion criteria may be clarified, but
not reduced.

## Target

Make the Pi agent harness from <https://pi.dev/> available and usable on Hera
through the existing declarative Nix configuration. Use an established
upstream package when one is already present; add a local `ai-nix` derivation
only if no suitable upstream package exists. The referenced "Learning Pi
Through Force" workflow is context, not a parity target.

## Done criteria

1. Confirm the canonical Pi identity, package source, executable, version, and
   runtime requirements from current authoritative sources.
2. Use the existing `llm-agents.nix#pi` package if the pinned input supports
   `aarch64-darwin`; do not add a duplicate local derivation.
3. Include Pi in the `ai-nix` aggregate toolchain and document that inventory.
4. Include Pi in the shared managed-host agent package list so Hera's Home
   Manager profile receives it.
5. Preserve Pi's mutable profile, sessions, credentials, trust state, and
   third-party extensions outside the Nix store. Do not create or overwrite
   `~/.pi/agent` as part of package activation.
6. Pass the complete `ai-nix` format, lint, test, build, and flake checks, and
   prove its aggregate output contains a working `bin/pi`.
7. Build and switch Hera's complete Darwin configuration, then prove the
   activated `pi` is the Nix-managed executable and passes isolated,
   credential-free offline version/help/model-registry smoke tests.
8. Commit each repository's logical change, audit the work independently,
   address only observations caused by these Pi changes, and leave both
   branches current with their bases. After Hera verification, push both
   repositories normally; never rewrite shared history or force-push.

## Explicit non-goals

- Do not install the article's `pi-subagents`, MCP adapter, Lens extension,
  research skills, provider endpoints, or credentials without a separate
  request.
- Do not modify unrelated observation or handoff files owned by another agent.
