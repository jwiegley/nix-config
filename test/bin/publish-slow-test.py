#!/usr/bin/env python3
"""Tests for bin/publish and its dual-remote refusal paths.

Remote-mutation tests use throwaway local repositories; self-consistency tests
read the real script without mutating its repository.

Run: python3 -m unittest -v test/bin/publish-slow-test.py
"""

import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
PUBLISH = os.path.join(REPO, "bin", "publish")


# Repository/config selector variables scrubbed from Git subprocesses.
_GIT_LOCATION_VARS = (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_PREFIX",
    "GIT_CONFIG",
    "GIT_CONFIG_GLOBAL",
    "GIT_CONFIG_SYSTEM",
    "GIT_CONFIG_COUNT",
    "GIT_INTERNAL_SUPER_PREFIX",
    "GIT_CEILING_DIRECTORIES",
)


def clean_env(**extra):
    """Return os.environ without the repository selectors listed above."""
    e = dict(os.environ)
    for var in _GIT_LOCATION_VARS:
        e.pop(var, None)
    e.update(extra)
    return e


def git(*args, cwd, check=True, env=None):
    e = clean_env()
    # Deterministic unsigned commits by default; signing tests install their own
    # fixture behavior.
    e.update(
        {
            "GIT_AUTHOR_NAME": "Test",
            "GIT_AUTHOR_EMAIL": "test@example.invalid",
            "GIT_COMMITTER_NAME": "Test",
            "GIT_COMMITTER_EMAIL": "test@example.invalid",
            "GIT_AUTHOR_DATE": "2026-01-01T00:00:00+0000",
            "GIT_COMMITTER_DATE": "2026-01-01T00:00:00+0000",
        }
    )
    if env:
        e.update(env)
    r = subprocess.run(
        ["git", *args], cwd=cwd, capture_output=True, text=True, env=e
    )
    if check and r.returncode != 0:
        raise AssertionError(
            "git %s failed in %s:\n%s\n%s" % (" ".join(args), cwd, r.stdout, r.stderr)
        )
    return r


