#!/usr/bin/env python3
"""Replayable negative regressions for the fleet programme's shell gates.

Why this file exists. An independent audit observed that of five gates added in
this programme, only `test/bin/oracle-currency-slow-test.py` shipped negative cases that
could be REPLAYED from the repository. The other signature, cross-consumer, and
immutable-subflake gates had negative proofs recorded only as prose in commit
messages and issue comments.

That is a real gap and not a pedantic one. This programme's standing rule is that
a gate without a proven negative case is assumed broken, and five separate
defects here were gates reporting success while covering nothing. A negative
proof that lives in a commit message cannot catch the regression that reintroduces
the defect six months from now. "Proven negative" has to mean reproducible.

Everything below runs against throwaway fixtures. Nothing touches a real
repository, a real remote, or a real consumer checkout.

Run: python3 -m unittest -v test/bin/gates-slow-test.py
"""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

# The real checkout. Used only to READ a genuine signature blob for the
# unverifiable-signature test; never mutated.
REPO = Path(__file__).resolve().parents[2]
BIN = REPO / "test" / "bin"
VERIFY_SIGNATURES = BIN / "verify-signatures"
CROSS_CONSUMER_EVAL = BIN / "cross-consumer-eval"
CONSUMER_INVENTORY = BIN / "consumer-inventory"
DARWIN_SURFACE_DIFF = BIN / "darwin-surface-diff"
DARWIN_SURFACE_BASELINE = BIN / "darwin-surface-baseline"
IMMUTABLE_SUBFLAKE_CHECK = BIN / "immutable-subflake-check"

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
    """test/bin/verify-signatures must be fail-closed, and provably so.

    The audit's point: the tool IS fail-closed by construction — only G and U
    pass, so a keyring-less run yields E and rejects. But "by construction" is an
    argument, and an argument does not fail when someone widens the accepted set.
    These tests fail if it is widened.
    """

    def setUp(self):
        # Keep GnuPG's agent sockets below Darwin's AF_UNIX path ceiling; the
        # per-user TMPDIR is already too long before the temporary suffix.
        self.tmp = tempfile.mkdtemp(prefix="gates-sig-", dir="/tmp")
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

    def test_base_owned_verifier_rejects_a_head_side_success_stub(self):
        self._commit("initial", "initial")
        verifier = Path(self.repo) / "test" / "bin" / "verify-signatures"
        verifier.parent.mkdir(parents=True)
        verifier.write_text(VERIFY_SIGNATURES.read_text())
        verifier.chmod(0o755)
        git("add", "test/bin/verify-signatures", cwd=self.repo)
        git(
            "commit",
            "-q",
            "--no-gpg-sign",
            "-m",
            "trusted base verifier",
            cwd=self.repo,
        )
        base = git("rev-parse", "HEAD", cwd=self.repo).stdout.strip()

        verifier.write_text("#!/bin/sh\nexit 0\n")
        git("add", "test/bin/verify-signatures", cwd=self.repo)
        git(
            "commit",
            "-q",
            "--no-gpg-sign",
            "-m",
            "malicious success stub",
            cwd=self.repo,
        )
        head = git("rev-parse", "HEAD", cwd=self.repo).stdout.strip()

        trusted = Path(self.tmp) / "trusted" / "verify-signatures"
        trusted.parent.mkdir()
        trusted.write_text(
            git("show", f"{base}:test/bin/verify-signatures", cwd=self.repo).stdout
        )
        trusted.chmod(0o755)
        result = subprocess.run(
            [
                str(trusted),
                "--base",
                base,
                "--head",
                head,
                "--keys-dir",
                str(Path(self.tmp) / "trusted-keys"),
            ],
            cwd=self.repo,
            capture_output=True,
            text=True,
            env=clean_env(),
        )
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("REJECTED [N]", result.stdout + result.stderr)


