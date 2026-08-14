#!/usr/bin/env python3
"""Behavioral checks for destructive and ordered Make targets."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MAKEFILE = REPO / "Makefile"


def clean_env(**extra: str) -> dict[str, str]:
    env = dict(os.environ)
    for name in ("MAKEFLAGS", "MAKELEVEL", "MAKEOVERRIDES", "MFLAGS"):
        env.pop(name, None)
    env.update(extra)
    return env


def write_executable(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")
    path.chmod(0o755)


class MakeMaintenanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="make-safety-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.fake_bin = self.root / "bin"
        self.fake_bin.mkdir()
        self.rm_bin = self.root / "rm-bin"
        self.rm_bin.mkdir()
        self.calls = self.root / "calls.jsonl"
        self.fixture = self.root / "Makefile"
        self.fixture.write_text(f"include {MAKEFILE}\n", encoding="utf-8")

        recorder = (
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "with open(os.environ['CALLS'], 'a', encoding='utf-8') as stream:\n"
            "    stream.write(json.dumps([os.path.basename(sys.argv[0]), *sys.argv[1:]]) + '\\n')\n"
        )
        for name in ("nix", "nix-env", "nix-collect-garbage", "sudo"):
            write_executable(self.fake_bin / name, recorder)
        write_executable(self.rm_bin / "rm", recorder)

    def run_make(
        self,
        target: str,
        *,
        home: str | None = None,
        unset_home: bool = False,
        record_rm: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        self.calls.unlink(missing_ok=True)
        path = f"{self.fake_bin}{os.pathsep}{os.environ['PATH']}"
        if record_rm:
            path = f"{self.rm_bin}{os.pathsep}{path}"
        env = clean_env(
            HOME=str(self.home) if home is None else home,
            PATH=path,
            CALLS=str(self.calls),
        )
        if unset_home:
            env.pop("HOME", None)
        return subprocess.run(
            [
                "make",
                "--no-print-directory",
                "-f",
                str(self.fixture),
                target,
                "HOSTNAME=hera",
                "SYSTEM=fixture-system",
            ],
            cwd=self.root,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def recorded_calls(self) -> list[list[str]]:
        if not self.calls.exists():
            return []
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def test_check_is_read_only_and_repair_is_explicit(self) -> None:
        check = self.run_make("check")
        self.assertEqual(check.returncode, 0, check.stdout + check.stderr)
        self.assertEqual(
            self.recorded_calls(),
            [["nix", "store", "verify", "--no-trust", "--all"]],
        )

        repair = self.run_make("repair-store")
        self.assertEqual(repair.returncode, 0, repair.stdout + repair.stderr)
        self.assertEqual(
            self.recorded_calls(),
            [["nix", "store", "verify", "--no-trust", "--repair", "--all"]],
        )

    def test_retired_generation_cleanup_targets_cannot_mutate(self) -> None:
        for target in ("clean", "purge"):
            with self.subTest(target=target):
                result = self.run_make(target)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("No rule to make target", result.stderr)
                self.assertEqual(self.recorded_calls(), [])

    def test_file_named_scour_cannot_suppress_cache_deletion(self) -> None:
        shadow = self.root / "scour"
        shadow.write_text("ordinary file\n", encoding="utf-8")
        cache = self.home / ".cache" / "cargo"
        cache.mkdir(parents=True)
        (cache / "entry").write_text("cached\n", encoding="utf-8")

        result = self.run_make("scour")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(cache.exists())
        self.assertEqual(shadow.read_text(encoding="utf-8"), "ordinary file\n")

    def test_scour_rejects_missing_or_non_absolute_home_before_rm(self) -> None:
        with self.subTest(case="empty"):
            result = self.run_make("scour", home="", record_rm=True)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("HOME must be an absolute path", result.stderr)
            self.assertEqual(self.recorded_calls(), [])

        with self.subTest(case="unset"):
            result = self.run_make("scour", unset_home=True, record_rm=True)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("HOME must be an absolute path", result.stderr)
            self.assertEqual(self.recorded_calls(), [])

        with self.subTest(case="relative"):
            result = self.run_make("scour", home="relative/home", record_rm=True)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("HOME must be an absolute path", result.stderr)
            self.assertEqual(self.recorded_calls(), [])

    def test_scour_preserves_spaced_home_as_one_operand(self) -> None:
        home = self.root / "home with spaces"
        result = self.run_make("scour", home=str(home), record_rm=True)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        paths = [
            "Library/Caches/pip",
            ".cache/bun",
            ".cache/cabal",
            ".cache/cargo",
            ".cache/ccache",
            ".cache/ghcide",
            ".cache/hie-bios",
            ".cache/nix",
            ".cache/npm",
            ".cache/pnpm",
            ".cache/rustup",
            ".cache/swiftpm",
            ".cache/uv",
            ".cache/.bun",
        ]
        self.assertEqual(
            self.recorded_calls(),
            [["rm", "-fr", "--", str(home / path)] for path in paths],
        )

    def test_vps_push_uses_target_local_bash(self) -> None:
        rejecting_shell = self.root / "reject-shell"
        write_executable(rejecting_shell, "#!/bin/sh\nexit 97\n")
        self.fixture.write_text(
            f"SHELL := {rejecting_shell}\n"
            f"include {MAKEFILE}\n"
            "vps-push:\n"
            '\t@test -n "$${BASH_VERSION:-}"\n',
            encoding="utf-8",
        )

        result = self.run_make("vps-push")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class MakeUpgradeOrderingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="make-upgrade-order-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.events = self.root / "events"
        self.done = self.root / "update-done"
        (self.root / "Makefile").write_text(
            f"include {MAKEFILE}\n"
            ".PHONY: update upgrade-tasks travel-ready\n"
            "travel-ready:\n"
            "\t@:\n"
            "update:\n"
            "\t@printf 'update-start\\n' >>\"$$EVENTS\"\n"
            "\t@sleep 1\n"
            '\t@if [ "$${UPDATE_FAIL:-0}" = 1 ]; then exit 73; fi\n'
            '\t@touch "$$UPDATE_DONE"\n'
            "\t@printf 'update-done\\n' >>\"$$EVENTS\"\n"
            "upgrade-tasks:\n"
            '\t@if [ ! -f "$$UPDATE_DONE" ]; then printf \'tasks-before-update\\n\' >>"$$EVENTS"; exit 91; fi\n'
            "\t@printf 'upgrade-tasks\\n' >>\"$$EVENTS\"\n"
            '\t@if [ "$${TASKS_FAIL:-0}" = 1 ]; then exit 74; fi\n',
            encoding="utf-8",
        )

    def run_upgrade(
        self, *, update_fail: bool = False, tasks_fail: bool = False
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["make", "--no-print-directory", "upgrade"],
            cwd=self.root,
            env=clean_env(
                EVENTS=str(self.events),
                UPDATE_DONE=str(self.done),
                UPDATE_FAIL="1" if update_fail else "0",
                TASKS_FAIL="1" if tasks_fail else "0",
                MAKEFLAGS="-j8",
            ),
            capture_output=True,
            text=True,
            check=False,
        )

    def event_log(self) -> list[str]:
        if not self.events.exists():
            return []
        return self.events.read_text(encoding="utf-8").splitlines()

    def test_parallel_make_runs_upgrade_tasks_only_after_update(self) -> None:
        result = self.run_upgrade()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            self.event_log(),
            ["update-start", "update-done", "upgrade-tasks"],
        )

    def test_failed_update_prevents_upgrade_tasks(self) -> None:
        result = self.run_upgrade(update_fail=True)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.event_log(), ["update-start"])

    def test_failed_upgrade_tasks_fails_outer_upgrade(self) -> None:
        result = self.run_upgrade(tasks_fail=True)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            self.event_log(),
            ["update-start", "update-done", "upgrade-tasks"],
        )


if __name__ == "__main__":
    unittest.main()
