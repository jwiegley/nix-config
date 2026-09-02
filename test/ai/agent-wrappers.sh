#!/usr/bin/env bash

set -euo pipefail

: "${CLAUDE_BIN:?}"
: "${CLAUDE_REAL_BIN:?}"
: "${CODEX_BIN:?}"
: "${CODEX_NON_DARWIN_BIN:?}"
: "${CODEX_RAISES_OPEN_FILE_LIMIT:?}"
: "${CLAUDE_IDENTITY_BIN:?}"
: "${CLAUDE_REAL_IDENTITY_BIN:?}"
: "${CODEX_IDENTITY_BIN:?}"
: "${CODEX_POLICY_RESPONSE_CHECKER:?}"
: "${REAL_CLAUDE_BIN:?}"
: "${REAL_CODEX_BIN:?}"
: "${REAL_PROBED_CODEX_BIN:?}"
: "${REAL_WRAPPED_CODEX_BIN:?}"
: "${NETWORK_GUARD_LIBRARY:?}"
: "${NETWORK_GUARD_VARIABLE:?}"

work_root="$TMPDIR/agent wrapper cases"
managed_file_sentinel='MANAGED-FILE-CONTENT-MUST-NEVER-APPEAR-7d6b78'
case_counter=0
cleanup_roots=()
background_pids=()
test_run_id=$(printf '%s' "$TMPDIR" | cksum | awk '{ print $1 }')

mkdir -p "$work_root"

fail() {
    if [ -n "${STDERR_FILE:-}" ] && [ -s "$STDERR_FILE" ]; then
        sed -n '1,20p' "$STDERR_FILE" >&2
    fi
    printf 'agent-wrappers check [%s]: %s\n' "${CASE_DIR:-global}" "$*" >&2
    exit 1
}

cleanup() {
    local pid root
    for pid in "${background_pids[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    for pid in "${background_pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    for root in "${cleanup_roots[@]}"; do
        case "$root" in
        /var/tmp/codex-[0-9]*) rm -rf -- "$root" ;;
        *) fail "refusing unsafe cleanup path: $root" ;;
        esac
    done
}
trap cleanup EXIT

client_display_name() {
    case "$1" in
    claude) printf '%s\n' claude ;;
    codex) printf '%s\n' codex ;;
    *) fail "unknown client: $1" ;;
    esac
}

new_case() {
    local client=$1
    local label=$2

    case_counter=$((case_counter + 1))
    CASE_DIR="$work_root/$client/$case_counter-$label"
    HOME_DIR="$CASE_DIR/home with spaces"
    AGENT_TEST_UID="9$test_run_id$case_counter"
    CODEX_LOCAL_ROOT="/var/tmp/codex-$AGENT_TEST_UID"
    ARGV_FILE="$CASE_DIR/upstream.argv"
    ENV_FILE="$CASE_DIR/upstream.env"
    STDOUT_FILE="$CASE_DIR/stdout"
    STDERR_FILE="$CASE_DIR/stderr"

    mkdir -p "$HOME_DIR"
    case "$client" in
    claude)
        ROOT="$CASE_DIR/Claude Config With Spaces"
        FIRST="$ROOT/nix-managed-settings.json"
        SECOND="$ROOT/nix-managed-mcp.json"
        ;;
    codex)
        ROOT="$CASE_DIR/Codex Home With Spaces"
        FIRST="$ROOT/nix-managed.config.toml"
        CODEX_RUNTIME_LINK="$ROOT/nix-runtime.config.toml"
        CODEX_RUNTIME_FILE="$CODEX_LOCAL_ROOT/nix-runtime.config.toml"
        SECOND=
        [ ! -e "$CODEX_LOCAL_ROOT" ] && [ ! -L "$CODEX_LOCAL_ROOT" ] ||
            fail "Codex test root unexpectedly exists: $CODEX_LOCAL_ROOT"
        cleanup_roots+=("$CODEX_LOCAL_ROOT")
        ;;
    *) fail "unknown client: $client" ;;
    esac
    mkdir -p "$ROOT"
}

finish_case() {
    local client=$1
    if [ "$client" = codex ]; then
        case "$CODEX_LOCAL_ROOT" in
        /var/tmp/codex-[0-9]*) rm -rf -- "$CODEX_LOCAL_ROOT" ;;
        *) fail "refusing unsafe Codex cleanup path: $CODEX_LOCAL_ROOT" ;;
        esac
    fi
}

write_managed_file() {
    printf '%s\n' "$managed_file_sentinel" >"$1"
}

configure_state() {
    local state=$1
    local target_a target_b

    case "$state" in
    zero) ;;
    complete)
        write_managed_file "$FIRST"
        [ -z "$SECOND" ] || write_managed_file "$SECOND"
        ;;
    symlink-complete)
        mkdir -p "$CASE_DIR/regular targets"
        target_a="$CASE_DIR/regular targets/first"
        write_managed_file "$target_a"
        ln -s "$target_a" "$FIRST"
        if [ -n "$SECOND" ]; then
            target_b="$CASE_DIR/regular targets/second"
            write_managed_file "$target_b"
            ln -s "$target_b" "$SECOND"
        fi
        ;;
    left-only) write_managed_file "$FIRST" ;;
    right-only) write_managed_file "$SECOND" ;;
    dangling)
        ln -s "$CASE_DIR/missing first" "$FIRST"
        [ -z "$SECOND" ] || ln -s "$CASE_DIR/missing second" "$SECOND"
        ;;
    directories)
        mkdir "$FIRST"
        [ -z "$SECOND" ] || mkdir "$SECOND"
        ;;
    fifos)
        mkfifo "$FIRST"
        [ -z "$SECOND" ] || mkfifo "$SECOND"
        ;;
    regular-dangling)
        write_managed_file "$FIRST"
        ln -s "$CASE_DIR/missing companion" "$SECOND"
        ;;
    regular-directory)
        write_managed_file "$FIRST"
        mkdir "$SECOND"
        ;;
    regular-fifo)
        write_managed_file "$FIRST"
        mkfifo "$SECOND"
        ;;
    *) fail "unknown companion state: $state" ;;
    esac
}

invoke_agent() {
    local client=$1
    local bypass=$2
    local upstream_exit=$3
    shift 3
    local binary
    local -a command_env

    rm -f -- "$ARGV_FILE" "$ENV_FILE" "$STDOUT_FILE" "$STDERR_FILE"

    command_env=(
        env
        -u AI_NIX_BYPASS_MANAGED_CONFIG
        -u CLAUDE_CONFIG_DIR
        -u CODEX_HOME
        -u CODEX_SQLITE_HOME
        "HOME=$HOME_DIR"
        "AGENT_TEST_ARGV=$ARGV_FILE"
        "AGENT_TEST_ENV=$ENV_FILE"
        "AGENT_TEST_EXIT=$upstream_exit"
        "AGENT_TEST_UID=$AGENT_TEST_UID"
    )

    case "$client" in
    claude)
        binary=$CLAUDE_BIN
        case "${AGENT_TEST_CLAUDE_CONFIG_MODE:-explicit}" in
        explicit) command_env+=("CLAUDE_CONFIG_DIR=$ROOT") ;;
        unset) ;;
        empty) command_env+=("CLAUDE_CONFIG_DIR=") ;;
        *) fail "unknown Claude config mode: $AGENT_TEST_CLAUDE_CONFIG_MODE" ;;
        esac
        ;;
    codex)
        binary=$CODEX_BIN
        command_env+=(
            "CODEX_HOME=$ROOT"
            "AGENT_TEST_CODEX_POLICY=${AGENT_TEST_CODEX_POLICY:-manage}"
        )
        if [ -n "${AGENT_TEST_CODEX_PROBE_EXIT:-}" ]; then
            command_env+=("AGENT_TEST_CODEX_PROBE_EXIT=$AGENT_TEST_CODEX_PROBE_EXIT")
        fi
        if [ "${AGENT_TEST_CODEX_PROBE_NO_OUTPUT:-}" = 1 ]; then
            command_env+=(AGENT_TEST_CODEX_PROBE_NO_OUTPUT=1)
        fi
        if [ "${AGENT_TEST_CODEX_PROBE_NO_NEWLINE:-}" = 1 ]; then
            command_env+=(AGENT_TEST_CODEX_PROBE_NO_NEWLINE=1)
        fi
        if [ "${AGENT_TEST_CODEX_PROBE_NUL:-}" = 1 ]; then
            command_env+=(AGENT_TEST_CODEX_PROBE_NUL=1)
        fi
        if [ -n "${AGENT_TEST_CODEX_PROBE_FILE:-}" ]; then
            command_env+=("AGENT_TEST_CODEX_PROBE_FILE=$AGENT_TEST_CODEX_PROBE_FILE")
        fi
        if [ -n "${AGENT_TEST_CODEX_SQLITE_MARKER:-}" ]; then
            command_env+=("AGENT_TEST_CODEX_SQLITE_MARKER=$AGENT_TEST_CODEX_SQLITE_MARKER")
        fi
        if [ -n "${AGENT_TEST_UPSTREAM_STARTED:-}" ]; then
            command_env+=("AGENT_TEST_UPSTREAM_STARTED=$AGENT_TEST_UPSTREAM_STARTED")
        fi
        if [ "${AGENT_TEST_CODEX_FAST_BACKUP_DEADLINE:-}" = 1 ]; then
            command_env+=(AGENT_TEST_CODEX_FAST_BACKUP_DEADLINE=1)
        fi
        if [ -n "${AGENT_TEST_CODEX_TIMEOUT_PID_FILE:-}" ]; then
            command_env+=("AGENT_TEST_CODEX_TIMEOUT_PID_FILE=$AGENT_TEST_CODEX_TIMEOUT_PID_FILE")
        fi
        if [ -n "${AGENT_TEST_CODEX_TIMEOUT_CHILD_PID_FILE:-}" ]; then
            command_env+=(
                "AGENT_TEST_CODEX_TIMEOUT_CHILD_PID_FILE=$AGENT_TEST_CODEX_TIMEOUT_CHILD_PID_FILE"
            )
        fi
        if [ "${AGENT_TEST_CODEX_SQLITE_HOME+x}" = x ]; then
            command_env+=("CODEX_SQLITE_HOME=$AGENT_TEST_CODEX_SQLITE_HOME")
        fi
        if [ -n "${AGENT_TEST_STAT_WRONG_OWNER_PATH:-}" ]; then
            command_env+=("AGENT_TEST_STAT_WRONG_OWNER_PATH=$AGENT_TEST_STAT_WRONG_OWNER_PATH")
        fi
        ;;
    *) fail "unknown client: $client" ;;
    esac

    if [ "$bypass" = 1 ]; then
        command_env+=(AI_NIX_BYPASS_MANAGED_CONFIG=1)
    fi

    if "${command_env[@]}" "$binary" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"; then
        LAST_STATUS=0
    else
        LAST_STATUS=$?
    fi
}

assert_argv() {
    local file=$1
    shift
    local value index=0
    local -a actual=()

    [ -f "$file" ] || fail "upstream argv was not recorded"
    while IFS= read -r -d '' value; do
        actual+=("$value")
    done <"$file"

    [ "${#actual[@]}" -eq "$#" ] ||
        fail "argv length differs: expected $#, got ${#actual[@]}"
    for value in "$@"; do
        [ "${actual[$index]}" = "$value" ] ||
            fail "argv[$index] differs"
        index=$((index + 1))
    done
}

assert_env() {
    local expected=$1
    [ -f "$ENV_FILE" ] || fail "upstream environment was not recorded"
    grep -zFx -- "$expected" "$ENV_FILE" >/dev/null ||
        fail "missing upstream environment entry: $expected"
}

assert_env_name_absent() {
    local name=$1
    [ -f "$ENV_FILE" ] || fail "upstream environment was not recorded"
    if tr '\0' '\n' <"$ENV_FILE" | grep -E "^${name}=" >/dev/null; then
        fail "unexpected upstream environment entry: $name"
    fi
}

assert_network_guard_loaded() {
    local file=$1
    local program=$2
    local pid=${3:-'[0-9]+'}
    local pattern

    case "$program" in
    claude) pattern='[^:]*claude[^:]*' ;;
    codex) pattern='[^:]*codex[^:]*' ;;
    *) fail "unknown guarded program: $program" ;;
    esac
    grep -E "^loaded:$pid:$pattern$" "$file" >/dev/null || {
        sed 's/^/network-guard event: /' "$file" >&2 || true
        fail "network guard did not load in final $program process"
    }
}

assert_upstream_not_invoked() {
    [ ! -e "$ARGV_FILE" ] && [ ! -e "$ENV_FILE" ] ||
        fail "upstream ran during a rejected launch"
}

assert_bounded_redacted_error() {
    local client=$1
    local require_paths=$2
    local bytes

    bytes=$(wc -c <"$STDERR_FILE")
    [ "$bytes" -gt 0 ] && [ "$bytes" -le 512 ] ||
        fail "$client error is empty or exceeds 512 bytes"
    grep -F -- "$(client_display_name "$client")" "$STDERR_FILE" >/dev/null ||
        fail "$client error does not identify the client"
    if [ "$require_paths" = 1 ]; then
        grep -F -- "$FIRST" "$STDERR_FILE" >/dev/null ||
            fail "$client partial-state error omits the first artifact path"
        if [ -n "$SECOND" ]; then
            grep -F -- "$SECOND" "$STDERR_FILE" >/dev/null ||
                fail "$client partial-state error omits the second artifact path"
        fi
    fi
    ! grep -F -- "$managed_file_sentinel" "$STDERR_FILE" >/dev/null ||
        fail "$client error leaked managed file content"
    [ ! -s "$STDOUT_FILE" ] || fail "$client rejection wrote to stdout"
}

assert_managed_argv() {
    local client=$1
    shift
    case "$client" in
    claude) assert_argv "$ARGV_FILE" --settings "$FIRST" "--mcp-config=$SECOND" "$@" ;;
    codex) assert_argv "$ARGV_FILE" --profile nix-runtime "$@" ;;
    *) fail "unknown client: $client" ;;
    esac
}

test_state_matrix() {
    local client=$1
    local state
    local -a partial_states=(
        dangling
        directories
        fifos
    )
    if [ "$client" != codex ]; then
        partial_states+=(
            left-only
            right-only
            regular-dangling
            regular-directory
            regular-fifo
        )
    fi
    local -a all_states=(zero complete symlink-complete "${partial_states[@]}")
    local -a launch_args=(alpha 'two words')
    if [ "$client" = codex ]; then
        launch_args=('two words')
    fi

    new_case "$client" zero
    configure_state zero
    invoke_agent "$client" 0 0 "${launch_args[@]}"
    [ "$LAST_STATUS" -eq 0 ] || fail "$client zero state did not pass through"
    assert_argv "$ARGV_FILE" "${launch_args[@]}"
    finish_case "$client"

    for state in complete symlink-complete; do
        new_case "$client" "$state"
        configure_state "$state"
        invoke_agent "$client" 0 0 "${launch_args[@]}"
        [ "$LAST_STATUS" -eq 0 ] || fail "$client $state state did not launch"
        assert_managed_argv "$client" "${launch_args[@]}"
        finish_case "$client"
    done

    for state in "${partial_states[@]}"; do
        new_case "$client" "$state"
        configure_state "$state"
        invoke_agent "$client" 0 0 "${launch_args[@]}"
        [ "$LAST_STATUS" -eq 2 ] ||
            fail "$client partial state $state returned $LAST_STATUS instead of 2"
        assert_upstream_not_invoked
        assert_bounded_redacted_error "$client" 1
        finish_case "$client"
    done

    for state in "${all_states[@]}"; do
        new_case "$client" "bypass-$state"
        configure_state "$state"
        invoke_agent "$client" 1 0 "${launch_args[@]}"
        [ "$LAST_STATUS" -eq 0 ] || fail "$client bypass failed for state $state"
        assert_argv "$ARGV_FILE" "${launch_args[@]}"
        assert_env AI_NIX_BYPASS_MANAGED_CONFIG=1
        finish_case "$client"
    done
}

