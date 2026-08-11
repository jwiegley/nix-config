#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=test/ai/scripts/lib.sh
. "$script_dir/lib.sh"

usage() {
    printf 'usage: %s [--check] [PATH ...]\n' "${0##*/}" >&2
}

check=false
case "${1:-}" in
--check)
    check=true
    shift
    ;;
-*)
    usage
    exit 2
    ;;
esac

quality_args=(nix-format shell-format)
if ! "$check"; then
    quality_args=(--fix "${quality_args[@]}")
fi
if [ "$#" -gt 0 ]; then
    quality_args+=(--paths "$@")
fi

run_quality "${quality_args[@]}"
