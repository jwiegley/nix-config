#!/usr/bin/env python3
"""Behavioral tests for transactional YubiKey key-file switching."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
YUBIKEY_SWITCH = REPO / "bin/yubikey-switch"
KEYS = (
    "4975B4558FC5A7699D4E6DFD940DF0A5633B661F.key",
    "99C79A2052C3B513DF26BB5B03519C83328F13E1.key",
    "A8ADF3692CFDEA476DD3EF8191DF7C5806C0C825.key",
)


class YubiKeySwitchTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)
        self.home = self.root / "home"
        self.key_dir = self.home / ".config/gnupg/private-keys-v1.d"
        self.key_dir.mkdir(parents=True)
        (self.home / "src/category-theory").mkdir(parents=True)

        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        self.side_effects = self.root / "side-effects"
        self.key_state_check = self.root / "key-state-check.py"
        self.key_state_check.write_text(
            """import os
import re
import stat
import subprocess
import sys
from pathlib import Path

key_dir = Path(os.environ["KEY_DIR"])
lock_dir = key_dir / ".yubikey-switch.lock"
if not lock_dir.is_dir():
    raise SystemExit(f"transaction lock is absent before side effects: {lock_dir}")
if any(lock_dir.iterdir()):
    raise SystemExit(f"transaction lock retains plaintext before side effects: {lock_dir}")
