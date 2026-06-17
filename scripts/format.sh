#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

enter_repo

if [ "$#" -gt 0 ]; then
	nix_files=()
	shell_files=()

	for path in "$@"; do
		case "$path" in
		*.nix) nix_files+=("$path") ;;
		*.sh) shell_files+=("$path") ;;
		esac
	done

	if [ "${#nix_files[@]}" -gt 0 ]; then
		nixfmt "${nix_files[@]}"
	fi

	if [ "${#shell_files[@]}" -gt 0 ]; then
		shfmt -w "${shell_files[@]}"
	fi

	exit 0
fi

if has_nix_files; then
	find_nix_files0 | xargs -0 -r nixfmt
fi

if has_shell_files; then
	find_shell_files0 | xargs -0 -r shfmt -w
fi
