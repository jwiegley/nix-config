#!/usr/bin/env python3
"""Replayable regression tests for the fleet programme's shell gates.

Tests use throwaway fixtures; the real checkout is read or executed but never
mutated.

Run: python3 -m unittest -v test/bin/gates-slow-test.py
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

# The real checkout supplies gate definitions, commands, and a genuine
# signature blob. Tests read or execute it but never mutate it.
REPO = Path(__file__).resolve().parents[2]
BIN = REPO / "test" / "bin"
VERIFY_SIGNATURES = BIN / "verify-signatures"
CROSS_CONSUMER_EVAL = BIN / "cross-consumer-eval"
IMMUTABLE_SUBFLAKE_CHECK = BIN / "immutable-subflake-check"

# Repository/config selectors scrubbed from Git subprocess environments.
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
    """Verify that only G, U, and Y signature states pass."""

    def setUp(self):
        # Keep GnuPG agent sockets under a short temporary path.
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
        """An unverifiable or bad transplanted signature must reject."""
        base = self._commit("a", "base")
        # Fabricate a commit carrying a gpgsig header that an empty keyring cannot verify.
        head = self._commit("b", "second")
        raw = git("cat-file", "commit", head, cwd=self.repo).stdout
        lines = raw.split("\n")
        insert_at = next(
            i for i, line in enumerate(lines) if line.startswith("committer")
        )
        # Transplant a real signature blob, then verify the rewritten commit with
        # an empty keyring. Git may report E or B; both must reject.
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
        """Y passes for a valid signature under an expired generated key."""
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
    """Exercise zero-evaluation and proxy-only refusal paths."""

    def setUp(self):
        self.nowhere = os.path.join(tempfile.gettempdir(), "gates-no-such-checkout")
        self.assertFalse(
            os.path.exists(self.nowhere), "fixture path unexpectedly exists"
        )

    def run_tool(self, *args, **env):
        env = {
            "VPS_CHECKOUT": self.nowhere,
            "ANDORIA_CHECKOUT": self.nowhere,
            **env,
        }
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
        """A full run must not pass after evaluating only shared-work."""
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
        self.committed_source_marker = "committed source marker\n"
        (self.repo / "config" / "ai" / "flake.lock").write_text(
            self.committed_lock_bytes, encoding="utf-8"
        )
        (self.repo / "config" / "ai" / "flake.nix").write_text(
            "{ outputs = _: {}; }\n", encoding="utf-8"
        )
        (self.repo / "source-marker").write_text(
            self.committed_source_marker, encoding="utf-8"
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
        self.worktree_lock = self.repo / "config" / "ai" / "flake.lock"
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
        self.expected_source_marker = self.root / "expected-source-marker"
        self.expected_source_marker.write_text(
            self.committed_source_marker, encoding="utf-8"
        )
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
            "config/ai/flake.lock"
        ).read().decode()
        row["archiveSourceMarker"] = archive.extractfile("source-marker").read().decode()
    record(row)
    if row["archiveLock"] != Path(
        os.environ["FAKE_EXPECTED_ARCHIVE_LOCK"]
    ).read_text():
        raise SystemExit(91)
    if row["archiveSourceMarker"] != Path(
        os.environ["FAKE_EXPECTED_SOURCE_MARKER"]
    ).read_text():
        raise SystemExit(92)
    print(json.dumps({"hash": "sha256-/+fixture=", "storePath": "/nix/store/fake"}))
elif args[:2] == ["flake", "metadata"]:
    locked = {
        "type": os.environ.get("FAKE_METADATA_TYPE", "tarball"),
        "dir": os.environ.get("FAKE_METADATA_DIR", "config/ai"),
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
            FAKE_EXPECTED_SOURCE_MARKER=str(self.expected_source_marker),
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
        self.assertEqual(len(calls), 3, calls)
        prefetch, metadata, check = calls
        self.assertEqual(prefetch["args"][:3], ["flake", "prefetch", "--json"])
        self.assertEqual(prefetch["archiveLock"], self.committed_lock_bytes)
        self.assertEqual(
            prefetch["archiveSourceMarker"], self.committed_source_marker
        )
        self.assertFalse(Path(prefetch["archivePath"]).exists())

        immutable_ref = metadata["args"][-1]
        self.assertTrue(immutable_ref.startswith("tarball+file://"), immutable_ref)
        self.assertIn(
            "?dir=config/ai&narHash=sha256-%2F%2Bfixture%3D", immutable_ref
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
        self.assertEqual(list(self.scratch.iterdir()), [])

    def test_default_revision_is_head(self):
        result = self.run_gate(include_revision=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(self.revision[:12], result.stdout)
        self.assertEqual(self.worktree_lock.read_bytes(), self.worktree_lock_bytes)

    def test_metadata_requires_tarball_dir_and_prefetched_nar_hash(self):
        cases = (
            ({"FAKE_METADATA_TYPE": "git"}, "locked.type is not tarball"),
            ({"FAKE_METADATA_DIR": "wrong/subflake"}, "locked.dir is not config/ai"),
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
                    "working-tree config/ai/flake.lock changed",
                    result.stdout + result.stderr,
                )
                expected_calls = 2 if phase == "metadata" else 3
                self.assertEqual(len(self.calls()), expected_calls)
                self.assertEqual(list(self.scratch.iterdir()), [])


class TestMakeVerifyInputs(unittest.TestCase):
    """Exercise local-input safety through the real Make prerequisite."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gates-verify-inputs-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        (self.bin / "lib").mkdir(parents=True)
        shutil.copy2(
            REPO / "bin/lib/local-git-inputs.py",
            self.bin / "lib/local-git-inputs.py",
        )
        self.makefile = self.root / "Makefile"
        self.makefile.write_text(f"include {REPO / 'Makefile'}\n")
        self.git_log = self.root / "git.log"
        self.nix_log = self.root / "nix.jsonl"
        self.real_git = shutil.which("git")
        self.real_nix = shutil.which("nix")
        self.assertIsNotNone(self.real_git)
        self.assertIsNotNone(self.real_nix)

        fake_git = self.bin / "git"
        fake_git.write_text(
            "#!/bin/sh\n"
            'case "$*" in\n'
            "  *' ls-files -v') probe=ls-files-v ;;\n"
            "  *' submodule status --recursive') probe=submodule-status ;;\n"
            "  *' ls-files --stage') probe=ls-files-stage ;;\n"
            "  *) probe=other ;;\n"
            "esac\n"
            'printf "%s\\n" "$probe" >>"$GIT_LOG"\n'
            'if [ "$FAKE_GIT_FAIL" = "$probe" ]; then\n'
            '  printf "stub failing %s\\n" "$probe" >&2\n'
            "  exit 73\n"
            "fi\n"
            'exec "$REAL_GIT" "$@"\n'
        )
        fake_git.chmod(0o755)
        nix = self.bin / "nix"
        nix.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "with open(os.environ['NIX_LOG'], 'a', encoding='utf-8') as stream:\n"
            "    stream.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            "if os.environ.get('NIX_FAIL'):\n"
            "    print('lock update failed', file=sys.stderr)\n"
            "    raise SystemExit(73)\n"
        )
        nix.chmod(0o755)

    def init_repo(self, name):
        repo = self.root / name
        repo.mkdir()
        git("init", "-q", ".", cwd=repo)
        git("config", "user.email", "test@example.invalid", cwd=repo)
        git("config", "user.name", "Test", cwd=repo)
        git("config", "commit.gpgsign", "false", cwd=repo)
        (repo / "tracked").write_text("tracked\n")
        git("add", "tracked", cwd=repo)
        git("commit", "-qm", "fixture", cwd=repo)
        return repo

    @staticmethod
    def lock(url, *, name="local", ref="local-node", submodules=None):
        locked = {
            "lastModified": 1767225600,
            "narHash": "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            "rev": "0123456789abcdef0123456789abcdef01234567",
            "revCount": 1,
            "type": "git",
            "url": url,
        }
        original = {"type": "git", "url": url}
        if submodules is not None:
            locked["submodules"] = submodules
            original["submodules"] = submodules
        return {
            "version": 7,
            "root": "root",
            "nodes": {
                "root": {"inputs": {name: ref}},
                ref: {
                    "locked": locked,
                    "original": original,
                },
            },
        }

    def write_lock(self, lock):
        if isinstance(lock, str):
            (self.root / "flake.lock").write_text(lock)
        else:
            (self.root / "flake.lock").write_text(json.dumps(lock))

    def run_make(self, target="lock-local", **extra_env):
        for log in (self.git_log, self.nix_log):
            log.unlink(missing_ok=True)
        env = clean_env(
            PATH=f"{self.bin}:{os.environ['PATH']}",
            REAL_GIT=self.real_git,
            GIT_LOG=str(self.git_log),
            NIX_LOG=str(self.nix_log),
            FAKE_GIT_FAIL="",
        )
        env.update(extra_env)
        return subprocess.run(
            [
                "make",
                "--no-print-directory",
                "-f",
                str(self.makefile),
                target,
                "SYSTEM=fixture-system",
            ],
            cwd=self.root,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def git_calls(self):
        if not self.git_log.exists():
            return []
        return self.git_log.read_text().splitlines()

    def nix_calls(self):
        if not self.nix_log.exists():
            return []
        return [json.loads(line) for line in self.nix_log.read_text().splitlines()]

    def test_nix_generated_local_git_lock_is_accepted(self):
        repo = self.init_repo("nix generated repo")
        (self.root / "flake.nix").write_text(
            "{\n"
            f"  inputs.local = {{ url = {json.dumps('git+' + repo.as_uri())}; "
            "flake = false; };\n"
            "  outputs = _: {};\n"
            "}\n"
        )
        generated = subprocess.run(
            [
                self.real_nix,
                "--extra-experimental-features",
                "nix-command flakes",
                "flake",
                "lock",
            ],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(generated.returncode, 0, generated.stdout + generated.stderr)
        lock = json.loads((self.root / "flake.lock").read_text())
        node_ref = lock["nodes"][lock["root"]]["inputs"]["local"]
        self.assertIsInstance(lock["nodes"][node_ref]["original"], dict)

        result = self.run_make()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.nix_calls(), [["flake", "update", "local"]])

    def test_real_lock_local_updates_followed_target_revision(self):
        target = self.init_repo("real target repo")
        bridge = self.root / "bridge"
        bridge.mkdir()
        (bridge / "flake.nix").write_text(
            "{\n"
            f"  inputs.source = {{ url = {json.dumps('git+' + target.as_uri())}; "
            "flake = false; };\n"
            "  outputs = _: {};\n"
            "}\n"
        )
        (self.root / "flake.nix").write_text(
            "{\n"
            f"  inputs.bridge.url = {json.dumps(f'path:{bridge}')};\n"
            '  inputs.local.follows = "bridge/source";\n'
            "  outputs = _: {};\n"
            "}\n"
        )
        generated = subprocess.run(
            [
                self.real_nix,
                "--extra-experimental-features",
                "nix-command flakes",
                "flake",
                "lock",
            ],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(generated.returncode, 0, generated.stdout + generated.stderr)

        def target_revision():
            lock = json.loads((self.root / "flake.lock").read_text())
            root = lock["nodes"][lock["root"]]
            self.assertEqual(root["inputs"]["local"], ["bridge", "source"])
            bridge_ref = root["inputs"]["bridge"]
            source_ref = lock["nodes"][bridge_ref]["inputs"]["source"]
            return lock["nodes"][source_ref]["locked"]["rev"]

        initial_revision = git("rev-parse", "HEAD", cwd=target).stdout.strip()
        self.assertEqual(target_revision(), initial_revision)
        (target / "tracked").write_text("changed\n")
        git("add", "tracked", cwd=target)
        git("commit", "-qm", "changed target", cwd=target)
        changed_revision = git("rev-parse", "HEAD", cwd=target).stdout.strip()

        result = subprocess.run(
            [
                "make",
                "--no-print-directory",
                "-f",
                str(self.makefile),
                "lock-local",
                "SYSTEM=fixture-system",
            ],
            cwd=self.root,
            env=clean_env(
                PATH=os.environ["PATH"],
                NIX_CONFIG=(
                    os.environ.get("NIX_CONFIG", "")
                    + "\nexperimental-features = nix-command flakes\n"
                ),
            ),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(target_revision(), changed_revision)

    def test_absent_root_inputs_is_an_empty_inventory(self):
        self.write_lock({"version": 7, "root": "root", "nodes": {"root": {}}})

        result = self.run_make()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.git_calls(), [])
        self.assertEqual(self.nix_calls(), [])

    def test_empty_follows_path_to_root_is_skipped(self):
        self.write_lock(
            {
                "version": 7,
                "root": "root",
                "nodes": {"root": {"inputs": {"self": []}}},
            }
        )

        result = self.run_make()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.git_calls(), [])
        self.assertEqual(self.nix_calls(), [])

    def test_root_anchored_follows_path_resolves_local_input(self):
        repo = self.init_repo("followed repo")
        lock = self.lock(repo.as_uri())
        lock["nodes"]["root"]["inputs"] = {
            "bridge": "bridge-node",
            "local": ["bridge", "source"],
        }
        lock["nodes"]["bridge-node"] = {
            "inputs": {"source": "local-node"},
            "locked": {
                "narHash": "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
                "type": "github",
            },
            "original": {"owner": "example", "repo": "bridge", "type": "github"},
        }
        self.write_lock(lock)

        result = self.run_make()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            self.git_calls(),
            ["ls-files-v", "submodule-status", "ls-files-stage"],
        )
        self.assertEqual(self.nix_calls(), [["flake", "update", "bridge/source"]])

    def test_malformed_lock_shapes_and_unsafe_text_fail_before_commands(self):
        repo = self.init_repo("valid repo")
        valid = self.lock(repo.as_uri())

        missing_node = self.lock(repo.as_uri())
        missing_node["nodes"].pop("local-node")
        nonobject_node = self.lock(repo.as_uri())
        nonobject_node["nodes"]["local-node"] = []
        nonobject_inputs = self.lock(repo.as_uri())
        nonobject_inputs["nodes"]["root"]["inputs"] = []
        missing_locked = self.lock(repo.as_uri())
        missing_locked["nodes"]["local-node"].pop("locked")
        nonobject_locked = self.lock(repo.as_uri())
        nonobject_locked["nodes"]["local-node"]["locked"] = []
        missing_original = self.lock(repo.as_uri())
        missing_original["nodes"]["local-node"].pop("original")
        nonobject_original = self.lock(repo.as_uri())
        nonobject_original["nodes"]["local-node"]["original"] = []
        missing_url = self.lock(repo.as_uri())
        missing_url["nodes"]["local-node"]["locked"].pop("url")
        nonstring_url = self.lock(repo.as_uri())
        nonstring_url["nodes"]["local-node"]["locked"]["url"] = 42
        nonboolean_submodules = self.lock(repo.as_uri())
        nonboolean_submodules["nodes"]["local-node"]["locked"]["submodules"] = 1
        unsupported_ref = self.lock(repo.as_uri())
        unsupported_ref["nodes"]["root"]["inputs"]["local"] = 42
        bad_follows_step = self.lock(repo.as_uri())
        bad_follows_step["nodes"]["root"]["inputs"]["local"] = [42]
        missing_follows_step = self.lock(repo.as_uri())
        missing_follows_step["nodes"]["root"]["inputs"]["local"] = ["missing"]
        follows_cycle = self.lock(repo.as_uri())
        follows_cycle["nodes"]["root"]["inputs"]["local"] = ["local"]

        cases = (
            ("invalid JSON", "{"),
            ("missing version", {"root": "root", "nodes": valid["nodes"]}),
            ("unsupported version", {**valid, "version": 8}),
            ("non-integer version", {**valid, "version": 7.0}),
            ("missing nodes", {"version": 7, "root": "root"}),
            ("non-object nodes", {"version": 7, "root": "root", "nodes": []}),
            ("unsupported root ref", {**valid, "root": ["root"]}),
            (
                "non-object root node",
                {**valid, "nodes": {**valid["nodes"], "root": []}},
            ),
            ("unsupported input ref", unsupported_ref),
            ("non-object inputs", nonobject_inputs),
            ("non-string follows step", bad_follows_step),
            ("missing follows step", missing_follows_step),
            ("follows cycle", follows_cycle),
            ("missing referenced node", missing_node),
            ("non-object referenced node", nonobject_node),
            ("missing locked node", missing_locked),
            ("non-object locked node", nonobject_locked),
            ("missing original node", missing_original),
            ("non-object original node", nonobject_original),
            ("missing git URL", missing_url),
            ("non-string git URL", nonstring_url),
            ("non-boolean submodules", nonboolean_submodules),
            ("control in name", self.lock(repo.as_uri(), name="bad\nname")),
            ("format control in name", self.lock(repo.as_uri(), name="bad\u202ename")),
            ("option-like name", self.lock(repo.as_uri(), name="--override")),
            ("relative path", self.lock("file:relative/repo")),
            ("encoded control", self.lock(repo.as_uri() + "%0Aescape")),
            ("encoded C1 control", self.lock(repo.as_uri() + "%C2%9Bescape")),
            ("invalid escaping", self.lock(repo.as_uri() + "%ZZ")),
        )
        for label, lock in cases:
            with self.subTest(label=label):
                self.write_lock(lock)
                result = self.run_make()
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.git_calls(), [], result.stdout + result.stderr)
                self.assertEqual(self.nix_calls(), [], result.stdout + result.stderr)

    def test_partial_producers_and_invalid_inventory_fail_before_commands(self):
        repo = self.init_repo("producer repo")
        helper = self.bin / "lib/local-git-inputs.py"
        scripts = (
            (
                "partial repos",
                f"import sys\nprint('0\\t{repo}')\nraise SystemExit(73)\n",
            ),
            (
                "partial names",
                "import sys\n"
                "if sys.argv[1] == 'repos': raise SystemExit(0)\n"
                "print('local')\n"
                "raise SystemExit(73)\n",
            ),
            (
                "NUL in inventory",
                "import sys\n"
                f"sys.stdout.buffer.write(('0\\t' + {str(repo)!r} + "
                "'\\0trailing\\n').encode())\n",
            ),
            (
                "missing final delimiter",
                f"import sys\nsys.stdout.write('0\\t' + {str(repo)!r})\n",
            ),
            (
                "invalid inventory",
                "import sys\n"
                "if sys.argv[1] == 'repos':\n"
                f"    print('0\\t{repo}')\n"
                "    print('2\\t/not/valid')\n"
                "else:\n"
                "    print('local')\n",
            ),
        )
        self.write_lock(self.lock(repo.as_uri()))
        for label, script in scripts:
            with self.subTest(label=label):
                helper.write_text(script)
                result = self.run_make()
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.git_calls(), [], result.stdout + result.stderr)
                self.assertEqual(self.nix_calls(), [], result.stdout + result.stderr)

    def test_skip_worktree_and_assume_unchanged_block_nix(self):
        repo = self.init_repo("flags repo")
        for name in ("skip-worktree", "assume-unchanged"):
            (repo / name).write_text(name + "\n")
        git("add", "skip-worktree", "assume-unchanged", cwd=repo)
        git("commit", "-qm", "indexed files", cwd=repo)
        git("update-index", "--skip-worktree", "skip-worktree", cwd=repo)
        git("update-index", "--assume-unchanged", "assume-unchanged", cwd=repo)
        self.write_lock(self.lock("git+" + repo.as_uri()))

        result = self.run_make()
        combined = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0, combined)
        self.assertIn("skip-worktree", combined)
        self.assertIn("assume-unchanged", combined)
        self.assertEqual(self.nix_calls(), [], combined)

    def test_gitlink_contract_and_nested_uninitialized_submodule(self):
        grandchild = self.init_repo("grandchild repo")
        child = self.init_repo("child repo")
        git(
            "-c",
            "protocol.file.allow=always",
            "submodule",
            "add",
            "-q",
            str(grandchild),
            "grandchild",
            cwd=child,
        )
        git("commit", "-qam", "add grandchild", cwd=child)
        parent = self.init_repo("parent repo")
        git(
            "-c",
            "protocol.file.allow=always",
            "submodule",
            "add",
            "-q",
            str(child),
            "nested",
            cwd=parent,
        )
        git("commit", "-qam", "add submodule", cwd=parent)
        git(
            "-c",
            "protocol.file.allow=always",
            "submodule",
            "update",
            "--init",
            "--recursive",
            cwd=parent,
        )

        self.write_lock(self.lock(parent.as_uri(), submodules=False))
        mismatch = self.run_make()
        self.assertNotEqual(mismatch.returncode, 0, mismatch.stdout + mismatch.stderr)
        self.assertIn("lock omits submodules=true", mismatch.stdout + mismatch.stderr)
        self.assertEqual(self.nix_calls(), [])

        self.write_lock(self.lock(parent.as_uri(), submodules=True))
        initialized = self.run_make()
        self.assertEqual(
            initialized.returncode, 0, initialized.stdout + initialized.stderr
        )
        self.assertEqual(self.nix_calls(), [["flake", "update", "local"]])

        git("submodule", "deinit", "-q", "-f", "grandchild", cwd=parent / "nested")
        uninitialized = self.run_make()
        self.assertNotEqual(
            uninitialized.returncode,
            0,
            uninitialized.stdout + uninitialized.stderr,
        )
        self.assertIn("uninitialized submodules", uninitialized.stdout)
        self.assertIn("nested/grandchild", uninitialized.stdout)
        self.assertIn("--init --recursive", uninitialized.stdout)
        self.assertEqual(self.nix_calls(), [])

    def test_each_git_probe_failure_blocks_nix(self):
        repo = self.init_repo("probe repo")
        self.write_lock(self.lock(repo.as_uri()))
        for probe, diagnostic in (
            ("ls-files-v", "git ls-files -v failed"),
            ("submodule-status", "git submodule status failed"),
            ("ls-files-stage", "git ls-files --stage failed"),
        ):
            with self.subTest(probe=probe):
                result = self.run_make(FAKE_GIT_FAIL=probe)
                combined = result.stdout + result.stderr
                self.assertNotEqual(result.returncode, 0, combined)
                self.assertIn(f"stub failing {probe}", combined)
                self.assertIn(diagnostic, combined)
                self.assertEqual(self.nix_calls(), [], combined)


