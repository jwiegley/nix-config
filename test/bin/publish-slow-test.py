#!/usr/bin/env python3
"""Tests for Gitea-only publication through bin/publish.

Remote-mutation tests use throwaway local repositories; self-consistency tests
read the real script without mutating its repository.

Run: test/bin/unittest-strict.py test/bin/publish-slow-test.py
"""

import os
import shutil
import subprocess
import tempfile
import unittest

from git_fixture import clean_env, git

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
PUBLISH = os.path.join(REPO, "bin", "publish")


class PublishHarness(unittest.TestCase):
    """A work repo whose Gitea network operations route to a local bare remote."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="publish-test-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

        self.origin = os.path.join(self.tmp, "nix-config.git")
        git("init", "--bare", "--initial-branch=main", self.origin, cwd=self.tmp)

        self.work = os.path.join(self.tmp, "work")
        git("init", "--initial-branch=main", self.work, cwd=self.tmp)
        git("config", "commit.gpgsign", "false", cwd=self.work)
        git(
            "remote",
            "add",
            "origin",
            "gitea@gitea:johnw/nix-config.git",
            cwd=self.work,
        )

        self._commit("base\n", "initial commit")
        # Seed Gitea so the branch exists; publish's signature
        # range is "what fresh Gitea refs lack", so this makes the baseline empty.
        git("push", "-q", self.origin, "main", cwd=self.work)

        # Keep the configured URL exact. A test-only Git wrapper redirects only
        # the literal Gitea authority to the local bare repository. Any network
        # command that still uses a mutable remote name fails closed.
        self.fakebin = os.path.join(self.tmp, "fakebin")
        os.mkdir(self.fakebin)
        self.real_git = shutil.which("git")
        self.assertIsNotNone(self.real_git)
        self.network_log = os.path.join(self.tmp, "network.log")
        self.network_git = os.path.join(self.fakebin, "git")
        with open(self.network_git, "w") as fh:
            fh.write(
                """#!/usr/bin/env python3
import os
import subprocess
import sys

args = sys.argv[1:]
if args and args[0] in ("fetch", "ls-remote", "push"):
    expected = os.environ["PUBLISH_TEST_EXPECTED_URL"]
    with open(os.environ["PUBLISH_TEST_NETWORK_LOG"], "a") as log:
        print(" ".join(args), file=log)
    if expected not in args:
        print("publish test blocked a non-Gitea network destination", file=sys.stderr)
        sys.exit(97)
    injected = os.environ.get("PUBLISH_TEST_INJECT_SNAPSHOT_SHA")
    if args[0] == "fetch" and injected:
        subprocess.run(
            [
                os.environ["PUBLISH_TEST_REAL_GIT"],
                "--git-dir=" + os.environ["GIT_DIR"],
                "update-ref",
                "refs/publish-snapshot/injected",
                injected,
            ],
            check=True,
        )
    args = [
        "file://" + os.environ["PUBLISH_TEST_REMOTE"] if arg == expected else arg
        for arg in args
    ]
