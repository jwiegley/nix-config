#!/usr/bin/env python3
"""Cheap currency and consistency guard for the fleet parity oracle.

The oracle is ``test/baseline/parity-<rev>.json``, derived by
``test/bin/parity-baseline`` (jwiegley/nix-config#19). Deriving it costs roughly five
minutes of cross-system ``nix eval``, so this guard NEVER re-derives. It reads
the committed artifact plus git metadata only, and answers one question that a
frozen oracle cannot answer about itself: *is this still a meaningful thing to
compare against?*

Determinism (byte-identity at the recorded rev) and multiset/drvPath
equivalence remain ``test/bin/parity-baseline``'s job -- ``--check`` and
``--compare``. This file is strictly the currency/consistency half owned by
jwiegley/nix-config#31, and it costs a few git calls, not a build.

What it asserts, all without a single nix evaluation:

* exactly one committed oracle (the previous oracle belongs in git history, not
  a second tracked file);
* ``baselineRev`` is a real commit, an ancestor of HEAD (not a stranded
  baseline), and a descendant of the armed-overlay refactor ``a3cc3843`` -- an
  oracle predating it can never be satisfied by post-refactor work;
* the filename encodes the same rev the file records -- the exact inconsistency
  the ``--write`` double ``git rev-parse`` bug produced;
* ``packageCount`` equals ``len(packages)`` on every target, so a hand-edited
  count can never drift from the list it summarises;
* the recorded derivation command's KEYS and SHAPE are present
      (drift against the live tool is NOT asserted: that test skips until
      test/bin/parity-baseline gains a --commands mode -- see the skip reason)
  command that has drifted from the tool derives a different oracle than the one
  a later gate would;
* provenance: any recorded history chain is well-formed and its tail is the
  current ``baselineRev``; once the oracle advances past its genesis schema, the
  chain is mandatory.

The negative side of every assertion lives in ``OracleGuardSelfTests`` below,
which mutates synthetic copies in throwaway git repositories -- never the real
artifact -- and proves each check actually fires.
"""

import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BASELINE_DIR = REPO_ROOT / "test" / "baseline"
PARITY_BASELINE = REPO_ROOT / "test" / "bin" / "parity-baseline"

# Must agree with test/bin/parity-baseline's ARMED_REFACTOR. a36d3f51 predates it, so
# demanding byte-identity against a pre-a3cc3843 oracle can never be met.
ARMED_REFACTOR = "a3cc3843"

SCHEMA_PREFIX = "fleet-parity-oracle/"
# Schema versions this guard understands. /1 is the genesis capture (jw#19),
# which predates provenance. /2 adds the mandatory history chain (jw#31). An
# unknown version fails loudly rather than being waved through.
KNOWN_SCHEMAS = (1, 2)
# The schema version at and above which a non-empty, well-formed history chain
# is required. Below it (the genesis capture) history is optional, which is what
# lets this guard land and stay green before the first refresh re-derives.
PROVENANCE_FROM_SCHEMA = 2

EXPECTED_COMMAND_KEYS = frozenset(
    {
        "darwinDrvPath",
        "darwinPackages",
        "hmDrvPath",
        "hmPackages",
        "portablePackages",
    }
)

HISTORY_ENTRY_KEYS = frozenset({"old_rev", "new_rev", "reason", "intentional_deltas"})

_REV40 = re.compile(r"\A[0-9a-f]{40}\Z")
_FILENAME = re.compile(r"\Aparity-([0-9a-f]{12})\.json\Z")


# --- helpers -------------------------------------------------------------


def find_baselines(baseline_dir):
    """Every committed oracle artifact, sorted for a stable message."""
    return sorted(Path(baseline_dir).glob("parity-*.json"))


def schema_version(oracle):
    """Integer N from a ``fleet-parity-oracle/N`` schema string, else None."""
    schema = oracle.get("schema", "")
    if isinstance(schema, str) and schema.startswith(SCHEMA_PREFIX):
        tail = schema[len(SCHEMA_PREFIX) :]
        if tail.isdigit():
            return int(tail)
    return None


