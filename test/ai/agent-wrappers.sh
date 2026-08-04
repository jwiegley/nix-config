#!/usr/bin/env bash

set -euo pipefail

: "${CLAUDE_BIN:?}"
: "${CLAUDE_REAL_BIN:?}"
: "${CODEX_BIN:?}"
: "${CODEX_NON_DARWIN_BIN:?}"
: "${CODEX_APP_IS_COMMAND:?}"
: "${CODEX_RAISES_OPEN_FILE_LIMIT:?}"
: "${CLAUDE_IDENTITY_BIN:?}"
: "${CLAUDE_REAL_IDENTITY_BIN:?}"
: "${CODEX_IDENTITY_BIN:?}"
: "${REAL_CLAUDE_BIN:?}"
: "${REAL_CODEX_BIN:?}"
: "${REAL_WRAPPED_CODEX_BIN:?}"
: "${BRIDGE_BIN:?}"
: "${NETWORK_GUARD_LIBRARY:?}"
: "${NETWORK_GUARD_VARIABLE:?}"

work_root="$TMPDIR/agent wrapper cases"
managed_file_sentinel='MANAGED-FILE-CONTENT-MUST-NEVER-APPEAR-7d6b78'
case_counter=0
cleanup_roots=()

mkdir -p "$work_root"

fail() {
    printf 'agent-wrappers check [%s]: %s\n' "${CASE_DIR:-global}" "$*" >&2
    exit 1
}

