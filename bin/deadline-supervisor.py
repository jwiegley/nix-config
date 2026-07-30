#!/usr/bin/env python3

"""Run one command in an owned process group with a bounded TERM/KILL deadline."""

import argparse
import math
import os
import signal
import subprocess
import sys
import time


def _group_exists(pgid: int) -> bool:
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _signal_group(pgid: int, sig: signal.Signals) -> None:
    try:
        os.killpg(pgid, sig)
    except ProcessLookupError:
        pass


def _wait_group_gone(
    process: subprocess.Popen[bytes], pgid: int, seconds: float
) -> bool:
    deadline = time.monotonic() + seconds
    while True:
        process.poll()  # Reap the group leader as soon as it exits.
        if not _group_exists(pgid):
            return True
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        time.sleep(min(0.02, remaining))


def _stop_group(
    process: subprocess.Popen[bytes], pgid: int, grace: float
) -> tuple[bool, bool]:
    _signal_group(pgid, signal.SIGTERM)
    if _wait_group_gone(process, pgid, grace):
        return False, True
    _signal_group(pgid, signal.SIGKILL)
    return True, _wait_group_gone(process, pgid, 0.5)


def _shell_status(status: int) -> int:
    return 128 + (-status) if status < 0 else status


def run(
    argv: list[str],
    term_after: float,
    kill_after: float,
    *,
    popen=subprocess.Popen,
) -> int:
    handled_signals = {signal.SIGHUP, signal.SIGTERM}
    previous_handlers = {sig: signal.getsignal(sig) for sig in handled_signals}
    process: subprocess.Popen[bytes] | None = None
    forwarded_signal: int | None = None

    def forward(signum, _frame):
        nonlocal forwarded_signal
        if forwarded_signal is None:
            forwarded_signal = signum

    try:
        for sig in handled_signals:
            signal.signal(sig, forward)
        if forwarded_signal is not None:
            return 128 + forwarded_signal
        process = popen(argv, start_new_session=True)
        pgid = process.pid
        deadline = time.monotonic() + term_after
        while True:
            if forwarded_signal is not None:
                _stop_group(process, pgid, kill_after)
                return 128 + forwarded_signal
            status = process.poll()
            if status is not None:
                break
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                status = None
                break
            time.sleep(min(0.02, remaining))
        if status is None:
            escalated, gone = _stop_group(process, pgid, kill_after)
            if not escalated:
                print(
                    f"deadline-supervisor: terminated process group after {term_after:g}s",
                    file=sys.stderr,
                )
                return 124
            print(
                "deadline-supervisor: SIGKILL sent after TERM grace; "
                + ("process group is gone" if gone else "process group remains observable"),
                file=sys.stderr,
            )
            return 137
        # A successful leader must not leave members of its process group behind.
        if _group_exists(pgid):
            _escalated, gone = _stop_group(process, pgid, kill_after)
            print(
                "deadline-supervisor: command exited with live process-group members; "
                + ("group cleaned" if gone else "group remains observable"),
                file=sys.stderr,
            )
            return 125
        return _shell_status(status)
    except KeyboardInterrupt:
        if process is not None:
            _escalated, gone = _stop_group(process, process.pid, kill_after)
            if not gone:
                print(
                    "deadline-supervisor: process group remains after interrupt",
                    file=sys.stderr,
                )
        return 130
    finally:
        for sig, handler in previous_handlers.items():
            signal.signal(sig, handler)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--term-after", type=float, required=True)
    parser.add_argument("--kill-after", type=float, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if (
        not math.isfinite(args.term_after)
        or not math.isfinite(args.kill_after)
        or args.term_after <= 0
        or args.kill_after <= 0
    ):
        parser.error("deadline values must be positive and finite")
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("a command is required after --")
    try:
        return run(command, args.term_after, args.kill_after)
    except OSError as error:
        print(f"deadline-supervisor: could not start command: {error}", file=sys.stderr)
        return 126


if __name__ == "__main__":
    raise SystemExit(main())