test_unset_home_bypass() {
    local client=$1
    local binary

    new_case "$client" bypass-unset-home
    configure_state complete
    rm -f -- "$ARGV_FILE" "$ENV_FILE" "$STDOUT_FILE" "$STDERR_FILE"
    case "$client" in
    claude) binary=$CLAUDE_BIN ;;
    *) fail "unset-HOME bypass is unsupported for $client" ;;
    esac

    if env \
        -u HOME \
        -u CLAUDE_CONFIG_DIR \
        -u CODEX_HOME \
        -u CODEX_SQLITE_HOME \
        AI_NIX_BYPASS_MANAGED_CONFIG=1 \
        "AGENT_TEST_ARGV=$ARGV_FILE" \
        "AGENT_TEST_ENV=$ENV_FILE" \
        AGENT_TEST_EXIT=0 \
        "AGENT_TEST_UID=$AGENT_TEST_UID" \
        "$binary" alpha 'two words' >"$STDOUT_FILE" 2>"$STDERR_FILE"; then
        LAST_STATUS=0
    else
        LAST_STATUS=$?
    fi

    [ "$LAST_STATUS" -eq 0 ] || fail "$client bypass required HOME"
    assert_argv "$ARGV_FILE" alpha 'two words'
    assert_env AI_NIX_BYPASS_MANAGED_CONFIG=1
}

test_claude_default_root() {
    local mode

    for mode in unset empty; do
        new_case claude "default-root-$mode"
        ROOT="$HOME_DIR/.claude"
        FIRST="$ROOT/nix-managed-settings.json"
        SECOND="$ROOT/nix-managed-mcp.json"
        mkdir -p "$ROOT"
        configure_state complete

        AGENT_TEST_CLAUDE_CONFIG_MODE=$mode
        invoke_agent claude 0 0 alpha
        unset AGENT_TEST_CLAUDE_CONFIG_MODE

        [ "$LAST_STATUS" -eq 0 ] || fail "Claude $mode config-dir fallback failed"
        assert_managed_argv claude alpha
        finish_case claude
    done
}

test_one_conflict() {
    local client=$1
    local label=$2
    local AGENT_TEST_CODEX_POLICY=manage
    shift 2

    if [ "$client" = codex ]; then
        case "$label" in
        ignore-user-config*) AGENT_TEST_CODEX_POLICY=conflict-ignore-user-config ;;
        *) AGENT_TEST_CODEX_POLICY=conflict-profile ;;
        esac
    fi

    new_case "$client" "conflict-$label"
    configure_state complete
    invoke_agent "$client" 0 0 "$@"
    [ "$LAST_STATUS" -eq 2 ] ||
        fail "$client conflicting $label returned $LAST_STATUS instead of 2"
    assert_upstream_not_invoked
    assert_bounded_redacted_error "$client" 0
    finish_case "$client"

    new_case "$client" "zero-conflict-$label"
    configure_state zero
    invoke_agent "$client" 0 0 "$@"
    [ "$LAST_STATUS" -eq 0 ] || fail "$client rejected $label in pass-through mode"
    assert_argv "$ARGV_FILE" "$@"
    finish_case "$client"

    new_case "$client" "bypass-conflict-$label"
    configure_state complete
    invoke_agent "$client" 1 0 "$@"
    [ "$LAST_STATUS" -eq 0 ] || fail "$client rejected $label in bypass mode"
    assert_argv "$ARGV_FILE" "$@"
    finish_case "$client"
}

test_conflicts() {
    local client=$1
    local caller_path="$work_root/caller supplied path"

    case "$client" in
    claude)
        test_one_conflict "$client" settings-separated --settings "$caller_path" tail
        test_one_conflict "$client" settings-equals "--settings=$caller_path" tail
        test_one_conflict "$client" mcp-separated --mcp-config "$caller_path" tail
        test_one_conflict "$client" mcp-equals "--mcp-config=$caller_path" tail

        new_case "$client" conflict-delimiter
        configure_state complete
        invoke_agent "$client" 0 0 -- --settings "$caller_path" --mcp-config "$caller_path"
        [ "$LAST_STATUS" -eq 0 ] || fail "$client scanned conflicts after --"
        assert_managed_argv "$client" -- --settings "$caller_path" --mcp-config "$caller_path"
        finish_case "$client"
        ;;
    codex)
        # Codex's own Clap graph recognizes spellings and payload boundaries.
        # This fake-package contract only verifies the wrapper's responses.
        test_one_conflict "$client" profile --profile caller tail
        test_one_conflict "$client" ignore-user-config \
            exec --ignore-user-config tail
        ;;
    *) fail "unknown client: $client" ;;
    esac
}

test_codex_managed_case() {
    local label=$1
    shift

    new_case codex "$label"
    configure_state complete
    invoke_agent codex 0 0 "$@"
    [ "$LAST_STATUS" -eq 0 ] || fail "Codex rejected managed case $label"
    assert_managed_argv codex "$@"
    finish_case codex
}

test_codex_delegated_case() {
    local label=$1
    local AGENT_TEST_CODEX_POLICY=delegate
    shift

    new_case codex "$label"
    configure_state complete
    invoke_agent codex 0 0 "$@"
    [ "$LAST_STATUS" -eq 0 ] || fail "Codex rejected delegated case $label"
    assert_argv "$ARGV_FILE" "$@"
    finish_case codex
}

test_codex_conflict_case() {
    local label=$1
    local AGENT_TEST_CODEX_POLICY=conflict-profile
    shift

    new_case codex "$label"
    configure_state complete
    invoke_agent codex 0 0 "$@"
    [ "$LAST_STATUS" -eq 2 ] ||
        fail "Codex conflicting profile case $label returned $LAST_STATUS instead of 2"
    assert_upstream_not_invoked
    assert_bounded_redacted_error codex 0
    finish_case codex
}

test_codex_probe_rejection_case() {
    local label=$1
    local AGENT_TEST_CODEX_POLICY=$2
    local AGENT_TEST_CODEX_PROBE_EXIT=$3
    local AGENT_TEST_CODEX_PROBE_NO_OUTPUT=$4
    local AGENT_TEST_CODEX_PROBE_NO_NEWLINE=$5
    local AGENT_TEST_CODEX_PROBE_NUL=${6:-0}

    new_case codex "probe-rejection-$label"
    configure_state complete
    invoke_agent codex 0 0 opaque --future-payload
    [ "$LAST_STATUS" -eq 2 ] ||
        fail "Codex unsafe probe response $label returned $LAST_STATUS instead of 2"
    assert_upstream_not_invoked
    assert_bounded_redacted_error codex 0
    finish_case codex
}

test_codex_policy_protocol() {
    test_codex_managed_case protocol-manage opaque --future-payload
    assert_env_name_absent CODEX_INTERNAL_WRAPPER_POLICY_PROBE

    test_codex_delegated_case protocol-delegate features future-subcommand
    assert_env_name_absent CODEX_INTERNAL_WRAPPER_POLICY_PROBE

    test_codex_conflict_case protocol-profile-conflict --profile caller opaque

    test_codex_probe_rejection_case unknown future-policy 0 0 0
    test_codex_probe_rejection_case multiline $'manage\nextra' 0 0 0
    test_codex_probe_rejection_case missing-newline manage 0 0 1
    test_codex_probe_rejection_case missing-output manage 0 1 0
    test_codex_probe_rejection_case embedded-nul manage 0 0 0 1
    test_codex_probe_rejection_case nonzero manage 74 0 0

    new_case codex inherited-private-probe-variable
    configure_state complete
    local AGENT_TEST_CODEX_POLICY=delegate
    CODEX_INTERNAL_WRAPPER_POLICY_PROBE=caller-controlled
    export CODEX_INTERNAL_WRAPPER_POLICY_PROBE
    invoke_agent codex 0 0 --version
    unset CODEX_INTERNAL_WRAPPER_POLICY_PROBE
    [ "$LAST_STATUS" -eq 0 ] || fail "Codex rejected delegated inherited-probe case"
    assert_argv "$ARGV_FILE" --version
    assert_env_name_absent CODEX_INTERNAL_WRAPPER_POLICY_PROBE
    finish_case codex
}

test_codex_policy_response_checker() {
    local response_file="$work_root/policy-response"

    printf '%s\n' manage >"$response_file"
    "$CODEX_POLICY_RESPONSE_CHECKER" manage "$response_file" ||
        fail "packaging response checker rejected an exact response"

    printf %s manage >"$response_file"
    if "$CODEX_POLICY_RESPONSE_CHECKER" manage "$response_file"; then
        fail "packaging response checker accepted a missing newline"
    fi
    printf 'manage\nextra\n' >"$response_file"
    if "$CODEX_POLICY_RESPONSE_CHECKER" manage "$response_file"; then
        fail "packaging response checker accepted extra output"
    fi
    printf 'man\0age\n' >"$response_file"
    if "$CODEX_POLICY_RESPONSE_CHECKER" manage "$response_file"; then
        fail "packaging response checker accepted an embedded NUL"
    fi
    : >"$response_file"
    if "$CODEX_POLICY_RESPONSE_CHECKER" manage "$response_file"; then
        fail "packaging response checker accepted empty output"
    fi
}

test_codex_interrupted_policy_probe() {
    local ready release wrapper_pid status=0

    new_case codex interrupted-policy-probe
    configure_state complete
    ready="$CASE_DIR/probe.ready"
    release="$CASE_DIR/probe.release"

    env \
        -u AI_NIX_BYPASS_MANAGED_CONFIG \
        -u CODEX_HOME \
        -u CODEX_SQLITE_HOME \
        "HOME=$HOME_DIR" \
        "CODEX_HOME=$ROOT" \
        "AGENT_TEST_ARGV=$ARGV_FILE" \
        "AGENT_TEST_ENV=$ENV_FILE" \
        AGENT_TEST_EXIT=0 \
        "AGENT_TEST_UID=$AGENT_TEST_UID" \
        AGENT_TEST_CODEX_POLICY=manage \
        "AGENT_TEST_CODEX_PROBE_READY=$ready" \
        "AGENT_TEST_CODEX_PROBE_RELEASE=$release" \
        "$CODEX_BIN" opaque >"$STDOUT_FILE" 2>"$STDERR_FILE" &
    wrapper_pid=$!

    for _ in {1..500}; do
        [ ! -e "$ready" ] || break
        kill -0 "$wrapper_pid" 2>/dev/null || break
        sleep 0.01
    done
    [ -e "$ready" ] || fail "Codex probe did not reach its interrupt point"

    kill -TERM "$wrapper_pid"
    touch "$release"
    wait "$wrapper_pid" || status=$?

    [ "$status" -eq 143 ] ||
        fail "Codex interrupted probe returned $status instead of 143"
    assert_upstream_not_invoked
    if find "$CODEX_LOCAL_ROOT" -maxdepth 1 -name '.wrapper-policy.*' \
        -print -quit | grep . >/dev/null; then
        fail "Codex interrupted probe retained a policy response file"
    fi
    finish_case codex
}

test_codex_open_file_limit_case() {
    local label=$1
    local binary=$2
    local bypass=$3
    local expected=$4
    local hard_limit=${5:-}

    new_case codex "$label"
    configure_state zero
    (
        ulimit -Sn 256
        if [ -n "$hard_limit" ]; then
            ulimit -Hn "$hard_limit"
        fi
        CODEX_BIN=$binary invoke_agent codex "$bypass" 0 alpha
        [ "$LAST_STATUS" -eq 0 ] || fail "Codex open-file limit case failed: $label"
        assert_argv "$ARGV_FILE" alpha
        assert_env "AGENT_TEST_OPEN_FILE_LIMIT=$expected"
    )
    finish_case codex
}

test_codex_open_file_limit() {
    local expected=256
    if [ "$CODEX_RAISES_OPEN_FILE_LIMIT" = 1 ]; then
        expected=65536
        test_codex_open_file_limit_case finite-hard-limit \
            "$CODEX_BIN" 0 4096 4096
    fi
    test_codex_open_file_limit_case primary-limit "$CODEX_BIN" 0 "$expected"
    test_codex_open_file_limit_case primary-bypass-limit "$CODEX_BIN" 1 "$expected"

    new_case codex primary-managed-limit
    configure_state complete
    (
        ulimit -Sn 256
        invoke_agent codex 0 0 alpha
        [ "$LAST_STATUS" -eq 0 ] || fail "Codex managed open-file limit case failed"
        assert_managed_argv codex alpha
        assert_env "AGENT_TEST_OPEN_FILE_LIMIT=$expected"
    )
    finish_case codex

    test_codex_open_file_limit_case non-darwin-limit \
        "$CODEX_NON_DARWIN_BIN" 0 256
}

test_exit_propagation() {
    local client=$1

    new_case "$client" exit-propagation
    configure_state complete
    invoke_agent "$client" 0 37 alpha
    [ "$LAST_STATUS" -eq 37 ] || fail "$client did not propagate upstream exit 37"
    assert_managed_argv "$client" alpha
    finish_case "$client"
}

test_environment_contract() {
    local client=$1
    local credential_name=$2
    local credential_value session_value thread_value path
    local before_entries='' after_entries=''
    local -a launch_args=(alpha 'two words')

    if [ "$client" = codex ]; then
        launch_args=('two words')
    fi

    new_case "$client" environment-contract
    configure_state complete
    credential_value="credential-${client}-${AGENT_TEST_UID}-must-not-leak"
    session_value="session-${client}-${AGENT_TEST_UID}"
    thread_value="thread-${client}-${AGENT_TEST_UID}"
    export "$credential_name=$credential_value"
    if [ "$client" = codex ]; then
        export CODEX_SESSION_ID="$session_value"
        export CODEX_THREAD_ID="$thread_value"
    else
        export AGENT_WRAPPER_SESSION_MARKER="$session_value"
        before_entries="$CASE_DIR/before-credential.entries"
        after_entries="$CASE_DIR/after-credential.entries"
        find "$ROOT" -mindepth 1 -printf '%P|%y|%m|%l\n' | sort >"$before_entries"
    fi

    invoke_agent "$client" 0 0 "${launch_args[@]}"
    unset "$credential_name" AGENT_WRAPPER_SESSION_MARKER CODEX_SESSION_ID CODEX_THREAD_ID

    [ "$LAST_STATUS" -eq 0 ] || fail "$client environment contract launch failed"
    assert_managed_argv "$client" "${launch_args[@]}"
    assert_env "$credential_name=$credential_value"
    if [ "$client" = codex ]; then
        assert_env "CODEX_SESSION_ID=$session_value"
        assert_env "CODEX_THREAD_ID=$thread_value"
    else
        assert_env "AGENT_WRAPPER_SESSION_MARKER=$session_value"
    fi

    for path in "$ARGV_FILE" "$STDOUT_FILE" "$STDERR_FILE" "$FIRST"; do
        ! grep -aF -- "$credential_value" "$path" >/dev/null ||
            fail "$client credential escaped its upstream environment"
    done
    if [ -n "$SECOND" ]; then
        ! grep -aF -- "$credential_value" "$SECOND" >/dev/null ||
            fail "$client credential entered a managed companion"
    fi
    if [ "$client" = codex ] && [ -e "$CODEX_RUNTIME_FILE" ]; then
        ! grep -aF -- "$credential_value" "$CODEX_RUNTIME_FILE" >/dev/null ||
            fail "Codex credential entered the runtime profile"
    fi
    ! grep -aR -F -- "$credential_value" "$ROOT" >/dev/null ||
        fail "$client credential entered its managed root"
    if [ "$client" = codex ]; then
        ! grep -aR -F -- "$credential_value" "$CODEX_LOCAL_ROOT" >/dev/null ||
            fail "Codex credential entered host-local state"
    else
        find "$ROOT" -mindepth 1 -printf '%P|%y|%m|%l\n' | sort >"$after_entries"
        cmp "$before_entries" "$after_entries" ||
            fail "$client created or removed state during credential handling"
    fi
    finish_case "$client"
}