os.execv(os.environ["PUBLISH_TEST_REAL_GIT"], ["git", *args])
"""
            )
        os.chmod(self.network_git, 0o755)

    def _commit(self, content, message):
        p = os.path.join(self.work, "file.txt")
        with open(p, "a") as fh:
            fh.write(content)
        git("add", "file.txt", cwd=self.work)
        git("commit", "-q", "--no-gpg-sign", "-m", message, cwd=self.work)
        return git("rev-parse", "HEAD", cwd=self.work).stdout.strip()

    def publish(self, *args):
        env = clean_env()
        env.update(
            PATH=self.fakebin + os.pathsep + env["PATH"],
            PUBLISH_TEST_REAL_GIT=self.real_git,
            PUBLISH_TEST_REMOTE=self.origin,
            PUBLISH_TEST_EXPECTED_URL="gitea@gitea:johnw/nix-config.git",
            PUBLISH_TEST_NETWORK_LOG=self.network_log,
        )
        return subprocess.run(
            [PUBLISH, *args],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=env,
        )

    def remote_sha(self, bare, branch="main"):
        r = git("ls-remote", bare, "refs/heads/%s" % branch, cwd=self.work)
        out = r.stdout.split()
        return out[0] if out else None

    def network_actions(self):
        if not os.path.exists(self.network_log):
            return []
        with open(self.network_log) as fh:
            return [line.strip() for line in fh if line.strip()]


class TestNoop(PublishHarness):
    def test_unsigned_gitea_tip_is_refused_even_when_already_current(self):
        before = self.remote_sha(self.origin)
        r = self.publish("--dry-run")
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("unsigned branch tip", r.stderr.lower())
        self.assertEqual(self.remote_sha(self.origin), before)


@unittest.skipUnless(shutil.which("lefthook"), "lefthook not available")
class TestEmptyRangePrePush(PublishHarness):
    def test_tracked_tree_scope_runs_for_empty_range_and_empty_index(self):
        marker = os.path.join(self.tmp, "pre-push-ran")
        config = os.path.join(self.work, "lefthook.yml")

        with open(config, "w") as fh:
            fh.write(
                "pre-push:\n"
                "  files: '{ git ls-files; printf \"%s\\n\" lefthook.yml; }'\n"
                "  commands:\n"
                "    probe:\n"
                "      run: ': {files}; printf ran >>\"$EMPTY_RANGE_MARKER\"'\n"
            )
        installed = subprocess.run(
            ["lefthook", "install", "--force"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(),
        )
        self.assertEqual(installed.returncode, 0, installed.stdout + installed.stderr)

        forced = git(
            "push",
            self.origin,
            "main",
            cwd=self.work,
            check=False,
            env={"EMPTY_RANGE_MARKER": marker},
        )
        self.assertEqual(forced.returncode, 0, forced.stdout + forced.stderr)
        self.assertTrue(os.path.exists(marker), forced.stdout + forced.stderr)
        with open(marker) as fh:
            self.assertEqual(fh.read(), "ran")

        # A custom-file command that only runs `git ls-files` is still empty for
        # an empty index. Prove the sentinel also makes that raw-hook case run.
        os.unlink(marker)
        git("rm", "-q", "file.txt", cwd=self.work)
        git("commit", "-q", "--no-gpg-sign", "-m", "empty tree", cwd=self.work)
        self.assertEqual(git("ls-files", cwd=self.work).stdout, "")
        git("push", "-q", "--no-verify", self.origin, "main", cwd=self.work)
        empty_index = git(
            "push",
            self.origin,
            "main",
            cwd=self.work,
            check=False,
            env={"EMPTY_RANGE_MARKER": marker},
        )
        self.assertEqual(
            empty_index.returncode, 0, empty_index.stdout + empty_index.stderr
        )
        with open(marker) as fh:
            self.assertEqual(fh.read(), "ran")


class TestRefusals(PublishHarness):
    def test_force_is_refused_outright(self):
        for flag in ("--force", "-f", "--force-with-lease"):
            r = self.publish(flag)
            self.assertNotEqual(r.returncode, 0, "%s was not refused" % flag)
            self.assertIn("refusing to force-push", r.stderr)

    def test_non_gitea_remote_is_refused_before_any_push(self):
        git(
            "remote",
            "set-url",
            "origin",
            "git@github.com:jwiegley/nix-config.git",
            cwd=self.work,
        )
        head = self._commit("more\n", "second commit")
        r = self.publish()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("must fetch from gitea@gitea:johnw/nix-config.git", r.stderr)
        self.assertNotEqual(self.remote_sha(self.origin), head)

    def test_non_gitea_push_url_is_refused_before_any_push(self):
        git(
            "remote",
            "set-url",
            "--push",
            "origin",
            "git@github.com:jwiegley/nix-config.git",
            cwd=self.work,
        )
        head = self._commit("more\n", "second commit")
        r = self.publish()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("must push to gitea@gitea:johnw/nix-config.git", r.stderr)
        self.assertNotEqual(self.remote_sha(self.origin), head)

    def test_additional_remote_is_refused_before_any_fetch(self):
        git(
            "remote",
            "add",
            "github",
            "git@github.com:jwiegley/nix-config.git",
            cwd=self.work,
        )
        head = self._commit("more\n", "second commit")
        r = self.publish()
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("configured remote set must be exactly 'origin'", r.stderr)
        self.assertEqual(self.network_actions(), [])
        self.assertNotEqual(self.remote_sha(self.origin), head)

    def test_multiple_fetch_urls_are_refused_even_when_gitea_is_last(self):
        git("config", "--unset-all", "remote.origin.url", cwd=self.work)
        git(
            "config",
            "--add",
            "remote.origin.url",
            "git@github.com:jwiegley/nix-config.git",
            cwd=self.work,
        )
        git(
            "config",
            "--add",
            "remote.origin.url",
            "gitea@gitea:johnw/nix-config.git",
            cwd=self.work,
        )
        head = self._commit("more\n", "second commit")
        r = self.publish()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("must fetch from gitea@gitea:johnw/nix-config.git", r.stderr)
        self.assertNotEqual(self.remote_sha(self.origin), head)

    def test_multiple_push_urls_are_refused_even_when_gitea_is_last(self):
        git(
            "config",
            "--add",
            "remote.origin.pushurl",
            "git@github.com:jwiegley/nix-config.git",
            cwd=self.work,
        )
        git(
            "config",
            "--add",
            "remote.origin.pushurl",
            "gitea@gitea:johnw/nix-config.git",
            cwd=self.work,
        )
        head = self._commit("more\n", "second commit")
        r = self.publish()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("must push to gitea@gitea:johnw/nix-config.git", r.stderr)
        self.assertNotEqual(self.remote_sha(self.origin), head)

    def test_instead_of_rewrite_is_refused_before_any_fetch(self):
        git(
            "config",
            "url.git@github.com:jwiegley/.insteadOf",
            "gitea@gitea:johnw/",
            cwd=self.work,
        )
        head = self._commit("more\n", "second commit")
        r = self.publish()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("must fetch from gitea@gitea:johnw/nix-config.git", r.stderr)
        self.assertNotEqual(self.remote_sha(self.origin), head)

    def test_push_instead_of_rewrite_is_refused_before_any_push(self):
        git(
            "config",
            "url.git@github.com:jwiegley/.pushInsteadOf",
            "gitea@gitea:johnw/",
            cwd=self.work,
        )
        head = self._commit("more\n", "second commit")
        r = self.publish()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("must push to gitea@gitea:johnw/nix-config.git", r.stderr)
        self.assertNotEqual(self.remote_sha(self.origin), head)

    def test_unreachable_gitea_is_refused(self):
        self._commit("more\n", "second commit")
        shutil.rmtree(self.origin)
        r = self.publish()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("unreachable", r.stderr)

    def test_non_fast_forward_is_refused_and_nothing_is_pushed(self):
        # Advance Gitea independently so our history is not a descendant.
        other = os.path.join(self.tmp, "other")
        git("clone", "-q", self.origin, other, cwd=self.tmp)
        git("config", "commit.gpgsign", "false", cwd=other)
        with open(os.path.join(other, "divergent.txt"), "w") as fh:
            fh.write("theirs\n")
        git("add", "divergent.txt", cwd=other)
        git("commit", "-q", "--no-gpg-sign", "-m", "their commit", cwd=other)
        git("push", "-q", "origin", "main", cwd=other)
        origin_before = self.remote_sha(self.origin)

        head = self._commit("ours\n", "our commit")
        r = self.publish()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("NOT an ancestor", r.stderr)
        self.assertIn("will not force", r.stderr)
        self.assertEqual(self.remote_sha(self.origin), origin_before)
        self.assertNotEqual(origin_before, head)

    def test_rev_not_on_named_branch_is_refused(self):
        self._commit("a\n", "on main")
        git("checkout", "-q", "-b", "side", cwd=self.work)
        side = self._commit("b\n", "on side")
        git("checkout", "-q", "main", cwd=self.work)
        r = self.publish("--rev", side, "--branch", "main")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("must equal the current main branch tip", r.stderr)

    def test_older_revision_is_refused_before_gating_another_tree(self):
        old_tip = git("rev-parse", "HEAD", cwd=self.work).stdout.strip()
        new_tip = self._commit("new\n", "new branch tip")
        before = self.remote_sha(self.origin)

        r = self.publish("--rev", old_tip, "--branch", "main")

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("must equal the current main branch tip", r.stderr)
        self.assertEqual(self.remote_sha(self.origin), before)
        self.assertNotEqual(new_tip, before)

    def test_non_current_named_branch_is_refused_before_gating(self):
        git("checkout", "-q", "-b", "side", cwd=self.work)
        side_tip = self._commit("side\n", "side branch tip")
        git("checkout", "-q", "main", cwd=self.work)
        before = self.remote_sha(self.origin)

        r = self.publish("--rev", side_tip, "--branch", "side")

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("branch 'side' is not checked out", r.stderr)
        self.assertEqual(self.remote_sha(self.origin), before)

    def test_unknown_argument_is_refused(self):
        r = self.publish("--yolo")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("unknown argument", r.stderr)


class TestSignatureGate(PublishHarness):
    def test_unsigned_new_commit_is_refused(self):
        self._commit("unsigned\n", "an unsigned commit")
        r = self.publish("--dry-run")
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("UNSIGNED", r.stderr)
        self.assertIn("refusing to publish unsigned commits", r.stderr)

    def test_unsigned_new_branch_tip_is_refused_even_when_reachable_on_gitea(self):
        """Reachability from another branch does not waive the signed-tip rule."""
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        r = self.publish("--dry-run")
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("unsigned branch tip", r.stderr.lower())


class TestSignatureGateIsAHardStop(PublishHarness):
    def test_unsigned_commit_stops_before_any_remote_is_touched(self):
        head = self._commit("x\n", "an unsigned commit")
        before = self.remote_sha(self.origin)
        r = self.publish()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("refusing to publish unsigned commits", r.stderr)
        after = self.remote_sha(self.origin)
        self.assertEqual(before, after, "a remote moved despite the signature gate")
        self.assertNotEqual(head, after)


def _gpg_available():
    return shutil.which("gpg") is not None


@unittest.skipUnless(_gpg_available(), "gpg not available")
class TestSignedPublication(PublishHarness):
    """The real-push paths, reached with genuinely signed commits.

    Reaching this path requires passing the signature gate, which requires
    genuinely signed commits. Rather than add a test-only bypass to bin/publish —
    which would put a hole in the very guard under test — generate an ephemeral
    key in a throwaway GNUPGHOME and sign for real.
    """

    def setUp(self):
        super().setUp()
        self.gnupghome = os.path.join(self.tmp, "gnupg")
        os.makedirs(self.gnupghome, mode=0o700)
        r = subprocess.run(
            [
                "gpg",
                "--batch",
                "--pinentry-mode",
                "loopback",
                "--passphrase",
                "",
                "--quick-generate-key",
                "Publish Test <test@example.invalid>",
                "ed25519",
                "sign",
                "never",
            ],
            capture_output=True,
            text=True,
            env=clean_env(GNUPGHOME=self.gnupghome),
        )
        if r.returncode != 0:
            self.skipTest(
                "could not generate an ephemeral gpg key: %s" % r.stderr[:200]
            )
        keyid = subprocess.run(
            ["gpg", "--batch", "--list-secret-keys", "--with-colons"],
            capture_output=True,
            text=True,
            env=clean_env(GNUPGHOME=self.gnupghome),
        ).stdout
        fpr = next(
            (
                line.split(":")[9]
                for line in keyid.splitlines()
                if line.startswith("fpr:")
            ),
            None,
        )
        self.assertIsNotNone(fpr, "no fingerprint from generated key")
        gate_bin = os.path.join(self.tmp, "gate-bin")
        os.makedirs(gate_bin)
        self.gate_log = os.path.join(self.tmp, "pre-push-gates.log")
        lefthook = os.path.join(gate_bin, "lefthook")
        with open(lefthook, "w") as fh:
            fh.write(
                """#!/bin/sh
