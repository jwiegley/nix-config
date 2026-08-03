#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=test/ai/scripts/lib.sh
. "$script_dir/lib.sh"

enter_repo

nix_conf_dir=$(empty_nix_conf_dir)
nix_cmd=(env NIX_CONF_DIR="$nix_conf_dir" nix --option warn-dirty false)

system=$("${nix_cmd[@]}" eval --impure --raw --expr 'builtins.currentSystem')

"${nix_cmd[@]}" flake show ./config/fleet --no-write-lock-file >/dev/null
"${nix_cmd[@]}" eval --raw "./config/fleet#packages.${system}.default.name" >/dev/null
"${nix_cmd[@]}" eval --raw "./config/fleet#devShells.${system}.default.name" >/dev/null
test -n "$("${nix_cmd[@]}" eval --raw "./config/fleet#packages.${system}.plasma-wiki.version")"
test -n "$("${nix_cmd[@]}" eval --raw "./config/fleet#packages.${system}.plasma-fractal.version")"
