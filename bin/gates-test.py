#!/usr/bin/env python3
"""Replayable negative regressions for the fleet programme's shell gates.

Why this file exists. An independent audit observed that of five gates added in
this programme, only `bin/oracle-currency-test.py` shipped negative cases that
could be REPLAYED from the repository. The others — `bin/verify-signatures`,
`bin/cross-consumer-eval`, and `bin/consumer-inventory`'s null-`repoHead`
refusal — had their negative proofs recorded only as prose in commit messages
and issue comments.

That is a real gap and not a pedantic one. This programme's standing rule is that
a gate without a proven negative case is assumed broken, and five separate
defects here were gates reporting success while covering nothing. A negative
proof that lives in a commit message cannot catch the regression that reintroduces
the defect six months from now. "Proven negative" has to mean reproducible.

Everything below runs against throwaway fixtures. Nothing touches a real
repository, a real remote, or a real consumer checkout.

Run: python3 -m unittest -v bin/gates-test.py
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

BIN = Path(__file__).parent
VERIFY_SIGNATURES = BIN / "verify-signatures"
CROSS_CONSUMER_EVAL = BIN / "cross-consumer-eval"
CONSUMER_INVENTORY = BIN / "consumer-inventory"

# Repository-pointing git variables. A test that shells out to git in a temp
# directory MUST scrub these: under a git hook they name the REAL repository and
# beat `cwd`, which is how a sibling suite once set core.bare=true on the live
# checkout and broke every linked worktree at once.
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
    "GIT_CEILING_DIRECTORIES",
)


def clean_env(**extra):
    env = dict(os.environ)
    for var in _GIT_LOCATION_VARS:
        env.pop(var, None)
    env.update(extra)
    return env


def git(*args, cwd, check=True, env=None):
    e = clean_env(
        GIT_AUTHOR_NAME="Test",
        GIT_AUTHOR_EMAIL="test@example.invalid",
        GIT_COMMITTER_NAME="Test",
        GIT_COMMITTER_EMAIL="test@example.invalid",
        GIT_AUTHOR_DATE="2026-01-01T00:00:00+0000",
        GIT_COMMITTER_DATE="2026-01-01T00:00:00+0000",
    )
    if env:
        e.update(env)
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, env=e)
    if check and r.returncode != 0:
        raise AssertionError(
            "git %s failed in %s:\n%s\n%s" % (" ".join(args), cwd, r.stdout, r.stderr)
        )
    return r


class TestVerifySignaturesRejects(unittest.TestCase):
    """bin/verify-signatures must be fail-closed, and provably so.

    The audit's point: the tool IS fail-closed by construction — only G and U
    pass, so a keyring-less run yields E and rejects. But "by construction" is an
    argument, and an argument does not fail when someone widens the accepted set.
    These tests fail if it is widened.
    """

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="gates-sig-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.repo = os.path.join(self.tmp, "repo")
        git("init", "--quiet", "--initial-branch=main", self.repo, cwd=self.tmp)
        git("config", "commit.gpgsign", "false", cwd=self.repo)

    def _commit(self, name, message):
        with open(os.path.join(self.repo, name), "w") as fh:
            fh.write("x\n")
        git("add", name, cwd=self.repo)
        git("commit", "-q", "--no-gpg-sign", "-m", message, cwd=self.repo)
        return git("rev-parse", "HEAD", cwd=self.repo).stdout.strip()

    def run_tool(self, **env):
        return subprocess.run(
            [str(VERIFY_SIGNATURES)],
            cwd=self.repo,
            capture_output=True,
            text=True,
            env=clean_env(**env),
        )

    def test_unsigned_commit_in_range_is_rejected(self):
        base = self._commit("a", "base")
        head = self._commit("b", "an unsigned commit")
        r = self.run_tool(SIGVERIFY_BASE=base, SIGVERIFY_HEAD=head)
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        combined = r.stdout + r.stderr
        self.assertIn("REJECTED", combined)
        # %G? for an unsigned commit is N. If the accepted set is ever widened to
        # include it, this assertion is what fails.
        self.assertIn("[N]", combined)

    def test_unverifiable_signature_is_rejected_not_ignored(self):
        """A signature that cannot be checked must reject, never pass.

        This is the CI shape: a runner with no keyring sees E for every signed
        commit. Passing there would make the job permanently green while
        verifying nothing — the exact defect class this programme keeps finding.
        """
        base = self._commit("a", "base")
        # Fabricate a commit carrying a gpgsig header that no keyring can verify,
        # so %G? reports E rather than N. Done by rewriting the commit object
        # directly: no key material and no signing capability required.
        head = self._commit("b", "second")
        raw = git("cat-file", "commit", head, cwd=self.repo).stdout
        lines = raw.split("\n")
        insert_at = next(
            i for i, line in enumerate(lines) if line.startswith("committer")
        )
        fake = [
            "gpgsig -----BEGIN PGP SIGNATURE-----",
            " ",
            " bm90YXNpZ25hdHVyZQ==",
            " -----END PGP SIGNATURE-----",
        ]
        lines[insert_at + 1 : insert_at + 1] = fake
        r = subprocess.run(
            ["git", "hash-object", "-t", "commit", "-w", "--stdin"],
            cwd=self.repo,
            input="\n".join(lines),
            capture_output=True,
            text=True,
            env=clean_env(),
        )
        if r.returncode != 0:
            self.skipTest(
                "could not fabricate a signed commit object: %s" % r.stderr[:200]
            )
        forged = r.stdout.strip()
        git("update-ref", "refs/heads/main", forged, cwd=self.repo)

        status = git("log", "--pretty=%G?", "-1", forged, cwd=self.repo).stdout.strip()
        if status not in ("E", "B"):
            self.skipTest("git reported %r, not an unverifiable status" % status)

        out = self.run_tool(SIGVERIFY_BASE=base, SIGVERIFY_HEAD=forged)
        self.assertNotEqual(
            out.returncode,
            0,
            "an unverifiable signature (%s) was accepted:\n%s" % (status, out.stdout),
        )
        self.assertIn("REJECTED", out.stdout + out.stderr)

    def test_empty_range_is_explicit_about_having_checked_nothing(self):
        """An empty range exits 0, and must SAY that it verified nothing.

        Exiting 0 here is defensible — there is genuinely nothing to check — but
        it is the same "passed having checked nothing" shape the programme is
        strict about elsewhere, so the output must not read as a clean bill of
        health. STRICT mode turns it into a failure for callers that need one.
        """
        base = self._commit("a", "base")
        r = self.run_tool(SIGVERIFY_BASE=base, SIGVERIFY_HEAD=base)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("nothing to verify", r.stdout + r.stderr)

        strict = self.run_tool(
            SIGVERIFY_BASE=base, SIGVERIFY_HEAD=base, SIGVERIFY_STRICT="1"
        )
        self.assertNotEqual(
            strict.returncode,
            0,
            "SIGVERIFY_STRICT=1 must refuse to pass on an empty range:\n%s"
            % (strict.stdout + strict.stderr),
        )


class TestCrossConsumerEvalRefusesEmptySuccess(unittest.TestCase):
    """The honesty guards must be able to FIRE, not merely exist.

    An independent audit found that on a default full run `ran >= 1` always,
    because shared-work is this repo's own fixture and has no checkout to be
    missing. So the ran==0 refusal was unreachable on the path that is actually
    wired into pre-push, and a run with both consumer checkouts absent would have
    reported success having verified only a self-described moderate proxy.

    Both guards are exercised here through the tool's real surface: positional
    target selection, and VPS_CHECKOUT / VULCAN_CHECKOUT.
    """

    def setUp(self):
        self.nowhere = os.path.join(tempfile.gettempdir(), "gates-no-such-checkout")
        self.assertFalse(
            os.path.exists(self.nowhere), "fixture path unexpectedly exists"
        )

    def run_tool(self, *args, **env):
        return subprocess.run(
            [str(CROSS_CONSUMER_EVAL), *args],
            cwd=str(BIN.parent),
            capture_output=True,
            text=True,
            env=clean_env(**env),
        )

    def test_refuses_success_when_every_selected_target_is_skipped(self):
        """ran == 0 must refuse. Reachable only via a named subset."""
        r = self.run_tool(
            "vps",
            "vulcan",
            VPS_CHECKOUT=self.nowhere,
            VULCAN_CHECKOUT=self.nowhere,
        )
        combined = r.stdout + r.stderr
        self.assertNotEqual(
            r.returncode, 0, "evaluated nothing yet reported success:\n%s" % combined
        )
        self.assertIn("evaluated nothing", combined)
        self.assertNotIn("all evaluated consumers passed", combined)

    def test_full_run_refuses_when_only_the_proxy_was_evaluated(self):
        """The hole the audit found: a FULL run with both checkouts missing.

        shared-work still runs, so ran == 1 and the ran==0 guard cannot fire.
        Without the full-run guard this reported success while verifying nothing
        about vulcan or vps.
        """
        r = self.run_tool(VPS_CHECKOUT=self.nowhere, VULCAN_CHECKOUT=self.nowhere)
        combined = r.stdout + r.stderr
        self.assertNotEqual(
            r.returncode,
            0,
            "a full run passed having evaluated only the proxy:\n%s" % combined,
        )
        self.assertIn("ONLY shared-work", combined)

    def test_full_run_refuses_when_only_consumer_locks_were_checked(self):
        """Parsing coherent locks must not count as evaluating reach-in consumers."""
        with tempfile.TemporaryDirectory(prefix="gates-lock-only-") as tmp:
            lock = """{
              "nodes": {
                "nix-config": {"locked": {"rev": "aaaaaaaaaaaaaaaa"}},
                "nix-config-ai": {"locked": {"rev": "aaaaaaaaaaaaaaaa"}}
              }
            }"""
            vps = Path(tmp) / "vps"
            vulcan = Path(tmp) / "vulcan"
            for checkout in (vps, vulcan):
                checkout.mkdir()
                (checkout / "flake.lock").write_text(lock)

            r = self.run_tool(VPS_CHECKOUT=str(vps), VULCAN_CHECKOUT=str(vulcan))

        combined = r.stdout + r.stderr
        self.assertNotEqual(
            r.returncode,
            0,
            f"a full run passed after reading locks but no consumer flakes:\n{combined}",
        )
        self.assertIn("[lock coherence]: OK", combined)
        self.assertIn("ONLY shared-work", combined)
        self.assertNotIn("all evaluated consumers passed", combined)

    def test_strict_mode_turns_a_skip_into_a_failure(self):
        r = self.run_tool("vps", CONSUMER_EVAL_STRICT="1", VPS_CHECKOUT=self.nowhere)
        self.assertNotEqual(
            r.returncode,
            0,
            "CONSUMER_EVAL_STRICT=1 tolerated a skipped consumer:\n%s"
            % (r.stdout + r.stderr),
        )

    def test_unknown_target_is_refused_rather_than_silently_ignored(self):
        r = self.run_tool("not-a-consumer")
        self.assertNotEqual(r.returncode, 0)


class TestConsumerInventoryRefusesNullHead(unittest.TestCase):
    """--write must refuse an artifact that cannot say which tree it describes.

    Every per-reference line number in the inventory is meaningless without the
    revision it was read at, so a null repoHead is not a smaller artifact — it is
    an uninterpretable one.
    """

    def test_write_refuses_when_repo_head_is_unresolvable(self):
        tmp = tempfile.mkdtemp(prefix="gates-inv-")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        dest = os.path.join(tmp, "inventory.json")
        # The override is an ENV VAR, not a flag. An earlier manual check of this
        # guard passed for the wrong reason: it used a `--repo-head` flag that
        # does not exist, so the tool died on "unknown argument" rather than on
        # the null-head refusal. That is precisely the vacuous-negative-test
        # failure this file exists to prevent, and it happened in my own
        # verification of this very guard.
        r = subprocess.run(
            [str(CONSUMER_INVENTORY), "--write", dest],
            cwd=str(BIN.parent),
            capture_output=True,
            text=True,
            env=clean_env(CONSUMER_INVENTORY_REPO_HEAD=""),
        )
        self.assertNotIn(
            "unknown argument",
            r.stdout + r.stderr,
            "the tool rejected the invocation rather than exercising the guard",
        )
        self.assertNotEqual(
            r.returncode, 0, "wrote an artifact with no revision:\n%s" % r.stdout
        )
        self.assertFalse(
            os.path.exists(dest),
            "refused but still left a file behind, which is worse than either",
        )
        self.assertIn("repoHead", r.stdout + r.stderr)


class TestGatesAreRegistered(unittest.TestCase):
    """A gate nothing invokes is not a gate."""

    def test_every_gate_script_is_executable(self):
        for tool in (VERIFY_SIGNATURES, CROSS_CONSUMER_EVAL, CONSUMER_INVENTORY):
            self.assertTrue(os.access(tool, os.X_OK), "%s is not executable" % tool)

    def test_quality_registers_the_gate_suites(self):
        body = (BIN / "quality").read_text()
        for suite in ("signatures", "consumer-eval"):
            self.assertIn(
                "%s) run_%s ;;" % (suite, suite.replace("-", "_")),
                body,
                "bin/quality has no dispatch arm for %s" % suite,
            )

    def test_no_gate_embeds_a_credential(self):
        for tool in (VERIFY_SIGNATURES, CROSS_CONSUMER_EVAL, CONSUMER_INVENTORY):
            body = tool.read_text()
            for pattern in ("ghp_", "github_pat_", "PRIVATE KEY", "password="):
                self.assertNotIn(
                    pattern, body, "%s appears to embed a credential" % tool.name
                )


if __name__ == "__main__":
    unittest.main()
