#!/usr/bin/env python3

import contextlib
import json
import os
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


FAKE_TOOLS = {
    "bootstrap",
    "cmp",
    "grep",
    "id",
    "install",
    "kill",
    "launchctl",
    "mv",
    "pgrep",
    "plutil",
    "ps",
    "rm",
    "sfltool",
    "stat",
    "syncthing",
    "tmutil",
}
WRAPPER_TOOLS = {"ifconfig", "route", "sleep", "socat", "ssh"}
STATE_DIRECTORY = Path("Library/Application Support/Syncthing")
LOG_DIRECTORY = Path("logs")
RUNTIME_DIRECTORY = Path("runtime")
PRIVATE_DIRECTORIES = (
    STATE_DIRECTORY,
    LOG_DIRECTORY,
    RUNTIME_DIRECTORY,
    Path("documents"),
    Path("desktop"),
)


def read_argv_log(path: Path):
    return [
        [argument.decode() for argument in invocation.split(b"\0")]
        for invocation in path.read_bytes().split(b"\0\0")
        if invocation
    ]


def expected_bootstrap_arguments(mode):
    peer_policies = (
        {
            "deviceID": "PEER-ONE",
            "addresses": ["tcp://192.0.2.10:22000"],
            "networks": ["192.0.2.10/32"],
            "autoAcceptFolders": True,
        },
        {
            "deviceID": "PEER-TWO",
            "addresses": ["tcp://198.51.100.20:22000"],
            "networks": ["198.51.100.0/24"],
            "autoAcceptFolders": False,
        },
    )
    arguments = [
        mode,
        "--config",
        str(STATE_DIRECTORY / "config.xml"),
        "--local-device-id",
        "LOCAL-DEVICE",
        "--listen-address",
        "tcp://127.0.0.1:22000",
    ]
    for policy in peer_policies:
        arguments.extend(
            [
                "--peer-policy",
                json.dumps(policy, separators=(",", ":"), sort_keys=True),
            ]
        )
    arguments.extend(
        [
            "--gui-socket",
            "runtime/gui.sock",
            "--default-policy",
            json.dumps(
                {
                    "folder": {"path": "~/test-doc", "fsWatcherEnabled": True},
                    "ignores": ["(?d).test-cache"],
                },
                separators=(",", ":"),
                sort_keys=True,
            ),
            "--documents",
            "documents",
            "--desktop",
            "desktop",
        ]
    )
    return arguments


def cleanup_process_group(process):
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