def _short(rev):
    return rev[:12] if isinstance(rev, str) else repr(rev)


def _is_rev40(value):
    return isinstance(value, str) and _REV40.match(value) is not None


def git_runner(repo_root):
    """A callable ``git(args) -> CompletedProcess`` bound to one repository.

    Never raises on a non-zero git exit -- the checks inspect returncode
    themselves, because 'not an ancestor' is a finding, not an error.
    """
    root = str(repo_root)

    def run(args):
        return subprocess.run(
            ["git", "-C", root, *args],
            capture_output=True,
            text=True,
            check=False,
        )

    return run


# --- the checks (pure; each returns a list of human-readable problems) ---


def check_single_baseline(baseline_dir):
    found = find_baselines(baseline_dir)
    if len(found) == 1:
        return []
    if not found:
        return ["no committed oracle: expected exactly one test/baseline/parity-*.json"]
    names = ", ".join(p.name for p in found)
    return [
        "expected exactly one committed oracle, found %d (%s); a superseded "
        "oracle belongs in git history, not a second tracked file" % (len(found), names)
    ]


def check_filename_matches_rev(path, oracle):
    match = _FILENAME.match(Path(path).name)
    if not match:
        return ["oracle filename %r is not parity-<12hex>.json" % Path(path).name]
    rev = oracle.get("baselineRev")
    if not _is_rev40(rev):
        return ["baselineRev %r is not a 40-char lowercase-hex sha" % (rev,)]
    if match.group(1) != rev[:12]:
        return [
            "filename rev %s disagrees with recorded baselineRev %s; a baseline "
            "whose name and contents name different revs is worse than none (the "
            "--write double rev-parse bug)" % (match.group(1), rev[:12])
        ]
    return []


def check_counts(oracle):
    targets = oracle.get("targets")
    if not isinstance(targets, list) or not targets:
        return ["oracle has no targets array"]
    problems = []
    for target in targets:
        key = "%s/%s" % (target.get("kind"), target.get("target"))
        packages = target.get("packages")
        count = target.get("packageCount")
        if not isinstance(packages, list):
            problems.append("target %s has no packages list" % key)
            continue
        if count != len(packages):
            problems.append(
                "target %s records packageCount=%r but len(packages)=%d; a "
                "count maintained apart from its list must never drift from it"
                % (key, count, len(packages))
            )
    return problems


def check_commands_present(oracle):
    commands = oracle.get("commands")
    if not isinstance(commands, dict) or not commands:
        return [
            "oracle has no non-empty commands field; a later 'vs baseline' gate "
            "could not re-derive identically"
        ]
    problems = []
    keys = frozenset(commands)
    if keys != EXPECTED_COMMAND_KEYS:
        problems.append(
            "commands keys %s != expected %s"
            % (sorted(keys), sorted(EXPECTED_COMMAND_KEYS))
        )
    for name, value in commands.items():
        if not isinstance(value, str) or not value.strip():
            problems.append("command %r is empty" % name)
    return problems


def check_schema_known(oracle):
    version = schema_version(oracle)
    if version is None:
        return [
            "oracle schema %r is not of the form %sN"
            % (oracle.get("schema"), SCHEMA_PREFIX)
        ]
    if version not in KNOWN_SCHEMAS:
        return [
            "oracle schema version %d is unknown to this guard (known: %s); a "
            "guard that silently accepts an unknown schema is how a format drift "
            "goes unnoticed" % (version, list(KNOWN_SCHEMAS))
        ]
    return []


