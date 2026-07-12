#!/usr/bin/env python3
"""Deterministic unit coverage for the dedicated root watchdog."""

from __future__ import annotations

import ast
import errno
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import time


FUNCTION_NAMES = {
    "close_monitor_descriptors",
    "compensate_scheduler_gap",
    "deadline_expired",
    "file_generation",
    "open_monitor_file",
    "monitor_file_info",
    "lease_state_from_info",
    "monitor_snapshot",
    "refresh_durable_state",
}


def load_watchdog_functions(launcher: Path) -> dict[str, object]:
    """Compile the named production functions without running launcher main."""
    tree = ast.parse(launcher.read_text(encoding="utf-8"), filename=str(launcher))
    definitions = [
        node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name in FUNCTION_NAMES
    ]
    found = {node.name for node in definitions}
    if found != FUNCTION_NAMES:
        raise AssertionError(
            f"watchdog function drift: missing={sorted(FUNCTION_NAMES - found)}"
        )

    namespace: dict[str, object] = {
        "errno": errno,
        "EXIT_CONFIG": 77,
        "os": os,
        "stat": stat,
    }

    def fail(message: str, status: int = 70) -> None:
        raise RuntimeError(f"{status}: {message}")

    namespace["fail"] = fail
    module = ast.Module(body=definitions, type_ignores=[])
    exec(compile(module, str(launcher), "exec"), namespace)
    return namespace


def assert_scheduler_math(namespace: dict[str, object]) -> None:
    """Preserve lease time across scheduler gaps but expire ordinary hangs."""
    compensate = namespace["compensate_scheduler_gap"]
    expired = namespace["deadline_expired"]

    started, last_progress, lease_started = compensate(
        650.0,
        550.0,
        0.5,
        0.0,
        0.0,
        0.0,
    )
    if (started, last_progress, lease_started) != (99.5, 99.5, 99.5):
        raise AssertionError(
            "100-second scheduler gap did not preserve deadline anchors: "
            f"{(started, last_progress, lease_started)}"
        )
    if expired(650.0, lease_started, 600.0):
        raise AssertionError("near-deadline async lease expired during scheduler gap")
    if not expired(699.5, lease_started, 600.0):
        raise AssertionError(
            "async lease did not expire after observable budget elapsed"
        )

    started = 0.0
    last_progress = 0.0
    lease_started = None
    last_poll = 0.0
    for step in range(1, 91):
        now = step * 0.5
        started, last_progress, lease_started = compensate(
            now,
            last_poll,
            0.5,
            started,
            last_progress,
            lease_started,
        )
        last_poll = now
    if (started, last_progress, lease_started) != (0.0, 0.0, None):
        raise AssertionError("ordinary polls incorrectly received scheduler grace")
    if not expired(45.0, last_progress, 45.0):
        raise AssertionError("normal hung root did not expire at its deadline")

    started = 0.0
    last_progress = 0.0
    lease_started = 0.0
    last_poll = 0.0
    for _ in range(4):
        now = last_poll + 2.0
        started, last_progress, lease_started = compensate(
            now,
            last_poll,
            0.5,
            started,
            last_progress,
            lease_started,
        )
        last_poll = now
    if now - lease_started != 2.0:
        raise AssertionError(
            "repeated scheduler starvation did not count one poll per wake: "
            f"elapsed={now - lease_started}"
        )


