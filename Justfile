# Darwin Configuration Management
# Based on existing Makefile with improved ergonomics

# Configuration variables
hostname := "hera"
remotes := "clio athena"
git_remote := "jwiegley"
max_age := "14"
nix_conf := env_var('HOME') + "/src/nix"
projects := env_var('HOME') + "/.config/projects"

# Default recipe
default:
    @just --list

# Show configuration info
[group('info')]
info:
    @echo "HOSTNAME={{hostname}}"
    @echo "BUILDER=${BUILDER:-}"
    @echo "Projects file: {{projects}}"

# System Information
[group('info')]
system-info:
    @echo "=== System Information ==="
    @echo "Hostname: {{hostname}}"
    @echo "Remotes: {{remotes}}"
    @echo "NIX_CONF: {{nix_conf}}"
    @echo "Max age: {{max_age}} days"

# Build system configuration
[group('nix')]
build:
    #!/usr/bin/env bash
    echo
    echo '┌────────────────────────────────────────────────────────────────────────────┐'
    printf '│ >>> darwin-rebuild build --impure --flake .#{{hostname}}%*s│\n' $((72 - $(echo 'darwin-rebuild build --impure --flake .#{{hostname}}' | wc -c)))
    echo '└────────────────────────────────────────────────────────────────────────────┘'
    darwin-rebuild build --impure --flake .#{{hostname}}
    rm -f result*

# Build and switch system configuration
[group('nix')]
switch:
    #!/usr/bin/env bash
    echo
    echo '┌────────────────────────────────────────────────────────────────────────────┐'
    printf '│ >>> darwin-rebuild switch --impure --flake .#{{hostname}}%*s│\n' $((72 - $(echo 'darwin-rebuild switch --impure --flake .#{{hostname}}' | wc -c)))
    echo '└────────────────────────────────────────────────────────────────────────────┘'
    sudo darwin-rebuild switch --impure --flake .#{{hostname}}
    echo "Darwin generation: $(darwin-rebuild --list-generations | tail -1)"