printf '%s\n' "$*" >>"$PUBLISH_GATE_LOG"
if [ "${PUBLISH_GATE_MUTATE:-}" = dirty ]; then
    printf dirty >>file.txt
elif [ "${PUBLISH_GATE_MUTATE:-}" = remote ]; then
    git config remote.origin.url git@github.com:jwiegley/nix-config.git
fi
if [ "${PUBLISH_TEST_SIGNAL_PHASE:-}" = preflight ]; then
    printf preflight >"$PUBLISH_TEST_SIGNAL_MARKER"
    kill -s "$PUBLISH_TEST_SIGNAL_NAME" "$PPID"
fi
exit "${PUBLISH_GATE_EXIT:-0}"
"""
            )
        os.chmod(lefthook, 0o755)

        # Exercise Git's actual pre-push hook path. bin/publish must suppress
        # these duplicate invocations because it runs the same authority once.
        hook = os.path.join(self.work, ".git", "hooks", "pre-push")
        with open(hook, "w") as fh:
            fh.write("#!/bin/sh\nlefthook run pre-push --force\n")
        os.chmod(hook, 0o755)
        self.signing_env = {
            "GNUPGHOME": self.gnupghome,
            "PATH": f"{gate_bin}:{self.fakebin}:{os.environ['PATH']}",
            "PUBLISH_GATE_LOG": self.gate_log,
            "PUBLISH_TEST_REAL_GIT": self.real_git,
            "PUBLISH_TEST_REMOTE": self.origin,
            "PUBLISH_TEST_EXPECTED_URL": "gitea@gitea:johnw/nix-config.git",
            "PUBLISH_TEST_NETWORK_LOG": self.network_log,
        }
        git("config", "user.signingkey", fpr, cwd=self.work)
        git("config", "gpg.format", "openpgp", cwd=self.work)
        git("config", "commit.gpgsign", "true", cwd=self.work)
        # Signed-publication fixtures start from a signed remote root so a new
        # target branch can conservatively verify its complete ancestry.
        git(
            "commit",
            "-q",
            "--amend",
            "--no-edit",
            "-S",
            cwd=self.work,
            env=self.signing_env,
        )
        git(
            "push",
            "-q",
            "--force",
            "--no-verify",
            self.origin,
            "main",
            cwd=self.work,
            env={"GNUPGHOME": self.gnupghome, "PATH": os.environ["PATH"]},
        )

    def _signed_commit(self, content, message):
        p = os.path.join(self.work, "signed.txt")
        with open(p, "a") as fh:
            fh.write(content)
        git("add", "signed.txt", cwd=self.work, env=self.signing_env)
        git("commit", "-q", "-S", "-m", message, cwd=self.work, env=self.signing_env)
        return git("rev-parse", "HEAD", cwd=self.work).stdout.strip()

    def _replace_with_signed_commit(self, original):
        no_replacements = {**self.signing_env, "GIT_NO_REPLACE_OBJECTS": "1"}
        tree = git(
            "rev-parse",
            f"{original}^{{tree}}",
            cwd=self.work,
            env=no_replacements,
        ).stdout.strip()
        lineage = git(
            "rev-list",
            "--parents",
            "-n",
            "1",
            original,
            cwd=self.work,
            env=no_replacements,
        ).stdout.split()
        commit_tree_args = ["commit-tree", "-S", tree]
        for parent in lineage[1:]:
            commit_tree_args.extend(("-p", parent))
        commit_tree_args.extend(("-m", "signed replacement view"))
        replacement = git(
            *commit_tree_args,
            cwd=self.work,
            env=no_replacements,
        ).stdout.strip()
        git("replace", original, replacement, cwd=self.work)

        replaced_view = git(
            "log",
            "-1",
            "--pretty=%G? %H",
            original,
            cwd=self.work,
            env=self.signing_env,
        ).stdout.split()
        self.assertEqual(replaced_view, ["G", original])
        return replacement

    def _race_env(self, raced_sha):
        fake_bin = os.path.join(self.tmp, "race-bin")
        os.makedirs(fake_bin, exist_ok=True)
        real_git = self.network_git
        wrapper = os.path.join(fake_bin, "git")
        with open(wrapper, "w") as fh:
            fh.write(
                """#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == push && " $* " == *" $PUBLISH_TEST_EXPECTED_URL "* && " $* " != *" --dry-run "* ]]; then
    "$REAL_GIT" --git-dir="$RACE_REMOTE" fetch --quiet "$PWD" "$RACE_SHA"
    "$REAL_GIT" --git-dir="$RACE_REMOTE" update-ref refs/heads/main "$RACE_SHA"
    echo "simulated mirror/ref race" >&2
    exit 1
fi
exec "$REAL_GIT" "$@"
"""
            )
        os.chmod(wrapper, 0o755)
        return clean_env(
            **{
                **self.signing_env,
                "PATH": f"{fake_bin}:{self.signing_env['PATH']}",
                "REAL_GIT": real_git,
                "RACE_REMOTE": self.origin,
                "RACE_SHA": raced_sha,
            }
        )

    def _readback_failure_env(self):
        fake_bin = os.path.join(self.tmp, "readback-bin")
        os.makedirs(fake_bin, exist_ok=True)
        real_git = self.network_git
        marker = os.path.join(self.tmp, "origin-pushed")
        wrapper = os.path.join(fake_bin, "git")
        with open(wrapper, "w") as fh:
            fh.write(
                """#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == push && " $* " == *" $PUBLISH_TEST_EXPECTED_URL "* && " $* " != *" --dry-run "* ]]; then
    if "$REAL_GIT" "$@"; then status=0; else status=$?; fi
    : >"$READBACK_FAIL_MARKER"
    exit "$status"
