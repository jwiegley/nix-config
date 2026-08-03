#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=test/ai/scripts/lib.sh
. "$script_dir/lib.sh"

enter_repo

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

nixfmt_command=(nixfmt)
shfmt_command=(shfmt -i 4 -w)
if "$check"; then
    nixfmt_command+=(--check)
    shfmt_command=(shfmt -i 4 -d)
fi

if [ "$#" -gt 0 ]; then
    nix_files=()
    shell_files=()

    for path in "$@"; do
        case "$path" in
        -*)
            usage
            exit 2
            ;;
        *.nix) nix_files+=("$path") ;;
        *.sh) shell_files+=("$path") ;;
        esac
    done

    if [ "${#nix_files[@]}" -gt 0 ]; then
        "${nixfmt_command[@]}" "${nix_files[@]}"
    fi

    if [ "${#shell_files[@]}" -gt 0 ]; then
        "${shfmt_command[@]}" "${shell_files[@]}"
    fi

    exit 0
fi

find_nix_files0 | xargs -0 -r "${nixfmt_command[@]}"
find_shell_files0 | xargs -0 -r "${shfmt_command[@]}"
