#!/usr/bin/env bash

set -euo pipefail

: "${CLAUDE_BIN:?}"
: "${CLAUDE_REAL_BIN:?}"
: "${CODEX_BIN:?}"
: "${CODEX_NON_DARWIN_BIN:?}"
: "${CODEX_APP_IS_COMMAND:?}"
: "${DROID_BIN:?}"
: "${REAL_CODEX_BIN:?}"
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
	droid) printf '%s\n' droid ;;
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
	droid)
		ROOT="$HOME_DIR/.factory"
		FIRST="$ROOT/nix-managed-settings.json"
		SECOND="$ROOT/mcp.json"
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
		command_env+=("CLAUDE_CONFIG_DIR=$ROOT")
		;;
	codex)
		binary=$CODEX_BIN
		command_env+=("CODEX_HOME=$ROOT")
		;;
	droid) binary=$DROID_BIN ;;
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
	claude) assert_argv "$ARGV_FILE" --settings "$FIRST" --mcp-config "$SECOND" "$@" ;;
	codex) assert_argv "$ARGV_FILE" --profile nix-runtime "$@" ;;
	droid) assert_argv "$ARGV_FILE" --settings "$FIRST" "$@" ;;
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
		[ "$LAST_STATUS" -ne 0 ] || fail "$client accepted partial state $state"
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
	droid) binary=$DROID_BIN ;;
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

test_one_conflict() {
	local client=$1
	local label=$2
	shift 2

	new_case "$client" "conflict-$label"
	configure_state complete
	invoke_agent "$client" 0 0 "$@"
	[ "$LAST_STATUS" -ne 0 ] || fail "$client accepted conflicting $label"
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
		;;
	codex)
		test_one_conflict "$client" profile-separated --profile caller tail
		test_one_conflict "$client" profile-equals --profile=caller tail
		test_one_conflict "$client" profile-short -p caller tail
		test_one_conflict "$client" profile-short-attached -pcaller tail
		test_one_conflict "$client" profile-short-equals -p=caller tail
		;;
	droid)
		test_one_conflict "$client" settings-separated --settings "$caller_path" tail
		test_one_conflict "$client" settings-equals "--settings=$caller_path" tail
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
	[ "$LAST_STATUS" -ne 0 ] || fail "Codex accepted conflicting profile case $label"
	assert_upstream_not_invoked
	assert_bounded_redacted_error codex 0
	finish_case codex
}

