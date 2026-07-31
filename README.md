# nix-config

Personal, multi-host Nix configuration for Darwin, standalone Home Manager, NixOS consumers, and portable AI tooling.

## Configuration owners

| Consumer | Platform | Authoritative checkout | How this repository is used |
|---|---|---|---|
| Hera | aarch64-darwin | `~/src/nix` | Direct `darwinConfigurations.hera` |
| Clio | aarch64-darwin | `~/src/nix` on Clio | Direct `darwinConfigurations.clio` |
| Andoria-08/T2, Delphi, GPU | x86_64 Linux | `~/.config/home-manager` on the shared-work hosts | Paired root source and portable input; legacy `dir=config/ai` edges migrate atomically to `dir=config/fleet` |
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
nix flake check ./config/fleet --all-systems --no-build

# Format/lint through repository hooks
lefthook run pre-commit --all-files
```

System and Home Manager switches are owned by each authoritative checkout. Build first. NixOS hosts use their `.nixos-build` lock protocol.

## Updates

- `bin/update` owns the isolated update transaction for both lock files and every automatic catalog pin; targeted and dry-run modes remain available for review.
- `make update` runs the complete sequence: fast-forward, update, validate, signed candidate commit, exact-candidate build and switch, then fast-forward and push. Homebrew runs separately after the repository transaction.
- `bin/update-overlay --inventory --json` validates and lists every catalog-owned update target. Inventory and execution derive exclusively from `sources/*.json`; every inventoried target is executable, with no Nix-overlay discovery or secondary update manifest.

## Structure

| Path | Purpose |
|---|---|
| `flake.nix` | Root systems, packages, checks, and exported Home Manager module |
| `config/` | Shared Home Manager/Darwin policy and AI catalog/renderers |
| `config/fleet/` | Portable AI subflake, models, profiles, resources, and client adapters |
| `overlays/` | Root and AI package overrides/composition |
| `packages/` | Package implementations and immutable Pi gallery |
| `test/` | Root, portable, wrapper, renderer, and activation contracts |
| `bin/` | Operator and maintenance commands |
| `doc/` | Current architecture, runbooks, and active work |

See [`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md) for ownership and data flow and [`doc/CURRENT-WORK.md`](doc/CURRENT-WORK.md) for the active local work boundary. Git history is the archive for completed plans and handoffs.

## Safety

- Never print or commit credentials, private keys, decrypted SOPS content, request payloads, or session transcripts.
- Never edit generated store paths or generated symlinks directly.
- Preserve mutable agent state, tmux sessions, caches, auth, trust, reports, and workflows.
- Review Git status and exact staged paths before every commit.

## License

BSD 3-Clause. See [`LICENSE.txt`](LICENSE.txt).
