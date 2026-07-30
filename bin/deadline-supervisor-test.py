#!/usr/bin/env python3

import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


SUPERVISOR = Path(__file__).with_name("deadline-supervisor.py")


def process_exists(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


class DeadlineSupervisorTests(unittest.TestCase):
    def run_supervisor(self, *command, term_after="0.2", kill_after="0.2"):
        return subprocess.run(
            [
                sys.executable,
                str(SUPERVISOR),
                "--term-after",
                term_after,
                "--kill-after",
                kill_after,
                "--",
                *command,
            ],
            capture_output=True,
            text=True,
            check=False,
            timeout=3,
        )

    def test_success_propagates_status(self):
        result = self.run_supervisor(sys.executable, "-c", "raise SystemExit(7)")
        self.assertEqual(result.returncode, 7, result.stderr)

    def test_signalled_status_uses_shell_convention(self):
        result = self.run_supervisor(
            sys.executable,
            "-c",
            "import os,signal; os.kill(os.getpid(), signal.SIGTERM)",
        )
        self.assertEqual(result.returncode, 143, result.stderr)

    def test_term_ignoring_group_is_killed_without_orphans(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            pid_path = Path(temp_dir) / "child.pid"
            child = (
                "import signal,time; "
                "signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)"
            )
            parent = (
                "import pathlib,signal,subprocess,sys,time; "
                "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                f"p=subprocess.Popen([sys.executable,'-c',{child!r}]); "
                f"pathlib.Path({str(pid_path)!r}).write_text(str(p.pid)); "
                "time.sleep(30)"
            )
            started = time.monotonic()
            result = self.run_supervisor(sys.executable, "-c", parent)
            elapsed = time.monotonic() - started
            self.assertEqual(result.returncode, 137, result.stderr)
            self.assertLess(elapsed, 2)
            child_pid = int(pid_path.read_text())
            for _attempt in range(50):
                if not process_exists(child_pid):
                    break
                time.sleep(0.02)
            self.assertFalse(process_exists(child_pid), "descendant survived deadline")

    def test_cooperative_group_returns_timeout_status(self):
        result = self.run_supervisor(sys.executable, "-c", "import time; time.sleep(30)")
        self.assertEqual(result.returncode, 124, result.stderr)

    def test_early_exit_with_background_child_is_failure_and_cleanup(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            pid_path = Path(temp_dir) / "child.pid"
            parent = (
                "import pathlib,subprocess,sys; "
                "p=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); "
                f"pathlib.Path({str(pid_path)!r}).write_text(str(p.pid))"
            )
            result = self.run_supervisor(sys.executable, "-c", parent)
            self.assertEqual(result.returncode, 125, result.stderr)
            child_pid = int(pid_path.read_text())
            for _attempt in range(50):
                if not process_exists(child_pid):
                    break
                time.sleep(0.02)
            self.assertFalse(process_exists(child_pid), "background child survived")

    def test_external_term_and_hup_clean_the_owned_process_group(self):
        for sig in (signal.SIGTERM, signal.SIGHUP):
            with self.subTest(signal=sig), tempfile.TemporaryDirectory() as temp_dir:
                pid_path = Path(temp_dir) / "child.pid"
                child = (
                    "import signal,time; "
                    "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                    "signal.signal(signal.SIGHUP, signal.SIG_IGN); time.sleep(30)"
                )
                command = (
                    "import pathlib,signal,subprocess,sys,time; "
                    "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                    "signal.signal(signal.SIGHUP, signal.SIG_IGN); "
                    f"p=subprocess.Popen([sys.executable,'-c',{child!r}]); "
                    f"pathlib.Path({str(pid_path)!r}).write_text(str(p.pid)); "
                    "time.sleep(30)"
                )
                supervisor = subprocess.Popen(
                    [
                        sys.executable,
                        str(SUPERVISOR),
                        "--term-after",
                        "30",
                        "--kill-after",
                        "0.2",
                        "--",
                        sys.executable,
                        "-c",
                        command,
                    ],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                for _attempt in range(100):
                    if pid_path.exists():
                        break
                    time.sleep(0.02)
                self.assertTrue(pid_path.exists(), "child PID was never published")
                os.kill(supervisor.pid, sig)
                _stdout, stderr = supervisor.communicate(timeout=3)
                self.assertEqual(supervisor.returncode, 128 + sig, stderr)
                child_pid = int(pid_path.read_text())
                for _attempt in range(50):
                    if not process_exists(child_pid):
                        break
                    time.sleep(0.02)
                self.assertFalse(process_exists(child_pid), "signal left child alive")

    def test_nonfinite_deadlines_refuse(self):
        for value in ("nan", "inf", "-inf", "1e309"):
            with self.subTest(value=value):
                result = subprocess.run(
                    [
                        sys.executable,
                        str(SUPERVISOR),
                        f"--term-after={value}",
                        "--kill-after",
                        "1",
                        "--",
                        sys.executable,
                        "-c",
                        "pass",
                    ],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 2)
                self.assertIn("positive and finite", result.stderr)


if __name__ == "__main__":
    unittest.main()
