#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=test/ai/scripts/lib.sh
. "$script_dir/lib.sh"

if [ -n "${AI_NIX_LINT_ROOT:-}" ]; then
    export AI_NIX_ROOT=$AI_NIX_LINT_ROOT
fi

run_quality nix-lint nix-deadcode shell-lint
