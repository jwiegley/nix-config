#!/usr/bin/env python3
"""Security and concurrency tests for bin/upgrade-projects logging."""

import fcntl
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
UPGRADE_PROJECTS = REPO / "bin/upgrade-projects"
PROJECTS = (
    "src/category-theory/master",
    "src/ltl/coq",
    "src/notes/haskell",
    "src/org-jw",
    "src/pushme",
    "src/gitlib",
    "src/hours",
    "src/renamer",
    "src/simple-amount",
    "src/sizes",
    "src/three-partition",
    "src/trade-journal",
    "src/una",
    "src/comparable",
    "src/rag-client",
    "src/hf",
    "src/ledger/main",
)


class UpgradeProjectsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = UPGRADE_PROJECTS.read_text(encoding="utf-8")
        if "/tmp" in source:
            raise AssertionError(
                "refusing to execute upgrade-projects with a shared /tmp path"
            )

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        for project in PROJECTS:
            directory = self.home / project
            directory.mkdir(parents=True, exist_ok=True)
            (directory / ".envrc").write_text(":\n", encoding="utf-8")
        self.marker = self.root / "commands-ran"
        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        stub = """#!/bin/sh
current_umask=$(umask)
if [ -n "${UPGRADE_EXPECTED_UMASK:-}" ] \
    && [ "$current_umask" != "$UPGRADE_EXPECTED_UMASK" ]; then
    printf 'wrong umask: %s\n' "$current_umask" >&2
    exit 97
fi
printf '%s\n' "${0##*/}" >>"$UPGRADE_COMMAND_MARKER"
"""
        for command in ("nix", "cabal", "cargo", "rag-client", "huggingface-cli"):
            self.write_executable(self.fake_bin / command, stub)

    def tearDown(self):
        self.temporary.cleanup()

    @staticmethod
    def write_executable(path, content):
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)

    def environment(self, state_dir=None, **extra):
        bash = shutil.which("bash")
        self.assertIsNotNone(bash)
        env = {
            "HOME": str(self.home),
            "LC_ALL": "C",
            "PATH": os.pathsep.join(
                (
                    str(self.fake_bin),
                    str(Path(sys.executable).parent),
                    str(Path(bash).parent),
                    os.defpath,
                )
            ),
            "UPGRADE_COMMAND_MARKER": str(self.marker),
        }
        if state_dir is not None:
            env["UPGRADE_LOG_DIR"] = str(state_dir)
        env.update({key: str(value) for key, value in extra.items()})
        return env

    def run_script(self, state_dir=None, child_umask=None, **extra):
        def apply_umask():
            os.umask(child_umask)

        return subprocess.run(
            [str(UPGRADE_PROJECTS)],
            cwd=self.root,
            env=self.environment(state_dir, **extra),
            capture_output=True,
            text=True,
            check=False,
            preexec_fn=apply_umask if child_umask is not None else None,
        )

    def assert_rejected(self, state_dir, message, **extra):
        result = self.run_script(state_dir, **extra)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(message, result.stderr)
        self.assertFalse(
            self.marker.exists(), "project command ran before log validation"
        )

    def install_fd_metadata_shim(self, owner, mode):
        self.write_executable(
            self.fake_bin / "python3",
            f"""#!/bin/sh
if [ "$2" = fstat ]; then
    printf '%s %s %s\n' {owner} {mode} regular
    exit 0
fi
exec "$UPGRADE_REAL_PYTHON" "$@"
            """,
        )

    def install_anchor_race_shim(self, replacement):
        self.write_executable(
            self.fake_bin / "python3",
            f"""#!/bin/sh
if [ "$2" = anchor ]; then
    mv -- "$3" "$3.moved"
    {replacement}
fi
exec "$UPGRADE_REAL_PYTHON" "$@"
""",
        )

    def test_concurrent_runs_use_private_per_run_state(self):
        state_dir = self.home / ".local/state/upgrade-projects"
        state_dir.mkdir(parents=True)
        state_dir.chmod(0o700)
        for index in range(10):
            old_run = state_dir / f"run.20000101T0000{index:02}Z.fixture"
            old_run.mkdir(mode=0o700)
            complete = old_run / ".complete"
            complete.touch(mode=0o600)
            complete.chmod(0o600)

        active_run = state_dir / "run.19990101T000000Z.active"
        active_run.mkdir(mode=0o700)
        active_marker = active_run / ".active"
        active_marker.touch(mode=0o600)
        active_marker.chmod(0o600)
        old_time = time.time() - 7200
        os.utime(active_run, (old_time, old_time))

        abandoned_run = state_dir / "run.19980101T000000Z.abandoned"
        abandoned_run.mkdir(mode=0o700)
        abandoned_marker = abandoned_run / ".active"
        abandoned_marker.touch(mode=0o600)
        abandoned_marker.chmod(0o600)
        os.utime(abandoned_run, (old_time, old_time))

        symlink_run = state_dir / "run.19970101T000000Z.symlink"
        symlink_run.mkdir(mode=0o700)
        symlink_target = self.root / "active-target"
        symlink_target.touch(mode=0o600)
        (symlink_run / ".active").symlink_to(symlink_target)
        os.utime(symlink_run, (old_time, old_time))

        fifo_run = state_dir / "run.19960101T000000Z.fifo"
        fifo_run.mkdir(mode=0o700)
        fifo_marker = fifo_run / ".active"
        os.mkfifo(fifo_marker, mode=0o600)
        os.utime(fifo_run, (old_time, old_time))

        env = self.environment()
        with active_marker.open("r", encoding="utf-8") as active_file:
            fcntl.flock(active_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
            processes = [
                subprocess.Popen(
                    [str(UPGRADE_PROJECTS)],
                    cwd=self.root,
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                for _ in range(2)
            ]
            results = [process.communicate(timeout=30) for process in processes]

        run_paths = []
        for process, (stdout, stderr) in zip(processes, results, strict=True):
            self.assertEqual(process.returncode, 0, stdout + stderr)
            report = next(
                line
                for line in stdout.splitlines()
                if line.startswith("upgrade-projects: logs: ")
            )
            run_paths.append(Path(report.removeprefix("upgrade-projects: logs: ")))

        self.assertEqual(stat.S_IMODE(state_dir.stat().st_mode), 0o700)
        runs = [path for path in state_dir.iterdir() if path.name.startswith("run.")]
        self.assertEqual(len(runs), 13)
        self.assertTrue(active_run.exists())
        self.assertFalse(abandoned_run.exists())
        self.assertTrue(symlink_run.exists())
        self.assertTrue(fifo_run.exists())
        self.assertEqual(len(set(run_paths)), 2)
        for run in run_paths:
            self.assertTrue(run.exists())
            self.assertFalse(run.is_symlink())
            self.assertEqual(stat.S_IMODE(run.stat().st_mode), 0o700)
            self.assertEqual(run.stat().st_uid, os.geteuid())
            logs = list(run.glob("*.log"))
            self.assertTrue(logs)
            for log in logs:
                self.assertTrue(log.is_file())
                self.assertFalse(log.is_symlink())
                self.assertEqual(stat.S_IMODE(log.stat().st_mode), 0o600)
                self.assertEqual(log.stat().st_uid, os.geteuid())
            for marker in (run / ".active", run / ".complete"):
                self.assertTrue(marker.is_file())
                self.assertEqual(stat.S_IMODE(marker.stat().st_mode), 0o600)
        self.assertFalse(
            any(path.name.startswith(".prune.") for path in state_dir.iterdir())
        )

    def test_rejects_symlink_state_directory(self):
        target = self.root / "state-target"
        target.mkdir(mode=0o700)
        state_dir = self.root / "state-link"
        state_dir.symlink_to(target, target_is_directory=True)
        self.assert_rejected(state_dir, "log state directory is a symlink")

    def test_rejects_symlink_state_directory_with_trailing_slash(self):
        target = self.root / "state-target"
        target.mkdir(mode=0o700)
        state_dir = self.root / "state-link"
        state_dir.symlink_to(target, target_is_directory=True)
        self.assert_rejected(f"{state_dir}/", "log state directory is a symlink")

    def test_rejects_terminal_dot_hiding_state_symlink(self):
        target = self.root / "state-target"
        target.mkdir(mode=0o700)
        state_dir = self.root / "state-link"
        state_dir.symlink_to(target, target_is_directory=True)
        self.assert_rejected(
            f"{state_dir}/.", "log state directory must not end in . or .."
        )

    def test_rejects_terminal_dotdot_hiding_state_symlink(self):
        target = self.root / "state-target"
        child = target / "child"
        child.mkdir(parents=True, mode=0o700)
        state_dir = self.root / "state-link"
        state_dir.symlink_to(child, target_is_directory=True)
        self.assert_rejected(
            f"{state_dir}/..", "log state directory must not end in . or .."
        )

    def test_rejects_state_anchor_inode_mismatch(self):
        state_dir = self.root / "state"
        self.install_anchor_race_shim('mkdir "$3"; chmod 700 "$3"')
        self.assert_rejected(
            state_dir,
            "log state directory changed while anchoring",
            UPGRADE_REAL_PYTHON=sys.executable,
        )

    def test_rejects_final_symlink_during_anchor(self):
        state_dir = self.root / "state"
        self.install_anchor_race_shim('ln -s "$3.moved" "$3"')
        self.assert_rejected(
            state_dir,
            "log state directory changed while anchoring",
            UPGRADE_REAL_PYTHON=sys.executable,
        )

    def test_rejects_foreign_owner_metadata(self):
        state_dir = self.root / "state"
        state_dir.mkdir(mode=0o700)
        wrong_uid = os.geteuid() + 1
        self.write_executable(
            self.fake_bin / "stat",
            f"#!/bin/sh\nprintf '%s %s\\n' {wrong_uid} 700\n",
        )
        self.assert_rejected(
            state_dir, f"has owner {wrong_uid}, expected {os.geteuid()}"
        )

    def test_rejects_open_state_directory_mode(self):
        state_dir = self.root / "state"
        state_dir.mkdir(mode=0o700)
        state_dir.chmod(0o755)
        self.assert_rejected(state_dir, "has mode 755, expected 700")

    def test_rejects_relative_log_override(self):
        self.assert_rejected(
            "relative-state", "UPGRADE_LOG_DIR must be absolute: relative-state"
        )

    def test_ignores_relative_xdg_state_home(self):
        result = self.run_script(XDG_STATE_HOME="relative-state")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.home / ".local/state/upgrade-projects").is_dir())
        self.assertFalse((self.root / "relative-state").exists())

    def test_retention_api_check_does_not_run_projects(self):
        result = subprocess.run(
            [str(UPGRADE_PROJECTS), "--retention-api-check"],
            cwd=self.root,
            env=self.environment(),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.marker.exists())
        self.assertFalse((self.home / ".local/state/upgrade-projects").exists())

    def test_retention_api_check_propagates_probe_failure(self):
        self.write_executable(self.fake_bin / "python3", "#!/bin/sh\nexit 1\n")
        result = subprocess.run(
            [str(UPGRADE_PROJECTS), "--retention-api-check"],
            cwd=self.root,
            env=self.environment(),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("required retention APIs are unavailable", result.stderr)
        self.assertFalse(self.marker.exists())
        self.assertFalse((self.home / ".local/state/upgrade-projects").exists())

    def test_project_commands_inherit_caller_umask(self):
        state_dir = self.root / "state"
        result = self.run_script(
            state_dir,
            child_umask=0o027,
            UPGRADE_EXPECTED_UMASK="0027",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_rejects_wrong_log_descriptor_owner(self):
        state_dir = self.root / "state"
        wrong_uid = os.geteuid() + 1
        self.install_fd_metadata_shim(wrong_uid, 600)
        self.assert_rejected(
            state_dir,
            f"open log descriptor has owner {wrong_uid}, expected {os.geteuid()}",
            UPGRADE_REAL_PYTHON=sys.executable,
        )

    def test_rejects_wrong_log_descriptor_mode(self):
        state_dir = self.root / "state"
        self.install_fd_metadata_shim(os.geteuid(), 644)
        self.assert_rejected(
            state_dir,
            "open log descriptor has mode 644, expected 600",
            UPGRADE_REAL_PYTHON=sys.executable,
        )

    def test_rejects_log_symlink_before_project_commands(self):
        state_dir = self.root / "state"
        state_dir.mkdir(mode=0o700)
        target = self.root / "target.log"
        target.write_text("unchanged\n", encoding="utf-8")
        self.write_executable(
            self.fake_bin / "mktemp",
            """#!/bin/sh
run_name=run.injected
mkdir -p "$run_name"
chmod 700 "$run_name"
ln -s "$UPGRADE_SYMLINK_TARGET" \
    "$run_name/category-theory-build.log"
printf '%s\n' "$run_name"
""",
        )
        self.assert_rejected(
            state_dir,
            "cannot exclusively create log file",
            UPGRADE_SYMLINK_TARGET=target,
        )
        self.assertEqual(target.read_text(encoding="utf-8"), "unchanged\n")


if __name__ == "__main__":
    unittest.main()
