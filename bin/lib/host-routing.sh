#!/usr/bin/env bash
# Generated from config/hosts/registry.nix by config/hosts/shell-routing.nix.
# Edit the registry, not this projection.

normalize_nix_host() {
    local host=${1%%.*}
    case $host in
    [cC][lL][iI][oO] | *[cC][lL][iI][oO]*) printf '%s\n' clio ;;
    [hH][eE][rR][aA] | *[hH][eE][rR][aA]*) printf '%s\n' hera ;;
    [sS][hH][aA][rR][eE][dD]-[wW][oO][rR][kK] | [aA][nN][dD][oO][rR][iI][aA]-08 | [aA][nN][dD][oO][rR][iI][aA]-[tT]2 | [dD][eE][lL][pP][hH][iI]-3[bB][dD]4 | [gG][iI][tT]-[aA][iI] | [gG][pP][uU]-[sS][eE][rR][vV][eE][rR]) printf '%s\n' shared-work ;;
    [vV][pP][sS] | [oO][vV][hH]-[vV][pP][sS] | *[sS][rR][pP]-[nN][eE][xX][tT]*) printf '%s\n' vps ;;
    [vV][uU][lL][cC][aA][nN] | *[vV][uU][lL][cC][aA][nN]*) printf '%s\n' vulcan ;;
    *) return 1 ;;
    esac
}

nix_flake_output_for_host() {
    case $(normalize_nix_host "$1") in
    clio) printf '%s\n' clio ;;
    hera) printf '%s\n' hera ;;
    shared-work) printf '%s\n' jwiegley ;;
    vps) printf '%s\n' ovh-vps ;;
    vulcan) printf '%s\n' vulcan ;;
    *) return 1 ;;
    esac
}

nix_activation_for_host() {
    case $(normalize_nix_host "$1") in
    clio) printf '%s\n' darwin ;;
    hera) printf '%s\n' darwin ;;
    shared-work) printf '%s\n' home-standalone ;;
    vps) printf '%s\n' nixos-module ;;
    vulcan) printf '%s\n' nixos-module ;;
    *) return 1 ;;
    esac
}

nix_local_build_limits_for_host() {
    case $(normalize_nix_host "$1") in
    vps) printf '%s %s\n' 1 1 ;;
    *) return 1 ;;
    esac
}

nix_shared_work_members() {
    printf '%s\n' andoria-08
    printf '%s\n' andoria-t2
    printf '%s\n' delphi-3bd4
    printf '%s\n' git-ai
    printf '%s\n' gpu-server
}

nix_active_shared_work_rollout_hosts() {
    printf '%s\n' andoria-08
    printf '%s\n' andoria-t2
    printf '%s\n' delphi-3bd4
    printf '%s\n' gpu-server
}