fi
if [[ ${1:-} == ls-remote && " $* " == *" $PUBLISH_TEST_EXPECTED_URL "* && -e $READBACK_FAIL_MARKER ]]; then
    echo "simulated readback network failure" >&2
    exit 1
fi
exec "$REAL_GIT" "$@"
"""
            )
        os.chmod(wrapper, 0o755)
        return clean_env(
            **{
                **self.signing_env,
                "PATH": f"{fake_bin}:{self.signing_env['PATH']}",
                "REAL_GIT": real_git,
                "READBACK_FAIL_MARKER": marker,
            }
        )

    def _post_push_authority_mutation_env(self):
        fake_bin = os.path.join(self.tmp, "post-push-authority-bin")
        os.makedirs(fake_bin, exist_ok=True)
        real_git = self.network_git
        wrapper = os.path.join(fake_bin, "git")
        with open(wrapper, "w") as fh:
            fh.write(
                """#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == push && " $* " == *" $PUBLISH_TEST_EXPECTED_URL "* && " $* " != *" --dry-run "* ]]; then
    if "$REAL_GIT" "$@"; then status=0; else status=$?; fi
    "$REAL_GIT" --git-dir="$PUBLISH_TEST_WORK_GIT_DIR" \
        config remote.origin.url git@github.com:jwiegley/nix-config.git
    exit "$status"
fi
exec "$REAL_GIT" "$@"
"""
            )
        os.chmod(wrapper, 0o755)
        return clean_env(
            **{
                **self.signing_env,
                "PATH": f"{fake_bin}:{self.signing_env['PATH']}",
                "REAL_GIT": real_git,
                "PUBLISH_TEST_WORK_GIT_DIR": os.path.join(self.work, ".git"),
            }
        )

    def _transient_rewrite_env(self, evil_remote):
        fake_bin = os.path.join(self.tmp, "transient-rewrite-bin")
        os.makedirs(fake_bin, exist_ok=True)
        marker = os.path.join(self.tmp, "real-push-finished")
        ssh_log = os.path.join(self.tmp, "ssh-transport.log")

        fake_ssh = os.path.join(fake_bin, "ssh")
        with open(fake_ssh, "w") as fh:
            fh.write(
                """#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$PUBLISH_TEST_SSH_LOG"
case $* in
*git-upload-pack*) exec "$PUBLISH_TEST_REAL_GIT" upload-pack "$PUBLISH_TEST_REMOTE" ;;
*git-receive-pack*) exec "$PUBLISH_TEST_REAL_GIT" receive-pack "$PUBLISH_TEST_REMOTE" ;;
*) echo "unexpected fake SSH invocation: $*" >&2; exit 97 ;;
esac
"""
            )
        os.chmod(fake_ssh, 0o755)

        wrapper = os.path.join(fake_bin, "git")
        with open(wrapper, "w") as fh:
            fh.write(
                """#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == fetch || ${1:-} == push || ${1:-} == ls-remote ]]; then
    printf '%s\n' "$*" >>"$PUBLISH_TEST_NETWORK_LOG"
fi
rewrite_key="url.file://$PUBLISH_TEST_EVIL_REMOTE.insteadOf"
run_with_transient_rewrite() {
    "$PUBLISH_TEST_REAL_GIT" --git-dir="$PUBLISH_TEST_WORK_GIT_DIR" \
        config "$rewrite_key" "$PUBLISH_TEST_EXPECTED_URL"
    if "$PUBLISH_TEST_REAL_GIT" "$@"; then status=0; else status=$?; fi
    "$PUBLISH_TEST_REAL_GIT" --git-dir="$PUBLISH_TEST_WORK_GIT_DIR" \
        config --unset-all "$rewrite_key" || true
    return "$status"
}
if [[ ${1:-} == push && " $* " != *" --dry-run "* ]]; then
    if run_with_transient_rewrite "$@"; then status=0; else status=$?; fi
    : >"$PUBLISH_TEST_REAL_PUSH_MARKER"
    exit "$status"
fi
if [[ ${1:-} == ls-remote && -e $PUBLISH_TEST_REAL_PUSH_MARKER ]]; then
    run_with_transient_rewrite "$@"
    exit $?
fi
exec "$PUBLISH_TEST_REAL_GIT" "$@"
"""
            )
        os.chmod(wrapper, 0o755)

        env = clean_env(
            **{
                **self.signing_env,
                "PATH": f"{fake_bin}:{self.signing_env['PATH']}",
                "GIT_SSH_COMMAND": fake_ssh,
                "GIT_SSH_VARIANT": "ssh",
                "PUBLISH_TEST_EVIL_REMOTE": evil_remote,
                "PUBLISH_TEST_REAL_GIT": self.real_git,
                "PUBLISH_TEST_REAL_PUSH_MARKER": marker,
                "PUBLISH_TEST_REMOTE": self.origin,
                "PUBLISH_TEST_SSH_LOG": ssh_log,
                "PUBLISH_TEST_WORK_GIT_DIR": os.path.join(self.work, ".git"),
            }
        )
        return env, ssh_log

    def _publication_signal_env(self, phase, signal_name):
        fake_bin = os.path.join(self.tmp, f"signal-{phase}-bin")
        os.makedirs(fake_bin, exist_ok=True)
        marker = os.path.join(self.tmp, f"signal-{phase}.marker")
        transport_tmp = os.path.join(self.tmp, f"signal-{phase}-tmp")
        os.makedirs(transport_tmp)

        wrapper = os.path.join(fake_bin, "git")
        with open(wrapper, "w") as fh:
            fh.write(
                """#!/usr/bin/env bash
set -euo pipefail
is_real_push=0
if [[ ${1:-} == push && " $* " == *" $PUBLISH_TEST_EXPECTED_URL "* && " $* " != *" --dry-run "* ]]; then
    is_real_push=1
fi
if [[ $is_real_push -eq 1 ]]; then
    if [[ $PUBLISH_TEST_SIGNAL_PHASE == during-push ]]; then
        printf during-push >"$PUBLISH_TEST_SIGNAL_MARKER"
        kill -s "$PUBLISH_TEST_SIGNAL_NAME" "$PPID"
    fi
    if "$REAL_GIT" "$@"; then status=0; else status=$?; fi
    if [[ $PUBLISH_TEST_SIGNAL_PHASE == after-push ]]; then
        printf after-push >"$PUBLISH_TEST_SIGNAL_MARKER"
        kill -s "$PUBLISH_TEST_SIGNAL_NAME" "$PPID"
    fi
    exit "$status"
