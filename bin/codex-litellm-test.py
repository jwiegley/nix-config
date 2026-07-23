#!/usr/bin/env python3

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


WRAPPER = Path(__file__).with_name("codex-litellm")
SYNTHETIC_LITELLM_SECRET = "synthetic-litellm-secret"
SYNTHETIC_REF_SECRET = "synthetic-ref-secret"


def write_executable(path: Path, content: str) -> None:
    path.write_text(content)
    path.chmod(0o700)


class CodexLiteLLMTests(unittest.TestCase):
    def test_routes_through_litellm_without_putting_secret_in_argv_or_output(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pass_bin = root / "pass"
            codex_bin = root / "codex-real"
            argv_path = root / "argv"
            env_path = root / "env"
            invoked_path = root / "invoked"

            write_executable(
                pass_bin,
                f"""#!/usr/bin/env bash
case "$1" in
  litellm.vulcan.lan)
    printf '%s\\n' '{SYNTHETIC_LITELLM_SECRET}' 'ignored-line'
    ;;
  api.ref.tools)
    printf '%s\\n' '{SYNTHETIC_REF_SECRET}' 'ignored-line'
    ;;
  *)
    exit 1
    ;;
esac
""",
            )
            write_executable(
                codex_bin,
                """#!/usr/bin/env bash
set -euo pipefail
printf '%s\\0' "$@" >"$CAPTURE_ARGV"
printf '%s\\n%s' "$LITELLM_API_KEY" "$REF_API_KEY" >"$CAPTURE_ENV"
: >"$CAPTURE_INVOKED"
""",
            )

            env = {
                **os.environ,
                "CODEX_LITELLM_PASS_BIN": str(pass_bin),
                "CODEX_LITELLM_REAL_CODEX": str(codex_bin),
                "CAPTURE_ARGV": str(argv_path),
                "CAPTURE_ENV": str(env_path),
                "CAPTURE_INVOKED": str(invoked_path),
            }
            result = subprocess.run(
                [
                    str(WRAPPER),
                    "exec",
                    "-m",
                    "gpt-5.6-sol",
                    "-c",
                    'model_reasoning_effort="medium"',
                    "--json",
                    "--",
                    "reply with: OK",
                ],
                capture_output=True,
                text=True,
                env=env,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(invoked_path.exists())
            self.assertEqual(
                env_path.read_text(),
                f"{SYNTHETIC_LITELLM_SECRET}\n{SYNTHETIC_REF_SECRET}",
            )

            argv = [
                item.decode()
                for item in argv_path.read_bytes().split(b"\0")
                if item
            ]
            rendered_argv = "\n".join(argv)
            for secret in (SYNTHETIC_LITELLM_SECRET, SYNTHETIC_REF_SECRET):
                self.assertNotIn(secret, rendered_argv)
                self.assertNotIn(secret, result.stdout)
                self.assertNotIn(secret, result.stderr)
            self.assertIn('model="positron_openai/gpt-5.6-sol"', argv)
            self.assertEqual(argv.count('model="positron_openai/gpt-5.6-sol"'), 1)
            self.assertIn('model_provider="litellm"', argv)
            self.assertIn(
                'model_providers.litellm.base_url="https://litellm.vulcan.lan/v1"',
                argv,
            )
            self.assertIn(
                'model_providers.litellm.env_key="LITELLM_API_KEY"', argv
            )
            self.assertIn('model_providers.litellm.wire_api="responses"', argv)
            self.assertIn(
                'shell_environment_policy.filters.LITELLM_API_KEY="exclude"',
                argv,
            )
            self.assertIn(
                'shell_environment_policy.set.LITELLM_API_KEY=""',
                argv,
            )
            self.assertIn(
                'shell_environment_policy.filters.REF_API_KEY="exclude"',
                argv,
            )
            self.assertIn(
                'shell_environment_policy.set.REF_API_KEY=""',
                argv,
            )
            exec_index = argv.index("exec")
            provider_index = argv.index('model_provider="litellm"')
            reasoning_index = argv.index('model_reasoning_effort="medium"')
            self.assertLess(exec_index, provider_index)
            self.assertLess(provider_index, reasoning_index)
            self.assertNotIn("-m", argv)
            self.assertNotIn("--model", argv)
            self.assertNotIn("gpt-5.6-sol", argv)
            self.assertEqual(argv[reasoning_index - 1], "-c")
            self.assertEqual(argv[-3:], ["--json", "--", "reply with: OK"])

    def test_removes_all_supported_agent_deck_model_override_forms(self):
        model_forms = (
            ("-m", "gpt-5.6-sol"),
            ("--model", "gpt-5.6-sol"),
            ("--model=gpt-5.6-sol",),
            ("-m", "positron_openai/gpt-5.6-sol"),
            ("--model", "positron_openai/gpt-5.6-sol"),
            ("--model=positron_openai/gpt-5.6-sol",),
        )
        for model_args in model_forms:
            with self.subTest(model_args=model_args), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                pass_bin = root / "pass"
                codex_bin = root / "codex-real"
                argv_path = root / "argv"

                write_executable(
                    pass_bin,
                    f"""#!/usr/bin/env bash
case "$1" in
  litellm.vulcan.lan) printf '%s\\n' '{SYNTHETIC_LITELLM_SECRET}' ;;
  api.ref.tools) printf '%s\\n' '{SYNTHETIC_REF_SECRET}' ;;
  *) exit 1 ;;
esac
""",
                )
                write_executable(
                    codex_bin,
                    """#!/usr/bin/env bash
set -euo pipefail
printf '%s\\0' "$@" >"$CAPTURE_ARGV"
""",
                )
                result = subprocess.run(
                    [str(WRAPPER), *model_args, "resume", "session-id"],
                    capture_output=True,
                    text=True,
                    env={
                        **os.environ,
                        "CODEX_LITELLM_PASS_BIN": str(pass_bin),
                        "CODEX_LITELLM_REAL_CODEX": str(codex_bin),
                        "CAPTURE_ARGV": str(argv_path),
                    },
                    check=False,
                )

                self.assertEqual(result.returncode, 0, result.stderr)
                argv = [
                    item.decode()
                    for item in argv_path.read_bytes().split(b"\0")
                    if item
                ]
                self.assertEqual(
                    argv.count('model="positron_openai/gpt-5.6-sol"'), 1
                )
                self.assertNotIn("-m", argv)
                self.assertNotIn("--model", argv)
                self.assertFalse(any(arg.startswith("--model=") for arg in argv))

    def test_empty_credential_fails_before_codex_runs(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pass_bin = root / "pass"
            codex_bin = root / "codex-real"
            invoked_path = root / "invoked"

            write_executable(pass_bin, "#!/usr/bin/env bash\nexit 0\n")
            write_executable(
                codex_bin,
                f"#!/usr/bin/env bash\n: >'{invoked_path}'\n",
            )

            env = {
                **os.environ,
                "CODEX_LITELLM_PASS_BIN": str(pass_bin),
                "CODEX_LITELLM_REAL_CODEX": str(codex_bin),
            }
            result = subprocess.run(
                [str(WRAPPER), "exec", "--json", "prompt"],
                capture_output=True,
                text=True,
                env=env,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(invoked_path.exists())
            self.assertIn("credential is unavailable or empty", result.stderr)
            self.assertNotIn("Authorization", result.stderr)


if __name__ == "__main__":
    unittest.main()
