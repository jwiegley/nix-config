#!/usr/bin/env python3
"""Regression tests for the committed Darwin value-surface backstop."""

import hashlib
import importlib.machinery
import importlib.util
import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO = HERE.parent
TOOL = HERE / "darwin-surface-diff"
BASELINE_TOOL = HERE / "darwin-surface-baseline"
BASELINE_DIR = REPO / "test" / "baseline"
HASH_A = "0123456789abcdfghijklmnpqrsvwxyz"
HASH_B = "zyxwvsrqpnmlkjihgfdcba9876543210"
UNREADABLE = "<unreadable: removed or throwing option>"
SURFACES = {
    "users",
    "environment",
    "services",
    "homebrew",
    "nix",
    "system",
    "launchd",
}


def load_tool():
    loader = importlib.machinery.SourceFileLoader("darwin_surface_diff", str(TOOL))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


DIFF = load_tool()


class DarwinSurfaceDiffTests(unittest.TestCase):
    def test_nix_projection_keeps_name_and_rejects_unnamed_homebrew_objects(self):
        expression = r'''
          let
            helpers = import ./test/darwin/surface-helpers.nix;
          in {
            names = [
              (helpers.derivationName { pname = "same"; name = "package-1.0"; })
              (helpers.derivationName { pname = "same"; name = "package-2.0"; })
            ];
            unnamedHomebrewSucceeds =
              (builtins.tryEval (builtins.deepSeq (helpers.homebrewName "brew" { }) true)).success;
          }
        '''
        process = subprocess.run(
            ["nix", "eval", "--impure", "--json", "--expr", expression],
            cwd=REPO,
            capture_output=True,
            text=True,
        )
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        result = json.loads(process.stdout)
        self.assertEqual(result["names"], ["package-1.0", "package-2.0"])
        self.assertFalse(result["unnamedHomebrewSucceeds"])

    def test_hash_only_change_is_ignored_but_name_is_retained(self):
        before = {"path": f"/nix/store/{HASH_A}-activation-johnw"}
        after = {"path": f"/nix/store/{HASH_B}-activation-johnw"}
        self.assertEqual(
            DIFF.differences(
                DIFF.normalize_store(before), DIFF.normalize_store(after)
            ),
            [],
        )
        self.assertEqual(
            DIFF.normalize_store(before)["path"],
            "/nix/store/<hash>-activation-johnw",
        )

    def test_renamed_derivation_still_fails_after_normalization(self):
        before = {"path": f"/nix/store/{HASH_A}-aria2c-start"}
        after = {"path": f"/nix/store/{HASH_B}-EVIL-start"}
        found = DIFF.differences(
            DIFF.normalize_store(before), DIFF.normalize_store(after)
        )
        self.assertEqual(len(found), 1)
        self.assertIn("aria2c-start", found[0])
        self.assertIn("EVIL-start", found[0])

    def test_tampered_value_and_list_element_report_leaf_paths(self):
        before = {"system": {"dock": {"orientation": "bottom"}}, "items": [1, 2]}
        after = {"system": {"dock": {"orientation": "left"}}, "items": [1, 3]}
        found = DIFF.differences(before, after)
        self.assertTrue(any("system.dock.orientation" in item for item in found))
        self.assertTrue(any("items[1]" in item for item in found))

    def test_invalid_store_alphabet_is_not_masked(self):
        invalid = "/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-name"
        self.assertEqual(DIFF.normalize_store(invalid), invalid)

    def test_cli_rejects_missing_unknown_and_extra_arguments(self):
        for arguments in ([], ["--unknown"], ["a", "b", "c"]):
            process = subprocess.run(
                [str(TOOL), *arguments], capture_output=True, text=True
            )
            self.assertEqual(process.returncode, 2, process.stdout + process.stderr)

    def test_cli_distinguishes_drift_from_input_error(self):
        with tempfile.TemporaryDirectory(prefix="darwin-surface-diff-") as tmp:
            root = Path(tmp)
            before = root / "before.json"
            after = root / "after.json"
            before.write_text('{"value": 1}\n')
            after.write_text('{"value": 2}\n')
            drift = subprocess.run(
                [str(TOOL), str(before), str(after)],
                capture_output=True,
                text=True,
            )
            broken = subprocess.run(
                [str(TOOL), str(before), str(root / "missing.json")],
                capture_output=True,
                text=True,
            )
            self.assertEqual(drift.returncode, 1, drift.stdout + drift.stderr)
            self.assertEqual(broken.returncode, 2, broken.stdout + broken.stderr)

    def test_baseline_generator_is_executable_and_documents_safe_modes(self):
        self.assertTrue(BASELINE_TOOL.is_file())
        self.assertTrue(BASELINE_TOOL.stat().st_mode & 0o111)
        help_result = subprocess.run(
            [str(BASELINE_TOOL), "--help"], capture_output=True, text=True
        )
        self.assertEqual(
            help_result.returncode, 0, help_result.stdout + help_result.stderr
        )
        self.assertIn("--rev REV", help_result.stdout)
        self.assertIn("--print", help_result.stdout)
        self.assertIn("--write", help_result.stdout)


class CommittedDarwinSurfaceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        baselines = sorted(BASELINE_DIR.glob("darwin-surface-*.json"))
        if len(baselines) != 1:
            raise AssertionError(f"expected one Darwin surface baseline, got {baselines}")
        cls.path = baselines[0]
        cls.baseline = json.loads(cls.path.read_text())

    def test_baseline_identity_and_schema_are_not_vacuous(self):
        baseline_rev = self.baseline.get("baselineRev", "")
        self.assertRegex(baseline_rev, r"^[0-9a-f]{40}$")
        self.assertEqual(self.path.stem, f"darwin-surface-{baseline_rev[:12]}")
        self.assertEqual(self.baseline.get("schema"), "darwin-value-surface/2")
        self.assertEqual(set(self.baseline.get("hosts", {})), {"hera", "clio"})
        for surface in self.baseline["hosts"].values():
            self.assertEqual(set(surface), SURFACES)
        self.assertEqual(
            self.baseline["commands"].get("refresh"),
            "bin/darwin-surface-baseline --rev <rev> --write",
        )
        expected_projection = {}
        for relative in (
            "test/darwin/darwin-surface.nix",
            "test/darwin/surface-helpers.nix",
            "bin/darwin-surface-diff",
        ):
            expected_projection[relative] = hashlib.sha256(
                (REPO / relative).read_bytes()
            ).hexdigest()
        self.assertEqual(self.baseline.get("projection"), expected_projection)

    def test_baseline_encodes_both_nonvacuity_traps_and_nix_builders(self):
        expected_counts = {"hera": (12, 6, 8), "clio": (5, 3, 4)}
        for host, (user_agents, daemons, max_jobs) in expected_counts.items():
            surface = self.baseline["hosts"][host]
            launchd = surface["launchd"]
            self.assertEqual(len(launchd["userAgentNames"]), user_agents)
            self.assertEqual(len(launchd["daemonNames"]), daemons)
            self.assertEqual(launchd["agentNames"], [])
            self.assertEqual(surface["system"]["defaults"]["alf"], UNREADABLE)
            self.assertEqual(surface["nix"]["maxJobs"], max_jobs)
            self.assertEqual(len(surface["nix"]["buildMachines"]), 1)
            for group in ("userAgents", "daemons", "agents"):
                for agent in launchd[group].values():
                    self.assertEqual(
                        set(agent), {"serviceConfigSha256", "scriptSha256"}
                    )
                    self.assertRegex(agent["serviceConfigSha256"], r"^[0-9a-f]{64}$")
                    if agent["scriptSha256"] is not None:
                        self.assertRegex(agent["scriptSha256"], r"^[0-9a-f]{64}$")

    def test_post_85_prometheus_entries_are_not_duplicated(self):
        hera_users = self.baseline["hosts"]["hera"]["users"]
        self.assertEqual(hera_users["knownUsers"].count("_prometheus-node-exporter"), 1)
        self.assertEqual(hera_users["knownGroups"].count("_prometheus-node-exporter"), 1)

    def test_committed_baseline_contains_no_raw_store_hashes(self):
        encoded = json.dumps(self.baseline, sort_keys=True)
        self.assertIsNone(re.search(DIFF.STORE_PATH, encoded))

    def test_committed_baseline_contains_no_credential_material(self):
        encoded = json.dumps(self.baseline, sort_keys=True)
        for pattern in (
            "ghp_",
            "github_pat_",
            "PRIVATE KEY",
            "password=",
            "token=",
        ):
            self.assertNotIn(pattern, encoded)

    def test_cross_host_comparison_is_a_real_negative_case(self):
        hosts = self.baseline["hosts"]
        self.assertTrue(DIFF.differences(hosts["hera"], hosts["clio"]))


if __name__ == "__main__":
    unittest.main()
