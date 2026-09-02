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


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: syncthing-runtime-check.py PREFLIGHT BASH FAKE-TOOL"
        )
    PREFLIGHT, BASH, fake_tool = sys.argv[1:]
    FAKE_TOOL = str(Path(fake_tool).resolve())
    unittest.main(argv=[sys.argv[0]])
