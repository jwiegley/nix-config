#!/usr/bin/env python3
"""Boundary and race tests for the dedicated Anvil environment cleaner."""

from __future__ import annotations

import base64
import importlib.util
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock


ACTIVE_KEYS = (
    "DIRENV_DIFF",
    "DIRENV_DIR",
    "DIRENV_FILE",
    "DIRENV_WATCHES",
    "DIRENV_DUMP_FILE_PATH",
)
GENERIC_ERROR = "anvil-mcp: cannot unload inherited direnv environment"


def load_cleaner_module():
    """Load the generated cleaner source for deterministic race injection."""
    spec = importlib.util.spec_from_file_location("anvil_clean_environment", CLEANER)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot import cleaner: {CLEANER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CleanEnvironmentTests(unittest.TestCase):
    """Exercise public boundaries plus deterministic internal race injection."""

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(
            prefix="anvil-clean-environment-"
        )
        self.root = Path(self.temporary.name)
        self.neutral = self.root / "neutral"
        self.neutral.mkdir()
        self.called = self.root / "direnv-called.json"
        self.target_ran = self.root / "target-ran"
        self.child_pid = self.root / "timeout-child.pid"
        self.fake_direnv = self.root / "fake-direnv"
        self.target = self.root / "probe-target"
        self._write_executable(
            self.fake_direnv,
            f"""#!{sys.executable}
import base64
import json
import os
from pathlib import Path
import sys
import time

called = Path(os.environ["FAKE_CALLED"])
called.write_text(json.dumps({{
    "pid": os.getpid(),
    "argv": sys.argv[1:],
    "cwd": os.getcwd(),
    "stdin": sys.stdin.buffer.read().decode("utf-8"),
    "guard_parent": os.environ.get("ANVIL_HEADLESS_PARENT_PID"),
}}))
mode = os.environ.get("FAKE_MODE", "raw")
if mode == "nonzero":
    print("direnv-secret-canary")
    print("direnv-secret-canary", file=sys.stderr)
    raise SystemExit(9)
if mode == "timeout":
    child = os.fork()
    if child == 0:
        Path(os.environ["FAKE_CHILD_PID"]).write_text(str(os.getpid()))
        time.sleep(30)
        raise SystemExit(0)
    time.sleep(30)
    raise SystemExit(0)
if mode in ("leader-zero", "leader-nonzero"):
    child = os.fork()
    if child == 0:
        for descriptor in (0, 1, 2):
            try:
                os.close(descriptor)
            except OSError:
                pass
        Path(os.environ["FAKE_CHILD_PID"]).write_text(str(os.getpid()))
        time.sleep(30)
        os._exit(0)
    deadline = time.monotonic() + 5
    while (not Path(os.environ["FAKE_CHILD_PID"]).exists()
           and time.monotonic() < deadline):
        time.sleep(0.001)
    if mode == "leader-nonzero":
        os._exit(9)
    sys.stdout.buffer.write(base64.b64decode(os.environ["FAKE_RAW_B64"]))
    sys.stdout.buffer.flush()
    os._exit(0)
if mode == "large":
    sys.stdout.buffer.write(b"x" * (4 * 1024 * 1024 + 1))
    raise SystemExit(0)
sys.stdout.buffer.write(base64.b64decode(os.environ["FAKE_RAW_B64"]))
""",
        )
        self._write_executable(
            self.target,
            f"""#!{sys.executable}
import json
import os
from pathlib import Path
import signal
import sys

Path(os.environ["FAKE_TARGET_RAN"]).write_text("ran")
keys = [
    "BASELINE",
    "PROJECT_ONLY",
    "PATH",
    "DIRENV_CONFIG",
    "DIRENV_BASH",
    "DIRENV_DEBUG",
    *{ACTIVE_KEYS!r},
]
print(json.dumps({{
    "pid": os.getpid(),
    "stdin": sys.stdin.buffer.read().decode("utf-8"),
    "env": {{key: os.environ.get(key) for key in keys}},
    "sighup_ignored": signal.getsignal(signal.SIGHUP) == signal.SIG_IGN,
}}))
""",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def _write_executable(path: Path, content: str) -> None:
        path.write_text(content)
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def base_environment(self) -> dict[str, str]:
        environment = os.environ.copy()
        for name in ACTIVE_KEYS:
            environment.pop(name, None)
        environment.update(
            {
                "FAKE_CALLED": str(self.called),
                "FAKE_CHILD_PID": str(self.child_pid),
                "FAKE_TARGET_RAN": str(self.target_ran),
                "FAKE_MODE": "raw",
                "FAKE_RAW_B64": base64.b64encode(b"{}").decode("ascii"),
                "DIRENV_CONFIG": "/preserved/config",
                "DIRENV_BASH": "/preserved/bash",
                "DIRENV_DEBUG": "preserved-debug",
            }
        )
        return environment

    def sanitizer_command(
        self,
        *,
        target: Path | None = None,
        timeout: str = "30",
        direnv: Path | None = None,
    ) -> list[str]:
        return [
            sys.executable,
            "-I",
            CLEANER,
            "--direnv",
            str(direnv or self.fake_direnv),
            "--parent-guard",
            PARENT_GUARD,
            "--neutral",
            str(self.neutral),
            "--timeout-seconds",
            timeout,
            "--",
            str(target or self.target),
        ]

    def cleanup_fixture_process(
        self, process: subprocess.Popen[bytes]
    ) -> None:
        """Best-effort bounded cleanup for one test-owned wrapper tree."""
        fixture_pids: list[int] = []
        try:
            if self.called.exists():
                fixture_pids.append(
                    int(json.loads(self.called.read_text())["pid"])
                )
            if self.child_pid.exists():
                fixture_pids.append(int(self.child_pid.read_text()))
        except (KeyError, OSError, TypeError, ValueError, json.JSONDecodeError):
            pass
        for pid in fixture_pids:
            if self.process_is_running(pid):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    pass
        for stream in (process.stdin, process.stdout, process.stderr):
            if stream is not None and not stream.closed:
                stream.close()

    def invoke(
        self,
        environment: dict[str, str],
        *,
        input_bytes: bytes = b"",
        target: Path | None = None,
        timeout: str = "30",
        direnv: Path | None = None,
        ignore_sighup: bool = False,
    ) -> tuple[subprocess.CompletedProcess[bytes], int]:
        command = self.sanitizer_command(
            target=target, timeout=timeout, direnv=direnv
        )

        def set_ignored_sighup() -> None:
            signal.signal(signal.SIGHUP, signal.SIG_IGN)

        process = subprocess.Popen(
            command,
            env=environment,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            preexec_fn=set_ignored_sighup if ignore_sighup else None,
        )
        pid = process.pid
        try:
            stdout, stderr = process.communicate(input=input_bytes, timeout=60)
        except BaseException:
            self.cleanup_fixture_process(process)
            raise
        return (
            subprocess.CompletedProcess(command, process.returncode, stdout, stderr),
            pid,
        )

    def assert_generic_failure(
        self, completed: subprocess.CompletedProcess[bytes]
    ) -> None:
        self.assertEqual(completed.returncode, 70)
        self.assertEqual(completed.stdout, b"")
        self.assertEqual(
            completed.stderr, (GENERIC_ERROR + "\n").encode("utf-8")
        )
        self.assertFalse(self.target_ran.exists())

    def active_environment(self) -> dict[str, str]:
        environment = self.base_environment()
        environment.update(
            {
                "BASELINE": "project-overwrite",
                "PROJECT_ONLY": "direnv-secret-canary",
                "PATH": "/project/bin:/baseline/bin",
                "DIRENV_DIFF": "encoded-real-diff",
                "DIRENV_DIR": "-/project",
                "DIRENV_FILE": "/project/.envrc",
                "DIRENV_WATCHES": "encoded-watches",
                "DIRENV_DUMP_FILE_PATH": "/project/dump",
            }
        )
        return environment

    def install_patch(
        self, environment: dict[str, str], patch: object
    ) -> None:
        raw = json.dumps(patch).encode("utf-8")
        environment["FAKE_RAW_B64"] = base64.b64encode(raw).decode("ascii")

    def test_no_context_execs_without_invoking_direnv(self) -> None:
        environment = self.base_environment()
        environment.update({"BASELINE": "clean", "PATH": "/baseline/bin"})
        completed, launch_pid = self.invoke(
            environment,
            input_bytes=b"mcp-input",
            direnv=self.root / "missing-direnv",
            ignore_sighup=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertFalse(self.called.exists())
        result = json.loads(completed.stdout)
        self.assertEqual(result["pid"], launch_pid)
        self.assertEqual(result["stdin"], "mcp-input")
        self.assertEqual(result["env"]["BASELINE"], "clean")
        self.assertEqual(result["env"]["PATH"], "/baseline/bin")
        self.assertTrue(result["sighup_ignored"])
        self.assertEqual(
            [
                result["env"]["DIRENV_CONFIG"],
                result["env"]["DIRENV_BASH"],
                result["env"]["DIRENV_DEBUG"],
            ],
            ["/preserved/config", "/preserved/bash", "preserved-debug"],
        )

    def test_active_context_restores_baseline_and_preserves_stdio_pid(self) -> None:
        environment = self.active_environment()
        patch: dict[str, str | None] = {
            "BASELINE": "clean-baseline",
            "PROJECT_ONLY": None,
            "PATH": "/baseline/bin",
        }
        patch.update({name: None for name in ACTIVE_KEYS})
        self.install_patch(environment, patch)
        completed, launch_pid = self.invoke(
            environment, input_bytes=b'{"jsonrpc":"2.0"}'
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads(completed.stdout)
        self.assertEqual(result["pid"], launch_pid)
        self.assertEqual(result["stdin"], '{"jsonrpc":"2.0"}')
        self.assertEqual(result["env"]["BASELINE"], "clean-baseline")
        self.assertIsNone(result["env"]["PROJECT_ONLY"])
        self.assertEqual(result["env"]["PATH"], "/baseline/bin")
        self.assertTrue(all(result["env"][name] is None for name in ACTIVE_KEYS))
        self.assertEqual(
            [
                result["env"]["DIRENV_CONFIG"],
                result["env"]["DIRENV_BASH"],
                result["env"]["DIRENV_DEBUG"],
            ],
            ["/preserved/config", "/preserved/bash", "preserved-debug"],
        )
        invocation = json.loads(self.called.read_text())
        self.assertEqual(invocation["argv"], ["export", "json"])
        self.assertEqual(Path(invocation["cwd"]).resolve(), self.neutral.resolve())
        self.assertEqual(invocation["stdin"], "")
        self.assertIsNone(invocation["guard_parent"])

    def test_exited_direnv_leader_cannot_abandon_descendants(self) -> None:
        for mode in ("leader-zero", "leader-nonzero"):
            with self.subTest(mode=mode):
                self.called.unlink(missing_ok=True)
                self.child_pid.unlink(missing_ok=True)
                self.target_ran.unlink(missing_ok=True)
                environment = self.active_environment()
                environment["FAKE_MODE"] = mode
                patch: dict[str, str | None] = {
                    name: None for name in ACTIVE_KEYS
                }
                self.install_patch(environment, patch)
                completed, _ = self.invoke(environment)
                if mode == "leader-zero":
                    self.assertEqual(completed.returncode, 0, completed.stderr)
                    self.assertTrue(self.target_ran.exists())
                else:
                    self.assert_generic_failure(completed)
                self.assertTrue(self.child_pid.exists())
                child = int(self.child_pid.read_text())
                deadline = time.monotonic() + 3
                while self.process_is_running(child) and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertFalse(
                    self.process_is_running(child),
                    "direnv descendant escaped guarded cleanup",
                )

    def test_partial_context_fails_before_direnv_or_target(self) -> None:
        for name in ACTIVE_KEYS:
            with self.subTest(name=name):
                self.called.unlink(missing_ok=True)
                self.target_ran.unlink(missing_ok=True)
                environment = self.base_environment()
                environment[name] = "partial"
                if name == "DIRENV_DIFF":
                    environment[name] = ""
                completed, _ = self.invoke(environment)
                self.assert_generic_failure(completed)
                self.assertFalse(self.called.exists())

    def test_invalid_or_incomplete_exports_fail_closed(self) -> None:
        invalid_documents = {
            "empty": b"",
            "syntax": b"not-json",
            "null": b"null",
            "list": b"[]",
            "number-value": b'{"X": 1}',
            "empty-key": b'{"": null}',
            "equals-key": b'{"A=B": null}',
            "nul-key": b'{"A\\u0000B": null}',
            "nul-value": b'{"A": "B\\u0000C"}',
            "duplicate": b'{"X": null, "X": "again"}',
            "context-remains": b"{}",
        }
        for label, document in invalid_documents.items():
            with self.subTest(label=label):
                self.called.unlink(missing_ok=True)
                self.target_ran.unlink(missing_ok=True)
                environment = self.active_environment()
                environment["FAKE_RAW_B64"] = base64.b64encode(document).decode(
                    "ascii"
                )
                completed, _ = self.invoke(environment)
                self.assert_generic_failure(completed)
                self.assertTrue(self.called.exists())

    def test_nonzero_and_oversized_output_are_redacted(self) -> None:
        for mode in ("nonzero", "large"):
            with self.subTest(mode=mode):
                self.called.unlink(missing_ok=True)
                self.target_ran.unlink(missing_ok=True)
                environment = self.active_environment()
                environment["FAKE_MODE"] = mode
                completed, _ = self.invoke(environment)
                self.assert_generic_failure(completed)
                self.assertNotIn(b"direnv-secret-canary", completed.stderr)

    def test_timeout_kills_the_direnv_process_group(self) -> None:
        environment = self.active_environment()
        environment["FAKE_MODE"] = "timeout"
        completed, _ = self.invoke(environment, timeout="5")
        self.assert_generic_failure(completed)
        deadline = time.monotonic() + 3
        while not self.child_pid.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(self.child_pid.exists())
        child = int(self.child_pid.read_text())
        while self.process_is_running(child) and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertFalse(self.process_is_running(child))

    def test_external_sigterm_reaps_the_export_group(self) -> None:
        environment = self.active_environment()
        environment["FAKE_MODE"] = "timeout"
        process = subprocess.Popen(
            self.sanitizer_command(timeout="30"),
            env=environment,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        cleanup_required = True

        def cleanup_owned_group() -> None:
            if cleanup_required:
                self.cleanup_fixture_process(process)

        self.addCleanup(cleanup_owned_group)
        try:
            deadline = time.monotonic() + 30
            while (
                (not self.called.exists() or not self.child_pid.exists())
                and time.monotonic() < deadline
            ):
                time.sleep(0.01)
            self.assertTrue(self.called.exists())
            self.assertTrue(self.child_pid.exists())
            leader = json.loads(self.called.read_text())["pid"]
            child = int(self.child_pid.read_text())

            process.terminate()
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, -signal.SIGTERM)
            self.assertEqual(stdout, b"")
            self.assertEqual(stderr, b"")
            self.assertFalse(self.target_ran.exists())

            deadline = time.monotonic() + 3
            while (
                (self.process_is_running(leader) or self.process_is_running(child))
                and time.monotonic() < deadline
            ):
                time.sleep(0.02)
            self.assertFalse(self.process_is_running(leader))
            self.assertFalse(self.process_is_running(child))
            cleanup_required = False
        finally:
            cleanup_owned_group()

    @staticmethod
    def process_is_running(pid: int) -> bool:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        if sys.platform.startswith("linux"):
            try:
                stat_line = Path(f"/proc/{pid}/stat").read_text()
            except (FileNotFoundError, ProcessLookupError):
                return False
            close = stat_line.rfind(")")
            fields = stat_line[close + 1 :].split() if close >= 0 else []
            return bool(fields) and fields[0] != "Z"
        status = subprocess.run(
            ["/bin/ps", "-o", "stat=", "-p", str(pid)],
            check=False,
            capture_output=True,
            text=True,
        ).stdout.strip()
        return bool(status) and not status.startswith("Z")

    def capture_main_termination(
        self, module, *, during_install: bool
    ) -> tuple[object, dict[int, object], int]:
        """Run main with a deterministic signal in one publication window."""

        class CapturedTermination(BaseException):
            pass

        saved_argv = sys.argv
        saved_mask = signal.pthread_sigmask(signal.SIG_BLOCK, set())
        saved_handlers = {
            int(signum): signal.getsignal(signum)
            for signum in module.TERMINATION_SIGNALS
        }
        real_signal = signal.signal
        published = 0
        captured: list[tuple[object, dict[int, object]]] = []

        def signal_after_first_publication(signum, handler):
            nonlocal published
            result = real_signal(signum, handler)
            if handler is module.termination_handler:
                published += 1
                if published == 1:
                    os.kill(os.getpid(), signal.SIGTERM)
            return result

        def signal_during_print(*_args, **_kwargs) -> None:
            os.kill(os.getpid(), signal.SIGTERM)

        def capture_termination(request, originals) -> None:
            captured.append((request, originals))
            raise CapturedTermination

        try:
            signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGTERM})
            real_signal(signal.SIGTERM, signal.SIG_DFL)
            sys.argv = [CLEANER]
            with mock.patch.object(
                module,
                "terminate_after_cleanup",
                side_effect=capture_termination,
            ):
                if during_install:
                    context = mock.patch.object(
                        module.signal,
                        "signal",
                        side_effect=signal_after_first_publication,
                    )
                else:
                    context = mock.patch(
                        "builtins.print", side_effect=signal_during_print
                    )
                with context, self.assertRaises(CapturedTermination):
                    module.main()
        finally:
            sys.argv = saved_argv
            for numeric, handler in saved_handlers.items():
                real_signal(numeric, handler)
            signal.pthread_sigmask(signal.SIG_SETMASK, saved_mask)
        self.assertEqual(len(captured), 1)
        request, originals = captured[0]
        return request, originals, published

    def test_signal_during_handler_installation_uses_outer_boundary(self) -> None:
        module = load_cleaner_module()
        request, originals, published = self.capture_main_termination(
            module, during_install=True
        )
        self.assertEqual(request.signum, signal.SIGTERM)
        self.assertGreaterEqual(published, 1)
        self.assertIn(int(signal.SIGTERM), originals)

    def test_signal_during_failure_reporting_uses_outer_boundary(self) -> None:
        module = load_cleaner_module()
        request, originals, published = self.capture_main_termination(
            module, during_install=False
        )
        self.assertEqual(request.signum, signal.SIGTERM)
        self.assertEqual(published, 0)
        self.assertIn(int(signal.SIGTERM), originals)

    def test_signal_during_spawn_publication_reaps_exact_child(self) -> None:
        module = load_cleaner_module()
        handled = tuple(module.TERMINATION_SIGNALS)
        previous_handlers = {
            signum: signal.getsignal(signum) for signum in handled
        }
        previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, set())
        real_popen = module.subprocess.Popen
        spawned = None
        descendant = None

        def signal_after_spawn(*args, **kwargs):
            nonlocal spawned, descendant
            spawned = real_popen(*args, **kwargs)
            deadline = time.monotonic() + 30
            while (
                (not self.called.exists() or not self.child_pid.exists())
                and time.monotonic() < deadline
            ):
                time.sleep(0.01)
            if not self.called.exists() or not self.child_pid.exists():
                raise AssertionError("fake direnv did not publish its process tree")
            descendant = int(self.child_pid.read_text())
            os.kill(os.getpid(), signal.SIGTERM)
            return spawned

        environment = self.active_environment()
        environment["FAKE_MODE"] = "timeout"
        leaked_leader = False
        leaked_descendant = False
        try:
            _originals, installation_mask = (
                module.install_termination_handlers()
            )
            module.restore_signal_mask(installation_mask)
            with mock.patch.object(
                module.subprocess, "Popen", side_effect=signal_after_spawn
            ):
                with self.assertRaises(module.TerminationRequested):
                    module.read_bounded_export(
                        str(self.fake_direnv),
                        PARENT_GUARD,
                        str(self.neutral),
                        30,
                        environment,
                    )
            self.assertIsNotNone(spawned)
            self.assertIsNotNone(descendant)
            deadline = time.monotonic() + 3
            while (
                (
                    spawned.poll() is None
                    or self.process_is_running(descendant)
                )
                and time.monotonic() < deadline
            ):
                time.sleep(0.02)
            leaked_leader = spawned.poll() is None
            leaked_descendant = self.process_is_running(descendant)
        finally:
            for signum, handler in previous_handlers.items():
                signal.signal(signum, handler)
            signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
            if spawned is not None:
                if spawned.poll() is None:
                    # The exact Popen leader is still live and unreaped, so its
                    # private process-group identity cannot have been recycled.
                    try:
                        os.killpg(spawned.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    try:
                        spawned.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        spawned.kill()
                        try:
                            spawned.wait(timeout=2)
                        except subprocess.TimeoutExpired:
                            pass
                if spawned.stdout is not None and not spawned.stdout.closed:
                    spawned.stdout.close()
            if descendant is not None and self.process_is_running(descendant):
                try:
                    os.kill(descendant, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        self.assertFalse(leaked_leader, "spawned direnv leader escaped custody")
        self.assertFalse(
            leaked_descendant, "spawned direnv descendant escaped group custody"
        )

    def test_cleanup_reap_waits_are_bounded(self) -> None:
        module = load_cleaner_module()
        process = mock.Mock()
        process.pid = 2**30
        process.returncode = None
        process.wait.side_effect = [
            subprocess.TimeoutExpired(["direnv"], 2),
            subprocess.TimeoutExpired(["direnv"], 2),
        ]
        with mock.patch.object(
            module.os, "killpg", side_effect=ProcessLookupError
        ):
            with self.assertRaisesRegex(
                module.SanitizerError, "export cleanup timeout"
            ):
                module.kill_process_group(process)
        self.assertEqual(
            process.wait.call_args_list,
            [
                mock.call(timeout=module.CLEANUP_WAIT_SECONDS),
                mock.call(timeout=module.CLEANUP_WAIT_SECONDS),
            ],
        )
        process.kill.assert_called_once_with()

    def test_exec_failure_is_generic(self) -> None:
        environment = self.base_environment()
        missing = self.root / "missing-target"
        completed, _ = self.invoke(environment, target=missing)
        self.assert_generic_failure(completed)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(
            "usage: clean-environment-test.py CLEANER PARENT_GUARD"
        )
    PARENT_GUARD = str(Path(sys.argv.pop()).resolve())
    CLEANER = str(Path(sys.argv.pop()).resolve())
    unittest.main()
