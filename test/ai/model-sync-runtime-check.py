#!/usr/bin/env python3
"""Exercise the generated model-sync activation with hermetic fake tools."""

from __future__ import annotations

import itertools
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


ABSENT = object()
FAKE_TOOLS = {
    "defaults",
    "devonthink",
    "mkdir",
    "mktemp",
    "mv",
    "pgrep",
    "rm",
    "security",
}


def preference_id(domain: str, key: str) -> str:
    return json.dumps([domain, key], separators=(",", ":"))


def normalized_default(kind: str, value: str) -> str:
    if kind == "-bool":
        return "1" if value.lower() in {"1", "true", "yes"} else "0"
    if kind == "-int":
        return str(int(value))
    return value


def cleanup_process_group(process: subprocess.Popen[str]) -> None:
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        process.communicate(timeout=1)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate()


class ModelSyncRuntimeTest(unittest.TestCase):
    script: Path
    digest: str
    fake_tool: Path
    preferences: list[dict[str, str]]

    def prepare(
        self, directory: str, initial_stamp: object = ABSENT
    ) -> tuple[Path, Path, dict[str, str]]:
        root = Path(directory)
        home = root / "home"
        state_home = root / "state"
        stamp = state_home / "nix-managed-ai" / "model-sync-v1.sha256"
        home.mkdir()
        fake_root = root / "fake"
        fake_root.mkdir()
        fake_bin = root / "fake-bin"
        fake_bin.mkdir()
        for name in FAKE_TOOLS:
            (fake_bin / name).symlink_to(self.fake_tool)
        if initial_stamp is not ABSENT:
            stamp.parent.mkdir(parents=True)
            stamp.parent.chmod(0o700)
            stamp.write_bytes(initial_stamp)
        environment = {
            key: value
            for key, value in os.environ.items()
            if key != "DRY_RUN" and not key.startswith("MODEL_SYNC_FAKE_")
        }
        environment.update(
            {
                "HOME": str(home),
                "XDG_STATE_HOME": str(state_home),
                "MODEL_SYNC_FAKE_ROOT": str(fake_root),
            }
        )
        return root, stamp, environment

    def invoke(
        self,
        root: Path,
        stamp: Path,
        environment: dict[str, str],
        *,
        send_signal: signal.Signals | None = None,
    ) -> dict[str, object]:
        if send_signal is None:
            completed = subprocess.run(
                [self.script],
                check=False,
                capture_output=True,
                cwd=root,
                env=environment,
                text=True,
                timeout=30,
            )
            returncode, stdout, stderr = (
                completed.returncode,
                completed.stdout,
                completed.stderr,
            )
        else:
            process = subprocess.Popen(
                [self.script],
                cwd=root,
                env=environment,
                start_new_session=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            try:
                ready = root / "fake" / "mv-ready"
                deadline = time.monotonic() + 10
                while (
                    not ready.exists()
                    and process.poll() is None
                    and time.monotonic() < deadline
                ):
                    time.sleep(0.01)
                if not ready.exists():
                    self.fail("model-sync did not reach the blocking stamp replacement")
                trapped_pid, tool_pid = map(
                    int, ready.read_text(encoding="utf-8").split()
                )
                os.kill(trapped_pid, send_signal)
                os.kill(tool_pid, signal.SIGKILL)
                stdout, stderr = process.communicate(timeout=10)
                returncode = process.returncode
            except BaseException:
                cleanup_process_group(process)
                raise

        fake_root = root / "fake"
        event_path = fake_root / "events.tsv"
        events = (
            [
                {"tool": fields[0], "args": fields[1:]}
                for fields in (
                    line.split("\t")
                    for line in event_path.read_text(encoding="utf-8").splitlines()
                )
            ]
            if event_path.exists()
            else []
        )
        observed_preferences = {}
        for index, item in enumerate(self.preferences, start=1):
            path = fake_root / f"preference-{index}"
            if path.exists():
                observed_preferences[preference_id(item["domain"], item["key"])] = (
                    path.read_text(encoding="utf-8")
                )
        return {
            "returncode": returncode,
            "stdout": stdout,
            "stderr": stderr,
            "events": events,
            "preferences": observed_preferences,
            "stamp": stamp.read_bytes() if stamp.is_file() else None,
            "stamp_mode": stat.S_IMODE(stamp.stat().st_mode)
            if stamp.is_file()
            else None,
            "state_mode": (
                stat.S_IMODE(stamp.parent.stat().st_mode)
                if stamp.parent.is_dir()
                else None
            ),
            "temporary_stamps": sorted(stamp.parent.glob(f"{stamp.name}.tmp.*")),
            "stamp_path": stamp,
        }

    def run_case(
        self,
        *,
        initial_stamp: object = ABSENT,
        failures: str = "",
        running: str | None = None,
        dry_run: bool = False,
        send_signal: signal.Signals | None = None,
    ) -> dict[str, object]:
        with tempfile.TemporaryDirectory() as directory:
            root, stamp, environment = self.prepare(directory, initial_stamp)
            if failures:
                environment["MODEL_SYNC_FAKE_FAILURES"] = failures
            if running is not None:
                environment["MODEL_SYNC_FAKE_RUNNING"] = running
            if dry_run:
                environment["DRY_RUN"] = ""
            return self.invoke(root, stamp, environment, send_signal=send_signal)

    def expected_preferences(self) -> dict[str, str]:
        return {
            preference_id(item["domain"], item["key"]): normalized_default(
                item["type"], item["value"]
            )
            for item in self.preferences
        }

    def expected_default_events(self) -> list[dict[str, object]]:
        events = []
        for _, group in itertools.groupby(
            self.preferences, lambda item: item["domain"]
        ):
            entries = list(group)
            events.extend(
                {
                    "tool": "defaults",
                    "args": [
                        "write",
                        item["domain"],
                        item["key"],
                        item["type"],
                        item["value"],
                    ],
                }
                for item in entries
            )
            events.extend(
                {
                    "tool": "defaults",
                    "args": ["read", item["domain"], item["key"]],
                }
                for item in entries
            )
        return events

    def assert_reconciled(self, result: dict[str, object]) -> None:
        self.assertEqual(result["returncode"], 0, result["stderr"])
        self.assertEqual(result["stdout"], "")
        self.assertEqual(result["stderr"], "")
        self.assertEqual(result["stamp"], f"{self.digest}\n".encode())
        self.assertEqual(result["stamp_mode"], 0o600)
        self.assertEqual(result["state_mode"], 0o700)
        self.assertEqual(result["temporary_stamps"], [])
        self.assertEqual(result["preferences"], self.expected_preferences())

        events = result["events"]
        self.assertEqual(
            events[:5],
            [
                {"tool": "pgrep", "args": ["-x", "DEVONthink"]},
                {"tool": "pgrep", "args": ["-x", "DEVONthink 3"]},
                {"tool": "pgrep", "args": ["-x", "iTerm2"]},
                {"tool": "devonthink", "args": []},
                {
                    "tool": "security",
                    "args": [
                        "find-generic-password",
                        "-s",
                        "iTerm2 API Keys",
                        "-a",
                        "OpenAI API Key for iTerm2",
                    ],
                },
            ],
        )
        default_events = self.expected_default_events()
        self.assertEqual(events[5 : 5 + len(default_events)], default_events)
        final_events = events[5 + len(default_events) :]
        self.assertEqual(final_events[:2], events[3:5])
        self.assertEqual(
            [event["tool"] for event in final_events[2:]],
            ["mkdir", "mktemp", "mv"],
        )

    def assert_failure(self, result: dict[str, object], message: str) -> None:
        self.assertEqual(result["returncode"], 1)
        self.assertIn(f"nix-managed model sync: {message}\n", result["stderr"])
        self.assertIsNone(result["stamp"])

    def test_dry_run_only_reports(self) -> None:
        stale = b"do-not-touch\n"
        for initial, expected, state_mode in (
            (ABSENT, None, None),
            (stale, stale, 0o700),
        ):
            with self.subTest(initial=initial):
                result = self.run_case(
                    initial_stamp=initial,
                    failures="pgrep,devonthink,security,write,read,mkdir,mktemp,mv,rm",
                    dry_run=True,
                )
                self.assertEqual(result["returncode"], 0)
                self.assertEqual(
                    result["stdout"],
                    "Would reconcile DEVONthink and iTerm2 model defaults and "
                    f"{result['stamp_path']}\n",
                )
                self.assertEqual(result["stderr"], "")
                self.assertEqual(result["stamp"], expected)
                self.assertEqual(result["state_mode"], state_mode)
                self.assertEqual(result["events"], [])

    def test_stale_stamp_states_reconcile(self) -> None:
        for initial in (ABSENT, b"", b"stale\n", f"{self.digest}\nextra\n".encode()):
            with self.subTest(initial=initial):
                self.assert_reconciled(self.run_case(initial_stamp=initial))

    def test_success_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root, stamp, environment = self.prepare(directory)
            self.assert_reconciled(self.invoke(root, stamp, environment))
            (root / "fake" / "events.tsv").unlink()
            environment["MODEL_SYNC_FAKE_FAILURES"] = (
                "pgrep,devonthink,security,write,read,mkdir,mktemp,mv,rm"
            )
            result = self.invoke(root, stamp, environment)
            self.assertEqual(result["returncode"], 0)
            self.assertEqual(result["events"], [])
            self.assertEqual(result["stamp"], f"{self.digest}\n".encode())

    def test_running_applications_defer(self) -> None:
        applications = ["DEVONthink", "DEVONthink 3", "iTerm2"]
        for index, application in enumerate(applications, start=1):
            with self.subTest(application=application):
                result = self.run_case(running=application)
                self.assertEqual(result["returncode"], 0)
                self.assertEqual(
                    result["stderr"],
                    "nix-managed model sync: deferred while DEVONthink or iTerm2 is running\n",
                )
                self.assertIsNone(result["stamp"])
                self.assertEqual(
                    [event["tool"] for event in result["events"]],
                    ["pgrep"] * index,
                )

    def test_process_probe_failure_is_fatal(self) -> None:
        result = self.run_case(failures="pgrep")
        self.assert_failure(result, "application process check failed")
        self.assertEqual(len(result["events"]), 1)

    def test_credential_probe_failures_are_fatal(self) -> None:
        cases = [
            ("devonthink:1", "DEVONthink compatible credential is missing"),
            ("security:1", "iTerm2 credential metadata is missing"),
            ("devonthink:2", "DEVONthink compatible credential metadata changed"),
            ("security:2", "iTerm2 credential metadata changed"),
        ]
        for failure, message in cases:
            with self.subTest(failure=failure):
                self.assert_failure(self.run_case(failures=failure), message)

    def test_every_preference_write_failure_is_fatal(self) -> None:
        for occurrence in range(1, len(self.preferences) + 1):
            with self.subTest(occurrence=occurrence):
                result = self.run_case(failures=f"write:{occurrence}")
                self.assert_failure(result, "preference update failed")
                writes = [
                    event
                    for event in result["events"]
                    if event["tool"] == "defaults" and event["args"][0] == "write"
                ]
                self.assertEqual(len(writes), occurrence)

    def test_every_preference_read_failure_and_mismatch_is_fatal(self) -> None:
        for failure in ("read", "mismatch"):
            for occurrence in range(1, len(self.preferences) + 1):
                with self.subTest(failure=failure, occurrence=occurrence):
                    result = self.run_case(failures=f"{failure}:{occurrence}")
                    self.assert_failure(result, "preference verification failed")
                    reads = [
                        event
                        for event in result["events"]
                        if event["tool"] == "defaults" and event["args"][0] == "read"
                    ]
                    self.assertEqual(len(reads), occurrence)

    def test_stamp_publication_failures_are_fatal(self) -> None:
        cases = [
            ("mkdir", "state directory creation failed"),
            ("mktemp", "temporary stamp creation failed"),
            ("stamp-write", "temporary stamp write failed"),
            ("mv", "stamp replacement failed"),
        ]
        for failure, message in cases:
            with self.subTest(failure=failure):
                result = self.run_case(failures=failure)
                self.assert_failure(result, message)
                self.assertEqual(result["temporary_stamps"], [])

    def test_cleanup_failure_is_reported_without_masking_primary_failure(self) -> None:
        result = self.run_case(failures="mv,rm")
        self.assert_failure(result, "stamp replacement failed")
        self.assertIn(
            "nix-managed model sync: temporary stamp cleanup failed\n",
            result["stderr"],
        )
        self.assertEqual(len(result["temporary_stamps"]), 1)

    def test_failure_preserves_previous_stamp(self) -> None:
        previous = b"previous-state\n"
        result = self.run_case(initial_stamp=previous, failures="mv")
        self.assertEqual(result["returncode"], 1)
        self.assertIn(
            "nix-managed model sync: stamp replacement failed\n", result["stderr"]
        )
        self.assertEqual(result["stamp"], previous)
        self.assertEqual(result["temporary_stamps"], [])

    def test_signals_clean_temporary_stamp(self) -> None:
        for caught, returncode in (
            (signal.SIGHUP, 129),
            (signal.SIGINT, 130),
            (signal.SIGTERM, 143),
        ):
            with self.subTest(caught=caught):
                result = self.run_case(failures="mv-block", send_signal=caught)
                self.assertEqual(result["returncode"], returncode)
                self.assertIsNone(result["stamp"])
                self.assertEqual(result["temporary_stamps"], [])
                self.assertEqual(result["events"][-1]["tool"], "rm")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(
            "usage: model-sync-runtime-check.py SCRIPT DIGEST PREFERENCES FAKE-TOOL"
        )
    ModelSyncRuntimeTest.script = Path(sys.argv[1])
    ModelSyncRuntimeTest.digest = sys.argv[2]
    ModelSyncRuntimeTest.preferences = json.loads(
        Path(sys.argv[3]).read_text(encoding="utf-8")
    )
    ModelSyncRuntimeTest.fake_tool = Path(sys.argv[4])
    unittest.main(argv=[sys.argv[0]], verbosity=2)
