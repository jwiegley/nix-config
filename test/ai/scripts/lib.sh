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

run_quality() {
    local program=${AI_NIX_QUALITY:-}
    if [ -z "$program" ]; then
        program=$(repo_root)/test/bin/quality
    fi
    if [ ! -f "$program" ]; then
        printf 'ai-nix: quality authority is missing: %s\n' "$program" >&2
        return 2
    fi
    bash "$program" "$@"
}
