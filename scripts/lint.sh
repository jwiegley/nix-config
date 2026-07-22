#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

enter_repo

statix check flake.nix
statix check overlays
statix check packages
statix check tests
deadnix --fail flake.nix overlays packages tests

if has_shell_files; then
	find_shell_files0 | xargs -0 -r shellcheck -x
fi