test_managed_state_immutable() {
    local client=$1
    local before_entries before_hashes after_entries after_hashes

    [ "$client" != codex ] || fail "Codex managed state is intentionally mutable"
    new_case "$client" managed-state-immutable
    configure_state complete
    before_entries="$CASE_DIR/before.entries"
    before_hashes="$CASE_DIR/before.hashes"
    after_entries="$CASE_DIR/after.entries"
    after_hashes="$CASE_DIR/after.hashes"

    find "$ROOT" -mindepth 1 -maxdepth 1 -printf '%f|%y|%m|%l\n' | sort >"$before_entries"
    sha256sum "$FIRST" "$SECOND" >"$before_hashes"

    invoke_agent "$client" 0 0 alpha
    [ "$LAST_STATUS" -eq 0 ] || fail "$client immutable-state launch failed"
    assert_managed_argv "$client" alpha

    find "$ROOT" -mindepth 1 -maxdepth 1 -printf '%f|%y|%m|%l\n' | sort >"$after_entries"
    sha256sum "$FIRST" "$SECOND" >"$after_hashes"
    cmp "$before_entries" "$after_entries" ||
        fail "$client created or removed managed-root state"
    cmp "$before_hashes" "$after_hashes" ||
        fail "$client changed managed configuration content"
    finish_case "$client"
}

test_process_identity() {
    local client=$1
    local binary expected_argv0 recorded_pid recorded_argv0 wrapper_pid status
    local identity_file
    local -a launch_args=(alpha 'two words')
    local -a command_env

    new_case "$client" process-identity
    configure_state complete
    identity_file="$CASE_DIR/identity"
    if [ "$client" = codex ]; then
        launch_args=('two words')
    fi
    case "$client" in
    claude)
        binary=$CLAUDE_IDENTITY_BIN
        expected_argv0=claude
        ;;
    codex)
        binary=$CODEX_IDENTITY_BIN
        expected_argv0=codex
        ;;
    *) fail "unknown identity client: $client" ;;
    esac

    command_env=(
        env
        -u AI_NIX_BYPASS_MANAGED_CONFIG
        -u CLAUDE_CONFIG_DIR
        -u CODEX_HOME
        -u CODEX_SQLITE_HOME
        "HOME=$HOME_DIR"
        "AGENT_TEST_IDENTITY_FILE=$identity_file"
        AGENT_TEST_EXIT=0
        "AGENT_TEST_UID=$AGENT_TEST_UID"
    )
    case "$client" in
    claude) command_env+=("CLAUDE_CONFIG_DIR=$ROOT") ;;
    codex) command_env+=("CODEX_HOME=$ROOT") ;;
    esac

    "${command_env[@]}" "$binary" "${launch_args[@]}" >"$STDOUT_FILE" 2>"$STDERR_FILE" &
    wrapper_pid=$!
    if wait "$wrapper_pid"; then
        status=0
    else
        status=$?
    fi
    [ "$status" -eq 0 ] || fail "$client identity launch returned $status"
    [ -f "$identity_file" ] || fail "$client identity recorder did not run"
    recorded_pid=$(sed -n '1p' "$identity_file")
    recorded_argv0=$(sed -n '2p' "$identity_file")
    [ "$recorded_pid" = "$wrapper_pid" ] || fail "$client wrapper did not preserve its PID"
    [ "$recorded_argv0" = "$expected_argv0" ] ||
        fail "$client argv[0] is $recorded_argv0, expected $expected_argv0"
    finish_case "$client"
}

test_claude_real_process_identity() {
    local identity_file recorded_pid recorded_argv0 wrapper_pid status

    new_case claude claude-real-process-identity
    configure_state regular-directory
    identity_file="$CASE_DIR/identity"
    env -u HOME -u CLAUDE_CONFIG_DIR -u AI_NIX_BYPASS_MANAGED_CONFIG \
        "AGENT_TEST_IDENTITY_FILE=$identity_file" AGENT_TEST_EXIT=0 \
        "$CLAUDE_REAL_IDENTITY_BIN" alpha >"$STDOUT_FILE" 2>"$STDERR_FILE" &
    wrapper_pid=$!
    if wait "$wrapper_pid"; then
        status=0
    else
        status=$?
    fi
    [ "$status" -eq 0 ] || fail "claude-real identity launch returned $status"
    recorded_pid=$(sed -n '1p' "$identity_file")
    recorded_argv0=$(sed -n '2p' "$identity_file")
    [ "$recorded_pid" = "$wrapper_pid" ] || fail "claude-real did not preserve its PID"
    [ "$recorded_argv0" = claude ] || fail "claude-real argv[0] is not claude"
}

test_claude_real() {
    new_case claude claude-real
    configure_state complete
    rm -f -- "$ARGV_FILE" "$ENV_FILE" "$STDOUT_FILE" "$STDERR_FILE"

    if env \
        -u AI_NIX_BYPASS_MANAGED_CONFIG \
        "HOME=$HOME_DIR" \
        "CLAUDE_CONFIG_DIR=$ROOT" \
        "AGENT_TEST_ARGV=$ARGV_FILE" \
        "AGENT_TEST_ENV=$ENV_FILE" \
        AGENT_TEST_EXIT=41 \
        "AGENT_TEST_UID=$AGENT_TEST_UID" \
        "$CLAUDE_REAL_BIN" alpha 'two words' >"$STDOUT_FILE" 2>"$STDERR_FILE"; then
        LAST_STATUS=0
    else
        LAST_STATUS=$?
    fi

    [ "$LAST_STATUS" -eq 41 ] || fail "claude-real is absent or did not directly propagate exit 41"
    assert_argv "$ARGV_FILE" alpha 'two words'
}

create_codex_sqlite_seed() {
    local database=$1
    local marker=$2

    "$PYTHON_BIN" - "$database" "$marker" <<'PY'
import sqlite3
import sys
from pathlib import Path

path = Path(sys.argv[1])
for suffix in ("", "-shm", "-wal"):
    try:
        Path(str(path) + suffix).unlink()
    except FileNotFoundError:
        pass
with sqlite3.connect(path) as database:
    database.execute("CREATE TABLE seed(marker TEXT NOT NULL)")
    database.execute("INSERT INTO seed VALUES (?)", (sys.argv[2],))
PY
    chmod 600 "$database"
}

create_codex_sqlite_interior_corruption() {
    local database=$1

    "$PYTHON_BIN" - "$database" <<'PY'
import sqlite3
import sys
from pathlib import Path

path = Path(sys.argv[1])
with sqlite3.connect(path) as database:
    database.execute("PRAGMA page_size=1024")
    database.execute("CREATE TABLE seed(marker TEXT NOT NULL, payload BLOB NOT NULL)")
    database.executemany(
        "INSERT INTO seed VALUES (?, ?)",
        ((f"marker-{index}", bytes(400)) for index in range(500)),
    )
    root_page = database.execute(
        "SELECT rootpage FROM sqlite_schema WHERE name = 'seed'"
    ).fetchone()[0]
    page_size = database.execute("PRAGMA page_size").fetchone()[0]

if root_page <= 1:
    raise RuntimeError("fixture did not allocate an interior database page")
with path.open("r+b") as database_file:
    database_file.seek((root_page - 1) * page_size)
    database_file.write(b"\xff")

if path.read_bytes()[:16] != b"SQLite format 3\0":
    raise RuntimeError("fixture damaged the SQLite header")
try:
    with sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True) as database:
        corrupted = database.execute("PRAGMA quick_check").fetchall() != [("ok",)]
except sqlite3.DatabaseError:
    corrupted = True
if not corrupted:
    raise RuntimeError("fixture corruption escaped SQLite quick_check")
PY
    chmod 600 "$database"
}

assert_codex_sqlite_marker() {
    local database=$1
    local expected=$2

    if ! "$PYTHON_BIN" - "$database" "$expected" <<'PY'
import sqlite3
import sys
from pathlib import Path

path = Path(sys.argv[1])
if path.read_bytes()[:16] != b"SQLite format 3\0":
    raise SystemExit(1)
with sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True) as database:
    healthy = database.execute("PRAGMA quick_check").fetchall() == [("ok",)]
    marker = database.execute("SELECT marker FROM seed").fetchone()
raise SystemExit(0 if healthy and marker == (sys.argv[2],) else 1)
PY
    then
        fail "Codex SQLite marker is missing or the database is invalid: $expected"
    fi
}

assert_codex_sqlite_published_form() {
    local database=$1
    local suffix

    if [ "$(
        "$PYTHON_BIN" - "$database" <<'PY'
import sqlite3
import sys
from pathlib import Path

path = Path(sys.argv[1])
with sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True) as database:
    print(database.execute("PRAGMA journal_mode").fetchone()[0])
PY
    )" != delete ]; then
        fail "published Codex SQLite database did not use DELETE journal mode"
    fi
    for suffix in -wal -shm -journal; do
        [ ! -e "$database$suffix" ] ||
            fail "published Codex SQLite database left a $suffix sidecar"
    done
}

assert_no_codex_seed_temporaries() {
    local sqlite_root=$1

    if [ -d "$sqlite_root" ] && find "$sqlite_root" -maxdepth 1 \
        -name '.memories_1.sqlite.seed.*' -print -quit | grep -q .; then
        fail "Codex left a SQLite backup temporary file behind"
    fi
}

assert_codex_host_state() {
    local expected_marker=$1

    assert_env "CODEX_HOME=$ROOT"
    assert_env "CODEX_SQLITE_HOME=$CODEX_LOCAL_ROOT/sqlite"
    [ -f "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite" ] ||
        fail "Codex did not seed host-local SQLite state"
    assert_codex_sqlite_marker \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite" "$expected_marker"
    assert_codex_sqlite_published_form \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite"
    [ "$(stat -c %a "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite")" = 600 ] ||
        fail "Codex local SQLite database does not have mode 0600"
    [ "$(stat -c %a "$CODEX_LOCAL_ROOT")" = 700 ] ||
        fail "Codex local root does not have mode 0700"
    [ "$(stat -c %a "$CODEX_LOCAL_ROOT/sqlite")" = 700 ] ||
        fail "Codex SQLite root does not have mode 0700"
    [ "$(stat -c %a "$CODEX_LOCAL_ROOT/log")" = 700 ] ||
        fail "Codex log root does not have mode 0700"
    [ -L "$ROOT/log" ] || fail "Codex did not create the host-local log link"
    [ "$(readlink "$ROOT/log")" = "$CODEX_LOCAL_ROOT/log" ] ||
        fail "Codex log link has the wrong target"
    [ ! -e "$CODEX_LOCAL_ROOT/sqlite/.memories-seed-lock" ] ||
        fail "Codex left a persistent SQLite backup lock behind"
    assert_no_codex_seed_temporaries "$CODEX_LOCAL_ROOT/sqlite"
}

assert_codex_runtime_profile() {
    [ -L "$CODEX_RUNTIME_LINK" ] ||
        fail "Codex did not create the writable runtime profile link"
    [ "$(readlink "$CODEX_RUNTIME_LINK")" = "$CODEX_RUNTIME_FILE" ] ||
        fail "Codex runtime profile link has the wrong target"
    [ -f "$CODEX_RUNTIME_FILE" ] && [ ! -L "$CODEX_RUNTIME_FILE" ] ||
        fail "Codex runtime profile is not a regular host-local file"
    [ "$(stat -c %a "$CODEX_RUNTIME_FILE")" = 600 ] ||
        fail "Codex runtime profile does not have mode 0600"
    [ -w "$CODEX_RUNTIME_FILE" ] ||
        fail "Codex runtime profile is not writable"
    cmp "$FIRST" "$CODEX_RUNTIME_FILE" ||
        fail "Codex runtime profile does not match the managed template"
    if find "$CODEX_LOCAL_ROOT" -maxdepth 1 \
        -name '.nix-runtime.config.toml.*' -print -quit | grep -q .; then
        fail "Codex left a runtime profile temporary file behind"
    fi
}

assert_codex_runtime_profile_absent() {
    [ ! -e "$CODEX_RUNTIME_LINK" ] && [ ! -L "$CODEX_RUNTIME_LINK" ] ||
        fail "Codex created the runtime profile link outside managed mode"
    [ ! -e "$CODEX_RUNTIME_FILE" ] && [ ! -L "$CODEX_RUNTIME_FILE" ] ||
        fail "Codex created the runtime profile outside managed mode"
}

assert_codex_sqlite_seed_absent() {
    local sqlite_root=$1

    [ ! -e "$sqlite_root/memories_1.sqlite" ] ||
        fail "Codex copied into a rejected SQLite root"
    [ ! -e "$sqlite_root/.memories-seed-lock" ] ||
        fail "Codex locked a rejected SQLite root"
    if [ -d "$sqlite_root" ] && find "$sqlite_root" -maxdepth 1 \
        -name '.memories_1.sqlite.seed.*' \
        -print -quit | grep -q .; then
        fail "Codex created a temporary file in a rejected SQLite root"
    fi
}

start_codex_live_wal_seed() {
    local database=$1
    local marker=$2
    local ready=$3
    local release=$4

    "$PYTHON_BIN" - "$database" "$marker" "$ready" "$release" <<'PY' &
import sqlite3
import sys
import time
from pathlib import Path

database_path, marker, ready_path, release_path = map(Path, sys.argv[1:])
with sqlite3.connect(database_path) as database:
    database.execute("PRAGMA journal_mode=WAL")
    database.execute("PRAGMA wal_autocheckpoint=0")
    database.execute("CREATE TABLE seed(marker TEXT NOT NULL)")
    database.execute("INSERT INTO seed VALUES (?)", (str(marker),))
    database.commit()
    ready_path.touch()
    while not release_path.exists():
        time.sleep(0.01)
PY
    SQLITE_HELPER_PID=$!
}

start_codex_exclusive_holder() {
    local database=$1
    local ready=$2
    local release=$3

    "$PYTHON_BIN" - "$database" "$ready" "$release" <<'PY' &
import sqlite3
import sys
import time
from pathlib import Path

database_path, ready_path, release_path = map(Path, sys.argv[1:])
with sqlite3.connect(database_path, isolation_level=None) as database:
    database.execute("BEGIN EXCLUSIVE")
    ready_path.touch()
    while not release_path.exists():
        time.sleep(0.01)
    database.execute("ROLLBACK")
PY
    SQLITE_HELPER_PID=$!
}

start_codex_seed_launch() {
    local prefix=$1
    local marker=$2
    local source_root=${3:-$ROOT}
    local -a command_env

    command_env=(
        env -u AI_NIX_BYPASS_MANAGED_CONFIG -u CODEX_SQLITE_HOME
        "HOME=$HOME_DIR"
        "CODEX_HOME=$source_root"
        "AGENT_TEST_UID=$AGENT_TEST_UID"
        AGENT_TEST_CODEX_POLICY=manage
        "AGENT_TEST_CODEX_PROBE_FILE=$prefix.probe"
        "AGENT_TEST_CODEX_SQLITE_MARKER=$marker"
        "AGENT_TEST_UPSTREAM_STARTED=$prefix.started"
        "AGENT_TEST_ARGV=$prefix.argv"
        "AGENT_TEST_ENV=$prefix.env"
        AGENT_TEST_EXIT=0
    )
    if [ "${AGENT_TEST_CODEX_FAST_BACKUP_DEADLINE:-}" = 1 ]; then
        command_env+=(AGENT_TEST_CODEX_FAST_BACKUP_DEADLINE=1)
    fi
    if [ -n "${AGENT_TEST_CODEX_TIMEOUT_PID_FILE:-}" ]; then
        command_env+=("AGENT_TEST_CODEX_TIMEOUT_PID_FILE=$AGENT_TEST_CODEX_TIMEOUT_PID_FILE")
    fi
    if [ -n "${AGENT_TEST_CODEX_TIMEOUT_CHILD_PID_FILE:-}" ]; then
        command_env+=(
            "AGENT_TEST_CODEX_TIMEOUT_CHILD_PID_FILE=$AGENT_TEST_CODEX_TIMEOUT_CHILD_PID_FILE"
        )
    fi
    "${command_env[@]}" "$CODEX_BIN" alpha \
        >"$prefix.stdout" 2>"$prefix.stderr" &
    CODEX_LAUNCH_PID=$!
}

wait_for_path() {
    local path=$1
    local pid=$2
    local label=$3
    local attempt

    for ((attempt = 0; attempt < 1000; attempt++)); do
        [ -e "$path" ] && return
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.01
    done
    fail "timed out waiting for $label"
}

