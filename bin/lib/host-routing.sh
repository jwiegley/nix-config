#!/usr/bin/env bash
# Shared host normalization and flake-output routing.

# Normalization MUST be idempotent: nix_flake_output_for_host normalizes its
# argument, and callers such as bin/switch pass a value they already normalized.
# The four host names below survived a second pass only by accident of their glob
# patterns; `shared-work` did not, so `bin/switch` failed for every work machine
# with a bare `return 1`. Accept the canonical labels explicitly so the property
# is guaranteed rather than incidental.
normalize_nix_host() {
    local host=${1%%.*}
    case $host in
    shared-work) printf '%s\n' shared-work ;;
    *[Hh][Ee][Rr][Aa]*) printf '%s\n' hera ;;
    *[Cc][Ll][Ii][Oo]*) printf '%s\n' clio ;;
    *[Vv][Uu][Ll][Cc][Aa][Nn]*) printf '%s\n' vulcan ;;
    vps | ovh-vps | *srp-next*) printf '%s\n' vps ;;
    [Aa]ndoria-* | [Dd]elphi-* | [Gg][Pp][Uu]-* | git-ai) printf '%s\n' shared-work ;;
    *) return 1 ;;
    esac
}

# The attribute to switch to in each host's *authoritative* checkout. Note the
# namespaces differ by host class and that is intentional: hera/clio are
# darwinConfigurations in ~/src/nix, vulcan/ovh-vps are nixosConfigurations in
# /etc/nixos, and shared-work is a homeConfiguration in ~/.config/home-manager.
#
# `shared-work` is `jwiegley`, unqualified. That is the attribute the work
# machines' own flake exports, confirmed live on andoria-08:
#
#   $ nix eval --raw .#homeConfigurations --apply 'x: ...attrNames x' → jwiegley
#   ~/.config/home-manager/flake.nix:403: homeConfigurations.jwiegley = ...
#
# Do NOT use `jwiegley@x86_64-linux` here. That attribute exists in *this* repo's
# flake, but it is a synthetic CI fixture pinned to hostname="linux" and marked
# "not a host switch target"; it is not what the consumer flake exposes and
# switching to it would silently disable hostname-gated behaviour.
nix_flake_output_for_host() {
    case $(normalize_nix_host "$1") in
    hera) printf '%s\n' hera ;;
    clio) printf '%s\n' clio ;;
    vulcan) printf '%s\n' vulcan ;;
    vps) printf '%s\n' ovh-vps ;;
    shared-work) printf '%s\n' jwiegley ;;
    *) return 1 ;;
    esac
}
