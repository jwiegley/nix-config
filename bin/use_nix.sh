set -e

# Usage: use_nix [...]
#
# Load environment variables from `nix-shell`.
# If you have a `default.nix` or `shell.nix` one of these will be used and
# the derived environment will be stored at ./.direnv/env-<hash>
# and symlink to it will be created at ./.direnv/default.
# Dependencies are added to the GC roots, such that the environment remains persistent.
#
# Packages can also be specified directly via e.g `use nix -p ocaml`,
# however those will not be added to the GC roots.
#
# The resulting environment is cached for better performance.
#
# To trigger switch to a different environment:
# `rm -f .direnv/default`
#
# To derive a new environment:
# `rm -rf .direnv/env-$(md5sum {shell,default}.nix 2> /dev/null | cut -c -32)`
#
# To remove cache:
# `rm -f .direnv/dump-*`
#
# To remove all environments:
# `rm -rf .direnv/env-*`
#
# To remove only old environments:
# `find .direnv -name 'env-*' -and -not -name `readlink .direnv/default` -exec rm -rf {} +`
#

keep_except() {
    DIRENV_kept=$(for v in $@; do
        echo "-u $v"
    done | xargs env -0 | base64)
}

keep_vars() {
    local v
    for k in $@; do
        eval "v=\$$k"
        DIRENV_kept="$DIRENV_kept"$(printf "%s=%s\000" "$k" "$v" | base64)
    done
}

reset_kept() {
    : ${DIRENV_kept?No environment stored. Missing keep_except()?}
    echo "$DIRENV_kept" | base64 -d | while IFS= read -r -d '' V; do
        echo "export ${V%%=*}='${V#*=}'"
    done
    unset DIRENV_kept
}

identify_shell() {
    local shell="shell.nix"
    if [[ -n "$NIXFILE" && -f "${NIXFILE}" ]]; then
        shell="$NIXFILE"
    elif [[ ! -f "${shell}" ]]; then
        shell="default.nix"
    fi

    if [[ ! -f "${shell}" ]]; then
        echo "use nix: shell.nix or default.nix not found in the folder"
        exit 1
    fi
    echo "${shell}"
}

build_drv() {
    local dir="${PWD}"/.direnv
    local default="${dir}/default"
    local shell=$(identify_shell)
    if [[ ! -L "${default}" ]] || [[ ! -d `readlink "${default}"` ]]; then
        local wd="${dir}/env-`md5sum "${shell}" | cut -c -32`"
        mkdir -p "${wd}"

        local drv="${wd}/env.drv"
        if [[ ! -f "${drv}" ]]; then
            log_status "use nix: deriving new environment"
            IN_NIX_SHELL=1 nix-instantiate "${NIXARGS[@]}"              \
                --add-root "${drv}" --indirect "${shell}" > /dev/null
            nix-store -r `nix-store --query --references "${drv}"`      \
                --add-root "${wd}/dep" --indirect > /dev/null
        fi

        rm -f "${default}"
        ln -s `basename "${wd}"` "${default}"
    fi

    local drv=`readlink "${default}/env.drv"`
    echo "${drv}"
}

dump_file() {
    local dir="${PWD}"/.direnv
    local drv=$(build_drv)
    local dump="${dir}/dump-`md5sum ".envrc" | cut -c -32`-`md5sum ${drv} | cut -c -32`"
    echo "${dump}"
}

watch_files() {
    local dir="${PWD}"/.direnv
    local default="${dir}/default"
    watch_file "${default}"
    if [[ -f shell.nix ]]; then
        watch_file shell.nix
    fi
    local shell=$(identify_shell)
    if [[ ${shell} == "default.nix" ]]; then
        watch_file default.nix
    fi
}

build_cache() {
    local dir="${PWD}"/.direnv
    local default="${dir}/default"
    local drv=`readlink "${default}/env.drv"`
    local dump="${dir}/dump-`md5sum ".envrc" | cut -c -32`-`md5sum ${drv} | cut -c -32`"

    echo "direnv: use_nix: building cache"

    old=`find ${dir} -name 'dump-*'`
    if [[ -n $NIXBLDARGS ]]; then
        IN_NIX_SHELL=1 nix build "${NIXBLDARGS[@]}"
    fi
    nix-shell "${NIXARGS[@]}" "${drv}" --show-trace "$@" \
        --run 'source $(which use_nix.sh) && keep_except ${!SSH_@} ${!DIRENV_@} && direnv dump && reset_kept' > "${dump}"
    rm -f ${old}
}
