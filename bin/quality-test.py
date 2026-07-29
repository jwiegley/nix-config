#!/usr/bin/env python3
"""Execution tests for bin/quality -- the first this repository has had.

Everything that referenced `bin/quality` from a test previously did so as TEXT:
`bin/gates-test.py` greps its source for two dispatch arms. Nothing invoked it, and
nothing exercised `each_file`, the function every per-file suite runs through. So
when `d6b3cf3d` fixed `each_file` to skip tracked-but-absent paths, both of its
negative cases existed only in the commit message.

This programme's standing rule is that a gate without a proven negative case is
assumed broken, and a negative proof in a commit message cannot catch a regression.
These tests make the two cases replayable, plus the exit-status propagation every
hook depends on.

SAFETY: every test runs `bin/quality` with the CWD inside a throwaway repository,
and scrubs GIT_* from the environment first. That scrub is not decoration --
`bin/publish-test.py` once inherited GIT_DIR under a git hook and its
`git init --bare <tmpdir>` retargeted the REAL repository, setting core.bare=true
and breaking five worktrees at once. `bin/quality` resolves its scope with
`git rev-parse --show-toplevel`, so a leaked GIT_DIR would point it at the real
checkout and these tests would silently assert against the wrong tree.
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

QUALITY = Path(__file__).resolve().parent / "quality"

# Every variable git consults for location or identity. A test that shells out to
# git must start from a known-empty set of these, not from whatever the caller had.
GIT_VARS = (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_CEILING_DIRECTORIES",
    "GIT_COMMON_DIR",
    "GIT_NAMESPACE",
    "GIT_PREFIX",
    "GIT_CONFIG",
    "GIT_CONFIG_GLOBAL",
    "GIT_CONFIG_SYSTEM",
    "GIT_CONFIG_COUNT",
)


def clean_env():
    env = dict(os.environ)
    for var in GIT_VARS:
        env.pop(var, None)
    return env


def have(tool):
    return shutil.which(tool) is not None


class QualityEachFileTests(unittest.TestCase):
    """The per-file loop: what it checks, what it skips, and what it reports."""

    def setUp(self):
        self.env = clean_env()
        self.tmp = tempfile.mkdtemp(prefix="quality-test-")
        self.repo = Path(self.tmp) / "r"
        self.repo.mkdir()
        self.git("init", "-q", ".")
        self.git("config", "user.email", "t@example.invalid")
        self.git("config", "user.name", "quality test")
        self.git("config", "commit.gpgsign", "false")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def git(self, *args):
        return subprocess.run(
            ["git", *args],
            cwd=self.repo,
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def quality(self, *suites):
        return subprocess.run(
            [str(QUALITY), *suites],
            cwd=self.repo,
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def write(self, name, text):
        p = self.repo / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        return p

    def test_python_template_is_discovered(self):
        self.write("template.py.in", "VALUE = @VALUE@\n")
        self.git("add", "template.py.in")
        proc = self.quality("--files", "python")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout.splitlines(), ["template.py.in"])

    @unittest.skipUnless(have("ruff"), "ruff is not on PATH")
    def test_python_template_is_rendered_for_lint(self):
        self.write("template.py.in", "VALUE = @VALUE@\n")
        self.git("add", "template.py.in")
        proc = self.quality("python-lint")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("1 rendered template(s)", proc.stderr + proc.stdout)

        self.write("template.py.in", "if @VALUE@\n    pass\n")
        proc = self.quality("python-lint")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("template.py", proc.stderr + proc.stdout)

    # --- positive control -------------------------------------------------
    # Without this, a suite that skipped EVERYTHING would satisfy every
    # "passes" assertion below. This proves the harness can see a real file
    # and check it.
    @unittest.skipUnless(have("nixfmt"), "nixfmt is not on PATH")
    def test_canonical_file_passes_and_is_counted(self):
        self.write("a.nix", "{ }\n")
        self.git("add", "a.nix")
        proc = self.quality("nix-format")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("1 file(s) OK", proc.stderr + proc.stdout)

    # --- the negative case that must keep working ------------------------
    @unittest.skipUnless(have("nixfmt"), "nixfmt is not on PATH")
    def test_misformatted_tracked_file_fails(self):
        self.write("bad.nix", "{ a=1;b=2; }\n")
        self.git("add", "bad.nix")
        proc = self.quality("nix-format")
        self.assertNotEqual(
            proc.returncode, 0, "a misformatted tracked file must fail the suite"
        )
        self.assertIn("bad.nix", proc.stderr)

    # --- the case d6b3cf3d fixed ----------------------------------------
    @unittest.skipUnless(have("nixfmt"), "nixfmt is not on PATH")
    def test_absent_tracked_path_is_skipped_not_failed(self):
        """A tracked path that is gone from disk must be skipped.

        Reproduces what lefthook's pre-commit stash does during a partial commit:
        the index still tracks a path the worktree no longer has. Before the fix,
        nixfmt was handed the missing path and reported
        `openFile: does not exist`, surfaced as "1 of N file(s) failed" -- a
        formatting failure for a file that does not exist.
        """
        self.write("kept.nix", "{ }\n")
        self.write("gone.nix", "{ }\n")
        self.git("add", "kept.nix", "gone.nix")
        self.git("commit", "-qm", "init")
        # Track the path, then remove it from the worktree only.
        os.unlink(self.repo / "gone.nix")
        tracked = self.git("ls-files").stdout.split()
        self.assertIn("gone.nix", tracked, "fixture must keep the path tracked")
        self.assertFalse((self.repo / "gone.nix").exists())

        proc = self.quality("nix-format")
        self.assertEqual(
            proc.returncode,
            0,
            "an absent tracked path must be skipped, not reported as a failure:\n"
            + proc.stderr,
        )
        self.assertNotIn("does not exist", proc.stderr)
        # Counted as one file, not two: the count means "files actually checked".
        self.assertIn("1 file(s) OK", proc.stderr + proc.stdout)

    # --- the distinction the skip must NOT swallow -----------------------
    @unittest.skipUnless(have("nixfmt"), "nixfmt is not on PATH")
    def test_dangling_tracked_symlink_is_reported_not_skipped(self):
        """`-e` follows symlinks, so `-e` alone would skip a broken one.

        A staged rename is benign bookkeeping; a tracked symlink whose target is
        missing is a real repository defect. The guard is `-e || -L` so the second
        reaches the checker and fails instead of vanishing.
        """
        os.symlink("nowhere-at-all.nix", self.repo / "link.nix")
        self.git("add", "link.nix")
        mode = self.git("ls-files", "-s", "link.nix").stdout.split()
        self.assertTrue(mode and mode[0] == "120000", "fixture must stage a symlink")
        self.assertFalse((self.repo / "link.nix").exists(), "target must be missing")

        proc = self.quality("nix-format")
        self.assertNotEqual(
            proc.returncode,
            0,
            "a tracked dangling symlink must be reported, not silently skipped",
        )
        self.assertIn("link.nix", proc.stderr)


class QualityExitPropagationTests(unittest.TestCase):
    """Failure must reach the caller; every hook depends on it.

    The tool's own header records that its predecessors "looped over files WITHOUT
    propagating failure", so this is the regression most worth pinning.
    """

    def setUp(self):
        self.env = clean_env()
        self.tmp = tempfile.mkdtemp(prefix="quality-exit-")
        self.repo = Path(self.tmp) / "r"
        self.repo.mkdir()
        for args in (
            ("init", "-q", "."),
            ("config", "user.email", "t@example.invalid"),
            ("config", "user.name", "quality test"),
            ("config", "commit.gpgsign", "false"),
        ):
            subprocess.run(
                ["git", *args], cwd=self.repo, env=self.env, capture_output=True
            )

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_unknown_suite_is_rejected(self):
        proc = subprocess.run(
            [str(QUALITY), "no-such-suite"],
            cwd=self.repo,
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(proc.returncode, 0)

    @unittest.skipUnless(have("nixfmt"), "nixfmt is not on PATH")
    def test_one_bad_file_among_many_still_fails(self):
        """A single failure must not be diluted by its passing siblings."""
        (self.repo / "ok1.nix").write_text("{ }\n")
        (self.repo / "ok2.nix").write_text("{ }\n")
        (self.repo / "bad.nix").write_text("{ a=1;b=2; }\n")
        subprocess.run(
            ["git", "add", "ok1.nix", "ok2.nix", "bad.nix"],
            cwd=self.repo,
            env=self.env,
            capture_output=True,
        )
        proc = subprocess.run(
            [str(QUALITY), "nix-format"],
            cwd=self.repo,
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("bad.nix", proc.stderr)


class QualityPythonTierTests(unittest.TestCase):
    """Tier selection must be exact, complete, and budgeted."""

    def setUp(self):
        self.env = clean_env()
        self.tmp = tempfile.mkdtemp(prefix="quality-tier-")
        self.repo = Path(self.tmp) / "r"
        self.repo.mkdir()
        subprocess.run(
            ["git", "init", "-q", "."],
            cwd=self.repo,
            env=self.env,
            check=True,
        )
        self.tests = {
            "bin/a-fast-test.py": "pre-commit",
            "bin/b-push-test.py": "pre-push",
            "bin/c-demand-test.py": "ci-on-demand",
        }
        for path in self.tests:
            target = self.repo / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(
                "import unittest\n"
                "class T(unittest.TestCase):\n"
                "    def test_ok(self): self.assertTrue(True)\n",
                encoding="utf-8",
            )
        shutil.copy2(QUALITY, self.repo / "bin/quality")
        self.write_manifest()
        subprocess.run(["git", "add", "."], cwd=self.repo, env=self.env, check=True)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write_manifest(self, *, omit=(), budgets=None):
        entries = [
            {
                "path": path,
                "kind": "test",
                "tier": tier,
                "evidence": ["fixture"],
                "gap": None,
            }
            for path, tier in self.tests.items()
            if path not in omit
        ]
        target = self.repo / "test" / "coverage" / "manifest.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            json.dumps(
                {
                    "pythonInventory": entries,
                    "budgetsSeconds": budgets
                    or {"pre-commit": 180, "pre-push": 900, "ci-on-demand": 1800},
                }
            ),
            encoding="utf-8",
        )

    def quality(self, *args, env=None, cwd=None):
        return subprocess.run(
            [str(QUALITY), *args],
            cwd=self.repo if cwd is None else cwd,
            env=self.env if env is None else env,
            capture_output=True,
            text=True,
            check=False,
        )

    @unittest.skipUnless(have("timeout"), "timeout is not on PATH")
    def test_pre_commit_selects_only_pre_commit_suite(self):
        proc = self.quality("--python-tier", "pre-commit", "python-test")
        combined = proc.stdout + proc.stderr
        self.assertEqual(proc.returncode, 0, combined)
        self.assertIn("bin/a-fast-test.py", combined)
        self.assertNotIn("bin/b-push-test.py", combined)
        self.assertNotIn("bin/c-demand-test.py", combined)
        self.assertIn("planned=1 ran=1", combined)

    @unittest.skipUnless(have("timeout"), "timeout is not on PATH")
    def test_default_preserves_all_tracked_suites(self):
        proc = self.quality("python-test")
        combined = proc.stdout + proc.stderr
        self.assertEqual(proc.returncode, 0, combined)
        for path in self.tests:
            self.assertIn(path, combined)
        self.assertIn("tier=all planned=3 ran=3", combined)

    def test_missing_manifest_assignment_refuses(self):
        self.write_manifest(omit={"bin/b-push-test.py"})
        proc = self.quality("--python-tier", "pre-push", "python-test")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("missing=['bin/b-push-test.py']", proc.stdout + proc.stderr)

    def test_invalid_tier_refuses_before_execution(self):
        proc = self.quality("--python-tier", "fast", "python-test")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("--python-tier needs one of", proc.stderr)

    def test_whole_tier_supervisor_reports_timeout_and_forced_kill(self):
        fakebin = self.repo / "fakebin"
        fakebin.mkdir()
        timeout = fakebin / "timeout"
        env = dict(self.env)
        env["PATH"] = f"{fakebin}{os.pathsep}{env['PATH']}"
        for status, expected in (
            (124, "timed out after 180s"),
            (137, "exited 137 (SIGKILL; deadline escalation, OOM, or external kill)"),
        ):
            timeout.write_text(
                f"#!/usr/bin/env bash\nexit {status}\n", encoding="utf-8"
            )
            timeout.chmod(0o755)
            proc = self.quality("--tier", "pre-commit", env=env)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn(expected, proc.stderr)

    def test_tier_supervisor_recurses_through_repo_absolute_quality_path(self):
        fakebin = self.repo / "fakebin"
        fakebin.mkdir()
        timeout = fakebin / "timeout"
        expected = (self.repo / "bin/quality").resolve()
        timeout.write_text(
            f"#!/usr/bin/env bash\n[[ $4 == {expected!s} ]] || exit 99\nexit 124\n",
            encoding="utf-8",
        )
        timeout.chmod(0o755)
        env = dict(self.env)
        env["PATH"] = f"{fakebin}{os.pathsep}{env['PATH']}"
        subdir = self.repo / "doc"
        subdir.mkdir()
        proc = self.quality("--tier", "pre-commit-core", env=env, cwd=subdir)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("timed out after 180s", proc.stderr)

    @unittest.skipUnless(have("timeout"), "timeout is not on PATH")
    def test_budget_timeout_names_not_reached_suites(self):
        (self.repo / "bin/a-fast-test.py").write_text(
            "import time, unittest\n"
            "class T(unittest.TestCase):\n"
            "    def test_slow(self): time.sleep(5)\n",
            encoding="utf-8",
        )
        self.tests["bin/z-never-test.py"] = "pre-commit"
        (self.repo / "bin/z-never-test.py").write_text(
            "import unittest\n"
            "class T(unittest.TestCase):\n"
            "    def test_never(self): self.fail('must not run')\n",
            encoding="utf-8",
        )
        self.write_manifest(
            budgets={"pre-commit": 1, "pre-push": 900, "ci-on-demand": 1800}
        )
        subprocess.run(["git", "add", "."], cwd=self.repo, env=self.env, check=True)
        proc = self.quality("--python-tier", "pre-commit", "python-test")
        combined = proc.stdout + proc.stderr
        self.assertNotEqual(proc.returncode, 0, combined)
        self.assertIn("timed-out=1", combined)
        self.assertIn("not-reached=1", combined)


class GitScrubRegressionTest(unittest.TestCase):
    """The scrub itself, asserted rather than trusted.

    `bin/publish-test.py` inherited GIT_DIR under a git hook and its
    `git init --bare` retargeted the real repository. `bin/quality` resolves scope
    via `git rev-parse --show-toplevel`, so a leaked GIT_DIR would silently point
    these tests at the real checkout.
    """

    def test_clean_env_removes_every_git_var(self):
        os.environ["GIT_DIR"] = "/somewhere/else/.git"
        os.environ["GIT_WORK_TREE"] = "/somewhere/else"
        try:
            env = clean_env()
            for var in GIT_VARS:
                self.assertNotIn(var, env, "%s survived the scrub" % var)
        finally:
            os.environ.pop("GIT_DIR", None)
            os.environ.pop("GIT_WORK_TREE", None)


if __name__ == "__main__":
    unittest.main(verbosity=2)
