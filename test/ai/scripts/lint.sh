#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=test/ai/scripts/lib.sh
. "$script_dir/lib.sh"

enter_repo

portable_nix_paths=(
    config/ai/flake.nix
    overlays/ai
    overlays/tests/agent-deck-go-compat.nix
    overlays/tests/llama-cpp-platform-compat.nix
    overlays/tests/plasma-fractal-smoke.nix
    packages/agent-resources.nix
    packages/ai-flake-definition.nix
    packages/ai-flake-outputs.nix
    test/ai
)

for path in "${portable_nix_paths[@]}"; do
    statix check "$path"
done
deadnix --fail "${portable_nix_paths[@]}"
find test/ai -type f -name '*.sh' -print0 | xargs -0 -r shellcheck -x