class TestCrossConsumerEvalRefusesEmptySuccess(unittest.TestCase):
    """The honesty guards must be able to FIRE, not merely exist.

    An independent audit found that on a default full run `ran >= 1` always,
    because shared-work is this repo's own fixture and has no checkout to be
    missing. So the ran==0 refusal was unreachable on the path used by the
    local/manual expensive tier, and a run with both consumer checkouts absent
    would have reported success having verified only a self-described moderate
    proxy.

    Both guards are exercised here through the tool's real surface: positional
    target selection and VPS_CHECKOUT.
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
            VPS_CHECKOUT=self.nowhere,
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
        about vps.
        """
        r = self.run_tool(VPS_CHECKOUT=self.nowhere)
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
            vps.mkdir()
            (vps / "flake.lock").write_text(lock)

            r = self.run_tool(VPS_CHECKOUT=str(vps))

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



class TestImmutableSubflakeCheck(unittest.TestCase):
    """The immutable proof must use committed bytes and a pinned tarball."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gates-immutable-subflake-")
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        (self.repo / "test" / "bin").mkdir(parents=True)
        (self.repo / "config" / "fleet").mkdir(parents=True)
        (self.repo / "config" / "ai").mkdir(parents=True)
        shutil.copy2(IMMUTABLE_SUBFLAKE_CHECK, self.repo / "test" / "bin")

        self.committed_lock = {
            "nodes": {"root": {"inputs": {}}},
            "root": "root",
            "version": 7,
        }
        self.committed_lock_bytes = (
            json.dumps(self.committed_lock, separators=(",", ":")) + "\n"
        )
        self.committed_up_import = "# committed up-import authority\n"
        (self.repo / "config" / "fleet" / "flake.lock").write_text(
            self.committed_lock_bytes, encoding="utf-8"
        )
        (self.repo / "config" / "fleet" / "flake.nix").write_text(
            "{ outputs = _: {}; }\n", encoding="utf-8"
        )
        (self.repo / "config" / "ai" / "flake.nix").write_text(
            'throw "config/fleet #47"\n', encoding="utf-8"
        )
        (self.repo / "flake-ai.nix").write_text(
            self.committed_up_import, encoding="utf-8"
        )
        git("init", "-q", ".", cwd=self.repo)
        git("config", "user.email", "test@example.invalid", cwd=self.repo)
        git("config", "user.name", "Test", cwd=self.repo)
        git("config", "commit.gpgsign", "false", cwd=self.repo)
        git("add", ".", cwd=self.repo)
        git("commit", "-qm", "fixture", cwd=self.repo)
        self.revision = git("rev-parse", "HEAD", cwd=self.repo).stdout.strip()

        # Deliberately disagree with the selected commit.  The gate may inspect
        # the working lock only for byte stability; archive and lock semantics
        # must both come from the requested revision.
        self.worktree_lock = self.repo / "config" / "fleet" / "flake.lock"
        self.worktree_lock_bytes = b'{"dirty-working-tree":true}\n'
        self.worktree_lock.write_bytes(self.worktree_lock_bytes)

        self.fakebin = self.root / "fakebin"
        self.fakebin.mkdir()
        self.log = self.root / "nix-calls.jsonl"
        self.metadata_lock = self.root / "metadata-lock.json"
        self.metadata_lock.write_text(
            json.dumps(self.committed_lock, indent=4) + "\n", encoding="utf-8"
        )
        self.expected_archive_lock = self.root / "expected-archive-lock"
        self.expected_archive_lock.write_text(
            self.committed_lock_bytes, encoding="utf-8"
        )
        self.expected_up_import = self.root / "expected-up-import"
        self.expected_up_import.write_text(self.committed_up_import, encoding="utf-8")
        self.scratch = self.root / "scratch"
        self.scratch.mkdir()
        self._write_fake_nix()

    def tearDown(self):
        self.temp.cleanup()

    def _write_fake_nix(self):
        fake = self.fakebin / "nix"
        fake.write_text(
            r"""#!/usr/bin/env python3
