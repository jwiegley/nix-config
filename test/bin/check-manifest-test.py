#!/usr/bin/env python3

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "test/bin/check-manifest"
MANIFEST = ROOT / "test/check-manifest.nix"


class CheckManifestTest(unittest.TestCase):
    def run_driver(
        self, *arguments: str
    ) -> tuple[subprocess.CompletedProcess[str], str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            fake_bin = temporary / "bin"
            fake_bin.mkdir()
            log = temporary / "nix.log"
            log.write_text("")
            fake_nix = fake_bin / "nix"
            fake_nix.write_text(
                """#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$CHECK_MANIFEST_TEST_LOG"
if [[ $1 == eval && $* == *'--file'* ]]; then
    case $* in
    *'kind = "evaluation-only"'*) printf 'eval-one\\neval-two\\n' ;;
    *'kind = "behavioral"'*'baselineOnly = true'*) printf 'base-one\\nbase-two\\n' ;;
    *'kind = "behavioral"'*) printf 'behavior-one\\nbehavior-three\\nbehavior-two\\n' ;;
    *) exit 2 ;;
    esac
elif [[ $1 == eval ]]; then
    cat >/dev/null
    printf '/nix/store/check.drv'
elif [[ $1 != build ]]; then
    exit 2
fi
"""
            )
            fake_nix.chmod(0o755)
            environment = os.environ.copy()
            environment["PATH"] = f"{fake_bin}:{environment['PATH']}"
            environment["CHECK_MANIFEST_TEST_LOG"] = str(log)
            result = subprocess.run(
                [str(SCRIPT), *arguments],
                cwd=ROOT,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )
            return result, log.read_text()

    def test_baseline_builds_only_the_manifest_subset(self) -> None:
        result, log = self.run_driver("baseline", "root", "aarch64-darwin")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("build 2 behavioral checks", result.stdout)
        self.assertNotIn(".drvPath", log)
        self.assertIn(
            "build --no-link --no-warn-dirty "
            ".#checks.aarch64-darwin.base-one "
            ".#checks.aarch64-darwin.base-two",
            log,
        )

    def test_closeout_evaluates_and_builds_separate_sets(self) -> None:
        result, log = self.run_driver("closeout", "portable", "x86_64-linux")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("evaluate eval-one", result.stdout)
        self.assertIn("evaluate eval-two", result.stdout)
        self.assertIn("build 3 behavioral checks", result.stdout)
        self.assertIn(
            "./config/ai#checks.x86_64-linux.eval-one.drvPath",
            log,
        )
        self.assertIn(
            "build --no-link --no-warn-dirty "
            "./config/ai#checks.x86_64-linux.behavior-one "
            "./config/ai#checks.x86_64-linux.behavior-three "
            "./config/ai#checks.x86_64-linux.behavior-two",
            log,
        )

    def test_system_is_not_interpolated_as_nix_code(self) -> None:
        result, log = self.run_driver(
            "closeout", "portable", 'x86_64-linux"; builtins.abort "injected'
        )

        self.assertEqual(result.returncode, 64)
        self.assertEqual(log, "")

    def test_manifest_rejects_unclassified_and_stale_checks(self) -> None:
        expression = r"""
manifest:
let
  names = manifest.namesFor {
    flake = "portable";
    system = "x86_64-linux";
  };
  declared = builtins.listToAttrs (map (name: { inherit name; value = null; }) names);
  validate = value: manifest.validateDeclared {
    flake = "portable";
    system = "x86_64-linux";
    declared = value;
  };
in
{
  exact = validate declared;
  unclassified = (builtins.tryEval (validate (declared // { extra = null; }))).success;
  stale = (builtins.tryEval (validate (builtins.removeAttrs declared [ (builtins.head names) ]))).success;
}
"""
        result = subprocess.run(
            [
                "nix",
                "eval",
                "--json",
                "--file",
                str(MANIFEST),
                "--apply",
                expression,
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout),
            {"exact": True, "stale": False, "unclassified": False},
        )


if __name__ == "__main__":
    unittest.main()
