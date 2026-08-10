#!/usr/bin/env bash

set -euo pipefail

repo_root() {
    if [ -n "${AI_NIX_ROOT:-}" ]; then
        printf '%s\n' "$AI_NIX_ROOT"
        return
    fi

    git rev-parse --show-toplevel 2>/dev/null || pwd
}

# A fixed path under /tmp could be pre-created by another user on a shared
# host with a nix.conf inside; mktemp makes that state unreachable.
empty_nix_conf_dir() {
    mktemp -d "${TMPDIR:-/tmp}/ai-nix-empty-nix-conf.XXXXXX"
}

enter_repo() {
    cd "$(repo_root)"
}

find_nix_files0() {
    find . -type f -name '*.nix' \
        -not -path './.git/*' \
        -not -path './.direnv/*' \
        -not -path './build/*' \
        -not -path './result/*' \
        -not -path './result-*/*' \
        -print0
}

find_shell_files0() {
    find . -type f -name '*.sh' \
        -not -path './.git/*' \
        -not -path './.direnv/*' \
        -not -path './build/*' \
        -not -path './result/*' \
        -not -path './result-*/*' \
        -print0
}
