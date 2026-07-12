#!/usr/bin/env python3
"""Deterministic tests for per-Codex-process Anvil daemon supervision."""

from __future__ import annotations

import ctypes
import importlib.util
import json
import os
from pathlib import Path
import signal
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


class AgentSupervisorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.runtime_root = self.root / "runtime"
        self.state_root = self.root / "state"
        self.runtime_root.mkdir(mode=0o700)
        self.state_root.mkdir(mode=0o700)
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

    def test_same_owner_server_bridges_converge_restart_and_cleanup(self):
        args = self.prepare()
        first, _ = self.register(args, "anvil")
        second, _ = self.register(args, "emacs-eval")
        SUPERVISOR.start_daemon = fake_start_daemon
        self.assertTrue(SUPERVISOR.spawn_supervisor_if_absent(args))
        self.assertFalse(SUPERVISOR.spawn_supervisor_if_absent(args))

        status = self.remember_status(eventually(lambda: self.read_status(args)))
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
            eventually(lambda: self.read_status(first_args))
        )
        second = self.remember_status(
            eventually(lambda: self.read_status(second_args))
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
        status = self.remember_status(eventually(lambda: self.read_status(args)))
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