def check_provenance(oracle):
    """Validate the history chain -- shape, linkage, and its tail.

    History is optional at the genesis schema (jw#19's capture, /1) and
    mandatory once the oracle has advanced (/2+), which is exactly when a
    lineage becomes something to audit.
    """
    version = schema_version(oracle)
    history = oracle.get("history")
    rev = oracle.get("baselineRev")

    if history is None:
        if version is not None and version >= PROVENANCE_FROM_SCHEMA:
            return [
                "schema /%d oracle has no history; provenance is mandatory once "
                "the oracle has advanced past its genesis capture (jw#31)" % version
            ]
        return []

    if not isinstance(history, list) or not history:
        return [
            "history is present but empty; omit it (genesis capture) or record "
            "at least one {old_rev,new_rev,reason,intentional_deltas} entry"
        ]

    problems = []
    prev_new = None
    for index, entry in enumerate(history):
        where = "history[%d]" % index
        if not isinstance(entry, dict):
            problems.append("%s is not an object" % where)
            prev_new = None
            continue
        missing = HISTORY_ENTRY_KEYS - frozenset(entry)
        if missing:
            problems.append("%s is missing %s" % (where, sorted(missing)))
        new_rev = entry.get("new_rev")
        old_rev = entry.get("old_rev")
        reason = entry.get("reason")
        if not _is_rev40(new_rev):
            problems.append("%s new_rev %r is not a 40-char sha" % (where, new_rev))
        if old_rev is not None and not _is_rev40(old_rev):
            problems.append(
                "%s old_rev %r is neither null nor a 40-char sha" % (where, old_rev)
            )
        if not (isinstance(reason, str) and reason.strip()):
            problems.append("%s reason is empty" % where)
        if not isinstance(entry.get("intentional_deltas"), list):
            problems.append("%s intentional_deltas is not a list" % where)
        if prev_new is not None and old_rev != prev_new:
            problems.append(
                "%s old_rev %s does not chain from the previous new_rev %s"
                % (where, _short(old_rev), _short(prev_new))
            )
        prev_new = new_rev

    tail = history[-1].get("new_rev") if isinstance(history[-1], dict) else None
    if tail != rev:
        problems.append(
            "history tail new_rev %s is not the current baselineRev %s; the "
            "chain must end at the oracle it describes" % (_short(tail), _short(rev))
        )
    return problems


def check_git_ancestry(oracle, armed_refactor, git):
    """Currency: the recorded revs must sit on this line of history.

    ``git`` is any callable returning a CompletedProcess, so a synthetic
    repository can be substituted in the self-tests.
    """
    rev = oracle.get("baselineRev")
    if not _is_rev40(rev):
        return ["baselineRev %r is not a usable sha" % (rev,)]
    if git(["cat-file", "-t", rev]).stdout.strip() != "commit":
        return [
            "baselineRev %s is not a commit in this repository; the oracle names "
            "a rev that does not exist here" % _short(rev)
        ]

    problems = []
    if git(["merge-base", "--is-ancestor", rev, "HEAD"]).returncode != 0:
        problems.append(
            "STRANDED BASELINE: baselineRev %s is not an ancestor of HEAD; the "
            "oracle no longer sits on this line of history, so every 'vs "
            "baseline' comparison is meaningless. Refresh it "
            "(doc/PARITY-ORACLE-REFRESH.md, jw#31)." % _short(rev)
        )
    if git(["merge-base", "--is-ancestor", armed_refactor, rev]).returncode != 0:
        problems.append(
            "baselineRev %s does not descend from the armed-overlay refactor %s; "
            "such an oracle can never be satisfied by post-refactor work"
            % (_short(rev), armed_refactor)
        )

    for index, entry in enumerate(oracle.get("history") or []):
        if not isinstance(entry, dict):
            continue
        new_rev = entry.get("new_rev")
        if not _is_rev40(new_rev):
            continue  # shape already reported by check_provenance
        if git(["cat-file", "-t", new_rev]).stdout.strip() != "commit":
            problems.append(
                "history[%d] new_rev %s is not a commit here" % (index, _short(new_rev))
            )
        elif git(["merge-base", "--is-ancestor", new_rev, "HEAD"]).returncode != 0:
            problems.append(
                "history[%d] new_rev %s is not an ancestor of HEAD"
                % (index, _short(new_rev))
            )
    return problems