class PreflightTests(unittest.TestCase):
    @contextlib.contextmanager
    def fixture(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            for directory in PRIVATE_DIRECTORIES:
                path = root / directory
                path.mkdir(parents=True)
                path.chmod(0o700)
            for name in ("cert.pem", "key.pem", "config.xml"):
                path = root / STATE_DIRECTORY / name
                path.write_text(name, encoding="utf-8")
                path.chmod(0o600)
            for directory, expected in (
                ("documents", "expected-documents"),
                ("desktop", "expected-desktop"),
            ):
                (root / expected).write_text(f"{directory} ignore\n", encoding="utf-8")
                ignore = root / directory / ".stignore"
                ignore.write_text(f"{directory} ignore\n", encoding="utf-8")
                ignore.chmod(0o600)

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            for tool in FAKE_TOOLS:
                (fake_bin / tool).symlink_to(FAKE_TOOL)
            environment = {
                name: value
                for name, value in os.environ.items()
                if not name.startswith("FAKE_")
            }
            environment.update(
                {
                    "FAKE_DEVICE_ID": "LOCAL-DEVICE",
                    "FAKE_LOGIN_ITEMS": "clean",
                    "FAKE_TM_EXCLUDED": "1",
                }
            )
            yield root, environment

    def run_preflight(self, root: Path, environment: dict[str, str]):
        process = subprocess.Popen(
            [BASH, "-euo", "pipefail", PREFLIGHT],
            cwd=root,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        self.addCleanup(cleanup_process_group, process)
        stdout, stderr = process.communicate(timeout=10)
        return subprocess.CompletedProcess(
            process.args, process.returncode, stdout, stderr
        )

    def assert_failure(self, expected: str, mutate=None, extra_environment=None):
        with self.fixture() as (root, environment):
            if mutate:
                mutate(root)
            environment.update(extra_environment or {})
            result = self.run_preflight(root, environment)
            self.assertNotEqual(result.returncode, 0, result)
            self.assertIn(expected, result.stderr)

    def test_success_cleans_transients_and_only_checks_policy(self):
        with self.fixture() as (root, environment):
            result = self.run_preflight(root, environment)
            self.assertEqual(result.returncode, 0, result)
            self.assertFalse(any((root / RUNTIME_DIRECTORY).glob("login-items.*")))
            self.assertEqual((root / ".bootstrap-log").read_text(), "--check\n")
            self.assertEqual(
                read_argv_log(root / ".bootstrap-argv"),
                [expected_bootstrap_arguments("--check")],
            )
            self.assertFalse((root / ".tmutil-log").exists())

    def test_every_private_directory_rejects_wrong_owner(self):
        for path in PRIVATE_DIRECTORIES:
            with self.subTest(path=path):
                self.assert_failure(
                    "private directory has the wrong owner",
                    extra_environment={"FAKE_WRONG_OWNER_PATH": str(path)},
                )

    def test_required_private_directories_reject_wrong_mode(self):
        for path in (STATE_DIRECTORY, Path("documents"), Path("desktop")):
            with self.subTest(path=path):
                self.assert_failure(
                    "private directory has the wrong mode",
                    extra_environment={"FAKE_WRONG_MODE_PATH": str(path)},
                )

    def test_private_directories_reject_missing_and_symlink_paths(self):
        for path in (STATE_DIRECTORY, Path("documents"), Path("desktop")):
            for kind in ("missing", "symlink"):

                def mutate(root, path=path, kind=kind):
                    shutil.rmtree(root / path)
                    if kind == "symlink":
                        (root / path).symlink_to(root / LOG_DIRECTORY)

                with self.subTest(path=path, kind=kind):
                    self.assert_failure(
                        f"required private directory is missing or unsafe: {path}",
                        mutate,
                    )

    def test_generated_private_directories_are_created_without_following_symlinks(
        self,
    ):
        for directory in (LOG_DIRECTORY, RUNTIME_DIRECTORY):
            with self.subTest(directory=directory, state="drifted mode"):
                with self.fixture() as (root, environment):
                    (root / directory).chmod(0o755)
                    result = self.run_preflight(root, environment)
                    self.assertEqual(result.returncode, 0, result)
                    self.assertEqual(
                        stat.S_IMODE((root / directory).stat().st_mode), 0o700
                    )

            with self.subTest(directory=directory, state="absent"):
                with self.fixture() as (root, environment):
                    shutil.rmtree(root / directory)
                    result = self.run_preflight(root, environment)
                    self.assertEqual(result.returncode, 0, result)
                    self.assertEqual(
                        stat.S_IMODE((root / directory).stat().st_mode), 0o700
                    )

            with self.subTest(directory=directory, state="symlink"):
                with self.fixture() as (root, environment):
                    shutil.rmtree(root / directory)
                    sentinel = root / f"{directory.name}-sentinel"
                    sentinel.mkdir()
                    sentinel.chmod(0o755)
                    (root / directory).symlink_to(sentinel)
                    result = self.run_preflight(root, environment)
                    self.assertNotEqual(result.returncode, 0, result)
                    self.assertIn(
                        f"required private directory is missing or unsafe: {directory}",
                        result.stderr,
                    )
                    self.assertEqual(stat.S_IMODE(sentinel.stat().st_mode), 0o755)

            with self.subTest(directory=directory, state="regular file"):
                with self.fixture() as (root, environment):
                    shutil.rmtree(root / directory)
                    (root / directory).touch()
                    result = self.run_preflight(root, environment)
                    self.assertNotEqual(result.returncode, 0, result)
                    self.assertIn(
                        f"required private directory is missing or unsafe: {directory}",
                        result.stderr,
                    )

            with self.subTest(directory=directory, state="creation failure"):
                with self.fixture() as (root, environment):
                    shutil.rmtree(root / directory)
                    environment.update(
                        {
                            "FAKE_FAIL_TOOL": "install",
                            "FAKE_FAIL_TARGET": str(directory),
                        }
                    )
                    result = self.run_preflight(root, environment)
                    self.assertNotEqual(result.returncode, 0, result)
                    self.assertIn(
                        f"could not create private directory: {directory}",
                        result.stderr,
                    )

    def test_every_identity_file_rejects_each_unsafe_state(self):
        def replace_with_symlink(item):
            target = item.parent / "identity-target"
            target.write_text("target", encoding="utf-8")
            target.chmod(0o600)
            item.unlink()
            item.symlink_to(target)

        for name in ("cert.pem", "key.pem", "config.xml"):
            path = str(STATE_DIRECTORY / name)
            cases = {
                "missing": (
                    lambda item: item.unlink(),
                    "required private file is missing or unsafe",
                ),
                "symlink": (
                    replace_with_symlink,
                    "required private file is missing or unsafe",
                ),
                "owner": (None, "private file has the wrong owner"),
                "mode": (None, "private file has the wrong mode"),
            }
            for kind, (change, message) in cases.items():
                extra = {}
                if kind == "owner":
                    extra["FAKE_WRONG_OWNER_PATH"] = path
                elif kind == "mode":
                    extra["FAKE_WRONG_MODE_PATH"] = path

                def mutate(root, change=change, name=name):
                    if change:
                        change(root / STATE_DIRECTORY / name)

                with self.subTest(path=path, kind=kind):
                    self.assert_failure(message, mutate, extra)

    def test_device_identity_command_and_value_are_both_enforced(self):
        for environment, message in (
            (
                {"FAKE_DEVICE_ID_STATUS": "1"},
                "could not derive the bootstrapped device identity",
            ),
            (
                {"FAKE_DEVICE_ID": "WRONG"},
                "bootstrapped device identity does not match this host",
            ),
        ):
            with self.subTest(message=message):
                self.assert_failure(message, extra_environment=environment)

    def test_login_item_ownership_is_enforced(self):
        cases = (
            ({"FAKE_LOGIN_ITEMS": "registered"}, "Syncthing.app is still registered"),
            ({"FAKE_LOGIN_ITEMS": "bundle"}, "Syncthing.app is still registered"),
            (
                {"FAKE_LOGIN_ITEMS": "failure"},
                "could not safely inspect legacy login items",
            ),
            (
                {"FAKE_GREP_STATUS": "2"},
                "could not safely inspect legacy login items",
            ),
            (
                {
                    "FAKE_FAIL_TOOL": "install",
                    "FAKE_FAIL_TARGET": "runtime/login-items",
                },
                "could not safely inspect legacy login items",
            ),
        )
        for environment, message in cases:
            with self.subTest(environment=environment):
                self.assert_failure(message, extra_environment=environment)

    def test_login_item_timeout_reaps_the_inspector(self):
        with self.fixture() as (root, environment):
            environment["FAKE_LOGIN_ITEMS"] = "timeout"
            result = self.run_preflight(root, environment)
            self.assertNotEqual(result.returncode, 0, result)
            self.assertIn("could not safely inspect legacy login items", result.stderr)
            inspector_pid = (root / ".sfltool-pid").read_text()
            self.assertIn(
                inspector_pid, (root / ".preflight-wait-log").read_text().splitlines()
            )
            with self.assertRaises(ProcessLookupError):
                os.kill(int(inspector_pid), 0)

    def test_daemon_process_topology_rejects_every_unsafe_shape(self):
        cases = (
            (
                {"FAKE_DAEMON_PGREP_STATUS": "2"},
                "could not safely inspect running Syncthing processes",
            ),
            ({"FAKE_DAEMON_PIDS": "100"}, "unmanaged, duplicate, or unhealthy"),
            ({"FAKE_DAEMON_PIDS": "100,200,300"}, "unmanaged, duplicate, or unhealthy"),
            ({"FAKE_DAEMON_PIDS": "100,200"}, "unmanaged, duplicate, or unhealthy"),
            (
                {"FAKE_DAEMON_PIDS": "100,200", "FAKE_MANAGED_PID": "300"},
                "monitor is not owned by the managed launchd job",
            ),
            (
                {
                    "FAKE_DAEMON_PIDS": "100,200",
                    "FAKE_MANAGED_PID": "100",
                    "FAKE_EXPECTED_PS_PID": "200",
                    "FAKE_CHILD_PARENT": "300",
                },
                "second Syncthing process is not the managed monitor child",
            ),
        )
        for environment, message in cases:
            with self.subTest(environment=environment):
                self.assert_failure(message, extra_environment=environment)

    def test_single_daemon_sample_is_retried_until_topology_stabilizes(self):
        cases = (
            {
                "FAKE_DAEMON_PGREP_SEQUENCE": "100;100,200",
                "FAKE_MANAGED_PID": "100",
                "FAKE_EXPECTED_PS_PID": "200",
                "FAKE_CHILD_PARENT": "100",
            },
            {"FAKE_DAEMON_PGREP_SEQUENCE": "100;none"},
        )
        for extra_environment in cases:
            with self.subTest(sequence=extra_environment["FAKE_DAEMON_PGREP_SEQUENCE"]):
                with self.fixture() as (root, environment):
                    environment.update(extra_environment)
                    result = self.run_preflight(root, environment)
                    self.assertEqual(result.returncode, 0, result)
                    self.assertEqual((root / ".daemon-pgrep-index").read_text(), "2")

    def test_both_ignore_files_reject_unsafe_nodes(self):
        for directory in ("documents", "desktop"):
            for kind in ("directory", "symlink"):

                def mutate(root, directory=directory, kind=kind):
                    path = root / directory / ".stignore"
                    path.unlink()
                    if kind == "directory":
                        path.mkdir()
                    else:
                        path.symlink_to(root / f"expected-{directory}")

                with self.subTest(directory=directory, kind=kind):
                    self.assert_failure(
                        f"{directory.title()} .stignore is not a safe regular file",
                        mutate,
                    )

    def test_ignore_replacement_is_atomic_and_failure_is_fatal(self):
        for directory in ("documents", "desktop"):
            with self.subTest(directory=directory, result="success"):
                with self.fixture() as (root, environment):
                    ignore = root / directory / ".stignore"
                    ignore.write_text("stale\n", encoding="utf-8")
                    result = self.run_preflight(root, environment)
                    self.assertEqual(result.returncode, 0, result)
                    self.assertEqual(
                        ignore.read_text(), (root / f"expected-{directory}").read_text()
                    )
                    self.assertEqual(stat.S_IMODE(ignore.stat().st_mode), 0o600)
                    self.assertFalse(any((root / directory).glob(".stignore.tmp.*")))
            for tool in ("install", "mv"):
                with self.subTest(directory=directory, tool=tool):
                    with self.fixture() as (root, environment):
                        ignore = root / directory / ".stignore"
                        ignore.write_text("stale\n", encoding="utf-8")
                        environment.update(
                            {
                                "FAKE_FAIL_TOOL": tool,
                                "FAKE_FAIL_TARGET": f"{directory}/.stignore",
                            }
                        )
                        result = self.run_preflight(root, environment)
                        self.assertNotEqual(result.returncode, 0, result)
                        self.assertIn(
                            f"could not install the managed {directory.title()} .stignore",
                            result.stderr,
                        )
                        self.assertEqual(ignore.read_text(), "stale\n")
                        self.assertFalse(
                            any((root / directory).glob(".stignore.tmp.*"))
                        )

    def test_identical_ignore_files_replace_unsafe_metadata(self):
        for directory in ("documents", "desktop"):
            target = f"{directory}/.stignore"
            for variable in ("FAKE_WRONG_OWNER_PATH", "FAKE_WRONG_MODE_PATH"):
                with self.subTest(directory=directory, variable=variable):
                    with self.fixture() as (root, environment):
                        environment[variable] = target
                        result = self.run_preflight(root, environment)
                        self.assertEqual(result.returncode, 0, result)
                        self.assertIn(
                            target, (root / ".mv-log").read_text().splitlines()
                        )
                        ignore = root / target
                        self.assertEqual(
                            ignore.read_text(),
                            (root / f"expected-{directory}").read_text(),
                        )
                        self.assertEqual(stat.S_IMODE(ignore.stat().st_mode), 0o600)

    def test_time_machine_inspection_and_addition_fail_closed(self):
        cases = (
            (
                {"FAKE_TM_INSPECT_FAILURE": "1"},
                "could not inspect Time Machine exclusion",
            ),
            ({"FAKE_PLUTIL_FAILURE": "1"}, "could not inspect Time Machine exclusion"),
            (
                {"FAKE_TM_EXCLUDED": "0", "FAKE_TM_ADD_FAILURE": "1"},
                "could not add Time Machine exclusion",
            ),
        )
        for environment, message in cases:
            with self.subTest(environment=environment):
                self.assert_failure(message, extra_environment=environment)
        with self.fixture() as (root, environment):
            environment["FAKE_TM_EXCLUDED"] = "0"
            result = self.run_preflight(root, environment)
            self.assertEqual(result.returncode, 0, result)
            self.assertEqual((root / ".tmutil-log").read_text(), "documents\ndesktop\n")

    @staticmethod
    def create_socket(path: Path) -> None:
        opened = socket.socket(socket.AF_UNIX)
        try:
            opened.bind(str(path))
        finally:
            opened.close()

    def test_gui_socket_type_and_daemon_ownership_control_removal(self):
        self.assert_failure(
            "GUI socket path is unsafe",
            lambda root: (root / RUNTIME_DIRECTORY / "gui.sock").touch(),
        )
        with self.fixture() as (root, environment):
            target = root / "socket-target"
            opened = socket.socket(socket.AF_UNIX)
            try:
                opened.bind(str(target))
                (root / RUNTIME_DIRECTORY / "gui.sock").symlink_to(target)
                result = self.run_preflight(root, environment)
                self.assertNotEqual(result.returncode, 0, result)
                self.assertIn("GUI socket path is unsafe", result.stderr)
            finally:
                opened.close()
        with self.fixture() as (root, environment):
            path = root / RUNTIME_DIRECTORY / "gui.sock"
            self.create_socket(path)
            result = self.run_preflight(root, environment)
            self.assertEqual(result.returncode, 0, result)
            self.assertFalse(path.exists())
        with self.fixture() as (root, environment):
            path = root / RUNTIME_DIRECTORY / "gui.sock"
            self.create_socket(path)
            environment.update(
                {
                    "FAKE_DAEMON_PIDS": "200,100",
                    "FAKE_MANAGED_PID": "100",
                    "FAKE_EXPECTED_PS_PID": "200",
                    "FAKE_CHILD_PARENT": "100",
                }
            )
            result = self.run_preflight(root, environment)
            self.assertEqual(result.returncode, 0, result)
            self.assertTrue(path.exists())

    def test_bootstrap_status_and_each_hardening_step_are_enforced(self):
        cases = (
            (
                {"FAKE_BOOTSTRAP_STATUSES": "2"},
                "config.xml failed offline policy validation",
            ),
            (
                {
                    "FAKE_BOOTSTRAP_STATUSES": "3",
                    "FAKE_DAEMON_PIDS": "100,200",
                    "FAKE_MANAGED_PID": "100",
                    "FAKE_EXPECTED_PS_PID": "200",
                    "FAKE_CHILD_PARENT": "100",
                },
                "config.xml needs hardening while the managed daemon is running",
            ),
            (
                {"FAKE_BOOTSTRAP_STATUSES": "3,1"},
                "could not harden config.xml before launch",
            ),
            (
                {"FAKE_BOOTSTRAP_STATUSES": "3,0,1"},
                "config.xml did not retain the hardened policy",
            ),
        )
        for environment, message in cases:
            with self.subTest(environment=environment):
                self.assert_failure(message, extra_environment=environment)
        with self.fixture() as (root, environment):
            environment["FAKE_BOOTSTRAP_STATUSES"] = "3,0,0"
            result = self.run_preflight(root, environment)
            self.assertEqual(result.returncode, 0, result)
            self.assertEqual(
                (root / ".bootstrap-log").read_text(), "--check\n--apply\n--check\n"
            )
            self.assertEqual(
                read_argv_log(root / ".bootstrap-argv"),
                [
                    expected_bootstrap_arguments("--check"),
                    expected_bootstrap_arguments("--apply"),
                    expected_bootstrap_arguments("--check"),
                ],
            )


class WrapperTests(unittest.TestCase):
    @contextlib.contextmanager
    def fixture(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            fake_bin = root / "wrapper-bin"
            fake_bin.mkdir()
            for tool in WRAPPER_TOOLS:
                (fake_bin / tool).symlink_to(FAKE_TOOL)
            environment = {
                name: value
                for name, value in os.environ.items()
                if not name.startswith("FAKE_")
            }
            yield root, environment

    def run_wrapper(self, wrapper, root, environment):
        process = subprocess.Popen(
            [BASH, wrapper],
            cwd=root,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        self.addCleanup(cleanup_process_group, process)
        stdout, stderr = process.communicate(timeout=5)
        return subprocess.CompletedProcess(
            process.args, process.returncode, stdout, stderr
        )

    @staticmethod
    def wireguard_ssh_arguments(interface="utun7"):
        return [
            "-N",
            "-T",
            "-B",
            interface,
            "-b",
            "10.6.0.2",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=10",
            "-o",
            "ConnectionAttempts=1",
            "-o",
            "ControlMaster=no",
            "-o",
            "ControlPath=none",
            "-o",
            "ExitOnForwardFailure=yes",
            "-o",
            "ForwardAgent=no",
            "-o",
            "HostName=192.168.1.4",
            "-o",
            "PermitLocalCommand=no",
            "-o",
            "ProxyCommand=none",
            "-o",
            "ProxyJump=none",
            "-o",
            "ServerAliveCountMax=3",
            "-o",
            "ServerAliveInterval=15",
            "-o",
            "StrictHostKeyChecking=yes",
            "-L",
            "127.0.0.1:22001:192.168.1.4:22000",
            "hera",
        ]

    @staticmethod
    def home_ssh_arguments():
        return [
            "-T",
            "-b",
            "192.168.1.5",
            "-o",
            "BatchMode=yes",
            "-o",
            "ClearAllForwardings=yes",
            "-o",
            "ConnectTimeout=3",
            "-o",
            "ConnectionAttempts=1",
            "-o",
            "ControlMaster=no",
            "-o",
            "ControlPath=none",
            "-o",
            "ForwardAgent=no",
            "-o",
            "HostName=192.168.1.4",
            "-o",
            "PermitLocalCommand=no",
            "-o",
            "ProxyCommand=none",
            "-o",
            "ProxyJump=none",
            "-o",
            "StrictHostKeyChecking=yes",
            "hera",
            "/usr/bin/true",
        ]

    def assert_child_reaped(self, root):
        with self.assertRaises(ProcessLookupError):
            os.kill(int((root / ".wrapper-child-pid").read_text()), 0)

    def test_inactive_routes_never_launch_production_children(self):
        scenarios = (
            (WIREGUARD_WRAPPER, "error", None, False),
            (WIREGUARD_WRAPPER, "utun7", "wrong", True),
            (HOME_WRAPPER, "error", None, False),
            (HOME_WRAPPER, "en0", "wrong", True),
            (HOME_WRAPPER, "utun7", "192.168.1.5", False),
        )
        for wrapper, route, address, expects_ifconfig in scenarios:
            with self.subTest(wrapper=wrapper, route=route, address=address):
                with self.fixture() as (root, environment):
                    environment["FAKE_ROUTE_SEQUENCE"] = route
                    if address:
                        environment["FAKE_INTERFACE_ADDRESS"] = address
                    result = self.run_wrapper(wrapper, root, environment)
                    self.assertEqual(result.returncode, 0, result)
                    self.assertFalse((root / ".ssh-argv").exists())
                    self.assertFalse((root / ".socat-argv").exists())
                    self.assertEqual(
                        (root / ".ifconfig-argv").exists(), expects_ifconfig
                    )

    def test_active_routes_preserve_exact_production_child_arguments(self):
        with self.fixture() as (root, environment):
            environment.update(
                {
                    "FAKE_ROUTE_SEQUENCE": "utun7",
                    "FAKE_INTERFACE_ADDRESS": "10.6.0.2",
                }
            )
            result = self.run_wrapper(WIREGUARD_WRAPPER, root, environment)
            self.assertEqual(result.returncode, 0, result)
            self.assertEqual(
                read_argv_log(root / ".ssh-argv"),
                [self.wireguard_ssh_arguments()],
            )
            self.assertTrue(
                all(
                    invocation == ["-n", "get", "192.168.1.4"]
                    for invocation in read_argv_log(root / ".route-argv")
                )
            )
            ifconfig_calls = read_argv_log(root / ".ifconfig-argv")
            self.assertTrue(ifconfig_calls)
            self.assertTrue(
                all(invocation == ["utun7"] for invocation in ifconfig_calls)
            )

        with self.fixture() as (root, environment):
            environment.update(
                {
                    "FAKE_ROUTE_SEQUENCE": "en0",
                    "FAKE_INTERFACE_ADDRESS": "192.168.1.5",
                }
            )
            result = self.run_wrapper(HOME_WRAPPER, root, environment)
            self.assertEqual(result.returncode, 0, result)
            self.assertEqual(
                read_argv_log(root / ".ssh-argv"), [self.home_ssh_arguments()]
            )
            self.assertEqual(
                read_argv_log(root / ".socat-argv"),
                [
                    [
                        "TCP4-LISTEN:22000,bind=192.168.1.5,range=192.168.1.4/32,reuseaddr,fork",
                        "TCP4:127.0.0.1:22000",
                    ]
                ],
            )
            self.assertTrue(
                all(
                    invocation == ["-n", "get", "192.168.1.4"]
                    for invocation in read_argv_log(root / ".route-argv")
                )
            )
            self.assertTrue(
                all(
                    invocation == ["en0"]
                    for invocation in read_argv_log(root / ".ifconfig-argv")
                )
            )

    def test_home_ssh_probe_failure_prevents_bridge_launch(self):
        with self.fixture() as (root, environment):
            environment.update(
                {
                    "FAKE_ROUTE_SEQUENCE": "en0",
                    "FAKE_INTERFACE_ADDRESS": "192.168.1.5",
                    "FAKE_SSH_PROBE_STATUS": "7",
                }
            )
            result = self.run_wrapper(HOME_WRAPPER, root, environment)
            self.assertEqual(result.returncode, 7, result)
            self.assertEqual(
                read_argv_log(root / ".ssh-argv"), [self.home_ssh_arguments()]
            )
            self.assertFalse((root / ".socat-argv").exists())

    def test_route_loss_stops_and_reaps_each_production_child(self):
        scenarios = (
            (WIREGUARD_WRAPPER, "utun7;error", "10.6.0.2", 2),
            (HOME_WRAPPER, "en0;en0;error", "192.168.1.5", 3),
        )
        for wrapper, routes, address, route_count in scenarios:
            with self.subTest(wrapper=wrapper):
                with self.fixture() as (root, environment):
                    environment.update(
                        {
                            "FAKE_ROUTE_SEQUENCE": routes,
                            "FAKE_INTERFACE_ADDRESS": address,
                            "FAKE_CHILD_MODE": "run",
                            "FAKE_WAIT_FOR_CHILD": "1",
                        }
                    )
                    result = self.run_wrapper(wrapper, root, environment)
                    self.assertEqual(result.returncode, 0, result)
                    self.assertEqual(
                        (root / ".wrapper-child-events").read_text(), "start\nterm\n"
                    )
                    self.assert_child_reaped(root)
                    self.assertEqual(
                        len(read_argv_log(root / ".route-argv")), route_count
                    )
                    self.assertEqual(read_argv_log(root / ".sleep-argv"), [["30"]])


class MonitorTests(unittest.TestCase):
    def wrapper(
        self,
        root: Path,
        route: str,
        child: str,
        interval="0.02",
        interrupt_launch=None,
        timer="",
    ) -> Path:
        child_path = root / "child-test.sh"
        child_path.write_text(
            f"""#!{BASH}
set -euo pipefail
trap 'printf "term\\n" >>events; exit 0' TERM
printf '%s' "$$" >child-pid
printf 'start:%s\\n' "$1" >>events
: >child-ready
{child}
""",
            encoding="utf-8",
        )
        child_path.chmod(0o755)
        timer_path = root / "sleep-test.sh"
        timer_path.write_text(
            f"""#!{BASH}
set -euo pipefail
printf '%s' "$$" >timer-pid
{timer}
exec {SLEEP!r} "$1"
""",
            encoding="utf-8",
        )
        timer_path.chmod(0o755)
        debug_hook = ""
        if interrupt_launch:
            assignment = {
                "child": "child_pid=$!",
                "timer": "timer_pid=$!",
            }[interrupt_launch]
            readiness = {
                "child": "-f child-ready",
                "timer": "-f child-ready && -s timer-pid",
            }[interrupt_launch]
            debug_hook = f"""set -T
signal_before_assignment() {{
  if [[ "$BASH_COMMAND" == {assignment!r} ]]; then
    while ! [[ {readiness} ]]; do :; done
    trap - DEBUG
    kill -TERM "$$"
  fi
}}
trap signal_before_assignment DEBUG
"""
        path = root / "monitor-test.sh"
        path.write_text(
            f"""set -euo pipefail
source {MONITOR_LIBRARY!r}
{debug_hook}
wait() {{
  printf '%s\n' "${{1:-all}}" >>wait-log
  builtin wait "$@"
}}
route_probe() {{
  count=0
  [[ -f route-count ]] && count=$(cat route-count)
  count=$((count + 1))
  printf '%s' "$count" >route-count
  {route}
}}
child_command() {{
  exec {str(child_path)!r} "$1"
}}
syncthing_monitor route_probe child_command {str(timer_path)!r} {interval}
""",
            encoding="utf-8",
        )
        return path

    def start_monitor(self, wrapper: Path):
        process = subprocess.Popen(
            [BASH, str(wrapper)],
            cwd=wrapper.parent,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        self.addCleanup(cleanup_process_group, process)
        return process

    def run_monitor(self, wrapper: Path, *, timeout=5):
        process = self.start_monitor(wrapper)
        stdout, stderr = process.communicate(timeout=timeout)
        return subprocess.CompletedProcess(
            process.args, process.returncode, stdout, stderr
        )

    def assert_reaped(self, root: Path, name="child-pid"):
        pid_path = root / name
        if not pid_path.exists():
            return
        with self.assertRaises(ProcessLookupError):
            os.kill(int(pid_path.read_text()), 0)

    def assert_waited(self, root: Path, name="child-pid"):
        pid = (root / name).read_text()
        self.assertIn(pid, (root / "wait-log").read_text().splitlines())

    def test_inactive_route_never_launches_child(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            wrapper = self.wrapper(root, "return 1", "exit 0")
            result = self.run_monitor(wrapper)
            self.assertEqual(result.returncode, 0, result)
            self.assertFalse((root / "events").exists())

    def test_active_route_starts_and_reaps_successful_child(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            wrapper = self.wrapper(root, "printf 'en0\\n'", "exit 0")
            result = self.run_monitor(wrapper)
            self.assertEqual(result.returncode, 0, result)
            self.assertEqual((root / "events").read_text(), "start:en0\n")
            self.assert_reaped(root)
            self.assert_waited(root)

    def test_route_loss_terminates_and_reaps_child(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            route = "[[ $count == 1 || ! -f events ]] || return 1; printf 'en0\\n'"
            wrapper = self.wrapper(root, route, "while :; do :; done")
            result = self.run_monitor(wrapper)
            self.assertEqual(result.returncode, 0, result)
            self.assertEqual((root / "events").read_text(), "start:en0\nterm\n")
            self.assert_reaped(root)
            self.assert_waited(root)
            self.assert_waited(root, "timer-pid")

    def test_timer_failure_terminates_child_and_propagates_status(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            wrapper = self.wrapper(
                root,
                "printf 'en0\\n'",
                "while :; do :; done",
                timer="while [[ ! -f child-ready ]]; do :; done\nexit 9",
            )
            result = self.run_monitor(wrapper)
            self.assertEqual(result.returncode, 9, result)
            self.assertEqual((root / "events").read_text(), "start:en0\nterm\n")
            self.assert_reaped(root)
            self.assert_reaped(root, "timer-pid")
            self.assert_waited(root)
            self.assert_waited(root, "timer-pid")

    def test_signals_terminate_child_and_return_signal_status(self):
        for sent_signal, expected_status in (
            (signal.SIGHUP, 129),
            (signal.SIGINT, 130),
            (signal.SIGTERM, 143),
        ):
            with self.subTest(signal=sent_signal):
                with tempfile.TemporaryDirectory() as temporary_directory:
                    root = Path(temporary_directory)
                    wrapper = self.wrapper(
                        root,
                        "printf 'en0\\n'",
                        "while :; do :; done",
                        interval="30",
                    )
                    process = self.start_monitor(wrapper)
                    for _ in range(200):
                        timer_pid = root / "timer-pid"
                        if (
                            (root / "events").exists()
                            and timer_pid.exists()
                            and timer_pid.stat().st_size > 0
                        ):
                            break
                        time.sleep(0.01)
                    else:
                        process.kill()
                        self.fail("monitor did not launch its child")
                    signal_time = time.monotonic()
                    process.send_signal(sent_signal)
                    stdout, stderr = process.communicate(timeout=5)
                    self.assertLess(time.monotonic() - signal_time, 5)
                    self.assertEqual(
                        process.returncode, expected_status, (stdout, stderr)
                    )
                    self.assertEqual((root / "events").read_text(), "start:en0\nterm\n")
                    self.assert_reaped(root)
                    self.assert_reaped(root, "timer-pid")
                    self.assert_waited(root)
                    self.assert_waited(root, "timer-pid")

    def test_signal_during_async_launch_reaps_every_started_process(self):
        for launch in ("child", "timer"):
            with self.subTest(launch=launch):
                with tempfile.TemporaryDirectory() as temporary_directory:
                    root = Path(temporary_directory)
                    wrapper = self.wrapper(
                        root,
                        "printf 'en0\\n'",
                        "while :; do :; done",
                        interval="30",
                        interrupt_launch=launch,
                    )
                    result = self.run_monitor(wrapper)
                    self.assertEqual(result.returncode, 143, result)
                    self.assertEqual((root / "events").read_text(), "start:en0\nterm\n")
                    self.assert_reaped(root)
                    self.assert_waited(root)
                    if launch == "timer":
                        self.assert_reaped(root, "timer-pid")
                        self.assert_waited(root, "timer-pid")

    def test_child_failure_is_reaped_and_propagated(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            wrapper = self.wrapper(root, "printf 'en0\\n'", "exit 7")
            result = self.run_monitor(wrapper)
            self.assertEqual(result.returncode, 7, result)
            self.assertEqual((root / "events").read_text(), "start:en0\n")
            self.assert_reaped(root)
            self.assert_waited(root)


if __name__ == "__main__":
    if len(sys.argv) != 8:
        raise SystemExit(
            "usage: syncthing-runtime-check.py "
            "PREFLIGHT MONITOR-LIBRARY BASH FAKE-TOOL SLEEP "
            "WIREGUARD-WRAPPER HOME-WRAPPER"
        )
    (
        PREFLIGHT,
        MONITOR_LIBRARY,
        BASH,
        fake_tool,
        SLEEP,
        WIREGUARD_WRAPPER,
        HOME_WRAPPER,
    ) = sys.argv[1:]
    FAKE_TOOL = str(Path(fake_tool).resolve())
    unittest.main(argv=[sys.argv[0]])