test_codex_command_scope() {
	local -a supported=(
		exec
		e
		review
		resume
		archive
		delete
		unarchive
		fork
		sandbox
	)
	local -a unsupported=(
		features
		doctor
		completion
		mcp-server
		app-server
		remote-control
		login
		logout
		mcp
		plugin
		update
		apply
		a
		cloud
		cloud-tasks
		exec-server
		help
		execpolicy
		responses-api-proxy
		stdio-to-uds
	)
	local command
	if [ "$CODEX_APP_IS_COMMAND" = 1 ]; then
		unsupported+=(app)
	else
		test_codex_managed_case platform-app-prompt app
	fi

	new_case codex supported-empty
	configure_state complete
	invoke_agent codex 0 0
	[ "$LAST_STATUS" -eq 0 ] || fail "Codex rejected empty interactive invocation"
	assert_managed_argv codex
	finish_case codex

	for command in ordinary-prompt import; do
		new_case codex "supported-prompt-$command"
		configure_state complete
		invoke_agent codex 0 0 "$command"
		[ "$LAST_STATUS" -eq 0 ] || fail "Codex rejected interactive prompt $command"
		assert_managed_argv codex "$command"
		finish_case codex
	done

	test_codex_managed_case lone-dash-prompt -
	test_codex_managed_case review-lone-dash-prompt review -
	test_codex_managed_case debug-lone-dash-prompt debug prompt-input -

	for command in "${supported[@]}"; do
		new_case codex "supported-$command"
		configure_state complete
		invoke_agent codex 0 0 "$command" tail
		[ "$LAST_STATUS" -eq 0 ] || fail "Codex rejected supported command $command"
		assert_managed_argv codex "$command" tail
		finish_case codex
	done

	new_case codex supported-debug-prompt-input
	configure_state complete
	invoke_agent codex 0 0 debug prompt-input tail
	[ "$LAST_STATUS" -eq 0 ] || fail "Codex rejected debug prompt-input"
	assert_managed_argv codex debug prompt-input tail
	finish_case codex

	new_case codex unsupported-debug-models
	configure_state complete
	invoke_agent codex 0 0 debug models --bundled
	[ "$LAST_STATUS" -eq 0 ] || fail "Codex wrapper rejected debug models"
	assert_argv "$ARGV_FILE" debug models --bundled
	finish_case codex

	for command in "${unsupported[@]}"; do
		new_case codex "unsupported-$command"
		configure_state complete
		invoke_agent codex 0 0 "$command" tail
		[ "$LAST_STATUS" -eq 0 ] || fail "Codex wrapper rejected unsupported command $command"
		assert_argv "$ARGV_FILE" "$command" tail
		finish_case codex
	done

	new_case codex unsupported-app-server-prettier
	configure_state complete
	invoke_agent codex 0 0 app-server generate-ts -p "$CASE_DIR/out"
	[ "$LAST_STATUS" -eq 0 ] || fail "Codex wrapper mistook app-server -p for a profile"
	assert_argv "$ARGV_FILE" app-server generate-ts -p "$CASE_DIR/out"
	finish_case codex

	new_case codex separated-option-before-supported
	configure_state complete
	invoke_agent codex 0 0 --config model=probe debug prompt-input tail
	[ "$LAST_STATUS" -eq 0 ] || fail "Codex wrapper misparsed a global option value"
	assert_managed_argv codex --config model=probe debug prompt-input tail
	finish_case codex

	new_case codex attached-option-before-supported
	configure_state complete
	invoke_agent codex 0 0 --config=model=probe -mprobe exec tail
	[ "$LAST_STATUS" -eq 0 ] || fail "Codex wrapper misparsed attached root options"
	assert_managed_argv codex --config=model=probe -mprobe exec tail
	finish_case codex

	test_codex_managed_case empty-string-root-options \
		--config '' --model= --local-provider= debug prompt-input tail
	test_codex_managed_case comma-bearing-root-options \
		--config=one, --model=gpt, --local-provider=probe, \
		debug prompt-input tail
	test_codex_managed_case lone-dash-root-values \
		--model - --cd - --add-dir - debug prompt-input tail
	test_codex_delegated_case empty-separated-root-paths \
		--cd '' --add-dir '' --image '' debug prompt-input tail
	test_codex_delegated_case malformed-root-value --config --help
	test_codex_delegated_case empty-root-cd --cd= debug prompt-input tail
	test_codex_delegated_case empty-root-image --image= debug prompt-input tail
	test_codex_delegated_case invalid-root-image-list \
		--image=a, debug prompt-input tail
	test_codex_managed_case valid-root-enums \
		--sandbox workspace-write --ask-for-approval=never debug prompt-input tail
	test_codex_delegated_case invalid-root-sandbox-separated \
		--sandbox bogus debug prompt-input tail
	test_codex_delegated_case invalid-root-sandbox-attached \
		--sandbox=bogus debug prompt-input tail
	test_codex_delegated_case invalid-root-sandbox-short \
		-sbogus debug prompt-input tail
	test_codex_delegated_case invalid-root-approval-separated \
		--ask-for-approval bogus debug prompt-input tail
	test_codex_delegated_case invalid-root-approval-attached \
		--ask-for-approval=bogus debug prompt-input tail
	test_codex_delegated_case invalid-root-approval-short \
		-abogus debug prompt-input tail
	test_codex_delegated_case root-approval-bypass-conflict \
		--ask-for-approval never --yolo debug prompt-input tail
	test_codex_delegated_case root-bypass-approval-conflict-reversed \
		--dangerously-bypass-approvals-and-sandbox \
		--ask-for-approval=never debug prompt-input tail
	test_codex_delegated_case duplicate-root-model \
		--model one --model two debug prompt-input tail
	test_codex_delegated_case duplicate-root-local-provider \
		--local-provider one --local-provider two debug prompt-input tail
	test_codex_delegated_case duplicate-root-sandbox \
		--sandbox read-only --sandbox workspace-write debug prompt-input tail
	test_codex_delegated_case duplicate-root-approval \
		--ask-for-approval never --ask-for-approval never debug prompt-input tail
	test_codex_delegated_case duplicate-root-cd \
		--cd one --cd two debug prompt-input tail
	test_codex_delegated_case duplicate-root-remote \
		--remote one --remote two debug prompt-input tail
	test_codex_delegated_case duplicate-root-remote-auth \
		--remote-auth-token-env ONE --remote-auth-token-env TWO debug prompt-input tail
	test_codex_delegated_case duplicate-root-oss \
		--oss --oss debug prompt-input tail
	test_codex_delegated_case duplicate-root-hook-trust \
		--dangerously-bypass-hook-trust --dangerously-bypass-hook-trust \
		debug prompt-input tail
	test_codex_delegated_case duplicate-root-search \
		--search --search debug prompt-input tail
	test_codex_delegated_case duplicate-root-no-alt-screen \
		--no-alt-screen --no-alt-screen debug prompt-input tail
	test_codex_delegated_case duplicate-root-strict \
		--strict-config --strict-config debug prompt-input tail
	test_codex_delegated_case duplicate-root-bypass \
		--yolo --dangerously-bypass-approvals-and-sandbox debug prompt-input tail
	test_codex_delegated_case duplicate-root-profile \
		--profile one --profile two exec tail
	test_codex_managed_case root-strict-exec \
		--strict-config exec tail
	test_codex_managed_case root-strict-review \
		--strict-config review --uncommitted
	test_codex_delegated_case root-strict-sandbox \
		--strict-config sandbox /bin/true
	test_codex_delegated_case root-strict-debug \
		--strict-config debug prompt-input tail
	test_codex_managed_case root-remote-prompt \
		--remote ws://127.0.0.1:1 ordinary-prompt
	test_codex_managed_case root-remote-resume \
		--remote ws://127.0.0.1:1 resume --last
	test_codex_delegated_case root-remote-exec \
		--remote ws://127.0.0.1:1 exec tail
	test_codex_delegated_case root-remote-review \
		--remote ws://127.0.0.1:1 review --uncommitted
	test_codex_delegated_case root-remote-sandbox \
		--remote ws://127.0.0.1:1 sandbox /bin/true
	test_codex_delegated_case root-remote-debug \
		--remote ws://127.0.0.1:1 debug prompt-input tail
	test_codex_delegated_case unpaired-root-remote-auth \
		--remote-auth-token-env TOKEN resume --last
	test_codex_managed_case paired-root-remote-auth \
		--remote ws://127.0.0.1:1 --remote-auth-token-env TOKEN resume --last
	test_codex_managed_case repeated-root-options \
		--config one=1 -ctwo=2 --enable alpha --enable beta \
		--disable gamma --disable delta --image one --image two \
		--add-dir one --add-dir two debug prompt-input tail

	new_case codex variadic-images-before-supported
	configure_state complete
	invoke_agent codex 0 0 --image one.png two.png --oss exec tail
	[ "$LAST_STATUS" -eq 0 ] || fail "Codex wrapper misparsed variadic images"
	assert_managed_argv codex --image one.png two.png --oss exec tail
	finish_case codex
	test_codex_managed_case lone-dash-image-before-supported \
		--image - --oss exec tail

	new_case codex attached-image-before-supported
	configure_state complete
	invoke_agent codex 0 0 -ione.png --oss exec tail
	[ "$LAST_STATUS" -eq 0 ] || fail "Codex wrapper misparsed attached image"
	assert_managed_argv codex -ione.png --oss exec tail
	finish_case codex

	test_codex_delegated_case option-config-separated \
		--config model=probe features list
	test_codex_delegated_case option-config-attached \
		--config=model=probe features list
	test_codex_delegated_case option-config-short-attached \
		-cmodel=probe features list
	test_codex_delegated_case option-model-separated \
		--model probe features list
	test_codex_delegated_case option-model-attached \
		--model=probe features list
	test_codex_delegated_case option-model-short-attached \
		-mprobe features list
	test_codex_delegated_case option-local-provider \
		--local-provider ollama features list
	test_codex_delegated_case option-sandbox \
		--sandbox read-only features list
	test_codex_delegated_case option-cd \
		--cd "$CASE_DIR/root" features list
	test_codex_delegated_case option-add-dir \
		--add-dir "$CASE_DIR/extra" features list
	test_codex_delegated_case option-approval \
		--ask-for-approval never features list
	test_codex_delegated_case option-remote \
		--remote ws://127.0.0.1:1 features list
	test_codex_delegated_case option-remote-auth \
		--remote-auth-token-env TOKEN features list
	test_codex_delegated_case option-enable \
		--enable alpha features list
	test_codex_delegated_case option-disable-attached \
		--disable=alpha features list
	test_codex_managed_case option-image-separated-greedy \
		--image one.png features list
	test_codex_delegated_case option-image-attached-bounded \
		--image=one.png features list
	test_codex_delegated_case option-image-short-attached-bounded \
		-ione.png features list

	test_codex_managed_case nested-debug-config \
		debug --config model=probe prompt-input tail
	test_codex_managed_case nested-debug-enable \
		debug --enable alpha --disable beta prompt-input tail
	test_codex_delegated_case malformed-nested-debug-value \
		debug --config --help prompt-input tail

	new_case codex separator-prompt
	configure_state complete
	invoke_agent codex 0 0 -- features
	[ "$LAST_STATUS" -eq 0 ] || fail "Codex wrapper misparsed a prompt after --"
	assert_managed_argv codex -- features
	finish_case codex
	test_codex_managed_case separator-profile-literal -- -p
	test_codex_delegated_case separator-extra-positional -- -p caller
	test_codex_managed_case option-after-prompt ordinary-prompt --model o3
	test_codex_delegated_case second-root-prompt ordinary-prompt second-prompt

	for command in --help --version -h -V; do
		new_case codex "root-pass-through-$command"
		configure_state complete
		invoke_agent codex 0 0 "$command"
		[ "$LAST_STATUS" -eq 0 ] || fail "Codex wrapper rejected $command"
		assert_argv "$ARGV_FILE" "$command"
		finish_case codex
	done

	new_case codex unknown-option-pass-through
	configure_state complete
	invoke_agent codex 0 0 --future-option exec tail
	[ "$LAST_STATUS" -eq 0 ] || fail "Codex wrapper rejected an unknown option"
	assert_argv "$ARGV_FILE" --future-option exec tail
	finish_case codex

	for command in exec resume archive delete unarchive fork; do
		new_case codex "unknown-$command-child-option-pass-through"
		configure_state complete
		invoke_agent codex 0 0 "$command" --future-option
		[ "$LAST_STATUS" -eq 0 ] ||
			fail "Codex wrapper rejected an unknown $command child option"
		assert_argv "$ARGV_FILE" "$command" --future-option
		finish_case codex
	done
	test_codex_delegated_case duplicate-exec-model \
		exec --model one --model two tail
	test_codex_delegated_case duplicate-resume-last \
		resume --last --last tail
	test_codex_delegated_case duplicate-archive-remote \
		archive --remote one --remote two session
	test_codex_delegated_case duplicate-delete-force \
		delete --force --force 00000000-0000-0000-0000-000000000000
	test_codex_delegated_case duplicate-fork-bypass-alias \
		fork --yolo --dangerously-bypass-approvals-and-sandbox tail
	test_codex_delegated_case duplicate-exec-profile \
		exec -p one -p two tail
	test_codex_delegated_case unpaired-command-remote-auth \
		resume --remote-auth-token-env TOKEN --last
	test_codex_managed_case paired-command-remote-auth \
		resume --remote ws://127.0.0.1:1 --remote-auth-token-env TOKEN --last
	test_codex_managed_case cross-scope-root-auth-command-remote \
		--remote-auth-token-env TOKEN resume --remote ws://127.0.0.1:1 --last
	test_codex_managed_case cross-scope-root-remote-command-auth \
		--remote ws://127.0.0.1:1 resume --remote-auth-token-env TOKEN --last
	test_codex_delegated_case exec-empty-separated-paths \
		exec --cd '' --add-dir '' --image '' --json tail
	test_codex_delegated_case exec-invalid-image-list \
		exec --image a, --json tail
	test_codex_managed_case nested-exec-resume \
		exec resume session prompt
	test_codex_managed_case nested-exec-resume-last \
		exec resume --last prompt
	test_codex_managed_case nested-exec-resume-image \
		exec resume --image image.png session prompt
	test_codex_managed_case nested-exec-review-prompt \
		exec review prompt
	test_codex_managed_case nested-exec-review-selector \
		exec review --uncommitted
	test_codex_managed_case nested-exec-review-title \
		exec review --commit deadbeef --title title
	test_codex_managed_case nested-exec-scope-local-model \
		exec --model outer resume --model inner session
	test_codex_managed_case nested-exec-scope-local-conflict \
		exec --full-auto resume --yolo session
	test_codex_delegated_case nested-exec-resume-profile \
		exec resume --profile caller
	test_codex_delegated_case nested-exec-review-profile \
		exec review -pcaller
	test_codex_delegated_case nested-exec-resume-outer-only-option \
		exec resume --oss
	test_codex_delegated_case nested-exec-review-outer-only-option \
		exec review --image image.png
	test_codex_delegated_case nested-exec-resume-extra-positionals \
		exec resume -i image.png session prompt extra
	test_codex_delegated_case nested-exec-review-selector-conflict \
		exec review --uncommitted --base main
	test_codex_delegated_case nested-exec-duplicate-model \
		exec resume --model one --model two session
	test_codex_delegated_case nested-exec-same-scope-conflict \
		exec resume --full-auto --yolo session
	test_codex_delegated_case nested-exec-help exec help resume
	test_codex_conflict_case nested-exec-outer-profile \
		exec --profile caller resume session
	test_codex_conflict_case root-and-command-profile \
		--profile root resume --profile child --last
	test_codex_conflict_case root-and-sandbox-profile \
		--profile root sandbox --profile child /bin/true

	new_case codex malformed-option-pass-through
	configure_state complete
	invoke_agent codex 0 0 --config
	[ "$LAST_STATUS" -eq 0 ] || fail "Codex wrapper rejected a malformed option"
	assert_argv "$ARGV_FILE" --config
	finish_case codex

	new_case codex sandbox-child-profile-looking
	configure_state complete
	invoke_agent codex 0 0 sandbox /bin/echo -p child
	[ "$LAST_STATUS" -eq 0 ] || fail "Codex wrapper rejected a sandbox child -p"
	assert_managed_argv codex sandbox /bin/echo -p child
	finish_case codex

	new_case codex sandbox-separator-child-profile-looking
	configure_state complete
	invoke_agent codex 0 0 sandbox -- /bin/echo -p child
	[ "$LAST_STATUS" -eq 0 ] || fail "Codex wrapper rejected a sandbox child -p after --"
	assert_managed_argv codex sandbox -- /bin/echo -p child
	finish_case codex

	new_case codex mcp-child-profile-looking
	configure_state complete
	invoke_agent codex 0 0 mcp add probe -- /bin/echo -p child
	[ "$LAST_STATUS" -eq 0 ] || fail "Codex wrapper rejected an MCP child -p"
	assert_argv "$ARGV_FILE" mcp add probe -- /bin/echo -p child
	finish_case codex

	new_case codex mcp-explicit-profile-delegates
	configure_state complete
	invoke_agent codex 0 0 --profile caller mcp list
	[ "$LAST_STATUS" -eq 0 ] || fail "Codex wrapper rejected an MCP explicit profile"
	assert_argv "$ARGV_FILE" --profile caller mcp list
	finish_case codex
	test_codex_delegated_case mcp-root-profile-equals --profile=caller mcp list
	test_codex_delegated_case mcp-root-profile-short -p caller mcp list
	test_codex_delegated_case mcp-root-profile-short-attached -pcaller mcp list
	test_codex_delegated_case mcp-root-profile-short-equals -p=caller mcp list
	test_codex_delegated_case invalid-root-profile-name \
		--profile ../bad exec tail
	test_codex_delegated_case invalid-root-profile-attached \
		--profile=bad.name exec tail
	test_codex_delegated_case empty-root-profile \
		--profile '' exec tail
	test_codex_conflict_case valid-leading-hyphen-profile \
		--profile=-foo exec tail
	test_codex_conflict_case root-lone-dash-profile \
		--profile - exec tail

	test_codex_conflict_case exec-local-profile exec -pcaller tail
	test_codex_conflict_case exec-lone-dash-profile exec --profile - tail
	test_codex_conflict_case e-local-profile e -p=caller tail
	test_codex_conflict_case resume-local-profile resume --profile caller
	test_codex_conflict_case archive-local-profile archive session -pcaller
	test_codex_conflict_case delete-local-profile delete session --profile=caller
	test_codex_conflict_case unarchive-local-profile unarchive session -p=caller
	test_codex_conflict_case fork-local-profile fork -p caller --last
	test_codex_conflict_case interactive-profile-after-prompt ordinary-prompt -pcaller
	test_codex_conflict_case sandbox-local-profile \
		sandbox --permission-profile standard -p caller /bin/true
	test_codex_conflict_case sandbox-lone-dash-profile \
		sandbox --permission-profile standard --profile - /bin/true
	test_codex_conflict_case sandbox-global-enable-profile \
		sandbox --enable unified_exec -p caller /bin/true
	test_codex_conflict_case sandbox-global-disable-attached-profile \
		sandbox --disable=unified_exec -pcaller /bin/true
	test_codex_delegated_case sandbox-malformed-global-value \
		sandbox --enable -p caller /bin/true
	test_codex_delegated_case sandbox-invalid-profile-name \
		sandbox --profile bad.name /bin/true
	test_codex_delegated_case sandbox-malformed-profile-value \
		sandbox --profile -- /bin/true
	test_codex_delegated_case sandbox-profile-before-unknown \
		sandbox --profile caller --future-option /bin/true
	test_codex_delegated_case sandbox-duplicate-profile \
		sandbox --profile one --profile two /bin/true
	test_codex_delegated_case sandbox-empty-cd \
		sandbox --cd= /bin/true
	test_codex_delegated_case sandbox-cwd-requires-permission \
		sandbox -C "$work_root" /bin/true
	test_codex_delegated_case sandbox-include-requires-permission \
		sandbox --include-managed-config /bin/true
	test_codex_delegated_case sandbox-readable-requires-state \
		sandbox --sandbox-state-readable-root "$work_root" /bin/true
	test_codex_delegated_case sandbox-network-requires-state \
		sandbox --sandbox-state-disable-network /bin/true
	test_codex_delegated_case sandbox-state-conflicts-permission \
		sandbox --sandbox-state-json '{}' --permission-profile standard /bin/true
	test_codex_managed_case sandbox-valid-state \
		sandbox --sandbox-state-json '{}' \
		--sandbox-state-readable-root "$work_root" \
		--sandbox-state-disable-network /bin/true
	test_codex_managed_case sandbox-valid-permission \
		sandbox --permission-profile standard -C "$work_root" \
		--include-managed-config /bin/true
	test_codex_managed_case sandbox-lone-dash-command sandbox -
	test_codex_managed_case sandbox-lone-dash-values \
		sandbox --sandbox-state-json '{}' \
		--sandbox-state-readable-root - /bin/true
	test_codex_managed_case sandbox-lone-dash-cd \
		sandbox --permission-profile standard -C - /bin/true
	test_codex_delegated_case sandbox-empty-separated-cd \
		sandbox --permission-profile standard -C '' /bin/true
	test_codex_managed_case sandbox-lone-dash-permission \
		sandbox --permission-profile - /bin/true
	test_codex_delegated_case sandbox-duplicate-state \
		sandbox --sandbox-state-json '{}' --sandbox-state-json '{}' -- /bin/true
	test_codex_delegated_case sandbox-duplicate-permission \
		sandbox --permission-profile standard --permission-profile standard /bin/true
	test_codex_delegated_case sandbox-duplicate-cd \
		sandbox --permission-profile standard -C "$work_root" -C "$work_root" /bin/true
	test_codex_delegated_case sandbox-duplicate-include \
		sandbox --permission-profile standard \
		--include-managed-config --include-managed-config /bin/true
	test_codex_delegated_case sandbox-duplicate-network \
		sandbox --sandbox-state-json '{}' \
		--sandbox-state-disable-network --sandbox-state-disable-network /bin/true
	if [ "$CODEX_APP_IS_COMMAND" = 1 ]; then
		test_codex_managed_case sandbox-darwin-socket \
			sandbox --allow-unix-socket "$work_root/socket" /bin/true
		test_codex_managed_case sandbox-darwin-lone-dash-socket \
			sandbox --allow-unix-socket - /bin/true
		test_codex_managed_case sandbox-darwin-repeated-socket \
			sandbox --allow-unix-socket one --allow-unix-socket two /bin/true
		test_codex_delegated_case sandbox-darwin-duplicate-log-denials \
			sandbox --log-denials --log-denials /bin/true
	fi

	test_codex_managed_case review-child-profile-literal review -- -p
	test_codex_delegated_case review-malformed-profile-looking review -p caller
	test_codex_delegated_case review-selector-conflict \
		review --uncommitted --base main
	test_codex_delegated_case review-selector-conflict-reversed \
		review --base main --uncommitted
	test_codex_delegated_case review-title-without-commit \
		review --title title
	test_codex_managed_case review-lone-dash-base review --base -
	test_codex_delegated_case review-prompt-selector-conflict \
		review --uncommitted prompt
	test_codex_delegated_case review-duplicate-uncommitted \
		review --uncommitted --uncommitted
	test_codex_delegated_case review-duplicate-base \
		review --base main --base other
	test_codex_delegated_case review-duplicate-commit \
		review --commit one --commit two
	test_codex_delegated_case review-duplicate-title \
		review --commit deadbeef --title one --title two
	test_codex_delegated_case review-duplicate-strict \
		review --strict-config --strict-config
	test_codex_managed_case review-valid-title \
		review --commit deadbeef --title title
	test_codex_managed_case debug-child-profile-literal \
		debug prompt-input -- -p
	test_codex_managed_case debug-lone-dash-image \
		debug prompt-input --image -
	test_codex_delegated_case debug-empty-separated-image \
		debug prompt-input --image ''
	test_codex_delegated_case debug-invalid-image-list \
		debug prompt-input --image=a,
	test_codex_delegated_case debug-malformed-profile-looking \
		debug prompt-input -p caller
}

