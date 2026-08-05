#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=test/ai/scripts/lib.sh
. "$script_dir/lib.sh"

if [ -n "${AI_NIX_LINT_ROOT:-}" ]; then
    cd "$AI_NIX_LINT_ROOT"
else
    enter_repo
fi

statix check .
deadnix --fail .
find test/ai -type f -name '*.sh' -print0 | xargs -0 -r shellcheck -x
