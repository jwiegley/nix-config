#!/usr/bin/env bash

set -euo pipefail

repo_root() {
    if [ -n "${AI_NIX_ROOT:-}" ]; then
        printf '%s\n' "$AI_NIX_ROOT"
        return
    fi

    git rev-parse --show-toplevel 2>/dev/null || pwd
}

empty_nix_conf_dir() {
    local dir

    dir="${TMPDIR:-/tmp}/ai-nix-empty-nix-conf"
    mkdir -p "$dir"
    printf '%s\n' "$dir"
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