wait_for_codex_seed_temporaries() {
    local expected=$1
    local pid=$2
    local attempt count

    for ((attempt = 0; attempt < 1000; attempt++)); do
        count=0
        if [ -d "$CODEX_LOCAL_ROOT/sqlite" ]; then
            count=$(find "$CODEX_LOCAL_ROOT/sqlite" -maxdepth 1 \
                -name '.memories_1.sqlite.seed.*' -type f -print | wc -l)
        fi
        [ "$count" -ge "$expected" ] && return
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.01
    done
    fail "timed out waiting for $expected concurrent SQLite backup temporaries"
}

start_process_watchdog() {
    local pid=$1
    local fired=$2

    "$PYTHON_BIN" - "$pid" "$fired" <<'PY' &
import os
import signal
import sys
import time
from pathlib import Path

time.sleep(5)
Path(sys.argv[2]).touch()
try:
    os.kill(int(sys.argv[1]), signal.SIGKILL)
except ProcessLookupError:
    pass
PY
    WATCHDOG_PID=$!
}

test_codex_runtime_profile() {
    local AGENT_TEST_CODEX_POLICY=manage

    new_case codex runtime-profile-refresh
    configure_state complete
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -eq 0 ] || fail "managed Codex runtime profile launch failed"
    assert_managed_argv codex alpha
    assert_codex_runtime_profile

    printf '%s\n' runtime-selection >"$CODEX_RUNTIME_LINK"
    grep -Fx runtime-selection "$CODEX_RUNTIME_FILE" >/dev/null ||
        fail "Codex runtime profile link is not writable"
    invoke_agent codex 0 0 beta
    [ "$LAST_STATUS" -eq 0 ] || fail "managed Codex runtime profile refresh failed"
    assert_managed_argv codex beta
    assert_codex_runtime_profile
    finish_case codex

    new_case codex runtime-profile-bypass
    configure_state complete
    invoke_agent codex 1 0 alpha
    [ "$LAST_STATUS" -eq 0 ] || fail "Codex bypass launch failed"
    assert_argv "$ARGV_FILE" alpha
    assert_codex_runtime_profile_absent
    finish_case codex

    new_case codex runtime-profile-delegated
    configure_state complete
    AGENT_TEST_CODEX_POLICY=delegate
    invoke_agent codex 0 0 --version
    [ "$LAST_STATUS" -eq 0 ] || fail "Codex delegated launch failed"
    assert_argv "$ARGV_FILE" --version
    assert_codex_runtime_profile_absent
    finish_case codex
}

test_codex_runtime_profile_rejections() {
    new_case codex runtime-link-regular
    configure_state complete
    printf '%s\n' local-collision >"$CODEX_RUNTIME_LINK"
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -ne 0 ] || fail "Codex accepted a regular runtime link path"
    assert_upstream_not_invoked
    assert_bounded_redacted_error codex 0
    finish_case codex

    new_case codex runtime-link-retargeted
    configure_state complete
    ln -s "$CASE_DIR/external runtime" "$CODEX_RUNTIME_LINK"
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -ne 0 ] || fail "Codex accepted a retargeted runtime profile link"
    assert_upstream_not_invoked
    assert_bounded_redacted_error codex 0
    finish_case codex

    new_case codex runtime-file-symlink
    configure_state complete
    mkdir -p "$CODEX_LOCAL_ROOT"
    ln -s "$CASE_DIR/external runtime" "$CODEX_RUNTIME_FILE"
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -ne 0 ] || fail "Codex accepted a symlink runtime profile"
    assert_upstream_not_invoked
    assert_bounded_redacted_error codex 0
    finish_case codex

    new_case codex runtime-file-directory
    configure_state complete
    mkdir -p "$CODEX_RUNTIME_FILE"
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -ne 0 ] || fail "Codex accepted a directory runtime profile"
    assert_upstream_not_invoked
    assert_bounded_redacted_error codex 0
    finish_case codex
}

test_codex_host_state_rejections() {
    local external_sqlite
    local AGENT_TEST_CODEX_PROBE_FILE AGENT_TEST_CODEX_SQLITE_HOME
    local AGENT_TEST_STAT_WRONG_OWNER_PATH AGENT_TEST_UPSTREAM_STARTED

    new_case codex host-state-external-sqlite
    configure_state complete
    external_sqlite="$CASE_DIR/external sqlite"
    mkdir -m 700 "$external_sqlite"
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" codex-external-seed
    AGENT_TEST_CODEX_PROBE_FILE="$CASE_DIR/policy-probe"
    AGENT_TEST_UPSTREAM_STARTED="$CASE_DIR/upstream-started"
    AGENT_TEST_CODEX_SQLITE_HOME=$external_sqlite
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -ne 0 ] || fail "Codex accepted an external SQLite root"
    assert_upstream_not_invoked
    [ ! -e "$AGENT_TEST_CODEX_PROBE_FILE" ] ||
        fail "Codex probed policy before rejecting an external SQLite root"
    [ ! -e "$AGENT_TEST_UPSTREAM_STARTED" ] ||
        fail "Codex launched upstream before rejecting an external SQLite root"
    grep -F 'codex: refusing unapproved SQLite state path' "$STDERR_FILE" >/dev/null ||
        fail "Codex external SQLite failure was not reported at the host-state boundary"
    assert_codex_sqlite_seed_absent "$external_sqlite"
    finish_case codex

    new_case codex host-state-symlinked-sqlite
    configure_state complete
    external_sqlite="$CASE_DIR/external sqlite"
    mkdir -m 700 "$external_sqlite" "$CODEX_LOCAL_ROOT"
    ln -s "$external_sqlite" "$CODEX_LOCAL_ROOT/sqlite"
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" codex-symlink-seed
    AGENT_TEST_CODEX_PROBE_FILE="$CASE_DIR/policy-probe"
    AGENT_TEST_UPSTREAM_STARTED="$CASE_DIR/upstream-started"
    AGENT_TEST_CODEX_SQLITE_HOME=$CODEX_LOCAL_ROOT/sqlite
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -ne 0 ] || fail "Codex accepted a symlinked SQLite root"
    assert_upstream_not_invoked
    [ ! -e "$AGENT_TEST_CODEX_PROBE_FILE" ] ||
        fail "Codex probed policy before rejecting a symlinked SQLite root"
    [ ! -e "$AGENT_TEST_UPSTREAM_STARTED" ] ||
        fail "Codex launched upstream before rejecting a symlinked SQLite root"
    grep -F 'codex: cannot secure state directory' "$STDERR_FILE" >/dev/null ||
        fail "Codex symlinked SQLite failure was not reported at the host-state boundary"
    assert_codex_sqlite_seed_absent "$external_sqlite"
    finish_case codex

    new_case codex host-state-wrong-owner-sqlite
    configure_state complete
    mkdir -m 700 "$CODEX_LOCAL_ROOT" "$CODEX_LOCAL_ROOT/sqlite"
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" codex-owner-seed
    AGENT_TEST_CODEX_PROBE_FILE="$CASE_DIR/policy-probe"
    AGENT_TEST_UPSTREAM_STARTED="$CASE_DIR/upstream-started"
    AGENT_TEST_CODEX_SQLITE_HOME=$CODEX_LOCAL_ROOT/sqlite
    AGENT_TEST_STAT_WRONG_OWNER_PATH=$CODEX_LOCAL_ROOT/sqlite
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -ne 0 ] || fail "Codex accepted a wrong-owner SQLite root"
    assert_upstream_not_invoked
    [ ! -e "$AGENT_TEST_CODEX_PROBE_FILE" ] ||
        fail "Codex probed policy before rejecting a wrong-owner SQLite root"
    [ ! -e "$AGENT_TEST_UPSTREAM_STARTED" ] ||
        fail "Codex launched upstream before rejecting a wrong-owner SQLite root"
    grep -F 'codex: cannot secure state directory' "$STDERR_FILE" >/dev/null ||
        fail "Codex wrong-owner SQLite failure was not reported at the host-state boundary"
    assert_codex_sqlite_seed_absent "$CODEX_LOCAL_ROOT/sqlite"
    finish_case codex

    new_case codex host-state-permissive-sqlite
    configure_state complete
    mkdir -m 700 "$CODEX_LOCAL_ROOT"
    mkdir -m 755 "$CODEX_LOCAL_ROOT/sqlite"
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" codex-mode-seed
    AGENT_TEST_CODEX_PROBE_FILE="$CASE_DIR/policy-probe"
    AGENT_TEST_UPSTREAM_STARTED="$CASE_DIR/upstream-started"
    AGENT_TEST_CODEX_SQLITE_HOME=$CODEX_LOCAL_ROOT/sqlite
    unset AGENT_TEST_STAT_WRONG_OWNER_PATH
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -ne 0 ] || fail "Codex accepted a permissive SQLite root"
    assert_upstream_not_invoked
    [ ! -e "$AGENT_TEST_CODEX_PROBE_FILE" ] ||
        fail "Codex probed policy before rejecting a permissive SQLite root"
    [ ! -e "$AGENT_TEST_UPSTREAM_STARTED" ] ||
        fail "Codex launched upstream before rejecting a permissive SQLite root"
    [ "$(stat -c %a "$CODEX_LOCAL_ROOT/sqlite")" = 755 ] ||
        fail "Codex changed a rejected permissive SQLite root"
    grep -F 'codex: cannot secure state directory' "$STDERR_FILE" >/dev/null ||
        fail "Codex permissive SQLite failure was not reported at the host-state boundary"
    assert_codex_sqlite_seed_absent "$CODEX_LOCAL_ROOT/sqlite"
    unset AGENT_TEST_CODEX_SQLITE_HOME
    finish_case codex

    new_case codex host-state-wrong-log-link
    configure_state complete
    unset AGENT_TEST_CODEX_SQLITE_HOME AGENT_TEST_STAT_WRONG_OWNER_PATH
    mkdir -p "$CASE_DIR/wrong-log-target"
    ln -s "$CASE_DIR/wrong-log-target" "$ROOT/log"
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -ne 0 ] || fail "Codex accepted a host-state log link with the wrong target"
    assert_upstream_not_invoked
    grep -F 'codex: refusing host-local log path' "$STDERR_FILE" >/dev/null ||
        fail "Codex wrong-log-link failure was not reported at the host-state boundary"
    finish_case codex

    new_case codex host-state-plain-log-directory
    configure_state complete
    mkdir -p "$ROOT/log"
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -ne 0 ] || fail "Codex accepted a plain host-state log directory"
    assert_upstream_not_invoked
    grep -F 'codex: refusing host-local log path' "$STDERR_FILE" >/dev/null ||
        fail "Codex plain-log-directory failure was not reported at the host-state boundary"
    finish_case codex
}

test_codex_unapproved_sqlite_routing() {
    local route state bypass policy external_parent external_sqlite
    local AGENT_TEST_CODEX_POLICY AGENT_TEST_CODEX_PROBE_FILE
    local AGENT_TEST_CODEX_SQLITE_HOME AGENT_TEST_UPSTREAM_STARTED

    for route in zero managed delegated bypass; do
        case "$route" in
        zero)
            state=zero
            bypass=0
            policy=manage
            ;;
        managed)
            state=complete
            bypass=0
            policy=manage
            ;;
        delegated)
            state=complete
            bypass=0
            policy=delegate
            ;;
        bypass)
            state=complete
            bypass=1
            policy=manage
            ;;
        esac

        new_case codex "unapproved-sqlite-$route"
        configure_state "$state"
        create_codex_sqlite_seed "$ROOT/memories_1.sqlite" "route-$route"
        external_parent="$CASE_DIR/nonexistent external parent"
        external_sqlite="$external_parent/sqlite"
        AGENT_TEST_CODEX_POLICY=$policy
        AGENT_TEST_CODEX_PROBE_FILE="$CASE_DIR/policy-probe"
        AGENT_TEST_CODEX_SQLITE_HOME=$external_sqlite
        AGENT_TEST_UPSTREAM_STARTED="$CASE_DIR/upstream-started"
        invoke_agent codex "$bypass" 0 alpha
        [ "$LAST_STATUS" -ne 0 ] ||
            fail "Codex accepted an unapproved SQLite root in $route routing"
        assert_upstream_not_invoked
        [ ! -e "$AGENT_TEST_CODEX_PROBE_FILE" ] ||
            fail "Codex probed policy before SQLite validation in $route routing"
        [ ! -e "$AGENT_TEST_UPSTREAM_STARTED" ] ||
            fail "Codex launched upstream before SQLite validation in $route routing"
        [ ! -e "$external_parent" ] ||
            fail "Codex mutated a nonexistent external target in $route routing"
        [ ! -e "$CODEX_LOCAL_ROOT" ] ||
            fail "Codex created local state before rejecting $route routing"
        grep -F 'codex: refusing unapproved SQLite state path' \
            "$STDERR_FILE" >/dev/null ||
            fail "Codex omitted the unapproved SQLite error in $route routing"
        finish_case codex
    done
}

test_codex_parent_root_rejections() {
    local mode external_root
    local AGENT_TEST_CODEX_PROBE_FILE AGENT_TEST_CODEX_SQLITE_HOME
    local AGENT_TEST_STAT_WRONG_OWNER_PATH AGENT_TEST_UPSTREAM_STARTED

    new_case codex host-state-symlinked-parent-root
    configure_state complete
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" parent-symlink
    external_root="$CASE_DIR/external parent root"
    mkdir -m 700 "$external_root"
    ln -s "$external_root" "$CODEX_LOCAL_ROOT"
    AGENT_TEST_CODEX_PROBE_FILE="$CASE_DIR/policy-probe"
    AGENT_TEST_UPSTREAM_STARTED="$CASE_DIR/upstream-started"
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -ne 0 ] || fail "Codex accepted a symlinked parent root"
    assert_upstream_not_invoked
    [ ! -e "$AGENT_TEST_CODEX_PROBE_FILE" ] ||
        fail "Codex probed policy before rejecting a symlinked parent root"
    [ ! -e "$AGENT_TEST_UPSTREAM_STARTED" ] ||
        fail "Codex launched upstream before rejecting a symlinked parent root"
    test -z "$(find "$external_root" -mindepth 1 -print -quit)" ||
        fail "Codex mutated the target of a symlinked parent root"
    grep -F 'not a private directory owned by uid' "$STDERR_FILE" >/dev/null ||
        fail "Codex omitted the symlinked parent-root diagnostic"
    finish_case codex

    new_case codex host-state-wrong-owner-parent-root
    configure_state complete
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" parent-owner
    mkdir -m 700 "$CODEX_LOCAL_ROOT"
    AGENT_TEST_CODEX_PROBE_FILE="$CASE_DIR/policy-probe"
    AGENT_TEST_CODEX_SQLITE_HOME=$CODEX_LOCAL_ROOT/sqlite
    AGENT_TEST_STAT_WRONG_OWNER_PATH=$CODEX_LOCAL_ROOT
    AGENT_TEST_UPSTREAM_STARTED="$CASE_DIR/upstream-started"
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -ne 0 ] || fail "Codex accepted a wrong-owner parent root"
    assert_upstream_not_invoked
    [ ! -e "$CODEX_LOCAL_ROOT/sqlite" ] && [ ! -e "$CODEX_LOCAL_ROOT/log" ] ||
        fail "Codex created child state beneath a wrong-owner parent root"
    [ ! -e "$AGENT_TEST_CODEX_PROBE_FILE" ] ||
        fail "Codex probed policy before rejecting a wrong-owner parent root"
    [ ! -e "$AGENT_TEST_UPSTREAM_STARTED" ] ||
        fail "Codex launched upstream before rejecting a wrong-owner parent root"
    grep -F 'not a private directory owned by uid' "$STDERR_FILE" >/dev/null ||
        fail "Codex omitted the wrong-owner parent-root diagnostic"
    finish_case codex

    for mode in 750 755; do
        new_case codex "host-state-parent-mode-$mode"
        configure_state complete
        create_codex_sqlite_seed "$ROOT/memories_1.sqlite" "parent-mode-$mode"
        mkdir -m "$mode" "$CODEX_LOCAL_ROOT"
        unset AGENT_TEST_CODEX_SQLITE_HOME AGENT_TEST_STAT_WRONG_OWNER_PATH
        if [ "$mode" = 755 ]; then
            AGENT_TEST_CODEX_SQLITE_HOME=$CODEX_LOCAL_ROOT/sqlite
        fi
        AGENT_TEST_CODEX_PROBE_FILE="$CASE_DIR/policy-probe"
        AGENT_TEST_UPSTREAM_STARTED="$CASE_DIR/upstream-started"
        invoke_agent codex 0 0 alpha
        [ "$LAST_STATUS" -ne 0 ] ||
            fail "Codex accepted a mode $mode parent root"
        assert_upstream_not_invoked
        [ "$(stat -c %a "$CODEX_LOCAL_ROOT")" = "$mode" ] ||
            fail "Codex changed a rejected mode $mode parent root"
        [ ! -e "$CODEX_LOCAL_ROOT/sqlite" ] && [ ! -e "$CODEX_LOCAL_ROOT/log" ] ||
            fail "Codex created child state beneath a mode $mode parent root"
        [ ! -e "$AGENT_TEST_CODEX_PROBE_FILE" ] ||
            fail "Codex probed policy before rejecting a mode $mode parent root"
        [ ! -e "$AGENT_TEST_UPSTREAM_STARTED" ] ||
            fail "Codex launched upstream before rejecting a mode $mode parent root"
        grep -F 'not a private directory owned by uid' "$STDERR_FILE" >/dev/null ||
            fail "Codex omitted the mode $mode parent-root diagnostic"
        finish_case codex
    done
}

