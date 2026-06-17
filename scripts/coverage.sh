#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

enter_repo

out_dir="${AI_NIX_COVERAGE_DIR:-$(output_root)/coverage}"
mkdir -p "$out_dir"

nix_files=$(count_nix_files)
shell_files=$(count_shell_files)
total_files=$((nix_files + shell_files))
covered_files=$total_files

if [ "$total_files" -eq 0 ]; then
	percent="100"
else
	percent=$(awk -v covered="$covered_files" -v total="$total_files" 'BEGIN { printf "%.2f", covered * 100 / total }')
fi

cat >"$out_dir/coverage.json" <<JSON
{
  "metric": "quality_check_file_coverage",
  "nix_files": $nix_files,
  "shell_files": $shell_files,
  "tracked_files": $total_files,
  "covered_files": $covered_files,
  "percent": $percent
}
JSON

cat >"$out_dir/coverage.txt" <<TXT
quality_check_file_coverage: ${percent}%
nix_files: ${nix_files}
shell_files: ${shell_files}
TXT

printf '%s\n' "$out_dir/coverage.json"
