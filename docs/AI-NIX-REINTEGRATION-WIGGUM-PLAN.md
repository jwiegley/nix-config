# AI/Nix Reintegration Wiggum Plan

Status: Definition of Done frozen on 2026-07-23. The mandatory PAL architecture gate is resolved in favor of a thin portable subflake within this repository. These completion criteria may be extended but not reduced.

## Goal

Return the maintained contents and published capabilities of `~/src/ai-nix` to `~/src/nix`, their repository of origin, so one repository manages John’s host and home configuration while remaining consumable by Vulcan, Andoria, VPS, and other current Linux consumers. Complete the already approved Pi extension packaging and per-machine MCP parity work in the same declarative configuration.

## Frozen Definition of Done

1. Preserve the complete maintained `ai-nix` Git history in the unified repository, with the 2026-06-17 extraction/removal history documented and traceable.
2. Integrate every maintained overlay, patch, package, resource derivation, substantive test, and public package/library output from `ai-nix`; do not migrate generated outputs, caches, the old lock file, or synthetic no-signal QA reports.
3. Retain one canonical package inventory, overlay implementation, CI workflow, hook configuration, and active update workflow.
4. Remove all live dependencies on a sibling `~/src/ai-nix` checkout from the root flake, Home Manager modules, build helpers, `update-agents`, `update-overlay`, `upgrade`, and installed scripts.
5. Keep the unified source consumable by Hera and Clio directly and by Vulcan, Andoria, VPS, and current auxiliary consumers, preserving all observed flake outputs, raw source import paths, package names, wrapper behavior, resource layouts, supported systems, and downstream overlay ordering.
6. Update every authoritative downstream consumer flake and regenerate its lock through its own direnv environment; historical records retain explicit archival context rather than receiving misleading bulk rewrites.
7. Move `auto-compact-resume` source, tests, and corrected design documentation under `config/ai/extensions/auto-compact-resume`; Nix installs only runtime `index.ts` at `~/.pi/agent/extensions/auto-compact-resume`.
8. Enforce per-machine MCP parity: every MCP available to Claude Code and/or Codex on a machine is also available to OpenCode, Droid, and Pi on that machine. Preserve target-only MCPs.
9. Generalize Pi HTTP MCP rendering for optional headers with OAuth disabled, and Droid rendering so secret-header HTTP uses the existing bridge while headerless Memory Vault uses native HTTP.
10. Add exact regression oracles for extension packaging, every changed MCP selection, header/credential behavior, and one-repository update commands. Follow red-green TDD for behavior changes.
11. Read command environments from each current working tree’s direnv; never use `nix develop` or install dependencies on the fly. If environment dependencies change, regenerate with `de`, re-read direnv, and retry.
12. Preserve secrets and private CA boundaries; never read or decrypt `secrets.yaml`, expose credentials, or make local-only inputs silently break remote consumers.
13. Each logical work unit is committed, independently fess-audited, partner observations are cleaned up, and the branch is locally current with its base. No push or shared-history rewrite occurs without a human gate.
14. The full root build/check suite, focused extension tests, cross-platform evaluations, wrapper/resource tests, and every affected consumer evaluation pass with fresh evidence.
15. A final literal-reference audit leaves no live `ai-nix`, `AI_NIX`, sibling-path, retired CLI-flag, or old-URL dependency except intentional compatibility aliases and clearly marked historical records.
16. `~/src/ai-nix` and its worktrees are retired only after their clean/branch/unintegrated-work state is proven and all source/history is recoverable from the unified repository; use a reversible archive step before deletion.
17. The final work commit passes fess, no actionable partner observation remains, and parity checks prove both the old `ai-nix` contract and the approved per-machine MCP contract.
18. Preserve evidence that `pi-subagent` launches headless Pi RPC child processes rather than tmux panes and that `pi-btw` was planned but never implemented or installed; do not fabricate or package a nonexistent extension, and identify the remaining implementation gap explicitly.
19. Write a comprehensive Markdown audit under `~/dl` covering prompts, commands, agents, skills, MCP servers, extensions, and gaps for every configured tool/host combination. The audit must use fresh tmux sessions for each applicable combination, invoke each tool's own introspection capabilities, distinguish expected from observed resources, and record every unresolved hole.
20. Preserve Codex's Nix-managed LiteLLM default at GPT-5.6 Sol with `ultra` reasoning while retaining writable host-local runtime selection; automated tests and a fresh interactive acceptance session must prove model/reasoning changes no longer collide with immutable Nix configuration.
21. Carry the evidence-backed LiteLLM attribution into the final report: Opus 4.7 came from Vulcan `stock-trader`, historical Haiku came from DEVONthink and OpenCode, `10.0.2.100` is rootless Podman's synthetic `tap0`, and `hera_vibe_proxy_credential` is the outbound deployment credential name.
22. Reconcile Anvil source/profile provenance, the pre-existing orphan stdio process, and the clean/SIGKILL tmux lifecycle evidence before making any final hardening claim. Fresh acceptance must leave no unexplained process or instance residue attributable to the tested generation.
23. Replace Superpowers globally with Bigpowers for Claude, Codex, OpenCode, Droid, and Pi. Remove the live Superpowers input, copied skills, `using-superpowers` bootstrap, and Claude plugin; project the complete frozen Bigpowers 80-skill/80-prompt release without namespace collisions. Historical Superpowers plans remain historical records, not live resources.
24. Reproducibly package and enable through Nix: `pi-hashline-edit-pro`, `pi-web-access`, `pi-lens`, `bigpowers`, `@dietrichgebert/ponytail`, `@quintinshaw/pi-dynamic-workflows`, `pi-agent-browser-native`, and `pi-lean-ctx`. Use immutable sources and complete production closures; perform no runtime npm/git installation and do not give Pi's package reconciler ownership of mutable `settings.json`.
25. Add a version- and digest-guarded one-argument `ExtensionAPI.registerToolRenderer(wrapper)` ABI to the exact Pi 0.81.1 Nix package, matching `pi-quiet`'s wrapper contract and exposing an exact capability marker that cannot false-positive on a two-argument ABI. After normal slot inheritance, wrappers compose in extension registration order for built-in, extension, SDK, MCP, and dynamically registered tools. Tests must preserve execution, schemas, active-tool state, result bytes, `renderShell`, every callback argument, full render context, row state, `lastComponent`, partial/expanded/error/image rendering, reload, HTML export, and safe fallback to the previous renderer when a wrapper throws.
26. Enforce exact package ownership in executable tests. Hashline alone owns `read`, `replace`, and `undo_last_replace` and intentionally deactivates `edit`; `pi-quiet` must use the renderer seam rather than compete for built-in execution. Web Access alone owns `web_search`, `fetch_content`, and `get_search_content`. Ponytail has one canonical six-skill source while its extension is enabled. Dynamic Workflows cannot recursively invoke the existing `subagent`. `pi-lean-ctx` reuses native `lean-ctx`, and its embedded bridge is the sole Lean MCP owner—no duplicate adapter entry. Browser Native uses exactly `agent-browser` 0.33.0 plus declarative Chromium. Hashline and Lens both load while their known immediate-`replace` Lens gap is explicitly reported.
27. Disable Pi Lens's npm/npx/Python/native-package/GitHub-release runtime installers and downloaders; provide the approved analysis/LSP/format/security tools declaratively on `PATH`, and degrade unavailable optional tools without mutation. Language-gated acceptance must exercise those branches with failing installer/network sentinels and prove `~/.pi-lens/bin` and package caches remain unchanged.
28. Build and load the patched Pi and every requested package on `aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`; run aggregate offline package discovery with failing installer/network sentinels, Home Manager evaluation, authorized activation, fresh Pi introspection, and unchanged mutable credential/session/trust state.

