#!/usr/bin/env python3
"""Behavioral tests for bin/de's generated direnv cache."""

import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
DE = REPO / "bin/de"
SYSTEM_BASH = "/bin/bash"

LEGACY_ENVRC = r"""keep_vars() {
    local k v
    DIRENV_kept=
    for k in "$@"; do
        [[ -v $k ]] || continue
        v=${!k}
        DIRENV_kept="$DIRENV_kept"$(printf "%s=%s\000" "$k" "$v" | base64)
    done
}

reset_kept() {
    : ${DIRENV_kept?No environment stored. Missing keep_except()?}
    echo "$DIRENV_kept" | base64 -d | while IFS= read -r -d '' V; do
        echo "export ${V%%=*}='${V#*=}'"
    done
    unset DIRENV_kept
}

keep_vars                                       \
    ALTERNATE_EDITOR                            \
    COLORTERM                                   \
    EDITOR                                      \
    EMACS_SERVER_FILE                           \
    GIT_PROMPT_EXECUTABLE                       \
    GH_ACCOUNT                                  \
    ITERM_SESSION_ID                            \
    NIX_PATH                                    \
    GIT_PAGER                                   \
    PAGER                                       \
    NO_COLOR                                    \
    PERSONA                                     \
    PROMPT                                      \
    RPROMPT                                     \
    SECURITYSESSIONID                           \
    SSH_AUTH_SOCK                               \
    SSL_CERT_FILE                               \
    STARSHIP_CONFIG                             \
    STARSHIP_SESSION_KEY                        \
    STARSHIP_SHELL                              \
    TERM                                        \
    TERM_SESSION_ID                             \
    TMPDIR                                      \
    XDG_DATA_DIRS                               \
    __GIT_PROMPT_DIR

source <(direnv apply_dump .envrc.cache)
source <(reset_kept)
[[ ! -v TMPDIR || -d $TMPDIR ]] || unset TMPDIR

watch_file .envrc
watch_file .envrc.cache
watch_file default.nix
watch_file shell.nix
"""


class DeTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)
        self.home = self.root / "home"
        self.project = self.root / "project"
        self.fake_bin = self.root / "bin"
        self.home.mkdir()
        self.project.mkdir()
        self.fake_bin.mkdir()
        (self.project / "shell.nix").write_text("{}\n", encoding="utf-8")
        self.write_executable(
            "nix-shell",
            """#!/bin/bash
set -e
while (( $# )); do
    if [[ $1 == --run ]]; then
        exec bash -c "$2"
    fi
    shift
done
exit 64
""",
        )
        self.write_executable(
            "direnv",
            """#!/bin/bash
set -e
case $1 in
export)
    [[ $2 == bash && $PWD == / ]] || exit 65
    if [[ ${DIRENV_TEST_INCOMPLETE_UNLOAD+x} ]]; then
        printf '%s\\n' \\
            'unset SECRET_SENTINEL DIRENV_DIR DIRENV_FILE DIRENV_WATCHES'
    else
        printf '%s\\n' \\
            'unset SECRET_SENTINEL DIRENV_DIFF DIRENV_DIR DIRENV_FILE DIRENV_WATCHES'
    fi
    ;;
dump)
    if [[ ${DIRENV_TEST_DUMP_FAIL+x} ]]; then
        printf 'partial-dump\\n'
        exit 23
    fi
    if [[ ${CACHE_SENTINEL+x} ]]; then
        printf 'CACHE_SENTINEL=%s\\n' "$CACHE_SENTINEL"
    fi
    if [[ ${SECRET_SENTINEL+x} ]]; then
        printf 'SECRET_SENTINEL=%s\\n' "$SECRET_SENTINEL"
    fi
    ;;
apply_dump)
    if [[ ${DIRENV_TEST_APPLY_FAIL+x} ]]; then
        exit 24
    fi
    printf '%s\\n' 'unset EDITOR SECRET_SENTINEL' \\
        'export CACHE_SENTINEL=from-cache'
    ;;
reload)
    ;;
*)
    exit 64
    ;;
esac
""",
        )

    def write_executable(self, name, contents):
        path = self.fake_bin / name
        path.write_text(contents, encoding="utf-8")
        path.chmod(0o755)

    def run_de(self, additions=None, expected_returncode=0):
        env = {
            "CACHE_SENTINEL": "cache-visible",
            "DIRENV_DIFF": "active-direnv-diff",
            "DIRENV_DIR": "-ignored",
            "DIRENV_FILE": str(self.project / ".envrc"),
            "DIRENV_WATCHES": "active-direnv-watches",
            "HOME": str(self.home),
            "PATH": f"{self.fake_bin}{os.pathsep}{os.defpath}",
            "SECRET_SENTINEL": "active-direnv-secret",
            **(additions or {}),
        }
        result = subprocess.run(
            [str(DE)],
            cwd=self.project,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            expected_returncode,
            result.stdout + result.stderr,
        )
        return result

    def test_env_secret_is_loaded_after_private_cache_is_written(self):
        secret = "sentinel-secret-must-not-be-cached"
        (self.project / ".env").write_text(
            f"SECRET_SENTINEL={secret}\n", encoding="utf-8"
        )
        cache = self.project / ".envrc.cache"
        cache.write_text("old-public-cache\n", encoding="utf-8")
        cache.chmod(0o644)
        old_cache_inode = cache.stat().st_ino

        self.run_de()

        self.assertNotEqual(cache.stat().st_ino, old_cache_inode)
        self.assertEqual(stat.S_IMODE(cache.stat().st_mode), 0o600)
        cache_contents = cache.read_text(encoding="utf-8")
        self.assertIn("CACHE_SENTINEL=cache-visible", cache_contents)
        self.assertNotIn("active-direnv-secret", cache_contents)
        self.assertNotIn("SECRET_SENTINEL", cache_contents)
        self.assertNotIn(secret, cache_contents)

        self.run_de()
        result = self.run_envrc({"EDITOR": "caller-editor"})
        editor, loaded_secret, cached = result.stdout.split(b"\0")[:3]
        self.assertEqual(editor, b"caller-editor")
        self.assertEqual(loaded_secret, secret.encode())
        self.assertEqual(cached, b"from-cache")

    def test_preserved_quotes_newlines_and_metacharacters_remain_data(self):
        marker = self.root / "injected"
        sentinel = (
            'quote\'\nprintf injected >"$DIRENV_TEST_MARKER"\n'
            "# newline; $(false) `$HOME`"
        )
        (self.project / ".env").write_text(
            "SECRET_SENTINEL=loaded-after-cache\n", encoding="utf-8"
        )
        self.run_de()

        result = self.run_envrc(
            {
                "DIRENV_TEST_MARKER": str(marker),
                "EDITOR": sentinel,
            }
        )

        editor, loaded_secret, cached = result.stdout.split(b"\0")[:3]
        self.assertEqual(editor, sentinel.encode())
        self.assertEqual(loaded_secret, b"loaded-after-cache")
        self.assertEqual(cached, b"from-cache")
        self.assertFalse(marker.exists())

    def test_apply_dump_failure_stops_before_env_is_loaded(self):
        (self.project / ".env").write_text(
            "SECRET_SENTINEL=must-not-load\n", encoding="utf-8"
        )
        self.run_de()

        result = self.run_envrc(
            {
                "DIRENV_TEST_APPLY_FAIL": "1",
                "EDITOR": "caller-editor",
            },
            expected_returncode=1,
        )

        self.assertEqual(result.stdout, b"")
        self.assertIn(b"could not decode .envrc.cache", result.stderr)

    def test_exact_legacy_envrc_is_atomically_migrated(self):
        envrc = self.project / ".envrc"
        envrc.write_text(LEGACY_ENVRC, encoding="utf-8")
        legacy_inode = envrc.stat().st_ino

        result = self.run_de()

        migrated = envrc.read_text(encoding="utf-8")
        self.assertNotEqual(envrc.stat().st_ino, legacy_inode)
        self.assertIn("migrated the legacy generated .envrc", result.stderr)
        self.assertIn("source .env", migrated)
        self.assertNotIn("source <(reset_kept)", migrated)
        self.assertNotIn("[[ -v", migrated)
        self.assertEqual(list(self.project.glob(".envrc.current.*")), [])
        self.assertEqual(list(self.project.glob(".envrc.legacy.*")), [])

    def test_unrecognized_envrc_fails_with_regeneration_guidance(self):
        envrc = self.project / ".envrc"
        envrc.write_text("export CUSTOM_ENVRC=1\n", encoding="utf-8")

        result = self.run_de(expected_returncode=1)

        self.assertEqual(envrc.read_text(encoding="utf-8"), "export CUSTOM_ENVRC=1\n")
        self.assertIn("remove .envrc and rerun de", result.stderr)
        self.assertFalse((self.project / ".envrc.cache").exists())

    def test_successful_but_incomplete_direnv_unload_is_rejected(self):
        result = self.run_de(
            {"DIRENV_TEST_INCOMPLETE_UNLOAD": "1"},
            expected_returncode=1,
        )

        self.assertIn("direnv did not restore", result.stderr)
        self.assertFalse((self.project / ".envrc").exists())
        self.assertFalse((self.project / ".envrc.cache").exists())

    def test_failed_dump_preserves_old_cache_and_removes_temporary_file(self):
        cache = self.project / ".envrc.cache"
        cache.write_text("known-good-cache\n", encoding="utf-8")
        cache.chmod(0o640)
        old_cache_inode = cache.stat().st_ino

        self.run_de(
            {"DIRENV_TEST_DUMP_FAIL": "1"},
            expected_returncode=23,
        )

        self.assertEqual(cache.read_text(encoding="utf-8"), "known-good-cache\n")
        self.assertEqual(cache.stat().st_ino, old_cache_inode)
        self.assertEqual(stat.S_IMODE(cache.stat().st_mode), 0o640)
        self.assertEqual(list(self.project.glob(".envrc.cache.*")), [])

    def test_cache_symlink_is_rejected_without_touching_target(self):
        target = self.root / "cache-target"
        target.write_text("do-not-touch\n", encoding="utf-8")
        cache = self.project / ".envrc.cache"
        cache.symlink_to(target)

        result = self.run_de(expected_returncode=1)

        self.assertIn("refusing to replace symlink", result.stderr)
        self.assertTrue(cache.is_symlink())
        self.assertEqual(target.read_text(encoding="utf-8"), "do-not-touch\n")
        self.assertFalse((self.project / ".envrc").exists())
        self.assertEqual(list(self.project.glob(".envrc.cache.*")), [])

    def test_cache_directory_is_rejected_without_modification(self):
        cache = self.project / ".envrc.cache"
        cache.mkdir()

        result = self.run_de(expected_returncode=1)

        self.assertIn("refusing to replace non-regular", result.stderr)
        self.assertTrue(cache.is_dir())
        self.assertEqual(list(cache.iterdir()), [])
        self.assertFalse((self.project / ".envrc").exists())

    def run_envrc(self, additions, expected_returncode=0):
        env = {
            "HOME": str(self.home),
            "PATH": f"{self.fake_bin}{os.pathsep}{os.defpath}",
            **additions,
        }
        command = r"""
set -e
watch_file() { :; }
source .envrc
printf '%s\0%s\0%s\0' "$EDITOR" "$SECRET_SENTINEL" "$CACHE_SENTINEL"
"""
        result = subprocess.run(
            [SYSTEM_BASH, "-c", command],
            cwd=self.project,
            env=env,
            capture_output=True,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            expected_returncode,
            result.stdout.decode(errors="replace")
            + result.stderr.decode(errors="replace"),
        )
        return result


if __name__ == "__main__":
    unittest.main()
