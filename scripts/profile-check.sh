#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

enter_repo

baseline="${AI_NIX_PERF_BASELINE:-$(repo_root)/.ci/perf-baseline.json}"
report=$("$script_dir/profile.sh")

current=$(jq -r '.results[0].mean' "$report")
baseline_mean=$(jq -r '.mean_seconds' "$baseline")
threshold=$(jq -r '.threshold' "$baseline")
limit=$(awk -v mean="$baseline_mean" -v threshold="$threshold" 'BEGIN { printf "%.6f", mean * (1 + threshold) }')

awk -v current="$current" -v limit="$limit" '
  BEGIN {
    if (current + 0 > limit + 0) {
      printf "profile mean %.6fs exceeds %.6fs budget\n", current, limit > "/dev/stderr"
      exit 1
    }
  }
'

printf 'profile mean %.6fs <= %.6fs\n' "$current" "$limit"
