# Architecture

## Purpose

This repository owns shared Nix configuration and package implementation for two Darwin systems, several external Home Manager/NixOS consumers, and a portable AI toolchain. The central design constraint is **one implementation revision with separate consumer locks and activation authority**.

## Configuration flows

### Darwin

```text
flake.nix
  -> darwinConfigurations.{hera,clio}
  -> config/darwin.nix
  -> Home Manager config/home.nix
  -> config/johnw.nix + config/packages.nix
  -> config/ai.nix
```

Hera and Clio are direct root-flake outputs. Only their authoritative checkout may switch them.

### Portable AI

```text
config/ai/flake.nix
  -> flake-ai.nix
  -> flake/ai.nix
  -> overlays/ai/default.nix
  -> packages + checks + apps
```

The portable subflake has its own lock for remote-safe consumption. Root and portable shared inputs must remain coherent, but host-only inputs never belong in the portable boundary.

### External consumers

```text
consumer flake
  nix-config     = root source/module
  nix-config-ai  = same revision, dir=config/ai
  -> consumer-owned overlays and Home Manager/NixOS activation
```

Andoria/Delphi/GPU own standalone Home Manager checkouts. Vulcan/VPS own NixOS checkouts. This repository exports implementation and modules; it does not own their lock history or activation state.

## Module ownership

| Module | Owns | Must not own |
|---|---|---|
| `config/ai/catalog.nix` | Profiles, selectors, resources, validation | Client serialization or package builds |
| `config/ai/renderers/*` | One client's generated documents | Global resource selection |
| `config/ai.nix` | Home Manager composition/ownership guards | Package implementation |
| `flake/ai.nix` | Portable package/app/check composition | Host activation and root lock policy |
| `packages/*` | Build/runtime implementation | Host selection |
| `overlays/*` | Ordered exposure and narrow overrides | Broad hidden configuration channels |
| `test/*` | Interface and integration contracts | Duplicate production algorithms as oracles |
| `bin/*` | Explicit operator transactions | Undocumented cross-repository mutation |

## AI configuration flow

```text
model-registry.json + model-policy.nix
  -> models.nix
  -> catalog.nix selects per profile
  -> renderer adapters
  -> collision-checked generated leaves
  -> Home Manager preflight and activation
```

Nix owns generated leaves, not mutable roots. Auth, history, sessions, caches, reports, trust state, and user settings remain writable and outside generated ownership.

## Package and overlay flow

`config/overlays.nix` is the full-host overlay authority. It lists four phases explicitly: foundation, optional Vulcan CA, feature packages, and AI packages. Darwin pins and repairs are wrapped at the composition boundary, while the cross-platform Eask package has its own overlay. Input-consuming overlays are factories receiving only their declared sources; flake inputs are never published through `pkgs.inputs`. Tests require every numbered root and AI overlay to appear exactly once in its manifest and compare Darwin-only package behavior with stock nixpkgs on both Linux systems.

Package selection is explicit. `config/packages.nix` allows only named source-project inputs; package-shaped infrastructure inputs cannot enter a user profile. Agent Deck, Plasma Fractal, and Plasma Wiki remain installed on every profile where they were previously available, but their owning Home Manager modules make that selection explicit. Only the Agent Deck Discord bridge and Hera-specific Fractal wrappers/skill projections are Hera-only. `packages/ai-package-policy.nix` owns shared AI capability gates and optional package groups. `packages/pi-gallery/manifest.nix` owns the immutable gallery's member identity, source, version, extension, skills, projection, and registration order.

Package rules:

1. New independent derivations live under `packages/`.
2. Overlays expose those derivations or apply one narrow compatibility override.
3. Platform fixes are gated at the platform seam.
4. Package availability is not installation policy; owning feature/host modules select packages explicitly.
5. Updateable sources have one version/hash/update authority.

## Source catalog

The migration target is for all hand-maintained coordinates for Internet-fetched, future-upgraded package sources to live in data-only JSON files under `sources/`. Anvil is the first migrated category; remaining categories are tracked per-category in the [Fleet Configuration Programme](https://github.com/users/jwiegley/projects/9) under the `epic:2-update-authority` label. Category-local derivations keep their native Nix fetcher and build logic; they load records through `packages/source-catalog.nix`.

A record uses `schemaVersion = 1` at the category-file level and contains a stable ID with `fetcher`, canonical `url`, fetcher coordinates (`owner`, `repo`, `rev` as applicable), `hash`, optional `version`/`date`, and a closed `update.kind`. To add a source:

1. Add its record to the appropriate `sources/<category>.json` file, or create that JSON category file.
2. In the derivation, load the category with `import ../source-catalog.nix "category"` (adjusting the relative path) and pass the record's existing fields to the same native fetcher.
3. Run `bin/update-overlay --inventory`, the updater unit tests, and an exact pre/post derivation-path comparison.

Do not add package builders, patches, platform policy, gallery projections, shell commands, or runtime service URLs to the catalog. Generated npm/Cargo/flake locks remain beside their consumers as updater-owned projections. `bin/update-overlay` validates duplicate IDs, schema, fetcher-specific fields, HTTPS upstream identity, hashes, and update strategy before inventory or network work.

## State boundaries

- Agent Deck and tmux use `/tmp` as the persistent fleet socket parent; this avoids PAM/logind lifetime coupling.
- Anvil dedicated processes own isolated runtime/state roots and must not disturb interactive Emacs.
- Generated agent configuration uses preflight collision guards before Home Manager linking.
- Environment credentials are references only; secret values never enter Nix derivations or argv.
- Mutable profiles are migrated atomically and preserve the last usable state on failure.

## Verification tiers

| Tier | Purpose | Typical owner |
|---|---|---|
| Fast | Formatting, lint, parsing, focused units | pre-commit |
| Contract | Wrappers, renderers, Home integration, model sync, package selection | CI/pre-push |
| Runtime | Native platform/process behavior | native builders |
| Resilience | Repeated recovery/latency/leak campaigns | scheduled/release |

Names must represent distinct evidence. A coverage/fuzz/memory/soak label may exist only when that behavior actually runs.

## Change rules

- Change one authority, derive every projection.
- Fix shared behavior once at its narrowest seam.
- Search maintained external consumers before deleting compatibility.
- Keep activation reversible and consumer-owned.
- Record current decisions in current docs; move completed execution detail to Git history or an explicit archive.

## Current remediation

Fleet and architecture work is tracked issue-by-issue in the [Fleet Configuration Programme](https://github.com/users/jwiegley/projects/9). Each issue owns its own evidence, acceptance criteria, verification commands, rollback, and authorization boundary. [GitHub issue #15](https://github.com/jwiegley/nix-config/issues/15) is the archived 2026-audit record: it retains the completed findings, the per-work-unit signed-commit evidence, the audit baseline, and the deliberate `a88a77ba`/`a98385b9` revert evidence. It is historical evidence, not current authority. Issues concerning only vulcan's NixOS configuration are filed in [jwiegley/nixos-config](https://github.com/jwiegley/nixos-config/issues).
