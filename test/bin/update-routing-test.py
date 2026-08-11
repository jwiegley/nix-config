#!/usr/bin/env python3
"""Fast routing preflight tests for bin/update."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
UPDATE = REPO / "bin/update"


class UpdateRoutingTests(unittest.TestCase):
    def test_shared_work_switch_refuses_before_pull_or_candidate_work(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            checkout = root / "checkout"
            checkout.mkdir()
            command_log = root / "commands.log"

            stubs = {
                "git": """#!/bin/sh
printf 'git %s\n' "$*" >>"$COMMAND_LOG"
exit 1
""",
                "hostname": """#!/bin/sh
printf 'hostname %s\n' "$*" >>"$COMMAND_LOG"
printf 'andoria-08\n'
""",
            }
            for name in ("nix", "sudo", "darwin-rebuild"):
                stubs[name] = f"""#!/bin/sh
printf '{name} %s\\n' "$*" >>"$COMMAND_LOG"
exit 91
"""
            for name, body in stubs.items():
                path = fake_bin / name
                path.write_text(body, encoding="utf-8")
                path.chmod(0o755)

            result = subprocess.run(
                [str(UPDATE), "--all-inputs", "--pull", "--commit", "--switch"],
                cwd=root,
                env={
                    **os.environ,
                    "COMMAND_LOG": str(command_log),
                    "NIX_CONFIG_DIR": str(checkout),
                    "PATH": f"{fake_bin}{os.pathsep}{os.environ.get('PATH', os.defpath)}",
                    "UPDATE_AGENTS_SYSTEM_CONFIG_DIR": str(root / "absent"),
                },
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn("--switch is unsupported on shared-work hosts", result.stderr)
            self.assertIn("authoritative external Home Manager rollout", result.stderr)
            self.assertEqual(
                command_log.read_text(encoding="utf-8").splitlines(),
                ["git rev-parse --show-toplevel", "hostname -s"],
            )


if __name__ == "__main__":
    unittest.main()
