# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a personal Nix configuration repository for managing macOS (Darwin) and NixOS systems using Nix flakes, nix-darwin, and home-manager. The configuration manages three macOS hosts (hera, clio, athena) and one NixOS host (vulcan).

## Working with Nix: Use Specialized Tools

**IMPORTANT**: For any Nix-related tasks in this repository, you should proactively use the specialized Nix agent and tools:

- **nix-pro subagent**: An expert agent specialized in NixOS, nix-darwin, home-manager, flakes, and the Nix language. Use this agent for:
  - Modifying Nix configurations (flake.nix, darwin.nix, home.nix)
  - Writing or debugging overlays
  - Understanding Nix expressions and derivations
  - Troubleshooting build failures
  - Package management and module development

- **/nixos slash command**: Use this command for Nix-specific queries and tasks, such as:
  - Searching for packages: `/nixos search <package-name>`
  - Finding configuration options: `/nixos search <option-name>`
  - Getting package version information
  - Researching Home Manager options
  - Looking up nix-darwin settings

These specialized tools have access to comprehensive Nix documentation and can provide more accurate, idiomatic solutions for Nix-related work.

## Commands

### Building and Switching Configurations
```bash
# Build and switch Darwin configuration (main command)
u switch

# Just build without switching (ALWAYS TEST THIS FIRST)
./build system

# Update flake inputs and brew packages
make update

# Full upgrade: update, switch, and check
upgrade hera
```

### Maintenance Commands
```bash
# Verify Nix store integrity
u check

# Clean old generations (default: 14 days)
u clean

# Remove all but current generation
u purge

# Sign store paths with local key
u sign

# Copy store paths to remote hosts
 copy

# Prepare all projects for travel (rebuild direnv caches)
u travel-ready
```

### Development
```bash
# Open Nix REPL with current system packages
u repl

# Rebuild direnv cache for current project
./bin/de [--no-cache]
```

## Architecture

### Core Structure
- **flake.nix**: Main Darwin flake defining system configurations for macOS hosts
  - Defines darwinConfigurations for hera, clio, and athena
  - Imports home-manager as a Darwin module
  - Specifies flake inputs (nixpkgs, nix-darwin, home-manager, emacs-overlay, etc.)
  - Loads all overlays from the `overlays/` directory

- **nixos/flake.nix**: Separate flake for NixOS configuration (vulcan host)
  - Independent flake with its own inputs and lock file
  - Uses nixosSystem instead of darwinSystem
  - Shares some overlays but has NixOS-specific modules