def assert_fresh_inodes_and_lease(namespace: dict[str, object]) -> None:
    """Require fresh monitor inodes and coherent mode-derived lease snapshots."""
    open_monitor_file = namespace["open_monitor_file"]
    monitor_snapshot = namespace["monitor_snapshot"]

    with tempfile.TemporaryDirectory(prefix="anvil-watchdog-inodes-") as raw:
        root = Path(raw)
        root.chmod(0o700)
        pulse_entry = None
        lease_entry = None
        stale_pulse_fd = None
        stale_lease_fd = None
        try:
            pulse = root / ".anvil-root-pulse"
            pulse.write_bytes(b"stale\n")
            pulse.chmod(0o600)
            stale_pulse_fd = os.open(pulse, os.O_RDONLY | os.O_NOFOLLOW)
            stale_pulse_info = os.fstat(stale_pulse_fd)
            stale_pulse_identity = (
                stale_pulse_info.st_dev,
                stale_pulse_info.st_ino,
            )
            pulse_entry = open_monitor_file(
                str(root), pulse.name, b"pulse:boot\n", 0o600
            )

            lease = root / ".anvil-root-async-lease"
            lease.write_bytes(b"stale\n")
            lease.chmod(0o600)
            stale_lease_fd = os.open(lease, os.O_RDONLY | os.O_NOFOLLOW)
            stale_lease_info = os.fstat(stale_lease_fd)
            stale_lease_identity = (
                stale_lease_info.st_dev,
                stale_lease_info.st_ino,
            )
            lease_entry = open_monitor_file(str(root), lease.name, b"lease\n", 0o400)

            pulse_info = pulse.stat()
            if (pulse_info.st_dev, pulse_info.st_ino) == stale_pulse_identity:
                raise AssertionError("pulse monitor reused its stale inode")
            lease_info = lease.stat()
            if (lease_info.st_dev, lease_info.st_ino) == stale_lease_identity:
                raise AssertionError("lease monitor reused its stale inode")
            if os.read(stale_pulse_fd, 64) != b"stale\n":
                raise AssertionError("pulse monitor replaced the stale file in place")
            if os.read(stale_lease_fd, 64) != b"stale\n":
                raise AssertionError("lease monitor replaced the stale file in place")
            if stat.S_IMODE(pulse_info.st_mode) != 0o600:
                raise AssertionError("pulse monitor mode is not 0600")
            if stat.S_IMODE(lease_info.st_mode) != 0o400:
                raise AssertionError("idle lease mode is not 0400")

            _pulse_generation, idle_generation, idle_state = monitor_snapshot(
                pulse_entry, lease_entry
            )
            if idle_state != "idle":
                raise AssertionError(f"expected idle lease, got {idle_state}")
            time.sleep(0.01)
            lease.chmod(0o600)
            _pulse_generation, active_generation, active_state = monitor_snapshot(
                pulse_entry, lease_entry
            )
            if active_state != "active":
                raise AssertionError(f"expected active lease, got {active_state}")
            if active_generation == idle_generation:
                raise AssertionError("lease chmod did not advance its generation")
        finally:
            for descriptor in (
                None if pulse_entry is None else pulse_entry[1],
                None if lease_entry is None else lease_entry[1],
                stale_pulse_fd,
                stale_lease_fd,
            ):
                if descriptor is not None:
                    os.close(descriptor)


def assert_volatile_wal_is_benign(namespace: dict[str, object]) -> None:
    """Repeated lstat/open WAL replacement must not escape or raise."""
    refresh = namespace["refresh_durable_state"]

    with tempfile.TemporaryDirectory(prefix="anvil-watchdog-wal-") as raw:
        base = Path(raw)
        state_root = base / "state"
        state_root.mkdir(mode=0o700)
        wal = state_root / "index.db-wal"
        wal.write_bytes(b"old")
        wal.chmod(0o600)

        outside = base / "outside"
        outside.write_bytes(b"outside")
        outside.chmod(0o600)
        os.utime(outside, ns=(1_000_000_000, 1_000_000_000))
        outside_mtime = outside.stat().st_mtime_ns
        (state_root / "escape").symlink_to(outside)

        real_open = os.open
        replacements = 0

        def racing_open(
            path: str | bytes | int,
            flags: int,
            mode: int = 0o777,
            *,
            dir_fd: int | None = None,
        ) -> int:
            nonlocal replacements
            if path == wal.name and dir_fd is not None:
                try:
                    os.unlink(path, dir_fd=dir_fd)
                except FileNotFoundError:
                    pass
                replacement_fd = real_open(
                    path,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                    0o600,
                    dir_fd=dir_fd,
                )
                try:
                    os.write(replacement_fd, b"new")
                finally:
                    os.close(replacement_fd)
                replacements += 1
            return real_open(path, flags, mode, dir_fd=dir_fd)

        os.open = racing_open
        try:
            refresh(str(state_root))
            refresh(str(state_root))
        finally:
            os.open = real_open

        if replacements != 2:
            raise AssertionError(f"expected two WAL replacements, got {replacements}")
        if not wal.is_file():
            raise AssertionError("replacement WAL disappeared")
        if outside.stat().st_mtime_ns != outside_mtime:
            raise AssertionError("durable refresh followed a symlink outside state")



