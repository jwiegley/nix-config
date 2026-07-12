#!/usr/bin/env python3
"""Deterministic tests for per-Codex-process Anvil daemon supervision."""

from __future__ import annotations

import contextlib
import ctypes
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import socket
import stat
from types import SimpleNamespace
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock


MODULE_PATH = Path(
    os.environ.get(
        "ANVIL_AGENT_SUPERVISOR",
        Path(__file__).with_name("agent-supervisor.py"),
    )
)
SPEC = importlib.util.spec_from_file_location("anvil_agent_supervisor", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load supervisor module: {MODULE_PATH}")
SUPERVISOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SUPERVISOR)


def eventually(predicate, timeout: float = 10.0):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            result = predicate()
        except (FileNotFoundError, json.JSONDecodeError) as error:
            last_error = error
        else:
            if result:
                return result
        time.sleep(0.05)
    if last_error is not None:
        raise AssertionError(f"condition did not become true: {last_error}")
    raise AssertionError("condition did not become true")


def fake_start_daemon(_args):
    return subprocess.Popen(
        [sys.executable, "-c", "import time; time.sleep(60)"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        close_fds=True,
    )


def reap_child(pid: int, timeout: float = 3.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            waited, _status = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            return True
        if waited == pid:
            return True
        time.sleep(0.02)
    return False


def wait_child_status(pid: int, timeout: float = 3.0) -> int:
    """Reap PID within TIMEOUT and return its wait status."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            waited, status = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError as error:
            raise AssertionError(f"child {pid} was already reaped") from error
        if waited == pid:
            return status
        time.sleep(0.02)
    raise AssertionError(f"child {pid} did not exit within {timeout}s")


class AgentSupervisorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.root.chmod(0o700)
        self.runtime_root = self.root / "runtime"
        self.state_root = self.root / "state"
        self.runtime_root.mkdir(mode=0o700)
        self.state_root.mkdir(mode=0o700)
        self.runtime_root.chmod(0o700)
        self.state_root.chmod(0o700)
        self.supervisor_pids: set[int] = set()
        self.daemon_pids: set[int] = set()
        self.owner_processes: list[subprocess.Popen[bytes]] = []
        self.original_start_daemon = SUPERVISOR.start_daemon

    def tearDown(self):
        SUPERVISOR.start_daemon = self.original_start_daemon
        for pid in self.supervisor_pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        for pid in self.daemon_pids:
            try:
                os.killpg(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        unreaped = []
        for pid in self.supervisor_pids:
            if reap_child(pid):
                continue
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                continue
            if not reap_child(pid):
                unreaped.append(pid)
        for process in self.owner_processes:
            if process.poll() is None:
                process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
        self.temporary.cleanup()
        if unreaped:
            self.fail(f"supervisor children did not exit: {unreaped}")

    def start_owner(self) -> tuple[int, str]:
        process = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(60)"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            close_fds=True,
        )
        self.owner_processes.append(process)
        identity = eventually(
            lambda: SUPERVISOR.process_start_identity(process.pid)
        )
        return process.pid, identity

    def prepare(
        self,
        *,
        owner_pid: int | None = None,
        owner_start_identity: str | None = None,
        host: str = "hera",
    ):
        if owner_pid is None:
            owner_pid = os.getpid()
        if owner_start_identity is None:
            owner_start_identity = SUPERVISOR.process_start_identity(owner_pid)
        if owner_start_identity is None:
            raise AssertionError("test owner has no process start identity")
        agent_key = SUPERVISOR.derive_agent_key(
            owner_pid,
            owner_start_identity,
        )
        runtime_dir, state_dir, leases_dir = (
            SUPERVISOR.prepare_instance_directories(
                self.runtime_root,
                self.state_root,
                host,
                agent_key,
            )
        )
        return SimpleNamespace(
            agent_key=agent_key,
            daemon="unused",
            grace_seconds=0.5,
            host=host,
            leases_dir=leases_dir,
            owner_pid=owner_pid,
            owner_start_identity=owner_start_identity,
            parent_guard="unused",
            python=sys.executable,
            runtime_dir=runtime_dir,
            state_dir=state_dir,
        )

    @staticmethod
    def read_status(args):
        return json.loads((args.runtime_dir / SUPERVISOR.STATUS_NAME).read_text())

    def remember_status(self, status):
        self.supervisor_pids.add(status["supervisor_pid"])
        if status["daemon_pid"] is not None:
            self.daemon_pids.add(status["daemon_pid"])
        return status

    @staticmethod
    def register(args, server_id):
        return SUPERVISOR.register_lease(
            args.leases_dir,
            server_id,
            args.agent_key,
            args.owner_pid,
            args.owner_start_identity,
        )

    @staticmethod
    def live(args):
        return SUPERVISOR.live_leases(
            args.leases_dir,
            args.agent_key,
            args.owner_pid,
            args.owner_start_identity,
        )

    @staticmethod
    def parser_arguments(*extra: str) -> list[str]:
        return [
            "--server-id",
            "anvil",
            "--host",
            "hera",
            "--runtime-root",
            "/tmp/runtime",
            "--state-root",
            "/tmp/state",
            "--daemon",
            "/daemon",
            "--stdio",
            "/stdio",
            "--emacsclient",
            "/emacsclient",
            "--python",
            sys.executable,
            "--parent-guard",
            "/parent-guard",
            *extra,
        ]

    def test_linux_identity_includes_boot_id_and_start_ticks(self):
        boot_id = "12345678-1234-5678-9ABC-DEF012345678"
        stat_fields = ["S", *("0" for _ in range(18)), "987654"]
        stat_record = f"42 (codex worker) {' '.join(stat_fields)}"
        old_boot_id = SUPERVISOR._LINUX_BOOT_ID
        old_initialized = SUPERVISOR._LINUX_BOOT_ID_INITIALIZED
        SUPERVISOR._LINUX_BOOT_ID = None
        SUPERVISOR._LINUX_BOOT_ID_INITIALIZED = False
        try:
            with mock.patch.object(
                SUPERVISOR.Path,
                "read_text",
                side_effect=[boot_id + "\n", stat_record, stat_record],
            ) as read_text:
                expected = (
                    "linux:12345678-1234-5678-9abc-def012345678:987654"
                )
                self.assertEqual(SUPERVISOR.linux_process_start(42), expected)
                self.assertEqual(SUPERVISOR.linux_process_start(42), expected)
                self.assertEqual(read_text.call_count, 3)
        finally:
            SUPERVISOR._LINUX_BOOT_ID = old_boot_id
            SUPERVISOR._LINUX_BOOT_ID_INITIALIZED = old_initialized

    def test_linux_and_darwin_zombies_have_no_live_identity(self):
        old_boot_id = SUPERVISOR._LINUX_BOOT_ID
        old_initialized = SUPERVISOR._LINUX_BOOT_ID_INITIALIZED
        SUPERVISOR._LINUX_BOOT_ID = "12345678-1234-5678-9abc-def012345678"
        SUPERVISOR._LINUX_BOOT_ID_INITIALIZED = True
        try:
            zombie_fields = ["Z", *("0" for _ in range(18)), "987654"]
            zombie_record = f"42 (zombie worker) {' '.join(zombie_fields)}"
            with mock.patch.object(
                SUPERVISOR.Path,
                "read_text",
                return_value=zombie_record,
            ):
                self.assertIsNone(SUPERVISOR.linux_process_start(42))
        finally:
            SUPERVISOR._LINUX_BOOT_ID = old_boot_id
            SUPERVISOR._LINUX_BOOT_ID_INITIALIZED = old_initialized

        def zombie_proc_pidinfo(pid, _flavor, _arg, buffer, size):
            info = ctypes.cast(
                buffer,
                ctypes.POINTER(SUPERVISOR.DarwinBSDInfo),
            ).contents
            info.pbi_pid = pid
            info.pbi_status = 5
            info.pbi_start_tvsec = 100
            info.pbi_start_tvusec = 200
            return size

        with mock.patch.object(
            SUPERVISOR,
            "darwin_proc_pidinfo",
            return_value=zombie_proc_pidinfo,
        ):
            self.assertIsNone(SUPERVISOR.darwin_process_start(42))

    def test_exited_unreaped_owner_is_not_live(self):
        process = subprocess.Popen(
            [
                sys.executable,
                "-c",
                "import os; os.write(1, b'R')",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            close_fds=True,
        )
        try:
            if process.stdout is None or process.stdout.read(1) != b"R":
                self.fail("zombie fixture did not start")
            eventually(
                lambda: SUPERVISOR.process_start_identity(process.pid) is None
            )
        finally:
            if process.stdout is not None:
                process.stdout.close()
            process.wait(timeout=3)

    def test_owner_acquisition_rejects_reparent_and_identity_races(self):
        stable = "linux:12345678-1234-5678-9abc-def012345678:10"
        with (
            mock.patch.object(
                SUPERVISOR,
                "owner_pipe_closed",
                return_value=False,
            ),
            mock.patch.object(SUPERVISOR.os, "getppid", side_effect=[42, 42, 42]),
            mock.patch.object(
                SUPERVISOR,
                "process_start_identity",
                side_effect=[stable, stable],
            ),
        ):
            self.assertEqual(SUPERVISOR.identify_owner(), (42, stable))

        with (
            mock.patch.object(
                SUPERVISOR,
                "owner_pipe_closed",
                return_value=False,
            ),
            mock.patch.object(SUPERVISOR.os, "getppid", side_effect=[42, 43, 43]),
            mock.patch.object(
                SUPERVISOR,
                "process_start_identity",
                side_effect=[stable, stable],
            ),
        ):
            with self.assertRaises(SUPERVISOR.ConfigurationError):
                SUPERVISOR.identify_owner()

        with (
            mock.patch.object(
                SUPERVISOR,
                "owner_pipe_closed",
                side_effect=[False, True],
            ) as pipe_closed,
            mock.patch.object(SUPERVISOR.os, "getppid", side_effect=[42, 42, 42]),
            mock.patch.object(
                SUPERVISOR,
                "process_start_identity",
                side_effect=[stable, stable],
            ),
        ):
            with self.assertRaises(SUPERVISOR.ConfigurationError):
                SUPERVISOR.identify_owner()
            self.assertEqual(pipe_closed.call_count, 2)

        with (
            mock.patch.object(
                SUPERVISOR,
                "owner_pipe_closed",
                return_value=False,
            ),
            mock.patch.object(SUPERVISOR.os, "getppid", side_effect=[42, 42, 42]),
            mock.patch.object(
                SUPERVISOR,
                "process_start_identity",
                side_effect=[stable, stable + "-reused"],
            ),
        ):
            with self.assertRaises(SUPERVISOR.ConfigurationError):
                SUPERVISOR.identify_owner()

    def test_closed_owner_pipe_rejects_presample_reparenting(self):
        read_fd, write_fd = os.pipe()
        try:
            os.close(write_fd)
            with mock.patch.object(SUPERVISOR.os, "getppid") as getppid:
                with self.assertRaises(SUPERVISOR.ConfigurationError):
                    SUPERVISOR.identify_owner(read_fd)
                getppid.assert_not_called()
        finally:
            os.close(read_fd)

        read_fd, write_fd = os.pipe()
        try:
            os.write(write_fd, b"buffered MCP request")
            self.assertFalse(SUPERVISOR.owner_pipe_closed(read_fd))
            self.assertEqual(os.read(read_fd, 20), b"buffered MCP request")
        finally:
            os.close(read_fd)
            os.close(write_fd)

    def test_pid_generation_changes_agent_key_and_private_path(self):
        first_key = SUPERVISOR.derive_agent_key(4242, "linux:boot-a:100", 501)
        self.assertEqual(
            first_key,
            SUPERVISOR.derive_agent_key(4242, "linux:boot-a:100", 501),
        )
        second_key = SUPERVISOR.derive_agent_key(
            4242,
            "linux:boot-a:101",
            501,
        )
        self.assertNotEqual(first_key, second_key)
        first = SUPERVISOR.prepare_instance_directories(
            self.runtime_root,
            self.state_root,
            "hera",
            first_key,
        )[0]
        second = SUPERVISOR.prepare_instance_directories(
            self.runtime_root,
            self.state_root,
            "hera",
            second_key,
        )[0]
        self.assertNotEqual(first, second)
        self.assertEqual(first.parent.name, "agents")
        for invalid in ("short", f"{first_key}/../spoof", first_key.upper()):
            with self.subTest(invalid=invalid):
                with self.assertRaises(SUPERVISOR.ConfigurationError):
                    SUPERVISOR.validate_agent_key(invalid)

    def test_host_and_agent_paths_are_private_and_disjoint_from_home(self):
        nfs_home = self.root / "shared-nfs-home"
        nfs_home.mkdir(mode=0o700)
        old_home = os.environ.get("HOME")
        os.environ["HOME"] = str(nfs_home)
        try:
            one = self.prepare(host="andoria-t2")
            owner_pid, owner_identity = self.start_owner()
            two = self.prepare(
                owner_pid=owner_pid,
                owner_start_identity=owner_identity,
                host="gpu-server",
            )
        finally:
            if old_home is None:
                os.environ.pop("HOME", None)
            else:
                os.environ["HOME"] = old_home

        self.assertNotEqual(one.runtime_dir, two.runtime_dir)
        self.assertNotEqual(one.state_dir, two.state_dir)
        self.assertNotIn(str(nfs_home), str(one.runtime_dir))
        self.assertNotIn(str(nfs_home), str(two.state_dir))
        for path in (
            one.runtime_dir,
            one.state_dir,
            one.leases_dir,
            two.runtime_dir,
            two.state_dir,
            two.leases_dir,
        ):
            self.assertEqual(path.stat().st_mode & 0o777, 0o700)

    def test_lease_revalidates_bridge_and_owner_identities(self):
        args = self.prepare()
        lease, record = self.register(args, "anvil")
        self.assertEqual(self.live(args), [record])

        stale = dict(record)
        stale["bridge_start_identity"] = (
            f"{record['bridge_start_identity']}-reused"
        )
        lease.write_text(json.dumps(stale) + "\n")
        os.chmod(lease, 0o600)
        self.assertEqual(self.live(args), [])
        self.assertFalse(lease.exists())

        owner_pid, owner_identity = self.start_owner()
        owner_args = self.prepare(
            owner_pid=owner_pid,
            owner_start_identity=owner_identity,
        )
        owner_lease, owner_record = self.register(owner_args, "anvil")
        self.assertEqual(self.live(owner_args), [owner_record])
        owner_process = next(
            process
            for process in self.owner_processes
            if process.pid == owner_pid
        )
        owner_process.terminate()
        owner_process.wait(timeout=3)
        self.assertEqual(
            SUPERVISOR.process_start_identity(os.getpid()),
            owner_record["bridge_start_identity"],
            "the bridge must still be alive when owner validation fails",
        )
        self.assertEqual(self.live(owner_args), [])
        self.assertFalse(owner_lease.exists())

        target = args.leases_dir / "outside"
        target.write_text("not a lease")
        symlink = args.leases_dir / "lease-anvil-2-symlink.json"
        symlink.symlink_to(target)
        hardlink = args.leases_dir / "lease-anvil-2-hardlink.json"
        os.link(target, hardlink)
        self.assertEqual(self.live(args), [])
        self.assertFalse(symlink.exists())
        self.assertFalse(hardlink.exists())
        self.assertTrue(target.exists())

    def test_lease_mode_is_private_even_under_restrictive_umask(self):
        args = self.prepare()
        old_umask = os.umask(0o277)
        try:
            lease, record = self.register(args, "anvil")
        finally:
            os.umask(old_umask)
        self.assertEqual(stat.S_IMODE(lease.stat().st_mode), 0o600)
        self.assertEqual(self.live(args), [record])

    def test_rapid_daemon_failures_back_off_exponentially(self):
        args = self.prepare()
        lease, _record = self.register(args, "anvil")
        attempt_log = self.root / "daemon-attempts"
        attempt_log.touch(mode=0o600)
        attempt_log.chmod(0o600)

        def fail_immediately(_args):
            with attempt_log.open("a", encoding="ascii") as stream:
                stream.write(f"{time.monotonic()}\n")
            return subprocess.Popen(
                [sys.executable, "-c", "pass"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
                close_fds=True,
            )

        SUPERVISOR.start_daemon = fail_immediately
        with (
            mock.patch.object(SUPERVISOR, "POLL_SECONDS", 0.01),
            mock.patch.object(
                SUPERVISOR,
                "RESTART_BACKOFF_INITIAL_SECONDS",
                0.05,
            ),
            mock.patch.object(
                SUPERVISOR,
                "RESTART_BACKOFF_MAX_SECONDS",
                0.2,
            ),
            mock.patch.object(SUPERVISOR, "RESTART_STABLE_SECONDS", 1.0),
        ):
            self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(args))
            status = self.remember_status(eventually(lambda: self.read_status(args)))

            def attempts():
                if not attempt_log.exists():
                    return False
                values = [
                    float(line)
                    for line in attempt_log.read_text().splitlines()
                    if line
                ]
                return values if len(values) >= 4 else False

            timestamps = eventually(attempts, timeout=5)[:4]

        intervals = [
            later - earlier
            for earlier, later in zip(timestamps, timestamps[1:])
        ]
        self.assertGreaterEqual(intervals[0], 0.045)
        self.assertGreaterEqual(intervals[1], 0.09)
        self.assertGreaterEqual(intervals[2], 0.18)
        self.assertEqual(
            status["supervisor_pid"],
            self.read_status(args)["supervisor_pid"],
        )
        lease.unlink()

    def test_masked_dead_daemon_does_not_count_as_observed_stable(self):
        args = self.prepare()
        lease, _record = self.register(args, "anvil")
        starts = self.root / "masked-death-starts"
        transient_count = self.root / "masked-death-transients"
        recovered = self.root / "masked-death-recovered"
        post_recovery_backoffs = self.root / "masked-death-backoffs"
        for path, contents in (
            (starts, ""),
            (transient_count, "0\n"),
            (recovered, ""),
            (post_recovery_backoffs, ""),
        ):
            path.write_text(contents)
            path.chmod(0o600)

        def fail_immediately(_args):
            with starts.open("a", encoding="ascii") as stream:
                stream.write(f"{time.monotonic()}\n")
            return subprocess.Popen(
                [sys.executable, "-c", "pass"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
                close_fds=True,
            )

        original_live_leases = SUPERVISOR.live_leases

        def mask_second_death(*inner_args, **inner_kwargs):
            if len(starts.read_text().splitlines()) >= 2:
                failures = int(transient_count.read_text())
                if failures < 5:
                    transient_count.write_text(f"{failures + 1}\n")
                    raise OSError(SUPERVISOR.errno.EIO, "injected EIO")
                if not recovered.read_text():
                    recovered.write_text("recovered\n")
            return original_live_leases(*inner_args, **inner_kwargs)

        original_backoff = SUPERVISOR.restart_backoff_seconds

        def record_post_recovery_backoff(failures):
            if recovered.read_text():
                with post_recovery_backoffs.open("a", encoding="ascii") as stream:
                    stream.write(f"{failures}\n")
            return original_backoff(failures)

        SUPERVISOR.start_daemon = fail_immediately
        with (
            mock.patch.object(SUPERVISOR, "POLL_SECONDS", 0.005),
            mock.patch.object(
                SUPERVISOR,
                "RESTART_BACKOFF_INITIAL_SECONDS",
                0.02,
            ),
            mock.patch.object(
                SUPERVISOR,
                "RESTART_BACKOFF_MAX_SECONDS",
                0.04,
            ),
            mock.patch.object(SUPERVISOR, "RESTART_STABLE_SECONDS", 0.03),
            mock.patch.object(SUPERVISOR, "live_leases", mask_second_death),
            mock.patch.object(
                SUPERVISOR,
                "restart_backoff_seconds",
                record_post_recovery_backoff,
            ),
        ):
            self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(args))
            status = self.remember_status(eventually(lambda: self.read_status(args)))
            first_backoff = eventually(
                lambda: post_recovery_backoffs.read_text().splitlines()
            )[0]

        self.assertEqual(transient_count.read_text(), "5\n")
        self.assertEqual(first_backoff, "2")
        self.assertEqual(
            self.read_status(args)["supervisor_pid"],
            status["supervisor_pid"],
        )
        lease.unlink()

    def test_transient_status_failure_does_not_stop_supervisor(self):
        args = self.prepare()
        lease, _record = self.register(args, "anvil")
        failure_marker = self.root / "status-failed-once"
        original_write_status = SUPERVISOR.write_status

        def flaky_write_status(inner_args, record):
            if record["daemon_pid"] is not None and not failure_marker.exists():
                failure_marker.write_text("failed\n")
                raise OSError(SUPERVISOR.errno.ENOSPC, "injected ENOSPC")
            original_write_status(inner_args, record)

        SUPERVISOR.start_daemon = fake_start_daemon
        with (
            mock.patch.object(SUPERVISOR, "write_status", flaky_write_status),
            mock.patch.object(
                SUPERVISOR,
                "RESTART_BACKOFF_INITIAL_SECONDS",
                0.05,
            ),
        ):
            self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(args))
            status = self.remember_status(
                eventually(
                    lambda: (
                        (current := self.read_status(args))["daemon_pid"]
                        is not None
                        and current
                    )
                )
            )
        self.assertTrue(failure_marker.exists())
        time.sleep(0.2)
        current = self.read_status(args)
        self.assertEqual(current["supervisor_pid"], status["supervisor_pid"])
        self.assertEqual(current["daemon_pid"], status["daemon_pid"])
        self.assertIsNotNone(
            SUPERVISOR.process_start_identity(current["daemon_pid"])
        )
        lease.unlink()

    def test_repeated_transient_loop_failures_recover_without_restart(self):
        args = self.prepare()
        lease, _record = self.register(args, "anvil")
        trigger = self.root / "transient-trigger"
        counter = self.root / "transient-count"
        recovered = self.root / "transient-recovered"
        for path, contents in (
            (trigger, ""),
            (counter, "0\n"),
            (recovered, ""),
        ):
            path.write_text(contents)
            path.chmod(0o600)
        original_live_leases = SUPERVISOR.live_leases

        def repeatedly_flaky_live_leases(*inner_args, **inner_kwargs):
            if trigger.read_text() == "armed\n":
                failures = int(counter.read_text())
                if failures < 5:
                    counter.write_text(f"{failures + 1}\n")
                    raise OSError(SUPERVISOR.errno.EIO, "injected EIO")
                if not recovered.read_text():
                    recovered.write_text("recovered\n")
            return original_live_leases(*inner_args, **inner_kwargs)

        SUPERVISOR.start_daemon = fake_start_daemon
        with (
            mock.patch.object(
                SUPERVISOR,
                "live_leases",
                repeatedly_flaky_live_leases,
            ),
            mock.patch.object(SUPERVISOR, "POLL_SECONDS", 0.01),
            mock.patch.object(
                SUPERVISOR,
                "RESTART_BACKOFF_INITIAL_SECONDS",
                0.01,
            ),
            mock.patch.object(
                SUPERVISOR,
                "RESTART_BACKOFF_MAX_SECONDS",
                0.04,
            ),
        ):
            self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(args))
            status = self.remember_status(
                eventually(
                    lambda: (
                        (current := self.read_status(args))["daemon_pid"]
                        is not None
                        and current
                    )
                )
            )
            supervisor_identity = SUPERVISOR.process_start_identity(
                status["supervisor_pid"]
            )
            daemon_identity = SUPERVISOR.process_start_identity(
                status["daemon_pid"]
            )
            trigger.write_text("armed\n")
            eventually(lambda: recovered.read_text() == "recovered\n")
            current = self.read_status(args)

        self.assertEqual(counter.read_text(), "5\n")
        self.assertEqual(current["supervisor_pid"], status["supervisor_pid"])
        self.assertEqual(current["daemon_pid"], status["daemon_pid"])
        self.assertEqual(
            SUPERVISOR.process_start_identity(current["supervisor_pid"]),
            supervisor_identity,
        )
        self.assertEqual(
            SUPERVISOR.process_start_identity(current["daemon_pid"]),
            daemon_identity,
        )
        lease.unlink()

    def test_persistent_fatal_loop_failure_tears_down_but_retains_owner(self):
        owner_pid, owner_identity = self.start_owner()
        args = self.prepare(
            owner_pid=owner_pid,
            owner_start_identity=owner_identity,
        )
        self.register(args, "anvil")
        trigger = self.root / "fatal-enoent-trigger"
        trigger.write_text("idle\n")
        original_live_leases = SUPERVISOR.live_leases

        def fatal_live_leases(*inner_args, **inner_kwargs):
            if trigger.read_text() == "armed\n":
                raise OSError(SUPERVISOR.errno.ENOENT, "injected ENOENT")
            return original_live_leases(*inner_args, **inner_kwargs)

        SUPERVISOR.start_daemon = fake_start_daemon
        with (
            mock.patch.object(SUPERVISOR, "live_leases", fatal_live_leases),
            mock.patch.object(SUPERVISOR, "POLL_SECONDS", 0.01),
        ):
            self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(args))
            status = self.remember_status(
                eventually(
                    lambda: (
                        (current := self.read_status(args))["daemon_pid"]
                        is not None
                        and current
                    )
                )
            )
            trigger.write_text("armed\n")
            wait_status = wait_child_status(status["supervisor_pid"])

        self.supervisor_pids.remove(status["supervisor_pid"])
        self.assertEqual(os.waitstatus_to_exitcode(wait_status), SUPERVISOR.EXIT_SOFTWARE)
        eventually(
            lambda: SUPERVISOR.process_start_identity(status["daemon_pid"])
            is None
        )
        self.daemon_pids.remove(status["daemon_pid"])

        # Fatal teardown releases process resources but deliberately retains
        # the authenticated owner record.  Unlinking it here would recreate
        # the status-less orphan that owner-death pruning cannot classify.
        self.assertEqual(
            SUPERVISOR.read_status_owner(args.runtime_dir, args.agent_key),
            (owner_pid, owner_identity),
        )
        locked = SUPERVISOR.try_supervisor_lock(args.runtime_dir)
        self.assertIsNotNone(locked)
        lock_descriptor, lock_identity = locked
        try:
            SUPERVISOR.validate_supervisor_lock(
                lock_descriptor,
                args.runtime_dir / SUPERVISOR.LOCK_NAME,
                lock_identity,
            )
        finally:
            os.close(lock_descriptor)

        current = self.prepare()
        SUPERVISOR.prune_orphaned_state(
            current.runtime_dir.parent,
            current.state_dir.parent,
            current.agent_key,
        )
        self.assertTrue(args.runtime_dir.exists())
        self.assertTrue(args.state_dir.exists())

        owner_process = next(
            process for process in self.owner_processes if process.pid == owner_pid
        )
        owner_process.terminate()
        owner_process.wait(timeout=3)
        SUPERVISOR.prune_orphaned_state(
            current.runtime_dir.parent,
            current.state_dir.parent,
            current.agent_key,
        )
        self.assertFalse(args.runtime_dir.exists())
        self.assertFalse(args.state_dir.exists())

    def test_idle_status_is_cached_and_lifecycle_records_are_refreshed(self):
        args = self.prepare()
        record = SUPERVISOR.status_record(args, None, 0)
        with mock.patch.object(SUPERVISOR.os, "fsync") as fsync:
            SUPERVISOR.write_status(args, record)
        fsync.assert_not_called()

        lease, _record = self.register(args, "anvil")
        status_writes = self.root / "status-writes"
        status_writes.touch(mode=0o600)
        status_writes.chmod(0o600)
        original_write_status = SUPERVISOR.write_status

        def counted_write_status(inner_args, inner_record):
            with status_writes.open("a", encoding="ascii") as stream:
                stream.write("write\n")
            original_write_status(inner_args, inner_record)

        SUPERVISOR.start_daemon = fake_start_daemon
        with (
            mock.patch.object(SUPERVISOR, "POLL_SECONDS", 0.02),
            mock.patch.object(SUPERVISOR, "LIFECYCLE_REFRESH_SECONDS", 0.1),
            mock.patch.object(SUPERVISOR, "write_status", counted_write_status),
        ):
            self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(args))
            self.remember_status(
                eventually(
                    lambda: (
                        (current := self.read_status(args))["daemon_pid"]
                        is not None
                        and current
                    )
                )
            )
            status_path = args.runtime_dir / SUPERVISOR.STATUS_NAME
            lock_path = args.runtime_dir / SUPERVISOR.LOCK_NAME
            old_ns = 1_000_000_000
            os.utime(lock_path, ns=(old_ns, old_ns))
            os.utime(lease, ns=(old_ns, old_ns))
            os.utime(status_path, ns=(old_ns, old_ns))
            eventually(
                lambda: (
                    lock_path.stat().st_mtime_ns > old_ns
                    and lease.stat().st_mtime_ns > old_ns
                    and status_path.stat().st_mtime_ns > old_ns
                )
            )
            before = status_path.stat()
            time.sleep(0.25)
            after = status_path.stat()

        self.assertEqual((after.st_dev, after.st_ino), (before.st_dev, before.st_ino))
        self.assertEqual(
            status_writes.read_text().splitlines(),
            ["write", "write", "write"],
        )
        lease.unlink()

    def test_same_owner_server_bridges_converge_restart_and_cleanup(self):
        args = self.prepare()
        first, _ = self.register(args, "anvil")
        second, _ = self.register(args, "emacs-eval")
        SUPERVISOR.start_daemon = fake_start_daemon
        self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(args))
        self.assertFalse(SUPERVISOR.spawn_supervisor_if_absent(args))

        status = self.remember_status(
            eventually(
                lambda: (
                    (current := self.read_status(args))["lease_count"] == 2
                    and current["daemon_pid"] is not None
                    and current
                )
            )
        )
        self.assertEqual(status["lease_count"], 2)
        self.assertEqual(status["agent_key"], args.agent_key)
        self.assertEqual(status["owner_pid"], args.owner_pid)
        original_daemon = status["daemon_pid"]
        self.assertIsNotNone(original_daemon)

        first.unlink()
        surviving = self.remember_status(
            eventually(
                lambda: (
                    (current := self.read_status(args))["lease_count"] == 1
                    and current
                )
            )
        )
        self.assertEqual(surviving["daemon_pid"], original_daemon)

        os.killpg(original_daemon, signal.SIGKILL)
        restarted = self.remember_status(
            eventually(
                lambda: (
                    (current := self.read_status(args))["daemon_pid"]
                    not in (None, original_daemon)
                    and current
                )
            )
        )
        self.assertEqual(restarted["supervisor_pid"], status["supervisor_pid"])

        second.unlink()
        idle = self.remember_status(
            eventually(
                lambda: (
                    (current := self.read_status(args))["lease_count"] == 0
                    and current["daemon_pid"] is None
                    and current
                )
            )
        )
        self.assertEqual(idle["supervisor_pid"], status["supervisor_pid"])
        self.assertTrue(args.runtime_dir.exists())
        eventually(
            lambda: SUPERVISOR.process_start_identity(restarted["daemon_pid"])
            is None
        )

    def test_supervisor_detaches_cwd_and_preserves_exception_cause(self):
        args = self.prepare()
        child_record = self.root / "supervisor-cwd.json"

        def record_cwd(_args, lock_descriptor, _lock_identity):
            child_record.write_text(
                json.dumps({"cwd": os.getcwd(), "pid": os.getpid()})
            )
            os.close(lock_descriptor)

        with mock.patch.object(SUPERVISOR, "supervisor_loop", record_cwd):
            self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(args))
            recorded = eventually(
                lambda: json.loads(child_record.read_text())
                if child_record.exists()
                else False
            )
        os.waitpid(recorded["pid"], 0)
        self.assertEqual(recorded["cwd"], "/")

        cause = OSError(SUPERVISOR.errno.EIO, "injected failure")
        with mock.patch.object(SUPERVISOR.Path, "mkdir", side_effect=cause):
            with self.assertRaises(SUPERVISOR.ConfigurationError) as raised:
                SUPERVISOR.ensure_private_directory(self.root / "unavailable")
        self.assertIs(raised.exception.__cause__, cause)

    def test_distinct_owner_processes_get_distinct_instances(self):
        first_pid, first_identity = self.start_owner()
        second_pid, second_identity = self.start_owner()
        first_args = self.prepare(
            owner_pid=first_pid,
            owner_start_identity=first_identity,
        )
        second_args = self.prepare(
            owner_pid=second_pid,
            owner_start_identity=second_identity,
        )
        first_lease, _ = self.register(first_args, "anvil")
        second_lease, _ = self.register(second_args, "anvil")
        SUPERVISOR.start_daemon = fake_start_daemon
        self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(first_args))
        self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(second_args))
        first = self.remember_status(
            eventually(
                lambda: (
                    (current := self.read_status(first_args))["daemon_pid"]
                    is not None
                    and current
                )
            )
        )
        second = self.remember_status(
            eventually(
                lambda: (
                    (current := self.read_status(second_args))["daemon_pid"]
                    is not None
                    and current
                )
            )
        )
        self.assertNotEqual(first["supervisor_pid"], second["supervisor_pid"])
        self.assertNotEqual(first["daemon_pid"], second["daemon_pid"])
        self.assertNotEqual(first_args.runtime_dir, second_args.runtime_dir)
        first_lease.unlink()
        second_lease.unlink()
        eventually(
            lambda: self.read_status(first_args)["daemon_pid"] is None
            and self.read_status(first_args)["lease_count"] == 0
        )
        eventually(
            lambda: self.read_status(second_args)["daemon_pid"] is None
            and self.read_status(second_args)["lease_count"] == 0
        )
        for process in self.owner_processes[-2:]:
            process.terminate()
        eventually(lambda: not first_args.runtime_dir.exists())
        eventually(lambda: not first_args.state_dir.exists())
        eventually(lambda: not second_args.runtime_dir.exists())
        eventually(lambda: not second_args.state_dir.exists())

    def test_owner_death_cleans_trees_without_following_symlinks(self):
        owner_pid, owner_identity = self.start_owner()
        args = self.prepare(
            owner_pid=owner_pid,
            owner_start_identity=owner_identity,
        )
        lease, record = self.register(args, "anvil")
        outside = self.root / "outside-sentinel"
        outside.write_text("preserve me")
        (args.state_dir / "outside-link").symlink_to(outside)
        SUPERVISOR.start_daemon = fake_start_daemon
        self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(args))
        status = self.remember_status(
            eventually(
                lambda: (
                    (current := self.read_status(args))["daemon_pid"]
                    is not None
                    and current
                )
            )
        )
        self.assertIsNotNone(status["daemon_pid"])
        self.assertEqual(self.live(args), [record])

        owner_process = next(
            process
            for process in self.owner_processes
            if process.pid == owner_pid
        )
        owner_process.terminate()
        # Do not reap yet: zombie owners must already count as dead. The
        # registering bridge (this test process) deliberately remains live.
        eventually(lambda: not args.runtime_dir.exists())
        eventually(lambda: not args.state_dir.exists())
        self.assertTrue(outside.exists())
        self.assertEqual(outside.read_text(), "preserve me")
        self.assertFalse(lease.exists())
        self.assertIsNotNone(
            SUPERVISOR.process_start_identity(record["bridge_pid"])
        )
        eventually(
            lambda: SUPERVISOR.process_start_identity(status["daemon_pid"])
            is None
        )
        owner_process.wait(timeout=3)

    def test_initial_status_precedes_readiness_and_enables_orphan_pruning(
        self,
    ):
        owner_pid, owner_identity = self.start_owner()
        stale = self.prepare(
            owner_pid=owner_pid,
            owner_start_identity=owner_identity,
        )
        self.register(stale, "anvil")
        (stale.state_dir / "large-cache").write_text("stale\n")
        loop_entered = self.root / "initial-status-loop-entered"
        child_failed_once = self.root / "initial-status-child-failed-once"
        parent_pid = os.getpid()
        original_write_status = SUPERVISOR.write_status

        def transient_child_write(inner_args, record):
            if os.getpid() != parent_pid and not child_failed_once.exists():
                child_failed_once.write_text("failed\n")
                raise OSError(SUPERVISOR.errno.ENOSPC, "injected ENOSPC")
            original_write_status(inner_args, record)

        def stall_before_loop_status(
            _args,
            _lock_descriptor,
            _lock_identity,
        ):
            loop_entered.write_text("entered\n")
            while True:
                signal.pause()

        with (
            mock.patch.object(
                SUPERVISOR,
                "supervisor_loop",
                stall_before_loop_status,
            ),
            mock.patch.object(
                SUPERVISOR,
                "write_status",
                transient_child_write,
            ),
            mock.patch.object(
                SUPERVISOR,
                "RESTART_BACKOFF_INITIAL_SECONDS",
                0.01,
            ),
            mock.patch.object(
                SUPERVISOR,
                "RESTART_BACKOFF_MAX_SECONDS",
                0.01,
            ),
        ):
            self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(stale))
            eventually(loop_entered.exists)
            self.assertTrue(child_failed_once.exists())
            status = self.remember_status(self.read_status(stale))
            self.assertEqual(status["owner_pid"], owner_pid)
            self.assertEqual(status["owner_start_identity"], owner_identity)
            self.assertIsNone(status["daemon_pid"])
            self.assertEqual(status["lease_count"], 0)
            os.kill(status["supervisor_pid"], signal.SIGKILL)
            self.assertTrue(reap_child(status["supervisor_pid"]))
        self.supervisor_pids.remove(status["supervisor_pid"])

        current = self.prepare()
        SUPERVISOR.prune_orphaned_state(
            current.runtime_dir.parent,
            current.state_dir.parent,
            current.agent_key,
        )
        self.assertTrue(
            stale.runtime_dir.exists(),
            "a live owner must not be pruned",
        )
        self.assertTrue(
            stale.state_dir.exists(),
            "a live owner must not be pruned",
        )

        owner_process = next(
            process for process in self.owner_processes if process.pid == owner_pid
        )
        owner_process.terminate()
        owner_process.wait(timeout=3)
        SUPERVISOR.prune_orphaned_state(
            current.runtime_dir.parent,
            current.state_dir.parent,
            current.agent_key,
        )
        self.assertFalse(stale.runtime_dir.exists())
        self.assertFalse(stale.state_dir.exists())

    def test_child_status_failure_retains_owner_seed_for_pruning(self):
        owner_pid, owner_identity = self.start_owner()
        stale = self.prepare(
            owner_pid=owner_pid,
            owner_start_identity=owner_identity,
        )
        self.register(stale, "anvil")
        (stale.state_dir / "large-cache").write_text("stale\n")
        child_attempts = self.root / "initial-status-child-attempts"
        parent_pid = os.getpid()
        original_write_status = SUPERVISOR.write_status

        def fail_child_status(inner_args, record):
            if os.getpid() != parent_pid:
                with child_attempts.open("a", encoding="ascii") as stream:
                    stream.write("failed\n")
                raise OSError(SUPERVISOR.errno.ENOSPC, "injected ENOSPC")
            original_write_status(inner_args, record)

        with (
            mock.patch.object(
                SUPERVISOR,
                "write_status",
                fail_child_status,
            ),
            mock.patch.object(
                SUPERVISOR,
                "STARTUP_STATUS_RETRY_SECONDS",
                0.05,
            ),
            mock.patch.object(
                SUPERVISOR,
                "RESTART_BACKOFF_INITIAL_SECONDS",
                0.01,
            ),
            mock.patch.object(
                SUPERVISOR,
                "RESTART_BACKOFF_MAX_SECONDS",
                0.01,
            ),
        ):
            with self.assertRaisesRegex(
                TimeoutError,
                "agent supervisor did not become ready",
            ):
                SUPERVISOR.spawn_supervisor_if_absent(stale)

        self.assertGreaterEqual(len(child_attempts.read_text().splitlines()), 2)
        seed = self.read_status(stale)
        self.assertEqual(seed["owner_pid"], owner_pid)
        self.assertEqual(seed["owner_start_identity"], owner_identity)
        self.assertIsNone(seed["supervisor_pid"])
        self.assertIsNone(seed["supervisor_start_identity"])
        self.assertIsNone(seed["daemon_pid"])

        current = self.prepare()
        SUPERVISOR.prune_orphaned_state(
            current.runtime_dir.parent,
            current.state_dir.parent,
            current.agent_key,
        )
        self.assertTrue(stale.runtime_dir.exists(), "a live owner must not be pruned")
        self.assertTrue(stale.state_dir.exists(), "a live owner must not be pruned")

        owner_process = next(
            process for process in self.owner_processes if process.pid == owner_pid
        )
        owner_process.terminate()
        owner_process.wait(timeout=3)
        SUPERVISOR.prune_orphaned_state(
            current.runtime_dir.parent,
            current.state_dir.parent,
            current.agent_key,
        )
        self.assertFalse(stale.runtime_dir.exists())
        self.assertFalse(stale.state_dir.exists())

    def test_owner_seed_preserves_status_held_by_concurrent_supervisor(self):
        args = self.prepare()
        richer = SUPERVISOR.status_record(args, None, 7)
        locked = SUPERVISOR.try_supervisor_lock(args.runtime_dir)
        self.assertIsNotNone(locked)
        lock_descriptor, _lock_identity = locked
        try:
            SUPERVISOR.write_status(args, richer)
            before = (args.runtime_dir / SUPERVISOR.STATUS_NAME).stat()
            SUPERVISOR.publish_owner_seed_if_absent(args)
            after = (args.runtime_dir / SUPERVISOR.STATUS_NAME).stat()
        finally:
            os.close(lock_descriptor)

        self.assertEqual(self.read_status(args), richer)
        self.assertEqual((before.st_dev, before.st_ino), (after.st_dev, after.st_ino))

    def test_owner_seed_repairs_invalid_status_while_holding_lock(self):
        args = self.prepare()
        status_path = args.runtime_dir / SUPERVISOR.STATUS_NAME
        status_path.write_text("not json\n", encoding="utf-8")
        status_path.chmod(0o600)

        SUPERVISOR.publish_owner_seed_if_absent(args)

        self.assertEqual(
            SUPERVISOR.read_status_owner(args.runtime_dir, args.agent_key),
            (args.owner_pid, args.owner_start_identity),
        )
        status = self.read_status(args)
        self.assertIsNone(status["supervisor_pid"])
        self.assertIsNone(status["daemon_pid"])

    def test_owner_seed_rejects_mismatched_status_as_configuration_error(self):
        args = self.prepare()
        mismatched = SUPERVISOR.owner_seed_record(args)
        mismatched["owner_pid"] = args.owner_pid + 1
        mismatched["owner_start_identity"] = "injected-mismatched-generation"
        SUPERVISOR.write_status(args, mismatched)

        with self.assertRaises(SUPERVISOR.ConfigurationError):
            SUPERVISOR.publish_owner_seed_if_absent(args)

    def test_owner_seed_rejects_locked_mismatched_status_as_configuration_error(
        self,
    ):
        args = self.prepare()
        mismatched = SUPERVISOR.owner_seed_record(args)
        mismatched["owner_pid"] = args.owner_pid + 1
        mismatched["owner_start_identity"] = "injected-locked-generation"
        locked = SUPERVISOR.try_supervisor_lock(args.runtime_dir)
        self.assertIsNotNone(locked)
        lock_descriptor, _lock_identity = locked
        try:
            SUPERVISOR.write_status(args, mismatched)
            with self.assertRaises(SUPERVISOR.ConfigurationError):
                SUPERVISOR.publish_owner_seed_if_absent(args)
        finally:
            os.close(lock_descriptor)

    def test_bridge_seeds_owner_before_pruning_and_dead_owner_is_prunable(self):
        owner_pid, owner_identity = self.start_owner()
        bridge_args = SimpleNamespace(
            daemon="/daemon",
            emacsclient="/emacsclient",
            grace_seconds=0.5,
            host="hera",
            parent_guard="/parent-guard",
            python=sys.executable,
            ready_seconds=1.0,
            runtime_root=str(self.runtime_root),
            server_id="anvil",
            state_root=str(self.state_root),
            stdio="/stdio",
        )
        captured = {}

        class InjectedBridgeKill(Exception):
            pass

        def interrupt_at_prune(runtime_agents, state_agents, current_agent_key):
            runtime_dir = runtime_agents / current_agent_key
            captured["runtime_dir"] = runtime_dir
            captured["state_dir"] = state_agents / current_agent_key
            captured["owner"] = SUPERVISOR.read_status_owner(
                runtime_dir,
                current_agent_key,
            )
            raise InjectedBridgeKill

        with (
            mock.patch.object(
                SUPERVISOR,
                "identify_owner",
                return_value=(owner_pid, owner_identity),
            ),
            mock.patch.object(
                SUPERVISOR,
                "prune_orphaned_state",
                side_effect=interrupt_at_prune,
            ),
        ):
            with self.assertRaises(InjectedBridgeKill):
                SUPERVISOR.bridge_main(bridge_args)

        self.assertEqual(captured["owner"], (owner_pid, owner_identity))
        status = json.loads(
            (captured["runtime_dir"] / SUPERVISOR.STATUS_NAME).read_text()
        )
        self.assertIsNone(status["supervisor_pid"])
        self.assertIsNone(status["daemon_pid"])

        current = self.prepare()
        SUPERVISOR.prune_orphaned_state(
            current.runtime_dir.parent,
            current.state_dir.parent,
            current.agent_key,
        )
        self.assertTrue(captured["runtime_dir"].exists())
        self.assertTrue(captured["state_dir"].exists())

        owner_process = next(
            process for process in self.owner_processes if process.pid == owner_pid
        )
        owner_process.terminate()
        owner_process.wait(timeout=3)
        SUPERVISOR.prune_orphaned_state(
            current.runtime_dir.parent,
            current.state_dir.parent,
            current.agent_key,
        )
        self.assertFalse(captured["runtime_dir"].exists())
        self.assertFalse(captured["state_dir"].exists())

    def test_dead_owner_runtime_and_state_are_pruned_after_supervisor_kill(self):
        owner_pid, owner_identity = self.start_owner()
        stale = self.prepare(
            owner_pid=owner_pid,
            owner_start_identity=owner_identity,
        )
        self.register(stale, "anvil")
        (stale.state_dir / "large-cache").write_text("stale\n")
        SUPERVISOR.start_daemon = fake_start_daemon
        self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(stale))
        status = self.remember_status(
            eventually(
                lambda: (
                    (current := self.read_status(stale))["daemon_pid"]
                    is not None
                    and current
                )
            )
        )
        os.kill(status["supervisor_pid"], signal.SIGKILL)
        self.assertTrue(reap_child(status["supervisor_pid"]))
        self.supervisor_pids.remove(status["supervisor_pid"])
        os.killpg(status["daemon_pid"], signal.SIGKILL)
        eventually(
            lambda: SUPERVISOR.process_start_identity(status["daemon_pid"])
            is None
        )
        self.daemon_pids.remove(status["daemon_pid"])

        current = self.prepare()
        SUPERVISOR.prune_orphaned_state(
            current.runtime_dir.parent,
            current.state_dir.parent,
            current.agent_key,
        )
        self.assertTrue(
            stale.runtime_dir.exists(),
            "a live owner must not be pruned",
        )
        self.assertTrue(
            stale.state_dir.exists(),
            "a live owner must not be pruned",
        )

        owner_process = next(
            process for process in self.owner_processes if process.pid == owner_pid
        )
        owner_process.terminate()
        owner_process.wait(timeout=3)
        SUPERVISOR.prune_orphaned_state(
            current.runtime_dir.parent,
            current.state_dir.parent,
            current.agent_key,
        )
        self.assertFalse(stale.runtime_dir.exists())
        self.assertFalse(stale.state_dir.exists())

    def test_clean_supervisor_stop_retains_status_for_owner_death_prune(self):
        owner_pid, owner_identity = self.start_owner()
        stale = self.prepare(
            owner_pid=owner_pid,
            owner_start_identity=owner_identity,
        )
        self.register(stale, "anvil")
        (stale.state_dir / "large-cache").write_text("stale\n")
        SUPERVISOR.start_daemon = fake_start_daemon
        self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(stale))
        status = self.remember_status(
            eventually(
                lambda: (
                    (current := self.read_status(stale))["daemon_pid"]
                    is not None
                    and current
                )
            )
        )

        os.kill(status["supervisor_pid"], signal.SIGTERM)
        wait_status = wait_child_status(status["supervisor_pid"])
        self.supervisor_pids.remove(status["supervisor_pid"])
        self.assertEqual(os.waitstatus_to_exitcode(wait_status), 0)
        eventually(
            lambda: SUPERVISOR.process_start_identity(status["daemon_pid"])
            is None
        )
        self.daemon_pids.remove(status["daemon_pid"])
        self.assertEqual(
            SUPERVISOR.read_status_owner(stale.runtime_dir, stale.agent_key),
            (owner_pid, owner_identity),
        )

        current = self.prepare()
        SUPERVISOR.prune_orphaned_state(
            current.runtime_dir.parent,
            current.state_dir.parent,
            current.agent_key,
        )
        self.assertTrue(
            stale.runtime_dir.exists(),
            "a live owner must not be pruned",
        )
        self.assertTrue(
            stale.state_dir.exists(),
            "a live owner must not be pruned",
        )

        owner_process = next(
            process for process in self.owner_processes if process.pid == owner_pid
        )
        owner_process.terminate()
        owner_process.wait(timeout=3)
        SUPERVISOR.prune_orphaned_state(
            current.runtime_dir.parent,
            current.state_dir.parent,
            current.agent_key,
        )
        self.assertFalse(stale.runtime_dir.exists())
        self.assertFalse(stale.state_dir.exists())

    def test_reboot_orphan_state_is_pruned_without_following_symlinks(self):
        current = self.prepare()
        stale_key = SUPERVISOR.derive_agent_key(
            4242,
            "linux:old-boot:99",
            os.getuid(),
        )
        stale_state = current.state_dir.parent / stale_key
        SUPERVISOR.ensure_private_directory(stale_state)
        outside = self.root / "reboot-outside-sentinel"
        outside.write_text("preserve me too")
        (stale_state / "outside-link").symlink_to(outside)

        SUPERVISOR.prune_orphaned_state(
            current.runtime_dir.parent,
            current.state_dir.parent,
            current.agent_key,
        )
        self.assertFalse(stale_state.exists())
        self.assertEqual(outside.read_text(), "preserve me too")

    def test_daemon_environment_drops_alternate_editor(self):
        args = self.prepare()
        with mock.patch.dict(
            os.environ,
            {
                "ALTERNATE_EDITOR": "/tmp/user-editor",
                "ANVIL_DAEMON_SENTINEL": "preserved",
            },
        ):
            environment = SUPERVISOR.daemon_environment(args)

        self.assertNotIn("ALTERNATE_EDITOR", environment)
        self.assertEqual(environment["ANVIL_DAEMON_SENTINEL"], "preserved")

    def test_socket_readiness_drops_alternate_editor(self):
        socket_path = self.root / "readiness.sock"
        completed = subprocess.CompletedProcess(
            args=["/emacsclient"],
            returncode=0,
            stdout=b"t\n",
        )
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server_socket:
            server_socket.bind(str(socket_path))
            with (
                mock.patch.dict(
                    os.environ,
                    {
                        "ALTERNATE_EDITOR": "/tmp/must-not-run",
                        "ANVIL_TRANSPORT_SENTINEL": "preserved",
                    },
                ),
                mock.patch.object(
                    SUPERVISOR.subprocess,
                    "run",
                    return_value=completed,
                ) as run,
            ):
                self.assertTrue(
                    SUPERVISOR.safe_socket_ready(socket_path, "/emacsclient")
                )

        environment = run.call_args.kwargs["env"]
        self.assertNotIn("ALTERNATE_EDITOR", environment)
        self.assertEqual(
            environment["ANVIL_TRANSPORT_SENTINEL"],
            "preserved",
        )

    def test_bridge_stdio_environment_drops_alternate_editor(self):
        bridge_args = SimpleNamespace(
            daemon="/daemon",
            emacsclient="/emacsclient",
            grace_seconds=0.5,
            host="hera",
            parent_guard="/parent-guard",
            python=sys.executable,
            ready_seconds=1.0,
            runtime_root=str(self.runtime_root),
            server_id="anvil",
            state_root=str(self.state_root),
            stdio="/stdio",
        )
        owner_identity = SUPERVISOR.process_start_identity(os.getpid())
        captured = {}

        class ExecCaptured(Exception):
            pass

        def capture_execve(path, arguments, environment):
            captured.update(
                path=path,
                arguments=arguments,
                environment=environment.copy(),
            )
            raise ExecCaptured

        with (
            mock.patch.dict(
                os.environ,
                {
                    "ALTERNATE_EDITOR": "/tmp/must-not-run",
                    "ANVIL_TRANSPORT_SENTINEL": "preserved",
                },
            ),
            mock.patch.object(
                SUPERVISOR,
                "identify_owner",
                return_value=(os.getpid(), owner_identity),
            ),
            mock.patch.object(SUPERVISOR, "wait_for_daemon"),
            mock.patch.object(
                SUPERVISOR.os,
                "execve",
                side_effect=capture_execve,
            ),
        ):
            with self.assertRaises(ExecCaptured):
                SUPERVISOR.bridge_main(bridge_args)

        environment = captured["environment"]
        self.assertEqual(captured["path"], "/stdio")
        self.assertNotIn("ALTERNATE_EDITOR", environment)
        self.assertEqual(
            environment["ANVIL_TRANSPORT_SENTINEL"],
            "preserved",
        )
        self.assertTrue(environment["ANVIL_EMACS_SOCKET"].endswith("/server"))

    def test_nan_timeouts_are_rejected(self):
        for option in ("--grace-seconds", "--ready-seconds"):
            with self.subTest(option=option):
                stderr = io.StringIO()
                with contextlib.redirect_stderr(stderr):
                    with self.assertRaises(SystemExit) as raised:
                        SUPERVISOR.parse_arguments(
                            self.parser_arguments(option, "nan")
                        )
                self.assertEqual(raised.exception.code, 2)
                self.assertIn("must be between", stderr.getvalue())

    def test_parent_lock_runtime_failure_maps_to_unavailable_without_traceback(
        self,
    ):
        bridge_args = SimpleNamespace(
            daemon="/daemon",
            emacsclient="/emacsclient",
            grace_seconds=0.5,
            host="hera",
            parent_guard="/parent-guard",
            python=sys.executable,
            ready_seconds=1.0,
            runtime_root=str(self.runtime_root),
            server_id="anvil",
            state_root=str(self.state_root),
            stdio="/stdio",
        )
        owner_identity = SUPERVISOR.process_start_identity(os.getpid())
        stderr = io.StringIO()
        with (
            mock.patch.object(
                SUPERVISOR,
                "identify_owner",
                return_value=(os.getpid(), owner_identity),
            ),
            mock.patch.object(
                SUPERVISOR,
                "validate_supervisor_lock",
                side_effect=RuntimeError("injected lock identity change"),
            ),
            contextlib.redirect_stderr(stderr),
        ):
            with self.assertRaises(SystemExit) as raised:
                SUPERVISOR.bridge_main(bridge_args)

        self.assertEqual(raised.exception.code, SUPERVISOR.EXIT_UNAVAILABLE)
        self.assertEqual(
            stderr.getvalue(),
            "anvil-mcp: per-agent daemon: "
            "agent supervisor lock validation failed\n",
        )
        self.assertNotIn("Traceback", stderr.getvalue())

    def test_supervisor_readiness_timeout_maps_to_unavailable(self):
        args = self.prepare()
        lock_descriptor = os.open(os.devnull, os.O_RDONLY)
        with (
            mock.patch.object(
                SUPERVISOR,
                "try_supervisor_lock",
                return_value=(lock_descriptor, (1, 1)),
            ),
            mock.patch.object(SUPERVISOR, "validate_supervisor_lock"),
            mock.patch.object(SUPERVISOR, "publish_startup_status"),
            mock.patch.object(SUPERVISOR.os, "fork", return_value=4242),
            mock.patch.object(SUPERVISOR.os, "kill"),
            mock.patch.object(SUPERVISOR.os, "waitpid"),
        ):
            with self.assertRaisesRegex(
                TimeoutError,
                "agent supervisor did not become ready",
            ):
                SUPERVISOR.spawn_supervisor_if_absent(args)

        bridge_args = SimpleNamespace(
            daemon="/daemon",
            emacsclient="/emacsclient",
            host="hera",
            parent_guard="/parent-guard",
            python=sys.executable,
            runtime_root=str(self.runtime_root),
            server_id="anvil",
            state_root=str(self.state_root),
            stdio="/stdio",
        )
        owner_identity = SUPERVISOR.process_start_identity(os.getpid())
        stderr = io.StringIO()
        with (
            mock.patch.object(
                SUPERVISOR,
                "identify_owner",
                return_value=(os.getpid(), owner_identity),
            ),
            mock.patch.object(
                SUPERVISOR,
                "wait_for_daemon",
                side_effect=TimeoutError(
                    "agent supervisor did not become ready"
                ),
            ),
            contextlib.redirect_stderr(stderr),
        ):
            with self.assertRaises(SystemExit) as raised:
                SUPERVISOR.bridge_main(bridge_args)
        self.assertEqual(raised.exception.code, SUPERVISOR.EXIT_UNAVAILABLE)
        self.assertEqual(
            stderr.getvalue(),
            "anvil-mcp: per-agent daemon: "
            "agent supervisor did not become ready\n",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
