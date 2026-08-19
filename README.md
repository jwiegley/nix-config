# nix-config

This repository is the configuration and package authority for John's Darwin
systems, external Home Manager and NixOS consumers, and portable AI tooling. It
defines shared policy once, exposes a separately lockable AI boundary, and leaves
each host in control of its own lock, activation, rollback, and mutable state.

## Architecture

The repository is arranged as a sequence of explicit authorities:

```text
sources/*.json
    -> packages/source-catalog.nix
    -> packages/* and overlays/*
    -> flake/ai.nix
       |-> config/ai/flake.nix        portable package boundary
       `-> flake.nix                  root systems, modules, checks, and apps
             |-> Hera and Clio        direct nix-darwin consumers
             `-> exported modules     external NixOS and Home Manager consumers

config/ai/catalog.nix and renderers
    -> config/ai.nix                  Home Manager AI policy and generated leaves
    -> direct and external consumers
```

The layers have distinct responsibilities:

| Layer | Authority |
| --- | --- |
| Source catalogs | Updateable source coordinates, versions, and dependent hashes |
| Packages and overlays | Reusable derivations, package sets, compatibility corrections, and package exposure |
| Portable AI implementation | AI packages, applications, checks, overlays, and wrappers shared by both flakes |
| AI Home Manager policy | Profiles, resource selection, client renderers, generated leaves, and activation safeguards |
| Root flake and modules | Darwin systems, shared Home Manager policy, host capabilities, and repository checks |
| Consumer checkouts | Lock selection, build, activation, rollback, and host-local state |

Package availability is separate from installation policy. The portable flake may
export a package without assigning it to a host; the owning host or feature module
makes that selection explicitly. Prime Agent is initially selected only for Hera:
its source-built package, managed-settings overlay, model/provider overrides, prompt
commands, RLM specialist adapters, skills, theme, keybindings, and MCP adapter are
managed. Its writable preference/onboarding settings, daemon, kernel, authentication,
continual harness, history, sessions, caches, logs, and refinements remain mutable.
The root flake exports `obr`, and the dedicated root module selects it for every
managed home. Nix owns the executable; each machine's ignored `.obr/` cache and
each repository's tracked `PLAN.org` remain mutable project state. Consumers
that import this repository with `flake = false` declare `obr` as a direct input
and pass it through their Home Manager module arguments; their lock adoption
remains consumer-owned.

The managed Pi profile makes the same complete 26-member extension gallery
available on every host. Pi Lens and Pi Mem remain packaged and projected but are
excluded from automatic registration while their startup costs are isolated.
Darwin registers the two loopback discovery providers automatically; fixed
local-provider overrides and the synthetic router remain a separate catalog
capability, presently enabled only for Hera.