def assert_descriptor_cleanup(namespace: dict[str, object]) -> None:
    """A huge OPEN_MAX must not turn monitor detachment into a long sweep."""
    close_descriptors = namespace["close_monitor_descriptors"]
    result_read, result_write = os.pipe()
    kept_read, kept_write = os.pipe()
    leak_read, leak_write = os.pipe()
    child_pid = os.fork()
    if child_pid == 0:
        os.close(result_read)
        os.sysconf = lambda _name: 1_048_576
        started = time.monotonic()
        try:
            close_descriptors({result_write, kept_write})
            elapsed = time.monotonic() - started

            def is_open(descriptor: int) -> bool:
                try:
                    os.fstat(descriptor)
                except OSError as error:
                    if error.errno == errno.EBADF:
                        return False
                    raise
                return True

            payload = {
                "elapsed": elapsed,
                "kept": is_open(kept_write),
                "leaked": [
                    descriptor
                    for descriptor in (kept_read, leak_read, leak_write)
                    if is_open(descriptor)
                ],
            }
        except BaseException as error:
            payload = {"error": repr(error)}
        encoded = (json.dumps(payload, sort_keys=True) + "\n").encode()
        os.write(result_write, encoded)
        os._exit(0)

    os.close(result_write)
    deadline = time.monotonic() + 3.0
    status = None
    while time.monotonic() < deadline:
        waited, candidate = os.waitpid(child_pid, os.WNOHANG)
        if waited == child_pid:
            status = candidate
            break
        time.sleep(0.01)
    if status is None:
        os.kill(child_pid, 9)
        kill_deadline = time.monotonic() + 1.0
        while time.monotonic() < kill_deadline:
            waited, candidate = os.waitpid(child_pid, os.WNOHANG)
            if waited == child_pid:
                status = candidate
                break
            time.sleep(0.01)
        if status is None:
            raise AssertionError(
                "descriptor cleanup child survived SIGKILL for one second"
            )
        raise AssertionError("descriptor cleanup did not finish promptly")
    raw = os.read(result_read, 4096)
    os.close(result_read)
    for descriptor in (kept_read, kept_write, leak_read, leak_write):
        os.close(descriptor)
    if not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
        raise AssertionError(f"descriptor cleanup child failed: {status}")
    payload = json.loads(raw)
    if "error" in payload:
        raise AssertionError(f"descriptor cleanup failed: {payload['error']}")
    if payload["elapsed"] >= 1.0:
        raise AssertionError(f"descriptor cleanup was too slow: {payload}")
    if not payload["kept"] or payload["leaked"]:
        raise AssertionError(f"descriptor cleanup leaked or closed fds: {payload}")


def run_check(label: str, function, namespace: dict[str, object]) -> None:
    started = time.monotonic()
    print(f"watchdog-unit-start {label}", flush=True)
    function(namespace)
    elapsed = time.monotonic() - started
    print(f"watchdog-unit-pass {label} {elapsed:.3f}s", flush=True)


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: watchdog-test.py DEDICATED_LOCK_LAUNCHER")
    namespace = load_watchdog_functions(Path(sys.argv[1]))
    run_check("descriptor-cleanup", assert_descriptor_cleanup, namespace)
    run_check("scheduler-math", assert_scheduler_math, namespace)
    run_check("fresh-inodes", assert_fresh_inodes_and_lease, namespace)
    run_check("volatile-wal", assert_volatile_wal_is_benign, namespace)
    print("watchdog-unit-ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