class TestMakeCopyBuildInputs(unittest.TestCase):
    """Validate cached build inputs without bypassing project aggregation."""

    HASH_A = "0123456789abcdfghijklmnpqrsvwxyz"
    HASH_B = "zyxwvsrqpnmlkjihgfdcba9876543210"

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gates-copy-inputs-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home with spaces"
        self.home.mkdir()
        self.projects_file = self.root / "project list"
        self.makefile = self.root / "Makefile"
        self.makefile.write_text(f"include {REPO / 'Makefile'}\n")
        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        self.nix_log = self.root / "nix.jsonl"

        direnv = self.fake_bin / "direnv"
        direnv.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, shlex\n"
            "from pathlib import Path\n"
            "item = json.loads(os.environ['DIRENV_FIXTURE'])[Path.cwd().name]\n"
            "if 'partial' in item:\n"
            "    print(item['partial'])\n"
            "    raise SystemExit(item['status'])\n"
            "if item.get('status'):\n"
            "    raise SystemExit(item['status'])\n"
            "if 'dump' in item:\n"
            "    print(item['dump'])\n"
            "else:\n"
            "    print('export buildInputs=' + shlex.quote(item.get('value', '')))\n"
        )
        direnv.chmod(0o755)
        nix = self.fake_bin / "nix"
        nix.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "with open(os.environ['NIX_LOG'], 'a', encoding='utf-8') as stream:\n"
            "    stream.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            "if os.environ.get('NIX_FAIL_ARG') in sys.argv[1:]:\n"
            "    raise SystemExit(73)\n"
        )
        nix.chmod(0o755)

    def run_copy(self, fixture, *, fail_arg=""):
        self.nix_log.unlink(missing_ok=True)
        projects = list(fixture)
        self.projects_file.write_text(
            "\n".join(f"projects/{name}" for name in projects)
        )
        for name in projects:
            project = self.home / "projects" / name
            project.mkdir(parents=True, exist_ok=True)
            (project / ".envrc.cache").touch()
        return subprocess.run(
            [
                "make",
                "--no-print-directory",
                "-f",
                str(self.makefile),
                "copy",
                "REMOTES=fixture-host",
                f"PROJECTS={self.projects_file}",
                "SYSTEM=fixture-system",
            ],
            cwd=self.root,
            env=clean_env(
                HOME=str(self.home),
                PATH=f"{self.fake_bin}:{os.environ['PATH']}",
                DIRENV_FIXTURE=json.dumps(fixture),
                NIX_LOG=str(self.nix_log),
                NIX_FAIL_ARG=fail_arg,
            ),
            capture_output=True,
            text=True,
            check=False,
        )

    def nix_calls(self):
        if not self.nix_log.exists():
            return []
        return [json.loads(line) for line in self.nix_log.read_text().splitlines()]

    def test_exact_store_paths_are_passed_as_distinct_arguments(self):
        paths = [
            f"/nix/store/{self.HASH_A}-alpha",
            f"/nix/store/{self.HASH_B}-beta+dev",
            f"/nix/store/{self.HASH_A}-.hidden",
            f"/nix/store/{self.HASH_B}-..hidden",
            f"/nix/store/{self.HASH_A}-{'n' * 211}",
        ]
        result = self.run_copy({"first project": {"value": " \n".join(paths)}})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.nix_calls()
        self.assertEqual(len(calls), 2, calls)
        self.assertEqual(calls[1], ["copy", "--to", "ssh-ng://fixture-host", *paths])

    def test_empty_build_inputs_do_not_invoke_project_copy(self):
        result = self.run_copy(
            {
                "empty": {"value": ""},
                "whitespace": {"value": " \n\t "},
            }
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.nix_calls()), 1, self.nix_calls())

    def test_malformed_and_hostile_store_paths_are_rejected_before_copy(self):
        valid = f"/nix/store/{self.HASH_A}-alpha"
        marker = self.root / "injected"
        invalid = (
            f"/nix/store/{self.HASH_A[:-1]}-short-hash",
            f"/nix/store/e{self.HASH_A[1:]}-invalid-hash-character",
            f"/nix/store/{self.HASH_A.upper()}-uppercase-hash",
            f"/nix/store/{self.HASH_A}-",
            f"/nix/store/{self.HASH_A}-.",
            f"/nix/store/{self.HASH_A}-..",
            f"/nix/store/{self.HASH_A}-.-suffix",
            f"/nix/store/{self.HASH_A}-..-suffix",
            f"/nix/store/{self.HASH_A}-{'n' * 212}",
            valid + "/bin",
            valid + ";touch",
            "/tmp/not-in-the-store",
            f"{valid} $(touch {marker})",
        )
        for value in invalid:
            with self.subTest(value=value):
                marker.unlink(missing_ok=True)
                result = self.run_copy({"invalid": {"value": value}})
                combined = result.stdout + result.stderr
                self.assertNotEqual(result.returncode, 0, combined)
                self.assertIn("invalid cached build input", combined)
                self.assertFalse(marker.exists(), combined)
                self.assertEqual(len(self.nix_calls()), 1, self.nix_calls())

    def test_direnv_failure_is_captured_and_later_projects_continue(self):
        good = f"/nix/store/{self.HASH_A}-good"
        marker = self.root / "partial-dump-ran"
        result = self.run_copy(
            {
                "bad producer": {"partial": f"touch {marker}", "status": 24},
                "good producer": {"value": good},
            }
        )
        combined = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0, combined)
        self.assertIn("direnv apply_dump failed", combined)
        self.assertIn("bad producer", combined)
        self.assertFalse(marker.exists(), combined)
        self.assertEqual(
            self.nix_calls()[1],
            ["copy", "--to", "ssh-ng://fixture-host", good],
        )

    def test_invalid_env_dump_and_nix_failure_are_aggregated(self):
        first = f"/nix/store/{self.HASH_A}-first"
        second = f"/nix/store/{self.HASH_B}-second"
        invalid_dump = self.run_copy(
            {
                "invalid dump": {"dump": "export buildInputs='"},
                "good dump": {"value": second},
            }
        )
        self.assertNotEqual(
            invalid_dump.returncode,
            0,
            invalid_dump.stdout + invalid_dump.stderr,
        )
        self.assertIn("invalid direnv environment dump", invalid_dump.stderr)
        self.assertEqual(self.nix_calls()[-1][-1], second)

        failed_copy = self.run_copy(
            {
                "failing copy": {"value": first},
                "successful copy": {"value": second},
            },
            fail_arg=first,
        )
        combined = failed_copy.stdout + failed_copy.stderr
        self.assertNotEqual(failed_copy.returncode, 0, combined)
        self.assertIn("nix copy failed", combined)
        self.assertEqual([call[-1] for call in self.nix_calls()[1:]], [first, second])