# Update flake inputs and brew packages
[group('nix')]
update:
    #!/usr/bin/env bash
    echo
    echo '┌────────────────────────────────────────────────────────────────────────────┐'
    printf '│ >>> nix flake update && brew update%*s│\n' $((72 - $(echo 'nix flake update && brew update' | wc -c)))
    echo '└────────────────────────────────────────────────────────────────────────────┘'
    nix flake update

    # Update project flakes
    while IFS= read -r project; do
        [[ "$project" =~ ^[^#] ]] || continue
        echo "### $HOME/$project"
        (cd "$HOME/$project" && nix flake update)
    done < {{projects}}

    # Update homebrew
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    brew update

# Full upgrade: update, switch, and check
[group('nix')]
upgrade: update upgrade-tasks check

# Internal upgrade tasks
upgrade-tasks: switch travel-ready
    #!/usr/bin/env bash
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    brew upgrade --greedy

# Open Nix REPL with current system packages
[group('nix')]
repl:
    nix --extra-experimental-features repl-flake repl .#darwinConfigurations.{{hostname}}.pkgs

# Maintenance Commands

# Verify Nix store integrity
[group('maintenance')]
check:
    #!/usr/bin/env bash
    echo
    echo '┌────────────────────────────────────────────────────────────────────────────┐'
    printf '│ >>> nix store verify --no-trust --repair --all%*s│\n' $((72 - $(echo 'nix store verify --no-trust --repair --all' | wc -c)))
    echo '└────────────────────────────────────────────────────────────────────────────┘'
    nix store verify --no-trust --repair --all

# Show disk usage for /nix
[group('maintenance')]
sizes:
    df -H /nix 2>&1 | grep /dev

# Clean old generations (default: 14 days)
[group('maintenance')]
clean:
    #!/usr/bin/env bash
    # Delete old user generations
    nix-env --delete-generations $(nix-env --list-generations | awk 'NR>{{max_age}}{print $1}' | head -n -{{max_age}})
    # Delete old system generations
    nix-env -p /nix/var/nix/profiles/system --delete-generations $(nix-env -p /nix/var/nix/profiles/system --list-generations | awk 'NR>{{max_age}}{print $1}' | head -n -{{max_age}})
    # Collect garbage
    nix-collect-garbage --delete-older-than {{max_age}}d
    sudo nix-collect-garbage --delete-older-than {{max_age}}d

# Remove all but current generation
[group('maintenance')]
purge:
    #!/usr/bin/env bash
    # Delete all but current generation
    nix-env --delete-generations $(nix-env --list-generations | awk 'NR>1{print $1}' | head -n -1)
    nix-env -p /nix/var/nix/profiles/system --delete-generations $(nix-env -p /nix/var/nix/profiles/system --list-generations | awk 'NR>1{print $1}' | head -n -1)
    nix-collect-garbage --delete-old
    sudo nix-collect-garbage --delete-old

# Sign store paths with local key
[group('maintenance')]
sign:
    #!/usr/bin/env bash
    echo
    echo '┌────────────────────────────────────────────────────────────────────────────┐'
    printf '│ >>> nix store sign -k "<key>" --all%*s│\n' $((72 - $(echo 'nix store sign -k "<key>" --all' | wc -c)))
    echo '└────────────────────────────────────────────────────────────────────────────┘'
    nix store sign -k $HOME/.config/gnupg/nix-signing-key.sec --all

# Remote Operations

# Copy store paths to remote hosts
[group('remote')]
copy:
    #!/usr/bin/env bash
    echo
    echo '┌────────────────────────────────────────────────────────────────────────────┐'
    printf '│ >>> copy%*s│\n' $((72 - 8))
    echo '└────────────────────────────────────────────────────────────────────────────┘'
    for host in {{remotes}}; do
        nix copy --to "ssh-ng://$host" $HOME/.local/state/nix/profiles/profile
        while IFS= read -r project; do
            [[ "$project" =~ ^[^#] ]] || continue
            echo "$project"
            (cd "$HOME/$project" && \
             if [[ -f .envrc.cache ]]; then
                 source <(direnv apply_dump .envrc.cache)
                 if [[ -n "$buildInputs" ]]; then
                     eval nix copy --to ssh-ng://$host $buildInputs
                 fi
             fi)
        done < {{projects}}
    done

# Execute command on all remote hosts
[group('remote')]
remote-exec command:
    #!/usr/bin/env bash
    for host in {{remotes}}; do
        echo "=== $host ==="
        ssh $host "NIX_CONF={{nix_conf}} u $host {{command}}"
    done

# Switch configuration on remote hosts
[group('remote')]
switch-all: (remote-exec "switch")

# Update configuration on remote hosts
[group('remote')]
update-all: (remote-exec "update")

# Development Environment Management

# Prepare all projects for travel (rebuild direnv caches)
[group('dev')]
travel-ready:
    #!/usr/bin/env bash
    echo
    echo '┌────────────────────────────────────────────────────────────────────────────┐'
    printf '│ >>> travel-ready%*s│\n' $((72 - 16))
    echo '└────────────────────────────────────────────────────────────────────────────┘'

    readarray -t projects < <(grep -v '^(#.*)?$' "{{projects}}")
    for dir in "${projects[@]}"; do
        echo "Updating direnv on {{hostname}} for ~/$dir"
        (cd ~/$dir &&
         rm -f .envrc .envrc.cache &&
         clean &&
         if [[ "{{hostname}}" == "athena" ]] || [[ "{{hostname}}" == "hera" ]] || [[ "{{hostname}}" == "clio" ]]; then
             {{nix_conf}}/bin/de
         else
             unset BUILDER
             {{nix_conf}}/bin/de
         fi)
    done

# Show changes across all projects
[group('dev')]
changes:
    #!/usr/bin/env bash
    while IFS= read -r project; do
        [[ "$project" =~ ^[^#] ]] || continue
        echo "### $HOME/$project"
        (cd "$HOME/$project" && changes)
    done < {{projects}}

    for dir in ~/.config/pushme ~/.emacs.d ~/src/nix ~/src/scripts ~/doc ~/org; do
        echo "### $dir"
        (cd "$dir" && changes)
    done

# Test recipe for debugging
[group('dev')]
test:
    #!/usr/bin/env bash
    echo
    echo '┌────────────────────────────────────────────────────────────────────────────┐'
    printf '│ >>> this is a test%*s│\n' $((72 - 18))
    echo '└────────────────────────────────────────────────────────────────────────────┘'

# Tool verification
[group('dev')]
tools:
    @echo "HOSTNAME={{hostname}}"
    @echo "BUILDER=${BUILDER:-}"
    @echo "export PATH=$PATH"
    @which field find git head make nix nix-build nix-env sort uniq || true