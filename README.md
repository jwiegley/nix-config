# nix-config

Personal, multi-host Nix configuration for Darwin, standalone Home Manager, NixOS consumers, and portable AI tooling.

## Configuration owners

| Consumer | Platform | Authoritative checkout | How this repository is used |
|---|---|---|---|
| Hera | aarch64-darwin | `~/src/nix` | Direct `darwinConfigurations.hera` |
| Clio | aarch64-darwin | `~/src/nix` on Clio | Direct `darwinConfigurations.clio` |
| Andoria-08/T2, Delphi, GPU | x86_64 Linux | `~/.config/home-manager` on the shared-work hosts | Paired `nix-config` source and `nix-config?dir=config/ai` inputs |
| Vulcan | aarch64 NixOS | `/etc/nixos` on Vulcan | Paired root/portable inputs plus shared Home Manager module |
| VPS | x86_64 NixOS | `/etc/nixos` on the VPS | Root/portable inputs plus shared Home Manager module |

The external checkouts own their locks and activation. Do not overwrite them from a secondary local clone.

Shared-work Home Manager consumers must declare their role explicitly when importing `config/johnw.nix`:

```nix
extraSpecialArgs = {
  inherit hostname inputs;
  nixManagedAiHomeClass = "shared-work";
};
```

Accepted classes are `clio`, `hera`, `shared-work`, `vps`, `vulcan`, and the synthetic `personal-linux` fixture. Ordinary named hosts fall back to their hostname; shared-work checkouts must pass the class because their machine hostnames are intentionally not profile identities.

## Common commands

Run commands from this repository with its direnv loaded. Do not use `nix develop` as an ad-hoc command wrapper.

```bash
# Build Hera/Clio without switching
./build system

# Focused package builds
./build pkg PACKAGE
./build python PACKAGE
./build haskell PACKAGE

# Core AI contracts
make test

# Portable evaluation
nix flake check ./config/ai --all-systems --no-build

# Format/lint through repository hooks
lefthook run pre-commit --all-files
```

System and Home Manager switches are owned by each authoritative checkout. Build first. NixOS hosts use their `.nixos-build` lock protocol.

## Updates

- `bin/update-agents` atomically updates executable shared inputs and, by default, leaves reviewable changes without pull/commit/switch/push/Homebrew side effects. Those actions require explicit flags.
- `make update` delegates the all-input root/portable transaction to the same command.
- `bin/update-overlay --inventory --json` validates and lists every catalog-owned update target. Inventory and execution derive exclusively from `sources/*.json`; every inventoried target is executable, with no Nix-overlay discovery or secondary update manifest.

## Structure

| Path | Purpose |
|---|---|
| `flake.nix` | Root systems, packages, checks, and exported Home Manager module |
| `config/` | Shared Home Manager/Darwin policy and AI catalog/renderers |
| `config/ai/` | Portable AI subflake, models, profiles, resources, and client adapters |
| `overlays/` | Root and AI package overrides/composition |
| `packages/` | Package implementations, immutable Pi gallery, and Anvil runtime |
| `test/` | Root, portable, wrapper, renderer, and activation contracts |
| `bin/` | Operator and maintenance commands |
| `doc/` | Durable architecture and historical evidence |

See [`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md) for ownership and data flow. Fleet and architecture work is tracked issue-by-issue in the [Fleet Configuration Programme](https://github.com/users/jwiegley/projects/9); [GitHub issue #15](https://github.com/jwiegley/nix-config/issues/15) is the archived 2026-audit record, retained as historical evidence. The programme's design corpus is [`doc/FLEET-DESIGN-PLAN.md`](doc/FLEET-DESIGN-PLAN.md) and [`doc/FLEET-PROGRAMME-CROSS-STREAM.md`](doc/FLEET-PROGRAMME-CROSS-STREAM.md).

## Safety

- Never print or commit credentials, private keys, decrypted SOPS content, request payloads, or session transcripts.
- Never edit generated store paths or generated symlinks directly.
- Preserve mutable agent state, tmux sessions, caches, auth, trust, reports, and workflows.
- Review Git status and exact staged paths before every commit.

## License

BSD 3-Clause. See [`LICENSE.txt`](LICENSE.txt).
