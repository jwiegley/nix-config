#!/usr/bin/env python3
"""Behavioral tests for the Codex credential-only launcher."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


WRAPPER = Path(__file__).with_name("codex-env")
REF_SECRET = "synthetic-ref-secret"
PERPLEXITY_SECRET = "synthetic-perplexity-secret"


class CodexEnvTests(unittest.TestCase):
    def test_forwards_arguments_and_exports_only_mcp_credentials(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            captured_args = root / "args"
            captured_env = root / "env"
            pass_bin = root / "pass"
            codex_bin = root / "codex"
            pass_bin.write_text(
                "#!/bin/sh\n"
                "case $1 in\n"
                f"  api.ref.tools) printf '%s\\n' '{REF_SECRET}' ;;\n"
                f"  api.perplexity.ai) printf '%s\\n' '{PERPLEXITY_SECRET}' ;;\n"
                "  *) exit 1 ;;\n"
                "esac\n"
            )
            codex_bin.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$@\" >\"$CAPTURE_ARGS\"\n"
                "printf '%s\\n' \"$REF_API_KEY\" \"$PERPLEXITY_API_KEY\" >\"$CAPTURE_ENV\"\n"
            )
            pass_bin.chmod(0o755)
            codex_bin.chmod(0o755)
            env = os.environ.copy()
            env.update(
                {
                    "CAPTURE_ARGS": str(captured_args),
                    "CAPTURE_ENV": str(captured_env),
                    "CODEX_ENV_PASS_BIN": str(pass_bin),
                    "CODEX_ENV_REAL_CODEX": str(codex_bin),
                }
            )

            result = subprocess.run(
                [str(WRAPPER), "exec", "--profile", "omlx", "hello"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(
                captured_args.read_text().splitlines(),
                ["exec", "--profile", "omlx", "hello"],
            )
            self.assertEqual(
                captured_env.read_text().splitlines(),
                [REF_SECRET, PERPLEXITY_SECRET],
            )
            combined = result.stdout + result.stderr + captured_args.read_text()
            self.assertNotIn(REF_SECRET, combined)
            self.assertNotIn(PERPLEXITY_SECRET, combined)

    def test_missing_credential_refuses_before_codex(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            marker = root / "ran"
            pass_bin = root / "pass"
            codex_bin = root / "codex"
            pass_bin.write_text("#!/bin/sh\nexit 1\n")
            codex_bin.write_text(f"#!/bin/sh\ntouch {marker}\n")
            pass_bin.chmod(0o755)
            codex_bin.chmod(0o755)
            env = os.environ.copy()
            env.update(
                {
                    "CODEX_ENV_PASS_BIN": str(pass_bin),
                    "CODEX_ENV_REAL_CODEX": str(codex_bin),
                }
            )

            result = subprocess.run(
                [str(WRAPPER)], env=env, capture_output=True, text=True, check=False
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("credential is unavailable or empty", result.stderr)
            self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
