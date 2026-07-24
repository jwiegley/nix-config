#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

"$script_dir/format-check.sh"
"$script_dir/lint.sh"
"$script_dir/test.sh"
"$script_dir/build-check.sh"
"$script_dir/no-warnings.sh"