test_codex_host_state() {
    local marker
    local AGENT_TEST_CODEX_POLICY=manage
    local AGENT_TEST_CODEX_SQLITE_HOME AGENT_TEST_CODEX_SQLITE_MARKER

    new_case codex host-state-managed
    configure_state complete
    marker=codex-seed-managed
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" "$marker"
    AGENT_TEST_CODEX_SQLITE_MARKER=$marker
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -eq 0 ] || fail "managed Codex host-state launch failed"
    assert_managed_argv codex alpha
    assert_codex_host_state "$marker"
    finish_case codex

    new_case codex host-state-approved-inherited-sqlite
    configure_state complete
    marker=codex-seed-inherited
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" "$marker"
    AGENT_TEST_CODEX_SQLITE_HOME=$CODEX_LOCAL_ROOT/sqlite
    AGENT_TEST_CODEX_SQLITE_MARKER=$marker
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -eq 0 ] || fail "approved inherited Codex SQLite root failed"
    assert_managed_argv codex alpha
    assert_codex_host_state "$marker"
    unset AGENT_TEST_CODEX_SQLITE_HOME
    finish_case codex

    new_case codex host-state-zero
    configure_state zero
    marker=codex-seed-zero
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" "$marker"
    AGENT_TEST_CODEX_SQLITE_MARKER=$marker
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -eq 0 ] || fail "zero-state Codex host-state launch failed"
    assert_argv "$ARGV_FILE" alpha
    assert_codex_host_state "$marker"
    finish_case codex

    new_case codex host-state-delegated
    configure_state complete
    marker=codex-seed-delegated
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" "$marker"
    AGENT_TEST_CODEX_POLICY=delegate
    AGENT_TEST_CODEX_SQLITE_MARKER=$marker
    invoke_agent codex 0 0 --version
    [ "$LAST_STATUS" -eq 0 ] || fail "delegated Codex host-state launch failed"
    assert_argv "$ARGV_FILE" --version
    assert_codex_host_state "$marker"
    finish_case codex

    new_case codex host-state-bypass
    configure_state complete
    marker=codex-seed-bypass
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" "$marker"
    AGENT_TEST_CODEX_POLICY=manage
    AGENT_TEST_CODEX_SQLITE_MARKER=$marker
    invoke_agent codex 1 0 alpha
    [ "$LAST_STATUS" -eq 0 ] || fail "bypass Codex host-state launch failed"
    assert_argv "$ARGV_FILE" alpha
    assert_codex_host_state "$marker"
    finish_case codex
}

test_codex_log_rotation() {
    local holder_pid holder_status ready release sqlite_root
    local AGENT_TEST_CODEX_LSOF_ERROR

    new_case codex log-rotation-over-cap
    configure_state zero
    sqlite_root="$CODEX_LOCAL_ROOT/sqlite"
    mkdir -m 700 "$CODEX_LOCAL_ROOT"
    mkdir -m 700 "$sqlite_root"
    printf 'unrelated-state' >"$sqlite_root/state_5.sqlite"
    truncate -s $((900 * 1024 * 1024)) "$sqlite_root/logs_2.sqlite"
    truncate -s $((100 * 1024 * 1024)) "$sqlite_root/logs_2.sqlite-wal"
    truncate -s $((50 * 1024 * 1024)) "$sqlite_root/logs_2.sqlite-shm"
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -eq 0 ] ||
        fail "Codex launch with an oversized log database failed"
    assert_argv "$ARGV_FILE" alpha
    [ ! -e "$sqlite_root/logs_2.sqlite" ] ||
        fail "Codex did not rotate an oversized log database"
    [ ! -e "$sqlite_root/logs_2.sqlite-wal" ] ||
        fail "Codex did not rotate an oversized log database WAL"
    [ ! -e "$sqlite_root/logs_2.sqlite-shm" ] ||
        fail "Codex did not rotate an oversized log database shared memory"
    [ "$(cat "$sqlite_root/state_5.sqlite")" = unrelated-state ] ||
        fail "Codex log rotation modified an unrelated database"
    grep -F 'rotating oversized log database' "$STDERR_FILE" >/dev/null ||
        fail "Codex log rotation did not warn"
    finish_case codex

    new_case codex log-rotation-under-cap
    configure_state zero
    sqlite_root="$CODEX_LOCAL_ROOT/sqlite"
    mkdir -m 700 "$CODEX_LOCAL_ROOT"
    mkdir -m 700 "$sqlite_root"
    truncate -s $((512 * 1024 * 1024)) "$sqlite_root/logs_2.sqlite"
    truncate -s $((256 * 1024 * 1024)) "$sqlite_root/logs_2.sqlite-wal"
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -eq 0 ] ||
        fail "Codex launch with an in-budget log database failed"
    assert_argv "$ARGV_FILE" alpha
    [ -f "$sqlite_root/logs_2.sqlite" ] && [ -f "$sqlite_root/logs_2.sqlite-wal" ] ||
        fail "Codex rotated an in-budget log database"
    if grep -F 'rotating oversized log database' "$STDERR_FILE" >/dev/null; then
        fail "Codex warned about an in-budget log database"
    fi
    finish_case codex

    new_case codex log-rotation-symlink-uncounted
    configure_state zero
    sqlite_root="$CODEX_LOCAL_ROOT/sqlite"
    mkdir -m 700 "$CODEX_LOCAL_ROOT"
    mkdir -m 700 "$sqlite_root"
    truncate -s $((2048 * 1024 * 1024)) "$CASE_DIR/decoy.sqlite"
    ln -s "$CASE_DIR/decoy.sqlite" "$sqlite_root/logs_2.sqlite"
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -eq 0 ] ||
        fail "Codex launch with a symlinked log database failed"
    assert_argv "$ARGV_FILE" alpha
    [ -L "$sqlite_root/logs_2.sqlite" ] ||
        fail "Codex removed a symlinked log database it must not count"
    if grep -F 'rotating oversized log database' "$STDERR_FILE" >/dev/null; then
        fail "Codex counted a symlinked log database toward the rotation cap"
    fi
    finish_case codex

    new_case codex log-rotation-removal-failure
    configure_state zero
    sqlite_root="$CODEX_LOCAL_ROOT/sqlite"
    mkdir -m 700 "$CODEX_LOCAL_ROOT"
    mkdir -m 700 "$sqlite_root"
    truncate -s $((1024 * 1024 * 1024 + 1)) "$sqlite_root/logs_2.sqlite"
    mkdir "$sqlite_root/logs_2.sqlite-shm"
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -ne 0 ] ||
        fail "Codex ignored a log database rotation failure"
    assert_upstream_not_invoked
    grep -F 'cannot rotate oversized log database' "$STDERR_FILE" >/dev/null ||
        fail "Codex log rotation failure had no diagnostic"
    finish_case codex

    new_case codex log-rotation-holder-probe-failure
    configure_state zero
    sqlite_root="$CODEX_LOCAL_ROOT/sqlite"
    mkdir -m 700 "$CODEX_LOCAL_ROOT"
    mkdir -m 700 "$sqlite_root"
    truncate -s $((1024 * 1024 * 1024 + 1)) "$sqlite_root/logs_2.sqlite"
    export AGENT_TEST_CODEX_LSOF_ERROR=1
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -eq 0 ] ||
        fail "Codex rejected an uninspectable oversized log database"
    assert_argv "$ARGV_FILE" alpha
    [ -e "$sqlite_root/logs_2.sqlite" ] ||
        fail "Codex rotated a log database after holder inspection failed"
    grep -F 'cannot inspect log database holders; skipping rotation' \
        "$STDERR_FILE" >/dev/null ||
        fail "Codex did not report the holder inspection failure"
    unset AGENT_TEST_CODEX_LSOF_ERROR
    finish_case codex

    new_case codex log-rotation-live-holder
    configure_state zero
    sqlite_root="$CODEX_LOCAL_ROOT/sqlite"
    ready="$CASE_DIR/holder-ready"
    release="$CASE_DIR/holder-release"
    mkdir -m 700 "$CODEX_LOCAL_ROOT"
    mkdir -m 700 "$sqlite_root"
    "$PYTHON_BIN" - "$sqlite_root/logs_2.sqlite" "$ready" "$release" <<'PY' &
import sqlite3
import sys
import time
from pathlib import Path

database_path, ready_path, release_path = map(Path, sys.argv[1:])
with sqlite3.connect(database_path) as database:
    database.execute("PRAGMA journal_mode=WAL")
    database.execute("CREATE TABLE IF NOT EXISTS events (value TEXT)")
    database.execute("INSERT INTO events VALUES ('held')")
    database.commit()
    ready_path.touch()
    while not release_path.exists():
        time.sleep(0.01)
PY
    holder_pid=$!
    background_pids=("$holder_pid")
    wait_for_path "$ready" "$holder_pid" "live Codex log database holder"
    truncate -s $((1024 * 1024 * 1024 + 1)) "$sqlite_root/logs_2.sqlite-wal"
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -eq 0 ] ||
        fail "Codex rejected an oversized log database with a live holder"
    assert_argv "$ARGV_FILE" alpha
    [ -e "$sqlite_root/logs_2.sqlite" ] &&
        [ -e "$sqlite_root/logs_2.sqlite-wal" ] &&
        [ -e "$sqlite_root/logs_2.sqlite-shm" ] ||
        fail "Codex rotated a log database with a live holder"
    grep -F 'oversized log database is in use; skipping rotation' \
        "$STDERR_FILE" >/dev/null ||
        fail "Codex did not report the live-holder rotation skip"
    touch "$release"
    if wait "$holder_pid"; then holder_status=0; else holder_status=$?; fi
    background_pids=()
    [ "$holder_status" -eq 0 ] || fail "live log holder exited $holder_status"
    finish_case codex
}

test_codex_sqlite_wal_snapshot() {
    local marker=codex-live-wal writer_pid writer_status
    local ready release
    local AGENT_TEST_CODEX_SQLITE_MARKER

    new_case codex sqlite-live-wal-snapshot
    configure_state complete
    ready="$CASE_DIR/wal-ready"
    release="$CASE_DIR/wal-release"
    start_codex_live_wal_seed "$ROOT/memories_1.sqlite" "$marker" "$ready" "$release"
    writer_pid=$SQLITE_HELPER_PID
    background_pids=("$writer_pid")
    wait_for_path "$ready" "$writer_pid" "live WAL source"
    AGENT_TEST_CODEX_SQLITE_MARKER=$marker
    invoke_agent codex 0 0 alpha
    touch "$release"
    if wait "$writer_pid"; then
        writer_status=0
    else
        writer_status=$?
    fi
    background_pids=()
    [ "$writer_status" -eq 0 ] || fail "live WAL fixture exited $writer_status"
    [ "$LAST_STATUS" -eq 0 ] || fail "Codex could not snapshot a live WAL database"
    assert_managed_argv codex alpha
    assert_codex_host_state "$marker"
    finish_case codex
}

test_codex_sqlite_backup_supervision() {
    local marker ready release prefix timeout_pid_file timeout_pid
    local holder_pid wrapper_pid watchdog_pid holder_status wrapper_status
    local watchdog_fired
    local AGENT_TEST_CODEX_FAST_BACKUP_DEADLINE
    local AGENT_TEST_CODEX_TIMEOUT_PID_FILE

    new_case codex sqlite-backup-term
    configure_state complete
    marker=codex-term-source
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" "$marker"
    ready="$CASE_DIR/exclusive-ready"
    release="$CASE_DIR/exclusive-release"
    prefix="$CASE_DIR/term-launch"
    timeout_pid_file="$CASE_DIR/timeout-pid"
    watchdog_fired="$CASE_DIR/watchdog-fired"
    start_codex_exclusive_holder "$ROOT/memories_1.sqlite" "$ready" "$release"
    holder_pid=$SQLITE_HELPER_PID
    background_pids=("$holder_pid")
    wait_for_path "$ready" "$holder_pid" "TERM fixture exclusive holder"
    AGENT_TEST_CODEX_TIMEOUT_PID_FILE=$timeout_pid_file
    start_codex_seed_launch "$prefix" "$marker"
    wrapper_pid=$CODEX_LAUNCH_PID
    background_pids+=("$wrapper_pid")
    wait_for_codex_seed_temporaries 1 "$wrapper_pid"
    wait_for_path "$timeout_pid_file" "$wrapper_pid" "backup supervisor PID"
    timeout_pid=$(<"$timeout_pid_file")
    start_process_watchdog "$wrapper_pid" "$watchdog_fired"
    watchdog_pid=$WATCHDOG_PID
    background_pids+=("$watchdog_pid")
    kill -TERM "$wrapper_pid"
    if wait "$wrapper_pid"; then wrapper_status=0; else wrapper_status=$?; fi
    kill -TERM "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    background_pids=("$holder_pid")

    [ "$wrapper_status" -eq 143 ] ||
        fail "TERM-interrupted SQLite backup exited $wrapper_status instead of 143"
    [ ! -e "$watchdog_fired" ] || fail "TERM did not stop the SQLite backup promptly"
    ! kill -0 "$timeout_pid" 2>/dev/null ||
        fail "TERM left the SQLite backup supervisor running"
    kill -0 "$holder_pid" 2>/dev/null ||
        fail "TERM fixture released the source's exclusive lock"
    [ ! -e "$release" ] || fail "TERM fixture released its source lock early"
    [ ! -e "$prefix.probe" ] && [ ! -e "$prefix.started" ] ||
        fail "TERM-interrupted backup reached policy or upstream"
    assert_codex_sqlite_seed_absent "$CODEX_LOCAL_ROOT/sqlite"

    touch "$release"
    if wait "$holder_pid"; then holder_status=0; else holder_status=$?; fi
    background_pids=()
    [ "$holder_status" -eq 0 ] || fail "TERM fixture holder exited $holder_status"
    finish_case codex

    new_case codex sqlite-backup-deadline
    configure_state complete
    marker=codex-deadline-source
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" "$marker"
    ready="$CASE_DIR/exclusive-ready"
    release="$CASE_DIR/exclusive-release"
    prefix="$CASE_DIR/deadline-launch"
    timeout_pid_file="$CASE_DIR/timeout-pid"
    watchdog_fired="$CASE_DIR/watchdog-fired"
    start_codex_exclusive_holder "$ROOT/memories_1.sqlite" "$ready" "$release"
    holder_pid=$SQLITE_HELPER_PID
    background_pids=("$holder_pid")
    wait_for_path "$ready" "$holder_pid" "deadline fixture exclusive holder"
    AGENT_TEST_CODEX_FAST_BACKUP_DEADLINE=1
    AGENT_TEST_CODEX_TIMEOUT_PID_FILE=$timeout_pid_file
    start_codex_seed_launch "$prefix" "$marker"
    wrapper_pid=$CODEX_LAUNCH_PID
    background_pids+=("$wrapper_pid")
    wait_for_codex_seed_temporaries 1 "$wrapper_pid"
    wait_for_path "$timeout_pid_file" "$wrapper_pid" "deadline supervisor PID"
    timeout_pid=$(<"$timeout_pid_file")
    start_process_watchdog "$wrapper_pid" "$watchdog_fired"
    watchdog_pid=$WATCHDOG_PID
    background_pids+=("$watchdog_pid")
    if wait "$wrapper_pid"; then wrapper_status=0; else wrapper_status=$?; fi
    kill -TERM "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    background_pids=("$holder_pid")

    [ "$wrapper_status" -eq 1 ] ||
        fail "deadline-bounded SQLite backup exited $wrapper_status instead of 1"
    [ ! -e "$watchdog_fired" ] || fail "SQLite backup deadline exceeded five seconds"
    ! kill -0 "$timeout_pid" 2>/dev/null ||
        fail "deadline left the SQLite backup supervisor running"
    kill -0 "$holder_pid" 2>/dev/null ||
        fail "deadline fixture released the source's exclusive lock"
    [ ! -e "$release" ] || fail "deadline fixture released its source lock early"
    [ ! -e "$prefix.probe" ] && [ ! -e "$prefix.started" ] ||
        fail "deadline-bounded backup reached policy or upstream"
    assert_codex_sqlite_seed_absent "$CODEX_LOCAL_ROOT/sqlite"
    grep -F 'codex: cannot create host-local memory backup' \
        "$prefix.stderr" >/dev/null || fail "deadline failure omitted its diagnostic"

    touch "$release"
    if wait "$holder_pid"; then holder_status=0; else holder_status=$?; fi
    background_pids=()
    [ "$holder_status" -eq 0 ] || fail "deadline fixture holder exited $holder_status"
    unset AGENT_TEST_CODEX_FAST_BACKUP_DEADLINE AGENT_TEST_CODEX_TIMEOUT_PID_FILE
    finish_case codex
}

