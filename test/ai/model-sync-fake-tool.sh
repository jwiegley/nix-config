#!/usr/bin/env bash

set -euo pipefail

tool="${0##*/}"
fake_root="${MODEL_SYNC_FAKE_ROOT:?}"

{
    printf '%s' "$tool"
    for argument in "$@"; do
        printf '\t%s' "$argument"
    done
    printf '\n'
} >>"$fake_root/events.tsv"

failure_requested() {
    case ",${MODEL_SYNC_FAKE_FAILURES:-}," in
    *,"$1",*) return 0 ;;
    *) return 1 ;;
    esac
}

next_count() {
    local name="$1"
    local path="$fake_root/$name.count"
    local count=0
    if [[ -f "$path" ]]; then
        read -r count <"$path" || return
    fi
    count=$((count + 1))
    printf '%s\n' "$count" >"$path" || return
    printf '%s\n' "$count"
}

probe() {
    local count
    count="$(next_count "$tool")"
    failure_requested "$tool" && return 1
    failure_requested "$tool:$count" && return 1
    return 0
}

case "$tool" in
pgrep)
    [[ $# == 2 && "$1" == -x ]] || exit 64
    failure_requested pgrep && exit 2
    [[ "$2" == "${MODEL_SYNC_FAKE_RUNNING:-}" ]] || exit 1
    ;;
devonthink)
    (($# == 0)) || exit 64
    probe
    ;;
security)
    [[ $# == 5 && "$1" == find-generic-password && "$2" == -s ]] || exit 64
    [[ "$3" == "iTerm2 API Keys" && "$4" == -a ]] || exit 64
    [[ "$5" == "OpenAI API Key for iTerm2" ]] || exit 64
    probe
    ;;
defaults)
    (($# >= 1)) || exit 64
    operation="$1"
    count="$(next_count "$operation")"
    case "$operation" in
    write)
        [[ $# == 5 ]] || exit 64
        failure_requested write && exit 1
        failure_requested "write:$count" && exit 1
        case "$4" in
        -bool)
            case "${5,,}" in
            1 | true | yes) value=1 ;;
            *) value=0 ;;
            esac
            ;;
        -int) value="$((10#$5))" ;;
        -string) value="$5" ;;
        *) exit 64 ;;
        esac
        printf '%s' "$value" >"$fake_root/preference-$count"
        ;;
    read)
        [[ $# == 3 ]] || exit 64
        failure_requested read && exit 1
        failure_requested "read:$count" && exit 1
        [[ -f "$fake_root/preference-$count" ]] || exit 1
        value="$(<"$fake_root/preference-$count")"
        if failure_requested mismatch || failure_requested "mismatch:$count"; then
            printf '%s:mismatch\n' "$value"
        else
            printf '%s\n' "$value"
        fi
        ;;
    *) exit 64 ;;
    esac
    ;;
mkdir)
    [[ $# == 3 && "$1" == -p && "$2" == -- ]] || exit 64
    failure_requested mkdir && exit 1
    mkdir -p -- "$3"
    ;;
mktemp)
    [[ $# == 1 && "$1" == *XXXXXX ]] || exit 64
    failure_requested mktemp && exit 1
    if failure_requested stamp-write; then
        target="$fake_root/stamp-write-target"
        mkdir "$target"
        printf '%s\n' "$target"
    else
        mktemp "$1"
    fi
    ;;
mv)
    [[ $# == 4 && "$1" == -fT && "$2" == -- ]] || exit 64
    if failure_requested mv-block; then
        ready="$fake_root/mv-ready.$$"
        printf '%s %s' "$PPID" "$$" >"$ready"
        mv -f -- "$ready" "$fake_root/mv-ready"
        exec sleep 60
    fi
    failure_requested mv && exit 1
    mv -f -- "$3" "$4"
    ;;
rm)
    [[ $# == 3 && "$1" == -f && "$2" == -- ]] || exit 64
    failure_requested rm && exit 1
    if [[ -d "$3" && "${3##*/}" == stamp-write-target ]]; then
        rmdir "$3"
    else
        rm -f -- "$3"
    fi
    ;;
*)
    printf 'unknown fake tool: %s\n' "$tool" >&2
    exit 64
    ;;
esac