The complete ownership and data-flow contract is maintained in
[`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md).

## Configuration owners

| Consumer | Platform | Authoritative checkout | Consumption model |
| --- | --- | --- | --- |
| Hera | aarch64-darwin | `~/src/nix` | Direct `darwinConfigurations.hera` output |
| Clio | aarch64-darwin | `~/src/nix` on Clio | Direct `darwinConfigurations.clio` output |
| Andoria-08, Andoria-T2, Delphi-3BD4, GPU Server | x86_64 Linux | `~/.config/home-manager` on the shared-work hosts | Active shared-work standalone Home Manager rollout |
| Git AI | x86_64 Linux | `~/.config/home-manager` on Git AI | Dormant shared-work member; excluded from the active rollout |
| Vulcan | aarch64 NixOS | `/etc/nixos` on Vulcan | External NixOS consumer plus the shared Home Manager module |
| VPS | x86_64 NixOS | `/etc/nixos` on VPS | Parked external consumer; retained for explicit manual updates |

An external consumer pins the root input and its `dir=config/ai` input at the
same repository revision. The consumer owns both lock entries and must update
them together. A secondary clone must never overwrite an authoritative checkout.

Shared-work consumers identify their policy class explicitly when importing
`config/johnw.nix`:

```nix
extraSpecialArgs = {
  inherit hostname inputs;
  nixManagedAiHomeClass = "shared-work";
};
```

Accepted classes are `clio`, `hera`, `shared-work`, `vps`, `vulcan`, and the
synthetic `personal-linux` evaluation fixture. Shared-work machine names are not
profile identities and therefore must not be allowed to fall through to hostname
selection.

Canonical shared-work membership contains the four active machines plus dormant
`git-ai`. Membership records identity only: it does not assert that a host is
online or include it in a rollout. The active rollout remains the explicit
four-host subset in `config/hosts/registry.nix`.

## Operations

The full operator reference is [`bin/README.md`](bin/README.md). It records every
command under `bin/`, every public Make target, the flake applications, their
intended use, and their material cautions.

The principal local commands are:

```sh
# Build the complete current Darwin system without activating it.
./build system

# Run the bounded essential commit gate.
lefthook run pre-commit --all-files

# Run the principal repository contracts.
make test

# Evaluate the portable AI boundary on all declared systems.
nix flake check ./config/ai --all-systems --no-build

# Update all flake inputs and automatic catalog targets; validate, sign, switch, and publish.
make update

# Show the same transaction's progress and successful no-op diagnostics.
make update-verbose
```

The quiet command streams one dot per work item as processing proceeds. After the
transaction succeeds, it prints one old-to-new line for each accepted version
or revision change; unchanged items remain silent. Failures and held-back
warnings remain visible. `make update-verbose` retains the detailed display.
`make update` is a repository transaction, not a whole-fleet deployment. External
consumers must adopt the published revision in their own locks and activate it
from their authoritative checkouts. Vulcan must use its local `./build` driver.
The parked VPS is excluded from default cross-consumer evaluation and
`update-remote` activation; its same driver remains the supported path when a
manual update is deliberately resumed.

## Repository layout

| Path | Purpose |
| --- | --- |
| `flake.nix` | Root systems, packages, applications, checks, and exported Home Manager module |
| `flake/` | Reusable flake implementation, including portable AI composition |
| `config/` | Shared Home Manager, Darwin, host, package-selection, and AI policy |
| `config/ai/` | Separately lockable portable AI flake, profiles, resources, renderers, prompts, commands, skills, and themes |
| `overlays/` | Ordered package exposure, compatibility corrections, and narrow integration-owned definitions |
| `packages/` | Reusable derivations, package policy, source loading, and the Pi extension gallery |
| `sources/` | Machine-readable update authority for manually tracked sources and versions |
| `test/` | Evaluation, build, security, command, and runtime-behavior checks; see [`test/README.md`](test/README.md) |
| `bin/` | Operator transactions, activation helpers, publication, and maintenance commands |
| `doc/` | Architecture, runbooks, active plans, security records, and focused operational documentation |

The root [`flake.nix`](flake.nix) composes the consumers. Shared cross-platform
policy begins in [`config/johnw.nix`](config/johnw.nix); Darwin adds
[`config/home.nix`](config/home.nix) and [`config/darwin.nix`](config/darwin.nix).
The portable AI boundary enters through [`config/ai/flake.nix`](config/ai/flake.nix)
and is implemented by [`flake/ai.nix`](flake/ai.nix).

## Repository authority

The sole fetch and push authority is the `origin` remote at
`gitea@gitea:johnw/nix-config.git`. GitHub must not be configured as a remote.

## Verification model

Verification is intentionally layered:

| Evidence | Establishes | Does not establish |
| --- | --- | --- |
| Evaluation | The configuration can be constructed | Derivation success or runtime behavior |
| Build | The selected closure can be realized | Activation on any host |
| Activation | A host selected the new generation | Client or service health |
| Publication | The Gitea authority contains the signed revision | Consumer adoption |
| Runtime acceptance | The affected executable or service works on the active generation | Health on another host |

The ordinary pre-commit gate has a three-minute outer envelope while its fast
Python suite keeps a separate two-minute deadline. Broader portable,
cross-consumer, and native build assurance belongs at issue
closeout or on the scheduled cadence. No single local check constitutes
whole-fleet runtime proof.

## Documentation

- [`doc/USER-GUIDE.md`](doc/USER-GUIDE.md) — architecture, repository relationships, trust, updates, activation, rollback, and security
- [`bin/README.md`](bin/README.md) — complete command and operational reference
- [`test/README.md`](test/README.md) — verification scope and maintainability policy
- [`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md) — ownership, data flow, rollout, and state boundaries
- [`doc/PLAN.org`](doc/PLAN.org) — tracked `obr` issue surface and current-work authority
- [`doc/Pi Coding Agent Extensions.md`](<doc/Pi Coding Agent Extensions.md>) — managed Pi extension inventory

`obr` and `doc/PLAN.org` are the sole current-work authority. Git history is the
archive for completed plans and handoffs; architecture documents describe the
present system rather than preserving obsolete execution narratives.

## Safety

- Never print or commit credentials, private keys, decrypted secret material,
  request payloads, or session transcripts.
- Never edit Nix store paths or generated symlinks directly.
- Preserve mutable agent state, tmux sessions, caches, authentication, trust,
  reports, and workflows.
- Keep publication, activation, and destructive maintenance independently
  authorized.
- Inspect `git status` and the exact staged paths before every commit.

## License

BSD 3-Clause. See [`LICENSE.txt`](LICENSE.txt).
