#!/usr/bin/env python3
"""Execution tests for test/bin/quality -- the first this repository has had.

Everything that referenced `test/bin/quality` from a test previously did so as TEXT:
`test/bin/gates-slow-test.py` greps its source for two dispatch arms. Nothing invoked it, and
nothing exercised `each_file`, the function every per-file suite runs through. So
when `d6b3cf3d` fixed `each_file` to skip tracked-but-absent paths, both of its
negative cases existed only in the commit message.

This programme's standing rule is that a gate without a proven negative case is
assumed broken, and a negative proof in a commit message cannot catch a regression.
These tests make the two cases replayable, plus the exit-status propagation every
hook depends on.

SAFETY: every test runs `test/bin/quality` with the CWD inside a throwaway repository,
and scrubs GIT_* from the environment first. That scrub is not decoration --
`test/bin/publish-slow-test.py` once inherited GIT_DIR under a git hook and its
`git init --bare <tmpdir>` retargeted the REAL repository, setting core.bare=true
and breaking five worktrees at once. `test/bin/quality` resolves its scope with
`git rev-parse --show-toplevel`, so a leaked GIT_DIR would point it at the real
checkout and these tests would silently assert against the wrong tree.
"""

import os
import runpy
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
QUALITY = REPO / "test" / "bin" / "quality"
DEADLINE_SUPERVISOR = REPO / "test" / "bin" / "deadline-supervisor.py"
UNITTEST_STRICT = Path(__file__).resolve().parent / "unittest-strict.py"
UPDATER_ESSENTIAL = (
    Path(__file__).resolve().parent / "update-overlay-essential-test.py"
)

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

    def quality(self, *suites, env=None):
        return subprocess.run(
            [str(QUALITY), *suites],
            cwd=self.repo,
            env=self.env if env is None else env,
            capture_output=True,
            text=True,
            check=False,
        )

    def failing_ls_files_env(self):
        fakebin = self.repo / "fake-git-bin"
        fakebin.mkdir()
        real_git = shlex.quote(shutil.which("git"))
        git = fakebin / "git"
        git.write_text(
            "#!/usr/bin/env bash\n"
            "if [[ $1 == rev-parse ]]; then\n"
            f"  exec {real_git} \"$@\"\n"
            "fi\n"
            "if [[ $1 == ls-files ]]; then exit 73; fi\n"
            f"exec {real_git} \"$@\"\n",
            encoding="utf-8",
        )
        git.chmod(0o755)
        env = dict(self.env)
        env["PATH"] = f"{fakebin}{os.pathsep}{env['PATH']}"
        return env

    def test_git_ls_files_failure_is_never_an_empty_success(self):
        env = self.failing_ls_files_env()
        for kind in ("nix", "shell", "python", "python-tests"):
            with self.subTest(interface="files", kind=kind):
                proc = self.quality("--files", kind, env=env)
                self.assertNotEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        for suite, tool in (
            ("nix-format", "nixfmt"),
            ("nix-lint", "statix"),
            ("nix-deadcode", "deadnix"),
            ("shell-lint", "shellcheck"),
            ("shell-format", "shfmt"),
            ("python-lint", "ruff"),
        ):
            if not have(tool):
                continue
            with self.subTest(interface="suite", suite=suite):
                proc = self.quality(suite, env=env)
                self.assertNotEqual(proc.returncode, 0, proc.stdout + proc.stderr)
                self.assertIn("tracked-file discovery failed", proc.stdout + proc.stderr)

    def test_fix_mode_preserves_paths_and_propagates_formatter_failure(self):
        paths = {
            "nix-format": [
                self.write("--version.nix", "{ }\n"),
                self.write("dir/a b.nix", "{ }\n"),
            ],
            "shell-format": [
                self.write("--version.sh", "#!/usr/bin/env bash\ntrue\n"),
                self.write("dir/a b.sh", "#!/usr/bin/env bash\ntrue\n"),
            ],
        }
        self.git(
            "add",
            "--",
            *(
                str(path.relative_to(self.repo))
                for suite_paths in paths.values()
                for path in suite_paths
            ),
        )
        fakebin = self.repo / "fake-format-bin"
        fakebin.mkdir()
        env = dict(self.env)
        env["PATH"] = f"{fakebin}{os.pathsep}{env['PATH']}"
        for suite, executable in (("nix-format", "nixfmt"), ("shell-format", "shfmt")):
            log = self.repo / f"{executable}.log"
            tool = fakebin / executable
            tool.write_text(
                "#!/usr/bin/env bash\n"
                f"printf '%s:%s\\n' \"$#\" \"${{@:$#}}\" >>{shlex.quote(str(log))}\n"
                "exit 71\n",
                encoding="utf-8",
            )
            tool.chmod(0o755)
            proc = self.quality("--fix", suite, env=env)
            self.assertNotEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            calls = [line.split(":", 1) for line in log.read_text().splitlines()]
            self.assertEqual(
                {final_arg for _, final_arg in calls},
                {f"./{path.relative_to(self.repo)}" for path in paths[suite]},
            )
            self.assertTrue(all(int(count) >= 1 for count, _ in calls))

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

    def test_posix_shell_is_discovered_without_selecting_zsh(self):
        self.write("posix", "#!/bin/sh\ntrue\n")
        self.write("zshell", "#!/bin/zsh\ntrue\n")
        self.git("add", "posix", "zshell")
        proc = self.quality("--files", "shell")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("posix", proc.stdout.splitlines())
        self.assertNotIn("zshell", proc.stdout.splitlines())

    def test_nix_tools_receive_only_safe_tracked_paths(self):
        self.write("--tracked.nix", "{ }\n")
        self.write("untracked.nix", "{ }\n")
        self.git("add", "--", "--tracked.nix")
        fakebin = self.repo / "fake-nix-tools"
        fakebin.mkdir()
        env = dict(self.env)
        env["PATH"] = f"{fakebin}{os.pathsep}{env['PATH']}"
        for suite, executable in (
            ("nix-lint", "statix"),
            ("nix-deadcode", "deadnix"),
        ):
            log = self.repo / f"{executable}.log"
            tool = fakebin / executable
            tool.write_text(
                "#!/usr/bin/env bash\n"
                f"printf '%s\\n' \"$@\" >{shlex.quote(str(log))}\n",
                encoding="utf-8",
            )
            tool.chmod(0o755)
            proc = self.quality(suite, env=env)
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            arguments = log.read_text().splitlines()
            self.assertIn("./--tracked.nix", arguments)
            self.assertNotIn("untracked.nix", "\n".join(arguments))

    def test_python_lint_prefixes_option_like_paths(self):
        self.write("--version.py", "VALUE = 1\n")
        self.git("add", "--", "--version.py")
        fakebin = self.repo / "fake-python-tools"
        fakebin.mkdir()
        log = self.repo / "ruff.log"
        ruff = fakebin / "ruff"
        ruff.write_text(
            "#!/usr/bin/env bash\n"
            f"printf '%s\\n' \"$@\" >{shlex.quote(str(log))}\n",
            encoding="utf-8",
        )
        ruff.chmod(0o755)
        env = dict(self.env)
        env["PATH"] = f"{fakebin}{os.pathsep}{env['PATH']}"
        proc = self.quality("python-lint", env=env)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("./--version.py", log.read_text().splitlines())

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
        self.tests = (
            "test/bin/a-fast-test.py",
            "test/bin/b-other-test.py",
            "test/bin/c-slow-test.py",
        )
        for path in self.tests:
            self.write_test(path)
        (self.repo / "bin").mkdir()
        shutil.copy2(QUALITY, self.repo / "test/bin/quality")
        shutil.copy2(DEADLINE_SUPERVISOR, self.repo / "test/bin/deadline-supervisor.py")
        shutil.copy2(UNITTEST_STRICT, self.repo / "test/bin/unittest-strict.py")
        subprocess.run(["git", "add", "."], cwd=self.repo, env=self.env, check=True)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write_test(self, path):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            "import unittest\n"
            "class T(unittest.TestCase):\n"
            "    def test_ok(self): self.assertTrue(True)\n",
            encoding="utf-8",
        )
        return target

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
    def test_fast_selects_every_non_slow_suite(self):
        proc = self.quality("--python-tier", "fast", "python-test")
        combined = proc.stdout + proc.stderr
        self.assertEqual(proc.returncode, 0, combined)
        self.assertIn("test/bin/a-fast-test.py", combined)
        self.assertIn("test/bin/b-other-test.py", combined)
        self.assertNotIn("test/bin/c-slow-test.py", combined)
        self.assertIn("tier=fast planned=2 ran=2", combined)

    @unittest.skipUnless(have("timeout"), "timeout is not on PATH")
    def test_default_preserves_all_tracked_suites(self):
        proc = self.quality("python-test")
        combined = proc.stdout + proc.stderr
        self.assertEqual(proc.returncode, 0, combined)
        for path in self.tests:
            self.assertIn(path, combined)
        self.assertIn("tier=full planned=3 ran=3", combined)

    @unittest.skipUnless(have("timeout"), "timeout is not on PATH")
    def test_new_test_needs_no_registration(self):
        path = "test/bin/new-test.py"
        self.write_test(path)
        subprocess.run(["git", "add", path], cwd=self.repo, env=self.env, check=True)
        for tier in ("fast", "full"):
            with self.subTest(tier=tier):
                proc = self.quality("--python-tier", tier, "python-test")
                self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
                self.assertIn(path, proc.stdout + proc.stderr)

    @unittest.skipUnless(have("timeout"), "timeout is not on PATH")
    def test_new_slow_test_enters_full_only(self):
        path = "test/bin/new-slow-test.py"
        self.write_test(path)
        subprocess.run(["git", "add", path], cwd=self.repo, env=self.env, check=True)
        fast = self.quality("--python-tier", "fast", "python-test")
        full = self.quality("--python-tier", "full", "python-test")
        self.assertEqual(fast.returncode, 0, fast.stdout + fast.stderr)
        self.assertEqual(full.returncode, 0, full.stdout + full.stderr)
        self.assertNotIn(path, fast.stdout + fast.stderr)
        self.assertIn(path, full.stdout + full.stderr)

    def test_empty_test_inventory_refuses_every_interface(self):
        subprocess.run(
            ["git", "rm", "-q", "-f", *self.tests],
            cwd=self.repo,
            env=self.env,
            check=True,
        )
        for args in (
            ("--files", "python-tests"),
            ("--python-tier", "fast", "python-test"),
            ("--python-tier", "full", "python-test"),
        ):
            with self.subTest(args=args):
                proc = self.quality(*args)
                self.assertNotEqual(proc.returncode, 0, proc.stdout + proc.stderr)
                self.assertIn("selected zero suites", proc.stdout + proc.stderr)

    def test_selected_suites_execute_exactly_once(self):
        runner = self.repo / "test/bin/unittest-strict.py"
        runner.write_text(
            "#!/usr/bin/env bash\n"
            "printf '%s\\n' \"$1\" >>\"$RUN_LOG\"\n",
            encoding="utf-8",
        )
        runner.chmod(0o755)
        log = self.repo / "runner.log"
        env = dict(self.env)
        env["RUN_LOG"] = str(log)

        fast = self.quality("--python-tier", "fast", "python-test", env=env)
        self.assertEqual(fast.returncode, 0, fast.stdout + fast.stderr)
        self.assertEqual(
            log.read_text().splitlines(),
            ["test/bin/a-fast-test.py", "test/bin/b-other-test.py"],
        )

        log.unlink()
        full = self.quality("--python-tier", "full", "python-test", env=env)
        self.assertEqual(full.returncode, 0, full.stdout + full.stderr)
        self.assertEqual(log.read_text().splitlines(), list(self.tests))

    def test_python_suite_outside_test_bin_refuses(self):
        misplaced = self.repo / "bin" / "misplaced-test.py"
        misplaced.write_text("import unittest\n", encoding="utf-8")
        subprocess.run(
            ["git", "add", str(misplaced)],
            cwd=self.repo,
            env=self.env,
            check=True,
        )
        proc = self.quality("--python-tier", "fast", "python-test")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("must live under test/bin", proc.stdout + proc.stderr)

    def test_invalid_tier_refuses_before_execution(self):
        for tier in ("pre-commit", "pre-push", "ci-on-demand", "all", "invalid"):
            with self.subTest(tier=tier):
                proc = self.quality("--python-tier", tier, "python-test")
                self.assertNotEqual(proc.returncode, 0)
                self.assertIn("--python-tier needs one of: fast full", proc.stderr)

    def test_whole_tier_supervisor_reports_timeout_and_forced_kill(self):
        supervisor = self.repo / "test/bin/deadline-supervisor.py"
        for status, expected in (
            (124, "exceeded its 105s work deadline inside the 120s envelope"),
            (137, "exited 137 (SIGKILL; deadline escalation, OOM, or external kill)"),
        ):
            supervisor.write_text(
                f"#!/usr/bin/env bash\nexit {status}\n", encoding="utf-8"
            )
            supervisor.chmod(0o755)
            proc = self.quality("--tier", "pre-commit")
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn(expected, proc.stderr)

    def test_tier_supervisor_recurses_through_repo_absolute_quality_path(self):
        supervisor = self.repo / "test/bin/deadline-supervisor.py"
        expected = (self.repo / "test/bin/quality").resolve()
        expected_shell = shlex.quote(str(expected))
        supervisor.write_text(
            f"#!/usr/bin/env bash\n"
            "[[ $1 == --term-after ]] || exit 95\n"
            "[[ $2 == 105 ]] || exit 96\n"
            "[[ $3 == --kill-after ]] || exit 97\n"
            "[[ $4 == 5 && $5 == -- ]] || exit 98\n"
            f"[[ $6 == {expected_shell} ]] || exit 99\n"
            "exit 124\n",
            encoding="utf-8",
        )
        supervisor.chmod(0o755)
        subdir = self.repo / "doc"
        subdir.mkdir()
        proc = self.quality("--tier", "pre-commit", cwd=subdir)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("exceeded its 105s work deadline", proc.stderr)

    def test_tier_membership_keeps_expensive_work_out_of_pre_commit(self):
        supervisor = self.repo / "test/bin/deadline-supervisor.py"
        log = self.repo / "supervisor-args"
        log_shell = shlex.quote(str(log))
        supervisor.write_text(
            f"#!/usr/bin/env bash\nprintf '%s\\n' \"$@\" >{log_shell}\nexit 124\n",
            encoding="utf-8",
        )
        supervisor.chmod(0o755)
        quality = str((self.repo / "test/bin/quality").resolve())

        pre_commit = self.quality("--tier", "pre-commit")
        self.assertNotEqual(pre_commit.returncode, 0)
        self.assertEqual(
            log.read_text().splitlines(),
            [
                "--term-after", "105", "--kill-after", "5", "--", quality,
                "--python-tier", "fast", "nix-format", "nix-lint",
                "nix-deadcode", "shell-lint", "shell-format", "python-lint",
                "python-test",
            ],
        )

        expensive = self.quality("--tier", "expensive")
        self.assertNotEqual(expensive.returncode, 0)
        self.assertEqual(
            log.read_text().splitlines(),
            [
                "--term-after", "1785", "--kill-after", "5", "--", quality,
                "--python-tier", "full", "python-test", "portable-eval",
                "immutable-subflake", "consumer-eval", "signatures", "coverage",
                "coverage-live", "output-denominators", "darwin-surface",
            ],
        )

    def test_tier_selector_conflicts_refuse(self):
        for args in (
            ("--tier",),
            ("--tier", "fast"),
            ("--tier", "pre-commit-core"),
            ("--tier", "pre-commit", "--tier", "expensive"),
            ("--python-tier", "full", "--tier", "pre-commit"),
            ("--tier", "pre-commit", "--python-tier", "full"),
            ("--python-tier", "full", "--python-tier", "fast", "python-test"),
            ("--tier", "pre-commit", "python-test"),
            ("--tier", "pre-commit", "--fix"),
        ):
            with self.subTest(args=args):
                proc = self.quality(*args)
                self.assertNotEqual(proc.returncode, 0)

    @unittest.skipUnless(have("timeout"), "timeout is not on PATH")
    def test_budget_timeout_names_not_reached_suites(self):
        fakebin = self.repo / "fakebin-timeout"
        fakebin.mkdir()
        timeout = fakebin / "timeout"
        timeout.write_text("#!/usr/bin/env bash\nexit 124\n", encoding="utf-8")
        timeout.chmod(0o755)
        env = dict(self.env)
        env["PATH"] = f"{fakebin}{os.pathsep}{env['PATH']}"
        proc = self.quality("--python-tier", "fast", "python-test", env=env)
        combined = proc.stdout + proc.stderr
        self.assertNotEqual(proc.returncode, 0, combined)
        self.assertIn("timed-out=1", combined)
        self.assertIn("not-reached=1", combined)

    def test_supervised_python_timeout_stays_in_outer_process_group(self):
        fakebin = self.repo / "fakebin"
        fakebin.mkdir()
        timeout = fakebin / "timeout"
        log = self.repo / "timeout-args"
        log_shell = shlex.quote(str(log))
        timeout.write_text(
            f"#!/usr/bin/env bash\nprintf '%s\\n' \"$@\" >{log_shell}\nexit 124\n",
            encoding="utf-8",
        )
        timeout.chmod(0o755)
        env = dict(self.env)
        env["PATH"] = f"{fakebin}{os.pathsep}{env['PATH']}"
        env["QUALITY_TIER_SUPERVISED"] = "1"
        proc = self.quality(
            "--python-tier", "fast", "python-test", env=env
        )
        self.assertNotEqual(proc.returncode, 0)
        supervised = log.read_text().splitlines()
        self.assertEqual(
            supervised[:3], ["--signal=TERM", "--kill-after=5", "--foreground"]
        )
        self.assertEqual(
            supervised[-2:],
            [
                str((self.repo / "test/bin/unittest-strict.py").resolve()),
                "test/bin/a-fast-test.py",
            ],
        )

        env.pop("QUALITY_TIER_SUPERVISED")
        proc = self.quality(
            "--python-tier", "fast", "python-test", env=env
        )
        self.assertNotEqual(proc.returncode, 0)
        unsupervised = log.read_text().splitlines()
        self.assertEqual(unsupervised[:2], ["--signal=TERM", "--kill-after=5"])
        self.assertNotIn("--foreground", unsupervised)