cleanup() {
    local root
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
    AGENT_TEST_UID="9$BASHPID$case_counter"
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
        command_env+=("CODEX_HOME=$ROOT")
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
    shift 2

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
        test_one_conflict "$client" profile-separated --profile caller tail
        test_one_conflict "$client" profile-equals --profile=caller tail
        test_one_conflict "$client" profile-short -p caller tail
        test_one_conflict "$client" profile-short-attached -pcaller tail
        test_one_conflict "$client" profile-short-equals -p=caller tail
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

test_codex_command_scope() {
    local command
    local -a managed=(
        exec
        e
        review
        resume
        archive
        delete
        unarchive
        fork
        mcp
        sandbox
    )
    local -a delegated=(
        features
        doctor
        completion
        mcp-server
        app-server
        remote-control
        login
        logout
        plugin
        update
        apply
        a
        cloud
        cloud-tasks
        exec-server
        execpolicy
        help
        responses-api-proxy
        stdio-to-uds
    )

    test_codex_managed_case interactive-empty
    test_codex_managed_case interactive-prompt ordinary-prompt
    test_codex_managed_case interactive-command-like-prompt import

    for command in "${managed[@]}"; do
        case "$command" in
        exec | e | review) test_codex_managed_case "managed-$command" "$command" opaque ;;
        resume | fork) test_codex_managed_case "managed-$command" "$command" --last ;;
        archive | delete | unarchive)
            test_codex_managed_case "managed-$command" "$command" target
            ;;
        mcp) test_codex_managed_case managed-mcp mcp list ;;
        sandbox) test_codex_managed_case managed-sandbox sandbox /bin/true ;;
        esac
    done
    test_codex_managed_case managed-debug-prompt-input debug prompt-input opaque
    test_codex_managed_case root-option-before-command --model o3 exec opaque
    test_codex_managed_case archive-lone-dash archive -
    test_codex_managed_case resume-last-lone-dash resume --last -

    for command in "${delegated[@]}"; do
        test_codex_delegated_case "delegated-$command" "$command" opaque
    done
    test_codex_delegated_case delegated-debug-child debug models opaque
    if [ "$CODEX_APP_IS_COMMAND" = 1 ]; then
        test_codex_delegated_case delegated-app app opaque
    else
        test_codex_managed_case interactive-app-prompt app
    fi

    # These are the only syntax edges the classifier owns. Upstream still
    # validates every option value, positional count, and command combination.
    test_codex_managed_case greedy-image-remains-interactive --image one.png features list
    test_codex_delegated_case attached-image-selects-command --image=one.png features list
    test_codex_delegated_case prompt-before-command \
        ordinary-prompt features list
    test_codex_delegated_case dash-prompt-before-command - features list
    test_codex_managed_case prompt-before-mcp ordinary-prompt mcp list
    test_codex_delegated_case future-option --future-option exec tail
    test_codex_managed_case separator-profile-literal -- -p
    test_codex_managed_case exec-separator-profile-literal exec -- -p
    test_codex_managed_case sandbox-profile-looking-payload sandbox /bin/echo -p child
    test_codex_managed_case sandbox-separated-profile-looking-payload sandbox -- /bin/echo -p child
    test_codex_managed_case mcp-profile-looking-payload mcp add probe -- /bin/echo -p child
    test_codex_managed_case mcp-undelimited-help-payload \
        mcp add probe /bin/echo --help
    test_codex_managed_case mcp-separator-before-name \
        mcp add -- probe /bin/echo
    test_codex_managed_case mcp-list-trailing-separator mcp list --
    test_codex_managed_case mcp-get-dash-name mcp get -- -name
    test_codex_managed_case mcp-add-lone-dash-name mcp add - /bin/echo
    test_codex_managed_case mcp-get-lone-dash-name mcp get -
    test_codex_managed_case debug-profile-looking-argument debug prompt-input -p caller
    test_codex_delegated_case nonprofile-short-p app-server generate-ts -p "$CASE_DIR/out"

    test_codex_conflict_case mcp-root-profile --profile caller mcp list
    test_codex_conflict_case mcp-root-profile-prompt-before-command \
        --profile caller ordinary-prompt mcp list
    test_codex_conflict_case mcp-root-profile-undelimited-payload \
        --profile caller mcp add probe /bin/echo --help
    test_codex_conflict_case mcp-root-profile-separator-before-name \
        --profile caller mcp add -- probe /bin/echo
    test_codex_conflict_case mcp-root-profile-trailing-separator \
        --profile caller mcp list --
    test_codex_conflict_case mcp-root-profile-dash-name \
        --profile caller mcp get -- -name
    test_codex_conflict_case mcp-root-profile-lone-dash-name \
        --profile caller mcp get -
    test_codex_conflict_case archive-root-profile-lone-dash \
        --profile caller archive -
    test_codex_conflict_case exec-local-profile exec --profile caller opaque
    test_codex_conflict_case root-and-local-profile --profile root exec -p child opaque
    test_codex_conflict_case attached-leading-hyphen-profile --profile=-foo exec opaque
    test_codex_delegated_case invalid-profile-name --profile bad.name exec opaque
    test_codex_delegated_case invalid-separated-profile --profile -foo exec opaque
    test_codex_delegated_case duplicate-root-profile --profile one --profile two exec opaque
    test_codex_delegated_case duplicate-local-profile exec -p one -p two opaque
    test_codex_delegated_case nested-exec-profile exec resume -p caller
    test_codex_delegated_case nested-exec-resume-help exec resume --help
    test_codex_delegated_case nested-exec-review-help exec review --help
    test_codex_delegated_case nested-exec-root-profile-help \
        --profile caller exec resume --help
    test_codex_delegated_case nested-exec-local-profile-help \
        exec -p caller resume --help
    test_codex_delegated_case exec-prompt-before-help exec foo help
    test_codex_delegated_case exec-dash-before-help exec - help
    test_codex_delegated_case exec-prompt-before-nested-help \
        exec foo resume --help
    test_codex_delegated_case exec-root-profile-prompt-before-help \
        --profile caller exec foo help
    test_codex_delegated_case resume-missing-remote \
        resume --remote -p caller
    test_codex_conflict_case resume-remote-profile \
        resume --remote ws://example.invalid -p caller
    test_codex_conflict_case sandbox-local-profile \
        sandbox -p caller /bin/true
    test_codex_delegated_case exec-tui-only-option \
        exec --search -p caller
    if [ "$CODEX_APP_IS_COMMAND" = 1 ]; then
        test_codex_conflict_case sandbox-darwin-option-profile \
            sandbox --allow-unix-socket "$work_root/socket" -p caller /bin/true
    else
        test_codex_delegated_case sandbox-darwin-option-profile \
            sandbox --allow-unix-socket "$work_root/socket" -p caller /bin/true
    fi
    test_codex_delegated_case missing-profile-value --profile

    test_codex_delegated_case root-help --help
    test_codex_delegated_case exec-help exec --help
    test_codex_delegated_case exec-help-subcommand exec help
    test_codex_delegated_case exec-root-profile-help-subcommand \
        --profile caller exec help
    test_codex_delegated_case mcp-help mcp --help
    test_codex_delegated_case mcp-help-subcommand mcp help
    test_codex_delegated_case mcp-root-profile-help-subcommand \
        --profile caller mcp help
    test_codex_delegated_case debug-prompt-input-help debug prompt-input --help
    test_codex_delegated_case sandbox-help sandbox --help
    test_codex_delegated_case ignore-user-config-help \
        exec --ignore-user-config --help
    test_one_conflict codex ignore-user-config \
        exec --ignore-user-config opaque
    test_one_conflict codex prompt-before-exec-ignore-user-config \
        foo exec --ignore-user-config opaque
    test_codex_conflict_case nested-ignore-user-config \
        exec resume --ignore-user-config --last
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

