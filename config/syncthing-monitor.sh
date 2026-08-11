#!/usr/bin/env bash

syncthing_monitor() {
    if (($# != 4)); then
        echo "usage: syncthing_monitor ROUTE-PROBE CHILD-COMMAND SLEEP-COMMAND INTERVAL" >&2
        return 64
    fi

    local route_probe="$1"
    local child_command="$2"
    local sleep_command="$3"
    local interval="$4"
    local route_interface child_status signal_status wait_status
    local child_pid="" timer_pid=""
    local launching=0 pending_signal=""

    cleanup() {
        if [[ -n "$timer_pid" ]]; then
            kill -TERM "$timer_pid" 2>/dev/null || true
            wait "$timer_pid" 2>/dev/null || true
            timer_pid=""
        fi
        if [[ -n "$child_pid" ]]; then
            kill -TERM "$child_pid" 2>/dev/null || true
            wait "$child_pid" 2>/dev/null || true
            child_pid=""
        fi
    }

    # Invoked indirectly by the signal traps below.
    # shellcheck disable=SC2329
    signal_exit() {
        signal_status="$1"
        if ((launching)); then
            [[ -n "$pending_signal" ]] || pending_signal="$signal_status"
            return
        fi
        trap - EXIT HUP INT TERM
        cleanup
        exit "$signal_status"
    }

    trap cleanup EXIT
    trap 'signal_exit 129' HUP
    trap 'signal_exit 130' INT
    trap 'signal_exit 143' TERM

    route_interface="$("$route_probe")" || {
        trap - EXIT HUP INT TERM
        return 0
    }
    launching=1
    "$child_command" "$route_interface" &
    child_pid=$!
    launching=0
    [[ -z "$pending_signal" ]] || signal_exit "$pending_signal"

    while kill -0 "$child_pid" 2>/dev/null; do
        wait_status=0
        launching=1
        "$sleep_command" "$interval" &
        timer_pid=$!
        launching=0
        [[ -z "$pending_signal" ]] || signal_exit "$pending_signal"
        wait "$timer_pid" || wait_status=$?
        timer_pid=""
        if ((wait_status != 0)); then
            trap - EXIT HUP INT TERM
            cleanup
            return "$wait_status"
        fi
        if ! "$route_probe" >/dev/null; then
            trap - EXIT HUP INT TERM
            cleanup
            return 0
        fi
    done

    child_status=0
    wait "$child_pid" || child_status=$?
    child_pid=""
    trap - EXIT HUP INT TERM
    return "$child_status"
}
