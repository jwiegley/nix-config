# Fleet Model Defaults Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `llm-setup.el` authoritative for Claude and Vulcan's default
LLM while removing migration snapshots that break normal model or asset
updates.

**Architecture:** `llm-setup-reset` continues publishing deterministic,
pretty JSON to `nix/config/ai/model-registry.json`. Shared Nix validates and
renders that registry; Vulcan projects its locked `nix-config` input into the
legacy service shape without a second generated model file.

**Tech Stack:** Emacs Lisp and ERT, Nix and Home Manager, NixOS flakes.

## Global Constraints

- Claude primary is exactly `claude-opus-4-8[1m]`.
- Claude subagents use exactly `claude-opus-4-8`.
- Claude Haiku selection remains unchanged.
- `llm-setup-reset` must not write `models.yaml`, invoke Nix, commit, push, or
  contact hosts.
- Vulcan accepts only a `litellm` general default because its consumers call
  the local LiteLLM endpoint.
- Retry policy, OpenClaw transport metadata, and `hera/bge-m3` remain
  Vulcan-owned policy.
- Keep ordinary flake locks and fixed-output hashes; remove only manually
  maintained migration snapshots.
- Do not modify or invoke Promptdeploy.

---

### Task 1: Publish the requested Claude selections

**Files:**
- Modify: `/Users/johnw/src/dot-emacs/lisp/llm-setup/llm-setup.el`
- Modify: `/Users/johnw/src/dot-emacs/lisp/llm-setup/llm-setup-test.el`
- Modify: `/Users/johnw/src/nix/config/ai/model-registry.json`

**Interfaces:**
- Produces registry routes and `selections.claudeDefault` /
  `selections.claudeSubagent` consumed by shared Nix.

- [x] Add ERT assertions for both exact route IDs and the requested selections.
- [x] Run the focused ERT selector and confirm it fails because the routes and
  selections are absent.
- [x] Add the two Positron Anthropic instances and change only the primary and
  subagent defcustom defaults.
- [x] Run all ERT tests and the repository pre-commit gate.
- [x] Call `llm-setup-build-nix-model-registry` twice and verify the second run
  leaves inode, mtime, bytes, and Git status unchanged.

### Task 2: Replace brittle migration snapshots with invariants

**Files:**
- Modify: `/Users/johnw/src/nix/config/ai/catalog.nix`
- Modify: `/Users/johnw/src/nix/packages/ai-home-manager-smoke.nix`

**Interfaces:**
- Consumes the schema-v2 registry and immutable resource package.
- Preserves uniqueness, reference resolution, safety, structural resource, and
  rendered-selection checks without exact route/asset inventories.

- [x] Identify assertions tied to exact route counts, source-order sequences,
  semantic snapshot hashes, asset names/counts, and `expected_asset_digest`.
- [x] Replace them with tests that reject duplicates, dangling selections,
  unsafe credentials/URLs, malformed skills, escaping symlinks, forbidden
  artifacts, and incorrect rendered selections.
- [x] Run `nixfmt` and the focused `ai-home-manager-smoke` check.
- [x] Run the Nix repository's full pre-commit and flake checks.

### Task 3: Report every managed-path preflight obstruction precisely

**Files:**
- Modify: `/Users/johnw/src/nix/config/ai/preflight.nix`
- Modify: `/Users/johnw/src/nix/flake.nix`
- Modify: `/Users/johnw/src/nix/packages/ai-home-manager-smoke.nix`
- Add: `/Users/johnw/src/nix/packages/ai-managed-preflight-smoke.nix`

**Interfaces:**
- Runs before Home Manager's `checkLinkTargets` activation step.
- Distinguishes a blocking leaf from the exact blocking parent while accepting
  parent links owned by the immediately previous Home Manager generation.

- [x] Add regressions for multiple simultaneous failures, exact leaf and parent
  diagnostics, and a previous-generation `.pi` parent link.
- [x] Confirm the new regressions fail against the current fail-fast preflight.
- [x] Collect, sort, and deduplicate all independent diagnostics before one
  final failure; never follow a symlink ancestor to infer leaf ownership.
- [x] Preserve unrelated sibling state in shared Claude, Codex, OpenCode,
  Droid, Pi, and universal agent directories, including writable aliases.
- [x] Print a path-count progress message before every activation scan.
- [x] Split the fast `ai-managed-preflight-smoke` check from the broader
  cross-profile `ai-home-manager-smoke` check.
- [x] Run both the focused preflight harness and `ai-home-manager-smoke` check.

### Task 4: Project the shared default into Vulcan

**Files:**
- Modify: `/Users/johnw/src/vulcan-nixos/models.nix`
- Delete: `/Users/johnw/src/vulcan-nixos/models.yaml`
- Modify: `/Users/johnw/src/vulcan-nixos/flake.nix`
- Modify: every module in `/Users/johnw/src/vulcan-nixos/modules` that imports
  `models.nix`
- Add or modify: `/Users/johnw/src/vulcan-nixos/tests` focused projection check

**Interfaces:**
- Consumes `inputs.nix-config/config/ai/models.nix` and
  `modelData.selections.default`.
- Produces the existing `{ llm; embedding; }` compatibility value for all
  NixOS, Home Manager, microVM, and `/etc/models.json` consumers.

- [ ] Add a pure evaluation test showing a changed `litellm` default changes
  primary, fast, and agent names and effective limits.
- [ ] Confirm the test fails against the host-local `models.yaml` adapter.
- [ ] Make `models.nix` accept the locked `nix-config` source, resolve one exact
  provider/model pair, reject non-LiteLLM defaults, and derive context/output
  limits while preserving Vulcan policy.
- [ ] Pass the computed value through NixOS, Home Manager, and OpenClaw guest
  module arguments; remove stale `models.yaml` comments and the file itself.
- [ ] Run formatting, the focused projection test, `nix flake check`, and the
  Vulcan system build on Vulcan.

### Task 5: Publish and activate the fleet

**Files:**
- Update Git commits and ordinary flake locks only where their normal host
  update commands change them.

**Interfaces:**
- Publishes llm-setup first, then its parent gitlink, shared Nix, and Vulcan.
- Activates only configurations that already built successfully.

- [ ] Review all diffs and run a final cross-repository code review.
- [ ] Commit and push `llm-setup`, the parent `dot-emacs` gitlink, `nix`, and
  Vulcan main branches; verify `ai-nix` main is already published.
- [ ] Build and switch Hera, then verify `.agents/skills`, Claude settings,
  model registry, and activation health.
- [ ] Fast-forward Clio, build and switch it, then verify the same managed
  artifacts.
- [ ] On Vulcan, wait while `.nixos-build` exists, run the requested full flake
  update and guarded rebuild, verify `/etc/models.json`, and require zero failed
  systemd units.
- [ ] On Andoria-08, run the requested full flake update and Home Manager
  switch, then verify managed Claude/OpenCode settings.

Promptdeploy remains untouched throughout.
