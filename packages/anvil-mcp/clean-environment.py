#!/usr/bin/env python3
"""Fail-closed direnv unloading before dedicated Anvil entrypoints."""

from __future__ import annotations

import json
import math
import os
import select
import signal
import subprocess
import sys
import time
from typing import NoReturn


EXIT_SOFTWARE = 70
MAX_EXPORT_BYTES = 4 * 1024 * 1024
ACTIVE_CONTEXT_KEYS = frozenset(
    (
        "DIRENV_DIFF",
        "DIRENV_DIR",
        "DIRENV_FILE",
        "DIRENV_WATCHES",
        "DIRENV_DUMP_FILE_PATH",
    )
)
GENERIC_ERROR = "anvil-mcp: cannot unload inherited direnv environment"
CLEANUP_WAIT_SECONDS = 2.0
TERMINATION_SIGNALS = frozenset(
    signum
    for name in ("SIGHUP", "SIGINT", "SIGTERM")
    if (signum := getattr(signal, name, None)) is not None
)


class SanitizerError(RuntimeError):
    """An inherited environment could not be restored safely."""


class TerminationRequested(BaseException):
    """The wrapper received a termination signal while it owned cleanup."""

    def __init__(self, signum: int) -> None:
        super().__init__(signum)
        self.signum = signum


def termination_handler(signum: int, _frame: object) -> NoReturn:
    """Turn termination into an unwind through owned process cleanup."""
    raise TerminationRequested(signum)


def block_termination_signals() -> set[signal.Signals]:
    """Defer handled termination while exact child custody is in flight."""
    return signal.pthread_sigmask(signal.SIG_BLOCK, TERMINATION_SIGNALS)


def restore_signal_mask(mask: set[signal.Signals]) -> None:
    """Restore the caller's signal mask, delivering any deferred request."""
    signal.pthread_sigmask(signal.SIG_SETMASK, mask)


def install_termination_handlers() -> tuple[dict[int, object], set[signal.Signals]]:
    """Publish handlers transactionally while preserving inherited ignores."""
    previous_mask = block_termination_signals()
    originals = {
        int(signum): signal.getsignal(signum) for signum in TERMINATION_SIGNALS
    }
    installed: list[int] = []
    try:
        for signum in TERMINATION_SIGNALS:
            numeric = int(signum)
            if originals[numeric] != signal.SIG_IGN:
                signal.signal(signum, termination_handler)
                installed.append(numeric)
    except BaseException:
        for numeric in reversed(installed):
            signal.signal(numeric, originals[numeric])
        restore_signal_mask(previous_mask)
        raise
    # Keep signals blocked across return so the caller publishes ORIGINALS
    # before any pending request can enter termination_handler.
    return originals, previous_mask


def restore_termination_handlers(originals: dict[int, object]) -> None:
    """Restore inherited dispositions before replacing the wrapper process."""
    previous_mask = block_termination_signals()
    try:
        for numeric, handler in originals.items():
            signal.signal(numeric, handler)
    finally:
        restore_signal_mask(previous_mask)


def terminate_after_cleanup(
    request: TerminationRequested, originals: dict[int, object]
) -> NoReturn:
    """Restore and redeliver REQUEST after owned children have been reaped."""
    block_termination_signals()
    for numeric, handler in originals.items():
        signal.signal(numeric, handler)
    os.kill(os.getpid(), request.signum)
    try:
        signal.pthread_sigmask(signal.SIG_UNBLOCK, {request.signum})
    finally:
        # A returning inherited handler cannot resume an interrupted transaction.
        os._exit(128 + request.signum)


def fail() -> NoReturn:
    """Exit without reproducing direnv output or parser diagnostics."""
    print(GENERIC_ERROR, file=sys.stderr)
    raise SystemExit(EXIT_SOFTWARE)


