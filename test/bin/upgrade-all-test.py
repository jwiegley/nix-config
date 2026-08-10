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
    def run_upgrade_all(self, failing_stub=None):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            script = root / "upgrade-all"
            shutil.copy2(UPGRADE_ALL, script)

            marker = root / "update-remote.ran"
            sibling = root / "update-remote"
            sibling.write_text(
                '#!/bin/sh\nprintf reached >"$UPGRADE_ALL_MARKER"\n',
                encoding="utf-8",
            )
            sibling.chmod(0o755)

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            for name in ("changes", "pushme", "update-and-pull", "upgrade"):
                stub = fake_bin / name
                status = 23 if name == failing_stub else 0
                stub.write_text(f"#!/bin/sh\nexit {status}\n", encoding="utf-8")
                stub.chmod(0o755)
            path_trap = fake_bin / "update-remote"
            path_trap.write_text("#!/bin/sh\nexit 99\n", encoding="utf-8")
            path_trap.chmod(0o755)

            env = {
                "NIX_CONF": str(root),
                "PATH": f"{fake_bin}{os.pathsep}{os.defpath}",
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
            return result, marker.exists()

    def test_update_remote_resolves_beside_source_script(self):
        result, marker_exists = self.run_upgrade_all()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(marker_exists)

    def test_background_prerequisite_failure_stops_rollout(self):
        result, marker_exists = self.run_upgrade_all(failing_stub="update-and-pull")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(marker_exists)


if __name__ == "__main__":
    unittest.main()
