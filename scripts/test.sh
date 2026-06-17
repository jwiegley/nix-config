#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

enter_repo

if [ "${AI_NIX_TEST_SOURCE_ONLY:-0}" = "1" ]; then
	nix_conf_dir=$(empty_nix_conf_dir)
	while IFS= read -r -d '' file; do
		NIX_CONF_DIR="$nix_conf_dir" nix-instantiate --parse "$file" >/dev/null
	done < <(find_nix_files0)
	exit 0
fi

nix_conf_dir=$(empty_nix_conf_dir)
nix_cmd=(env NIX_CONF_DIR="$nix_conf_dir" nix --option warn-dirty false)

system=$("${nix_cmd[@]}" eval --impure --raw --expr 'builtins.currentSystem')

"${nix_cmd[@]}" flake show --no-write-lock-file >/dev/null
"${nix_cmd[@]}" eval --raw ".#packages.${system}.default.name" >/dev/null
"${nix_cmd[@]}" eval --raw ".#devShells.${system}.default.name" >/dev/null
