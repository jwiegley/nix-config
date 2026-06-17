#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

enter_repo

out_dir="${AI_NIX_MEMORY_DIR:-$(output_root)/memory}"
mkdir -p "$out_dir"

cat >"$out_dir/memory.txt" <<TXT
Nix expressions do not have a memory-sanitizer build mode.
This repository has no native C, C++, Rust, or similar runtime code to instrument.
TXT

printf '%s\n' "$out_dir/memory.txt"
