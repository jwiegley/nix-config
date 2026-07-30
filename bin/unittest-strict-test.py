#!/usr/bin/env python3

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


RUNNER = Path(__file__).with_name("unittest-strict.py")


class StrictUnittestRunnerTests(unittest.TestCase):
    def run_fixture(self, body: str):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "fixture_test.py"
            path.write_text("import unittest\n" + body)
            return subprocess.run(
                [sys.executable, str(RUNNER), path.name],
                cwd=temp_dir,
                capture_output=True,
                text=True,
                check=False,
            )

    def test_pass_is_success(self):
        result = self.run_fixture(
            "class T(unittest.TestCase):\n"
            "    def test_ok(self): self.assertTrue(True)\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_failure_is_nonzero(self):
        result = self.run_fixture(
            "class T(unittest.TestCase):\n"
            "    def test_bad(self): self.fail('bad')\n"
        )
        self.assertEqual(result.returncode, 1)

    def test_skip_is_nonpass(self):
        result = self.run_fixture(
            "class T(unittest.TestCase):\n"
            "    @unittest.skip('missing authority')\n"
            "    def test_skipped(self): pass\n"
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("skipped test(s) are non-pass", result.stderr)

    def test_missing_name_refuses(self):
        result = subprocess.run(
            [sys.executable, str(RUNNER)],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2)

    def test_module_setup_and_teardown_are_not_bypassed(self):
        setup = self.run_fixture(
            "def setUpModule(): raise RuntimeError('setup ran')\n"
            "class T(unittest.TestCase):\n"
            "    def test_ok(self): pass\n"
        )
        self.assertEqual(setup.returncode, 1)
        self.assertIn("setup ran", setup.stderr)
        teardown = self.run_fixture(
            "def tearDownModule(): raise RuntimeError('teardown ran')\n"
            "class T(unittest.TestCase):\n"
            "    def test_ok(self): pass\n"
        )
        self.assertEqual(teardown.returncode, 1)
        self.assertIn("teardown ran", teardown.stderr)

    def test_empty_authority_refuses_alone_and_when_mixed(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            empty = Path(temp_dir) / "empty_test.py"
            passing = Path(temp_dir) / "passing_test.py"
            empty.write_text("value = 1\n")
            passing.write_text(
                "import unittest\n"
                "class T(unittest.TestCase):\n"
                "    def test_ok(self): pass\n"
            )
            for names in ((empty.name,), (passing.name, empty.name)):
                result = subprocess.run(
                    [sys.executable, str(RUNNER), *names],
                    cwd=temp_dir,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 2)
                self.assertIn("test authority is empty", result.stderr)


if __name__ == "__main__":
    unittest.main()
