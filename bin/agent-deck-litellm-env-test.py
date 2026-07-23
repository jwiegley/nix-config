#!/usr/bin/env python3

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


WRAPPER = Path(__file__).with_name("agent-deck-litellm-env")
SYNTHETIC_SECRET = "synthetic-litellm-secret"


def write_executable(path: Path, content: str) -> None:
    path.write_text(content)
    path.chmod(0o700)


class AgentDeckLiteLLMEnvTests(unittest.TestCase):
    def test_exports_first_password_line_without_exposing_it(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pass_bin = root / "pass"
            target_bin = root / "target"
            argv_path = root / "argv"
            env_path = root / "env"

            write_executable(
                pass_bin,
                f"""#!/usr/bin/env bash
set -euo pipefail
[[ $# == 1 && $1 == litellm.vulcan.lan ]]
printf '%s\\n' '{SYNTHETIC_SECRET}' 'ignored-line'
""",
            )
            write_executable(
                target_bin,
                """#!/usr/bin/env bash
set -euo pipefail
printf '%s\\0' "$@" >"$CAPTURE_ARGV"
printf '%s' "$LITELLM_API_KEY" >"$CAPTURE_ENV"
""",
            )

            result = subprocess.run(
                [str(WRAPPER), str(target_bin), "first", "second value"],
                capture_output=True,
                text=True,
                env={
                    **os.environ,
                    "AGENT_DECK_LITELLM_PASS_BIN": str(pass_bin),
                    "CAPTURE_ARGV": str(argv_path),
                    "CAPTURE_ENV": str(env_path),
                },
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(env_path.read_text(), SYNTHETIC_SECRET)
            self.assertEqual(
                [item.decode() for item in argv_path.read_bytes().split(b"\0") if item],
                ["first", "second value"],
            )
            self.assertNotIn(SYNTHETIC_SECRET, result.stdout)
            self.assertNotIn(SYNTHETIC_SECRET, result.stderr)
            self.assertNotIn(SYNTHETIC_SECRET, argv_path.read_text())

    def test_empty_credential_fails_before_running_command(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pass_bin = root / "pass"
            target_bin = root / "target"
            invoked_path = root / "invoked"

            write_executable(pass_bin, "#!/usr/bin/env bash\nexit 0\n")
            write_executable(
                target_bin,
                f"#!/usr/bin/env bash\n: >'{invoked_path}'\n",
            )

            result = subprocess.run(
                [str(WRAPPER), str(target_bin)],
                capture_output=True,
                text=True,
                env={
                    **os.environ,
                    "AGENT_DECK_LITELLM_PASS_BIN": str(pass_bin),
                },
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(invoked_path.exists())
            self.assertIn("credential is unavailable or empty", result.stderr)

    def test_requires_a_command(self):
        result = subprocess.run(
            [str(WRAPPER)],
            capture_output=True,
            text=True,
            env=os.environ,
            check=False,
        )

        self.assertEqual(result.returncode, 2)
        self.assertIn("command is required", result.stderr)


if __name__ == "__main__":
    unittest.main()