test_codex_sqlite_validation_supervision() {
    local marker ready release prefix timeout_pid_file timeout_child_pid_file
    local timeout_pid timeout_child_pid holder_pid wrapper_pid watchdog_pid
    local holder_status wrapper_status watchdog_fired
    local AGENT_TEST_CODEX_FAST_BACKUP_DEADLINE
    local AGENT_TEST_CODEX_TIMEOUT_CHILD_PID_FILE AGENT_TEST_CODEX_TIMEOUT_PID_FILE

    new_case codex sqlite-validation-term
    configure_state complete
    marker=codex-existing-winner-term
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" codex-unused-source
    mkdir -m 700 "$CODEX_LOCAL_ROOT" "$CODEX_LOCAL_ROOT/sqlite"
    create_codex_sqlite_seed \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite" "$marker"
    ready="$CASE_DIR/exclusive-ready"
    release="$CASE_DIR/exclusive-release"
    prefix="$CASE_DIR/term-launch"
    timeout_pid_file="$CASE_DIR/timeout-pid"
    timeout_child_pid_file="$CASE_DIR/timeout-child-pid"
    watchdog_fired="$CASE_DIR/watchdog-fired"
    start_codex_exclusive_holder \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite" "$ready" "$release"
    holder_pid=$SQLITE_HELPER_PID
    background_pids=("$holder_pid")
    wait_for_path "$ready" "$holder_pid" "validation TERM exclusive holder"
    AGENT_TEST_CODEX_TIMEOUT_PID_FILE=$timeout_pid_file
    AGENT_TEST_CODEX_TIMEOUT_CHILD_PID_FILE=$timeout_child_pid_file
    start_codex_seed_launch "$prefix" "$marker"
    wrapper_pid=$CODEX_LAUNCH_PID
    background_pids+=("$wrapper_pid")
    wait_for_path "$timeout_pid_file" "$wrapper_pid" "validation supervisor PID"
    wait_for_path "$timeout_child_pid_file" "$wrapper_pid" "validation helper PID"
    timeout_pid=$(<"$timeout_pid_file")
    timeout_child_pid=$(<"$timeout_child_pid_file")
    start_process_watchdog "$wrapper_pid" "$watchdog_fired"
    watchdog_pid=$WATCHDOG_PID
    background_pids+=("$watchdog_pid")
    kill -TERM "$wrapper_pid"
    if wait "$wrapper_pid"; then wrapper_status=0; else wrapper_status=$?; fi
    kill -TERM "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    background_pids=("$holder_pid")

    [ "$wrapper_status" -eq 143 ] ||
        fail "TERM-interrupted SQLite validation exited $wrapper_status instead of 143"
    [ ! -e "$watchdog_fired" ] || fail "TERM did not stop SQLite validation promptly"
    ! kill -0 "$timeout_pid" 2>/dev/null ||
        fail "TERM left the SQLite validation supervisor running"
    ! kill -0 "$timeout_child_pid" 2>/dev/null ||
        fail "TERM left the SQLite validation helper running"
    kill -0 "$holder_pid" 2>/dev/null ||
        fail "validation TERM fixture released the destination's exclusive lock"
    [ ! -e "$release" ] || fail "validation TERM fixture released its lock early"
    [ ! -e "$prefix.probe" ] && [ ! -e "$prefix.started" ] ||
        fail "TERM-interrupted validation reached policy or upstream"
    assert_no_codex_seed_temporaries "$CODEX_LOCAL_ROOT/sqlite"

    touch "$release"
    if wait "$holder_pid"; then holder_status=0; else holder_status=$?; fi
    background_pids=()
    [ "$holder_status" -eq 0 ] ||
        fail "validation TERM fixture holder exited $holder_status"
    assert_codex_sqlite_marker \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite" "$marker"
    assert_codex_sqlite_published_form \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite"
    finish_case codex

    new_case codex sqlite-validation-deadline
    configure_state complete
    marker=codex-existing-winner-deadline
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" codex-unused-source
    mkdir -m 700 "$CODEX_LOCAL_ROOT" "$CODEX_LOCAL_ROOT/sqlite"
    create_codex_sqlite_seed \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite" "$marker"
    ready="$CASE_DIR/exclusive-ready"
    release="$CASE_DIR/exclusive-release"
    prefix="$CASE_DIR/deadline-launch"
    timeout_pid_file="$CASE_DIR/timeout-pid"
    timeout_child_pid_file="$CASE_DIR/timeout-child-pid"
    watchdog_fired="$CASE_DIR/watchdog-fired"
    start_codex_exclusive_holder \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite" "$ready" "$release"
    holder_pid=$SQLITE_HELPER_PID
    background_pids=("$holder_pid")
    wait_for_path "$ready" "$holder_pid" "validation deadline exclusive holder"
    AGENT_TEST_CODEX_FAST_BACKUP_DEADLINE=1
    AGENT_TEST_CODEX_TIMEOUT_PID_FILE=$timeout_pid_file
    AGENT_TEST_CODEX_TIMEOUT_CHILD_PID_FILE=$timeout_child_pid_file
    start_codex_seed_launch "$prefix" "$marker"
    wrapper_pid=$CODEX_LAUNCH_PID
    background_pids+=("$wrapper_pid")
    wait_for_path "$timeout_pid_file" "$wrapper_pid" "validation deadline supervisor PID"
    wait_for_path "$timeout_child_pid_file" "$wrapper_pid" "validation deadline helper PID"
    timeout_pid=$(<"$timeout_pid_file")
    timeout_child_pid=$(<"$timeout_child_pid_file")
    start_process_watchdog "$wrapper_pid" "$watchdog_fired"
    watchdog_pid=$WATCHDOG_PID
    background_pids+=("$watchdog_pid")
    if wait "$wrapper_pid"; then wrapper_status=0; else wrapper_status=$?; fi
    kill -TERM "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    background_pids=("$holder_pid")

    [ "$wrapper_status" -eq 1 ] ||
        fail "deadline-bounded SQLite validation exited $wrapper_status instead of 1"
    [ ! -e "$watchdog_fired" ] || fail "SQLite validation deadline exceeded five seconds"
    ! kill -0 "$timeout_pid" 2>/dev/null ||
        fail "deadline left the SQLite validation supervisor running"
    ! kill -0 "$timeout_child_pid" 2>/dev/null ||
        fail "deadline left the SQLite validation helper running"
    kill -0 "$holder_pid" 2>/dev/null ||
        fail "validation deadline fixture released the destination's exclusive lock"
    [ ! -e "$release" ] || fail "validation deadline fixture released its lock early"
    [ ! -e "$prefix.probe" ] && [ ! -e "$prefix.started" ] ||
        fail "deadline-bounded validation reached policy or upstream"
    assert_no_codex_seed_temporaries "$CODEX_LOCAL_ROOT/sqlite"
    grep -F 'codex: refusing invalid host-local memory database' \
        "$prefix.stderr" >/dev/null ||
        fail "validation deadline failure omitted its diagnostic"

    touch "$release"
    if wait "$holder_pid"; then holder_status=0; else holder_status=$?; fi
    background_pids=()
    [ "$holder_status" -eq 0 ] ||
        fail "validation deadline fixture holder exited $holder_status"
    assert_codex_sqlite_marker \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite" "$marker"
    assert_codex_sqlite_published_form \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite"
    unset AGENT_TEST_CODEX_FAST_BACKUP_DEADLINE
    unset AGENT_TEST_CODEX_TIMEOUT_CHILD_PID_FILE AGENT_TEST_CODEX_TIMEOUT_PID_FILE
    finish_case codex
}

test_codex_sqlite_publication() {
    local marker source_marker corrupt_before
    local AGENT_TEST_CODEX_PROBE_FILE AGENT_TEST_CODEX_SQLITE_MARKER
    local AGENT_TEST_UPSTREAM_STARTED

    new_case codex sqlite-existing-winner
    configure_state complete
    mkdir -m 700 "$CODEX_LOCAL_ROOT" "$CODEX_LOCAL_ROOT/sqlite"
    source_marker=codex-source-loser
    marker=codex-existing-winner
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" "$source_marker"
    create_codex_sqlite_seed \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite" "$marker"
    AGENT_TEST_CODEX_SQLITE_MARKER=$marker
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -eq 0 ] || fail "Codex rejected a valid published winner"
    assert_codex_sqlite_marker "$ROOT/memories_1.sqlite" "$source_marker"
    assert_codex_host_state "$marker"
    finish_case codex

    new_case codex sqlite-existing-corrupt
    configure_state complete
    mkdir -m 700 "$CODEX_LOCAL_ROOT" "$CODEX_LOCAL_ROOT/sqlite"
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" codex-valid-source
    create_codex_sqlite_interior_corruption \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite"
    corrupt_before=$(sha256sum "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite")
    AGENT_TEST_CODEX_PROBE_FILE="$CASE_DIR/policy-probe"
    AGENT_TEST_UPSTREAM_STARTED="$CASE_DIR/upstream-started"
    unset AGENT_TEST_CODEX_SQLITE_MARKER
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -ne 0 ] || fail "Codex accepted a corrupt published destination"
    assert_upstream_not_invoked
    [ ! -e "$AGENT_TEST_CODEX_PROBE_FILE" ] ||
        fail "Codex probed policy before rejecting a corrupt destination"
    [ ! -e "$AGENT_TEST_UPSTREAM_STARTED" ] ||
        fail "Codex launched upstream with a corrupt destination"
    [ "$(sha256sum "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite")" = "$corrupt_before" ] ||
        fail "Codex overwrote a corrupt preexisting destination"
    assert_no_codex_seed_temporaries "$CODEX_LOCAL_ROOT/sqlite"
    grep -F 'codex: refusing invalid host-local memory database' \
        "$STDERR_FILE" >/dev/null ||
        fail "Codex omitted the corrupt destination diagnostic"
    finish_case codex

    new_case codex sqlite-stale-crash-lock
    configure_state complete
    mkdir -m 700 "$CODEX_LOCAL_ROOT" "$CODEX_LOCAL_ROOT/sqlite"
    mkdir "$CODEX_LOCAL_ROOT/sqlite/.memories-seed-lock"
    marker=codex-after-stale-lock
    create_codex_sqlite_seed "$ROOT/memories_1.sqlite" "$marker"
    AGENT_TEST_CODEX_SQLITE_MARKER=$marker
    unset AGENT_TEST_CODEX_PROBE_FILE AGENT_TEST_UPSTREAM_STARTED
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -eq 0 ] || fail "stale crash residue blocked a Codex launch"
    assert_managed_argv codex alpha
    assert_codex_sqlite_marker \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite" "$marker"
    assert_codex_sqlite_published_form \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite"
    [ -d "$CODEX_LOCAL_ROOT/sqlite/.memories-seed-lock" ] ||
        fail "Codex unexpectedly relied on or removed unrelated crash residue"
    assert_no_codex_seed_temporaries "$CODEX_LOCAL_ROOT/sqlite"
    finish_case codex
}

test_codex_sqlite_concurrent_publication() {
    local first_marker=codex-first-snapshot
    local second_marker=codex-second-snapshot
    local first_root second_root first_ready second_ready first_release second_release
    local first_prefix second_prefix first_holder_pid second_holder_pid
    local first_pid second_pid first_holder_status second_holder_status
    local first_status second_status

    new_case codex sqlite-concurrent-publication
    first_root="$CASE_DIR/first Codex home"
    second_root="$CASE_DIR/second Codex home"
    mkdir -p "$first_root" "$second_root"
    write_managed_file "$first_root/nix-managed.config.toml"
    write_managed_file "$second_root/nix-managed.config.toml"
    create_codex_sqlite_seed "$first_root/memories_1.sqlite" "$first_marker"
    create_codex_sqlite_seed "$second_root/memories_1.sqlite" "$second_marker"
    first_ready="$CASE_DIR/first-exclusive-ready"
    second_ready="$CASE_DIR/second-exclusive-ready"
    first_release="$CASE_DIR/first-exclusive-release"
    second_release="$CASE_DIR/second-exclusive-release"
    first_prefix="$CASE_DIR/first-launch"
    second_prefix="$CASE_DIR/second-launch"

    start_codex_exclusive_holder \
        "$first_root/memories_1.sqlite" "$first_ready" "$first_release"
    first_holder_pid=$SQLITE_HELPER_PID
    background_pids=("$first_holder_pid")
    start_codex_exclusive_holder \
        "$second_root/memories_1.sqlite" "$second_ready" "$second_release"
    second_holder_pid=$SQLITE_HELPER_PID
    background_pids+=("$second_holder_pid")
    wait_for_path "$first_ready" "$first_holder_pid" "first exclusive SQLite holder"
    wait_for_path "$second_ready" "$second_holder_pid" "second exclusive SQLite holder"

    start_codex_seed_launch "$first_prefix" "$first_marker" "$first_root"
    first_pid=$CODEX_LAUNCH_PID
    background_pids+=("$first_pid")
    wait_for_codex_seed_temporaries 1 "$first_pid"

    start_codex_seed_launch "$second_prefix" "$first_marker" "$second_root"
    second_pid=$CODEX_LAUNCH_PID
    background_pids+=("$second_pid")
    wait_for_codex_seed_temporaries 2 "$second_pid"

    [ ! -e "$first_prefix.probe" ] && [ ! -e "$second_prefix.probe" ] ||
        fail "a concurrent Codex launch probed policy before backup completion"
    [ ! -e "$first_prefix.started" ] && [ ! -e "$second_prefix.started" ] ||
        fail "a concurrent Codex launch reached upstream before publication"

    touch "$first_release"
    if wait "$first_holder_pid"; then first_holder_status=0; else first_holder_status=$?; fi
    if wait "$first_pid"; then first_status=0; else first_status=$?; fi
    background_pids=("$second_holder_pid" "$second_pid")

    [ "$first_holder_status" -eq 0 ] ||
        fail "first exclusive holder exited $first_holder_status"
    [ "$first_status" -eq 0 ] || fail "first concurrent launch exited $first_status"
    assert_codex_sqlite_marker \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite" "$first_marker"
    [ ! -e "$second_prefix.probe" ] && [ ! -e "$second_prefix.started" ] ||
        fail "second launch advanced before its distinct source snapshot completed"
    kill -0 "$second_holder_pid" 2>/dev/null ||
        fail "second source lock was released before first publication"

    touch "$second_release"
    if wait "$second_holder_pid"; then second_holder_status=0; else second_holder_status=$?; fi
    if wait "$second_pid"; then second_status=0; else second_status=$?; fi
    background_pids=()

    [ "$second_holder_status" -eq 0 ] ||
        fail "second exclusive holder exited $second_holder_status"
    [ "$second_status" -eq 0 ] || fail "second concurrent launch exited $second_status"
    [ -e "$first_prefix.probe" ] && [ -e "$second_prefix.probe" ] ||
        fail "concurrent launches did not resume policy routing after publication"
    [ -e "$first_prefix.started" ] && [ -e "$second_prefix.started" ] ||
        fail "concurrent launches did not both observe the published database"
    assert_argv "$first_prefix.argv" --profile nix-runtime alpha
    assert_argv "$second_prefix.argv" --profile nix-runtime alpha
    assert_codex_sqlite_marker \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite" "$first_marker"
    assert_codex_sqlite_marker "$second_root/memories_1.sqlite" "$second_marker"
    assert_codex_sqlite_published_form \
        "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite"
    [ "$(stat -c %a "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite")" = 600 ] ||
        fail "concurrently published SQLite database is not mode 0600"
    [ ! -e "$CODEX_LOCAL_ROOT/sqlite/.memories-seed-lock" ] ||
        fail "concurrent publication left a persistent lock"
    assert_no_codex_seed_temporaries "$CODEX_LOCAL_ROOT/sqlite"
    finish_case codex
}