## Planned Work Units

1. Resolve the portability/history architecture through mandatory PAL consensus.
2. Establish the feature branch, baseline checks, compatibility oracle, and history-preserving merge point.
3. Integrate AI overlays, patches, package/resource derivations, helper library, tests, and output compatibility.
4. Convert the root configuration and operational scripts to one-repository behavior.
5. Package `auto-compact-resume` and implement MCP parity with renderer support.
6. Update and verify downstream consumer flakes and locks.
7. Consolidate active documentation, CI, and hooks; mark historical records accurately.
8. Run full cross-platform and consumer verification, audits, partner cleanup, and local restack.
9. Reversibly archive the standalone checkout and remove live user-state references after proving recoverability.
10. Remove live Superpowers ownership and project the complete Bigpowers skills/prompts across every configured agent tool.
11. Build the eight immutable Pi package roots, package their fixed dependencies/native tools, and generate one Nix-owned Pi gallery projection extension without touching mutable package settings.
12. Patch and verify Pi 0.81.1's renderer-wrapper ABI, then integrate package resources, native `lean-ctx`, `agent-browser`, Chromium, and exact conflict policy into Home Manager.
13. Run full cross-system package/load checks and authorized activation, then the fresh-tmux cross-host/tool introspection matrix and comprehensive `~/dl` audit, including Codex runtime switching, LiteLLM attribution, Anvil cleanup, `pi-subagent`, and missing `pi-btw` conclusions.