# --- the guard, against the real committed oracle ------------------------


class OracleCurrencyTests(unittest.TestCase):
    """The guard proper: the committed oracle must be current and consistent.

    Runs where test/bin/quality's python-test suite runs it -- the repo root, inside
    a git work tree -- and shells out to git the same way update-overlay-test.py
    shells out to bash. Every check reads the artifact and git metadata; none
    re-derives.
    """

    def setUp(self):
        self.git = git_runner(REPO_ROOT)
        if self.git(["rev-parse", "--is-inside-work-tree"]).returncode != 0:
            self.skipTest("not inside a git work tree")
        found = find_baselines(BASELINE_DIR)
        self.path = found[0] if len(found) == 1 else None
        self.oracle = json.loads(self.path.read_text()) if self.path else None

    def _require_oracle(self):
        if self.oracle is None:
            self.fail(
                "no single committed oracle -- see test_exactly_one_committed_oracle"
            )

    def test_exactly_one_committed_oracle(self):
        self.assertEqual(check_single_baseline(BASELINE_DIR), [])

    def test_filename_matches_recorded_rev(self):
        self._require_oracle()
        self.assertEqual(check_filename_matches_rev(self.path, self.oracle), [])

    def test_schema_is_known(self):
        self._require_oracle()
        self.assertEqual(check_schema_known(self.oracle), [])

    def test_package_counts_match_lists(self):
        self._require_oracle()
        self.assertEqual(check_counts(self.oracle), [])

    def test_commands_present_and_shaped(self):
        self._require_oracle()
        self.assertEqual(check_commands_present(self.oracle), [])

    def test_provenance_chain_is_well_formed(self):
        self._require_oracle()
        self.assertEqual(check_provenance(self.oracle), [])

    def test_provenance_enforced_once_advanced(self):
        self._require_oracle()
        version = schema_version(self.oracle)
        if version == 1 and self.oracle.get("history") is None:
            self.skipTest(
                "oracle is still at genesis schema /1; provenance activates at "
                "/2, written by the first `test/bin/parity-baseline --refresh` "
                "(doc/PARITY-ORACLE-REFRESH.md, jw#31)"
            )
        self.assertGreaterEqual(
            len(self.oracle.get("history") or []),
            1,
            "an advanced oracle must carry at least one provenance entry",
        )

    def test_baseline_rev_is_current_and_satisfiable(self):
        self._require_oracle()
        self.assertEqual(check_git_ancestry(self.oracle, ARMED_REFACTOR, self.git), [])

    def test_recorded_command_matches_the_tool(self):
        self._require_oracle()
        if not PARITY_BASELINE.exists():
            self.skipTest("test/bin/parity-baseline is not present")
        proc = subprocess.run(
            [str(PARITY_BASELINE), "--commands"],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            self.skipTest(
                "test/bin/parity-baseline has no cheap --commands mode yet; apply the "
                "block in doc/PARITY-ORACLE-REFRESH.md so command drift is a hard "
                "failure rather than a skip"
            )
        try:
            current = json.loads(proc.stdout)
        except json.JSONDecodeError as exc:
            self.fail("test/bin/parity-baseline --commands did not emit JSON: %s" % exc)
        self.assertEqual(
            self.oracle.get("commands"),
            current,
            "the oracle's recorded derivation command has drifted from "
            "test/bin/parity-baseline; re-derive the oracle so the recorded command "
            "matches the tool (jw#31)",
        )

    def test_config_ai_to_fleet_command_migration_is_exact(self):
        self._require_oracle()
        current = self.oracle["commands"]
        old = json.loads(json.dumps(current))
        old["portablePackages"] = old["portablePackages"].replace(
            "./config/fleet#packages", "./config/ai#packages"
        )

        with tempfile.TemporaryDirectory(prefix="parity-command-migration-") as tmp:
            old_path = Path(tmp) / "old.json"
            new_path = Path(tmp) / "new.json"
            old_path.write_text(json.dumps(old))
            new_path.write_text(json.dumps(current))

            def validate(candidate):
                old_path.write_text(json.dumps(candidate))
                return subprocess.run(
                    [
                        str(PARITY_BASELINE),
                        "--validate-command-migration",
                        str(old_path),
                        str(new_path),
                    ],
                    capture_output=True,
                    text=True,
                    check=False,
                )

            self.assertEqual(validate(old).returncode, 0)

            unrelated = json.loads(json.dumps(old))
            unrelated["darwinPackages"] += " --impure"
            self.assertNotEqual(validate(unrelated).returncode, 0)

            no_migration = json.loads(json.dumps(current))
            self.assertNotEqual(validate(no_migration).returncode, 0)

            duplicate = json.loads(json.dumps(old))
            duplicate["portablePackages"] += " ./config/ai#packages.extra"
            self.assertNotEqual(validate(duplicate).returncode, 0)


# --- self-tests: every assertion, watched failing on a mutation ----------


def _init_repo(root):
    """A fresh throwaway repository with signing off and an identity set."""
    subprocess.run(["git", "init", "-q", str(root)], check=True)
    for key, value in (
        ("user.name", "Oracle Guard Test"),
        ("user.email", "oracle-guard@example.invalid"),
        ("commit.gpgsign", "false"),
    ):
        subprocess.run(["git", "-C", str(root), "config", key, value], check=True)


def _commit(root, name):
    (Path(root) / name).write_text(name + "\n")
    subprocess.run(["git", "-C", str(root), "add", name], check=True)
    subprocess.run(["git", "-C", str(root), "commit", "-q", "-m", name], check=True)
    return subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def _valid_oracle(base_rev, armed_rev, history=None):
    """A minimally valid oracle carrying real synthetic revs.

    ``history`` None means genesis schema /1; a list means schema /2.
    """
    oracle = {
        "schema": SCHEMA_PREFIX + ("2" if history is not None else "1"),
        "baselineRev": base_rev,
        "armedRefactorAncestor": armed_rev,
        "commands": {
            key: "nix eval placeholder for %s" % key for key in EXPECTED_COMMAND_KEYS
        },
        "targets": [
            {
                "kind": "portable",
                "target": "x86_64-linux",
                "packages": ["alpha", "beta", "gamma"],
                "packageCount": 3,
            }
        ],
    }
    if history is not None:
        oracle["history"] = history
    return oracle


class OracleGuardSelfTests(unittest.TestCase):
    """Build a synthetic repo and mutate synthetic oracles; watch each fire.

    A positive fixture that raised no problem would be no evidence at all, so a
    valid oracle is asserted clean first, then each field is broken in isolation
    and the specific problem is asserted to appear.
    """

    def setUp(self):
        local_env = subprocess.run(
            ["git", "rev-parse", "--local-env-vars"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.split()
        self._restore = {}
        for name in local_env:
            if name in os.environ:
                self._restore[name] = os.environ.pop(name)

        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name) / "repo"
        self.root.mkdir()
        _init_repo(self.root)
        # Linear history:  pre <- armed <- base <- head  (head is HEAD).
        # A side branch off armed gives a rev that is NOT an ancestor of HEAD.
        self.pre = _commit(self.root, "pre")
        self.armed = _commit(self.root, "armed")
        self.base = _commit(self.root, "base")
        self.head = _commit(self.root, "head")
        subprocess.run(
            ["git", "-C", str(self.root), "checkout", "-q", "-b", "side", self.armed],
            check=True,
        )
        self.side = _commit(self.root, "side")
        subprocess.run(
            ["git", "-C", str(self.root), "checkout", "-q", self.head], check=True
        )
        self.git = git_runner(self.root)
        (self.root / "test" / "baseline").mkdir(parents=True)

    def tearDown(self):
        os.environ.update(self._restore)

    def _write_baseline(self, oracle, rev12=None):
        rev12 = rev12 or oracle["baselineRev"][:12]
        path = self.root / "test" / "baseline" / ("parity-%s.json" % rev12)
        path.write_text(json.dumps(oracle, indent=1))
        return path

    def _baseline_dir(self):
        return self.root / "test" / "baseline"

    # -- positive fixtures: no problems ----------------------------------

    def test_valid_genesis_oracle_is_clean(self):
        oracle = _valid_oracle(self.base, self.armed)
        path = self._write_baseline(oracle)
        self.assertEqual(check_single_baseline(self._baseline_dir()), [])
        self.assertEqual(check_filename_matches_rev(path, oracle), [])
        self.assertEqual(check_schema_known(oracle), [])
        self.assertEqual(check_counts(oracle), [])
        self.assertEqual(check_commands_present(oracle), [])
        self.assertEqual(check_provenance(oracle), [])
        self.assertEqual(check_git_ancestry(oracle, self.armed, self.git), [])

    def test_valid_advanced_oracle_with_history_is_clean(self):
        history = [
            {
                "old_rev": None,
                "new_rev": self.pre,
                "reason": "initial capture (jw#19)",
                "intentional_deltas": [],
            },
            {
                "old_rev": self.pre,
                "new_rev": self.base,
                "reason": "overlay-factory refactor landed parity-clean",
                "intentional_deltas": [],
            },
        ]
        oracle = _valid_oracle(self.base, self.armed, history=history)
        self.assertEqual(check_schema_known(oracle), [])
        self.assertEqual(check_provenance(oracle), [])
        self.assertEqual(check_git_ancestry(oracle, self.armed, self.git), [])

    # -- one mutation per invariant, asserted to fire --------------------

    def test_two_baselines_rejected(self):
        self._write_baseline(_valid_oracle(self.base, self.armed))
        self._write_baseline(_valid_oracle(self.head, self.armed))
        problems = check_single_baseline(self._baseline_dir())
        self.assertTrue(problems)
        self.assertIn("exactly one", problems[0])

    def test_zero_baselines_rejected(self):
        problems = check_single_baseline(self._baseline_dir())
        self.assertTrue(problems)
        self.assertIn("no committed oracle", problems[0])

    def test_filename_rev_mismatch_rejected(self):
        oracle = _valid_oracle(self.base, self.armed)
        path = self._write_baseline(oracle, rev12=self.head[:12])
        problems = check_filename_matches_rev(path, oracle)
        self.assertTrue(problems)
        self.assertIn("disagrees with recorded baselineRev", problems[0])

    def test_bad_rev_format_rejected(self):
        oracle = _valid_oracle("not-a-sha", self.armed)
        path = self.root / "test" / "baseline" / "parity-000000000000.json"
        path.write_text(json.dumps(oracle))
        problems = check_filename_matches_rev(path, oracle)
        self.assertTrue(problems)
        self.assertIn("40-char", problems[0])

    def test_count_mismatch_rejected(self):
        oracle = _valid_oracle(self.base, self.armed)
        oracle["targets"][0]["packageCount"] = 99
        problems = check_counts(oracle)
        self.assertTrue(problems)
        self.assertIn("must never drift", problems[0])

    def test_missing_commands_rejected(self):
        oracle = _valid_oracle(self.base, self.armed)
        del oracle["commands"]
        problems = check_commands_present(oracle)
        self.assertTrue(problems)
        self.assertIn("no non-empty commands", problems[0])

    def test_command_key_drift_rejected(self):
        oracle = _valid_oracle(self.base, self.armed)
        oracle["commands"].pop("portablePackages")
        problems = check_commands_present(oracle)
        self.assertTrue(problems)
        self.assertIn("commands keys", problems[0])

    def test_unknown_schema_rejected(self):
        oracle = _valid_oracle(self.base, self.armed)
        oracle["schema"] = SCHEMA_PREFIX + "99"
        problems = check_schema_known(oracle)
        self.assertTrue(problems)
        self.assertIn("unknown to this guard", problems[0])

    def test_advanced_schema_without_history_rejected(self):
        oracle = _valid_oracle(self.base, self.armed)
        oracle["schema"] = SCHEMA_PREFIX + "2"  # /2 but no history
        problems = check_provenance(oracle)
        self.assertTrue(problems)
        self.assertIn("provenance is mandatory", problems[0])

    def test_history_missing_field_rejected(self):
        history = [{"new_rev": self.base, "reason": "x", "intentional_deltas": []}]
        oracle = _valid_oracle(self.base, self.armed, history=history)
        problems = check_provenance(oracle)
        self.assertTrue(problems)
        self.assertTrue(any("old_rev" in p for p in problems))

    def test_history_broken_chain_rejected(self):
        history = [
            {
                "old_rev": None,
                "new_rev": self.pre,
                "reason": "genesis",
                "intentional_deltas": [],
            },
            {
                "old_rev": self.head,  # should be self.pre
                "new_rev": self.base,
                "reason": "refresh",
                "intentional_deltas": [],
            },
        ]
        oracle = _valid_oracle(self.base, self.armed, history=history)
        problems = check_provenance(oracle)
        self.assertTrue(problems)
        self.assertTrue(any("does not chain from" in p for p in problems))

    def test_history_tail_not_baseline_rejected(self):
        history = [
            {
                "old_rev": None,
                "new_rev": self.pre,  # tail != baselineRev (self.base)
                "reason": "genesis",
                "intentional_deltas": [],
            }
        ]
        oracle = _valid_oracle(self.base, self.armed, history=history)
        problems = check_provenance(oracle)
        self.assertTrue(problems)
        self.assertTrue(any("is not the current baselineRev" in p for p in problems))

    def test_history_empty_reason_rejected(self):
        history = [
            {
                "old_rev": None,
                "new_rev": self.base,
                "reason": "   ",
                "intentional_deltas": [],
            }
        ]
        oracle = _valid_oracle(self.base, self.armed, history=history)
        problems = check_provenance(oracle)
        self.assertTrue(problems)
        self.assertTrue(any("reason is empty" in p for p in problems))

    def test_stranded_baseline_rejected(self):
        oracle = _valid_oracle(self.side, self.armed)  # off to the side of HEAD
        problems = check_git_ancestry(oracle, self.armed, self.git)
        self.assertTrue(problems)
        self.assertTrue(any("STRANDED BASELINE" in p for p in problems))

    def test_predates_armed_refactor_rejected(self):
        oracle = _valid_oracle(self.pre, self.armed)  # pre is before armed
        problems = check_git_ancestry(oracle, self.armed, self.git)
        self.assertTrue(problems)
        self.assertTrue(any("does not descend from" in p for p in problems))

    def test_nonexistent_rev_rejected(self):
        ghost = "0" * 40
        oracle = _valid_oracle(ghost, self.armed)
        problems = check_git_ancestry(oracle, self.armed, self.git)
        self.assertTrue(problems)
        self.assertTrue(any("does not exist here" in p for p in problems))

    def test_fabricated_history_rev_rejected(self):
        history = [
            {
                "old_rev": None,
                "new_rev": self.base,
                "reason": "genesis",
                "intentional_deltas": [],
            }
        ]
        oracle = _valid_oracle(self.base, self.armed, history=history)
        oracle["history"].insert(
            0,
            {
                "old_rev": None,
                "new_rev": "f" * 40,  # never committed here
                "reason": "fabricated",
                "intentional_deltas": [],
            },
        )
        # Re-chain so only the ancestry check, not the linkage check, fires.
        oracle["history"][1]["old_rev"] = "f" * 40
        problems = check_git_ancestry(oracle, self.armed, self.git)
        self.assertTrue(problems)
        self.assertTrue(any("is not a commit here" in p for p in problems))


if __name__ == "__main__":
    unittest.main()