test_codex_non_darwin_table() {
	local current_codex_bin=$CODEX_BIN

	CODEX_BIN=$CODEX_NON_DARWIN_BIN
	test_codex_managed_case non-darwin-app-prompt app
	test_codex_delegated_case non-darwin-darwin-sandbox-option \
		sandbox --allow-unix-socket "$work_root/socket" /bin/true
	CODEX_BIN=$current_codex_bin
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

test_real_codex_profile_contract() {
	local codex_home="$work_root/real Codex profile"
	local marker=NIX_MANAGED_PROFILE_SENTINEL
	local strict_marker=task_3_nix_managed_strict_marker
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
	grep -Fx loaded "$network_guard_loaded" >/dev/null ||
		fail "pinned Codex did not load the process-level network guard"
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
	[ "$MCP_REMOTE_REV" = 02619aff36e79803d7c894e8c8ae7b34b2d11f8c ] ||
		fail "mcp-remote revision differs"
	[ "$MCP_REMOTE_NAR_HASH" = 'sha256-+oNI2Uq7gW3sLzJS4ky2+BXhTmo44+WpcdYgieGPpmI=' ] ||
		fail "mcp-remote NAR hash differs"
	[ "$MCP_REMOTE_LOCK_HASH" = 598f60becf15b3197fce5c4e38e8158f3db2f774d218a443e50b3b5e2b098542 ] ||
		fail "mcp-remote pnpm lock hash differs"

	run_bridge_failure arity 'agent-http-header-bridge: invalid invocation' "$BRIDGE_BIN"
	run_bridge_failure http-url 'agent-http-header-bridge: invalid invocation' \
		env TASK3_BRIDGE_TOKEN=BRIDGE-SECRET-MUST-NOT-LEAK "$BRIDGE_BIN" \
		http://example.invalid/mcp x-ref-api-key TASK3_BRIDGE_TOKEN
	run_bridge_failure malformed-url 'agent-http-header-bridge: invalid invocation' \
		"$BRIDGE_BIN" https:// x-ref-api-key TASK3_BRIDGE_TOKEN
	run_bridge_failure credentialed-url 'agent-http-header-bridge: invalid invocation' \
		env TASK3_BRIDGE_TOKEN=BRIDGE-SECRET-MUST-NOT-LEAK "$BRIDGE_BIN" \
		https://user:password@example.invalid/mcp x-ref-api-key TASK3_BRIDGE_TOKEN
	run_bridge_failure header-name 'agent-http-header-bridge: invalid invocation' \
		"$BRIDGE_BIN" https://example.invalid/mcp 'bad header' TASK3_BRIDGE_TOKEN
	run_bridge_failure header-colon 'agent-http-header-bridge: invalid invocation' \
		"$BRIDGE_BIN" https://example.invalid/mcp 'bad:header' TASK3_BRIDGE_TOKEN
	run_bridge_failure header-newline 'agent-http-header-bridge: invalid invocation' \
		"$BRIDGE_BIN" https://example.invalid/mcp $'bad\nheader' TASK3_BRIDGE_TOKEN
	run_bridge_failure environment-name 'agent-http-header-bridge: invalid invocation' \
		"$BRIDGE_BIN" https://example.invalid/mcp x-ref-api-key 9INVALID
	run_bridge_failure environment-hyphen 'agent-http-header-bridge: invalid invocation' \
		"$BRIDGE_BIN" https://example.invalid/mcp x-ref-api-key INVALID-NAME
	run_bridge_failure missing-environment 'agent-http-header-bridge: credential unavailable' \
		env -u TASK3_BRIDGE_TOKEN "$BRIDGE_BIN" \
		https://example.invalid/mcp x-ref-api-key TASK3_BRIDGE_TOKEN
	run_bridge_failure empty-environment 'agent-http-header-bridge: credential unavailable' \
		env TASK3_BRIDGE_TOKEN= "$BRIDGE_BIN" \
		https://example.invalid/mcp x-ref-api-key TASK3_BRIDGE_TOKEN
	run_bridge_failure control-environment 'agent-http-header-bridge: credential unavailable' \
		env TASK3_BRIDGE_TOKEN=$'BRIDGE-SECRET-MUST-NOT-LEAK\nbad' "$BRIDGE_BIN" \
		https://example.invalid/mcp x-ref-api-key TASK3_BRIDGE_TOKEN
}

for client in claude codex droid; do
	test_state_matrix "$client"
	test_conflicts "$client"
	test_exit_propagation "$client"
done

test_unset_home_bypass claude
test_unset_home_bypass droid

test_claude_real
test_codex_host_state
test_codex_runtime_profile
test_codex_runtime_profile_rejections
test_codex_command_scope
test_codex_non_darwin_table
test_real_codex_profile_contract
test_bridge_static_contract