assert_codex_developer_marker() {
    local document=$1
    local marker=$2
    local expected=$3

    "$PYTHON_BIN" - "$document" "$marker" "$expected" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
marker = sys.argv[2]
expected = sys.argv[3]
texts = [
    content.get("text", "")
    for message in document
    if isinstance(message, dict) and message.get("role") == "developer"
    for content in message.get("content", [])
    if isinstance(content, dict) and content.get("type") == "input_text"
]
found = any(marker in text for text in texts)
raise SystemExit(0 if found == (expected == "present") else 1)
PY
}

test_real_claude_mcp_list_contract() {
    local claude_home="$work_root/real Claude MCP list"
    local claude_root="$claude_home/.claude"
    local network_guard_loaded="$claude_home/network-guard-loaded"
    local network_hit="$claude_home/network-attempted"
    local sentinel=nix-session-sentinel

    mkdir -p "$claude_root"
    printf '%s\n' '{}' >"$claude_root/nix-managed-settings.json"
    printf '%s\n' \
        "{\"mcpServers\":{\"$sentinel\":{\"command\":\"/usr/bin/false\",\"args\":[]}}}" \
        >"$claude_root/nix-managed-mcp.json"

    if env HOME="$claude_home" CLAUDE_CONFIG_DIR="$claude_root" \
        TASK3_NETWORK_GUARD_LOADED_FILE="$network_guard_loaded" \
        TASK3_NETWORK_ATTEMPT_FILE="$network_hit" \
        "$NETWORK_GUARD_VARIABLE=$NETWORK_GUARD_LIBRARY" \
        "$REAL_CLAUDE_BIN" mcp list \
        >"$claude_home/stdout" 2>"$claude_home/stderr"; then
        :
    else
        fail "pinned Claude failed to parse managed mcp list arguments"
    fi
    grep -F 'No MCP servers configured.' "$claude_home/stdout" >/dev/null ||
        fail "pinned Claude persistent MCP listing changed unexpectedly"
    ! grep -F -- "$sentinel" \
        "$claude_home/stdout" "$claude_home/stderr" >/dev/null ||
        fail "pinned Claude listed a session-only managed MCP as persistent"
    ! grep -F 'MCP config file not found:' "$claude_home/stderr" >/dev/null ||
        fail "pinned Claude parsed mcp/list as managed config filenames"
    grep -E '^loaded:[0-9]+:' "$network_guard_loaded" >/dev/null ||
        fail "pinned Claude did not load the process-level network guard"
    [ ! -e "$network_hit" ] ||
        fail "pinned Claude attempted network access during mcp list"
}

assert_real_probe_policy() {
    local label=$1
    local expected=$2
    shift 2
    local probe_dir="$work_root/real probe matrix/$label"
    local probe_home="$probe_dir/home"

    mkdir -p "$probe_home"
    if ! env -u AI_NIX_BYPASS_MANAGED_CONFIG \
        HOME="$probe_home" CODEX_HOME="$probe_home/codex" \
        CODEX_SQLITE_HOME="$probe_home/sqlite" \
        CODEX_INTERNAL_WRAPPER_POLICY_PROBE=v1 \
        timeout --signal=TERM --kill-after=1 30 \
        "$REAL_PROBED_CODEX_BIN" "$@" \
        >"$probe_dir/actual" 2>"$probe_dir/stderr"; then
        fail "real Codex policy probe failed: $label"
    fi
    printf '%s\n' "$expected" >"$probe_dir/expected"
    cmp -s "$probe_dir/expected" "$probe_dir/actual" || {
        od -An -tx1 "$probe_dir/actual" >&2 || true
        fail "real Codex policy probe differs: $label"
    }
    [ ! -s "$probe_dir/stderr" ] ||
        fail "real Codex policy probe wrote diagnostics: $label"
    test -z "$(find "$probe_home" -mindepth 1 -print -quit)" ||
        fail "real Codex policy probe touched state: $label"
}

test_real_codex_probe_matrix() {
    assert_real_probe_policy manage-root manage
    assert_real_probe_policy manage-prompt manage prompt
    assert_real_probe_policy manage-exec manage exec prompt
    assert_real_probe_policy manage-exec-short manage e prompt
    assert_real_probe_policy manage-review manage review --uncommitted
    assert_real_probe_policy manage-resume manage resume --last
    assert_real_probe_policy manage-queue manage \
        queue --thread thread --message message
    assert_real_probe_policy manage-archive manage archive thread
    assert_real_probe_policy manage-delete manage delete thread
    assert_real_probe_policy manage-unarchive manage unarchive thread
    assert_real_probe_policy manage-fork manage fork --last
    assert_real_probe_policy manage-mcp manage mcp list
    assert_real_probe_policy manage-sandbox manage sandbox -- echo
    assert_real_probe_policy manage-debug-prompt manage debug prompt-input

    assert_real_probe_policy delegate-completion delegate completion bash
    assert_real_probe_policy delegate-features delegate features list
    assert_real_probe_policy delegate-debug-models delegate debug models --bundled
    assert_real_probe_policy delegate-agents delegate agents
    assert_real_probe_policy delegate-agents-profile delegate \
        --profile work agents
    assert_real_probe_policy delegate-agents-ignore delegate \
        agents --ignore-user-config
    assert_real_probe_policy delegate-root-help delegate --help
    assert_real_probe_policy delegate-root-version delegate --version
    assert_real_probe_policy delegate-exec-help delegate exec --help
    assert_real_probe_policy delegate-exec-version delegate exec --version
    assert_real_probe_policy delegate-unknown delegate --unknown-option
    assert_real_probe_policy delegate-profile-missing delegate --profile
    assert_real_probe_policy delegate-profile-invalid delegate --profile nested/work
    assert_real_probe_policy delegate-profile-inapplicable delegate \
        --profile work features list
    assert_real_probe_policy delegate-ignore-root delegate --ignore-user-config
    assert_real_probe_policy delegate-ignore-inapplicable delegate \
        mcp list --ignore-user-config
    assert_real_probe_policy delegate-mcp-add-incomplete delegate mcp add
    assert_real_probe_policy delegate-queue-incomplete delegate queue

    assert_real_probe_policy conflict-root-profile conflict-profile \
        --profile work
    assert_real_probe_policy conflict-short-profile conflict-profile \
        -pwork exec prompt
    assert_real_probe_policy conflict-exec-profile conflict-profile \
        exec --profile=work prompt
    assert_real_probe_policy conflict-resume-profile conflict-profile \
        resume --profile work --last
    assert_real_probe_policy conflict-queue-profile conflict-profile \
        queue --thread thread --message message --profile work
    assert_real_probe_policy conflict-sandbox-profile conflict-profile \
        sandbox --profile work -- echo

    assert_real_probe_policy conflict-ignore-exec conflict-ignore-user-config \
        exec --ignore-user-config prompt
    assert_real_probe_policy conflict-ignore-resume conflict-ignore-user-config \
        exec resume --ignore-user-config --last
    assert_real_probe_policy conflict-ignore-wins conflict-ignore-user-config \
        exec --profile work --ignore-user-config prompt
    assert_real_probe_policy manage-ignore-payload manage \
        exec -- --ignore-user-config

    assert_real_probe_policy manage-root-profile-payload manage -- --profile
    assert_real_probe_policy manage-exec-profile-payload manage exec -- --profile
    assert_real_probe_policy manage-exec-help-payload manage exec -- --help
    assert_real_probe_policy manage-mcp-payload manage \
        mcp add server -- command --profile work --help
    assert_real_probe_policy manage-sandbox-payload manage \
        sandbox -- command --profile work --help
    assert_real_probe_policy manage-debug-profile-payload manage \
        debug prompt-input -- --profile
    assert_real_probe_policy delegate-apply-payload delegate apply -- -p
}

run_real_wrapped_codex() {
    local network_guard_loaded=$1
    local network_hit=$2
    local binary=${REAL_WRAPPED_CODEX_TEST_BIN:-$REAL_WRAPPED_CODEX_BIN}
    local poison_sqlite="$CASE_DIR/poison-sqlite"
    local wrapper_pid
    shift 2

    printf '%s\n' poison >"$poison_sqlite"
    CODEX_SQLITE_HOME="$poison_sqlite" \
        env -u AI_NIX_BYPASS_MANAGED_CONFIG -u CODEX_SQLITE_HOME \
        -u TASK3_SHELL_POLICY_SENTINEL \
        HOME="$HOME_DIR" CODEX_HOME="$ROOT" \
        AGENT_TEST_ARGV="$ARGV_FILE" AGENT_TEST_ENV="$ENV_FILE" AGENT_TEST_EXIT=0 \
        AGENT_TEST_UID="$AGENT_TEST_UID" \
        TASK3_NETWORK_GUARD_LOADED_FILE="$network_guard_loaded" \
        TASK3_NETWORK_ATTEMPT_FILE="$network_hit" \
        "$NETWORK_GUARD_VARIABLE=$NETWORK_GUARD_LIBRARY" \
        timeout --signal=TERM --kill-after=1 30 \
        "$binary" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE" &
    wrapper_pid=$!
    if wait "$wrapper_pid"; then
        LAST_STATUS=0
    else
        LAST_STATUS=$?
    fi
    [ -d "$CODEX_LOCAL_ROOT/sqlite" ] ||
        fail "real wrapped Codex did not use the synthetic SQLite root"
    printf '%s\n' poison | cmp -s - "$poison_sqlite" ||
        fail "real wrapped Codex touched the poison SQLite path"
    if [ "$LAST_STATUS" -eq 0 ] && [ -z "${REAL_WRAPPED_CODEX_TEST_BIN:-}" ]; then
        assert_network_guard_loaded "$network_guard_loaded" codex
    fi
}

assert_real_codex_status_parity() {
    local label=$1
    local expected_route=$2
    shift 2
    local raw_home raw_status wrapped_status
    local raw_network_guard_loaded raw_network_hit
    local wrapped_network_guard_loaded wrapped_network_hit

    new_case codex "real-status-$label"
    printf '%s\n' 'developer_instructions = "managed"' >"$FIRST"
    raw_home="$CASE_DIR/raw-home"
    raw_network_guard_loaded="$CASE_DIR/raw-network-guard-loaded"
    raw_network_hit="$CASE_DIR/raw-network-attempted"
    wrapped_network_guard_loaded="$CASE_DIR/wrapped-network-guard-loaded"
    wrapped_network_hit="$CASE_DIR/wrapped-network-attempted"
    mkdir -p "$raw_home/sqlite"

    if env -u AI_NIX_BYPASS_MANAGED_CONFIG -u TASK3_SHELL_POLICY_SENTINEL \
        HOME="$raw_home" CODEX_HOME="$raw_home" \
        CODEX_SQLITE_HOME="$raw_home/sqlite" \
        TASK3_NETWORK_GUARD_LOADED_FILE="$raw_network_guard_loaded" \
        TASK3_NETWORK_ATTEMPT_FILE="$raw_network_hit" \
        "$NETWORK_GUARD_VARIABLE=$NETWORK_GUARD_LIBRARY" \
        timeout --signal=TERM --kill-after=1 30 \
        "$REAL_CODEX_BIN" "$@" >"$CASE_DIR/raw.stdout" 2>"$CASE_DIR/raw.stderr"; then
        raw_status=0
    else
        raw_status=$?
    fi

    run_real_wrapped_codex \
        "$wrapped_network_guard_loaded" "$wrapped_network_hit" "$@"
    wrapped_status=$LAST_STATUS
    [ "$wrapped_status" -eq "$raw_status" ] ||
        fail "wrapped/raw Codex status differs for $label: $wrapped_status/$raw_status"
    case "$expected_route" in
    delegate)
        cmp "$CASE_DIR/raw.stdout" "$STDOUT_FILE" || {
            diff -u "$CASE_DIR/raw.stdout" "$STDOUT_FILE" >&2 || true
            fail "delegated Codex output differs for $label"
        }
        sed '/^WARNING: proceeding, even though we could not create PATH aliases:/d' \
            "$CASE_DIR/raw.stderr" >"$CASE_DIR/raw-normalized.stderr"
        sed '/^WARNING: proceeding, even though we could not create PATH aliases:/d' \
            "$STDERR_FILE" >"$CASE_DIR/wrapped-normalized.stderr"
        cmp "$CASE_DIR/raw-normalized.stderr" "$CASE_DIR/wrapped-normalized.stderr" || {
            diff -u "$CASE_DIR/raw-normalized.stderr" \
                "$CASE_DIR/wrapped-normalized.stderr" >&2 || true
            fail "delegated Codex diagnostic differs for $label"
        }
        assert_codex_runtime_profile_absent
        ;;
    manage) assert_codex_runtime_profile ;;
    *) fail "unknown real Codex route expectation: $expected_route" ;;
    esac
    assert_network_guard_loaded "$raw_network_guard_loaded" codex
    assert_network_guard_loaded "$wrapped_network_guard_loaded" codex
    [ ! -e "$raw_network_hit" ] && [ ! -e "$wrapped_network_hit" ] ||
        fail "Codex parity probe attempted network access"
    [ ! -e "$ROOT/sessions" ] && [ ! -e "$raw_home/sessions" ] ||
        fail "Codex parity probe created session state"
    finish_case codex
}

test_real_wrapped_codex_status_parity() {
    assert_real_codex_status_parity root-help delegate --help
    assert_real_codex_status_parity root-version delegate --version
    assert_real_codex_status_parity exec-help delegate exec --help
    assert_real_codex_status_parity exec-version delegate exec --version
    assert_real_codex_status_parity root-missing-config delegate --config
    assert_real_codex_status_parity exec-missing-model delegate exec --model
    assert_real_codex_status_parity exec-invalid-color delegate \
        exec --color purple --help
    assert_real_codex_status_parity review-selector-conflict delegate \
        review --uncommitted --base main
    assert_real_codex_status_parity resume-positional-overflow delegate \
        resume --last session prompt
    assert_real_codex_status_parity resume-missing-remote delegate \
        resume --remote -p caller
    assert_real_codex_status_parity mcp-missing-name delegate mcp get
    assert_real_codex_status_parity sandbox-state-conflict delegate \
        sandbox --permission-profile standard --sandbox-state-json '{}' /usr/bin/true
    assert_real_codex_status_parity debug-empty-image delegate \
        debug prompt-input --image=
    assert_real_codex_status_parity agents-profile delegate \
        --profile work agents
    assert_real_codex_status_parity agents-ignore delegate \
        agents --ignore-user-config
}

