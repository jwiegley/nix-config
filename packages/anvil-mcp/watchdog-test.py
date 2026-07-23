#!/usr/bin/env python3
"""Deterministic unit coverage for the dedicated root watchdog."""

from __future__ import annotations

import contextlib
import errno
import fcntl
import importlib.util
import io
import json
import os
from pathlib import Path
import select
import signal
import stat
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock


FUNCTION_NAMES = {
    "close_monitor_descriptors",
    "compensate_scheduler_gap",
    "configure_watchdog_capabilities",
    "deadline_expired",
    "drain_activity_connection",
    "file_generation",
    "kill_parent_if",
    "open_monitor_file",
    "monitor_file_info",
    "lease_state_from_info",
    "monitor_snapshot",
    "prepare_activity_listener",
    "accept_activity_connection",
    "refresh_durable_state",
    "safe_unlink_activity",
    "select_deadline_cause",
    "strict_json_object",
    "validate_activity",
    "validate_activity_socket_path",
    "validate_watchdog_event",
    "write_watchdog_event",
}


def load_support():
    """Load the shared hyphenated helper only from its required exact path."""
    raw = os.environ.get("ANVIL_WATCHDOG_TEST_SUPPORT")
    if not raw:
        raise RuntimeError("missing required ANVIL_WATCHDOG_TEST_SUPPORT")
    path = Path(raw)
    if not path.is_absolute() or not path.is_file():
        raise RuntimeError("ANVIL_WATCHDOG_TEST_SUPPORT must name an absolute file")
    if not str(path).startswith("/nix/store/"):
        raise RuntimeError(
            "ANVIL_WATCHDOG_TEST_SUPPORT must name a realised store file"
        )
    spec = importlib.util.spec_from_file_location("anvil_watchdog_test_support", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load ANVIL_WATCHDOG_TEST_SUPPORT")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if Path(module.__file__).resolve() != path.resolve():
        raise RuntimeError("watchdog support path identity changed")
    return module


SUPPORT = load_support()
LAUNCHER = SUPPORT.required_store_path("ANVIL_DEDICATED_LOCK_LAUNCHER")


def load_watchdog_functions(launcher: Path) -> dict[str, object]:
    """Load the exact generated launcher definitions through shared support."""
    return SUPPORT.load_generated_launcher(launcher, FUNCTION_NAMES).__dict__


def assert_scheduler_math(namespace: dict[str, object]) -> None:
    """Compensate scheduler gaps without extending a hung root deadline."""
    compensate = namespace["compensate_scheduler_gap"]
    expired = namespace["deadline_expired"]

    started, last_progress, dispatch_started = compensate(
        650.0,
        550.0,
        0.5,
        0.0,
        0.0,
        0.0,
    )
    if (started, last_progress, dispatch_started) != (99.5, 99.5, 99.5):
        raise AssertionError(
            "100-second scheduler gap did not preserve deadline anchors: "
            f"{(started, last_progress, dispatch_started)}"
        )
    if expired(144.0, last_progress, 45.0):
        raise AssertionError("compensated root expired before its normal deadline")
    if not expired(144.5, last_progress, 45.0):
        raise AssertionError(
            "compensated root did not expire after its normal deadline"
        )
    if expired(234.0, dispatch_started, 135.0):
        raise AssertionError("dispatch expired before its independent deadline")
    if not expired(234.5, dispatch_started, 135.0):
        raise AssertionError("dispatch did not expire at its independent deadline")

    started = 0.0
    last_progress = 0.0
    dispatch_started = None
    last_poll = 0.0
    for step in range(1, 91):
        now = step * 0.5
        started, last_progress, dispatch_started = compensate(
            now,
            last_poll,
            0.5,
            started,
            last_progress,
            dispatch_started,
        )
        last_poll = now
    if (started, last_progress, dispatch_started) != (0.0, 0.0, None):
        raise AssertionError("ordinary polls incorrectly received scheduler grace")
    if not expired(45.0, last_progress, 45.0):
        raise AssertionError("normal hung root did not expire at its deadline")

    started = 0.0
    last_progress = 0.0
    dispatch_started = 0.0
    last_poll = 0.0
    for _ in range(4):
        now = last_poll + 2.0
        started, last_progress, dispatch_started = compensate(
            now,
            last_poll,
            0.5,
            started,
            last_progress,
            dispatch_started,
        )
        last_poll = now
    if now - last_progress != 2.0 or now - dispatch_started != 2.0:
        raise AssertionError(
            "repeated scheduler starvation did not count one poll per wake: "
            f"heartbeat={now - last_progress}, "
            f"dispatch={now - dispatch_started}"
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


RUN_ID = "0123456789abcdef0123456789abcdef"
DAEMON_PID = 4242
LIFECYCLE_OUTER_TIMEOUT_SECONDS = 10
ACTIVITY_KEYS = {
    "schema_version",
    "run_id",
    "daemon_pid",
    "sequence",
    "phase",
    "method",
    "tool",
    "phase_started_unix_ms",
    "observed_at_unix_ms",
}
EVENT_KEYS = {
    "schema_version",
    "run_id",
    "daemon_pid",
    "cause",
    "phase",
    "method",
    "tool",
    "observed_at_unix_ms",
    "daemon_uptime_ms",
    "heartbeat_age_ms",
    "heartbeat_limit_ms",
    "dispatch_age_ms",
    "dispatch_limit_ms",
}
CAUSES = (
    "startup-timeout",
    "heartbeat-timeout",
    "dispatch-timeout",
    "lock-integrity-failure",
    "monitor-state-invalid",
    "durable-refresh-failure",
    "monitor-internal-error",
)


def valid_activity(**changes):
    value = {
        "schema_version": 1,
        "run_id": RUN_ID,
        "daemon_pid": DAEMON_PID,
        "sequence": 1,
        "phase": "tool-call",
        "method": "tools/call",
        "tool": "emacs-eval",
        "phase_started_unix_ms": 1_000,
        "observed_at_unix_ms": 1_001,
    }
    value.update(changes)
    return value


def valid_event(**changes):
    value = {
        "schema_version": 1,
        "run_id": RUN_ID,
        "daemon_pid": DAEMON_PID,
        "cause": "dispatch-timeout",
        "phase": "tool-call",
        "method": "tools/call",
        "tool": "emacs-eval",
        "observed_at_unix_ms": 1_100,
        "daemon_uptime_ms": 100,
        "heartbeat_age_ms": 20,
        "heartbeat_limit_ms": 45_000,
        "dispatch_age_ms": 225_001,
        "dispatch_limit_ms": 225_000,
    }
    value.update(changes)
    return value


class WatchdogTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.namespace = load_watchdog_functions(LAUNCHER)


class WatchdogProtocolTests(WatchdogTestCase):
    def test_strict_json_object_rejects_duplicate_keys_and_nonfinite_values(self):
        strict = self.namespace["strict_json_object"]
        with self.assertRaises(ValueError):
            strict(b'{"schema_version":1,"schema_version":1}')
        for constant in (b"NaN", b"Infinity", b"-Infinity"):
            with self.subTest(constant=constant), self.assertRaises(ValueError):
                strict(b'{"value":' + constant + b"}")

    def test_strict_json_object_requires_utf8_object(self):
        strict = self.namespace["strict_json_object"]
        with self.assertRaises((UnicodeError, ValueError)):
            strict(b'{"bad":"\xff"}')
        with self.assertRaises(ValueError):
            strict(b"[]")

    def test_activity_accepts_only_the_frozen_schema(self):
        validate = self.namespace["validate_activity"]
        self.assertEqual(
            validate(valid_activity(), RUN_ID, DAEMON_PID, 0),
            valid_activity(),
        )
        for mutation in (
            {**valid_activity(), "extra": 1},
            {key: value for key, value in valid_activity().items() if key != "phase"},
        ):
            with self.subTest(keys=set(mutation)), self.assertRaises(ValueError):
                validate(mutation, RUN_ID, DAEMON_PID, 0)

    def test_activity_rejects_bool_for_every_integer(self):
        validate = self.namespace["validate_activity"]
        for field in (
            "schema_version",
            "daemon_pid",
            "sequence",
            "phase_started_unix_ms",
            "observed_at_unix_ms",
        ):
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate(valid_activity(**{field: True}), RUN_ID, DAEMON_PID, 0)

    def test_activity_rejects_float_and_exponent_schema_versions(self):
        validate = self.namespace["validate_activity"]
        with self.assertRaises(ValueError):
            validate(
                valid_activity(schema_version=1.0),
                RUN_ID,
                DAEMON_PID,
                0,
            )
        payload = json.dumps(
            valid_activity(),
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
        payload = payload.replace(b'"schema_version":1', b'"schema_version":1e0')
        with self.assertRaises(ValueError):
            validate(payload, RUN_ID, DAEMON_PID, 0)

    def test_activity_rejects_wrong_types_for_every_enum(self):
        validate = self.namespace["validate_activity"]
        for field in ("phase", "method"):
            for value in ([], {}, True, 1, None):
                with (
                    self.subTest(field=field, value=value),
                    self.assertRaises(ValueError),
                ):
                    validate(valid_activity(**{field: value}), RUN_ID, DAEMON_PID, 0)

    def test_activity_rejects_identity_sequence_enum_tool_and_size_violations(self):
        validate = self.namespace["validate_activity"]
        mutations = (
            valid_activity(run_id="A" * 32),
            valid_activity(daemon_pid=DAEMON_PID + 1),
            valid_activity(sequence=0),
            valid_activity(phase="blocked"),
            valid_activity(method="secrets/read"),
            valid_activity(tool="bad tool"),
            valid_activity(tool="x" * 129),
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                validate(mutation, RUN_ID, DAEMON_PID, 0)
        oversized = valid_activity(tool=None)
        oversized["padding"] = "x" * 1024
        with self.assertRaises(ValueError):
            validate(json.dumps(oversized).encode(), RUN_ID, DAEMON_PID, 0)


class WatchdogCauseTests(WatchdogTestCase):
    def test_event_schema_accepts_all_and_only_frozen_causes(self):
        validate = self.namespace["validate_watchdog_event"]
        for cause in CAUSES:
            event = valid_event(cause=cause)
            with self.subTest(cause=cause):
                self.assertEqual(validate(event, RUN_ID, DAEMON_PID), event)
        coherent_events = (
            valid_event(),
            valid_event(heartbeat_age_ms=None, heartbeat_limit_ms=None),
            valid_event(dispatch_age_ms=None, dispatch_limit_ms=None),
            valid_event(
                heartbeat_age_ms=None,
                heartbeat_limit_ms=None,
                dispatch_age_ms=None,
                dispatch_limit_ms=None,
            ),
            valid_event(phase="unknown"),
        )
        for event in coherent_events:
            with self.subTest(event=event):
                self.assertEqual(validate(event, RUN_ID, DAEMON_PID), event)
        incoherent_events = (
            valid_event(heartbeat_age_ms=None),
            valid_event(heartbeat_limit_ms=None),
            valid_event(dispatch_age_ms=None),
            valid_event(dispatch_limit_ms=None),
        )
        for event in incoherent_events:
            with self.subTest(event=event), self.assertRaises(ValueError):
                validate(event, RUN_ID, DAEMON_PID)
        with self.assertRaises(ValueError):
            validate(valid_event(cause="unknown"), RUN_ID, DAEMON_PID)
        with self.assertRaises(ValueError):
            validate({**valid_event(), "extra": 1}, RUN_ID, DAEMON_PID)

    def test_event_rejects_bool_for_every_integer(self):
        validate = self.namespace["validate_watchdog_event"]
        for field in (
            "schema_version",
            "daemon_pid",
            "observed_at_unix_ms",
            "daemon_uptime_ms",
            "heartbeat_age_ms",
            "heartbeat_limit_ms",
            "dispatch_age_ms",
            "dispatch_limit_ms",
        ):
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate(valid_event(**{field: True}), RUN_ID, DAEMON_PID)

    def test_event_rejects_float_and_exponent_schema_versions(self):
        validate = self.namespace["validate_watchdog_event"]
        with self.assertRaises(ValueError):
            validate(
                valid_event(schema_version=1.0),
                RUN_ID,
                DAEMON_PID,
            )
        payload = json.dumps(
            valid_event(),
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
        payload = payload.replace(b'"schema_version":1', b'"schema_version":1e0')
        with self.assertRaises(ValueError):
            validate(payload, RUN_ID, DAEMON_PID)

    def test_event_rejects_wrong_types_for_every_enum(self):
        validate = self.namespace["validate_watchdog_event"]
        for field in ("cause", "phase", "method"):
            for value in ([], {}, True, 1, None):
                with (
                    self.subTest(field=field, value=value),
                    self.assertRaises(ValueError),
                ):
                    validate(valid_event(**{field: value}), RUN_ID, DAEMON_PID)
        for event in (
            valid_event(phase="blocked"),
            valid_event(method="secrets/read"),
        ):
            with self.subTest(event=event), self.assertRaises(ValueError):
                validate(event, RUN_ID, DAEMON_PID)

    def test_deadline_cause_uses_the_earlier_absolute_deadline(self):
        select_cause = self.namespace["select_deadline_cause"]
        self.assertEqual(
            select_cause(300.0, 250.0, 45.0, 0.0, 225.0),
            "dispatch-timeout",
        )
        self.assertEqual(
            select_cause(300.0, 0.0, 45.0, 250.0, 45.0),
            "heartbeat-timeout",
        )
        self.assertEqual(
            select_cause(100.0, 90.0, 45.0, None, 225.0),
            None,
        )

    def test_event_writer_is_one_nonblocking_atomic_write(self):
        write_event = self.namespace["write_watchdog_event"]
        read_descriptor, write_descriptor = os.pipe()
        try:
            os.set_blocking(read_descriptor, False)
            os.set_blocking(write_descriptor, False)
            real_write = os.write
            calls = []

            def recording_write(descriptor, payload):
                calls.append((descriptor, payload))
                return real_write(descriptor, payload)

            with (
                mock.patch.object(os, "write", side_effect=recording_write),
                mock.patch.object(
                    os,
                    "open",
                    side_effect=AssertionError("event writer opened a file"),
                ),
                mock.patch.object(
                    os,
                    "fsync",
                    side_effect=AssertionError("event writer called fsync"),
                ),
            ):
                self.assertTrue(write_event(write_descriptor, valid_event()))
            self.assertEqual(len(calls), 1)
            self.assertEqual(calls[0][0], write_descriptor)
            self.assertLessEqual(len(calls[0][1]), 512)
            self.assertTrue(calls[0][1].endswith(b"\n"))
            self.assertEqual(os.read(read_descriptor, 513), calls[0][1])
        finally:
            os.close(read_descriptor)
            os.close(write_descriptor)

    def test_event_writer_drops_tool_when_needed_to_fit(self):
        write_event = self.namespace["write_watchdog_event"]
        read_descriptor, write_descriptor = os.pipe()
        try:
            os.set_blocking(read_descriptor, False)
            os.set_blocking(write_descriptor, False)
            event = valid_event(
                tool="x" * 128,
                observed_at_unix_ms=10**20,
                daemon_uptime_ms=10**20,
                heartbeat_age_ms=10**20,
                heartbeat_limit_ms=10**20,
                dispatch_age_ms=10**20,
                dispatch_limit_ms=10**20,
            )
            encoded = (
                json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n"
            ).encode()
            without_tool = {**event, "tool": None}
            encoded_without_tool = (
                json.dumps(without_tool, sort_keys=True, separators=(",", ":")) + "\n"
            ).encode()
            self.assertGreater(len(encoded), 512)
            self.assertLessEqual(len(encoded_without_tool), 512)
            self.assertTrue(write_event(write_descriptor, event))
            payload = os.read(read_descriptor, 513)
            self.assertLessEqual(len(payload), 512)
            decoded = json.loads(payload)
            self.assertIsNone(decoded["tool"])
        finally:
            os.close(read_descriptor)
            os.close(write_descriptor)

    def test_event_writer_never_retries_diagnostic_failures(self):
        write_event = self.namespace["write_watchdog_event"]
        for failure in (
            OSError(errno.EAGAIN, "full"),
            OSError(errno.EPIPE, "broken"),
        ):
            with (
                self.subTest(failure=failure),
                mock.patch.object(os, "fpathconf", return_value=512),
                mock.patch.object(os, "write", side_effect=failure) as write,
            ):
                self.assertFalse(write_event(42, valid_event()))
                write.assert_called_once()

        with (
            mock.patch.object(os, "fpathconf", return_value=511),
            mock.patch.object(os, "write") as write,
        ):
            self.assertFalse(write_event(42, valid_event()))
            write.assert_not_called()

        def partial_write(_descriptor, payload):
            return len(payload) - 1

        with (
            mock.patch.object(os, "fpathconf", return_value=512),
            mock.patch.object(os, "write", side_effect=partial_write) as write,
        ):
            self.assertFalse(write_event(42, valid_event()))
            write.assert_called_once()

    def test_monitor_ignores_sigpipe_and_attributes_early_internal_failure(self):
        monitor = self.namespace["monitor"]
        original_kill_parent_if = self.namespace["kill_parent_if"]
        observed = {}
        signal_calls = []

        class MonitorExited(RuntimeError):
            pass

        def fail_after_sigpipe(signum, handler):
            signal_calls.append((signum, handler))
            raise RuntimeError("injected early monitor failure")

        def capture_kill(
            parent_pid,
            verifier,
            event_descriptor,
            event_factory,
            activity_entry,
        ):
            observed["parent_pid"] = parent_pid
            observed["verifier"] = verifier()
            observed["event_descriptor"] = event_descriptor
            observed["event"] = event_factory()
            observed["activity_entry"] = activity_entry
            return True

        try:
            self.namespace["kill_parent_if"] = capture_kill
            with (
                mock.patch.object(signal, "signal", side_effect=fail_after_sigpipe),
                mock.patch.object(os, "_exit", side_effect=MonitorExited),
                self.assertRaises(MonitorExited),
            ):
                monitor(
                    DAEMON_PID,
                    (),
                    "/unused-state",
                    ("/unused-pulse", 20, (1, 2), (0, 0)),
                    ("/unused-lease", 21, (1, 3), (0, 0)),
                    22,
                    None,
                    RUN_ID,
                    object(),
                    ("/unused-activity", (1, 4)),
                    100.0,
                    1.0,
                    120.0,
                    45.0,
                    225.0,
                )
        finally:
            self.namespace["kill_parent_if"] = original_kill_parent_if

        self.assertEqual(signal_calls, [(signal.SIGPIPE, signal.SIG_IGN)])
        self.assertEqual(observed["parent_pid"], DAEMON_PID)
        self.assertTrue(observed["verifier"])
        self.assertEqual(observed["event_descriptor"], 22)
        self.assertEqual(observed["activity_entry"], ("/unused-activity", (1, 4)))
        self.assertEqual(observed["event"]["cause"], "monitor-internal-error")
        self.assertEqual(observed["event"]["phase"], "startup")
        self.assertEqual(observed["event"]["method"], "none")
        self.assertIsNone(observed["event"]["tool"])

    def test_kill_is_unconditional_across_every_diagnostic_failure(self):
        kill_parent_if = self.namespace["kill_parent_if"]
        original_writer = self.namespace["write_watchdog_event"]
        original_unlink = self.namespace["safe_unlink_activity"]

        class MonitorExited(RuntimeError):
            pass

        def writer_raises(_descriptor, _event):
            raise RuntimeError("injected diagnostic failure")

        cases = (
            (lambda _descriptor, _event: True, lambda: valid_event()),
            (lambda _descriptor, _event: False, lambda: valid_event()),
            (writer_raises, lambda: valid_event()),
            (
                lambda _descriptor, _event: True,
                lambda: (_ for _ in ()).throw(ValueError("encoding failure")),
            ),
        )
        try:
            self.namespace["safe_unlink_activity"] = lambda *_arguments: True
            for writer, factory in cases:
                self.namespace["write_watchdog_event"] = writer
                with (
                    self.subTest(writer=writer),
                    mock.patch.object(os, "getppid", return_value=4242),
                    mock.patch.object(os, "kill") as kill,
                    mock.patch.object(os, "_exit", side_effect=MonitorExited),
                    self.assertRaises(MonitorExited),
                ):
                    kill_parent_if(
                        4242,
                        lambda: True,
                        11,
                        factory,
                        ("/unused", (1, 2)),
                    )
                kill.assert_called_once_with(4242, signal.SIGKILL)
        finally:
            self.namespace["write_watchdog_event"] = original_writer
            self.namespace["safe_unlink_activity"] = original_unlink

    def test_kill_orders_socket_unlink_event_write_and_sigkill(self):
        kill_parent_if = self.namespace["kill_parent_if"]
        original_writer = self.namespace["write_watchdog_event"]
        original_unlink = self.namespace["safe_unlink_activity"]
        calls = []

        class MonitorExited(RuntimeError):
            pass

        try:
            self.namespace["safe_unlink_activity"] = lambda *_arguments: (
                calls.append("unlink") or True
            )
            self.namespace["write_watchdog_event"] = lambda _descriptor, _event: (
                calls.append("write") or True
            )

            def record_kill(_pid, _signum):
                calls.append("kill")

            with (
                mock.patch.object(os, "getppid", return_value=DAEMON_PID),
                mock.patch.object(os, "kill", side_effect=record_kill),
                mock.patch.object(os, "_exit", side_effect=MonitorExited),
                self.assertRaises(MonitorExited),
            ):
                kill_parent_if(
                    DAEMON_PID,
                    lambda: True,
                    11,
                    lambda: valid_event(),
                    ("/unused", (1, 2)),
                )
        finally:
            self.namespace["write_watchdog_event"] = original_writer
            self.namespace["safe_unlink_activity"] = original_unlink

        self.assertEqual(calls, ["unlink", "write", "kill"])


class WatchdogTransportTests(WatchdogTestCase):
    def test_capabilities_accept_only_absent_or_complete_supervised_matrix(self):
        configure = self.namespace["configure_watchdog_capabilities"]
        keys = (
            "ANVIL_EMACS_WATCHDOG_SUPERVISED",
            "ANVIL_EMACS_WATCHDOG_EVENT_FD",
            "ANVIL_EMACS_WATCHDOG_RUN_ID",
        )
        capabilities = configure({})
        try:
            self.assertFalse(capabilities["supervised"])
            self.assertRegex(capabilities["run_id"], r"^[0-9a-f]{32}$")
            self.assertGreater(capabilities["event_fd"], 9)
            self.assertIsNotNone(capabilities["discard_fd"])
        finally:
            os.close(capabilities["event_fd"])
            os.close(capabilities["discard_fd"])

        read_descriptor, original_write = os.pipe()
        write_descriptor = fcntl.fcntl(original_write, fcntl.F_DUPFD, 10)
        os.close(original_write)
        os.set_blocking(read_descriptor, False)
        os.set_blocking(write_descriptor, False)
        environment = {
            keys[0]: "1",
            keys[1]: str(write_descriptor),
            keys[2]: RUN_ID,
        }
        try:
            capabilities = configure(environment)
            self.assertTrue(capabilities["supervised"])
            self.assertEqual(capabilities["event_fd"], write_descriptor)
            self.assertIsNone(capabilities["discard_fd"])
            self.assertNotIn(keys[0], environment)
            self.assertNotIn(keys[1], environment)
            self.assertEqual(environment[keys[2]], RUN_ID)
        finally:
            os.close(read_descriptor)
            os.close(write_descriptor)

        values = ("1", "10", RUN_ID)
        for mask in range(1, 7):
            partial = {
                key: value
                for index, (key, value) in enumerate(zip(keys, values, strict=True))
                if mask & (1 << index)
            }
            with (
                self.subTest(partial=partial),
                contextlib.redirect_stderr(io.StringIO()),
                self.assertRaises(SystemExit),
            ):
                configure(partial)
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            configure({keys[0]: "0", keys[1]: "10", keys[2]: RUN_ID})

    def test_supervised_descriptor_must_be_high_nonblocking_write_pipe(self):
        configure = self.namespace["configure_watchdog_capabilities"]
        original_read, original_write = os.pipe()
        read_descriptor = fcntl.fcntl(original_read, fcntl.F_DUPFD, 10)
        write_descriptor = fcntl.fcntl(original_write, fcntl.F_DUPFD, 10)
        os.close(original_read)
        os.close(original_write)
        try:
            os.set_blocking(read_descriptor, False)
            cases = (
                (read_descriptor, "read end"),
                (write_descriptor, "blocking"),
                (1, "low descriptor"),
            )
            for descriptor, label in cases:
                environment = {
                    "ANVIL_EMACS_WATCHDOG_SUPERVISED": "1",
                    "ANVIL_EMACS_WATCHDOG_EVENT_FD": str(descriptor),
                    "ANVIL_EMACS_WATCHDOG_RUN_ID": RUN_ID,
                }
                with (
                    self.subTest(label=label),
                    contextlib.redirect_stderr(io.StringIO()),
                    self.assertRaises(SystemExit),
                ):
                    configure(environment)
        finally:
            os.close(read_descriptor)
            os.close(write_descriptor)

    def test_activity_transport_handles_partial_and_coalesced_frames(self):
        prepare = self.namespace["prepare_activity_listener"]
        accept = self.namespace["accept_activity_connection"]
        drain = self.namespace["drain_activity_connection"]
        with tempfile.TemporaryDirectory(prefix="a-", dir="/tmp") as raw:
            runtime = Path(raw)
            runtime.chmod(0o700)
            listener, entry = prepare(str(runtime))
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            connection = None
            try:
                client.connect(entry[0])
                connection = accept(listener, entry)
                self.assertIsNotNone(connection)
                self.assertFalse(Path(entry[0]).exists())
                first = valid_activity(sequence=1, phase="parse", tool=None)
                second = valid_activity(sequence=2, phase="dispatch", tool=None)
                encoded_first = (
                    json.dumps(first, separators=(",", ":")) + "\n"
                ).encode()
                encoded_second = (
                    json.dumps(second, separators=(",", ":")) + "\n"
                ).encode()
                midpoint = len(encoded_first) // 2
                client.sendall(encoded_first[:midpoint])
                connection, pending, activity, sequence = drain(
                    connection, b"", RUN_ID, DAEMON_PID, 0, None
                )
                self.assertEqual(pending, encoded_first[:midpoint])
                self.assertIsNone(activity)
                client.sendall(encoded_first[midpoint:] + encoded_second)
                connection, pending, activity, sequence = drain(
                    connection, pending, RUN_ID, DAEMON_PID, sequence, activity
                )
                self.assertEqual(pending, b"")
                self.assertEqual(activity, second)
                self.assertEqual(sequence, 2)
            finally:
                client.close()
                if connection is not None:
                    connection.close()
                listener.close()

    def test_activity_transport_closes_malformed_oversized_and_disappeared_peers(self):
        prepare = self.namespace["prepare_activity_listener"]
        accept = self.namespace["accept_activity_connection"]
        drain = self.namespace["drain_activity_connection"]
        for payload in (b"not-json\n", b"x" * 1025):
            with (
                self.subTest(payload_size=len(payload)),
                tempfile.TemporaryDirectory(prefix="a-", dir="/tmp") as raw,
            ):
                runtime = Path(raw)
                runtime.chmod(0o700)
                listener, entry = prepare(str(runtime))
                client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                connection = None
                try:
                    client.connect(entry[0])
                    connection = accept(listener, entry)
                    client.sendall(payload)
                    connection, pending, activity, sequence = drain(
                        connection, b"", RUN_ID, DAEMON_PID, 0, None
                    )
                    self.assertIsNone(connection)
                    self.assertEqual(pending, b"")
                    self.assertIsNone(activity)
                    self.assertEqual(sequence, 0)
                finally:
                    client.close()
                    if connection is not None:
                        connection.close()
                    listener.close()

    def test_activity_accept_is_nonblocking_and_delivers_only_original_connection(self):
        prepare = self.namespace["prepare_activity_listener"]
        accept = self.namespace["accept_activity_connection"]
        with tempfile.TemporaryDirectory(prefix="a-", dir="/tmp") as raw:
            runtime = Path(raw)
            runtime.chmod(0o700)
            listener, entry = prepare(str(runtime))
            started = time.monotonic()
            self.assertIsNone(accept(listener, entry))
            self.assertLess(time.monotonic() - started, 0.1)
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            replacement = None
            connection = None
            try:
                client.connect(entry[0])
                connection = accept(listener, entry)
                replacement, replacement_entry = prepare(str(runtime))
                client.sendall(b"original")
                self.assertEqual(connection.recv(8), b"original")
                self.assertTrue(Path(replacement_entry[0]).exists())
            finally:
                client.close()
                if connection is not None:
                    connection.close()
                listener.close()
                if replacement is not None:
                    replacement.close()

    def test_activity_drain_reads_at_most_4096_bytes_per_tick(self):
        drain = self.namespace["drain_activity_connection"]
        stream = b"".join(
            (
                json.dumps(
                    valid_activity(sequence=sequence, tool=None),
                    separators=(",", ":"),
                )
                + "\n"
            ).encode()
            for sequence in range(1, 40)
        )

        class BufferedConnection:
            def __init__(self, payload):
                self.payload = payload
                self.read_bytes = 0
                self.closed = False

            def recv(self, maximum):
                chunk = self.payload[:maximum]
                self.payload = self.payload[maximum:]
                self.read_bytes += len(chunk)
                return chunk

            def close(self):
                self.closed = True

        connection = BufferedConnection(stream)
        returned, pending, activity, sequence = drain(
            connection,
            b"",
            RUN_ID,
            DAEMON_PID,
            0,
            None,
        )
        self.assertIs(returned, connection)
        self.assertEqual(connection.read_bytes, 4096)
        self.assertFalse(connection.closed)
        self.assertLessEqual(len(pending), 1024)
        self.assertGreater(sequence, 0)
        self.assertEqual(activity["sequence"], sequence)


class WatchdogLifecycleTests(WatchdogTestCase):
    def run_launcher(
        self,
        root,
        stage_body,
        *,
        environment=None,
        pass_fds=(),
        timeout=30,
    ):
        runtime = root / "r"
        state = root / "s"
        runtime.mkdir(mode=0o700, exist_ok=True)
        state.mkdir(mode=0o700, exist_ok=True)
        stage = root / "stage.py"
        stage.write_text(f"#!{sys.executable}\n" + stage_body)
        stage.chmod(0o700)
        child_environment = os.environ.copy()
        child_environment.update(environment or {})
        return subprocess.run(
            [
                sys.executable,
                "-I",
                "-S",
                str(LAUNCHER),
                str(runtime),
                str(state),
                "75",
                str(stage),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=child_environment,
            pass_fds=pass_fds,
            timeout=timeout,
            check=False,
        )

    def test_shared_launch_delivers_root_capabilities_without_descriptor_leaks(self):
        with tempfile.TemporaryDirectory(prefix="w-", dir="/tmp") as raw:
            root = Path(raw)
            result = root / "result.json"
            stage_body = (
                "import json, os, stat, sys\n"
                "leaked = []\n"
                "for fd in range(3, 1024):\n"
                "    try: info = os.fstat(fd)\n"
                "    except OSError: continue\n"
                "    if stat.S_ISFIFO(info.st_mode) or stat.S_ISSOCK(info.st_mode): leaked.append(fd)\n"
                "payload = {\n"
                " 'socket': os.environ.get('ANVIL_EMACS_WATCHDOG_ACTIVITY_SOCKET'),\n"
                " 'run_id': os.environ.get('ANVIL_EMACS_WATCHDOG_RUN_ID'),\n"
                " 'marker': os.environ.get('ANVIL_EMACS_WATCHDOG_SUPERVISED'),\n"
                " 'event_fd': os.environ.get('ANVIL_EMACS_WATCHDOG_EVENT_FD'),\n"
                " 'leaked': leaked,\n"
                "}\n"
                "open(os.environ['ANVIL_TEST_RESULT_FILE'], 'w').write(json.dumps(payload))\n"
            )
            completed = self.run_launcher(
                root,
                stage_body,
                environment={"ANVIL_TEST_RESULT_FILE": str(result)},
            )
            self.assertEqual(completed.returncode, 0, completed.stderr.decode())
            payload = json.loads(result.read_text())
            self.assertEqual(
                payload["socket"],
                str(root / "r" / ".anvil-root-activity.sock"),
            )
            self.assertRegex(payload["run_id"], r"^[0-9a-f]{32}$")
            self.assertIsNone(payload["marker"])
            self.assertIsNone(payload["event_fd"])
            self.assertEqual(payload["leaked"], [])

    def test_silent_startup_emits_exact_atomic_cause_before_sigkill(self):
        with tempfile.TemporaryDirectory(prefix="w-", dir="/tmp") as raw:
            root = Path(raw)
            read_descriptor, original_write = os.pipe()
            write_descriptor = fcntl.fcntl(original_write, fcntl.F_DUPFD, 10)
            os.close(original_write)
            os.set_blocking(read_descriptor, False)
            os.set_blocking(write_descriptor, False)
            environment = {
                "ANVIL_EMACS_WATCHDOG_SUPERVISED": "1",
                "ANVIL_EMACS_WATCHDOG_EVENT_FD": str(write_descriptor),
                "ANVIL_EMACS_WATCHDOG_RUN_ID": RUN_ID,
                "ANVIL_EMACS_WATCHDOG_STARTUP_SECONDS": "0.16",
                "ANVIL_EMACS_WATCHDOG_NORMAL_SECONDS": "0.16",
                "ANVIL_EMACS_WATCHDOG_DISPATCH_SECONDS": "0.16",
                "ANVIL_EMACS_WATCHDOG_PULSE_SECONDS": "0.05",
                "ANVIL_SECRET_SENTINEL": "must-not-appear",
            }
            try:
                completed = self.run_launcher(
                    root,
                    "import time\ntime.sleep(5)\n",
                    environment=environment,
                    pass_fds=(write_descriptor,),
                    timeout=LIFECYCLE_OUTER_TIMEOUT_SECONDS,
                )
                os.close(write_descriptor)
                write_descriptor = None
                self.assertEqual(completed.returncode, -signal.SIGKILL)
                self.assertNotIn(b"must-not-appear", completed.stderr)
                readable, _, _ = select.select([read_descriptor], [], [], 1)
                self.assertEqual(readable, [read_descriptor])
                payload = os.read(read_descriptor, 513)
                self.assertLessEqual(len(payload), 512)
                self.assertNotIn(b"must-not-appear", payload)
                event = json.loads(payload)
                self.assertEqual(event["cause"], "startup-timeout")
                self.assertEqual(event["phase"], "startup")
                self.assertEqual(event["method"], "none")
                self.assertIsNone(event["tool"])
                self.assertEqual(event["run_id"], RUN_ID)
                self.assertLess(event["daemon_uptime_ms"], 2_000)
            finally:
                os.close(read_descriptor)
                if write_descriptor is not None:
                    os.close(write_descriptor)

    def test_silent_partial_malformed_and_disappeared_peers_do_not_delay_timeout(
        self,
    ):
        actions = {
            "silent": "pass",
            "partial": "client.sendall(b'{\\\"schema_version\\\":1')",
            "malformed": "client.sendall(b'not-json\\n')",
            "wrong-type": (
                "client.sendall((json.dumps({"
                "'schema_version': 1, "
                "'run_id': os.environ['ANVIL_EMACS_WATCHDOG_RUN_ID'], "
                "'daemon_pid': os.getpid(), 'sequence': 1, "
                "'phase': [], 'method': 'none', 'tool': None, "
                "'phase_started_unix_ms': 1, 'observed_at_unix_ms': 1"
                "}) + '\\n').encode())"
            ),
            "disappeared": "client.close()",
        }
        for label, action in actions.items():
            with (
                self.subTest(label=label),
                tempfile.TemporaryDirectory(prefix="w-", dir="/tmp") as raw,
            ):
                root = Path(raw)
                read_descriptor, original_write = os.pipe()
                write_descriptor = fcntl.fcntl(original_write, fcntl.F_DUPFD, 10)
                os.close(original_write)
                os.set_blocking(read_descriptor, False)
                os.set_blocking(write_descriptor, False)
                environment = {
                    "ANVIL_EMACS_WATCHDOG_SUPERVISED": "1",
                    "ANVIL_EMACS_WATCHDOG_EVENT_FD": str(write_descriptor),
                    "ANVIL_EMACS_WATCHDOG_RUN_ID": RUN_ID,
                    "ANVIL_EMACS_WATCHDOG_STARTUP_SECONDS": "0.30",
                    "ANVIL_EMACS_WATCHDOG_NORMAL_SECONDS": "0.30",
                    "ANVIL_EMACS_WATCHDOG_DISPATCH_SECONDS": "0.30",
                    "ANVIL_EMACS_WATCHDOG_PULSE_SECONDS": "0.05",
                }
                stage_body = (
                    "import json, os, socket, time\n"
                    "client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n"
                    "client.connect(os.environ['ANVIL_EMACS_WATCHDOG_ACTIVITY_SOCKET'])\n"
                    f"{action}\n"
                    "time.sleep(5)\n"
                )
                try:
                    completed = self.run_launcher(
                        root,
                        stage_body,
                        environment=environment,
                        pass_fds=(write_descriptor,),
                        timeout=LIFECYCLE_OUTER_TIMEOUT_SECONDS,
                    )
                    os.close(write_descriptor)
                    write_descriptor = None
                    self.assertEqual(completed.returncode, -signal.SIGKILL)
                    readable, _, _ = select.select([read_descriptor], [], [], 1)
                    self.assertEqual(readable, [read_descriptor])
                    event = json.loads(os.read(read_descriptor, 513))
                    self.assertEqual(event["cause"], "startup-timeout")
                    self.assertEqual(event["phase"], "startup")
                    self.assertLess(event["daemon_uptime_ms"], 2_000)
                finally:
                    os.close(read_descriptor)
                    if write_descriptor is not None:
                        os.close(write_descriptor)

    def test_external_exit_before_accept_is_reclaimed_on_next_launch(self):
        with tempfile.TemporaryDirectory(prefix="w-", dir="/tmp") as raw:
            root = Path(raw)
            socket_path = root / "r" / ".anvil-root-activity.sock"
            first = self.run_launcher(root, "raise SystemExit(42)\n")
            self.assertEqual(first.returncode, 42, first.stderr.decode())
            first_info = socket_path.lstat()
            self.assertTrue(stat.S_ISSOCK(first_info.st_mode))
            self.assertEqual(stat.S_IMODE(first_info.st_mode), 0o600)

            second = self.run_launcher(root, "pass\n")
            self.assertEqual(second.returncode, 0, second.stderr.decode())
            second_info = socket_path.lstat()
            self.assertTrue(stat.S_ISSOCK(second_info.st_mode))
            self.assertNotEqual(
                (first_info.st_dev, first_info.st_ino),
                (second_info.st_dev, second_info.st_ino),
            )

    def test_descriptor_cleanup_is_bounded(self):
        assert_descriptor_cleanup(self.namespace)

    def test_scheduler_math_preserves_existing_timeout_policy(self):
        assert_scheduler_math(self.namespace)

    def test_monitor_files_use_fresh_inodes_and_coherent_lease_modes(self):
        assert_fresh_inodes_and_lease(self.namespace)

    def test_volatile_wal_replacement_is_benign(self):
        assert_volatile_wal_is_benign(self.namespace)

    def test_stale_socket_reclaims_only_safe_owned_entry(self):
        prepare = self.namespace["prepare_activity_listener"]
        unlink = self.namespace["safe_unlink_activity"]
        with tempfile.TemporaryDirectory(prefix="a-", dir="/tmp") as raw:
            runtime = Path(raw)
            runtime.chmod(0o700)
            first, entry = prepare(str(runtime))
            first.close()
            second, second_entry = prepare(str(runtime))
            try:
                self.assertNotEqual(entry[1], second_entry[1])
                self.assertTrue(unlink(second_entry[0], second_entry[1]))
                self.assertFalse(Path(second_entry[0]).exists())
            finally:
                second.close()

            hostile = runtime / ".anvil-root-activity.sock"
            hostile.write_text("preserve")
            hostile.chmod(0o600)
            with (
                contextlib.redirect_stderr(io.StringIO()),
                self.assertRaises(SystemExit),
            ):
                prepare(str(runtime))
            self.assertEqual(hostile.read_text(), "preserve")

    def test_stale_socket_rejects_symlink_mode_link_and_owner_changes(self):
        prepare = self.namespace["prepare_activity_listener"]
        identify = self.namespace["activity_entry_identity"]

        with tempfile.TemporaryDirectory(prefix="a-", dir="/tmp") as raw:
            runtime = Path(raw)
            runtime.chmod(0o700)
            path = runtime / ".anvil-root-activity.sock"

            target = runtime / "target"
            target.write_text("preserve")
            path.symlink_to(target.name)
            with (
                contextlib.redirect_stderr(io.StringIO()),
                self.assertRaises(SystemExit),
            ):
                prepare(str(runtime))
            self.assertTrue(path.is_symlink())
            self.assertEqual(target.read_text(), "preserve")
            path.unlink()

            permissive = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                permissive.bind(str(path))
                path.chmod(0o640)
                with (
                    contextlib.redirect_stderr(io.StringIO()),
                    self.assertRaises(SystemExit),
                ):
                    prepare(str(runtime))
                self.assertTrue(stat.S_ISSOCK(path.lstat().st_mode))
                self.assertEqual(stat.S_IMODE(path.lstat().st_mode), 0o640)
            finally:
                permissive.close()
                path.unlink(missing_ok=True)

            linked = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            alias = runtime / "linked-alias"
            try:
                linked.bind(str(path))
                path.chmod(0o600)
                os.link(path, alias)
                with (
                    contextlib.redirect_stderr(io.StringIO()),
                    self.assertRaises(SystemExit),
                ):
                    prepare(str(runtime))
                self.assertEqual(path.lstat().st_nlink, 2)
                self.assertTrue(alias.exists())
            finally:
                linked.close()
                path.unlink(missing_ok=True)
                alias.unlink(missing_ok=True)

            owned = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            directory_fd = None
            try:
                owned.bind(str(path))
                path.chmod(0o600)
                directory_fd = os.open(runtime, os.O_RDONLY | os.O_DIRECTORY)
                with (
                    mock.patch.object(os, "getuid", return_value=os.getuid() + 1),
                    self.assertRaises(OSError),
                ):
                    identify(directory_fd, path.name)
                self.assertTrue(stat.S_ISSOCK(path.lstat().st_mode))
            finally:
                if directory_fd is not None:
                    os.close(directory_fd)
                owned.close()
                path.unlink(missing_ok=True)

    def test_activity_path_checks_the_new_suffix_at_platform_boundary(self):
        validate = self.namespace["validate_activity_socket_path"]
        limit = self.namespace["UNIX_SOCKET_PATH_BYTES"]
        suffix = "/.anvil-root-activity.sock"
        fitting = "/" + ("x" * (limit - len(suffix) - 1))
        self.assertEqual(validate(fitting), fitting + suffix)
        old_suffix_only = "/" + ("x" * (limit - len("/emacs/server") - 1))
        self.assertLessEqual(len((old_suffix_only + "/emacs/server").encode()), limit)
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            validate(old_suffix_only)


if __name__ == "__main__":
    unittest.main(verbosity=2)
