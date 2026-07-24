#!/usr/bin/env bash

set -euo pipefail

repo_root() {
    if [ -n "${AI_NIX_ROOT:-}" ]; then
        printf '%s\n' "$AI_NIX_ROOT"
        return
    fi

    git rev-parse --show-toplevel 2>/dev/null || pwd
}

output_root() {
    if [ -n "${AI_NIX_OUTPUT_ROOT:-}" ]; then
        printf '%s\n' "$AI_NIX_OUTPUT_ROOT"
        return
    fi

    printf '%s/build\n' "$(repo_root)"
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

find_nix_files() {
    find . -type f -name '*.nix' \
        -not -path './.git/*' \
        -not -path './.direnv/*' \
        -not -path './build/*' \
        -not -path './result/*' \
        -not -path './result-*/*' \
        -print
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

find_shell_files() {
    find . -type f -name '*.sh' \
        -not -path './.git/*' \
        -not -path './.direnv/*' \
        -not -path './build/*' \
        -not -path './result/*' \
        -not -path './result-*/*' \
        -print
}

has_nix_files() {
    find . -type f -name '*.nix' \
        -not -path './.git/*' \
        -not -path './.direnv/*' \
        -not -path './build/*' \
        -not -path './result/*' \
        -not -path './result-*/*' \
        -print -quit | grep -q .
}

has_shell_files() {
    find . -type f -name '*.sh' \
        -not -path './.git/*' \
        -not -path './.direnv/*' \
        -not -path './build/*' \
        -not -path './result/*' \
        -not -path './result-*/*' \
        -print -quit | grep -q .
}

count_nix_files() {
    find_nix_files | wc -l | tr -d ' '
}

count_shell_files() {
    find_shell_files | wc -l | tr -d ' '
}