import json
import os
import sys
import tarfile
from pathlib import Path
from urllib.parse import unquote, urlparse

args = sys.argv[1:]
log_path = Path(os.environ["FAKE_NIX_LOG"])


def record(row):
    with log_path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(row, sort_keys=True) + "\n")


row = {"args": args}
if args[:2] == ["flake", "prefetch"]:
    reference = args[-1]
    if not reference.startswith("tarball+file://"):
        record(row)
        raise SystemExit(90)
    archive_path = Path(unquote(urlparse(reference[len("tarball+"):]).path))
    row["archivePath"] = str(archive_path)
    with tarfile.open(archive_path) as archive:
        row["archiveLock"] = archive.extractfile(
            "config/fleet/flake.lock"
        ).read().decode()
        row["archiveUpImport"] = archive.extractfile("flake-ai.nix").read().decode()
    record(row)
    if row["archiveLock"] != Path(
        os.environ["FAKE_EXPECTED_ARCHIVE_LOCK"]
    ).read_text():
        raise SystemExit(91)
    if row["archiveUpImport"] != Path(
        os.environ["FAKE_EXPECTED_UP_IMPORT"]
    ).read_text():
        raise SystemExit(92)
    print(json.dumps({"hash": "sha256-/+fixture=", "storePath": "/nix/store/fake"}))
elif args[:2] == ["flake", "show"]:
    reference = args[-1]
    record(row)
    print(
        os.environ.get(
            "FAKE_STUB_MESSAGE",
            "config/ai was renamed to config/fleet by #47",
        ),
        file=sys.stderr,
    )
    raise SystemExit(int(os.environ.get("FAKE_STUB_STATUS", "1")))
elif args[:2] == ["flake", "metadata"]:
    locked = {
        "type": os.environ.get("FAKE_METADATA_TYPE", "tarball"),
        "dir": os.environ.get("FAKE_METADATA_DIR", "config/fleet"),
        "narHash": os.environ.get("FAKE_METADATA_HASH", "sha256-/+fixture="),
        "url": "file:///the/archive.tar",
    }
    metadata = {
        "locked": locked,
        "locks": json.loads(Path(os.environ["FAKE_METADATA_LOCK"]).read_text()),
    }
    record(row)
    if os.environ.get("FAKE_MUTATE_ON") == "metadata":
        Path(os.environ["FAKE_WORKTREE_LOCK"]).write_text("rewritten by metadata\n")
    print(json.dumps(metadata))
elif args[:2] == ["flake", "check"]:
    record(row)
    if os.environ.get("FAKE_MUTATE_ON") == "check":
        Path(os.environ["FAKE_WORKTREE_LOCK"]).write_text("rewritten by check\n")
    raise SystemExit(int(os.environ.get("FAKE_CHECK_STATUS", "0")))
else:
    record(row)
    raise SystemExit(93)
