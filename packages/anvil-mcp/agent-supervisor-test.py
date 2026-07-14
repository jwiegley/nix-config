#!/usr/bin/env python3
"""Deterministic tests for per-MCP-bridge Anvil daemon supervision."""

from __future__ import annotations

import contextlib
import ctypes
import importlib.util
import io
import json
import os
from pathlib import Path
import selectors
import signal
import socket
import stat
from types import SimpleNamespace
import subprocess
import sys
import tempfile
import threading
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

TEST_GENERATION = "1" * 64
OTHER_GENERATION = "2" * 64


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
        identity = eventually(lambda: SUPERVISOR.process_start_identity(process.pid))
        return process.pid, identity

    def prepare(
        self,
        *,
        owner_pid: int | None = None,
        owner_start_identity: str | None = None,
        host: str = "hera",
        generation: str = TEST_GENERATION,
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
            generation,
        )
        runtime_dir, state_dir, leases_dir = SUPERVISOR.prepare_instance_directories(
            self.runtime_root,
            self.state_root,
            host,
            agent_key,
        )
        return SimpleNamespace(
            agent_key=agent_key,
            daemon="unused",
            grace_seconds=0.5,
            generation=generation,
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
            args.generation,
        )

    @staticmethod
    def live(args):
        return SUPERVISOR.live_leases(
            args.leases_dir,
            args.agent_key,
            args.owner_pid,
            args.owner_start_identity,
            args.generation,
        )

    @staticmethod
    def parser_arguments(*extra: str) -> list[str]:
        return [
            "--server-id",
            "anvil",
            "--host",
            "hera",
            "--generation",
            TEST_GENERATION,
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
                expected = "linux:12345678-1234-5678-9abc-def012345678:987654"
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

    def test_platform_process_probes_report_read_errors_as_unavailable(self):
        old_boot_id = SUPERVISOR._LINUX_BOOT_ID
        old_initialized = SUPERVISOR._LINUX_BOOT_ID_INITIALIZED
        SUPERVISOR._LINUX_BOOT_ID = "12345678-1234-5678-9abc-def012345678"
        SUPERVISOR._LINUX_BOOT_ID_INITIALIZED = True
        try:
            with mock.patch.object(
                SUPERVISOR.Path,
                "read_text",
                side_effect=OSError(SUPERVISOR.errno.EIO, "injected EIO"),
            ):
                self.assertEqual(
                    SUPERVISOR.linux_process_start_state(42),
                    (SUPERVISOR.LifecycleState.UNAVAILABLE, None),
                )
        finally:
            SUPERVISOR._LINUX_BOOT_ID = old_boot_id
            SUPERVISOR._LINUX_BOOT_ID_INITIALIZED = old_initialized

        def unavailable_proc_pidinfo(_pid, _flavor, _arg, _buffer, _size):
            ctypes.set_errno(SUPERVISOR.errno.EIO)
            return 0

        with mock.patch.object(
            SUPERVISOR,
            "darwin_proc_pidinfo",
            return_value=unavailable_proc_pidinfo,
        ):
            self.assertEqual(
                SUPERVISOR.darwin_process_start_state(42),
                (SUPERVISOR.LifecycleState.UNAVAILABLE, None),
            )

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
            eventually(lambda: SUPERVISOR.process_start_identity(process.pid) is None)
        finally:
            if process.stdout is not None:
                process.stdout.close()
            process.wait(timeout=3)

    def test_bridge_acquisition_uses_self_identity_not_parent_identity(self):
        stable = "linux:12345678-1234-5678-9abc-def012345678:10"
        with (
            mock.patch.object(
                SUPERVISOR,
                "input_pipe_closed",
                return_value=False,
            ),
            mock.patch.object(SUPERVISOR.os, "getpid", return_value=42),
            mock.patch.object(SUPERVISOR.os, "getppid") as getppid,
            mock.patch.object(
                SUPERVISOR,
                "process_start_identity",
                return_value=stable,
            ),
        ):
            self.assertEqual(SUPERVISOR.identify_bridge(), (42, stable))
            getppid.assert_not_called()

        with (
            mock.patch.object(
                SUPERVISOR,
                "input_pipe_closed",
                side_effect=[False, True],
            ) as pipe_closed,
            mock.patch.object(SUPERVISOR.os, "getpid", return_value=42),
            mock.patch.object(
                SUPERVISOR,
                "process_start_identity",
                return_value=stable,
            ),
        ):
            with self.assertRaises(SUPERVISOR.ConfigurationError):
                SUPERVISOR.identify_bridge()
            self.assertEqual(pipe_closed.call_count, 2)

        with (
            mock.patch.object(
                SUPERVISOR,
                "input_pipe_closed",
                return_value=False,
            ),
            mock.patch.object(SUPERVISOR.os, "getpid", return_value=42),
            mock.patch.object(
                SUPERVISOR,
                "process_start_identity",
                return_value=None,
            ),
        ):
            with self.assertRaises(SUPERVISOR.ConfigurationError):
                SUPERVISOR.identify_bridge()

    def test_closed_input_pipe_rejects_bridge_before_sampling_identity(self):
        read_fd, write_fd = os.pipe()
        try:
            os.close(write_fd)
            with mock.patch.object(SUPERVISOR.os, "getpid") as getpid:
                with self.assertRaises(SUPERVISOR.ConfigurationError):
                    SUPERVISOR.identify_bridge(read_fd)
                getpid.assert_not_called()
        finally:
            os.close(read_fd)

        read_fd, write_fd = os.pipe()
        try:
            os.write(write_fd, b"buffered MCP request")
            self.assertFalse(SUPERVISOR.input_pipe_closed(read_fd))
            self.assertEqual(os.read(read_fd, 20), b"buffered MCP request")
        finally:
            os.close(read_fd)
            os.close(write_fd)

    def test_bridge_and_package_generations_change_key_and_private_path(self):
        first_key = SUPERVISOR.derive_agent_key(
            4242,
            "linux:boot-a:100",
            TEST_GENERATION,
            501,
        )
        self.assertEqual(
            first_key,
            SUPERVISOR.derive_agent_key(
                4242,
                "linux:boot-a:100",
                TEST_GENERATION,
                501,
            ),
        )
        second_key = SUPERVISOR.derive_agent_key(
            4242,
            "linux:boot-a:101",
            TEST_GENERATION,
            501,
        )
        package_key = SUPERVISOR.derive_agent_key(
            4242,
            "linux:boot-a:100",
            OTHER_GENERATION,
            501,
        )
        self.assertNotEqual(first_key, second_key)
        self.assertNotEqual(first_key, package_key)
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
        for invalid in ("short", "A" * 64, "g" * 64):
            with self.subTest(generation=invalid):
                with self.assertRaises(SUPERVISOR.ConfigurationError):
                    SUPERVISOR.validate_generation(invalid)

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
        self.assertEqual(record["format"], 2)
        self.assertEqual(record["version"], 2)
        self.assertEqual(record["generation"], TEST_GENERATION)
        self.assertEqual(self.live(args), [record])

        stale = dict(record)
        stale["bridge_start_identity"] = f"{record['bridge_start_identity']}-reused"
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
            process for process in self.owner_processes if process.pid == owner_pid
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

    def test_lease_read_os_errors_are_unavailable_and_never_unlinked(self):
        args = self.prepare()
        lease, record = self.register(args, "anvil")
        for error_number in (
            SUPERVISOR.errno.ESTALE,
            SUPERVISOR.errno.ETIMEDOUT,
            SUPERVISOR.errno.ENOMEM,
        ):
            with self.subTest(error_number=error_number):
                with mock.patch.object(
                    SUPERVISOR.os,
                    "read",
                    side_effect=OSError(error_number, "injected read failure"),
                ):
                    with self.assertRaises(OSError) as raised:
                        self.live(args)
                self.assertEqual(raised.exception.errno, SUPERVISOR.errno.EAGAIN)
                self.assertTrue(lease.exists())
        self.assertEqual(self.live(args), [record])
        lease.unlink()

    def test_v1_lease_is_read_only_in_legacy_domain_and_pruned_from_v2(self):
        args = self.prepare()
        lease, record = self.register(args, "anvil")
        legacy = dict(record)
        legacy["format"] = 1
        legacy.pop("version")
        legacy.pop("generation")
        lease.write_text(json.dumps(legacy) + "\n")
        lease.chmod(0o600)

        self.assertEqual(
            SUPERVISOR.live_leases(
                args.leases_dir,
                args.agent_key,
                args.owner_pid,
                args.owner_start_identity,
                None,
            ),
            [legacy],
        )
        self.assertEqual(self.live(args), [])
        self.assertFalse(lease.exists())

    def test_v1_status_preserves_live_owner_and_prunes_dead_owner(self):
        owner_pid, owner_identity = self.start_owner()
        stale = self.prepare(
            owner_pid=owner_pid,
            owner_start_identity=owner_identity,
        )
        legacy = SUPERVISOR.owner_seed_record(stale)
        legacy["format"] = 1
        for field in (
            "generation",
            "version",
            "restart_count",
            "restart_reason",
        ):
            legacy.pop(field)
        SUPERVISOR.write_status(stale, legacy)

        self.assertEqual(
            SUPERVISOR.read_status_lifecycle(
                stale.runtime_dir,
                stale.agent_key,
            ),
            (owner_pid, owner_identity, None, 1),
        )
        current = self.prepare()
        SUPERVISOR.prune_orphaned_state(
            current.runtime_dir.parent,
            current.state_dir.parent,
            current.agent_key,
        )
        self.assertTrue(stale.runtime_dir.exists())
        self.assertTrue(stale.state_dir.exists())

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

    def test_v2_status_exposes_generation_and_record_version(self):
        args = self.prepare()
        SUPERVISOR.write_status(args, SUPERVISOR.owner_seed_record(args))
        self.assertEqual(
            SUPERVISOR.read_status_lifecycle(args.runtime_dir, args.agent_key),
            (args.owner_pid, args.owner_start_identity, TEST_GENERATION, 2),
        )

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
                    float(line) for line in attempt_log.read_text().splitlines() if line
                ]
                return values if len(values) >= 4 else False

            timestamps = eventually(attempts, timeout=5)[:4]

        intervals = [
            later - earlier for earlier, later in zip(timestamps, timestamps[1:])
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
                        (current := self.read_status(args))["daemon_pid"] is not None
                        and current
                    )
                )
            )
        self.assertTrue(failure_marker.exists())
        time.sleep(0.2)
        current = self.read_status(args)
        self.assertEqual(current["supervisor_pid"], status["supervisor_pid"])
        self.assertEqual(current["daemon_pid"], status["daemon_pid"])
        self.assertIsNotNone(SUPERVISOR.process_start_identity(current["daemon_pid"]))
        lease.unlink()

    def test_transient_owner_probe_preserves_live_instance(self):
        args = self.prepare()
        lease, _record = self.register(args, "anvil")
        trigger = self.root / "owner-probe-trigger"
        failed = self.root / "owner-probe-failed"
        recovered = self.root / "owner-probe-recovered"
        original_validate = SUPERVISOR.validate_process_identity

        def transient_owner_probe(pid, expected):
            if pid == args.owner_pid and trigger.exists():
                if not failed.exists():
                    failed.write_text("failed\n")
                    return SUPERVISOR.LifecycleState.UNAVAILABLE
                if not recovered.exists():
                    recovered.write_text("recovered\n")
            return original_validate(pid, expected)

        SUPERVISOR.start_daemon = fake_start_daemon
        with (
            mock.patch.object(
                SUPERVISOR,
                "validate_process_identity",
                side_effect=transient_owner_probe,
            ),
            mock.patch.object(SUPERVISOR, "POLL_SECONDS", 0.01),
            mock.patch.object(
                SUPERVISOR,
                "RESTART_BACKOFF_INITIAL_SECONDS",
                0.02,
            ),
        ):
            self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(args))
            status = self.remember_status(
                eventually(
                    lambda: (
                        (current := self.read_status(args))["daemon_pid"] is not None
                        and current
                    )
                )
            )
            supervisor_identity = SUPERVISOR.process_start_identity(
                status["supervisor_pid"]
            )
            daemon_identity = SUPERVISOR.process_start_identity(status["daemon_pid"])
            trigger.write_text("armed\n")
            eventually(recovered.exists)
            current = self.read_status(args)

        self.assertTrue(failed.exists())
        self.assertTrue(lease.exists())
        self.assertTrue(args.runtime_dir.is_dir())
        self.assertTrue(args.state_dir.is_dir())
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

    def test_transient_lease_read_preserves_valid_live_instance(self):
        args = self.prepare()
        lease, _record = self.register(args, "anvil")
        trigger = self.root / "lease-read-trigger"
        failed = self.root / "lease-read-failed"
        recovered = self.root / "lease-read-recovered"
        original_read_lease = SUPERVISOR.read_lease

        def transient_lease_read(*inner_args, **inner_kwargs):
            if trigger.exists():
                if not failed.exists():
                    with mock.patch.object(
                        SUPERVISOR.os,
                        "read",
                        side_effect=OSError(
                            SUPERVISOR.errno.EIO,
                            "injected lease EIO",
                        ),
                    ):
                        result = original_read_lease(
                            *inner_args,
                            **inner_kwargs,
                        )
                    failed.write_text(f"{result[0].value}\n")
                    return result
                if not recovered.exists():
                    recovered.write_text("recovered\n")
            return original_read_lease(*inner_args, **inner_kwargs)

        SUPERVISOR.start_daemon = fake_start_daemon
        with (
            mock.patch.object(
                SUPERVISOR,
                "read_lease",
                side_effect=transient_lease_read,
            ),
            mock.patch.object(SUPERVISOR, "POLL_SECONDS", 0.01),
            mock.patch.object(
                SUPERVISOR,
                "RESTART_BACKOFF_INITIAL_SECONDS",
                0.02,
            ),
        ):
            self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(args))
            status = self.remember_status(
                eventually(
                    lambda: (
                        (current := self.read_status(args))["daemon_pid"] is not None
                        and current
                    )
                )
            )
            supervisor_identity = SUPERVISOR.process_start_identity(
                status["supervisor_pid"]
            )
            daemon_identity = SUPERVISOR.process_start_identity(status["daemon_pid"])
            trigger.write_text("armed\n")
            eventually(recovered.exists)
            current = self.read_status(args)

        self.assertEqual(failed.read_text(), "unavailable\n")
        self.assertTrue(lease.exists())
        self.assertTrue(args.runtime_dir.is_dir())
        self.assertTrue(args.state_dir.is_dir())
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

    def test_real_stdio_pipe_and_instance_survive_transient_owner_probe(self):
        args = self.prepare()
        args.server_id = "anvil"
        args.stdio = "/json-rpc-fixture"
        lease, _record = self.register(args, "anvil")
        trigger = self.root / "pipe-owner-probe-trigger"
        failed = self.root / "pipe-owner-probe-failed"
        recovered = self.root / "pipe-owner-probe-recovered"
        original_validate = SUPERVISOR.validate_process_identity
        holder = {}
        responses = {}
        worker_errors = []

        def transient_supervisor_owner_probe(pid, expected):
            if (
                os.getpid() != args.owner_pid
                and pid == args.owner_pid
                and trigger.exists()
            ):
                if not failed.exists():
                    failed.write_text("failed\n")
                    return SUPERVISOR.LifecycleState.UNAVAILABLE
                if not recovered.exists():
                    recovered.write_text("recovered\n")
            return original_validate(pid, expected)

        stdio_script = """
import json
import sys

for line in sys.stdin:
    request = json.loads(line)
    response = {
        "jsonrpc": "2.0",
        "id": request["id"],
        "result": {"echo": request.get("params")},
    }
    print(json.dumps(response), flush=True)
    if request.get("method") == "shutdown":
        break
"""

        def start_real_stdio(_args):
            process = subprocess.Popen(
                [sys.executable, "-u", "-c", stdio_script],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                close_fds=True,
            )
            holder["process"] = process
            return process

        def rpc(process, identifier, method, params):
            if process.stdin is None or process.stdout is None:
                raise AssertionError("JSON-RPC fixture pipes are missing")
            request = {
                "jsonrpc": "2.0",
                "id": identifier,
                "method": method,
                "params": params,
            }
            process.stdin.write(json.dumps(request) + "\n")
            process.stdin.flush()
            selector = selectors.DefaultSelector()
            try:
                selector.register(process.stdout, selectors.EVENT_READ)
                if not selector.select(timeout=3):
                    raise AssertionError("JSON-RPC fixture response timed out")
            finally:
                selector.close()
            line = process.stdout.readline()
            if not line:
                stderr = ""
                if process.stderr is not None:
                    stderr = process.stderr.read()
                raise AssertionError(f"JSON-RPC fixture exited early: {stderr}")
            return json.loads(line)

        SUPERVISOR.start_daemon = fake_start_daemon
        with (
            mock.patch.object(
                SUPERVISOR,
                "validate_process_identity",
                side_effect=transient_supervisor_owner_probe,
            ),
            mock.patch.object(
                SUPERVISOR,
                "start_stdio_bridge",
                side_effect=start_real_stdio,
            ) as start_stdio,
            mock.patch.object(SUPERVISOR, "POLL_SECONDS", 0.01),
            mock.patch.object(
                SUPERVISOR,
                "RESTART_BACKOFF_INITIAL_SECONDS",
                0.02,
            ),
        ):
            self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(args))
            status = self.remember_status(
                eventually(
                    lambda: (
                        (current := self.read_status(args))["daemon_pid"] is not None
                        and current
                    )
                )
            )
            supervisor_identity = SUPERVISOR.process_start_identity(
                status["supervisor_pid"]
            )
            daemon_identity = SUPERVISOR.process_start_identity(status["daemon_pid"])

            def exercise_same_pipe():
                try:
                    process = eventually(lambda: holder.get("process"))
                    responses["stdio_pid"] = process.pid
                    responses["before"] = rpc(
                        process,
                        1,
                        "ping",
                        {"phase": "before"},
                    )
                    trigger.write_text("armed\n")
                    eventually(recovered.exists)
                    current = self.read_status(args)
                    if current["supervisor_pid"] != status["supervisor_pid"]:
                        raise AssertionError("transient probe replaced supervisor")
                    if current["daemon_pid"] != status["daemon_pid"]:
                        raise AssertionError("transient probe replaced daemon")
                    if not lease.exists():
                        raise AssertionError("transient probe removed lease")
                    if not args.runtime_dir.is_dir() or not args.state_dir.is_dir():
                        raise AssertionError("transient probe removed instance tree")
                    responses["after"] = rpc(
                        process,
                        2,
                        "ping",
                        {"phase": "after"},
                    )
                    responses["shutdown"] = rpc(
                        process,
                        3,
                        "shutdown",
                        {},
                    )
                except BaseException as error:
                    worker_errors.append(error)
                    process = holder.get("process")
                    if process is not None and process.poll() is None:
                        process.kill()

            worker = threading.Thread(target=exercise_same_pipe, daemon=True)
            worker.start()
            caretaker_status = SUPERVISOR.caretake_stdio_bridge(args)
            worker.join(timeout=5)

        process = holder.get("process")
        if worker.is_alive():
            if process is not None and process.poll() is None:
                process.kill()
            self.fail("same-pipe exercise did not terminate")
        if worker_errors:
            raise AssertionError("same-pipe exercise failed") from worker_errors[0]
        self.assertEqual(caretaker_status, 0)
        start_stdio.assert_called_once_with(args)
        self.assertIsNotNone(process)
        self.assertEqual(process.pid, responses["stdio_pid"])
        self.assertEqual(
            responses["before"]["result"]["echo"],
            {"phase": "before"},
        )
        self.assertEqual(
            responses["after"]["result"]["echo"],
            {"phase": "after"},
        )
        self.assertEqual(responses["shutdown"]["id"], 3)
        self.assertEqual(failed.read_text(), "failed\n")
        self.assertTrue(lease.exists())
        self.assertTrue(args.runtime_dir.is_dir())
        self.assertTrue(args.state_dir.is_dir())
        current = self.read_status(args)
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
        for stream in (process.stdin, process.stdout, process.stderr):
            if stream is not None:
                stream.close()
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
                        (current := self.read_status(args))["daemon_pid"] is not None
                        and current
                    )
                )
            )
            supervisor_identity = SUPERVISOR.process_start_identity(
                status["supervisor_pid"]
            )
            daemon_identity = SUPERVISOR.process_start_identity(status["daemon_pid"])
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
                        (current := self.read_status(args))["daemon_pid"] is not None
                        and current
                    )
                )
            )
            trigger.write_text("armed\n")
            wait_status = wait_child_status(status["supervisor_pid"])

        self.supervisor_pids.remove(status["supervisor_pid"])
        self.assertEqual(
            os.waitstatus_to_exitcode(wait_status), SUPERVISOR.EXIT_SOFTWARE
        )
        eventually(
            lambda: SUPERVISOR.process_start_identity(status["daemon_pid"]) is None
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
                        (current := self.read_status(args))["daemon_pid"] is not None
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

    def test_sibling_bridges_under_one_parent_are_isolated(self):
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
        second_lease, _ = self.register(second_args, "emacs-eval")
        SUPERVISOR.start_daemon = fake_start_daemon
        self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(first_args))
        self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(second_args))

        first = self.remember_status(
            eventually(
                lambda: (
                    (current := self.read_status(first_args))["lease_count"] == 1
                    and current["daemon_pid"] is not None
                    and current
                )
            )
        )
        second = self.remember_status(
            eventually(
                lambda: (
                    (current := self.read_status(second_args))["lease_count"] == 1
                    and current["daemon_pid"] is not None
                    and current
                )
            )
        )
        self.assertNotEqual(first_args.agent_key, second_args.agent_key)
        self.assertNotEqual(first_args.runtime_dir, second_args.runtime_dir)
        self.assertNotEqual(first["supervisor_pid"], second["supervisor_pid"])
        self.assertNotEqual(first["daemon_pid"], second["daemon_pid"])
        for status, args in ((first, first_args), (second, second_args)):
            self.assertEqual(status["format"], 2)
            self.assertEqual(status["version"], 2)
            self.assertEqual(status["generation"], TEST_GENERATION)
            self.assertEqual(status["agent_key"], args.agent_key)
            self.assertEqual(status["owner_pid"], args.owner_pid)

        old_daemon_pid = first["daemon_pid"]
        os.killpg(old_daemon_pid, signal.SIGKILL)
        # A successful signal transfers cleanup to the supervisor.  Forget the
        # historical PGID immediately so even a restart timeout cannot make
        # teardown target a host process that later reuses the numeric PID.
        self.daemon_pids.discard(old_daemon_pid)
        restarted = self.remember_status(
            eventually(
                lambda: (
                    (current := self.read_status(first_args))["daemon_pid"]
                    not in (None, old_daemon_pid)
                    and current
                )
            )
        )
        self.assertNotIn(old_daemon_pid, self.daemon_pids)
        self.assertIn(restarted["daemon_pid"], self.daemon_pids)
        self.assertIn(second["daemon_pid"], self.daemon_pids)
        self.assertEqual(restarted["supervisor_pid"], first["supervisor_pid"])
        self.assertEqual(restarted["restart_count"], 1)
        self.assertTrue(restarted["restart_reason"].startswith("daemon-exited:"))
        self.assertEqual(
            self.read_status(second_args)["daemon_pid"],
            second["daemon_pid"],
        )
        first_lease.unlink()
        second_lease.unlink()

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
                lambda: (
                    json.loads(child_record.read_text())
                    if child_record.exists()
                    else False
                )
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
                    (current := self.read_status(first_args))["daemon_pid"] is not None
                    and current
                )
            )
        )
        second = self.remember_status(
            eventually(
                lambda: (
                    (current := self.read_status(second_args))["daemon_pid"] is not None
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
            lambda: (
                self.read_status(first_args)["daemon_pid"] is None
                and self.read_status(first_args)["lease_count"] == 0
            )
        )
        eventually(
            lambda: (
                self.read_status(second_args)["daemon_pid"] is None
                and self.read_status(second_args)["lease_count"] == 0
            )
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
                    (current := self.read_status(args))["daemon_pid"] is not None
                    and current
                )
            )
        )
        self.assertIsNotNone(status["daemon_pid"])
        self.assertEqual(self.live(args), [record])

        owner_process = next(
            process for process in self.owner_processes if process.pid == owner_pid
        )
        owner_process.terminate()
        # Do not reap yet: zombie owners must already count as dead. The
        # registering bridge (this test process) deliberately remains live.
        eventually(lambda: not args.runtime_dir.exists())
        eventually(lambda: not args.state_dir.exists())
        self.assertTrue(outside.exists())
        self.assertEqual(outside.read_text(), "preserve me")
        self.assertFalse(lease.exists())
        self.assertIsNotNone(SUPERVISOR.process_start_identity(record["bridge_pid"]))
        eventually(
            lambda: SUPERVISOR.process_start_identity(status["daemon_pid"]) is None
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

        self.assertGreaterEqual(len(child_attempts.read_text().splitlines()), 1)
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
            generation=TEST_GENERATION,
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
                "identify_bridge",
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
                    (current := self.read_status(stale))["daemon_pid"] is not None
                    and current
                )
            )
        )
        os.kill(status["supervisor_pid"], signal.SIGKILL)
        self.assertTrue(reap_child(status["supervisor_pid"]))
        self.supervisor_pids.remove(status["supervisor_pid"])
        os.killpg(status["daemon_pid"], signal.SIGKILL)
        eventually(
            lambda: SUPERVISOR.process_start_identity(status["daemon_pid"]) is None
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
                    (current := self.read_status(stale))["daemon_pid"] is not None
                    and current
                )
            )
        )

        os.kill(status["supervisor_pid"], signal.SIGTERM)
        wait_status = wait_child_status(status["supervisor_pid"])
        self.supervisor_pids.remove(status["supervisor_pid"])
        self.assertEqual(os.waitstatus_to_exitcode(wait_status), 0)
        eventually(
            lambda: SUPERVISOR.process_start_identity(status["daemon_pid"]) is None
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
            TEST_GENERATION,
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

    def test_daemon_diagnostic_is_private_truncated_bounded_and_daemon_only(self):
        args = self.prepare()
        diagnostic = args.runtime_dir / SUPERVISOR.DAEMON_DIAGNOSTIC_NAME
        diagnostic.write_text("stale diagnostic content\n")
        diagnostic.chmod(0o600)
        script = self.root / "diagnostic-daemon.py"
        script.write_text(
            "import os, sys\n"
            "data = sys.stdin.buffer.read()\n"
            "os.write(1, f'daemon-stdin-bytes={len(data)}\\n'.encode())\n"
            "os.write(1, b'stdout-marker\\n')\n"
            "os.write(2, b'stderr-marker\\n')\n"
            f"os.write(1, b'x' * {SUPERVISOR.MAX_DAEMON_DIAGNOSTIC_BYTES + 4096})\n"
        )
        args.parent_guard = str(script)
        args.daemon = "/unused-daemon"

        process = SUPERVISOR.start_daemon(args)
        while process.poll() is None:
            SUPERVISOR.drain_daemon_diagnostic(process)
            time.sleep(0.005)
        SUPERVISOR.close_daemon_diagnostic(process)

        payload = diagnostic.read_bytes()
        self.assertEqual(
            len(payload),
            SUPERVISOR.MAX_DAEMON_DIAGNOSTIC_BYTES,
        )
        self.assertEqual(stat.S_IMODE(diagnostic.stat().st_mode), 0o600)
        self.assertIn(b"daemon-stdin-bytes=0", payload)
        self.assertIn(b"stdout-marker", payload)
        self.assertIn(b"stderr-marker", payload)
        self.assertNotIn(b"stale diagnostic content", payload)

    def test_daemon_diagnostic_refuses_symlink_target(self):
        args = self.prepare()
        outside = self.root / "outside-diagnostic"
        outside.write_text("preserve\n")
        diagnostic = args.runtime_dir / SUPERVISOR.DAEMON_DIAGNOSTIC_NAME
        diagnostic.symlink_to(outside)

        with self.assertRaises(OSError):
            SUPERVISOR.open_daemon_diagnostic(args.runtime_dir)
        self.assertEqual(outside.read_text(), "preserve\n")

    def test_daemon_diagnostic_validates_hardlink_before_truncating(self):
        args = self.prepare()
        outside = self.root / "outside-hardlinked-diagnostic"
        outside.write_text("preserve hardlink target\n")
        diagnostic = args.runtime_dir / SUPERVISOR.DAEMON_DIAGNOSTIC_NAME
        os.link(outside, diagnostic)

        with self.assertRaises(SUPERVISOR.ConfigurationError):
            SUPERVISOR.open_daemon_diagnostic(args.runtime_dir)
        self.assertEqual(outside.read_text(), "preserve hardlink target\n")

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

        self.assertEqual(
            run.call_args.args[0],
            [
                "/emacsclient",
                "-a",
                "false",
                "-s",
                str(socket_path),
                "-e",
                "t",
            ],
        )
        environment = run.call_args.kwargs["env"]
        self.assertNotIn("ALTERNATE_EDITOR", environment)
        self.assertEqual(
            environment["ANVIL_TRANSPORT_SENTINEL"],
            "preserved",
        )

    def test_stdio_child_inherits_pipes_and_drops_alternate_editor(self):
        args = self.prepare()
        args.server_id = "anvil"
        args.stdio = "/stdio"
        child = mock.Mock()
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
                "Popen",
                return_value=child,
            ) as popen,
        ):
            self.assertIs(SUPERVISOR.start_stdio_bridge(args), child)

        command = popen.call_args.args[0]
        options = popen.call_args.kwargs
        self.assertEqual(
            command[:5],
            [sys.executable, "-I", "-S", "unused", "group"],
        )
        self.assertEqual(command[5], "/stdio")
        self.assertEqual(command[-1], "--server-id=anvil")
        self.assertTrue(command[6].endswith("/emacs/server"))
        self.assertIsNone(options["stdin"])
        self.assertIsNone(options["stdout"])
        self.assertIsNone(options["stderr"])
        self.assertNotIn("ALTERNATE_EDITOR", options["env"])
        self.assertEqual(
            options["env"]["ANVIL_TRANSPORT_SENTINEL"],
            "preserved",
        )
        self.assertEqual(
            options["env"]["ANVIL_HEADLESS_PARENT_PID"],
            str(os.getpid()),
        )
        self.assertEqual(
            options["env"]["ANVIL_MCP_PARENT_GUARD"],
            args.parent_guard,
        )
        self.assertEqual(
            options["env"]["ANVIL_MCP_PARENT_GUARD_PYTHON"],
            args.python,
        )
        self.assertTrue(options["env"]["ANVIL_EMACS_SOCKET"].endswith("/server"))

    def test_bridge_caretaker_retains_identity_and_lease(self):
        bridge_args = SimpleNamespace(
            daemon="/daemon",
            emacsclient="/emacsclient",
            generation=TEST_GENERATION,
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

        def inspect_caretaker(args):
            captured["owner"] = (
                args.owner_pid,
                args.owner_start_identity,
            )
            captured["agent_key"] = args.agent_key
            captured["leases"] = SUPERVISOR.live_leases(
                args.leases_dir,
                args.agent_key,
                args.owner_pid,
                args.owner_start_identity,
                args.generation,
            )
            return 0

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
                "identify_bridge",
                return_value=(os.getpid(), owner_identity),
            ),
            mock.patch.object(SUPERVISOR, "wait_for_daemon"),
            mock.patch.object(
                SUPERVISOR,
                "caretake_stdio_bridge",
                side_effect=inspect_caretaker,
            ),
        ):
            SUPERVISOR.bridge_main(bridge_args)

        self.assertEqual(captured["owner"], (os.getpid(), owner_identity))
        self.assertEqual(len(captured["leases"]), 1)
        self.assertEqual(captured["leases"][0]["bridge_pid"], os.getpid())
        self.assertEqual(captured["leases"][0]["owner_pid"], os.getpid())
        runtime_dir = self.runtime_root / "hera" / "agents" / captured["agent_key"]
        self.assertEqual(
            SUPERVISOR.live_leases(
                runtime_dir / "leases",
                captured["agent_key"],
                os.getpid(),
                owner_identity,
                TEST_GENERATION,
            ),
            [],
        )

    def test_caretaker_reensures_supervisor_while_same_stdio_child_lives(self):
        args = self.prepare()
        args.server_id = "anvil"
        args.stdio = "/stdio"

        class FakeStdio:
            def __init__(self):
                self.returncode = None
                self.waits = 0

            def poll(self):
                return self.returncode

            def wait(self, timeout=None):
                self.waits += 1
                if self.waits < 3:
                    raise subprocess.TimeoutExpired(["/stdio"], timeout)
                self.returncode = 0
                return 0

            def terminate(self):
                self.returncode = -signal.SIGTERM

            def kill(self):
                self.returncode = -signal.SIGKILL

        child = FakeStdio()
        with (
            mock.patch.object(
                SUPERVISOR,
                "start_stdio_bridge",
                return_value=child,
            ) as start_stdio,
            mock.patch.object(
                SUPERVISOR,
                "spawn_supervisor_if_absent",
                side_effect=[False, TimeoutError("transient"), True],
            ) as ensure,
            mock.patch.object(
                SUPERVISOR,
                "CARETAKER_ENSURE_SECONDS",
                0.0,
            ),
            mock.patch.object(
                SUPERVISOR,
                "restart_backoff_seconds",
                return_value=0.0,
            ),
        ):
            self.assertEqual(SUPERVISOR.caretake_stdio_bridge(args), 0)

        start_stdio.assert_called_once_with(args)
        self.assertEqual(ensure.call_count, 3)
        self.assertEqual(child.waits, 3)

    def test_caretaker_preserves_stdio_child_during_transient_owner_probe(self):
        args = self.prepare()
        args.server_id = "anvil"
        args.stdio = "/stdio"

        class FakeStdio:
            def __init__(self):
                self.returncode = None
                self.waits = 0
                self.stopped = False

            def poll(self):
                return self.returncode

            def wait(self, timeout=None):
                self.waits += 1
                if self.waits == 1:
                    raise subprocess.TimeoutExpired(["/stdio"], timeout)
                self.returncode = 0
                return 0

            def terminate(self):
                self.stopped = True
                self.returncode = -signal.SIGTERM

            def kill(self):
                self.stopped = True
                self.returncode = -signal.SIGKILL

        child = FakeStdio()
        with (
            mock.patch.object(
                SUPERVISOR,
                "start_stdio_bridge",
                return_value=child,
            ) as start_stdio,
            mock.patch.object(
                SUPERVISOR,
                "validate_process_identity",
                side_effect=(
                    SUPERVISOR.LifecycleState.UNAVAILABLE,
                    SUPERVISOR.LifecycleState.LIVE,
                ),
            ) as owner_probe,
            mock.patch.object(
                SUPERVISOR,
                "spawn_supervisor_if_absent",
                return_value=False,
            ) as ensure,
            mock.patch.object(
                SUPERVISOR,
                "CARETAKER_ENSURE_SECONDS",
                0.0,
            ),
            mock.patch.object(
                SUPERVISOR,
                "restart_backoff_seconds",
                return_value=0.0,
            ),
        ):
            self.assertEqual(SUPERVISOR.caretake_stdio_bridge(args), 0)

        start_stdio.assert_called_once_with(args)
        self.assertEqual(owner_probe.call_count, 2)
        ensure.assert_called_once_with(args)
        self.assertEqual(child.waits, 2)
        self.assertFalse(child.stopped)

    def test_ready_timeout_cannot_exceed_client_startup_policy(self):
        accepted = SUPERVISOR.parse_arguments(
            self.parser_arguments(
                "--ready-seconds",
                str(SUPERVISOR.MAX_READY_SECONDS),
            )
        )
        self.assertEqual(
            accepted.ready_seconds,
            SUPERVISOR.MAX_READY_SECONDS,
        )

        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            with self.assertRaises(SystemExit) as raised:
                SUPERVISOR.parse_arguments(
                    self.parser_arguments(
                        "--ready-seconds",
                        str(SUPERVISOR.MAX_READY_SECONDS + 1),
                    )
                )
        self.assertEqual(raised.exception.code, 2)
        self.assertIn("must be between 1 and 120", stderr.getvalue())

    def test_nan_timeouts_are_rejected(self):
        for option in ("--grace-seconds", "--ready-seconds"):
            with self.subTest(option=option):
                stderr = io.StringIO()
                with contextlib.redirect_stderr(stderr):
                    with self.assertRaises(SystemExit) as raised:
                        SUPERVISOR.parse_arguments(self.parser_arguments(option, "nan"))
                self.assertEqual(raised.exception.code, 2)
                self.assertIn("must be between", stderr.getvalue())

    def test_parent_lock_runtime_failure_maps_to_unavailable_without_traceback(
        self,
    ):
        bridge_args = SimpleNamespace(
            daemon="/daemon",
            emacsclient="/emacsclient",
            generation=TEST_GENERATION,
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
                "identify_bridge",
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
            "anvil-mcp: per-agent daemon: agent supervisor lock validation failed\n",
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
            generation=TEST_GENERATION,
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
                "identify_bridge",
                return_value=(os.getpid(), owner_identity),
            ),
            mock.patch.object(
                SUPERVISOR,
                "wait_for_daemon",
                side_effect=TimeoutError("agent supervisor did not become ready"),
            ),
            contextlib.redirect_stderr(stderr),
        ):
            with self.assertRaises(SystemExit) as raised:
                SUPERVISOR.bridge_main(bridge_args)
        self.assertEqual(raised.exception.code, SUPERVISOR.EXIT_UNAVAILABLE)
        self.assertEqual(
            stderr.getvalue(),
            "anvil-mcp: per-agent daemon: agent supervisor did not become ready\n",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
