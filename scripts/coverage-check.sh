#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

enter_repo

baseline="${AI_NIX_COVERAGE_BASELINE:-$(repo_root)/.ci/coverage-baseline.json}"
report=$("$script_dir/coverage.sh")

current=$(jq -r '.percent' "$report")
minimum=$(jq -r '.minimum_percent' "$baseline")

awk -v current="$current" -v minimum="$minimum" '
  BEGIN {
    if (current + 0 < minimum + 0) {
      printf "coverage %.2f%% is below baseline %.2f%%\n", current, minimum > "/dev/stderr"
      exit 1
    }
  }
'

printf 'coverage %.2f%% >= %.2f%%\n' "$current" "$minimum"