class PublishHarness(unittest.TestCase):
    """A work repo on branch `main` with two bare remotes, both in sync."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="publish-test-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

        self.origin = os.path.join(self.tmp, "origin.git")
        self.github = os.path.join(self.tmp, "github.git")
        for bare in (self.origin, self.github):
            git("init", "--bare", "--initial-branch=main", bare, cwd=self.tmp)

        self.work = os.path.join(self.tmp, "work")
        git("init", "--initial-branch=main", self.work, cwd=self.tmp)
        git("config", "commit.gpgsign", "false", cwd=self.work)
        git("remote", "add", "origin", self.origin, cwd=self.work)
        git("remote", "add", "github", self.github, cwd=self.work)

        self._commit("base\n", "initial commit")
        # Seed both remotes so the branch exists on each; publish's signature
        # range is "what the remote lacks", so this makes the baseline empty.
        git("push", "-q", "origin", "main", cwd=self.work)
        git("push", "-q", "github", "main", cwd=self.work)
        git("fetch", "-q", "--all", cwd=self.work)

    def _commit(self, content, message):
        p = os.path.join(self.work, "file.txt")
        with open(p, "a") as fh:
            fh.write(content)
        git("add", "file.txt", cwd=self.work)
        git("commit", "-q", "--no-gpg-sign", "-m", message, cwd=self.work)
        return git("rev-parse", "HEAD", cwd=self.work).stdout.strip()

    def publish(self, *args):
        return subprocess.run(
            [PUBLISH, *args],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(),
        )

    def remote_sha(self, bare, branch="main"):
        r = git("ls-remote", bare, "refs/heads/%s" % branch, cwd=self.work)
        out = r.stdout.split()
        return out[0] if out else None


class TestNoop(PublishHarness):
    def test_both_already_current_is_a_noop_and_succeeds(self):
        r = self.publish("--dry-run")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("already at", r.stdout)
        self.assertIn("nothing to do", r.stdout)


@unittest.skipUnless(shutil.which("lefthook"), "lefthook not available")
class TestEmptyRangePrePush(PublishHarness):
    def test_tracked_tree_scope_turns_empty_range_from_skip_into_run(self):
        marker = os.path.join(self.tmp, "pre-push-ran")
        config = os.path.join(self.work, "lefthook.yml")

        def write_config(with_tree_scope):
            scope = (
                "  files: '{ git ls-files; printf \"%s\\n\" "
                "lefthook.yml; }'\n"
                if with_tree_scope
                else ""
            )
            command = (
                ': {files}; printf ran >>"$EMPTY_RANGE_MARKER"'
                if with_tree_scope
                else 'printf ran >>"$EMPTY_RANGE_MARKER"'
            )
            with open(config, "w") as fh:
                fh.write(
                    "pre-push:\n"
                    + scope
                    + "  commands:\n"
                    + "    probe:\n"
                    + "      run: '"
                    + command
                    + "'\n"
                )

        write_config(with_tree_scope=False)
        installed = subprocess.run(
            ["lefthook", "install", "--force"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(),
        )
        self.assertEqual(installed.returncode, 0, installed.stdout + installed.stderr)

        skipped = git(
            "push",
            "origin",
            "main",
            cwd=self.work,
            check=False,
            env={"EMPTY_RANGE_MARKER": marker},
        )
        self.assertEqual(skipped.returncode, 0, skipped.stdout + skipped.stderr)
        self.assertFalse(os.path.exists(marker), "old empty-range behavior unexpectedly ran")

        write_config(with_tree_scope=True)
        forced = git(
            "push",
            "origin",
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
        git("push", "-q", "--no-verify", "origin", "main", cwd=self.work)
        empty_index = git(
            "push",
            "origin",
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

    def test_missing_remote_is_refused_before_any_push(self):
        git("remote", "remove", "github", cwd=self.work)
        head = self._commit("more\n", "second commit")
        r = self.publish()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("github", r.stderr)
        self.assertIn("not configured", r.stderr)
        # The surviving remote must NOT have received anything.
        self.assertNotEqual(self.remote_sha(self.origin), head)

    def test_unreachable_remote_blocks_publishing_the_other(self):
        """The LAN-only case: gitea down must not let github race ahead."""
        head = self._commit("more\n", "second commit")
        shutil.rmtree(self.origin)
        r = self.publish()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("unreachable", r.stderr)
        # github is reachable and would have accepted — prove it stayed put.
        self.assertNotEqual(self.remote_sha(self.github), head)

    def test_non_fast_forward_is_refused_and_nothing_is_pushed(self):
        # Advance github independently so our history is not a descendant.
        other = os.path.join(self.tmp, "other")
        git("clone", "-q", self.github, other, cwd=self.tmp)
        git("config", "commit.gpgsign", "false", cwd=other)
        with open(os.path.join(other, "divergent.txt"), "w") as fh:
            fh.write("theirs\n")
        git("add", "divergent.txt", cwd=other)
        git("commit", "-q", "--no-gpg-sign", "-m", "their commit", cwd=other)
        git("push", "-q", "origin", "main", cwd=other)
        github_before = self.remote_sha(self.github)

        head = self._commit("ours\n", "our commit")
        r = self.publish()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("NOT an ancestor", r.stderr)
        self.assertIn("will not force", r.stderr)
        # Neither remote moved: origin must not be published when github can't be.
        self.assertEqual(self.remote_sha(self.github), github_before)
        self.assertNotEqual(self.remote_sha(self.origin), head)

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
        before = (self.remote_sha(self.origin), self.remote_sha(self.github))

        r = self.publish("--rev", old_tip, "--branch", "main")

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("must equal the current main branch tip", r.stderr)
        self.assertEqual((self.remote_sha(self.origin), self.remote_sha(self.github)), before)
        self.assertNotIn(new_tip, before)

    def test_non_current_named_branch_is_refused_before_gating(self):
        git("checkout", "-q", "-b", "side", cwd=self.work)
        side_tip = self._commit("side\n", "side branch tip")
        git("checkout", "-q", "main", cwd=self.work)
        before = (self.remote_sha(self.origin), self.remote_sha(self.github))

        r = self.publish("--rev", side_tip, "--branch", "side")

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("branch 'side' is not checked out", r.stderr)
        self.assertEqual((self.remote_sha(self.origin), self.remote_sha(self.github)), before)

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

    def test_new_branch_absent_from_both_remotes_does_not_drag_in_old_history(self):
        """A new branch whose tip is published elsewhere has no new history."""
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        r = self.publish("--dry-run")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("would create it", r.stdout)
        self.assertIn("all signed (0 commit-remote pairs checked)", r.stdout)


class TestSignatureGateIsAHardStop(PublishHarness):
    def test_unsigned_commit_stops_before_any_remote_is_touched(self):
        head = self._commit("x\n", "an unsigned commit")
        before = (self.remote_sha(self.origin), self.remote_sha(self.github))
        r = self.publish()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("refusing to publish unsigned commits", r.stderr)
        after = (self.remote_sha(self.origin), self.remote_sha(self.github))
        self.assertEqual(before, after, "a remote moved despite the signature gate")
        self.assertNotIn(head, [x for x in after if x])


def _gpg_available():
    return shutil.which("gpg") is not None


@unittest.skipUnless(_gpg_available(), "gpg not available")
class TestPartialFailure(PublishHarness):
    """The partial-publish path, reached with real signed commits.

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
                "gpg", "--batch", "--pinentry-mode", "loopback", "--passphrase", "",
                "--quick-generate-key", "Publish Test <test@example.invalid>",
                "ed25519", "sign", "never",
            ],
            capture_output=True, text=True,
            env=clean_env(GNUPGHOME=self.gnupghome),
        )
        if r.returncode != 0:
            self.skipTest("could not generate an ephemeral gpg key: %s" % r.stderr[:200])
        keyid = subprocess.run(
            ["gpg", "--batch", "--list-secret-keys", "--with-colons"],
            capture_output=True, text=True,
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
            "PATH": f"{gate_bin}:{os.environ['PATH']}",
            "PUBLISH_GATE_LOG": self.gate_log,
        }
        git("config", "user.signingkey", fpr, cwd=self.work)
        git("config", "gpg.format", "openpgp", cwd=self.work)
        git("config", "commit.gpgsign", "true", cwd=self.work)

    def _signed_commit(self, content, message):
        p = os.path.join(self.work, "signed.txt")
        with open(p, "a") as fh:
            fh.write(content)
        git("add", "signed.txt", cwd=self.work, env=self.signing_env)
        git("commit", "-q", "-S", "-m", message, cwd=self.work, env=self.signing_env)
        return git("rev-parse", "HEAD", cwd=self.work).stdout.strip()

    def _race_env(self, raced_sha):
        fake_bin = os.path.join(self.tmp, "race-bin")
        os.makedirs(fake_bin, exist_ok=True)
        real_git = shutil.which("git") or "/usr/bin/git"
        wrapper = os.path.join(fake_bin, "git")
        with open(wrapper, "w") as fh:
            fh.write(
                """#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == push && " $* " == *" github "* && " $* " != *" --dry-run "* ]]; then
    "$REAL_GIT" --git-dir="$RACE_REMOTE" fetch --quiet "$PWD" "$RACE_SHA"
    "$REAL_GIT" --git-dir="$RACE_REMOTE" update-ref refs/heads/main "$RACE_SHA"
    echo "simulated mirror/ref race" >&2
    exit 1
fi
exec "$REAL_GIT" "$@"
"""
            )
        os.chmod(wrapper, 0o755)
        return clean_env(**{
            **self.signing_env,
            "PATH": f"{fake_bin}:{self.signing_env['PATH']}",
            "REAL_GIT": real_git,
            "RACE_REMOTE": self.github,
            "RACE_SHA": raced_sha,
        })

    def _readback_failure_env(self):
        fake_bin = os.path.join(self.tmp, "readback-bin")
        os.makedirs(fake_bin, exist_ok=True)
        real_git = shutil.which("git") or "/usr/bin/git"
        marker = os.path.join(self.tmp, "github-pushed")
        wrapper = os.path.join(fake_bin, "git")
        with open(wrapper, "w") as fh:
            fh.write(
                """#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == push && " $* " == *" github "* && " $* " != *" --dry-run "* ]]; then
    if "$REAL_GIT" "$@"; then status=0; else status=$?; fi
    : >"$READBACK_FAIL_MARKER"
    exit "$status"
fi
if [[ ${1:-} == ls-remote && ${2:-} == github && -e $READBACK_FAIL_MARKER ]]; then
    echo "simulated readback network failure" >&2
    exit 1
fi
exec "$REAL_GIT" "$@"
"""
            )
        os.chmod(wrapper, 0o755)
        return clean_env(**{
            **self.signing_env,
            "PATH": f"{fake_bin}:{self.signing_env['PATH']}",
            "REAL_GIT": real_git,
            "READBACK_FAIL_MARKER": marker,
        })

    def _successful_push_race_env(self, raced_sha):
        fake_bin = os.path.join(self.tmp, "success-race-bin")
        os.makedirs(fake_bin, exist_ok=True)
        real_git = shutil.which("git") or "/usr/bin/git"
        wrapper = os.path.join(fake_bin, "git")
        with open(wrapper, "w") as fh:
            fh.write(
                """#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == push && " $* " == *" github "* && " $* " != *" --dry-run "* ]]; then
    if "$REAL_GIT" "$@"; then status=0; else status=$?; fi
    "$REAL_GIT" --git-dir="$RACE_REMOTE" update-ref refs/heads/main "$RACE_SHA"
    exit "$status"
fi
exec "$REAL_GIT" "$@"
"""
            )
        os.chmod(wrapper, 0o755)
        return clean_env(**{
            **self.signing_env,
            "PATH": f"{fake_bin}:{self.signing_env['PATH']}",
            "REAL_GIT": real_git,
            "RACE_REMOTE": self.github,
            "RACE_SHA": raced_sha,
        })

    def _third_remote_revision(self):
        other = os.path.join(self.tmp, "racer")
        git("clone", "-q", self.github, other, cwd=self.tmp)
        git("config", "commit.gpgsign", "false", cwd=other)
        with open(os.path.join(other, "race.txt"), "w") as fh:
            fh.write("third revision\n")
        git("add", "race.txt", cwd=other)
        git("commit", "-q", "--no-gpg-sign", "-m", "racing writer", cwd=other)
        third = git("rev-parse", "HEAD", cwd=other).stdout.strip()
        git("push", "-q", "origin", f"{third}:refs/heads/race-object", cwd=other)
        return third

    def test_default_does_not_push_but_reports_what_it_would_do(self):
        """A bare invocation with publishable work reports but does not push."""
        head = self._signed_commit("s\n", "a signed commit")
        before = (self.remote_sha(self.origin), self.remote_sha(self.github))
        r = subprocess.run(
            [PUBLISH], cwd=self.work, capture_output=True, text=True,
            env=clean_env(**self.signing_env),
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("re-run with --publish", r.stdout)
        after = (self.remote_sha(self.origin), self.remote_sha(self.github))
        self.assertEqual(before, after, "a bare invocation moved a remote")
        self.assertNotIn(head, [x for x in after if x])

    def test_dry_run_is_still_accepted_as_a_synonym(self):
        self._signed_commit("s\n", "a signed commit")
        r = subprocess.run(
            [PUBLISH, "--dry-run"], cwd=self.work, capture_output=True, text=True,
            env=clean_env(**self.signing_env),
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertNotIn("unknown argument", r.stderr)
        self.assertIn("re-run with --publish", r.stdout)

    def test_signed_commit_passes_the_gate(self):
        self._signed_commit("s\n", "a signed commit")
        r = subprocess.run(
            [PUBLISH, "--dry-run"], cwd=self.work, capture_output=True, text=True,
            env=clean_env(**self.signing_env),
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("all signed", r.stdout)
        self.assertIn("would accept", r.stdout)

    def test_publish_runs_tracked_pre_push_group_exactly_once(self):
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
        self.assertEqual(self.remote_sha(self.github), head)

    def test_failed_explicit_gate_stops_before_both_real_pushes(self):
        head = self._signed_commit("s\n", "a signed commit")
        before = (self.remote_sha(self.origin), self.remote_sha(self.github))
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
        after = (self.remote_sha(self.origin), self.remote_sha(self.github))
        self.assertEqual(before, after)
        self.assertNotIn(head, after)

    def test_dirty_tracked_tree_is_refused_before_the_gate(self):
        head = self._signed_commit("s\n", "a signed commit")
        before = (self.remote_sha(self.origin), self.remote_sha(self.github))
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
        self.assertEqual((self.remote_sha(self.origin), self.remote_sha(self.github)), before)
        self.assertNotIn(head, before)

    def test_gate_mutation_is_refused_before_hooks_are_bypassed(self):
        head = self._signed_commit("s\n", "a signed commit")
        before = (self.remote_sha(self.origin), self.remote_sha(self.github))

        r = subprocess.run(
            [PUBLISH, "--publish"],
            cwd=self.work,
            capture_output=True,
            text=True,
            env=clean_env(
                **{**self.signing_env, "PUBLISH_GATE_MUTATE": "dirty"}
            ),
        )

        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("post-gate: tracked working tree or index is dirty", r.stderr)
        with open(self.gate_log) as fh:
            invocations = [line.strip() for line in fh if line.strip()]
        self.assertEqual(invocations, ["run pre-push --force"])
        self.assertEqual((self.remote_sha(self.origin), self.remote_sha(self.github)), before)
        self.assertNotIn(head, before)

    def test_mirror_race_already_at_target_is_success(self):
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
        self.assertIn("push mirror", combined)
        self.assertNotIn("PARTIAL PUBLISH", combined)
        self.assertEqual(self.remote_sha(self.origin), head)
        self.assertEqual(self.remote_sha(self.github), head)

    def test_race_to_third_revision_is_still_partial_publish(self):
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
        self.assertIn("PARTIAL PUBLISH", combined)
        self.assertIn("github", combined)
        self.assertIn("github observed: %s" % third, combined)
        self.assertIn("git fetch github main", combined)
        self.assertIn("git merge-base --is-ancestor %s %s" % (third, head), combined)
        self.assertIn("git push github %s:refs/heads/main" % head[:12], combined)
        self.assertNotIn("now behind", combined)
        self.assertEqual(self.remote_sha(self.origin), head)
        self.assertEqual(self.remote_sha(self.github), third)

    def test_post_push_readback_failure_is_loud_partial_publish(self):
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
        self.assertIn("PARTIAL PUBLISH", combined)
        self.assertIn("github observed: <unreadable>", combined)
        self.assertIn("git ls-remote github refs/heads/main", combined)
        self.assertEqual(self.remote_sha(self.origin), head)
        self.assertEqual(self.remote_sha(self.github), head)

    def test_successful_push_then_third_readback_is_partial_publish(self):
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
        self.assertIn("PARTIAL PUBLISH", combined)
        self.assertIn("github observed: %s" % third, combined)
        self.assertEqual(self.remote_sha(self.origin), head)
        self.assertEqual(self.remote_sha(self.github), third)

    def test_partial_push_exits_nonzero_and_names_the_divergent_remote(self):
        """A remote that passes pre-flight then fails the real push.

        A rejecting `pre-receive` hook is the faithful simulation: `git push
        --dry-run` negotiates refs without transferring a pack, so it never runs
        the hook and pre-flight passes — exactly like a fault that opens after
        pre-flight. Push order is origin then github, so origin lands and github
        does not, which is the divergence the tool must report.
        """
        head = self._signed_commit("s\n", "a signed commit")
        hook = os.path.join(self.github, "hooks", "pre-receive")
        os.makedirs(os.path.dirname(hook), exist_ok=True)
        with open(hook, "w") as fh:
            fh.write("#!/bin/sh\necho 'simulated remote fault' >&2\nexit 1\n")
        os.chmod(hook, 0o755)
        self.addCleanup(lambda: os.path.exists(hook) and os.unlink(hook))

        r = subprocess.run(
            [PUBLISH, "--publish"], cwd=self.work, capture_output=True, text=True,
            env=clean_env(**self.signing_env),
        )
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        combined = r.stdout + r.stderr
        self.assertIn("PARTIAL PUBLISH", combined)
        self.assertIn("DIVERGED", combined)
        self.assertIn("github", combined)
        # It must print the exact reconciliation command, not just complain.
        self.assertIn("git push github %s:refs/heads/main" % head[:12], combined)
        # origin genuinely did receive it — that is the divergence being reported.
        self.assertEqual(self.remote_sha(self.origin), head)
        self.assertNotEqual(self.remote_sha(self.github), head)


class TestDoesNotEscapeItsSandbox(unittest.TestCase):
    """Hostile inherited Git selectors must not escape the temporary sandbox."""

    def test_inherited_git_dir_does_not_reach_the_outer_repository(self):
        outer = tempfile.mkdtemp(prefix="publish-test-outer-")
        self.addCleanup(shutil.rmtree, outer, ignore_errors=True)
        subprocess.run(
            ["git", "init", "--quiet", "--initial-branch=main", outer],
            check=True, capture_output=True, env=clean_env(),
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
                "python3", "-m", "unittest",
                "publish-slow-test.TestNoop.test_both_already_current_is_a_noop_and_succeeds",
            ],
            # cwd must be this file's directory: `-m unittest publish-slow-test...`
            # resolves the module through cwd on sys.path, and there is no
            # publish-slow-test at the repository root. f93f232d moved this suite
            # from bin/ to test/bin/ and changed HERE to REPO, which silently
            # turned this guard into an unconditional failure.
            cwd=HERE, capture_output=True, text=True, env=with_hostile,
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

        with open(outer_config) as fh:
            after = fh.read()
        self.assertEqual(
            before, after,
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

    def test_declares_both_remotes(self):
        with open(PUBLISH) as fh:
            body = fh.read()
        self.assertIn("REMOTES=(origin github)", body)

    def test_pre_push_commands_use_tracked_tree_scope(self):
        with open(os.path.join(REPO, "lefthook.yml")) as fh:
            config = fh.read()
        pre_push = config.split("\npre-push:\n", 1)[1]
        self.assertIn("git ls-files", pre_push)
        self.assertIn('printf "%s\\n" lefthook.yml', pre_push)
        self.assertEqual(pre_push.count(": {files};"), pre_push.count("      run:"))


if __name__ == "__main__":
    unittest.main()
