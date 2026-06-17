#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

enter_repo

out_dir="${AI_NIX_PROFILE_DIR:-$(output_root)/profile}"
mkdir -p "$out_dir"

runs="${AI_NIX_PROFILE_RUNS:-3}"
warmup="${AI_NIX_PROFILE_WARMUP:-1}"
command_text="${AI_NIX_PROFILE_COMMAND:-find . -type f -name '*.nix' -not -path './.git/*' -not -path './.direnv/*' -not -path './build/*' -not -path './result/*' -not -path './result-*/*' -print0 | xargs -0 -r nixfmt --check}"
report="$out_dir/profile.json"

hyperfine --warmup "$warmup" --runs "$runs" --export-json "$report" "$command_text" >&2

printf '%s\n' "$report"