def parse_arguments(
    arguments: list[str],
) -> tuple[str, str, str, float, list[str]]:
    """Parse the fixed internal wrapper protocol."""
    if (
        len(arguments) < 11
        or arguments[1] != "--direnv"
        or arguments[3] != "--parent-guard"
        or arguments[5] != "--neutral"
        or arguments[7] != "--timeout-seconds"
        or arguments[9] != "--"
    ):
        raise SanitizerError("invalid invocation")
    direnv = arguments[2]
    parent_guard = arguments[4]
    neutral = arguments[6]
    try:
        timeout = float(arguments[8])
    except ValueError as error:
        raise SanitizerError("invalid timeout") from error
    target = arguments[10:]
    if (
        not os.path.isabs(direnv)
        or not os.path.isabs(parent_guard)
        or not os.path.isfile(parent_guard)
        or not os.path.isabs(neutral)
        or not os.path.isdir(neutral)
        or not math.isfinite(timeout)
        or timeout <= 0
        or timeout > 120
        or not target
        or not os.path.isabs(target[0])
    ):
        raise SanitizerError("invalid invocation")
    return direnv, parent_guard, neutral, timeout, target


def wait_for_process_group_exit(group_id: int) -> None:
    """Wait a bounded interval for the exact guarded group to disappear."""
    deadline = time.monotonic() + CLEANUP_WAIT_SECONDS
    while True:
        try:
            # This is a read-only existence probe.  Once the Popen leader has
            # been reaped its PID could in principle be reused, so never send a
            # destructive signal from this path.
            os.killpg(group_id, 0)
        except ProcessLookupError:
            return
        except PermissionError:
            pass
        if time.monotonic() >= deadline:
            raise SanitizerError("export group cleanup timeout")
        time.sleep(0.01)


def kill_process_group(process: subprocess.Popen[bytes]) -> None:
    """Kill and reap PROCESS plus its same-group descendants within a bound."""
    previous_mask = block_termination_signals()
    try:
        # A completed Popen has already reaped its leader.  In that case the
        # parent guard, rather than this numeric PGID, owns descendant cleanup.
        if process.returncode is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            except OSError:
                try:
                    process.kill()
                except ProcessLookupError:
                    pass
            try:
                process.wait(timeout=CLEANUP_WAIT_SECONDS)
            except subprocess.TimeoutExpired:
                try:
                    process.kill()
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=CLEANUP_WAIT_SECONDS)
                except subprocess.TimeoutExpired as error:
                    raise SanitizerError("export cleanup timeout") from error
        wait_for_process_group_exit(process.pid)
    finally:
        restore_signal_mask(previous_mask)


def read_bounded_export(
    direnv: str,
    parent_guard: str,
    neutral: str,
    timeout: float,
    environment: dict[str, str],
) -> bytes:
    """Run pinned direnv and return one bounded JSON export."""
    process: subprocess.Popen[bytes] | None = None
    try:
        # A handled signal may arrive after Popen has created the guarded
        # child but before Python publishes its exact object to PROCESS.  Block
        # across that assignment so every unwind has exact kill/reap custody.
        previous_mask = block_termination_signals()
        try:
            guarded_environment = environment.copy()
            guarded_environment["ANVIL_HEADLESS_PARENT_PID"] = str(os.getpid())
            process = subprocess.Popen(
                [
                    sys.executable,
                    "-I",
                    "-B",
                    parent_guard,
                    "group",
                    direnv,
                    "export",
                    "json",
                ],
                cwd=neutral,
                env=guarded_environment,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                close_fds=True,
            )
        finally:
            restore_signal_mask(previous_mask)
        if process.stdout is None:
            raise SanitizerError("missing export pipe")
        descriptor = process.stdout.fileno()
        os.set_blocking(descriptor, False)
        deadline = time.monotonic() + timeout
        chunks: list[bytes] = []
        size = 0
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise SanitizerError("export timeout")
            readable, _, _ = select.select(
                [descriptor], [], [], min(remaining, 0.1)
            )
            if not readable:
                continue
            chunk = os.read(descriptor, 65536)
            if not chunk:
                break
            size += len(chunk)
            if size > MAX_EXPORT_BYTES:
                raise SanitizerError("export too large")
            chunks.append(chunk)
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise SanitizerError("export timeout")
        try:
            status = process.wait(timeout=remaining)
        except subprocess.TimeoutExpired as error:
            raise SanitizerError("export timeout") from error
        # The target leader is now reaped, but the parent guard anchored its
        # group before exec and kills every same-group descendant on that exit.
        # Do not publish a cleaned environment until the group is gone.
        wait_for_process_group_exit(process.pid)
        if status != 0:
            raise SanitizerError("export failed")
        return b"".join(chunks)
    except BaseException:
        if process is not None:
            kill_process_group(process)
        raise
    finally:
        if process is not None and process.stdout is not None:
            process.stdout.close()


