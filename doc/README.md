# nix

I've been managing my macOS and NixOS systems with Nix for about twelve years
now. This repository holds the result -- a flake-based configuration that
handles everything from system preferences to Emacs packages across multiple
machines.

The setup uses [nix-darwin](https://github.com/LnL7/nix-darwin) for macOS,
[NixOS](https://nixos.org) for my server, and
[home-manager](https://github.com/nix-community/home-manager) for user-level
configuration on both. It's nothing fancy, but it's reliable enough that I
rarely think about it anymore -- which is pretty much the highest praise I can
give a system configuration tool.

## Hosts

- **hera** and **clio**: Apple Silicon Macs (aarch64-darwin)
- **vulcan**: NixOS server (separate flake in `nixos/`)

## Usage

```bash
# Build without switching (always test first)
./build system

# Build and switch the running system
make switch

# Update all flake inputs and Homebrew
make update

# Full upgrade: update, switch, and verify
bin/upgrade hera
```

There's also a `bin/u` utility that wraps common maintenance tasks:

```bash
u switch    # Build and switch
u check     # Verify store integrity
u clean     # Remove old generations
u repl      # Open Nix REPL with system packages
```

## Structure

- **flake.nix** -- top-level flake defining Darwin configurations
- **config/** -- system (`darwin.nix`), user (`home.nix`), and package
  (`packages.nix`) settings, plus per-host overrides
- **overlays/** -- custom package overlays, numbered for load order (`00-`
  through `30-`). This is where most customization happens.
- **bin/** -- utility scripts for building, upgrading, and managing
  environments
- **nixos/** -- separate NixOS flake for vulcan

## Development

Enter a shell with all the linting and formatting tools:

```bash
nix develop
```

Format all Nix files:

```bash
nix fmt
```

Run all checks:

```bash
nix flake check
```

Pre-commit hooks run automatically via
[lefthook](https://github.com/evilmartians/lefthook):

```bash
lefthook install
```

## License

BSD 3-Clause. See [LICENSE.md](LICENSE.md).