""",
            encoding="utf-8",
        )
        fake.chmod(0o755)

    def run_gate(self, *, include_revision=True, **overrides):
        if self.log.exists():
            self.log.unlink()
        env = clean_env(
            PATH=f"{self.fakebin}{os.pathsep}{os.environ['PATH']}",
            TMPDIR=str(self.scratch),
            FAKE_NIX_LOG=str(self.log),
            FAKE_METADATA_LOCK=str(self.metadata_lock),
            FAKE_EXPECTED_ARCHIVE_LOCK=str(self.expected_archive_lock),
            FAKE_EXPECTED_UP_IMPORT=str(self.expected_up_import),
            FAKE_WORKTREE_LOCK=str(self.worktree_lock),
        )
        env.update(overrides)
        argv = [str(self.repo / "test" / "bin" / "immutable-subflake-check")]
        if include_revision:
            argv.append(self.revision)
        return subprocess.run(
            argv,
            cwd=self.root,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def calls(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_exact_revision_uses_url_pinned_tarball_and_preserves_worktree_lock(self):
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.worktree_lock.read_bytes(), self.worktree_lock_bytes)

        calls = self.calls()
        self.assertEqual(len(calls), 4, calls)
        prefetch, metadata, check, stale = calls
        self.assertEqual(prefetch["args"][:3], ["flake", "prefetch", "--json"])
        self.assertEqual(prefetch["archiveLock"], self.committed_lock_bytes)
        self.assertEqual(prefetch["archiveUpImport"], self.committed_up_import)
        self.assertFalse(Path(prefetch["archivePath"]).exists())

        immutable_ref = metadata["args"][-1]
        self.assertTrue(immutable_ref.startswith("tarball+file://"), immutable_ref)
        self.assertIn(
            "?dir=config/fleet&narHash=sha256-%2F%2Bfixture%3D", immutable_ref
        )
        self.assertNotIn("git+file", immutable_ref)
        self.assertEqual(
            metadata["args"],
            ["flake", "metadata", "--json", "--no-write-lock-file", immutable_ref],
        )
        self.assertEqual(
            check["args"],
            [
                "flake",
                "check",
                immutable_ref,
                "--all-systems",
                "--no-build",
                "--no-write-lock-file",
            ],
        )
        self.assertIn("?dir=config/ai&narHash=", stale["args"][-1])
        self.assertEqual(stale["args"][:2], ["flake", "show"])
        self.assertEqual(list(self.scratch.iterdir()), [])

    def test_default_revision_is_head(self):
        result = self.run_gate(include_revision=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(self.revision[:12], result.stdout)
        self.assertEqual(self.worktree_lock.read_bytes(), self.worktree_lock_bytes)

    def test_stale_stub_failure_must_name_target_and_issue(self):
        for message in ("renamed by #47", "renamed to config/fleet"):
            with self.subTest(message=message):
                result = self.run_gate(FAKE_STUB_MESSAGE=message)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    "does not name config/fleet and #47",
                    result.stdout + result.stderr,
                )
                self.assertEqual(len(self.calls()), 4)

    def test_stale_stub_unexpected_success_is_rejected(self):
        result = self.run_gate(FAKE_STUB_STATUS="0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "stale config/ai reference unexpectedly resolved",
            result.stdout + result.stderr,
        )
        self.assertEqual(len(self.calls()), 4)

    def test_metadata_requires_tarball_dir_and_prefetched_nar_hash(self):
        cases = (
            ({"FAKE_METADATA_TYPE": "git"}, "locked.type is not tarball"),
            ({"FAKE_METADATA_DIR": "config/ai"}, "locked.dir is not config/fleet"),
            ({"FAKE_METADATA_HASH": "sha256-other="}, "locked.narHash differs"),
        )
        for override, diagnostic in cases:
            with self.subTest(override=override):
                result = self.run_gate(**override)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(diagnostic, result.stdout + result.stderr)
                self.assertEqual(len(self.calls()), 2)
                self.assertEqual(
                    self.worktree_lock.read_bytes(), self.worktree_lock_bytes
                )

    def test_metadata_lock_graph_must_equal_selected_revision_semantically(self):
        drift = self.root / "drift-lock.json"
        drift.write_text('{"version":8,"root":"root","nodes":{}}\n')
        result = self.run_gate(FAKE_METADATA_LOCK=str(drift))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("metadata locks differ", result.stdout + result.stderr)
        self.assertEqual(len(self.calls()), 2)

    def test_any_nix_lock_rewrite_fails_and_cleanup_remains_exact(self):
        for phase in ("metadata", "check"):
            with self.subTest(phase=phase):
                self.worktree_lock.write_bytes(self.worktree_lock_bytes)
                result = self.run_gate(FAKE_MUTATE_ON=phase)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    "working-tree config/fleet/flake.lock changed",
                    result.stdout + result.stderr,
                )
                expected_calls = 2 if phase == "metadata" else 3
                self.assertEqual(len(self.calls()), expected_calls)
                self.assertEqual(list(self.scratch.iterdir()), [])


class TestGatesAreRegistered(unittest.TestCase):
    """A gate nothing invokes is not a gate."""

    def test_test_sources_live_under_the_singular_test_root(self):
        tracked = subprocess.run(
            ["git", "ls-files"],
            cwd=REPO,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.splitlines()
        test_sources = [
            path
            for path in tracked
            if path.endswith("-test.py")
            or ".test." in Path(path).name
            or path == "test/bin/unittest-strict.py"
        ]
        self.assertTrue(test_sources)
        self.assertEqual(
            [path for path in test_sources if not path.startswith("test/")],
            [],
        )
        self.assertEqual([path for path in tracked if path.startswith("tests/")], [])

    def test_every_gate_script_is_executable(self):
        for tool in (
            VERIFY_SIGNATURES,
            CROSS_CONSUMER_EVAL,
            CONSUMER_INVENTORY,
            DARWIN_SURFACE_DIFF,
            DARWIN_SURFACE_BASELINE,
            IMMUTABLE_SUBFLAKE_CHECK,
        ):
            self.assertTrue(os.access(tool, os.X_OK), "%s is not executable" % tool)

    def test_consumer_inventory_has_no_repository_writer(self):
        result = subprocess.run(
            [str(CONSUMER_INVENTORY), "--write"],
            cwd=REPO,
            capture_output=True,
            text=True,
            check=False,
            env=clean_env(),
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown argument", result.stdout + result.stderr)

    def test_python_tiers_are_wired_without_a_second_quality_authority(self):
        hook = (REPO / "lefthook.yml").read_text()
        self.assertRegex(
            hook,
            r"(?m)^      run: test/bin/quality --tier pre-commit$",
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

    def test_darwin_surface_gate_is_wired_to_local_expensive_entrypoints(self):
        self.assertNotIn("darwin-surface", (REPO / "lefthook.yml").read_text())
        self.assertRegex(
            (REPO / "Makefile").read_text(),
            r"(?m)^test:\n"
            r"\ttest/bin/quality --python-tier full python-test darwin-surface$",
        )

    def test_darwin_surface_is_not_wired_to_remote_ci_until_root_is_portable(self):
        ci = (REPO / ".github/workflows/ci.yml").read_text()
        self.assertNotRegex(ci, r"(?m)^\s+run: test/bin/quality darwin-surface$")
        self.assertIn("LAN-only ssh://gitea stock-trader input", ci)

    def test_make_build_and_switch_propagate_darwin_rebuild_failure(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            sudo = fake_bin / "sudo"
            sudo.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >>"$SUDO_LOG"\nexit 73\n')
            sudo.chmod(0o755)
            sudo_log = root / "sudo.log"

            fixture = root / "Makefile"
            fixture.write_text(
                f"include {REPO / 'Makefile'}\nverify-inputs: ;\nlock-local: ;\n"
            )
            env = clean_env(
                PATH=f"{fake_bin}:{os.environ['PATH']}",
                SUDO_LOG=str(sudo_log),
            )

            result_file = root / "result"
            result_file.touch()
            build = subprocess.run(
                [
                    "make",
                    "--no-print-directory",
                    "-f",
                    str(fixture),
                    "build",
                    "HOSTNAME=hera",
                ],
                cwd=root,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(build.returncode, 0, build.stdout + build.stderr)
            self.assertTrue(result_file.exists(), "cleanup ran after failed build")

            sudo_log.write_text("")
            switch = subprocess.run(
                [
                    "make",
                    "--no-print-directory",
                    "-f",
                    str(fixture),
                    "switch",
                    "HOSTNAME=hera",
                ],
                cwd=root,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(switch.returncode, 0, switch.stdout + switch.stderr)
            sudo_calls = sudo_log.read_text().splitlines()
            self.assertEqual(len(sudo_calls), 1, sudo_calls)
            self.assertNotIn("--list-generations", sudo_calls[0])

    def test_make_lock_local_propagates_update_failure(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            nix = fake_bin / "nix"
            nix.write_text(
                "#!/bin/sh\n"
                'printf "warning: filtered warning\\n"\n'
                'if [ "${NIX_FAIL:-0}" = 1 ]; then\n'
                '  printf "lock update failed\\n" >&2\n'
                "  exit 73\n"
                "fi\n"
            )
            nix.chmod(0o755)
            sudo = fake_bin / "sudo"
            sudo.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >>"$SUDO_LOG"\n')
            sudo.chmod(0o755)
            sudo_log = root / "sudo.log"

            (root / "flake.lock").write_text(
                json.dumps(
                    {
                        "nodes": {
                            "root": {"inputs": {"local": "local-node"}},
                            "local-node": {
                                "locked": {"type": "git", "url": "file:///tmp/local"}
                            },
                        }
                    }
                )
            )
            fixture = root / "Makefile"
            fixture.write_text(f"include {REPO / 'Makefile'}\nverify-inputs: ;\n")
            env = clean_env(
                PATH=f"{fake_bin}:{os.environ['PATH']}",
                SUDO_LOG=str(sudo_log),
            )

            success = subprocess.run(
                ["make", "--no-print-directory", "-f", str(fixture), "lock-local"],
                cwd=root,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(success.returncode, 0, success.stdout + success.stderr)
            self.assertNotIn("filtered warning", success.stdout + success.stderr)

            failing_env = {**env, "NIX_FAIL": "1"}
            failure = subprocess.run(
                ["make", "--no-print-directory", "-f", str(fixture), "lock-local"],
                cwd=root,
                env=failing_env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(failure.returncode, 0, failure.stdout + failure.stderr)
            self.assertIn("lock update failed", failure.stderr)

            (root / "flake.lock").write_text("{")
            parse_failure = subprocess.run(
                ["make", "--no-print-directory", "-f", str(fixture), "lock-local"],
                cwd=root,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(
                parse_failure.returncode,
                0,
                parse_failure.stdout + parse_failure.stderr,
            )

            (root / "flake.lock").write_text(
                json.dumps(
                    {
                        "nodes": {
                            "root": {"inputs": {"local": "local-node"}},
                            "local-node": {
                                "locked": {"type": "git", "url": "file:///tmp/local"}
                            },
                        }
                    }
                )
            )

            switch = subprocess.run(
                [
                    "make",
                    "--no-print-directory",
                    "-f",
                    str(fixture),
                    "switch",
                    "HOSTNAME=hera",
                ],
                cwd=root,
                env=failing_env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(switch.returncode, 0, switch.stdout + switch.stderr)
            self.assertFalse(
                sudo_log.exists(), "switch reached sudo after lock failure"
            )

    def test_precommit_tier_always_runs_python_authorities(self):
        config = (REPO / "lefthook.yml").read_text()
        self.assertRegex(
            config,
            r"(?m)^    quality-tier:\n      run: test/bin/quality --tier pre-commit$",
        )
        self.assertNotRegex(config, r"(?m)^      glob:")
        quality = (BIN / "quality").read_text()
        core = re.search(r"(?ms)^PRE_COMMIT_CORE_SUITES=\(\n(?P<body>.*?)^\)$", quality)
        self.assertIsNotNone(core)
        for suite in ("python-lint", "python-test"):
            self.assertRegex(core.group("body"), rf"(?m)^    {suite}$")
        self.assertNotRegex(core.group("body"), r"(?m)^    portable-eval$")
        expensive = re.search(r"(?ms)^EXPENSIVE_SUITES=\(\n(?P<body>.*?)^\)$", quality)
        self.assertIsNotNone(expensive)
        for suite in (
            "python-test",
            "portable-eval",
            "consumer-eval",
            "signatures",
            "darwin-surface",
            "immutable-subflake",
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
        pre_commit = set(core.group("body").split())
        expensive_set = set(expensive.group("body").split())
        self.assertEqual(pre_commit | expensive_set, registered)
        self.assertEqual(pre_commit & expensive_set, {"python-test"})

    def test_signature_ci_uses_the_real_event_range_and_public_key_only(self):
        workflow = (REPO / ".github/workflows/ci.yml").read_text()
        self.assertRegex(workflow, r"(?m)^  signatures:\n")
        self.assertRegex(
            workflow,
            r"(?m)^          fetch-depth: 0\n"
            r"(?:^          #.*\n)*"
            r"^          ref: \$\{\{ github\.event\.pull_request\.base\.sha \|\| github\.sha \}\}$",
        )
        self.assertIn(
            'run: git fetch --no-tags origin "pull/${{ github.event.pull_request.number }}/head"',
            workflow,
        )
        self.assertNotIn("ref: ${{ github.event.pull_request.head.sha", workflow)
        self.assertIn(
            "SIGVERIFY_BASE: ${{ github.event.pull_request.base.sha || github.event.before }}",
            workflow,
        )
        self.assertIn(
            "SIGVERIFY_HEAD: ${{ github.event.pull_request.head.sha || github.sha }}",
            workflow,
        )
        self.assertIn('SIGVERIFY_STRICT: "1"', workflow)
        self.assertIn(
            'run: test/bin/verify-signatures --base "$SIGVERIFY_BASE" --head "$SIGVERIFY_HEAD"',
            workflow,
        )

        public_keys = sorted((REPO / ".github/signing-keys").glob("*"))
        self.assertEqual(len(public_keys), 1)
        key = public_keys[0].read_text()
        self.assertIn("BEGIN PGP PUBLIC KEY BLOCK", key)
        self.assertNotIn("PRIVATE KEY", key)
        shown = subprocess.run(
            ["gpg", "--batch", "--show-keys", "--with-colons", str(public_keys[0])],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.splitlines()
        fingerprints = [line.split(":")[9] for line in shown if line.startswith("fpr:")]
        self.assertEqual(
            fingerprints,
            [
                "4710CF98AF9B327BB80F60E146C4BD1A7AC14BA2",
                "76DBD4ED877F4C2ADC6A46A612D70076AB504679",
            ],
        )
        self.assertEqual(sum(line.startswith("uid:") for line in shown), 1)
        subkeys = [line.split(":") for line in shown if line.startswith("sub:")]
        self.assertEqual(len(subkeys), 1)
        self.assertEqual(subkeys[0][11], "s")
        packets = subprocess.run(
            ["gpg", "--batch", "--list-packets", str(public_keys[0])],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        self.assertNotRegex(packets, r"(?m)^:secret (?:key|sub key) packet:")

    def test_expensive_assurance_is_low_frequency_and_manual(self):
        workflow = (REPO / ".github/workflows/portable-assurance.yml").read_text()
        self.assertIn('cron: "17 2,14 * * *"', workflow)
        self.assertIn("workflow_dispatch:", workflow)
        self.assertNotRegex(workflow, r"(?m)^  (push|pull_request):")
        self.assertRegex(workflow, r"(?m)^        run: test/bin/quality portable-eval$")
        self.assertNotRegex(workflow, r"(?m)^\s+run: test/bin/quality --tier expensive$")
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
        self.assertRegex(makefile, r"(?m)^expensive:\n\ttest/bin/quality --tier expensive$")

    def test_no_gate_contains_common_credential_markers(self):
        for tool in (
            VERIFY_SIGNATURES,
            CROSS_CONSUMER_EVAL,
            CONSUMER_INVENTORY,
            DARWIN_SURFACE_DIFF,
            DARWIN_SURFACE_BASELINE,
            IMMUTABLE_SUBFLAKE_CHECK,
        ):
            body = tool.read_text()
            for pattern in ("ghp_", "github_pat_", "PRIVATE KEY", "password="):
                self.assertNotIn(
                    pattern, body, "%s appears to embed a credential" % tool.name
                )



if __name__ == "__main__":
    unittest.main()