## Selected Architecture

Use a thin portable subflake under `config/ai` within this repository. Remote AI consumers use the repository directory flake, while the host-local root flake and the portable subflake import one canonical implementation tree. The subflake is an export and input boundary only: it must not acquire a separate package inventory, implementation copy, CI workflow, documentation hierarchy, or update workflow. Its lock records only portable AI inputs; the root lock remains authoritative for Hera and Clio host configuration.

The two-model PAL workflow completed successfully through LiteLLM on 2026-07-23. `gpt-5.5-pro` recommended the thin subflake; `gemini-3.1-pro-preview` recommended caller-supplied `flake = false` inputs. The final synthesis selects the subflake because frozen criterion 5 requires preserving all observed `ai-nix` flake outputs. The caller-supplied-only design would intentionally remove that contract and spread compatible-input coordination across every consumer. Making the root flake portable remains rejected because its machine-local application inputs and private CA are valid host concerns whose refactoring would add risk unrelated to AI portability.

The selected boundary has these invariants:

- The portable subflake contains only remote-safe AI inputs and preserves the existing `overlays`, `lib`, `packages`, `checks`, `apps`, `formatter`, and `devShells` contracts where currently published.
- AI overlays, package constructors, patches, resources, and tests have one implementation location in the root repository and are imported by both flake surfaces.
- The portable input graph contains no root-only `git+file` input, private CA, credential, or host configuration.
- The root composes each AI overlay exactly once and preserves caller overlay ordering.
- Flake-true AI and flake-false source consumers pin the same repository revision during migration; each downstream retains its own lock.
- Active CI, hooks, update commands, package inventory, and maintenance documentation remain root-owned.
- The standalone `ai-nix` checkout is not retired until compatibility, history recoverability, downstream locks, and the final literal-reference audit all pass.

## Pi Package and Methodology Architecture

Bigpowers replaces Superpowers globally. Bigpowers `2.82.3` (source commit `960ab5283e7b7766f02fbf8703da5bb6e997159d`) is the sole live methodology bundle; its complete 80 skills and 80 prompts are mapped into each client's native resource namespace. The Superpowers input, resource copies, `using-superpowers` skill, and Claude marketplace plugin are removed. Historical files that mention Superpowers retain archival context rather than being rewritten as if the old work used Bigpowers.

Each requested Pi package is a complete immutable Nix package root with an exact source, license, manifest, and dependency closure. One generated `nix-gallery` extension imports package extension factories in frozen order and returns selected skill/prompt/theme paths through `resources_discover`. Home Manager owns that generated extension leaf; Pi's mutable `settings.json`, package caches, credentials, sessions, and trust state remain unmanaged. No activation runs `pi install`, npm, npx, git reconciliation, browser installers, or package updater CLIs.

The frozen package set begins with `pi-hashline-edit-pro` 0.17.5, `pi-web-access` 0.13.0, `pi-lens` 3.8.71, Bigpowers 2.82.3, `@quintinshaw/pi-dynamic-workflows` 3.4.1, `pi-agent-browser-native` 0.2.72 paired with `agent-browser` 0.33.0, and `pi-lean-ctx` 3.9.12 paired with the existing native `lean-ctx` 3.9.12. Ponytail reuses the repository's newer pinned source for both its extension and the six canonical static skills; package skill discovery is suppressed so no duplicate names or divergent instruction copies exist. Hashline is the sole read/edit workflow owner, Web Access is the sole owner of its three web tools, and Lean Ctx's embedded bridge—not a second MCP-adapter registration—is the sole Lean tool source. Lens runtime installers are disabled; only declaratively packaged PATH tools may execute.

Pi 0.81.1 has no upstream `registerToolRenderer` method. The requested seam is therefore a private, exact-version Nix patch implementing the one-argument global wrapper ABI feature-detected by `pi-quiet`; it is not misrepresented as an upstream release. The patch composes wrappers deterministically after ordinary slot inheritance, affects rendering only, and is guarded by source digests and behavioral tests so a future Pi update fails closed until rebased.