class UpdaterEssentialPlanTests(unittest.TestCase):
    def test_safety_plan_declares_required_membership(self):
        plan = runpy.run_path(str(UPDATER_ESSENTIAL))
        groups = [
            plan["CLI_METHODS"],
            plan["INVENTORY_METHODS"],
            plan["INTEGRATION_METHODS"],
        ]
        for group in groups:
            self.assertIsInstance(group, tuple)
            self.assertTrue(group)
            self.assertEqual(len(group), len(set(group)))
        selected = set().union(*map(set, groups))
        self.assertTrue(
            {
                "test_catalog_and_cli_inventory_cover_all_update_targets",
                "test_source_transaction_rolls_back_and_commit_preserves",
                "test_active_commands_have_one_repository_update_transaction",
                "test_profile_symlinked_scripts_find_packaged_routing_library",
            }
            <= selected
        )
        self.assertNotIn("test_package_hash_build_never_creates_a_result_link", selected)
        self.assertNotIn("test_pi_manifest_normalizer_is_shared_complete_and_fail_closed", selected)
        suite = plan["load_tests"](unittest.TestLoader(), unittest.TestSuite(), None)
        self.assertGreater(suite.countTestCases(), 0)


class GitScrubRegressionTest(unittest.TestCase):
    """The scrub itself, asserted rather than trusted.

    `test/bin/publish-slow-test.py` inherited GIT_DIR under a git hook and its
    `git init --bare` retargeted the real repository. `test/bin/quality` resolves scope
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
