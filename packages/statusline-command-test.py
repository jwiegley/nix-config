#!/usr/bin/env python3

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STATUSLINE = ROOT / "config/ai/statusline-command.sh"


def fixture(project_dir: Path) -> dict:
    return {
        "workspace": {"project_dir": str(project_dir)},
        "model": {"display_name": "Test"},
        "context_window": {
            "used_percentage": 0,
            "total_input_tokens": 0,
            "total_output_tokens": 0,
            "current_usage": {
                "cache_read_input_tokens": 0,
                "input_tokens": 1,
                "cache_creation_input_tokens": 0,
            },
        },
        "rate_limits": {
            "five_hour": {"used_percentage": 0},
            "seven_day": {"used_percentage": 0},
        },
        "cost": {
            "total_lines_added": 0,
            "total_lines_removed": 0,
            "total_api_duration_ms": 0,
            "total_cost_usd": 0,
        },
    }


def run_statusline(
    payload: dict, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(STATUSLINE)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=False,
        env=env,
    )


class StatuslineCommandTest(unittest.TestCase):
    def test_json_values_are_not_awk_program_text(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            project_dir = Path(temporary_directory)
            marker = project_dir / "awk-code-executed"
            payload = fixture(project_dir)
            hostile_numeric = f'0; system("touch {marker.as_posix()}")'
            payload["cost"]["total_api_duration_ms"] = hostile_numeric
            payload["cost"]["total_cost_usd"] = hostile_numeric

            completed = run_statusline(payload)

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertFalse(marker.exists(), completed.stderr)

    def test_invokes_jq_once(self) -> None:
        real_jq = shutil.which("jq")
        self.assertIsNotNone(real_jq)

        with tempfile.TemporaryDirectory() as temporary_directory:
            project_dir = Path(temporary_directory)
            count_file = project_dir / "jq-count"
            count_file.write_text("0\n")
            jq_wrapper = project_dir / "jq"
            jq_wrapper.write_text(
                "#!/bin/bash\n"
                'count=$(<"$JQ_COUNT_FILE")\n'
                'printf "%s\\n" "$((count + 1))" > "$JQ_COUNT_FILE"\n'
                'exec "$REAL_JQ" "$@"\n'
            )
            jq_wrapper.chmod(0o755)
            env = os.environ.copy()
            env.update(
                {
                    "JQ_COUNT_FILE": str(count_file),
                    "PATH": f"{project_dir}{os.pathsep}{env['PATH']}",
                    "REAL_JQ": real_jq,
                }
            )

            completed = run_statusline(fixture(project_dir), env)

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(count_file.read_text().strip(), "1")

    def test_malformed_numeric_fields_coerce_to_zero(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            payload = fixture(Path(temporary_directory))
            payload["context_window"]["total_input_tokens"] = "not-a-number"
            payload["context_window"]["total_output_tokens"] = "also-not-a-number"
            payload["cost"]["total_api_duration_ms"] = "broken"
            payload["cost"]["total_cost_usd"] = "broken"

            completed = run_statusline(payload)

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(completed.stderr, "")
            self.assertIn("| ↓0 ↑0 |", completed.stdout)
            self.assertTrue(completed.stdout.rstrip().endswith("| 0s"))


if __name__ == "__main__":
    unittest.main()
