#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=test/ai/scripts/lib.sh
. "$script_dir/lib.sh"

enter_repo

nix_conf_dir=$(empty_nix_conf_dir)
trap 'rm -rf "$nix_conf_dir"' EXIT

NIX_CONF_DIR="$nix_conf_dir" nix \
    --option warn-dirty false \
    --option abort-on-warn true \
    build \
    --no-link \
    --print-build-logs \
    .#default
