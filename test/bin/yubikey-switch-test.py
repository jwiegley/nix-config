#!/usr/bin/env python3
"""Behavioral tests for transactional YubiKey key-file switching."""

import os
import shutil
import subprocess
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
        for command in ("sudo", "sleep", "gpg", "git", "ykpamcfg"):
            snapshot = f'printf "%s" "{command}" >>"$SIDE_EFFECTS"\n'
            for key in KEYS:
                snapshot += (
                    f'printf ":%s" "$(cat "$KEY_DIR/{key}")" >>"$SIDE_EFFECTS"\n'
                )
            self.write_stub(
                command,
                snapshot + 'printf "\\n" >>"$SIDE_EFFECTS"\n',
            )

        self.env = {
            "HOME": str(self.home),
            "KEY_DIR": str(self.key_dir),
            "PATH": f"{self.fake_bin}{os.pathsep}{os.defpath}",
            "SIDE_EFFECTS": str(self.side_effects),
        }

    def write_stub(self, name, body):
        stub = self.fake_bin / name
        stub.write_text(f"#!/bin/sh\n{body}", encoding="utf-8")
        stub.chmod(0o700)

    def prepare_keys(self, mode="test"):
        for index, key in enumerate(KEYS):
            active = self.key_dir / key
            source = self.key_dir / f"{key}.{mode}"
            active.write_text(f"old-{index}\n", encoding="utf-8")
            active.chmod(0o600)
            source.write_text(f"new-{index}\n", encoding="utf-8")
            source.chmod(0o644)

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
        return [
            (
                (self.key_dir / key).read_bytes(),
                (self.key_dir / key).stat().st_mode & 0o7777,
            )
            for key in KEYS
        ]

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

    def test_permissive_stage_is_restricted_before_side_effects(self):
        self.prepare_keys()

        result = self.run_switch()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_active_keys("new")
        self.assertEqual(
            [mode for _, mode in self.active_key_state()], [0o600] * len(KEYS)
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

    def test_staging_copy_failure_leaves_all_destinations_unchanged(self):
        self.prepare_keys()
        before = self.active_key_state()
        self.fail_copy_at(3)

        result = self.run_switch()

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.active_key_state(), before)
        self.assert_no_side_effects()
        self.assert_no_transaction_files()

    def test_backup_copy_failure_leaves_all_destinations_unchanged(self):
        self.prepare_keys()
        before = self.active_key_state()
        self.fail_copy_at(5)

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
