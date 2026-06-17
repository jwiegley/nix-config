#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

enter_repo

out_dir="${AI_NIX_FUZZ_DIR:-$(output_root)/fuzz}"
mkdir -p "$out_dir"

iterations="${AI_NIX_FUZZ_ITERATIONS:-5}"
nix_conf_dir=$(empty_nix_conf_dir)

for iteration in $(seq 1 "$iterations"); do
	seed=$((iteration * 7919))
	find_nix_files |
		awk -v seed="$seed" 'BEGIN { srand(seed) } { print rand() "\t" $0 }' |
		sort -n |
		cut -f2- |
		while IFS= read -r file; do
			NIX_CONF_DIR="$nix_conf_dir" nix-instantiate --parse "$file" >/dev/null
		done
done

cat >"$out_dir/fuzz.txt" <<TXT
Nix has no sanitizer-guided fuzz target here.
This target randomizes parser order and reparses every Nix file ${iterations} times.
TXT

printf '%s\n' "$out_dir/fuzz.txt"
