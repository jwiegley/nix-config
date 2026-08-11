# shellcheck shell=bash

set -o pipefail

: "${out:?out is required}"
: "${NIX_BUILD_TOP:?NIX_BUILD_TOP is required}"

samba_macho_load_commands() {
    local bin=$1
    local first line magic output trimmed

    if ! magic=$(od -An -N4 -tx1 -- "$bin"); then
        printf 'samba: cannot read %q\n' "$bin" >&2
        return 1
    fi
    magic=${magic//[[:space:]]/}
    case $magic in
    feedface | cefaedfe | feedfacf | cffaedfe | cafebabe | bebafeca | cafebabf | bfbafeca) ;;
    *) return 3 ;;
    esac

    if ! output=$(otool -L "$bin"); then
        printf 'samba: otool -L failed for %q\n' "$bin" >&2
        return 1
    fi
    first=1
    while IFS= read -r line; do
        if [[ $first -eq 1 ]]; then
            first=0
            if [[ $line != "$bin:" ]]; then
                printf 'samba: invalid otool -L header for %q\n' "$bin" >&2
                return 1
            fi
            continue
        fi
        trimmed=${line#"${line%%[!$' \t']*}"}
        if [[ -n $trimmed && $trimmed != *' (compatibility version '* ]]; then
            printf 'samba: invalid otool -L line for %q\n' "$bin" >&2
            return 1
        fi
    done <<<"$output"
    if [[ $first -eq 1 ]]; then
        printf 'samba: empty otool -L output for %q\n' "$bin" >&2
        return 1
    fi
    SAMBA_LOAD_COMMANDS=$output
}

samba_macho_has_id() {
    local bin=$1
    local field line output rest value

    if ! output=$(otool -l "$bin"); then
        printf 'samba: otool -l failed for %q\n' "$bin" >&2
        return 1
    fi
    case $output in
    "$bin:" | "$bin:"$'\n'*) ;;
    *)
        printf 'samba: invalid otool -l output for %q\n' "$bin" >&2
        return 1
        ;;
    esac
    SAMBA_HAS_ID=0
    while IFS= read -r line; do
        read -r field value rest <<<"$line"
        if [[ $field == cmd && $value == LC_ID_DYLIB ]]; then
            SAMBA_HAS_ID=1
            break
        fi
    done <<<"$output"
}

samba_fix_macho() {
    local bin=$1
    local candidate directory first line old_basename old_rpath status trimmed

    if samba_macho_load_commands "$bin"; then
        :
    else
        status=$?
        [[ $status -eq 3 ]] && return 0
        return 1
    fi
    samba_macho_has_id "$bin" || return 1

    set --
    [[ $SAMBA_HAS_ID -eq 0 ]] || set -- "$@" -id "$bin"
    first=1
    while IFS= read -r line; do
        if [[ $first -eq 1 ]]; then
            first=0
            continue
        fi
        trimmed=${line#"${line%%[!$' \t']*}"}
        [[ -n $trimmed ]] || continue
        old_rpath=${trimmed% \(compatibility\ version\ *}
        case $old_rpath in
        "$NIX_BUILD_TOP"/*)
            old_basename=${old_rpath##*/}
            candidate=
            for directory in "${samba_libs[@]}"; do
                if [[ -f $directory/$old_basename ]]; then
                    candidate=$directory/$old_basename
                    break
                fi
            done
            if [[ -z $candidate ]]; then
                printf 'samba: no replacement for %q used by %q\n' "$old_rpath" "$bin" >&2
                return 1
            fi
            set -- "$@" -change "$old_rpath" "$candidate"
            ;;
        esac
    done <<<"$SAMBA_LOAD_COMMANDS"
    [[ $# -eq 0 ]] || install_name_tool "$@" "$bin"
}

samba_fix_macho_tree() {
    local samba_libs_file

    samba_libs_file=$(mktemp) || return 1
    if ! find "$out" -type f -regex '.*\.dylib\(\..*\)?' -printf '%h\0' |
        sort -zu >"$samba_libs_file"; then
        rm -f "$samba_libs_file"
        echo "samba: failed to enumerate dylib directories" >&2
        return 1
    fi
    samba_libs=()
    if ! mapfile -d '' -t samba_libs <"$samba_libs_file"; then
        rm -f "$samba_libs_file"
        echo "samba: failed to load dylib directories" >&2
        return 1
    fi
    rm -f "$samba_libs_file"
    [[ ${#samba_libs[@]} -gt 0 ]] || {
        echo "samba: no dylib directories found" >&2
        return 1
    }

    if ! find "$out" -type f -print0 |
        while IFS= read -r -d '' bin; do
            samba_fix_macho "$bin" || exit 1
        done; then
        echo "samba: Mach-O fixup traversal failed" >&2
        return 1
    fi
}

samba_verify_macho() {
    local bin=$1
    local status

    if samba_macho_load_commands "$bin"; then
        :
    else
        status=$?
        [[ $status -eq 3 ]] && return 0
        return 1
    fi
    if [[ $SAMBA_LOAD_COMMANDS == *"$NIX_BUILD_TOP/"* ]]; then
        printf 'samba: build-root reference remains in %q\n' "$bin" >&2
        return 1
    fi
}

samba_verify_macho_tree() {
    if ! find "$out" -type f -print0 |
        while IFS= read -r -d '' bin; do
            samba_verify_macho "$bin" || exit 1
        done; then
        echo "samba: residual Mach-O scan failed" >&2
        return 1
    fi
}
