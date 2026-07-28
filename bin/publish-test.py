#!/usr/bin/env python3
"""Tests for bin/publish — the dual-remote publish guard.

Every test builds a throwaway repository with two local bare remotes named
`origin` and `github`, so nothing touches the real remotes and no network is
required. The point of these tests is the refusal paths: bin/publish is a tool
whose value is entirely in what it declines to do.

Run: python3 -m unittest -v bin/publish-test.py
"""

import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PUBLISH = os.path.join(HERE, "publish")


# Git environment variables that point git at a specific repository. These MUST
# be scrubbed before running git in a throwaway directory.
#
# This is not hypothetical tidiness. When this suite runs from inside a git hook —
# which is exactly what lefthook's pre-commit does — the hook environment carries
# GIT_DIR and GIT_INDEX_FILE for the REAL repository. Inheriting them makes every
# git call below operate on the real repo regardless of `cwd`, so
# `git init --bare` set `core.bare = true` on the actual nix-config repository and
# broke every linked worktree in it, including a concurrent session's.
#
# `cwd=` is not protection: an explicit GIT_DIR beats the working directory.
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
    """os.environ with every repository-pointing git variable removed.

    Use this for ANY subprocess that may invoke git, including bin/publish
    itself - not just the git() helper. Under a git hook the inherited GIT_DIR
    would otherwise redirect the child at the real repository.
    """
    e = dict(os.environ)
    for var in _GIT_LOCATION_VARS:
        e.pop(var, None)
    e.update(extra)
    return e


def git(*args, cwd, check=True, env=None):
    e = clean_env()
    # Deterministic, signature-free commits by default; individual tests opt in
    # to signing behaviour by rewriting %G? expectations instead.
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
        self.assertIn("not an ancestor of main", r.stderr)

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
        """Regression: the range must be `--not --remotes`, not `<r>/<b>..<rev>`.

        This is the exact shape that caught the bug. `feature` does not exist on
        either remote, so both are in need_push and the signature gate runs. But
        its tip is already published as an ancestor of main, so the set of newly
        published commits is empty. With the old `<r>/<b>..<rev>` form the range
        silently became the whole repository and flagged the unsigned base commit.
        """
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
        self.signing_env = {"GNUPGHOME": self.gnupghome}
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

    def test_signed_commit_passes_the_gate(self):
        self._signed_commit("s\n", "a signed commit")
        r = subprocess.run(
            [PUBLISH, "--dry-run"], cwd=self.work, capture_output=True, text=True,
            env=clean_env(**self.signing_env),
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("all signed", r.stdout)
        self.assertIn("would accept", r.stdout)

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
            [PUBLISH], cwd=self.work, capture_output=True, text=True,
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
    """Regression: the suite must never touch the repository it is run from.

    Running these tests under lefthook's pre-commit hook once set
    `core.bare = true` on the real nix-config repository, because the hook
    environment exports GIT_DIR and the harness inherited it — so
    `git init --bare` in a temp dir reconfigured the real repo and broke every
    linked worktree in it. `cwd=` does not protect against that; an explicit
    GIT_DIR wins. This test simulates the hook environment and proves the scrub.
    """

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

        # Exactly what a git hook hands its children.
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
                "publish-test.TestNoop.test_both_already_current_is_a_noop_and_succeeds",
            ],
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

    def test_never_embeds_a_credential(self):
        """Acceptance criterion: never embeds a credential or token."""
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


if __name__ == "__main__":
    unittest.main()
