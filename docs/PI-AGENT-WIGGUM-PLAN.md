# Pi Agent Wiggum Plan

Status: original target frozen on 2026-07-14; expanded target approved on
2026-07-22. These completion criteria may be clarified or extended, but not
reduced.

## Target

Make the Pi agent harness from <https://pi.dev/> available and usable on Hera
through the existing declarative Nix configuration. Use an established
upstream package when one is already present; add a local `ai-nix` derivation
only if no suitable upstream package exists. The referenced "Learning Pi
Through Force" workflow is context, not a parity target.

## Expanded approved target

The user's separate 2026-07-22 request activates work that was an explicit
non-goal of the original installation task:

- complete the approved first-class Promptdeploy Pi target in
  `/Users/johnw/src/promptdeploy-pi-target` according to its frozen master
  plan and acceptance criteria;
- add complete Nix packages in `/Users/johnw/src/ai-nix` for `pi-btw@0.4.1`,
  `pi-mcp-adapter@2.11.0`, `pi-web-access@0.13.0`,
  `pi-subagents@0.35.1`, `@narumitw/pi-goal@0.24.0`, and
  `pi-lean-ctx@3.9.12` from the already-audited pinned repositories;
- expose native `lean-ctx` from the existing `llm-agents.nix` package set;
- configure the six package store paths, existing Pi settings, and custom
  theme through Home Manager's existing `programs.pi-coding-agent` module,
  retaining `package = null` and mutable credentials/sessions;
- preserve `pi-subagents`'s native `subagent` and `subagent_wait`; rename the
  Promptdeploy-owned confined bridge tool to `promptdeploy_subagent` and
  update only Promptdeploy-owned adapters, instructions, policies, and tests;
- retain the complete `pi-mcp-adapter` package and helper CLI, but disable its
  extension in the managed Pi package selector so Promptdeploy remains the
  sole active managed MCP bridge;
- perform no direct npm/npx installation, lock update in consumer
  repositories, remote Andoria edit, Home Manager switch, system rebuild,
  live Promptdeploy deployment, or push without separate authorization.

The original criterion 7 was satisfied by the earlier Pi installation rollout.
It does not authorize activation of this expanded integration.

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
   branches current with their bases. Publication remains separately gated;
   never rewrite shared history or force-push.
9. Complete every phase and check in Promptdeploy's frozen
   `2026-07-21-pi-target.md` master plan except its separately gated live
   rollout, with the bridge namespace revision above applied consistently.
10. Export all six complete Pi package roots from `ai-nix` on
    `aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`, including declared
    resources, ordinary runtime dependencies, generated vendor bytes, and
    legitimate CLIs while excluding mutating installer CLIs.
11. Prove each packaged Pi root loads its selected resources under Pi 0.81.1
    without npm peer auto-installation or a second Pi runtime.
12. Make the shared Home Manager configuration retain Hera's exact current Pi
    settings and theme, add explicit per-package resource selectors, and place
    native `lean-ctx` on `PATH` without relying on
    `packageWithExtraPackages`.
13. Run each repository's complete format, lint, type, test, build, and flake
    gates through its direnv environment; run cross-platform Nix evaluation
    and focused package/loader acceptance checks.
14. Commit logical units, run an independent fess audit after work commits,
    drain actionable partner observations, and leave every branch locally
    current with its base and clean except for pre-existing unrelated work.

## Explicit non-goals

- Do not install the article's `pi-subagents`, MCP adapter, Lens extension,
  research skills, provider endpoints, or credentials without a separate
  request.
- Do not modify unrelated observation or handoff files owned by another agent.