for key in os.environ["EXPECTED_KEYS"].split(os.pathsep):
    path = key_dir / key
    mode = stat.S_IMODE(path.stat().st_mode)
    if mode != 0o600:
        raise SystemExit(f"active key has mode {mode:o}, expected 600: {path}")
    if sys.platform == "darwin":
        listing = subprocess.run(
            ["/bin/ls", "-lde", str(path)],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        if re.search(r"(?m)^\\s+\\d+:", listing):
            raise SystemExit(f"active key retains an ACL: {path}")
""",
            encoding="utf-8",
        )
        for command in ("sudo", "sleep", "gpg", "git", "ykpamcfg"):
            snapshot = f'printf "%s" "{command}" >>"$SIDE_EFFECTS"\n'
            for key in KEYS:
                snapshot += (
                    f'printf ":%s" "$(cat "$KEY_DIR/{key}")" >>"$SIDE_EFFECTS"\n'
                )
            if command == "sudo":
                snapshot = (
                    '"$PYTHON" "$KEY_STATE_CHECK" || '
                    '{ kill -TERM "$PPID"; exit 90; }\n' + snapshot
                )
            else:
                snapshot = '"$PYTHON" "$KEY_STATE_CHECK" || exit 90\n' + snapshot
            self.write_stub(
                command,
                snapshot + 'printf "\\n" >>"$SIDE_EFFECTS"\n',
            )

        self.env = {
            "HOME": str(self.home),
            "KEY_DIR": str(self.key_dir),
            "PATH": f"{self.fake_bin}{os.pathsep}{os.defpath}",
            "SIDE_EFFECTS": str(self.side_effects),
            "PYTHON": sys.executable,
            "KEY_STATE_CHECK": str(self.key_state_check),
            "EXPECTED_KEYS": os.pathsep.join(KEYS),
        }

    def write_stub(self, name, body):
        stub = self.fake_bin / name
        stub.write_text(f"#!/bin/sh\n{body}", encoding="utf-8")
        stub.chmod(0o700)

    def prepare_keys(self, mode="test", prefix="new"):
        for index, key in enumerate(KEYS):
            active = self.key_dir / key
            source = self.key_dir / f"{key}.{mode}"
            active.write_text(f"old-{index}\n", encoding="utf-8")
            active.chmod(0o600)
            source.write_text(f"{prefix}-{index}\n", encoding="utf-8")
            source.chmod(0o444)

    def prepare_restore_keys(self, active_indices=()):
        restore_root = self.root / "restore/private-keys-v1.d"
        restore_root.mkdir(parents=True)
        self.env["YUBIKEY_SWITCH_TEST_RESTORE_ROOT"] = str(restore_root)
        for index, key in enumerate(KEYS):
            source = restore_root / key
            source.write_text(f"new-{index}\n", encoding="utf-8")
            source.chmod(0o444)
            if index in active_indices:
                active = self.key_dir / key
                active.write_text(f"old-{index}\n", encoding="utf-8")
                active.chmod(0o600)

    def run_switch(self, mode="test"):
        return subprocess.run(
            [str(YUBIKEY_SWITCH), mode],
            cwd=self.root,
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def assert_active_keys(self, prefix):
        self.assertEqual(
            [(self.key_dir / key).read_text(encoding="utf-8") for key in KEYS],
            [f"{prefix}-{index}\n" for index in range(len(KEYS))],
        )

    def active_key_state(self):
        state = []
        for key in KEYS:
            path = self.key_dir / key
            if not path.exists():
                state.append(None)
            else:
                state.append((path.read_bytes(), path.stat().st_mode & 0o7777))
        return state

    def assert_no_side_effects(self):
        self.assertFalse(self.side_effects.exists())

    def assert_no_transaction_files(self):
        self.assertEqual(list(self.key_dir.glob(".yubikey-switch.*")), [])

    def fail_copy_at(self, invocation):
        real_cp = shutil.which("cp", path=os.defpath)
        self.assertIsNotNone(real_cp)
        self.write_stub(
            "cp",
            'count=$(cat "$CP_COUNT" 2>/dev/null || printf 0)\n'
            "count=$((count + 1))\n"
            'printf "%s" "$count" >"$CP_COUNT"\n'
            'if [ "$count" -eq "$CP_FAIL_AT" ]; then exit 71; fi\n'
            'exec "$REAL_CP" "$@"\n',
        )
        self.env.update(
            {
                "CP_COUNT": str(self.root / "cp-count"),
                "CP_FAIL_AT": str(invocation),
                "REAL_CP": real_cp,
            }
        )

    def fail_install_at(self, invocation):
        real_install = shutil.which("install", path=os.defpath)
        self.assertIsNotNone(real_install)
        self.write_stub(
            "install",
            'count=$(cat "$INSTALL_COUNT" 2>/dev/null || printf 0)\n'
            "count=$((count + 1))\n"
            'printf "%s" "$count" >"$INSTALL_COUNT"\n'
            'if [ "$count" -eq "$INSTALL_FAIL_AT" ]; then exit 71; fi\n'
            'exec "$REAL_INSTALL" "$@"\n',
        )
        self.env.update(
            {
                "INSTALL_COUNT": str(self.root / "install-count"),
                "INSTALL_FAIL_AT": str(invocation),
                "REAL_INSTALL": real_install,
            }
        )

    def test_read_only_stage_is_restricted_before_side_effects(self):
        self.prepare_keys()

        result = self.run_switch()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_active_keys("new")
        self.assertEqual(
            [entry[1] for entry in self.active_key_state() if entry is not None],
            [0o600] * len(KEYS),
        )
        observations = self.side_effects.read_text(encoding="utf-8").splitlines()
        self.assertEqual(
            [observation.split(":", 1)[0] for observation in observations],
            ["sudo", "sleep", "sudo", "gpg", "git", "ykpamcfg"],
        )
        self.assertTrue(
            all(
                observation.endswith(":new-0:new-1:new-2")
                for observation in observations
            )
        )
        self.assert_no_transaction_files()

    def test_first_side_effect_rejects_an_unhardened_active_mode(self):
        self.prepare_keys()
        real_chmod = shutil.which("chmod", path=os.defpath)
        self.assertIsNotNone(real_chmod)
        self.write_stub("chmod", 'exec "$REAL_CHMOD" 400 "$2"\n')
        self.env["REAL_CHMOD"] = real_chmod

        result = self.run_switch()

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_no_side_effects()
        self.assert_no_transaction_files()

    @unittest.skipUnless(sys.platform == "darwin", "Darwin ACL behavior")
    def test_source_acl_is_not_copied_to_active_key(self):
        self.prepare_keys()
        source = self.key_dir / f"{KEYS[0]}.test"
        subprocess.run(
            ["/bin/chmod", "+a", "everyone allow read", str(source)],
            check=True,
        )
        source_listing = subprocess.run(
            ["/bin/ls", "-lde", str(source)],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        self.assertRegex(source_listing, r"(?m)^\s+\d+:")

        result = self.run_switch()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for key in KEYS:
            listing = subprocess.run(
                ["/bin/ls", "-lde", str(self.key_dir / key)],
                check=True,
                capture_output=True,
                text=True,
            ).stdout
            self.assertNotRegex(listing, r"(?m)^\s+\d+:")

    def test_restore_populates_an_empty_active_key_directory(self):
        self.prepare_restore_keys()

        result = self.run_switch("restore")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_active_keys("new")
        self.assertEqual(
            [entry[1] for entry in self.active_key_state() if entry is not None],
            [0o600] * len(KEYS),
        )
        self.assert_no_transaction_files()

    def test_failed_restore_restores_existing_keys_and_removes_new_keys(self):
        self.prepare_restore_keys(active_indices=(0, 2))
        before = self.active_key_state()
        real_mv = shutil.which("mv", path=os.defpath)
        self.assertIsNotNone(real_mv)
        self.write_stub(
            "mv",
            'count=$(cat "$MV_COUNT" 2>/dev/null || printf 0)\n'
            "count=$((count + 1))\n"
            'printf "%s" "$count" >"$MV_COUNT"\n'
            'if [ "$count" -eq 3 ]; then exit 72; fi\n'
            'exec "$REAL_MV" "$@"\n',
        )
        self.env.update({"MV_COUNT": str(self.root / "mv-count"), "REAL_MV": real_mv})

        result = self.run_switch("restore")

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("rolling back", result.stderr)
        self.assertEqual(self.active_key_state(), before)
        self.assert_no_side_effects()
        self.assert_no_transaction_files()

    def test_missing_restore_root_has_no_effects(self):
        self.prepare_keys()
        restore_root = self.root / "missing-restore-root"
        self.env["YUBIKEY_SWITCH_TEST_RESTORE_ROOT"] = str(restore_root)
        before = self.active_key_state()

        result = self.run_switch("restore")

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(str(restore_root / KEYS[0]), result.stderr)
        self.assertEqual(self.active_key_state(), before)
        self.assert_no_side_effects()
        self.assert_no_transaction_files()

    def test_stale_transaction_path_is_refused_and_retained(self):
        self.prepare_keys()
        stale = self.key_dir / ".yubikey-switch.stale"
        stale.mkdir()
        sentinel = stale / "plaintext-key"
        sentinel.write_text("retained\n", encoding="utf-8")
        before = self.active_key_state()

        result = self.run_switch()

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("stale transaction path", result.stderr)
        self.assertEqual(self.active_key_state(), before)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "retained\n")
        self.assert_no_side_effects()

    def test_concurrent_switches_have_one_atomic_winner(self):
        self.prepare_keys("first", prefix="first")
        self.prepare_keys("second", prefix="second")
        barrier = self.root / "lock-barrier"
        barrier.mkdir()
        real_mkdir = shutil.which("mkdir", path=os.defpath)
        real_mktemp = shutil.which("mktemp", path=os.defpath)
        real_sleep = shutil.which("sleep", path=os.defpath)
        self.assertIsNotNone(real_mkdir)
        self.assertIsNotNone(real_mktemp)
        self.assertIsNotNone(real_sleep)
        # Cover the fixed lock and make the former scan-plus-mktemp race fail
        # deterministically if it is reintroduced.
        wait_for_both = (
            ': >"$BARRIER/$PARTICIPANT"\n'
            'while [ ! -e "$BARRIER/first" ] || [ ! -e "$BARRIER/second" ]; do\n'
            '    "$REAL_SLEEP" 0.01\n'
            "done\n"
        )
        self.write_stub(
            "mkdir",
            'if [ "$1" = "$TRANSACTION_LOCK" ]; then\n'
            f"{wait_for_both}"
            "fi\n"
            'exec "$REAL_MKDIR" "$@"\n',
        )
        self.write_stub(
            "mktemp",
            wait_for_both + 'exec "$REAL_MKTEMP" "$@"\n',
        )
        self.env.update(
            {
                "BARRIER": str(barrier),
                "REAL_MKDIR": real_mkdir,
                "REAL_MKTEMP": real_mktemp,
                "REAL_SLEEP": real_sleep,
                "TRANSACTION_LOCK": str(self.key_dir / ".yubikey-switch.lock"),
            }
        )
        processes = []
        outputs = []
        try:
            for participant in ("first", "second"):
                process_env = dict(self.env)
                process_env["PARTICIPANT"] = participant
                processes.append(
                    subprocess.Popen(
                        [str(YUBIKEY_SWITCH), participant],
                        cwd=self.root,
                        env=process_env,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                    )
                )
            for process in processes:
                outputs.append(process.communicate(timeout=10))
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                    process.wait()

        outcomes = [
            (participant, process.returncode, stdout, stderr)
            for participant, process, (stdout, stderr) in zip(
                ("first", "second"), processes, outputs, strict=True
            )
        ]
        winners = [outcome for outcome in outcomes if outcome[1] == 0]
        losers = [outcome for outcome in outcomes if outcome[1] != 0]
        self.assertEqual(len(winners), 1, outcomes)
        self.assertEqual(len(losers), 1, outcomes)
        self.assertIn("transaction lock exists", losers[0][3])
        self.assert_active_keys(winners[0][0])
        self.assert_no_transaction_files()

    def test_setup_failure_removes_new_transaction_directory(self):
        self.prepare_keys()
        before = self.active_key_state()
        real_mkdir = shutil.which("mkdir", path=os.defpath)
        self.assertIsNotNone(real_mkdir)
        self.write_stub(
            "mkdir",
            'count=$(cat "$MKDIR_COUNT" 2>/dev/null || printf 0)\n'
            "count=$((count + 1))\n"
            'printf "%s" "$count" >"$MKDIR_COUNT"\n'
            'if [ "$count" -eq 2 ]; then exit 73; fi\n'
            'exec "$REAL_MKDIR" "$@"\n',
        )
        self.env.update(
            {"MKDIR_COUNT": str(self.root / "mkdir-count"), "REAL_MKDIR": real_mkdir}
        )

        result = self.run_switch()

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.active_key_state(), before)
        self.assert_no_side_effects()
        self.assert_no_transaction_files()

    def test_missing_source_leaves_all_destinations_unchanged(self):
        self.prepare_keys()
        (self.key_dir / f"{KEYS[1]}.test").unlink()
        before = self.active_key_state()

        result = self.run_switch()

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(str(self.key_dir / f"{KEYS[1]}.test"), result.stderr)
        self.assertEqual(self.active_key_state(), before)
        self.assert_no_side_effects()
        self.assert_no_transaction_files()

    def test_staging_install_failure_leaves_all_destinations_unchanged(self):
        self.prepare_keys()
        before = self.active_key_state()
        self.fail_install_at(3)

        result = self.run_switch()

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.active_key_state(), before)
        self.assert_no_side_effects()
        self.assert_no_transaction_files()

    def test_backup_copy_failure_leaves_all_destinations_unchanged(self):
        self.prepare_keys()
        before = self.active_key_state()
        self.fail_copy_at(2)

        result = self.run_switch()

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.active_key_state(), before)
        self.assert_no_side_effects()
        self.assert_no_transaction_files()

    def test_quit_exits_131_before_replacement(self):
        self.prepare_keys()
        before = self.active_key_state()
        real_cp = shutil.which("cp", path=os.defpath)
        self.assertIsNotNone(real_cp)
        self.write_stub(
            "cp",
            'kill -QUIT "$PPID"\nexec "$REAL_CP" "$@"\n',
        )
        self.env["REAL_CP"] = real_cp

        result = self.run_switch()

        self.assertEqual(result.returncode, 131, result.stdout + result.stderr)
        self.assertEqual(self.active_key_state(), before)
        self.assert_no_side_effects()
        self.assert_no_transaction_files()

    def test_finalization_failure_rolls_back_every_destination(self):
        self.prepare_keys()
        before = self.active_key_state()
        real_mv = shutil.which("mv", path=os.defpath)
        self.assertIsNotNone(real_mv)
        count_file = self.root / "mv-count"
        self.write_stub(
            "mv",
            'count=$(cat "$MV_COUNT" 2>/dev/null || printf 0)\n'
            "count=$((count + 1))\n"
            'printf "%s" "$count" >"$MV_COUNT"\n'
            'if [ "$count" -eq 2 ]; then exit 72; fi\n'
            'if [ "$count" -eq 3 ]; then\n'
            '    kill -HUP "$PPID"\n'
            '    kill -INT "$PPID"\n'
            '    kill -QUIT "$PPID"\n'
            '    kill -TERM "$PPID"\n'
            "fi\n"
            'exec "$REAL_MV" "$@"\n',
        )
        self.env.update({"MV_COUNT": str(count_file), "REAL_MV": real_mv})

        result = self.run_switch()

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("rolling back", result.stderr)
        self.assertEqual(self.active_key_state(), before)
        self.assert_no_side_effects()
        self.assert_no_transaction_files()


if __name__ == "__main__":
    unittest.main()