def reject_constant(_value: str) -> NoReturn:
    """Reject JSON extensions such as NaN and Infinity."""
    raise SanitizerError("invalid JSON constant")


def strict_object(pairs: list[tuple[object, object]]) -> dict[str, object]:
    """Build a JSON object while rejecting duplicate keys."""
    result: dict[str, object] = {}
    for key, value in pairs:
        if not isinstance(key, str) or key in result:
            raise SanitizerError("invalid JSON object")
        result[key] = value
    return result


def parse_patch(document: bytes) -> dict[str, str | None]:
    """Decode and validate one direnv JSON environment patch."""
    if not document:
        raise SanitizerError("empty export")
    try:
        decoded = document.decode("utf-8", errors="strict")
        value = json.loads(
            decoded,
            object_pairs_hook=strict_object,
            parse_constant=reject_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SanitizerError("invalid export") from error
    if not isinstance(value, dict):
        raise SanitizerError("invalid export")
    patch: dict[str, str | None] = {}
    for name, replacement in value.items():
        if (
            not name
            or "=" in name
            or "\x00" in name
            or (
                replacement is not None
                and (
                    not isinstance(replacement, str)
                    or "\x00" in replacement
                )
            )
        ):
            raise SanitizerError("invalid export")
        patch[name] = replacement
    return patch


def clean_environment(
    environment: dict[str, str],
    direnv: str,
    parent_guard: str,
    neutral: str,
    timeout: float,
) -> dict[str, str]:
    """Return ENVIRONMENT with an inherited active direnv fully unloaded."""
    cleaned = environment.copy()
    active = ACTIVE_CONTEXT_KEYS.intersection(cleaned)
    if not active:
        return cleaned
    if not cleaned.get("DIRENV_DIFF"):
        raise SanitizerError("partial direnv context")
    patch = parse_patch(
        read_bounded_export(direnv, parent_guard, neutral, timeout, cleaned)
    )
    for name, replacement in patch.items():
        if replacement is None:
            cleaned.pop(name, None)
        else:
            cleaned[name] = replacement
    if ACTIVE_CONTEXT_KEYS.intersection(cleaned):
        raise SanitizerError("direnv context remains active")
    return cleaned


def main() -> NoReturn:
    """Clean the inherited environment and replace this process."""
    originals: dict[int, object] = {}
    try:
        try:
            originals, previous_mask = install_termination_handlers()
            # ORIGINALS is now published locally, so a deferred signal can
            # safely unwind through the outer termination boundary.
            restore_signal_mask(previous_mask)
            direnv, parent_guard, neutral, timeout, target = parse_arguments(
                sys.argv
            )
            environment = clean_environment(
                dict(os.environ), direnv, parent_guard, neutral, timeout
            )
            restore_termination_handlers(originals)
            os.execve(target[0], target, environment)
        except TerminationRequested:
            raise
        except SystemExit:
            raise
        except BaseException:
            fail()
    except TerminationRequested as request:
        terminate_after_cleanup(request, originals)


if __name__ == "__main__":
    main()
