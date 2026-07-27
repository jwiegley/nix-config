#!/usr/bin/env bash
# Shared host normalization and flake-output routing.

normalize_nix_host() {
    local host=${1%%.*}
    case $host in
    *[Hh][Ee][Rr][Aa]*) printf '%s\n' hera ;;
    *[Cc][Ll][Ii][Oo]*) printf '%s\n' clio ;;
    *[Vv][Uu][Ll][Cc][Aa][Nn]*) printf '%s\n' vulcan ;;
    vps | ovh-vps | *srp-next*) printf '%s\n' vps ;;
    [Aa]ndoria-* | [Dd]elphi-* | [Gg][Pp][Uu]-* | git-ai) printf '%s\n' shared-work ;;
    *) return 1 ;;
    esac
}

nix_flake_output_for_host() {
    case $(normalize_nix_host "$1") in
    hera) printf '%s\n' hera ;;
    clio) printf '%s\n' clio ;;
    vulcan) printf '%s\n' vulcan ;;
    vps) printf '%s\n' ovh-vps ;;
    *) return 1 ;;
    esac
}
