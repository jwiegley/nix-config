#!/usr/bin/env python3
"""Behavioral test for source-tree-only upgrade-all sibling dispatch."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
UPGRADE_ALL = REPO / "bin/upgrade-all"


class UpgradeAllTests(unittest.TestCase):
    def run_upgrade_all(
        self, failing_stub=None, remote_status=0, delay_prerequisite=False
    ):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            script = root / "upgrade-all"
            shutil.copy2(UPGRADE_ALL, script)

            marker = root / "update-remote.ran"
            event_log = root / "events.log"
            command_log = root / "commands.log"
            sibling = root / "update-remote"
            sibling.write_text(
                f"""#!/bin/sh
printf reached >"$UPGRADE_ALL_MARKER"
printf 'remote\n' >>"$UPGRADE_ALL_EVENTS"
exit {remote_status}
""",
                encoding="utf-8",
            )
            sibling.chmod(0o755)

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            for name in ("changes", "pushme", "update-and-pull", "upgrade"):
                stub = fake_bin / name
                status = 23 if name == failing_stub else 0
                body = f'printf \'{name} %s\\n\' "$*" >>"$UPGRADE_ALL_COMMANDS"\n'
                if name == "update-and-pull":
                    body += "printf 'prerequisite-start\\n' >>\"$UPGRADE_ALL_EVENTS\"\n"
                    if delay_prerequisite:
                        body += "sleep 0.2\n"
                    body += (
                        "printf 'prerequisite-complete\\n' >>\"$UPGRADE_ALL_EVENTS\"\n"
                    )
                if name == "upgrade":
                    body += """if [ "${2:-}" = --projects-only ]; then
  printf 'projects\n' >>"$UPGRADE_ALL_EVENTS"
fi
"""
                stub.write_text(f"#!/bin/sh\n{body}exit {status}\n", encoding="utf-8")
                stub.chmod(0o755)
            path_trap = fake_bin / "update-remote"
            path_trap.write_text("#!/bin/sh\nexit 99\n", encoding="utf-8")
            path_trap.chmod(0o755)

            env = {
                "NIX_CONF": str(root),
                "PATH": f"{fake_bin}{os.pathsep}{os.environ.get('PATH', os.defpath)}",
                "UPGRADE_ALL_COMMANDS": str(command_log),
                "UPGRADE_ALL_EVENTS": str(event_log),
                "UPGRADE_ALL_MARKER": str(marker),
            }
            result = subprocess.run(
                [str(script)],
                cwd=root,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            events = event_log.read_text().splitlines() if event_log.exists() else []
            commands = (
                command_log.read_text().splitlines() if command_log.exists() else []
            )
            return result, marker.exists(), events, commands

    def test_update_remote_resolves_beside_source_script(self):
        result, marker_exists, events, commands = self.run_upgrade_all()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(marker_exists)
        self.assertEqual(
            events,
            ["prerequisite-start", "prerequisite-complete", "remote", "projects"],
        )
        self.assertFalse(any("git-ai" in command for command in commands), commands)

    def test_named_background_prerequisite_failures_stop_rollout(self):
        for stub, job in (
            ("update-and-pull", "repositories"),
            ("pushme", "shared-work-source"),
        ):
            with self.subTest(job=job):
                result, marker_exists, events, _commands = self.run_upgrade_all(
                    failing_stub=stub
                )
                self.assertEqual(result.returncode, 23, result.stdout + result.stderr)
                self.assertFalse(marker_exists)
                self.assertEqual(
                    events, ["prerequisite-start", "prerequisite-complete"]
                )
                self.assertIn(f"failed {job} (status 23)", result.stderr)

    def test_background_prerequisite_completion_is_a_rollout_barrier(self):
        result, marker_exists, events, _commands = self.run_upgrade_all(
            delay_prerequisite=True
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(marker_exists)
        self.assertLess(events.index("prerequisite-complete"), events.index("remote"))

    def test_remote_failure_is_a_barrier_before_project_maintenance(self):
        result, marker_exists, events, _commands = self.run_upgrade_all(
            remote_status=29
        )
        self.assertEqual(result.returncode, 29, result.stdout + result.stderr)
        self.assertTrue(marker_exists)
        self.assertEqual(
            events, ["prerequisite-start", "prerequisite-complete", "remote"]
        )


if __name__ == "__main__":
    unittest.main()