fi
exec "$REAL_GIT" "$@"
"""
            )
        os.chmod(wrapper, 0o755)

        env = clean_env(
            **{
                **self.signing_env,
                "PATH": f"{fake_bin}:{self.signing_env['PATH']}",
                "REAL_GIT": self.network_git,
                "TMPDIR": transport_tmp,
                "PUBLISH_TEST_SIGNAL_MARKER": marker,
                "PUBLISH_TEST_SIGNAL_NAME": signal_name,
                "PUBLISH_TEST_SIGNAL_PHASE": phase,
            }
        )
        return env, marker, transport_tmp

    def _verified_readback_signal_env(self):
        marker = os.path.join(self.tmp, "signal-verified.marker")
        transport_tmp = os.path.join(self.tmp, "signal-verified-tmp")
        os.makedirs(transport_tmp)
        bash_env = os.path.join(self.tmp, "signal-verified.bash-env")
        with open(bash_env, "w") as fh:
            fh.write(
                """publish_test_signal_on_confirm() {
    if [[ $BASH_COMMAND == 'say "  $r confirmed at $short"' ]]; then
        trap - DEBUG
        printf verified >"$PUBLISH_TEST_SIGNAL_MARKER"
        kill -TERM "$$"
    fi
}
trap publish_test_signal_on_confirm DEBUG
"""
            )

        env = clean_env(
            **{
                **self.signing_env,
                "BASH_ENV": bash_env,
                "TMPDIR": transport_tmp,
                "PUBLISH_TEST_SIGNAL_MARKER": marker,
            }
        )
        return env, marker, transport_tmp

    def _successful_push_race_env(self, raced_sha):
        fake_bin = os.path.join(self.tmp, "success-race-bin")
        os.makedirs(fake_bin, exist_ok=True)
        real_git = self.network_git
        wrapper = os.path.join(fake_bin, "git")
        with open(wrapper, "w") as fh:
            fh.write(
                """#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == push && " $* " == *" $PUBLISH_TEST_EXPECTED_URL "* && " $* " != *" --dry-run "* ]]; then
    if "$REAL_GIT" "$@"; then status=0; else status=$?; fi
    "$REAL_GIT" --git-dir="$RACE_REMOTE" update-ref refs/heads/main "$RACE_SHA"
    exit "$status"