- **config/**: Host-specific and shared configuration files
  - `darwin.nix`: System-level Darwin configuration (users, fonts, services, system preferences)
  - `home.nix`: User-level home-manager configuration (shell, git, development tools)
  - `packages.nix`: User package declarations (imported by home.nix)
  - `{hostname}.nix`: Host-specific overrides (e.g., hera.nix, clio.nix)
    - Merged with shared config using `lib.mkMerge` and host detection
    - Can override packages, services, or add host-specific settings

- **overlays/**: Custom package overlays organized by category
  - **Numbered prefixes indicate loading order**: `00-` loads first, then `10-`, `15-`, `30-`, etc.
  - **Loading mechanism**: All `.nix` files in overlays/ are automatically imported by darwin.nix
  - **Categories**:
    - `00-last-known-good.nix`: Pin packages to specific nixpkgs revisions
    - `00-lib.nix`: Shared utility functions (mkScriptPackage, mkSimpleGitHubPackage, filterGitSource)
    - `10-coq.nix`: Coq theorem prover with IDE disabled
    - `10-emacs.nix`: Emacs with MacPort patches, custom packages, and variants
    - `15-darwin-fixes.nix`: Darwin-specific package fixes (time, zbar)
    - `30-ai-*.nix`: AI/ML tools split into llm, mcp, and python overlays
    - `30-data-tools.nix`: Data processing utilities (hashdb, dirscan, tsvutils)
    - `30-git-tools.nix`: Git extensions (git-lfs, git-pr, git-scripts)
    - `30-ledger.nix`: Ledger CLI accounting from local source
    - `30-misc-tools.nix`: Miscellaneous utilities (hammer, linkdups, z, yamale, etc.)
    - `30-text-tools.nix`: Text processing tools (filetags, hyperorg, org2tc)
    - `30-user-scripts.nix`: Personal script collections (nix-scripts, my-scripts)
  - **Overlay pattern**: Each file exports `final: prev: { ... }` where:
    - `final`: The final package set after all overlays
    - `prev`: The package set before this overlay
    - Always use `prev` to reference the previous package version
    - Use `final` when you need packages from later overlays (careful: can cause infinite recursion)

- **config/paths.nix**: Centralized path definitions for external source dependencies
  - Defines paths to local source checkouts used by overlays
  - Import in overlays: `let paths = import ../config/paths.nix; in { ... }`
  - Paths: scripts, gitScripts, dirscan, org2tc, hours, ledger

### Configuration Merging and Precedence

1. **System Configuration Flow** (Darwin):
   ```
   flake.nix → darwinConfigurations.${hostname}
     ├─ imports config/darwin.nix (system-level settings)
     ├─ applies all overlays/ (in numeric order)
     └─ imports home-manager module
          └─ imports config/home.nix (user-level settings)
               └─ imports config/packages.nix
   ```

2. **Host-Specific Overrides**:
   - Host detection: `if pkgs.stdenv.hostPlatform.system == "..." then ...`
   - Conditional imports: `imports = [ ] ++ lib.optional (hostname == "hera") ./hera.nix;`
   - Host-specific packages: Use `lib.mkIf (config.networking.hostName == "hera")`

3. **Home-Manager Integration**:
   - Runs as a Darwin module (not standalone)
   - User packages installed to `~/.nix-profile`
   - System packages installed to `/run/current-system`
   - Home-manager settings take precedence for user environment

### Key Design Patterns
1. **Flake-based Configuration**: Uses Nix flakes for reproducible system configuration with locked dependencies
   - All inputs pinned in `flake.lock`
   - `nix flake update` refreshes all inputs
   - `nix flake lock --update-input <input>` updates specific input

2. **Overlay System**: Extensive use of overlays to customize packages
   - Particularly for Emacs (MacPort version) and development tools
   - Overlays are composable and can reference each other
   - Use overlays for package modifications, not for creating entirely new packages (use packages/ dir instead)

3. **Host Differentiation**: Configuration varies by hostname with conditional attributes
   - PostgreSQL only on certain hosts
   - Different Emacs configurations per host
   - Host-specific services and packages

4. **Direnv Integration**: Custom `de` script manages per-project Nix shells
   - Caches built environments in `.envrc.cache`
   - Supports flakes (`flake.nix`), legacy (`shell.nix`), and Kadena projects
   - Preserves variables: `BUILDER`, `NIX_CONF`, SSH agent, etc.

5. **Remote Builder Support**: Optional use of remote builders
   - Set via `BUILDER` environment variable
   - Used by `de` script and Nix builds
   - Configured in `darwin.nix` under `nix.buildMachines`

### Important Variables
- `HOSTNAME`: Current host (hera, clio, athena, or vulcan)
- `NIX_CONF`: Points to this repository (`~/src/nix`)
- `BUILDER`: Optional remote builder hostname for Nix builds
- `MAX_AGE`: Days to keep old generations (default: 14)

### Custom Scripts
- **bin/de**: Direnv cache builder supporting flakes, shell.nix, and remote builders
  - Creates `.envrc` and `.envrc.cache` for faster shell activation
  - Preserves essential environment variables across direnv reloads
  - Supports Kadena-specific and flake-based projects
  - Usage: Run in project directory, optionally with `--no-cache` to force rebuild

## Best Practices

### Testing Configuration Changes
1. **Always build before switching**: `make build` catches errors without affecting the running system
2. **Review the diff**: Check what packages will change before switching
3. **Use git**: Commit working configurations before major changes
4. **Test in stages**: Make small, incremental changes rather than large rewrites
5. **Keep rollback ready**: Old generations remain available via `darwin-rebuild --list-generations`

### Managing Packages
- **System vs User packages**:
  - System packages (`environment.systemPackages`): Daemons, system-wide tools, things that need root
  - User packages (`home.packages`): Personal tools, development utilities, CLI apps
  - When in doubt, prefer user packages (easier to manage, faster rebuilds)

- **Adding packages**:
  1. Search first: Use `/nixos search <package>` or check nixpkgs
  2. Add to `config/packages.nix` for user packages
  3. Add to `config/darwin.nix` for system packages
  4. Build and test: `make build` before `make switch`

- **Custom package versions**:
  - Use overlays for modifications or version pinning
  - Place in appropriately numbered overlay file (e.g., `10-custom.nix`)
  - Reference existing patterns in `overlays/10-*.nix`

### Flake Management
- **Updating inputs**:
  - `make update`: Updates all inputs and Homebrew
  - `nix flake lock --update-input nixpkgs`: Update only nixpkgs
  - Review `flake.lock` changes before committing
  - Test after updates: `make build && make switch`

- **Adding new inputs**:
  1. Add to `inputs` section in `flake.nix`
  2. Pass to darwinConfigurations via `specialArgs` or module arguments
  3. Update lock: `nix flake lock`
  4. Use in config: Access via module arguments

- **Flake update strategy**:
  - Update regularly (weekly/monthly) to get security fixes
  - Test updates on non-critical host first
  - Keep old generations until new config is proven stable
  - Pin critical package versions in overlays if needed

### Overlay Development
- **Organization**:
  - Use numbered prefixes to control load order
  - Keep related modifications together (e.g., all Emacs changes in one file)
  - Document non-obvious changes with comments
  - Test overlays independently when possible

- **Common patterns**:
  ```nix
  # Simple package override
  final: prev: {
    package-name = prev.package-name.overrideAttrs (old: {
      version = "1.2.3";
      src = prev.fetchurl { ... };
    });
  }

  # Add to package
  final: prev: {
    package-name = prev.package-name.overrideAttrs (old: {
      buildInputs = old.buildInputs ++ [ prev.somelib ];
    });
  }

  # Conditional override
  final: prev: {
    package-name =
      if prev.stdenv.isDarwin
      then prev.package-name.override { enableFeature = true; }
      else prev.package-name;
  }
  ```

- **Debugging overlays**:
  - Use `nix repl` to test expressions: `make repl`
  - Check overlay order if changes aren't applying
  - Look for infinite recursion (using `final` to reference the same package you're defining)
  - Use `builtins.trace` for debugging: `builtins.trace "value: ${value}" expression`

### Secrets and Sensitive Data
- **Never commit secrets to the repository**
- **Key management**:
  - SSH keys referenced in `key-files.nix` but stored outside repo
  - Private keys in `~/.ssh/`, public keys in config
- **Passwords and tokens**:
  - Use environment variables for builds
  - Consider agenix or sops-nix for encrypted secrets (not currently used in this config)
- **Git hygiene**:
  - Review diffs before committing
  - Use `.gitignore` for local overrides or sensitive files

### Module Organization
- **Separation of concerns**:
  - `darwin.nix`: System settings, services, fonts, Nix daemon config
  - `home.nix`: User environment, shell config, dotfiles
  - `packages.nix`: Just the package list
  - Host-specific files: Only settings unique to that machine

- **When to create new modules**:
  - Feature has >50 lines of configuration
  - Configuration is reusable across hosts
  - Logical separation improves maintainability
  - Use `imports = [ ./modules/feature.nix ];`

## Troubleshooting

### Common Issues

#### Build Failures
```
error: attribute 'packageName' missing
```
**Solution**: Package was removed from nixpkgs or renamed. Search for replacement: `/nixos search <package>`

```
error: infinite recursion encountered
```
**Solution**: Overlay is referencing `final` when it should use `prev`, or circular dependency in config.
- Check overlay files for `final.packageName` references
- Use `prev.packageName` to get the previous version

```
error: hash mismatch in fixed-output derivation
```
**Solution**: Source hash changed (package updated). Update the hash in the overlay or fetch expression.

#### Darwin-Rebuild Errors
```
error: could not set permissions on '/nix/var/nix/profiles/per-user/...'
```
**Solution**: Permissions issue. Fix with: `sudo chown -R $(whoami) /nix/var/nix/profiles/per-user/$(whoami)`

```
error: profile '/nix/var/nix/profiles/system' does not exist
```
**Solution**: Fresh install or profile corruption. Run: `sudo nix-env -p /nix/var/nix/profiles/system --set /run/current-system`

#### Flake Lock Issues
```
error: flake 'git+file://...' does not provide attribute ...
```
**Solution**: Flake schema mismatch. Check that outputs match what's being accessed:
- `nix flake show` to see available outputs
- Verify `darwinConfigurations.${hostname}` exists in flake.nix

```
error: cannot update flake input 'foo' because it is locked
```
**Solution**: Remove `flake.lock` entry or use `--update-input foo` flag

#### Home-Manager Issues
```
error: collision between ... and ...
```
**Solution**: Same package in both system and user packages, or duplicate in packages list.
- Remove from one location (prefer user packages)
- Check for duplicates in `packages.nix`

#### Nix Store Issues
```
error: cannot open connection to remote store 'ssh://...'
```
**Solution**: Remote builder unreachable. Check `BUILDER` variable, SSH config, and network.

```
error: store path '...' is not valid
```
**Solution**: Store corruption. Run `make check` or `nix-store --verify --check-contents --repair`

### Debugging Techniques

1. **Verbose builds**: Add `-v` or `-vv` or `-vvv` for increasing verbosity
   ```bash
   darwin-rebuild build --flake .#hera -vv
   ```

2. **Show trace**: Add `--show-trace` to see full error context
   ```bash
   nix build --show-trace
   ```

3. **Test specific attributes**:
   ```bash
   nix eval .#darwinConfigurations.hera.config.environment.systemPackages
   ```

4. **REPL exploration**:
   ```bash
   make repl
   # Then explore: :lf . to load flake, tab completion works
   ```

5. **Build logs**: Check detailed logs
   ```bash
   nix log /nix/store/...-package-name
   ```

6. **Diff generations**: Compare what changed
   ```bash
   darwin-rebuild --list-generations
   nix store diff-closures /nix/var/nix/profiles/system-{42,43}-link
   ```

### Getting Help
- Check Nix manual: https://nixos.org/manual/nix/stable/
- nix-darwin options: https://daiderd.com/nix-darwin/manual/
- Home-manager options: https://nix-community.github.io/home-manager/options.html
- Search packages/options: Use `/nixos search <query>`
- NixOS Discourse: https://discourse.nixos.org/
- Use the nix-pro subagent for Nix-specific questions

## Development Notes

- The configuration uses macOS-specific packages via nix-darwin and Homebrew integration
- Emacs configuration is heavily customized with MacPort patches and extensive overlays
- SSH keys are managed via `key-files.nix` for cross-host authentication
- Projects listed in `~/.config/projects` are automatically managed by update/travel-ready commands
- Direnv caching significantly speeds up project shell activation
- Remote builders can be used by setting `BUILDER` environment variable before builds