assert_codex_host_state() {
    local seed=$1

    assert_env "CODEX_HOME=$ROOT"
    assert_env "CODEX_SQLITE_HOME=$CODEX_LOCAL_ROOT/sqlite"
    [ -f "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite" ] ||
        fail "Codex did not seed host-local SQLite state"
    cmp "$seed" "$CODEX_LOCAL_ROOT/sqlite/memories_1.sqlite" ||
        fail "Codex altered the seeded SQLite file"
    [ "$(stat -c %a "$CODEX_LOCAL_ROOT")" = 700 ] ||
        fail "Codex local root does not have mode 0700"
    [ "$(stat -c %a "$CODEX_LOCAL_ROOT/sqlite")" = 700 ] ||
        fail "Codex SQLite root does not have mode 0700"
    [ "$(stat -c %a "$CODEX_LOCAL_ROOT/log")" = 700 ] ||
        fail "Codex log root does not have mode 0700"
    [ -L "$ROOT/log" ] || fail "Codex did not create the host-local log link"
    [ "$(readlink "$ROOT/log")" = "$CODEX_LOCAL_ROOT/log" ] ||
        fail "Codex log link has the wrong target"
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

test_codex_runtime_profile() {
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
    new_case codex host-state-wrong-log-link
    configure_state complete
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

test_codex_host_state() {
    local seed

    new_case codex host-state-managed
    configure_state complete
    seed="$ROOT/memories_1.sqlite"
    printf '%s\n' codex-seed-managed >"$seed"
    invoke_agent codex 0 0 alpha
    [ "$LAST_STATUS" -eq 0 ] || fail "managed Codex host-state launch failed"
    assert_managed_argv codex alpha
    assert_codex_host_state "$seed"
    finish_case codex

    new_case codex host-state-bypass
    configure_state directories
    seed="$ROOT/memories_1.sqlite"
    printf '%s\n' codex-seed-bypass >"$seed"
    invoke_agent codex 1 0 alpha
    [ "$LAST_STATUS" -eq 0 ] || fail "bypass Codex host-state launch failed"
    assert_argv "$ARGV_FILE" alpha
    assert_codex_host_state "$seed"
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
        "$binary" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE" &
    wrapper_pid=$!
    REAL_WRAPPED_CODEX_LAST_PID=$wrapper_pid
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
        assert_network_guard_loaded "$network_guard_loaded" codex "$wrapper_pid"
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
        "$REAL_CODEX_BIN" "$@" >"$CASE_DIR/raw.stdout" 2>"$CASE_DIR/raw.stderr"; then
        raw_status=0
    else
        raw_status=$?
    fi

    run_real_wrapped_codex \
        "$wrapped_network_guard_loaded" "$wrapped_network_hit" "$@"
    wrapped_status=$LAST_STATUS
    [ "$raw_status" -ne 0 ] || fail "real Codex parity case was not malformed: $label"
    [ "$wrapped_status" -eq "$raw_status" ] ||
        fail "wrapped/raw Codex status differs for $label: $wrapped_status/$raw_status"
    case "$expected_route" in
    delegate)
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
    assert_network_guard_loaded \
        "$wrapped_network_guard_loaded" codex "$REAL_WRAPPED_CODEX_LAST_PID"
    [ ! -e "$raw_network_hit" ] && [ ! -e "$wrapped_network_hit" ] ||
        fail "Codex parity probe attempted network access"
    [ ! -e "$ROOT/sessions" ] && [ ! -e "$raw_home/sessions" ] ||
        fail "Codex parity probe created session state"
    finish_case codex
}

test_real_wrapped_codex_status_parity() {
    assert_real_codex_status_parity root-missing-config delegate --config
    assert_real_codex_status_parity exec-missing-model delegate exec --model
    assert_real_codex_status_parity exec-invalid-color delegate \
        exec --color purple --help
    assert_real_codex_status_parity review-selector-conflict manage \
        review --uncommitted --base main
    assert_real_codex_status_parity resume-positional-overflow manage \
        resume --last session prompt
    assert_real_codex_status_parity resume-missing-remote delegate \
        resume --remote -p caller
    assert_real_codex_status_parity mcp-missing-name manage mcp get
    assert_real_codex_status_parity sandbox-state-conflict manage \
        sandbox --permission-profile standard --sandbox-state-json '{}' /usr/bin/true
    assert_real_codex_status_parity debug-empty-image manage \
        debug prompt-input --image=
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

    if env HOME="$codex_home" CODEX_HOME="$codex_home" \
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

    if env HOME="$codex_home" CODEX_HOME="$codex_home" \
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
    if env HOME="$codex_home" CODEX_HOME="$codex_home" \
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
    if env HOME="$codex_home" CODEX_HOME="$codex_home" \
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

run_bridge_failure() {
    local label=$1
    local expected=$2
    shift 2
    local stdout="$work_root/bridge-$label.stdout"
    local stderr="$work_root/bridge-$label.stderr"
    local status bytes

    if "$@" >"$stdout" 2>"$stderr"; then
        status=0
    else
        status=$?
    fi
    [ "$status" -ne 0 ] || fail "bridge accepted invalid case: $label"
    bytes=$(wc -c <"$stderr")
    [ "$bytes" -gt 0 ] && [ "$bytes" -le 512 ] ||
        fail "bridge $label error is empty or exceeds 512 bytes"
    printf '%s\n' "$expected" | cmp -s - "$stderr" ||
        fail "bridge $label did not emit its exact fixed error"
    [ ! -s "$stdout" ] || fail "bridge $label wrote to stdout"
}

test_bridge_static_contract() {
    [ "$BRIDGE_PRESENT" = 1 ] || fail "agent-http-header-bridge package/output is missing"
    [ -x "$BRIDGE_BIN" ] || fail "agent-http-header-bridge executable is missing"

    run_bridge_failure arity 'agent-http-header-bridge: invalid invocation' "$BRIDGE_BIN"
    run_bridge_failure http-url 'agent-http-header-bridge: invalid invocation' \
        env TASK3_BRIDGE_TOKEN=BRIDGE-SECRET-MUST-NOT-LEAK "$BRIDGE_BIN" \
        http://example.invalid/mcp x-agent-test-token TASK3_BRIDGE_TOKEN
    run_bridge_failure malformed-url 'agent-http-header-bridge: invalid invocation' \
        "$BRIDGE_BIN" https:// x-agent-test-token TASK3_BRIDGE_TOKEN
    run_bridge_failure credentialed-url 'agent-http-header-bridge: invalid invocation' \
        env TASK3_BRIDGE_TOKEN=BRIDGE-SECRET-MUST-NOT-LEAK "$BRIDGE_BIN" \
        https://user:password@example.invalid/mcp x-agent-test-token TASK3_BRIDGE_TOKEN
    run_bridge_failure header-name 'agent-http-header-bridge: invalid invocation' \
        "$BRIDGE_BIN" https://example.invalid/mcp 'bad header' TASK3_BRIDGE_TOKEN
    run_bridge_failure header-colon 'agent-http-header-bridge: invalid invocation' \
        "$BRIDGE_BIN" https://example.invalid/mcp 'bad:header' TASK3_BRIDGE_TOKEN
    run_bridge_failure header-newline 'agent-http-header-bridge: invalid invocation' \
        "$BRIDGE_BIN" https://example.invalid/mcp $'bad\nheader' TASK3_BRIDGE_TOKEN
    run_bridge_failure environment-name 'agent-http-header-bridge: invalid invocation' \
        "$BRIDGE_BIN" https://example.invalid/mcp x-agent-test-token 9INVALID
    run_bridge_failure environment-hyphen 'agent-http-header-bridge: invalid invocation' \
        "$BRIDGE_BIN" https://example.invalid/mcp x-agent-test-token INVALID-NAME
    run_bridge_failure missing-environment 'agent-http-header-bridge: credential unavailable' \
        env -u TASK3_BRIDGE_TOKEN "$BRIDGE_BIN" \
        https://example.invalid/mcp x-agent-test-token TASK3_BRIDGE_TOKEN
    run_bridge_failure empty-environment 'agent-http-header-bridge: credential unavailable' \
        env TASK3_BRIDGE_TOKEN= "$BRIDGE_BIN" \
        https://example.invalid/mcp x-agent-test-token TASK3_BRIDGE_TOKEN
    run_bridge_failure control-environment 'agent-http-header-bridge: credential unavailable' \
        env TASK3_BRIDGE_TOKEN=$'BRIDGE-SECRET-MUST-NOT-LEAK\nbad' "$BRIDGE_BIN" \
        https://example.invalid/mcp x-agent-test-token TASK3_BRIDGE_TOKEN
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
    test_codex_runtime_profile
    test_codex_runtime_profile_rejections
    test_codex_command_scope
    test_codex_open_file_limit
    test_real_wrapped_codex_status_parity
    test_real_wrapped_codex_routing
    test_real_codex_profile_contract
    printf '%s\n' 'agent-wrapper-contract: codex: PASS'
}

case "${1:-all}" in
claude) run_claude_contract ;;
codex) run_codex_contract ;;
bridge)
    test_bridge_static_contract
    printf '%s\n' 'agent-wrapper-contract: bridge: PASS'
    ;;
all)
    run_claude_contract
    run_codex_contract
    test_bridge_static_contract
    ;;
*) fail "unknown contract mode: $1" ;;
esac
