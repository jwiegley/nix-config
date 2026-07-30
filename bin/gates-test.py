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

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

BIN = Path(__file__).parent
# The real checkout. Used only to READ a genuine signature blob for the
# unverifiable-signature test; never mutated.
REPO = Path(__file__).resolve().parent.parent
VERIFY_SIGNATURES = BIN / "verify-signatures"
CROSS_CONSUMER_EVAL = BIN / "cross-consumer-eval"
CONSUMER_INVENTORY = BIN / "consumer-inventory"
DARWIN_SURFACE_DIFF = BIN / "darwin-surface-diff"
DARWIN_SURFACE_BASELINE = BIN / "darwin-surface-baseline"
COVERAGE_REPORT = BIN / "coverage-report"

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
        # A REAL signature blob, harvested from this repository's own HEAD, plus an
        # empty keyring. Both halves are load-bearing and were measured:
        #
        #   fabricated garbage ("bm90YXNpZ25hdHVyZQ==")  -> git reports N (unsigned),
        #       so this test skipped and the E path was never exercised at all.
        #   a real signature blob + empty keyring        -> git reports E.
        #
        # E is the CI shape: a runner with no keyring sees E for every signed commit,
        # and accepting E would make the job permanently green while verifying
        # nothing. The signature will not match this fabricated commit's content, but
        # that is irrelevant -- with no key present, git cannot get far enough to
        # care, which is exactly the condition under test.
        #
        # Harvesting from HEAD is deterministic here because this repository's policy
        # IS signed commits only. If HEAD carries no signature that is a policy
        # violation, so the assertion below fails rather than skips.
        real = git("cat-file", "commit", "HEAD", cwd=REPO).stdout.split("\n")
        sig = []
        for line in real:
            if line.startswith("gpgsig"):
                sig.append(line)
            elif sig:
                if line.startswith(" "):
                    sig.append(line)
                else:
                    break
        self.assertTrue(
            sig,
            "this repository's HEAD carries no signature; 'signed commits only' is "
            "already violated, which is a finding rather than a reason to skip",
        )
        lines[insert_at + 1 : insert_at + 1] = sig
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

        empty_home = os.path.join(self.tmp, "empty-gnupg")
        os.makedirs(empty_home, exist_ok=True)
        os.chmod(empty_home, 0o700)
        env = clean_env()
        env["GNUPGHOME"] = empty_home
        status = subprocess.run(
            ["git", "log", "--pretty=%G?", "-1", forged],
            cwd=self.repo,
            capture_output=True,
            text=True,
            env=env,
        ).stdout.strip()
        self.assertIn(
            status,
            ("E", "B"),
            "expected an unverifiable status from a real signature under an empty "
            "keyring, got %r; without one this test cannot exercise the E path that "
            "is the whole point" % status,
        )

        out = self.run_tool(
            SIGVERIFY_BASE=base, SIGVERIFY_HEAD=forged, GNUPGHOME=empty_home
        )
        self.assertNotEqual(
            out.returncode,
            0,
            "an unverifiable signature (%s) was accepted:\n%s" % (status, out.stdout),
        )
        self.assertIn("REJECTED", out.stdout + out.stderr)

    def test_expired_key_signature_is_accepted_not_rejected(self):
        """Y (good signature, expired key) must PASS; R/E/B/N must not.

        Y proves the commit was signed by the project's key -- `git verify-commit`
        exits 0 on it -- and compromise is signalled by R (revoked), which stays
        rejected. Rejecting Y created a recurring cliff: on the day a key expired,
        every historical commit failed at once. The signing key here expires
        2026-11-25, which is what surfaced it.

        Built with a REAL key that really expires: generate one with a few seconds of
        life, sign while it is valid, wait past expiry, verify. No fabrication, so the
        code path under test is the one git actually takes.
        """
        import time

        gnupg = os.path.join(self.tmp, "gnupg-expiring")
        os.makedirs(gnupg, exist_ok=True)
        os.chmod(gnupg, 0o700)
        env = clean_env()
        env["GNUPGHOME"] = gnupg

        gen = subprocess.run(
            [
                "gpg",
                "--batch",
                "--quiet",
                "--passphrase",
                "",
                "--pinentry-mode",
                "loopback",
                "--quick-generate-key",
                "Expiry Probe <probe@example.invalid>",
                "default",
                "sign",
                "seconds=6",
            ],
            capture_output=True,
            text=True,
            env=env,
        )
        if gen.returncode != 0:
            self.skipTest("could not generate an expiring key: %s" % gen.stderr[:200])

        keyid = subprocess.run(
            ["gpg", "--batch", "--list-keys", "--with-colons", "probe@example.invalid"],
            capture_output=True,
            text=True,
            env=env,
        ).stdout
        fpr = next(
            (ln.split(":")[9] for ln in keyid.splitlines() if ln.startswith("fpr")),
            None,
        )
        self.assertTrue(fpr, "generated key has no fingerprint")

        base = self._commit("a", "base")
        # Sign WHILE the key is valid.
        with open(os.path.join(self.repo, "signed"), "w") as fh:
            fh.write("x\n")
        git("add", "signed", cwd=self.repo)
        signed = subprocess.run(
            [
                "git",
                "-c",
                "user.signingkey=" + fpr,
                "-c",
                "commit.gpgsign=true",
                "-c",
                "gpg.program=gpg",
                "commit",
                "-q",
                "-m",
                "signed while valid",
            ],
            cwd=self.repo,
            capture_output=True,
            text=True,
            env=env,
        )
        if signed.returncode != 0:
            self.skipTest("could not sign with the probe key: %s" % signed.stderr[:200])
        head = git("rev-parse", "HEAD", cwd=self.repo).stdout.strip()

        # Confirm it is G before expiry, so a later Y is attributable to the expiry
        # and not to a broken signature.
        before = subprocess.run(
            ["git", "log", "--pretty=%G?", "-1", head],
            cwd=self.repo,
            capture_output=True,
            text=True,
            env=env,
        ).stdout.strip()
        self.assertEqual(before, "G", "probe commit did not verify as G while valid")

        time.sleep(8)  # outlive the key

        after = subprocess.run(
            ["git", "log", "--pretty=%G?", "-1", head],
            cwd=self.repo,
            capture_output=True,
            text=True,
            env=env,
        ).stdout.strip()
        self.assertEqual(after, "Y", "expected Y after the key expired, got %r" % after)

        out = self.run_tool(SIGVERIFY_BASE=base, SIGVERIFY_HEAD=head, GNUPGHOME=gnupg)
        self.assertEqual(
            out.returncode,
            0,
            "Y (expired key) must be accepted; rejecting it makes every historical "
            "commit fail the day a key expires:\n%s\n%s" % (out.stdout, out.stderr),
        )
        self.assertNotIn("REJECTED", out.stdout + out.stderr)

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

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gates-inv-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo"
        self.root.mkdir()
        subprocess.run(
            ["git", "-C", str(self.root), "init", "--quiet"],
            check=True,
            capture_output=True,
            text=True,
            env=clean_env(),
        )
        self.sample = self.root / "sample.nix"
        self.sample.write_text("{ }\n")
        subprocess.run(
            ["git", "-C", str(self.root), "add", "--", "sample.nix"],
            check=True,
            capture_output=True,
            text=True,
            env=clean_env(),
        )
        subprocess.run(
            [
                "git",
                "-C",
                str(self.root),
                "-c",
                "user.name=Inventory Test",
                "-c",
                "user.email=inventory@example.invalid",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "--quiet",
                "-m",
                "baseline",
            ],
            check=True,
            capture_output=True,
            text=True,
            env=clean_env(),
        )

    def run_write(self, dest, **environment):
        return subprocess.run(
            [str(CONSUMER_INVENTORY), "--write", str(dest)],
            cwd=str(BIN.parent),
            capture_output=True,
            text=True,
            env=clean_env(
                CONSUMER_INVENTORY_REPO_ROOT=str(self.root),
                CONSUMER_INVENTORY_CONSUMER_BASE=self.temp.name,
                **environment,
            ),
        )

    def test_write_refuses_when_repo_head_is_unresolvable(self):
        dest = Path(self.temp.name) / "null-head.json"
        # The override is an ENV VAR, not a flag. An earlier manual check of this
        # guard passed for the wrong reason: it used a `--repo-head` flag that
        # does not exist, so the tool died on "unknown argument" rather than on
        # the null-head refusal. That is precisely the vacuous-negative-test
        # failure this file exists to prevent, and it happened in my own
        # verification of this very guard.
        r = self.run_write(dest, CONSUMER_INVENTORY_REPO_HEAD="")
        self.assertNotIn(
            "unknown argument",
            r.stdout + r.stderr,
            "the tool rejected the invocation rather than exercising the guard",
        )
        self.assertNotEqual(
            r.returncode, 0, "wrote an artifact with no revision:\n%s" % r.stdout
        )
        self.assertFalse(
            dest.exists(),
            "refused but still left a file behind, which is worse than either",
        )
        self.assertIn("repoHead", r.stdout + r.stderr)

    def test_write_stamps_clean_head_and_refuses_dirty_tree(self):
        clean_dest = Path(self.temp.name) / "clean.json"
        result = self.run_write(clean_dest)
        self.assertEqual(result.returncode, 0, result.stderr)
        actual_head = subprocess.run(
            ["git", "-C", str(self.root), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
            env=clean_env(),
        ).stdout.strip()
        self.assertEqual(json.loads(clean_dest.read_text())["repoHead"], actual_head)

        self.sample.rename(self.root / "moved.nix")
        dirty_dest = Path(self.temp.name) / "dirty.json"
        result = self.run_write(dirty_dest)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("tracked files differ from HEAD", result.stdout + result.stderr)
        self.assertFalse(dirty_dest.exists())


class TestGatesAreRegistered(unittest.TestCase):
    """A gate nothing invokes is not a gate."""

    def test_every_gate_script_is_executable(self):
        for tool in (
            VERIFY_SIGNATURES,
            CROSS_CONSUMER_EVAL,
            CONSUMER_INVENTORY,
            DARWIN_SURFACE_DIFF,
            DARWIN_SURFACE_BASELINE,
            COVERAGE_REPORT,
        ):
            self.assertTrue(os.access(tool, os.X_OK), "%s is not executable" % tool)

    def test_quality_registers_the_gate_suites(self):
        body = (BIN / "quality").read_text()
        for suite in (
            "signatures",
            "consumer-eval",
            "darwin-surface",
            "coverage",
            "coverage-live",
        ):
            self.assertIn(
                "%s) run_%s ;;" % (suite, suite.replace("-", "_")),
                body,
                "bin/quality has no dispatch arm for %s" % suite,
            )

    def test_coverage_gate_delegates_from_every_invocation_surface(self):
        hook = (REPO / "lefthook.yml").read_text()
        self.assertRegex(
            hook,
            r"(?m)^    quality-tier:\n      run: bin/quality --tier pre-commit$",
        )
        self.assertRegex(
            hook,
            r'(?m)^      run: ": \{files\}; bin/quality --python-tier pre-push python-test coverage"$',
        )
        self.assertRegex(
            hook,
            r'(?m)^      run: ": \{files\}; bin/quality coverage-live"$',
        )

        ci = (REPO / ".github/workflows/ci.yml").read_text()
        self.assertRegex(
            ci,
            r"(?m)^          -c bin/quality --python-tier pre-commit$",
        )
        self.assertRegex(
            ci,
            r"(?m)^          python-lint python-test coverage$",
        )

        makefile = (REPO / "Makefile").read_text()
        self.assertRegex(
            makefile,
            r"(?m)^\tbin/quality --python-tier pre-push python-test coverage darwin-surface$",
        )

    def test_python_tiers_are_wired_without_a_second_quality_authority(self):
        hook = (REPO / "lefthook.yml").read_text()
        self.assertRegex(
            hook,
            r"(?m)^      run: bin/quality --tier pre-commit$",
        )
        suites = subprocess.run(
            [str(BIN / "quality"), "--list"],
            cwd=REPO,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.splitlines()
        self.assertEqual(suites.count("python-test"), 1)
        self.assertNotIn("python-test-pre-push", suites)

    def test_darwin_surface_gate_is_wired_to_local_expensive_tier_entrypoints(self):
        self.assertRegex(
            (REPO / "lefthook.yml").read_text(),
            r'(?m)^\s+run: ": \{files\}; bin/quality darwin-surface"$',
        )
        self.assertRegex(
            (REPO / "Makefile").read_text(),
            r"(?m)^\tbin/quality --python-tier pre-push python-test coverage darwin-surface$",
        )

    def test_darwin_surface_is_not_wired_to_remote_ci_until_root_is_portable(self):
        ci = (REPO / ".github/workflows/ci.yml").read_text()
        self.assertNotRegex(ci, r"(?m)^\s+run: bin/quality darwin-surface$")
        self.assertIn("LAN-only ssh://gitea stock-trader input", ci)

    def test_precommit_tier_always_runs_python_authorities(self):
        config = (REPO / "lefthook.yml").read_text()
        self.assertRegex(
            config,
            r"(?m)^    quality-tier:\n      run: bin/quality --tier pre-commit$",
        )
        self.assertNotRegex(config, r"(?m)^      glob:")
        quality = (BIN / "quality").read_text()
        core = re.search(r"(?ms)^PRE_COMMIT_CORE_SUITES=\(\n(?P<body>.*?)^\)$", quality)
        self.assertIsNotNone(core)
        for suite in ("python-lint", "python-test"):
            self.assertRegex(core.group("body"), rf"(?m)^    {suite}$")
        self.assertNotRegex(core.group("body"), r"(?m)^    portable-eval$")
        expensive = re.search(
            r"(?ms)^EXPENSIVE_SUITES=\(\n(?P<body>.*?)^\)$", quality
        )
        self.assertIsNotNone(expensive)
        for suite in (
            "python-test",
            "portable-eval",
            "consumer-eval",
            "signatures",
            "coverage",
            "coverage-live",
            "darwin-surface",
        ):
            self.assertRegex(expensive.group("body"), rf"(?m)^    {suite}$")
        registered = set(
            subprocess.run(
                [str(BIN / "quality"), "--list"],
                cwd=REPO,
                capture_output=True,
                text=True,
                check=True,
            ).stdout.splitlines()
        )
        pre_commit = set(core.group("body").split()) | {"coverage"}
        expensive_set = set(expensive.group("body").split())
        self.assertEqual(pre_commit | expensive_set, registered)
        self.assertEqual(pre_commit & expensive_set, {"python-test", "coverage"})

    def test_expensive_assurance_is_low_frequency_and_manual(self):
        workflow = (REPO / ".github/workflows/portable-assurance.yml").read_text()
        self.assertIn('cron: "17 2,14 * * *"', workflow)
        self.assertIn("workflow_dispatch:", workflow)
        self.assertNotRegex(workflow, r"(?m)^  (push|pull_request):")
        self.assertRegex(
            workflow, r"(?m)^        run: bin/quality portable-eval$"
        )
        self.assertNotRegex(
            workflow, r"(?m)^\s+run: bin/quality --tier expensive$"
        )
        self.assertIn("portable-native:", workflow)
        self.assertIn("runner: macos-15", workflow)
        self.assertRegex(
            workflow,
            r"(?m)^      - uses: DeterminateSystems/magic-nix-cache-action@main\n        if: runner\.os != 'macOS'$",
        )

        regular_ci = (REPO / ".github/workflows/ci.yml").read_text()
        self.assertNotIn("  portable-eval:", regular_ci)
        self.assertNotIn("  portable-native:", regular_ci)

        makefile = (REPO / "Makefile").read_text()
        self.assertRegex(makefile, r"(?m)^expensive:\n\tbin/quality --tier expensive$")

    def test_no_gate_contains_common_credential_markers(self):
        for tool in (
            VERIFY_SIGNATURES,
            CROSS_CONSUMER_EVAL,
            CONSUMER_INVENTORY,
            DARWIN_SURFACE_DIFF,
            DARWIN_SURFACE_BASELINE,
        ):
            body = tool.read_text()
            for pattern in ("ghp_", "github_pat_", "PRIVATE KEY", "password="):
                self.assertNotIn(
                    pattern, body, "%s appears to embed a credential" % tool.name
                )


if __name__ == "__main__":
    unittest.main()


class TestConsumerInventoryLoadBearingFacet(unittest.TestCase):
    """The facet must never demote a real reference.

    #47 needs two numbers from this artifact: the LOAD-BEARING subset it verifies by
    building, and the COMPLETE set it verifies by re-grepping to zero. The facet adds
    the first without dropping any of the second, so its correctness property is
    one-sided -- misjudging prose as code is harmless, the reverse is a silent miss.

    These assertions run against the COMMITTED artifact, because that is the file #47
    and #63 consume; re-deriving would test the code and not the data.
    """

    @classmethod
    def setUpClass(cls):
        path = REPO / "test" / "inventory" / "consumer-inventory.json"
        if not path.exists():
            raise unittest.SkipTest("no committed consumer inventory")
        cls.inv = json.loads(path.read_text())
        cls.refs = cls.inv.get("references", [])
        cls.faceted = [r for r in cls.refs if "loadBearing" in r]

    def test_facet_is_present_on_internal_references(self):
        internal = [r for r in self.refs if r.get("kind") == "internal-config-ai-ref"]
        self.assertTrue(internal, "no internal references to check")
        missing = [r for r in internal if "loadBearing" not in r or "refKind" not in r]
        self.assertEqual(missing, [], "internal references lack the facet")

    def test_no_code_reference_is_demoted(self):
        """A non-comment .nix line is load-bearing. This is the one-sided property."""
        demoted = [
            (r["file"], r["line"], r.get("refKind"))
            for r in self.faceted
            if r["file"].endswith(".nix")
            and r.get("refKind") != "comment"
            and r.get("loadBearing") is not True
        ]
        self.assertEqual(demoted, [], "non-comment .nix references were demoted")

    def test_doc_prose_only_ever_comes_from_markdown(self):
        stray = [
            (r["file"], r["line"])
            for r in self.faceted
            if r.get("refKind") == "doc-prose" and not r["file"].endswith(".md")
        ]
        self.assertEqual(stray, [], "doc-prose applied outside a .md file")

    def test_known_code_and_catalog_traps_stay_load_bearing(self):
        """These look like prose or messages and are neither.

        home-manager-contract-common.nix carries expected VALUES of assertions;
        sources/{ai,pi}.json carry the update tooling's artifact LISTS. A
        prose-detecting filter would wrongly drop them, which is why the rule is
        conservative.
        """
        for needle in (
            "home-manager-contract-common.nix",
            "sources/ai.json",
            "sources/pi.json",
        ):
            hits = [r for r in self.faceted if needle in r["file"]]
            self.assertTrue(hits, "no faceted records for %s" % needle)
            bad = [
                (r["file"], r["line"]) for r in hits if r.get("loadBearing") is not True
            ]
            self.assertEqual(bad, [], "%s references were demoted" % needle)
        self.assertFalse(
            [r for r in self.refs if r["file"] == "packages/update-manifest.nix"],
            "empty transitional manifest retained ghost references",
        )
        self.assertFalse(
            [
                r
                for r in self.refs
                if r["file"] == "test/inventory/consumer-inventory.json"
            ],
            "consumer inventory recursively inventoried itself",
        )
        self.assertFalse(
            [r for r in self.refs if r["file"].startswith("test/baseline/")],
            "consumer inventory classified generated baselines as rename work",
        )
        derivation = self.inv["derivation"]
        self.assertIn("git -C <repo_root> ls-files", derivation["internalConfigAiRefs"])
        self.assertIn("existing-tracked-files", derivation["internalConfigAiRefs"])
        self.assertIn(
            "test/inventory/consumer-inventory.json",
            derivation["internalConfigAiExcludedPaths"],
        )
        self.assertIn("test/baseline/", derivation["internalConfigAiExcludedPrefixes"])

    def test_committed_internal_references_match_generator(self):
        result = subprocess.run(
            [str(CONSUMER_INVENTORY), "--print"],
            cwd=REPO,
            capture_output=True,
            text=True,
            env=clean_env(CONSUMER_INVENTORY_REPO_HEAD=self.inv["repoHead"]),
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        generated = json.loads(result.stdout)
        expected_refs = [
            record
            for record in self.refs
            if record.get("kind") == "internal-config-ai-ref"
        ]
        actual_refs = [
            record
            for record in generated["references"]
            if record.get("kind") == "internal-config-ai-ref"
        ]
        self.assertEqual(actual_refs, expected_refs)

    def test_repo_head_contains_every_inventoried_internal_file(self):
        revision = self.inv.get("repoHead")
        self.assertRegex(revision or "", r"^[0-9a-f]{40}$")
        for path in sorted(
            {
                record["file"]
                for record in self.refs
                if record.get("kind") == "internal-config-ai-ref"
            }
        ):
            probe = subprocess.run(
                ["git", "cat-file", "-e", f"{revision}:{path}"],
                cwd=REPO,
                capture_output=True,
                text=True,
                env=clean_env(),
            )
            self.assertEqual(
                probe.returncode,
                0,
                f"consumer inventory repoHead does not contain {path}",
            )

    def test_tallies_agree_with_the_records(self):
        """A summary that disagrees with its own records is worse than none."""
        by_lb = self.inv["summary"]["byLoadBearing"]
        true_n = sum(1 for r in self.faceted if r["loadBearing"] is True)
        false_n = sum(1 for r in self.faceted if r["loadBearing"] is False)
        self.assertEqual(by_lb.get("true", 0), true_n)
        self.assertEqual(by_lb.get("false", 0), false_n)
        self.assertEqual(
            true_n + false_n,
            self.inv["summary"]["byClassification"].get("rename-now", 0),
            "faceted records should account for exactly the rename-now class",
        )
