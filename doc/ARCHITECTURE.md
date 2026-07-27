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

Package rules:

1. New independent derivations live under `packages/`.
2. Overlays expose those derivations or apply one narrow compatibility override.
3. Platform fixes are gated at the platform seam.
4. Package availability is not installation policy; owning feature/host modules select packages explicitly.
5. Updateable sources have one version/hash/update authority.

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

The frozen implementation plan is `ARCHITECTURE-REMEDIATION-WIGGUM-PLAN.md`; resume state is `ARCHITECTURE-REMEDIATION-WIGGUM-HANDOFF.md`.