fi
exec "$REAL_GIT" "$@"
"""
            )
        os.chmod(wrapper, 0o755)
        return clean_env(
            **{
                **self.signing_env,
                "PATH": f"{fake_bin}:{self.signing_env['PATH']}",
                "REAL_GIT": real_git,
                "RACE_REMOTE": self.origin,
                "RACE_SHA": raced_sha,
            }
        )

    def _third_remote_revision(self):
        other = os.path.join(self.tmp, "racer")
        git("clone", "-q", self.origin, other, cwd=self.tmp)
        git("config", "commit.gpgsign", "false", cwd=other)
        with open(os.path.join(other, "race.txt"), "w") as fh:
            fh.write("third revision\n")
        git("add", "race.txt", cwd=other)
        git("commit", "-q", "--no-gpg-sign", "-m", "racing writer", cwd=other)
        third = git("rev-parse", "HEAD", cwd=other).stdout.strip()
        git("push", "-q", "origin", f"{third}:refs/heads/race-object", cwd=other)
        return third

    def _assert_transaction_recovery(self, combined, head, branch="main"):
        self.assertIn("final Gitea readback", combined)
        self.assertIn(
            "bin/publish --publish --rev %s --branch %s" % (head, branch),
            combined,
        )
        self.assertNotIn("git push ", combined)
        self.assertNotIn("git fetch ", combined)
        self.assertNotIn("git ls-remote ", combined)

    def test_default_does_not_push_but_reports_what_it_would_do(self):
        """A bare invocation with publishable work reports but does not push."""
        head = self._signed_commit("s\n", "a signed commit")
        before = self.remote_sha(self.origin)
        r = subprocess.run(
            [PUBLISH],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**self.signing_env),
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("re-run with --publish", r.stdout)
        after = self.remote_sha(self.origin)
        self.assertEqual(before, after, "a bare invocation moved a remote")
        self.assertNotEqual(head, after)

    def test_dry_run_is_still_accepted_as_a_synonym(self):
        self._signed_commit("s\n", "a signed commit")
        r = subprocess.run(
            [PUBLISH, "--dry-run"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**self.signing_env),
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertNotIn("unknown argument", r.stderr)
        self.assertIn("re-run with --publish", r.stdout)

    def test_publish_then_dry_run_is_rejected_without_network_or_push(self):
        head = self._signed_commit("s\n", "a signed commit")
        before = self.remote_sha(self.origin)

        r = subprocess.run(
            [PUBLISH, "--publish", "--dry-run"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**self.signing_env),
        )

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("cannot be combined", r.stderr)
        self.assertEqual(self.network_actions(), [])
        self.assertEqual(self.remote_sha(self.origin), before)
        self.assertNotEqual(head, before)

    def test_dry_run_then_publish_is_rejected_without_network_or_push(self):
        head = self._signed_commit("s\n", "a signed commit")
        before = self.remote_sha(self.origin)

        r = subprocess.run(
            [PUBLISH, "--dry-run", "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**self.signing_env),
        )

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("cannot be combined", r.stderr)
        self.assertEqual(self.network_actions(), [])
        self.assertEqual(self.remote_sha(self.origin), before)
        self.assertNotEqual(head, before)

    def test_signed_commit_passes_the_gate(self):
        self._signed_commit("s\n", "a signed commit")
        r = subprocess.run(
            [PUBLISH, "--dry-run"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**self.signing_env),
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("all selected commits signed", r.stdout)
        self.assertIn("would accept", r.stdout)

    def test_fresh_refs_expose_unsigned_middle_hidden_by_stale_and_injected_refs(
        self,
    ):
        unsigned = self._commit("unsigned middle\n", "an unsigned middle commit")
        head = self._signed_commit("signed tip\n", "a signed branch tip")
        git("update-ref", "refs/remotes/origin/stale", head, cwd=self.work)
        git("config", "--unset-all", "remote.origin.fetch", cwd=self.work)
        git(
            "config",
            "--add",
            "remote.origin.fetch",
            "+refs/heads/not-present:refs/remotes/origin/narrow",
            cwd=self.work,
        )

        r = subprocess.run(
            [PUBLISH, "--dry-run"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(
                **{
                    **self.signing_env,
                    "PUBLISH_TEST_INJECT_SNAPSHOT_SHA": head,
                }
            ),
        )

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("UNSIGNED", r.stderr)
        self.assertIn(unsigned[:12], r.stderr)
        self.assertNotEqual(self.remote_sha(self.origin), head)

    def test_signed_replacement_cannot_hide_unsigned_tip_object(self):
        unsigned = self._commit("unsigned tip\n", "an unsigned branch tip")
        self._replace_with_signed_commit(unsigned)

        r = subprocess.run(
            [PUBLISH, "--dry-run"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**self.signing_env),
        )

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("UNSIGNED", r.stderr)
        self.assertIn(unsigned[:12], r.stderr)
        self.assertNotEqual(self.remote_sha(self.origin), unsigned)

    def test_signed_replacement_cannot_hide_unsigned_middle_object(self):
        unsigned = self._commit("unsigned middle\n", "an unsigned middle commit")
        head = self._signed_commit("signed tip\n", "a signed branch tip")
        self._replace_with_signed_commit(unsigned)

        r = subprocess.run(
            [PUBLISH, "--dry-run"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**self.signing_env),
        )

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("UNSIGNED", r.stderr)
        self.assertIn(unsigned[:12], r.stderr)
        self.assertNotEqual(self.remote_sha(self.origin), head)

    def test_graft_cannot_hide_unsigned_middle_object(self):
        base = self.remote_sha(self.origin)
        unsigned = self._commit("unsigned middle\n", "an unsigned middle commit")
        head = self._signed_commit("signed tip\n", "a signed branch tip")
        grafts = os.path.join(self.work, ".git", "info", "grafts")
        with open(grafts, "w") as fh:
            fh.write(f"{head} {base}\n")

        grafted_range = git(
            "rev-list",
            head,
            "--not",
            base,
            cwd=self.work,
            env=self.signing_env,
        ).stdout.split()
        self.assertEqual(grafted_range, [head])

        r = subprocess.run(
            [PUBLISH, "--dry-run"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**self.signing_env),
        )

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("UNSIGNED", r.stderr)
        self.assertIn(unsigned[:12], r.stderr)
        self.assertNotEqual(self.remote_sha(self.origin), head)

    def test_inherited_graft_file_cannot_hide_unsigned_middle_object(self):
        base = self.remote_sha(self.origin)
        unsigned = self._commit("unsigned middle\n", "an unsigned middle commit")
        head = self._signed_commit("signed tip\n", "a signed branch tip")
        grafts = os.path.join(self.tmp, "hostile-grafts")
        with open(grafts, "w") as fh:
            fh.write(f"{head} {base}\n")

        r = subprocess.run(
            [PUBLISH, "--dry-run"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**{**self.signing_env, "GIT_GRAFT_FILE": grafts}),
        )

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("UNSIGNED", r.stderr)
        self.assertIn(unsigned[:12], r.stderr)
        self.assertNotEqual(self.remote_sha(self.origin), head)

    def test_inherited_shallow_file_does_not_change_signature_traversal(self):
        head = self._signed_commit("signed tip\n", "a signed branch tip")
        shallow = os.path.join(self.tmp, "hostile-shallow")
        with open(shallow, "w") as fh:
            fh.write(f"{head}\n")

        r = subprocess.run(
            [PUBLISH, "--dry-run"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**{**self.signing_env, "GIT_SHALLOW_FILE": shallow}),
        )

        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("all selected commits signed", r.stdout)

    def test_inherited_git_template_is_not_used(self):
        self._signed_commit("signed tip\n", "a signed branch tip")
        template = os.path.join(self.tmp, "hostile-template")
        os.makedirs(template)
        with open(os.path.join(template, "config"), "w") as fh:
            fh.write("[invalid-template-config\n")

        r = subprocess.run(
            [PUBLISH, "--dry-run"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**{**self.signing_env, "GIT_TEMPLATE_DIR": template}),
        )

        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("all selected commits signed", r.stdout)

    def test_checkout_gpg_program_cannot_override_signature_verifier(self):
        self._signed_commit("signed tip\n", "a signed branch tip")
        git("config", "gpg.program", "/usr/bin/false", cwd=self.work)

        r = subprocess.run(
            [PUBLISH, "--dry-run"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**self.signing_env),
        )

        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("all selected commits signed", r.stdout)

    def test_other_remote_branch_does_not_hide_unsigned_target_ancestor(self):
        unsigned = self._commit("unsigned side\n", "an unsigned side commit")
        git(
            "push",
            "-q",
            "--no-verify",
            self.origin,
            f"{unsigned}:refs/heads/side",
            cwd=self.work,
        )
        head = self._signed_commit("signed tip\n", "a signed branch tip")

        r = subprocess.run(
            [PUBLISH, "--dry-run"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**self.signing_env),
        )

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("UNSIGNED", r.stderr)
        self.assertIn(unsigned[:12], r.stderr)
        self.assertNotEqual(self.remote_sha(self.origin), head)

    def test_signed_tip_already_on_gitea_is_a_verified_noop(self):
        head = self._signed_commit("s\n", "a signed commit")
        git("push", "-q", "--no-verify", self.origin, "main", cwd=self.work)

        r = subprocess.run(
            [PUBLISH, "--dry-run"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**self.signing_env),
        )

        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("all selected commits signed", r.stdout)
        self.assertIn("already at", r.stdout)
        self.assertIn("nothing to do", r.stdout)
        self.assertEqual(self.remote_sha(self.origin), head)

    def test_signed_new_branch_tip_reachable_on_gitea_is_still_verified(self):
        head = self._signed_commit("s\n", "a signed commit")
        git("push", "-q", "--no-verify", self.origin, "main", cwd=self.work)
        git("checkout", "-q", "-b", "feature", cwd=self.work)

        r = subprocess.run(
            [PUBLISH, "--dry-run"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**self.signing_env),
        )

        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("would create it", r.stdout)
        self.assertIn(
            "all selected commits signed (unique commits checked: 2)", r.stdout
        )
        self.assertIsNone(self.remote_sha(self.origin, "feature"))
        self.assertEqual(self.remote_sha(self.origin), head)

    def test_publish_runs_tracked_pre_push_group_exactly_once(self):
        before = self.remote_sha(self.origin)
        head = self._signed_commit("s\n", "a signed commit")
        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**self.signing_env),
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        with open(self.gate_log) as fh:
            invocations = [line.strip() for line in fh if line.strip()]
        self.assertEqual(invocations, ["run pre-push --force"])
        self.assertIn("all tracked gates passed once", r.stdout)
        self.assertEqual(self.remote_sha(self.origin), head)
        real_pushes = [
            action
            for action in self.network_actions()
            if action.startswith("push ") and " --dry-run " not in f" {action} "
        ]
        self.assertEqual(len(real_pushes), 1, real_pushes)
        self.assertIn(f"--force-with-lease=refs/heads/main:{before}", real_pushes[0])

    def test_failed_explicit_gate_stops_before_real_push(self):
        head = self._signed_commit("s\n", "a signed commit")
        before = self.remote_sha(self.origin)
        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**{**self.signing_env, "PUBLISH_GATE_EXIT": "23"}),
        )
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("pre-push gates failed", r.stderr)
        with open(self.gate_log) as fh:
            invocations = [line.strip() for line in fh if line.strip()]
        self.assertEqual(invocations, ["run pre-push --force"])
        after = self.remote_sha(self.origin)
        self.assertEqual(before, after)
        self.assertNotEqual(head, after)

    def test_dirty_tracked_tree_is_refused_before_the_gate(self):
        head = self._signed_commit("s\n", "a signed commit")
        before = self.remote_sha(self.origin)
        with open(os.path.join(self.work, "file.txt"), "a") as fh:
            fh.write("dirty\n")

        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**self.signing_env),
        )

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("tracked working tree or index is dirty", r.stderr)
        self.assertFalse(os.path.exists(self.gate_log))
        self.assertEqual(self.remote_sha(self.origin), before)
        self.assertNotEqual(head, before)

    def test_gate_mutation_is_refused_before_hooks_are_bypassed(self):
        head = self._signed_commit("s\n", "a signed commit")
        before = self.remote_sha(self.origin)

        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**{**self.signing_env, "PUBLISH_GATE_MUTATE": "dirty"}),
        )

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("post-gate: tracked working tree or index is dirty", r.stderr)
        with open(self.gate_log) as fh:
            invocations = [line.strip() for line in fh if line.strip()]
        self.assertEqual(invocations, ["run pre-push --force"])
        self.assertEqual(self.remote_sha(self.origin), before)
        self.assertNotEqual(head, before)

    def test_gate_cannot_redirect_the_validated_gitea_destination(self):
        head = self._signed_commit("s\n", "a signed commit")
        before = self.remote_sha(self.origin)

        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**{**self.signing_env, "PUBLISH_GATE_MUTATE": "remote"}),
        )

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("post-gate configured URL set", r.stderr)
        with open(self.gate_log) as fh:
            invocations = [line.strip() for line in fh if line.strip()]
        self.assertEqual(invocations, ["run pre-push --force"])
        actions = self.network_actions()
        self.assertTrue(actions, "pre-gate fetch and dry-run were not exercised")
        self.assertTrue(
            all("gitea@gitea:johnw/nix-config.git" in action for action in actions),
            actions,
        )
        self.assertTrue(all("github.com" not in action for action in actions), actions)
        self.assertEqual(self.remote_sha(self.origin), before)
        self.assertNotEqual(head, before)

    def test_transient_url_rewrites_cannot_redirect_push_or_readback(self):
        evil = os.path.join(self.tmp, "evil.git")
        git("clone", "--bare", "-q", self.origin, evil, cwd=self.tmp)
        evil_before = self.remote_sha(evil)
        head = self._signed_commit("s\n", "a signed commit")
        env, ssh_log = self._transient_rewrite_env(evil)

        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=env,
        )

        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.remote_sha(self.origin), head)
        self.assertEqual(self.remote_sha(evil), evil_before)
        with open(ssh_log) as fh:
            ssh_actions = fh.read()
        self.assertIn("git-receive-pack", ssh_actions)
        self.assertIn("git-upload-pack", ssh_actions)
        rewrite_key = "url.file://%s.insteadOf" % evil
        leftover = git(
            "config", "--get-all", rewrite_key, cwd=self.work, check=False
        ).stdout
        self.assertEqual(leftover, "")

    def test_signal_during_real_push_reports_supported_recovery_and_cleans_up(self):
        head = self._signed_commit("s\n", "a signed commit")
        env, marker, transport_tmp = self._publication_signal_env("during-push", "TERM")

        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=env,
        )

        self.assertEqual(r.returncode, 143, r.stdout + r.stderr)
        combined = r.stdout + r.stderr
        self.assertIn("interrupted by TERM after the real push began", combined)
        self._assert_transaction_recovery(combined, head)
        self.assertTrue(os.path.exists(marker))
        self.assertEqual(self.remote_sha(self.origin), head)
        self.assertFalse(
            any(action.startswith("ls-remote ") for action in self.network_actions())
        )
        self.assertEqual(os.listdir(transport_tmp), [])

    def test_signal_between_push_and_readback_reports_recovery_and_cleans_up(self):
        head = self._signed_commit("s\n", "a signed commit")
        env, marker, transport_tmp = self._publication_signal_env("after-push", "INT")

        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=env,
        )

        self.assertEqual(r.returncode, 130, r.stdout + r.stderr)
        combined = r.stdout + r.stderr
        self.assertIn("interrupted by INT after the real push began", combined)
        self._assert_transaction_recovery(combined, head)
        self.assertTrue(os.path.exists(marker))
        self.assertEqual(self.remote_sha(self.origin), head)
        self.assertFalse(
            any(action.startswith("ls-remote ") for action in self.network_actions())
        )
        self.assertEqual(os.listdir(transport_tmp), [])

    def test_signal_after_exact_readback_sees_verified_state_without_retry(self):
        head = self._signed_commit("s\n", "a signed commit")
        env, marker, transport_tmp = self._verified_readback_signal_env()

        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=env,
        )

        self.assertEqual(r.returncode, 143, r.stdout + r.stderr)
        combined = r.stdout + r.stderr
        self.assertIn("after publication; final Gitea readback", combined)
        self.assertIn("had already verified the target revision", combined)
        self.assertNotIn("bin/publish --publish --rev", combined)
        self.assertNotIn("remote is not verified", combined.lower())
        self.assertNotIn("git push ", combined)
        self.assertNotIn("git fetch ", combined)
        self.assertNotIn("git ls-remote ", combined)
        self.assertTrue(os.path.exists(marker))
        self.assertEqual(self.remote_sha(self.origin), head)
        self.assertTrue(
            any(action.startswith("ls-remote ") for action in self.network_actions())
        )
        self.assertEqual(os.listdir(transport_tmp), [])

    def test_prepublication_signal_does_not_claim_possible_remote_mutation(self):
        head = self._signed_commit("s\n", "a signed commit")
        before = self.remote_sha(self.origin)
        env, marker, transport_tmp = self._publication_signal_env("preflight", "TERM")

        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=env,
        )

        self.assertEqual(r.returncode, 143, r.stdout + r.stderr)
        combined = r.stdout + r.stderr
        self.assertIn("before publication; no real push began", combined)
        self.assertNotIn("bin/publish --publish --rev", combined)
        self.assertNotIn("remote is not verified", combined.lower())
        self.assertTrue(os.path.exists(marker))
        self.assertEqual(self.remote_sha(self.origin), before)
        self.assertNotEqual(head, before)
        self.assertEqual(os.listdir(transport_tmp), [])

    def test_concurrent_publisher_already_at_target_is_success(self):
        head = self._signed_commit("s\n", "a signed commit")
        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=self._race_env(head),
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        combined = r.stdout + r.stderr
        self.assertIn("already at", combined)
        self.assertIn("concurrent publisher", combined)
        self.assertNotIn("PUBLICATION FAILED", combined)
        self.assertEqual(self.remote_sha(self.origin), head)

    def test_race_to_third_revision_is_a_failed_publication(self):
        third = self._third_remote_revision()
        head = self._signed_commit("s\n", "a signed commit")
        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=self._race_env(third),
        )
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        combined = r.stdout + r.stderr
        self.assertIn("PUBLICATION FAILED", combined)
        self.assertIn("origin observed: %s" % third, combined)
        self._assert_transaction_recovery(combined, head)
        self.assertNotIn("now behind", combined)
        self.assertEqual(self.remote_sha(self.origin), third)

    def test_post_push_readback_failure_is_loud_failed_publication(self):
        head = self._signed_commit("s\n", "a signed commit")
        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=self._readback_failure_env(),
        )
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        combined = r.stdout + r.stderr
        self.assertIn("push readback failed", combined)
        self.assertIn("PUBLICATION FAILED", combined)
        self.assertIn("origin observed: <unreadable>", combined)
        self._assert_transaction_recovery(combined, head)
        self.assertEqual(self.remote_sha(self.origin), head)

    def test_post_push_authority_change_uses_supported_recovery(self):
        head = self._signed_commit("s\n", "a signed commit")
        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=self._post_push_authority_mutation_env(),
        )

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        combined = r.stdout + r.stderr
        self.assertIn("authority changed after push", combined)
        self.assertIn("PUBLICATION FAILED", combined)
        self.assertIn("origin observed: <authority-changed>", combined)
        self._assert_transaction_recovery(combined, head)
        self.assertFalse(
            any(action.startswith("ls-remote ") for action in self.network_actions())
        )
        self.assertEqual(self.remote_sha(self.origin), head)

    def test_successful_push_then_third_readback_is_failed_publication(self):
        third = self._third_remote_revision()
        head = self._signed_commit("s\n", "a signed commit")
        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=self._successful_push_race_env(third),
        )
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        combined = r.stdout + r.stderr
        self.assertIn("reported success but reads back", combined)
        self.assertIn("PUBLICATION FAILED", combined)
        self.assertIn("origin observed: %s" % third, combined)
        self._assert_transaction_recovery(combined, head)
        self.assertEqual(self.remote_sha(self.origin), third)

    def test_rejected_real_push_exits_nonzero_and_names_gitea(self):
        """A remote that passes pre-flight then fails the real push.

        A rejecting `pre-receive` hook is the faithful simulation: `git push
        --dry-run` negotiates refs without transferring a pack, so it never runs
        the hook and pre-flight passes — exactly like a fault that opens after
        pre-flight.
        """
        head = self._signed_commit("s\n", "a signed commit")
        hook = os.path.join(self.origin, "hooks", "pre-receive")
        os.makedirs(os.path.dirname(hook), exist_ok=True)
        with open(hook, "w") as fh:
            fh.write("#!/bin/sh\necho 'simulated remote fault' >&2\nexit 1\n")
        os.chmod(hook, 0o755)
        self.addCleanup(lambda: os.path.exists(hook) and os.unlink(hook))

        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(**self.signing_env),
        )
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        combined = r.stdout + r.stderr
        self.assertIn("PUBLICATION FAILED", combined)
        self.assertIn("origin", combined)
        self._assert_transaction_recovery(combined, head)
        self.assertNotEqual(self.remote_sha(self.origin), head)


class TestDoesNotEscapeItsSandbox(unittest.TestCase):
    """Hostile inherited Git selectors must not escape the temporary sandbox."""

    def test_inherited_git_dir_does_not_reach_the_outer_repository(self):
        outer = tempfile.mkdtemp(prefix="publish-test-outer-")
        self.addCleanup(shutil.rmtree, outer, ignore_errors=True)
        subprocess.run(
            ["git", "init", "--quiet", "--initial-branch=main", outer],
            check=True,
            capture_output=True,
            env=clean_env(),
        )
        outer_config = os.path.join(outer, ".git", "config")
        with open(outer_config) as fh:
            before = fh.read()

        # Representative hostile Git selector variables.
        hostile = {
            "GIT_DIR": os.path.join(outer, ".git"),
            "GIT_INDEX_FILE": os.path.join(outer, ".git", "index"),
            "GIT_WORK_TREE": outer,
        }
        with_hostile = dict(os.environ)
        with_hostile.update(hostile)

        # Run the harness setup under that environment, in a separate process so
        # the poisoned variables are genuinely inherited rather than simulated.
        r = subprocess.run(
            [
                "python3",
                "-m",
                "unittest",
                "publish-slow-test.TestNoop.test_unsigned_gitea_tip_is_refused_even_when_already_current",
            ],
            # cwd must be this file's directory: `-m unittest publish-slow-test...`
            # resolves the module through cwd on sys.path, and there is no
            # publish-slow-test at the repository root. f93f232d moved this suite
            # from bin/ to test/bin/ and changed HERE to REPO, which silently
            # turned this guard into an unconditional failure.
            cwd=HERE,
            capture_output=True,
            text=True,
            env=with_hostile,
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

        with open(outer_config) as fh:
            after = fh.read()
        self.assertEqual(
            before,
            after,
            "the suite rewrote the outer repository's config; the GIT_* scrub in "
            "clean_env() is not holding:\n--- before ---\n%s\n--- after ---\n%s"
            % (before, after),
        )
        self.assertNotIn("bare = true", after)


class TestSelfConsistency(unittest.TestCase):
    def test_publish_is_executable_and_syntactically_valid(self):
        self.assertTrue(os.access(PUBLISH, os.X_OK), "bin/publish is not executable")
        r = subprocess.run(
            ["bash", "-n", PUBLISH], capture_output=True, text=True, env=clean_env()
        )
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_help_describes_rev_and_branch_as_assertions_not_selectors(self):
        r = subprocess.run(
            [PUBLISH, "--help"], capture_output=True, text=True, env=clean_env()
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("assert the revision", r.stdout)
        self.assertIn("must equal the checked-out", r.stdout)
        self.assertIn("assert the branch", r.stdout)
        self.assertIn("must be currently checked out", r.stdout)
        self.assertNotIn("operate on a specific revision", r.stdout)
        self.assertNotIn("branch other than the current one", r.stdout)

    def test_never_embeds_a_credential(self):
        """Scan the script for common embedded credential markers."""
        with open(PUBLISH) as fh:
            body = fh.read()
        for pattern in ("ghp_", "github_pat_", "PRIVATE KEY", "password=", "token="):
            self.assertNotIn(
                pattern, body, "bin/publish appears to embed a credential: %s" % pattern
            )

    def test_declares_only_gitea(self):
        with open(PUBLISH) as fh:
            body = fh.read()
        self.assertIn("REMOTE=origin", body)
        self.assertIn("EXPECTED_REMOTE_URL=gitea@gitea:johnw/nix-config.git", body)
        self.assertNotIn("git@github.com:jwiegley/nix-config.git", body)

    def test_isolated_transport_scrubs_graph_template_and_ssh_selectors(self):
        with open(PUBLISH) as fh:
            body = fh.read()
        for name in (
            "GIT_GRAFT_FILE",
            "GIT_SHALLOW_FILE",
            "GIT_TEMPLATE_DIR",
            "GIT_SSH",
            "GIT_SSH_COMMAND",
            "GIT_SSH_VARIANT",
        ):
            self.assertIn(f"-u {name}", body)
        self.assertIn('--template="$transport_template_dir"', body)
        self.assertIn("GIT_CONFIG_KEY_0=core.commitGraph", body)
        self.assertIn("GIT_CONFIG_VALUE_0=false", body)
        self.assertIn("GIT_CONFIG_KEY_1=pack.useBitmaps", body)
        self.assertIn("GIT_CONFIG_VALUE_1=false", body)
        self.assertLess(
            body.index("trap cleanup_transport EXIT"),
            body.index("transport_root=$(mktemp -d"),
        )

    def test_current_docs_describe_one_gitea_publication_authority(self):
        expected = {
            "README.md": "Publication | The Gitea authority",
            "doc/ARCHITECTURE.md": "one authoritative remote: LAN Gitea",
            "doc/USER-GUIDE.md": "publishes only to LAN Gitea (`origin`)",
            "bin/README.md": "sole publication command for authoritative Gitea",
        }
        retired = (
            "both remotes",
            "two remotes",
            "dual-remote",
            "github alone",
            "github remote",
        )
        for relative, current_contract in expected.items():
            with self.subTest(path=relative):
                with open(os.path.join(REPO, relative)) as fh:
                    body = fh.read()
                self.assertIn(current_contract, body)
                lowered = body.lower()
                for stale in retired:
                    self.assertNotIn(stale, lowered)

        for relative in ("README.md", "doc/ARCHITECTURE.md"):
            with self.subTest(path=relative, contract="canonical remote"):
                with open(os.path.join(REPO, relative)) as fh:
                    body = fh.read()
                self.assertIn("`origin`", body)
                self.assertIn("gitea@gitea:johnw/nix-config.git", body)
                self.assertIn("GitHub must not be configured as a remote", body)


if __name__ == "__main__":
    unittest.main()