class TestGatesAreRegistered(unittest.TestCase):
    """Check gate registration and source-layout contracts."""

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
            or ".check." in Path(path).name
            or path == "test/bin/unittest-strict.py"
        ]
        self.assertTrue(test_sources)
        self.assertEqual(
            [path for path in test_sources if not path.startswith("test/")],
            [],
        )
        self.assertEqual([path for path in tracked if path.startswith("tests/")], [])

    def _run_make_project_iterator(
        self, root, *, listed_projects, existing_projects, failing_project=""
    ):
        home = root / "home with spaces"
        caller = root / "caller"
        home.mkdir()
        caller.mkdir()
        for project in existing_projects:
            (home / project).mkdir()

        projects = root / "project list"
        projects.write_text("# ignored\n\n" + "\n".join(listed_projects))
        project_log = root / "project.log"
        fixture = root / "Makefile"
        fixture.write_text(
            f"include {REPO / 'Makefile'}\n"
            ".PHONY: project-loop-probe\n"
            "project-loop-probe: SHELL := bash\n"
            "project-loop-probe:\n"
            "\t@probe_project() { \\\n"
            "\t    local input stdin_state; \\\n"
            "\t    if IFS= read -r input; then \\\n"
            "\t        stdin_state=\"data:$$input\"; \\\n"
            "\t    else \\\n"
            "\t        stdin_state=eof; \\\n"
            "\t    fi; \\\n"
            '\t    printf \'start:%s|arg1:%s|pwd:%s|stdin:%s\\n\' '
            '"$$2" "$$1" "$$PWD" "$$stdin_state" >>"$$PROJECT_LOG"; \\\n'
            "\t    if [[ \"$$2\" == \"$${FAIL_PROJECT:-}\" ]]; then false; fi; \\\n"
            '\t    printf \'done:%s\\n\' "$$2" >>"$$PROJECT_LOG"; \\\n'
            "\t}; \\\n"
            "\t$(call for-each-project,probe_project); \\\n"
            "\tstatus=$$?; \\\n"
            "\texit \"$$status\"\n"
        )
        result = subprocess.run(
            [
                "make",
                "--no-print-directory",
                "-f",
                str(fixture),
                "project-loop-probe",
                f"PROJECTS={projects}",
            ],
            cwd=caller,
            env=clean_env(
                HOME=str(home),
                PROJECT_LOG=str(project_log),
                FAIL_PROJECT=failing_project,
            ),
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            check=False,
        )
        return result, home, project_log.read_text().splitlines()

    def test_make_project_iterator_reports_missing_paths_without_consuming_input(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            result, home, project_log = self._run_make_project_iterator(
                Path(temp_dir),
                listed_projects=("first project", "missing project", "last project"),
                existing_projects=("first project", "last project"),
            )

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(str(home / "missing project"), result.stderr)
            self.assertNotIn("project command failed", result.stderr)
            self.assertEqual(
                project_log,
                [
                    f"start:first project|arg1:{home / 'first project'}|"
                    f"pwd:{home / 'first project'}|stdin:eof",
                    "done:first project",
                    f"start:last project|arg1:{home / 'last project'}|"
                    f"pwd:{home / 'last project'}|stdin:eof",
                    "done:last project",
                ],
            )

    def test_make_project_iterator_aggregates_strict_callback_failures(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            result, home, project_log = self._run_make_project_iterator(
                Path(temp_dir),
                listed_projects=("first project", "failing project", "last project"),
                existing_projects=("first project", "failing project", "last project"),
                failing_project="failing project",
            )

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(str(home / "failing project"), result.stderr)
            self.assertNotIn("project directory not found", result.stderr)
            self.assertEqual(
                project_log,
                [
                    f"start:first project|arg1:{home / 'first project'}|"
                    f"pwd:{home / 'first project'}|stdin:eof",
                    "done:first project",
                    f"start:failing project|arg1:{home / 'failing project'}|"
                    f"pwd:{home / 'failing project'}|stdin:eof",
                    f"start:last project|arg1:{home / 'last project'}|"
                    f"pwd:{home / 'last project'}|stdin:eof",
                    "done:last project",
                ],
            )

    def test_make_changes_visits_every_repo_after_project_and_fixed_failures(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            home = root / "home"
            projects = (
                home / "projects/missing",
                home / "projects/inaccessible",
                home / "projects/first",
                home / "projects/last",
            )
            fixed = tuple(
                home / path
                for path in (
                    ".config/pushme",
                    ".emacs.d",
                    "src/nix",
                    "src/scripts",
                    "doc",
                    "org",
                )
            )
            visited = (*projects[2:], fixed[0], *fixed[2:])
            for repo in (*projects[1:], fixed[0], *fixed[2:]):
                repo.mkdir(parents=True, exist_ok=True)

            project_list = root / "projects"
            project_list.write_text(
                "projects/missing\n"
                "projects/inaccessible\n"
                "projects/first\n"
                "projects/last\n"
            )
            changes_log = root / "changes.log"
            fake_bin = root / "bin"
            fake_bin.mkdir()
            changes = fake_bin / "changes"
            changes.write_text('#!/bin/sh\nprintf "%s\\n" "$PWD" >>"$CHANGES_LOG"\n')
            changes.chmod(0o755)
            bash_env = root / "bash-env"
            bash_env.write_text(
                "cd() {\n"
                '    if [[ "$1" == "$INACCESSIBLE_PROJECT" ]]; then\n'
                "        return 73\n"
                "    fi\n"
                '    builtin cd "$@"\n'
                "}\n"
            )

            fixture = root / "Makefile"
            fixture.write_text(f"include {REPO / 'Makefile'}\n")
            result = subprocess.run(
                [
                    "make",
                    "--no-print-directory",
                    "-f",
                    str(fixture),
                    "changes",
                    f"PROJECTS={project_list}",
                ],
                cwd=root,
                env=clean_env(
                    HOME=str(home),
                    PATH=f"{fake_bin}:{os.defpath}",
                    CHANGES_LOG=str(changes_log),
                    BASH_ENV=str(bash_env),
                    INACCESSIBLE_PROJECT=str(projects[1]),
                ),
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(str(projects[0]), result.stderr)
            self.assertIn(f"project command failed (73): {projects[1]}", result.stderr)
            self.assertIn(str(fixed[1]), result.stderr)
            self.assertEqual(
                changes_log.read_text().splitlines(),
                [str(repo) for repo in visited],
            )

    def test_make_changes_rejects_unset_home_before_visiting_fixed_paths(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            projects = root / "projects"
            projects.write_text("")
            fixture = root / "Makefile"
            fixture.write_text(f"include {REPO / 'Makefile'}\n")
            fake_bin = root / "bin"
            fake_bin.mkdir()
            changes_log = root / "changes.log"
            changes = fake_bin / "changes"
            changes.write_text('#!/bin/sh\nprintf "reached\\n" >>"$CHANGES_LOG"\n')
            changes.chmod(0o755)
            env = clean_env(
                PATH=f"{fake_bin}:{os.defpath}", CHANGES_LOG=str(changes_log)
            )
            env.pop("HOME", None)

            result = subprocess.run(
                [
                    "make",
                    "--no-print-directory",
                    "-f",
                    str(fixture),
                    "changes",
                    f"PROJECTS={projects}",
                ],
                cwd=root,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Makefile: HOME is not set", result.stderr)
            self.assertNotIn("###", result.stdout)
            self.assertFalse(changes_log.exists())

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
            (fake_bin / "lib").mkdir()
            shutil.copy2(
                REPO / "bin/lib/local-git-inputs.py",
                fake_bin / "lib/local-git-inputs.py",
            )
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

            local_repo = root / "local"
            local_repo.mkdir()
            git("init", "-q", ".", cwd=local_repo)
            git("config", "user.email", "test@example.invalid", cwd=local_repo)
            git("config", "user.name", "Test", cwd=local_repo)
            git("config", "commit.gpgsign", "false", cwd=local_repo)
            (local_repo / "tracked").write_text("tracked\n")
            git("add", "tracked", cwd=local_repo)
            git("commit", "-qm", "fixture", cwd=local_repo)

            (root / "flake.lock").write_text(
                json.dumps(
                    {
                        "version": 7,
                        "root": "root",
                        "nodes": {
                            "root": {"inputs": {"local": "local-node"}},
                            "local-node": {
                                "locked": {
                                    "type": "git",
                                    "url": local_repo.as_uri(),
                                },
                                "original": {
                                    "type": "git",
                                    "url": local_repo.as_uri(),
                                },
                            },
                        },
                    }
                )
            )
            fixture = root / "Makefile"
            fixture.write_text(f"include {REPO / 'Makefile'}\n")
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
                        "version": 7,
                        "root": "root",
                        "nodes": {
                            "root": {"inputs": {"local": "local-node"}},
                            "local-node": {
                                "locked": {
                                    "type": "git",
                                    "url": local_repo.as_uri(),
                                },
                                "original": {
                                    "type": "git",
                                    "url": local_repo.as_uri(),
                                },
                            },
                        },
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

    def test_signature_ci_uses_the_base_owned_verifier_and_event_range(self):
        workflow = (REPO / ".github/workflows/ci.yml").read_text()
        for required in (
            "fetch-depth: 0",
            "ref: ${{ github.event.pull_request.base.sha || github.sha }}",
            'git fetch --no-tags origin "pull/${{ github.event.pull_request.number }}/head"',
            "SIGVERIFY_BASE: ${{ github.event.pull_request.base.sha || github.event.before }}",
            "SIGVERIFY_HEAD: ${{ github.event.pull_request.head.sha || github.sha }}",
            'SIGVERIFY_STRICT: "1"',
            'test/bin/verify-signatures --base "$SIGVERIFY_BASE" --head "$SIGVERIFY_HEAD"',
        ):
            self.assertIn(required, workflow)
        self.assertNotIn("ref: ${{ github.event.pull_request.head.sha", workflow)

    def test_signature_trust_root_is_public_and_unique(self):
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


if __name__ == "__main__":
    unittest.main()
