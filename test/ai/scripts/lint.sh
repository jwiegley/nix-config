#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=test/ai/scripts/lib.sh
. "$script_dir/lib.sh"

enter_repo

portable_nix_paths=(
    config/fleet/flake.nix
    overlays/ai
    test/ai/overlays/agent-deck-go-compat.nix
    test/ai/overlays/llama-cpp-platform-compat.nix
    test/ai/overlays/plasma-fractal-smoke.nix
    flake-ai.nix
    flake/ai.nix
    packages/agent-resources.nix
    test/ai
)

for path in "${portable_nix_paths[@]}"; do
    statix check "$path"
done
deadnix --fail "${portable_nix_paths[@]}"
find test/ai -type f -name '*.sh' -print0 | xargs -0 -r shellcheck -x