test_real_wrapped_codex_routing() {
    local marker=NIX_WRAPPED_PROFILE_SENTINEL
    local network_guard_loaded network_hit

    new_case codex wrapped-helper-sqlite-isolation
    printf '%s\n' 'developer_instructions = "managed"' >"$FIRST"
    network_guard_loaded="$CASE_DIR/network-guard-loaded"
    network_hit="$CASE_DIR/network-attempted"
    REAL_WRAPPED_CODEX_TEST_BIN=$CODEX_BIN
    run_real_wrapped_codex "$network_guard_loaded" "$network_hit" alpha
    unset REAL_WRAPPED_CODEX_TEST_BIN
    [ "$LAST_STATUS" -eq 0 ] || fail "isolated fake Codex wrapper failed"
    assert_managed_argv codex alpha
    assert_env "CODEX_SQLITE_HOME=$CODEX_LOCAL_ROOT/sqlite"
    assert_codex_runtime_profile
    finish_case codex

    new_case codex real-wrapped-debug-prompt-input
    printf 'developer_instructions = "%s"\n' "$marker" >"$FIRST"
    network_guard_loaded="$CASE_DIR/network-guard-loaded"
    network_hit="$CASE_DIR/network-attempted"
    run_real_wrapped_codex "$network_guard_loaded" "$network_hit" \
        debug prompt-input hello
    [ "$LAST_STATUS" -eq 0 ] || fail "wrapped Codex rejected debug prompt-input"
    assert_codex_developer_marker "$STDOUT_FILE" "$marker" present ||
        fail "wrapped Codex did not load the managed profile"
    assert_codex_runtime_profile
    [ ! -e "$network_hit" ] || fail "wrapped debug probe attempted network access"
    [ ! -e "$ROOT/sessions" ] || fail "wrapped debug probe created session state"
    finish_case codex

    new_case codex real-wrapped-mcp
    printf '%s\n' 'developer_instructions = "managed"' >"$FIRST"
    network_guard_loaded="$CASE_DIR/network-guard-loaded"
    network_hit="$CASE_DIR/network-attempted"
    run_real_wrapped_codex "$network_guard_loaded" "$network_hit" mcp list
    [ "$LAST_STATUS" -eq 0 ] || fail "wrapped Codex did not manage mcp"
    assert_codex_runtime_profile
    [ ! -e "$network_hit" ] || fail "wrapped mcp probe attempted network access"
    [ ! -e "$ROOT/sessions" ] || fail "wrapped mcp probe created session state"
    finish_case codex

    new_case codex real-wrapped-mcp-payload-help
    printf '%s\n' 'developer_instructions = "managed"' >"$FIRST"
    network_guard_loaded="$CASE_DIR/network-guard-loaded"
    network_hit="$CASE_DIR/network-attempted"
    run_real_wrapped_codex "$network_guard_loaded" "$network_hit" \
        mcp add payload-help /bin/echo --help
    [ "$LAST_STATUS" -eq 0 ] || fail "wrapped Codex rejected MCP help payload"
    assert_codex_runtime_profile
    [ ! -e "$network_hit" ] || fail "wrapped MCP payload probe attempted network access"
    [ ! -e "$ROOT/sessions" ] || fail "wrapped MCP payload probe created session state"
    finish_case codex

    new_case codex real-wrapped-mcp-separator-before-name
    printf '%s\n' 'developer_instructions = "managed"' >"$FIRST"
    network_guard_loaded="$CASE_DIR/network-guard-loaded"
    network_hit="$CASE_DIR/network-attempted"
    run_real_wrapped_codex "$network_guard_loaded" "$network_hit" \
        mcp add -- separator-name /bin/echo
    [ "$LAST_STATUS" -eq 0 ] || fail "wrapped Codex rejected MCP separator before name"
    assert_codex_runtime_profile
    [ ! -e "$network_hit" ] || fail "wrapped MCP separator probe attempted network access"
    [ ! -e "$ROOT/sessions" ] || fail "wrapped MCP separator probe created session state"
    finish_case codex

    new_case codex real-wrapped-mcp-lone-dash-name
    printf '%s\n' 'developer_instructions = "managed"' >"$FIRST"
    network_guard_loaded="$CASE_DIR/network-guard-loaded"
    network_hit="$CASE_DIR/network-attempted"
    run_real_wrapped_codex "$network_guard_loaded" "$network_hit" \
        mcp add - /bin/echo
    [ "$LAST_STATUS" -eq 0 ] || fail "wrapped Codex rejected MCP lone-dash name"
    assert_codex_runtime_profile
    [ ! -e "$network_hit" ] || fail "wrapped MCP dash probe attempted network access"
    [ ! -e "$ROOT/sessions" ] || fail "wrapped MCP dash probe created session state"
    finish_case codex

    new_case codex real-wrapped-mcp-lone-dash-conflict
    printf '%s\n' 'developer_instructions = "managed"' >"$FIRST"
    network_guard_loaded="$CASE_DIR/network-guard-loaded"
    network_hit="$CASE_DIR/network-attempted"
    run_real_wrapped_codex "$network_guard_loaded" "$network_hit" \
        --profile caller mcp get -
    [ "$LAST_STATUS" -eq 2 ] || fail "wrapped Codex accepted MCP caller profile"
    assert_codex_runtime_profile_absent
    grep -F 'managed configuration conflicts with a caller profile' \
        "$STDERR_FILE" >/dev/null || fail "wrapped MCP conflict diagnostic changed"
    [ ! -e "$network_hit" ] || fail "wrapped MCP conflict probe attempted network access"
    [ ! -e "$ROOT/sessions" ] || fail "wrapped MCP conflict probe created session state"
    finish_case codex

    new_case codex real-wrapped-nested-help
    printf '%s\n' 'developer_instructions = "managed"' >"$FIRST"
    network_guard_loaded="$CASE_DIR/network-guard-loaded"
    network_hit="$CASE_DIR/network-attempted"
    run_real_wrapped_codex "$network_guard_loaded" "$network_hit" \
        --profile caller exec resume --help
    [ "$LAST_STATUS" -eq 0 ] || fail "wrapped Codex intercepted nested exec help"
    assert_codex_runtime_profile_absent
    [ ! -e "$network_hit" ] || fail "wrapped nested-help probe attempted network access"
    [ ! -e "$ROOT/sessions" ] || fail "wrapped nested-help probe created session state"
    finish_case codex

    new_case codex real-wrapped-help-subcommands
    printf '%s\n' 'developer_instructions = "managed"' >"$FIRST"
    network_guard_loaded="$CASE_DIR/network-guard-loaded"
    network_hit="$CASE_DIR/network-attempted"
    run_real_wrapped_codex "$network_guard_loaded" "$network_hit" \
        --profile caller exec help
    [ "$LAST_STATUS" -eq 0 ] || fail "wrapped Codex intercepted exec help subcommand"
    assert_codex_runtime_profile_absent
    run_real_wrapped_codex "$network_guard_loaded" "$network_hit" \
        --profile caller mcp help
    [ "$LAST_STATUS" -eq 0 ] || fail "wrapped Codex intercepted MCP help subcommand"
    assert_codex_runtime_profile_absent
    run_real_wrapped_codex "$network_guard_loaded" "$network_hit" \
        --profile caller exec foo help
    [ "$LAST_STATUS" -eq 0 ] || fail "wrapped Codex intercepted exec prompt-before-help"
    assert_codex_runtime_profile_absent
    run_real_wrapped_codex "$network_guard_loaded" "$network_hit" \
        --profile caller exec foo resume --help
    [ "$LAST_STATUS" -eq 0 ] || fail "wrapped Codex intercepted nested prompt-before-help"
    assert_codex_runtime_profile_absent
    [ ! -e "$network_hit" ] || fail "wrapped help probe attempted network access"
    [ ! -e "$ROOT/sessions" ] || fail "wrapped help probe created session state"
    finish_case codex

    new_case codex real-wrapped-features
    printf '%s\n' 'developer_instructions = "managed"' >"$FIRST"
    network_guard_loaded="$CASE_DIR/network-guard-loaded"
    network_hit="$CASE_DIR/network-attempted"
    run_real_wrapped_codex "$network_guard_loaded" "$network_hit" features list
    [ "$LAST_STATUS" -eq 0 ] || fail "wrapped Codex did not delegate features"
    assert_codex_runtime_profile_absent
    run_real_wrapped_codex "$network_guard_loaded" "$network_hit" \
        ordinary-prompt features list
    [ "$LAST_STATUS" -eq 0 ] || fail "wrapped Codex missed command after prompt"
    assert_codex_runtime_profile_absent
    run_real_wrapped_codex "$network_guard_loaded" "$network_hit" - features list
    [ "$LAST_STATUS" -eq 0 ] || fail "wrapped Codex missed command after dash prompt"
    assert_codex_runtime_profile_absent
    [ ! -e "$network_hit" ] || fail "wrapped features probe attempted network access"
    [ ! -e "$ROOT/sessions" ] || fail "wrapped features probe created session state"
    finish_case codex
}

test_real_codex_profile_contract() {
    local codex_home="$work_root/real Codex profile"
    local marker=NIX_MANAGED_PROFILE_SENTINEL
    local strict_marker=task_3_nix_managed_strict_marker
    local valid_network_guard_loaded="$codex_home/valid-network-guard-loaded"
    local valid_network_hit="$codex_home/valid-network-attempted"
    local network_guard_loaded="$codex_home/network-guard-loaded"
    local network_hit="$codex_home/network-attempted"

    mkdir -p "$codex_home"
    printf 'developer_instructions = "%s"\n' "$marker" \
        >"$codex_home/nix-runtime.config.toml"

    if timeout --signal=TERM --kill-after=1 30 \
        env HOME="$codex_home" CODEX_HOME="$codex_home" \
        CODEX_SQLITE_HOME="$codex_home/sqlite" \
        "$REAL_CODEX_BIN" debug prompt-input hello \
        >"$codex_home/without-profile.json" 2>"$codex_home/without-profile.stderr"; then
        :
    else
        fail "pinned Codex failed without the selected profile"
    fi
    assert_codex_developer_marker \
        "$codex_home/without-profile.json" "$marker" absent ||
        fail "pinned Codex loaded the managed developer instructions without --profile"

    if timeout --signal=TERM --kill-after=1 30 \
        env HOME="$codex_home" CODEX_HOME="$codex_home" \
        CODEX_SQLITE_HOME="$codex_home/sqlite" \
        "$REAL_CODEX_BIN" --profile nix-runtime debug prompt-input hello \
        >"$codex_home/with-profile.json" 2>"$codex_home/with-profile.stderr"; then
        :
    else
        fail "pinned Codex failed to read the selected profile"
    fi
    assert_codex_developer_marker \
        "$codex_home/with-profile.json" "$marker" present ||
        fail "pinned Codex did not load the managed developer instructions"

    {
        printf 'model_provider = "task3-oracle"\n'
        printf '[shell_environment_policy]\n'
        printf 'ignore_default_excludes = false\n'
        printf 'exclude = ["TASK3_SHELL_POLICY_SENTINEL"]\n'
        printf '[model_providers.task3-oracle]\n'
        printf 'name = "Task 3 network oracle"\n'
        printf 'base_url = "http://127.0.0.1:9/v1"\n'
        printf 'env_key = "TASK3_ORACLE_API_KEY"\n'
        printf 'wire_api = "responses"\n'
        printf 'requires_openai_auth = false\n'
    } >"$codex_home/nix-runtime.config.toml"
    if timeout --signal=TERM --kill-after=1 30 \
        env HOME="$codex_home" CODEX_HOME="$codex_home" \
        CODEX_SQLITE_HOME="$codex_home/sqlite" \
        TASK3_SHELL_POLICY_SENTINEL=synthetic-policy-value \
        TASK3_ORACLE_API_KEY=not-a-real-key \
        TASK3_NETWORK_GUARD_LOADED_FILE="$valid_network_guard_loaded" \
        TASK3_NETWORK_ATTEMPT_FILE="$valid_network_hit" \
        "$NETWORK_GUARD_VARIABLE=$NETWORK_GUARD_LIBRARY" \
        "$REAL_CODEX_BIN" --profile nix-runtime --strict-config \
        exec --skip-git-repo-check hello \
        >"$codex_home/valid-strict.stdout" 2>"$codex_home/valid-strict.stderr"; then
        fail "pinned Codex unexpectedly completed the strict network oracle"
    fi
    assert_network_guard_loaded "$valid_network_guard_loaded" codex
    grep -Fx network "$valid_network_hit" >/dev/null ||
        fail "pinned Codex did not accept the managed shell environment policy"

    {
        printf 'model_provider = "task3-oracle"\n'
        printf '%s = true\n' "$strict_marker"
        printf '[model_providers.task3-oracle]\n'
        printf 'name = "Task 3 network oracle"\n'
        printf 'base_url = "http://127.0.0.1:9/v1"\n'
        printf 'env_key = "TASK3_ORACLE_API_KEY"\n'
        printf 'wire_api = "responses"\n'
        printf 'requires_openai_auth = false\n'
    } >"$codex_home/nix-runtime.config.toml"
    if timeout --signal=TERM --kill-after=1 30 \
        env HOME="$codex_home" CODEX_HOME="$codex_home" \
        CODEX_SQLITE_HOME="$codex_home/sqlite" \
        TASK3_ORACLE_API_KEY=not-a-real-key \
        TASK3_NETWORK_GUARD_LOADED_FILE="$network_guard_loaded" \
        TASK3_NETWORK_ATTEMPT_FILE="$network_hit" \
        "$NETWORK_GUARD_VARIABLE=$NETWORK_GUARD_LIBRARY" \
        "$REAL_CODEX_BIN" --profile nix-runtime --strict-config \
        exec --skip-git-repo-check hello \
        >"$codex_home/strict.stdout" 2>"$codex_home/strict.stderr"; then
        fail "pinned Codex accepted an unknown strict profile field"
    fi
    grep -F -- "$strict_marker" "$codex_home/strict.stderr" >/dev/null ||
        fail "pinned Codex strict profile failure did not identify the marker"
    assert_network_guard_loaded "$network_guard_loaded" codex
    [ ! -e "$network_hit" ] ||
        fail "pinned Codex attempted network access before rejecting strict config"
}

run_claude_contract() {
    test_state_matrix claude
    test_conflicts claude
    test_environment_contract claude ANTHROPIC_API_KEY
    test_managed_state_immutable claude
    test_process_identity claude
    test_exit_propagation claude
    test_unset_home_bypass claude
    test_claude_default_root
    test_claude_real
    test_claude_real_process_identity
    test_real_claude_mcp_list_contract
    printf '%s\n' 'agent-wrapper-contract: claude: PASS'
}

run_codex_contract() {
    test_state_matrix codex
    test_conflicts codex
    test_environment_contract codex OPENAI_API_KEY
    test_process_identity codex
    test_exit_propagation codex
    test_codex_host_state
    test_codex_host_state_rejections
    test_codex_log_rotation
    test_codex_unapproved_sqlite_routing
    test_codex_parent_root_rejections
    test_codex_sqlite_wal_snapshot
    test_codex_sqlite_backup_supervision
    test_codex_sqlite_validation_supervision
    test_codex_sqlite_publication
    test_codex_sqlite_concurrent_publication
    test_codex_runtime_profile
    test_codex_runtime_profile_rejections
    test_codex_policy_protocol
    test_codex_policy_response_checker
    test_codex_interrupted_policy_probe
    test_codex_open_file_limit
    test_real_codex_probe_matrix
    test_real_wrapped_codex_status_parity
    test_real_wrapped_codex_routing
    test_real_codex_profile_contract
    printf '%s\n' 'agent-wrapper-contract: codex: PASS'
}

case "${1:-all}" in
claude) run_claude_contract ;;
codex) run_codex_contract ;;
all)
    run_claude_contract
    run_codex_contract
    ;;
*) fail "unknown contract mode: $1" ;;
esac
