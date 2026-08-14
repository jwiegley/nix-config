#!/usr/bin/env bash

set -euo pipefail

tool="${0##*/}"
failure_matches() {
    [[ "${FAKE_FAIL_TOOL:-}" == "$tool" && "$1" == *"${FAKE_FAIL_TARGET:-$1}"* ]]
}
append_log() {
    printf '%s\n' "$2" >>".$1-log"
}
append_argv_log() {
    name="$1"
    shift
    printf '%s\0' "$@" >>".$name-argv"
    printf '\0' >>".$name-argv"
}
run_wrapper_child() {
    trap 'printf "term\n" >>.wrapper-child-events; exit 0' TERM
    printf '%s' "$$" >.wrapper-child-pid
    printf 'start\n' >>.wrapper-child-events
    printf 'ready' >.wrapper-child-ready
    if [[ "${FAKE_CHILD_MODE:-exit}" == run ]]; then
        while :; do :; done
    fi
    exit "${FAKE_CHILD_STATUS:-0}"
}

case "$tool" in
install)
    if [[ $# == 4 && "$1" == -d && "$2" == -m && "$3" == 0700 ]]; then
        directory=1
        mode="$3"
        paths=("$4")
        [[ "$4" == logs || "$4" == runtime ]] || exit 64
    elif [[ $# == 4 && "$1" == -m && "$2" == 0600 ]]; then
        directory=0
        mode="$2"
        paths=("$3" "$4")
        case "$3:$4" in
        /dev/null:runtime/login-items.* | expected-documents:documents/.stignore.tmp.* | expected-desktop:desktop/.stignore.tmp.*) ;;
        *) exit 64 ;;
        esac
    else
        exit 64
    fi
    target="${paths[${#paths[@]} - 1]}"
    failure_matches "$target" && exit 1
    if ((directory)); then
        for path in "${paths[@]}"; do
            mkdir -p "$path"
            chmod "$mode" "$path"
        done
    else
        cp "${paths[0]}" "$target"
        chmod "$mode" "$target"
    fi
    ;;
stat)
    [[ $# == 3 && "$1" == -f ]] || exit 64
    format="$2"
    [[ "$format" == %Su || "$format" == %Lp ]] || exit 64
    path="$3"
    case "$path" in
    logs | runtime | documents | desktop | \
        "Library/Application Support/Syncthing" | \
        "Library/Application Support/Syncthing/cert.pem" | \
        "Library/Application Support/Syncthing/key.pem" | \
        "Library/Application Support/Syncthing/config.xml" | \
        documents/.stignore | desktop/.stignore) ;;
    *) exit 64 ;;
    esac
    if [[ "$format" == %Su ]]; then
        [[ "${FAKE_WRONG_OWNER_PATH:-}" == "$path" ]] && printf 'other\n' || printf 'test\n'
    elif [[ "${FAKE_WRONG_MODE_PATH:-}" == "$path" ]]; then
        printf '755\n'
    elif [[ "$path" == Library/Application\ Support/Syncthing/* || "$path" == */.stignore ]]; then
        printf '600\n'
    else
        printf '700\n'
    fi
    ;;
syncthing)
    [[ $# == 3 && "$1" == device-id && "$2" == --home ]] || exit 64
    [[ "$3" == "Library/Application Support/Syncthing" ]] || exit 64
    [[ "${FAKE_DEVICE_ID_STATUS:-0}" == 0 ]] || exit "$FAKE_DEVICE_ID_STATUS"
    printf '%s\n' "${FAKE_DEVICE_ID:-LOCAL-DEVICE}"
    ;;
pgrep)
    (($# == 2)) || exit 64
    [[ "$1" == -x && "$2" == syncthing ]] || exit 64
    if [[ -n "${FAKE_DAEMON_PGREP_SEQUENCE:-}" ]]; then
        index=0
        [[ ! -f .daemon-pgrep-index ]] || index="$(<.daemon-pgrep-index)"
        printf '%s' "$((index + 1))" >.daemon-pgrep-index
        IFS=';' read -r -a responses <<<"$FAKE_DAEMON_PGREP_SEQUENCE"
        ((index < ${#responses[@]})) || index=$((${#responses[@]} - 1))
        response="${responses[index]}"
        [[ "$response" != none ]] || exit 1
        printf '%s\n' "${response//,/$'\n'}"
        exit 0
    fi
    if [[ -n "${FAKE_DAEMON_PGREP_STATUS:-}" ]]; then
        [[ "$FAKE_DAEMON_PGREP_STATUS" != 0 ]] ||
            printf '%s\n' "${FAKE_DAEMON_PIDS:-100}"
        exit "$FAKE_DAEMON_PGREP_STATUS"
    fi
    [[ -n "${FAKE_DAEMON_PIDS:-}" ]] || exit 1
    printf '%s\n' "${FAKE_DAEMON_PIDS//,/$'\n'}"
    ;;
sfltool)
    [[ $# == 2 && "$1" == list && "$2" == com.apple.LSSharedFileList.SessionLoginItems ]] ||
        exit 64
    case "${FAKE_LOGIN_ITEMS:-clean}" in
    registered) printf '/Applications/Syncthing.app\n' ;;
    bundle) printf 'com.github.xor-gate.syncthing-macosx\n' ;;
    failure) exit 1 ;;
    timeout)
        printf '%s' "$$" >.sfltool-pid
        exec sleep 60
        ;;
    esac
    ;;
kill)
    if [[ "$1" == -0 ]]; then
        (($# == 2)) || exit 64
        [[ "${FAKE_LOGIN_ITEMS:-clean}" == timeout ]] || exit 1
        while [[ ! -s .sfltool-pid ]]; do :; done
        [[ "$2" == "$(<.sfltool-pid)" ]] || exit 64
    else
        (($# == 1)) || exit 64
        [[ -s .sfltool-pid && "$1" == "$(<.sfltool-pid)" ]] || exit 64
        kill -TERM "$1"
    fi
    ;;
launchctl)
    [[ $# == 2 && "$1" == print && "$2" == gui/501/org.nix-community.home.syncthing ]] ||
        exit 64
    [[ -z "${FAKE_MANAGED_PID:-}" ]] || printf '    pid = %s\n' "$FAKE_MANAGED_PID"
    ;;
id)
    [[ $# == 1 && "$1" == -u ]] || exit 64
    printf '501\n'
    ;;
ps)
    [[ $# == 4 && "$1" == -p && "$3" == -o && "$4" == ppid= ]] || exit 64
    [[ -n "${FAKE_EXPECTED_PS_PID:-}" && "$2" == "$FAKE_EXPECTED_PS_PID" ]] || exit 64
    printf '%s\n' "${FAKE_CHILD_PARENT:-}"
    ;;
cmp)
    [[ $# == 3 && "$1" == -s ]] || exit 64
    case "$2:$3" in
    expected-documents:documents/.stignore | expected-desktop:desktop/.stignore) ;;
    *) exit 64 ;;
    esac
    cmp -s "$2" "$3"
    ;;
grep)
    [[ $# == 3 && "$1" == -Eiq ]] || exit 64
    [[ "$2" == '(/Applications/Syncthing\.app|com\.github\.xor-gate\.syncthing-macosx)' ]] ||
        exit 64
    [[ "$3" == runtime/login-items.* ]] || exit 64
    [[ -z "${FAKE_GREP_STATUS:-}" ]] || exit "$FAKE_GREP_STATUS"
    exec grep "$@"
    ;;
mv)
    [[ $# == 3 && "$1" == -f ]] || exit 64
    case "$2:$3" in
    documents/.stignore.tmp.*:documents/.stignore | desktop/.stignore.tmp.*:desktop/.stignore) ;;
    *) exit 64 ;;
    esac
    target="${!#}"
    failure_matches "$target" && exit 1
    append_log mv "$target"
    mv "${@: -2:1}" "$target"
    ;;
rm)
    [[ $# == 2 && "$1" == -f ]] || exit 64
    case "$2" in
    runtime/login-items.* | runtime/gui.sock | documents/.stignore.tmp.* | desktop/.stignore.tmp.*) ;;
    *) exit 64 ;;
    esac
    rm "$@"
    ;;
tmutil)
    if [[ "$1" == isexcluded ]]; then
        [[ $# == 3 && "$2" == -X ]] || exit 64
        [[ "$3" == documents || "$3" == desktop ]] || exit 64
        [[ "${FAKE_TM_INSPECT_FAILURE:-0}" == 0 ]] || exit 1
        printf '%s\n' "${FAKE_TM_EXCLUDED:-1}"
    else
        [[ $# == 2 && "$1" == addexclusion ]] || exit 64
        [[ "$2" == documents || "$2" == desktop ]] || exit 64
        append_log tmutil "${@: -1}"
        exit "${FAKE_TM_ADD_FAILURE:-0}"
    fi
    ;;
plutil)
    [[ $# == 7 && "$1" == -extract && "$2" == 0.IsExcluded && "$3" == raw ]] ||
        exit 64
    [[ "$4" == -o && "$5" == - && "$6" == -- && "$7" == - ]] || exit 64
    [[ "${FAKE_PLUTIL_FAILURE:-0}" == 0 ]] || exit 1
    cat
    ;;
bootstrap)
    index=0
    [[ ! -f .bootstrap-index ]] || index="$(<.bootstrap-index)"
    printf '%s' "$((index + 1))" >.bootstrap-index
    append_log bootstrap "$1"
    append_argv_log bootstrap "$@"
    IFS=, read -r -a statuses <<<"${FAKE_BOOTSTRAP_STATUSES:-0}"
    ((index < ${#statuses[@]})) || index=$((${#statuses[@]} - 1))
    exit "${statuses[index]}"
    ;;
route)
    append_argv_log route "$@"
    [[ $# == 3 && "$1" == -n && "$2" == get && "$3" == 192.168.1.4 ]] || exit 64
    index=0
    [[ ! -f .wrapper-route-index ]] || index="$(<.wrapper-route-index)"
    printf '%s' "$((index + 1))" >.wrapper-route-index
    IFS=';' read -r -a responses <<<"${FAKE_ROUTE_SEQUENCE:-error}"
    ((index < ${#responses[@]})) || index=$((${#responses[@]} - 1))
    response="${responses[index]}"
    [[ "$response" != error ]] || exit 1
    printf '    interface: %s\n' "$response"
    ;;
ifconfig)
    append_argv_log ifconfig "$@"
    (($# == 1)) || exit 64
    printf '    inet %s netmask 0xffffff00\n' "${FAKE_INTERFACE_ADDRESS:-missing}"
    ;;
sleep)
    append_argv_log sleep "$@"
    if [[ "${FAKE_WAIT_FOR_CHILD:-0}" == 1 ]]; then
        while [[ ! -s .wrapper-child-ready ]]; do :; done
    fi
    exit "${FAKE_SLEEP_STATUS:-0}"
    ;;
ssh)
    append_argv_log ssh "$@"
    for argument in "$@"; do
        [[ "$argument" != -N ]] || run_wrapper_child
    done
    exit "${FAKE_SSH_PROBE_STATUS:-0}"
    ;;
socat)
    append_argv_log socat "$@"
    run_wrapper_child
    ;;
*)
    printf 'unknown fake tool: %s\n' "$tool" >&2
    exit 64
    ;;
esac
