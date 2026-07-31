#!/usr/bin/env python3
"""Focused fault-injection tests for ``bin/coverage-report``.

The suite uses only temporary Git repositories and synthetic Nix diagnostics.  It
never invokes a real Nix evaluation probe.
"""

from __future__ import annotations

import copy
import importlib.machinery
import importlib.util
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock


SCRIPT = Path(__file__).with_name("coverage-report")
LOADER = importlib.machinery.SourceFileLoader("coverage_report", str(SCRIPT))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
coverage_report = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(coverage_report)

MACHINE_ROOTS = {
    "hera": "hera",
    "clio": "clio",
    "vulcan": "vulcan",
    "vps": "vps",
    "andoria-08": "shared-work",
    "andoria-t2": "shared-work",
    "delphi-3bd4": "shared-work",
    "gpu-server": "shared-work",
}
ROOT_SYSTEMS = {
    "hera": "aarch64-darwin",
    "clio": "aarch64-darwin",
    "linux-fixture": "aarch64-linux",
    "shared-work": "x86_64-linux",
    "vps": "x86_64-linux",
    "vulcan": "aarch64-linux",
}
ROOT_ALIASES = {
    "hera": ["darwinConfigurations.hera"],
    "clio": ["darwinConfigurations.clio"],
    "linux-fixture": ["homeConfigurations.johnw@aarch64-linux"],
    "shared-work": ["andoria", "homeConfigurations.jwiegley@x86_64-linux"],
    "vps": ["vps:nixosConfigurations.ovh-vps"],
    "vulcan": ["vulcan:checks.aarch64-linux.nix-config-reachin-compat"],
}
ROOT_KINDS = {
    "hera": "darwin-configuration",
    "clio": "darwin-configuration",
    "linux-fixture": "synthetic-home-manager",
    "shared-work": "shared-home-manager",
    "vps": "external-consumer",
    "vulcan": "external-consumer",
}


def manifest_for(paths: dict[str, list[str]]) -> dict[str, object]:
    python_entries = [
        {
            "path": path,
            "kind": "test" if path.endswith("-test.py") else "product",
            "tier": "pre-commit",
            "evidence": ["quality:unit"],
            "gap": None,
        }
        for path in paths["python"]
    ]
    shell_entries = [
        {
            "path": path,
            "kind": "test-driver" if path == "bin/quality" else "production",
            "tier": "pre-commit",
            "evidence": ["quality:unit"],
            "gap": None,
        }
        for path in paths["shell"]
    ]
    machines = [
        {"id": identifier, "root": root} for identifier, root in MACHINE_ROOTS.items()
    ]
    roots = []
    for identifier, system in ROOT_SYSTEMS.items():
        members = [
            machine["id"] for machine in machines if machine["root"] == identifier
        ]
        if identifier == "linux-fixture":
            members.append("linux")
        aliases = ROOT_ALIASES[identifier]
        roots.append(
            {
                "id": identifier,
                "kind": ROOT_KINDS[identifier],
                "system": system,
                "members": sorted(members),
                "aliases": aliases,
                "qualityEvidence": ["quality:unit"],
            }
        )
    systems = sorted(set(ROOT_SYSTEMS.values()))
    return {
        "schema": coverage_report.MANIFEST_SCHEMA,
        "declaredSystems": systems,
        "hosts": {
            "machineIds": machines,
            "groupRows": [
                {
                    "id": "andoria",
                    "members": [
                        "andoria-08",
                        "andoria-t2",
                        "delphi-3bd4",
                        "gpu-server",
                    ],
                    "root": "shared-work",
                    "evidenceLimits": ["group proxy does not prove member branches"],
                }
            ],
            "syntheticFixtures": [
                {
                    "id": "linux",
                    "alias": "johnw@aarch64-linux",
                    "root": "linux-fixture",
                }
            ],
        },
        "evaluationRoots": roots,
        "pythonInventory": python_entries,
        "shellOwnership": shell_entries,
        "gateDenominator": {
            "policy": {
                "authorityIds": ["quality:<suite>", "checks.<system>.<id>"],
                "invocationSurfaces": ["test"],
                "invocationSurfaceRule": "Invocation surfaces are aliases only.",
                "provenNegativeRule": "A replayable perturbation is required.",
            },
            "qualitySuites": ["unit"],
            "topLevelChecks": [{"system": system, "id": "unit"} for system in systems],
        },
        "nixFileReach": {
            "probes": [
                {
                    "id": "darwin-hera",
                    "tier": "pre-push",
                    "argv": [
                        "nix",
                        "eval",
                        "--no-eval-cache",
                        "--no-write-lock-file",
                        "-v",
                        "--log-format",
                        "internal-json",
                        "--raw",
                        ".#darwinConfigurations.hera.config.system.build.toplevel.drvPath",
                    ],
                    "normalForm": "One raw nix-darwin top-level drvPath string for Hera.",
                    "expectedRootFiles": ["flake.nix"],
                }
            ]
        },
        "outputApplicability": {
            "expectedTopLevelOutputNames": ["checks"],
            "outputKinds": [
                {
                    "kind": "checks",
                    "systems": systems,
                    "expectation": "derivation paths",
                    "expectedAttrs": ["unit"],
                }
            ],
        },
        "budgetsSeconds": {
            "pre-commit": 120,
            "pre-push": 900,
            "ci-on-demand": 1800,
        },
        "blindSpots": ["Structural assignment does not prove execution."],
    }


class RepositoryFixture(unittest.TestCase):
    def setUp(self) -> None:
        required_patcher = mock.patch.object(
            coverage_report, "REQUIRED_PROBE_IDS", frozenset({"darwin-hera"})
        )
        required_patcher.start()
        self.addCleanup(required_patcher.stop)
        self.temporary = tempfile.mkdtemp(prefix="coverage-report-test-")
        self.repo = Path(self.temporary) / "repo"
        self.repo.mkdir()
        self.env = coverage_report.clean_environment()
        self.git("init", "-q", ".")
        self.git("config", "user.name", "Coverage Test")
        self.git("config", "user.email", "coverage@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.write(".github/workflows/ci.yml", "name: fixture\n")
        self.write("Makefile", "test:\n\t@true\n")
        self.write("lefthook.yml", "pre-commit: {}\n")
        self.write("flake.nix", "{ value = 1; }\n")
        self.write(
            "tool.py",
            "def value():\n    return 1\n",
        )
        self.write(
            "bin/sample-test.py",
            "#!/usr/bin/env python3\n"
            "import unittest\n\n"
            "class Base(unittest.TestCase):\n"
            "    pass\n\n"
            "class Sample(Base):\n"
            "    def test_value(self):\n"
            "        self.assertEqual(1, 1)\n",
            executable=True,
        )
        self.write(
            "bin/pytool",
            "#!/usr/bin/env python3\nprint('ok')\n",
            executable=True,
        )
        self.write(
            "bin/sheller",
            "#!/usr/bin/env bash\nset -eu\n",
            executable=True,
        )
        self.write(
            "bin/quality",
            "#!/usr/bin/env bash\n"
            "set -eu\n"
            "if [[ ${1-} == --list ]]; then printf '%s\\n' unit; else exit 2; fi\n",
            executable=True,
        )
        self.git("add", ".")
        # Deliberately independent of the discovery implementation under test.
        initial_paths = {
            "nix": ["flake.nix"],
            "python": ["bin/pytool", "bin/sample-test.py", "tool.py"],
            "pythonTests": ["bin/sample-test.py"],
            "shell": ["bin/quality", "bin/sheller"],
        }
        self.manifest = manifest_for(initial_paths)
        self.write_json("test/coverage/manifest.json", self.manifest)
        self.git("add", "test/coverage/manifest.json")
        self.git("commit", "-qm", "fixture")

    def tearDown(self) -> None:
        shutil.rmtree(self.temporary, ignore_errors=True)

    def git(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *args],
            cwd=self.repo,
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def write(self, relative: str, text: str, *, executable: bool = False) -> Path:
        path = self.repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        if executable:
            path.chmod(0o755)
        return path

    def write_json(self, relative: str, value: object) -> Path:
        return self.write(relative, json.dumps(value, indent=2, sort_keys=True) + "\n")

    def refresh_manifest(self, value: dict[str, object]) -> None:
        self.write_json("test/coverage/manifest.json", value)
        self.git("add", "test/coverage/manifest.json")

    def ready_report(self) -> dict[str, object]:
        def timed_runner(argv, cwd, env, timeout):
            return subprocess.CompletedProcess(argv, 0, stdout="", stderr=""), 1.0

        timing = coverage_report.collect_pre_commit_timing(self.repo, 120, timed_runner)
        report = coverage_report.derive_report(self.repo, pre_commit_timing=timing)
        reach = report["measurements"]["nixFileReach"]
        reach["state"] = "observed"
        reach["reached"] = ["flake.nix"]
        reach["unreached"] = sorted(set(reach["denominator"]) - {"flake.nix"})
        for probe in reach["probes"]:
            probe["state"] = "observed"
            probe["paths"] = ["flake.nix"]
        timing_argv = report["provenance"]["commands"].pop()
        report["provenance"]["commands"].extend(
            probe["argv"] for probe in self.manifest["nixFileReach"]["probes"]
        )
        report["provenance"]["commands"].append(timing_argv)
        coverage_report.validate_report(
            report,
            manifest=coverage_report.validate_manifest(self.manifest),
            expected_structural=report["structural"],
            expected_projection_digest=report["sourceProjectionDigest"],
        )
        return report


class InventoryTests(RepositoryFixture):
    def test_inventory_is_git_tracked_and_sees_staged_files(self) -> None:
        self.write("staged.py", "value = 1\n")
        self.git("add", "staged.py")
        self.write("template.py.in", "value = @VALUE@\n")
        self.git("add", "template.py.in")
        self.write("untracked.py", "value = 2\n")
        files = coverage_report.discover_files(self.repo)
        self.assertIn("staged.py", files["python"])
        self.assertIn("template.py.in", files["python"])
        self.assertNotIn("untracked.py", files["python"])
        self.assertEqual(files["pythonTests"], ["bin/sample-test.py"])
        static = coverage_report.discover_python_static(
            self.repo, ["template.py.in"]
        )
        self.assertEqual(static, {"assertionCalls": [], "testCases": []})

    def test_python_template_without_placeholder_is_rejected(self) -> None:
        self.write("template.py.in", "value = 1\n")
        self.git("add", "template.py.in")
        with self.assertRaisesRegex(
            coverage_report.CoverageError, "contains no substitution placeholders"
        ):
            coverage_report.discover_python_static(self.repo, ["template.py.in"])

    def test_report_refuses_index_worktree_source_divergence(self) -> None:
        self.write("tool.py", "def value():\n    return 99\n")
        with self.assertRaisesRegex(
            coverage_report.CoverageError, "differs between index and worktree"
        ):
            coverage_report.derive_report(self.repo)

    def test_report_refuses_index_change_during_collection(self) -> None:
        writes = 0

        def runner(argv, cwd, env):
            nonlocal writes
            if list(argv) == ["git", "write-tree"]:
                writes += 1
                if writes == 2:
                    return subprocess.CompletedProcess(
                        argv, 0, stdout="1" * 40 + "\n", stderr=""
                    )
            return coverage_report.run_command(argv, cwd, env)

        with self.assertRaisesRegex(
            coverage_report.CoverageError, "index changed during"
        ):
            coverage_report.derive_report(self.repo, runner=runner)

    def test_worktree_symlink_cannot_leak_external_python_metadata(self) -> None:
        outside = Path(self.temporary) / "outside.py"
        outside.write_text(
            "import unittest\n"
            "class OutsideSecret(unittest.TestCase):\n"
            "    def test_external_name(self): self.assertTrue(True)\n",
            encoding="utf-8",
        )
        target = self.repo / "tool.py"
        target.unlink()
        target.symlink_to(outside)
        static = coverage_report.discover_python_static(self.repo, ["tool.py"])
        self.assertEqual(static["testCases"], [])
        self.assertNotIn("OutsideSecret", json.dumps(static))
        self.git("add", "tool.py")
        with self.assertRaisesRegex(coverage_report.CoverageError, "not a regular"):
            coverage_report.discover_files(self.repo)

    def test_static_unittest_cases_and_assertions_are_stable_ids(self) -> None:
        files = coverage_report.discover_files(self.repo)
        static = coverage_report.discover_python_static(self.repo, files["python"])
        self.assertEqual(static["testCases"], ["bin/sample-test.py::Sample.test_value"])
        self.assertEqual(
            static["assertionCalls"], ["bin/sample-test.py:9:9:assertEqual"]
        )

    def test_static_unittest_uses_module_classes_and_import_aliases(self) -> None:
        path = "bin/alias-collision-test.py"
        self.write(
            path,
            "from unittest import TestCase as Case\n"
            "class Real(Case):\n"
            "    class Collision:\n"
            "        def test_nested(self): pass\n"
            "    def test_real(self): self.assertTrue(True)\n"
            "class Container:\n"
            "    class Real(Case):\n"
            "        def test_hidden(self): self.assertTrue(True)\n",
        )
        self.git("add", path)
        static = coverage_report.discover_python_static(self.repo, [path])
        self.assertEqual(static["testCases"], [f"{path}::Real.test_real"])
        self.assertNotIn("test_nested", "\n".join(static["testCases"]))
        self.assertNotIn("test_hidden", "\n".join(static["testCases"]))

    def test_omitted_manifest_python_path_fails_collection(self) -> None:
        broken = copy.deepcopy(self.manifest)
        broken["pythonInventory"] = broken["pythonInventory"][:-1]
        self.refresh_manifest(broken)
        with self.assertRaisesRegex(coverage_report.CoverageError, "Python ownership"):
            coverage_report.derive_report(self.repo)

    def test_omitted_manifest_shell_path_fails_collection(self) -> None:
        broken = copy.deepcopy(self.manifest)
        broken["shellOwnership"] = broken["shellOwnership"][:-1]
        self.refresh_manifest(broken)
        with self.assertRaisesRegex(coverage_report.CoverageError, "shell ownership"):
            coverage_report.derive_report(self.repo)

    def test_duplicate_tier_assignment_is_rejected(self) -> None:
        broken = copy.deepcopy(self.manifest)
        broken["pythonInventory"].append(copy.deepcopy(broken["pythonInventory"][0]))
        with self.assertRaisesRegex(
            coverage_report.CoverageError, "duplicate ownership"
        ):
            coverage_report.validate_manifest(broken)

    def test_git_environment_is_scrubbed_from_every_runner_call(self) -> None:
        calls: list[dict[str, str]] = []

        def runner(argv, cwd, env):
            calls.append(dict(env))
            return coverage_report.run_command(argv, cwd, env)

        hostile = dict(os.environ)
        hostile.update(
            {
                "GIT_DIR": "/definitely/not/this/repo",
                "GIT_WORK_TREE": "/also/wrong",
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": "core.bare",
                "GIT_CONFIG_VALUE_0": "true",
            }
        )
        with mock.patch.dict(os.environ, hostile, clear=True):
            coverage_report.derive_report(self.repo, runner=runner)
        self.assertTrue(calls)
        for env in calls:
            self.assertFalse(
                any(key.startswith("GIT_") for key in env),
                f"Git injection leaked into subprocess environment: {env}",
            )


class NixEventTests(RepositoryFixture):
    def event(self, message: str) -> str:
        return "@nix " + json.dumps({"action": "msg", "level": 4, "msg": message})

    def test_successful_probe_collects_only_normalized_local_paths(self) -> None:
        stderr = "\n".join(
            [
                self.event("evaluating file '«nix-internal»/derivation-internal.nix'"),
                self.event("evaluating file '«builtin-flake-schemas»/flake.nix'"),
                self.event("evaluating file '«flakes-internal»/call-flake.nix'"),
                self.event(f"evaluating file '{self.repo / 'flake.nix'}'"),
                self.event("evaluating file '/nix/store/abc-source/external.nix'"),
            ]
        )
        drv = "/nix/store/" + "0" * 32 + "-fixture.drv"

        def runner(argv, cwd, env):
            return subprocess.CompletedProcess(argv, 0, stdout=drv, stderr=stderr)

        manifest = coverage_report.validate_manifest(self.manifest)
        probes = manifest["nixFileReach"]["probes"]
        progress = io.StringIO()
        with redirect_stderr(progress):
            result = coverage_report.collect_nix_file_reach(
                self.repo, probes, ["flake.nix"], manifest, runner
            )
        self.assertEqual(result["state"], "observed")
        self.assertEqual(result["evidenceKind"], "file-evaluation-start")
        self.assertEqual(result["reached"], ["flake.nix"])
        self.assertIn("probe darwin-hera (1/1)", progress.getvalue())

    def test_success_with_no_local_events_fails_closed(self) -> None:
        drv = "/nix/store/" + "0" * 32 + "-fixture.drv"

        def runner(argv, cwd, env):
            return subprocess.CompletedProcess(argv, 0, stdout=drv, stderr="")

        manifest = coverage_report.validate_manifest(self.manifest)
        probes = manifest["nixFileReach"]["probes"]
        with self.assertRaisesRegex(coverage_report.CoverageError, "without a local"):
            coverage_report.collect_nix_file_reach(
                self.repo, probes, ["flake.nix"], manifest, runner
            )

    def test_failed_probe_is_never_credited(self) -> None:
        stderr = self.event(f"evaluating file '{self.repo / 'flake.nix'}'")

        def runner(argv, cwd, env):
            return subprocess.CompletedProcess(argv, 1, stdout="", stderr=stderr)

        manifest = coverage_report.validate_manifest(self.manifest)
        probes = manifest["nixFileReach"]["probes"]
        with self.assertRaisesRegex(coverage_report.CoverageError, "failed with exit"):
            coverage_report.collect_nix_file_reach(
                self.repo, probes, ["flake.nix"], manifest, runner
            )

    def test_malformed_json_and_diagnostic_drift_fail_closed(self) -> None:
        with self.assertRaisesRegex(coverage_report.CoverageError, "malformed JSON"):
            coverage_report.parse_nix_evaluation_events(
                "@nix {broken", self.repo, {"flake.nix"}
            )
        drift = self.event(f"evaluation of file started: '{self.repo / 'flake.nix'}'")
        with self.assertRaisesRegex(coverage_report.CoverageError, "changed shape"):
            coverage_report.parse_nix_evaluation_events(
                drift.replace("evaluation of file started", "evaluating file started"),
                self.repo,
                {"flake.nix"},
            )

    def test_unrelated_evaluating_file_text_is_not_parser_drift(self) -> None:
        warning = self.event("warning: not evaluating file lists lazily")
        self.assertEqual(
            coverage_report.parse_nix_evaluation_events(
                warning, self.repo, {"flake.nix"}
            ),
            [],
        )

    def test_probe_stdout_contracts_fail_closed(self) -> None:
        manifest = coverage_report.validate_manifest(self.manifest)
        raw_probe = manifest["nixFileReach"]["probes"][0]
        with self.assertRaisesRegex(coverage_report.CoverageError, "raw drvPath"):
            coverage_report.validate_nix_probe_stdout(raw_probe, "1\n", manifest)
        with self.assertRaisesRegex(coverage_report.CoverageError, "system set"):
            coverage_report.validate_nix_probe_stdout(
                {"id": "root-checks"},
                json.dumps({"aarch64-darwin": ["unit"]}),
                manifest,
            )

    def test_probe_tier_and_timeout_contracts_are_load_bearing(self) -> None:
        manifest = coverage_report.validate_manifest(self.manifest)
        probes = manifest["nixFileReach"]["probes"]
        identifier, timeout_seconds = coverage_report.nix_probe_identity_and_timeout(
            probes[0]["argv"]
        )
        self.assertEqual(identifier, "darwin-hera")
        self.assertEqual(timeout_seconds, 600)
        with self.assertRaisesRegex(coverage_report.CoverageError, "selected zero"):
            coverage_report.collect_nix_file_reach(
                self.repo,
                probes,
                ["flake.nix"],
                manifest,
                lambda argv, cwd, env: subprocess.CompletedProcess(
                    argv, 0, stdout="", stderr=""
                ),
                tier="ci-on-demand",
            )

    def test_internal_json_framing_and_level_drift_fail_closed(self) -> None:
        message = f"evaluating file '{self.repo / 'flake.nix'}'"
        bare = json.dumps({"action": "msg", "level": 4, "msg": message})
        with self.assertRaisesRegex(coverage_report.CoverageError, "framing"):
            coverage_report.parse_nix_evaluation_events(bare, self.repo, {"flake.nix"})
        wrong_level = "@nix " + json.dumps(
            {"action": "msg", "level": 0, "msg": message}
        )
        with self.assertRaisesRegex(coverage_report.CoverageError, "level 4"):
            coverage_report.parse_nix_evaluation_events(
                wrong_level, self.repo, {"flake.nix"}
            )

    def test_probe_without_cache_disable_is_rejected(self) -> None:
        broken = copy.deepcopy(self.manifest)
        broken["nixFileReach"]["probes"][0]["argv"].remove("--no-eval-cache")
        with self.assertRaisesRegex(coverage_report.CoverageError, "cache/logging"):
            coverage_report.validate_manifest(broken)
        broken = copy.deepcopy(self.manifest)
        broken["nixFileReach"]["probes"][0]["argv"].remove("--no-write-lock-file")
        with self.assertRaisesRegex(coverage_report.CoverageError, "cache/logging"):
            coverage_report.validate_manifest(broken)

    def test_missing_mandatory_probe_contract_is_rejected(self) -> None:
        with (
            mock.patch.object(
                coverage_report,
                "REQUIRED_PROBE_IDS",
                frozenset({"darwin-hera", "root-checks"}),
            ),
            self.assertRaisesRegex(
                coverage_report.CoverageError, "missing=.*root-checks"
            ),
        ):
            coverage_report.validate_manifest(self.manifest)

    def test_probe_credential_option_is_outside_argv_allowlist(self) -> None:
        broken = copy.deepcopy(self.manifest)
        argv = broken["nixFileReach"]["probes"][0]["argv"]
        argv[2:2] = ["--option", "access-tokens", "github.com=not-a-real-token"]
        with self.assertRaisesRegex(
            coverage_report.CoverageError, "non-allowlisted"
        ) as raised:
            coverage_report.validate_manifest(broken)
        self.assertNotIn("not-a-real-token", str(raised.exception))

    def test_failed_child_diagnostics_are_not_copied_to_errors(self) -> None:
        marker = "ghp_012345678901234567890123456789"

        def runner(argv, cwd, env):
            return subprocess.CompletedProcess(argv, 1, stdout="", stderr=marker)

        with self.assertRaisesRegex(coverage_report.CoverageError, "exit 1") as raised:
            coverage_report._checked_command(
                runner, ["git", "status"], self.repo, description="fixture"
            )
        self.assertNotIn(marker, str(raised.exception))

    def test_probe_source_cannot_traverse_outside_repository(self) -> None:
        broken = copy.deepcopy(self.manifest)
        argv = broken["nixFileReach"]["probes"][0]["argv"]
        target_index = next(
            index for index, argument in enumerate(argv) if "#" in argument
        )
        argv[target_index] = "./../../outside#fixture"
        with self.assertRaisesRegex(coverage_report.CoverageError, "normalized"):
            coverage_report.validate_manifest(broken)

    def test_probe_explicit_path_ref_is_rejected(self) -> None:
        broken = copy.deepcopy(self.manifest)
        argv = broken["nixFileReach"]["probes"][0]["argv"]
        target_index = next(
            index for index, argument in enumerate(argv) if "#" in argument
        )
        argv[target_index] = "path:" + argv[target_index]
        with self.assertRaisesRegex(
            coverage_report.CoverageError, "copy untracked or Git metadata"
        ):
            coverage_report.validate_manifest(broken)

    def test_probe_id_is_bound_to_its_exact_target(self) -> None:
        broken = copy.deepcopy(self.manifest)
        argv = broken["nixFileReach"]["probes"][0]["argv"]
        target_index = next(
            index for index, argument in enumerate(argv) if "#" in argument
        )
        argv[target_index] = (
            ".#darwinConfigurations.clio.config.system.build.toplevel.drvPath"
        )
        with self.assertRaisesRegex(coverage_report.CoverageError, "not bound"):
            coverage_report.validate_manifest(broken)

    def test_successful_probe_must_reach_its_named_root(self) -> None:
        stderr = self.event(f"evaluating file '{self.repo / 'b.nix'}'")
        drv = "/nix/store/" + "0" * 32 + "-fixture.drv"

        def runner(argv, cwd, env):
            return subprocess.CompletedProcess(argv, 0, stdout=drv, stderr=stderr)

        manifest = coverage_report.validate_manifest(self.manifest)
        probes = manifest["nixFileReach"]["probes"]
        with self.assertRaisesRegex(coverage_report.CoverageError, "omitted expected"):
            coverage_report.collect_nix_file_reach(
                self.repo, probes, ["flake.nix", "b.nix"], manifest, runner
            )


class ArtifactTests(RepositoryFixture):
    def test_sensitive_keys_assignments_and_tokens_are_rejected(self) -> None:
        for value in (
            {"password": "not-even-real"},
            {"token": "not-even-real"},
            {"value": "raw values are not an artifact field"},
            {"note": "API_TOKEN=not-even-real"},
            {"note": "ghp_012345678901234567890123456789"},
        ):
            with self.subTest(value=value):
                with self.assertRaises(coverage_report.CoverageError):
                    coverage_report.sensitive_scan(value)

    def test_unknown_expensive_measurements_are_not_passes(self) -> None:
        report = coverage_report.derive_report(self.repo)
        self.assertEqual(report["measurements"]["pythonDynamic"]["state"], "unknown")
        report["measurements"]["pythonDynamic"]["state"] = "observed"
        manifest = coverage_report.validate_manifest(self.manifest)
        with self.assertRaisesRegex(coverage_report.CoverageError, "must remain"):
            coverage_report.validate_report(
                report, manifest=manifest, expected_structural=report["structural"]
            )

    def test_non_observed_nix_reach_states_never_pass_validation(self) -> None:
        manifest = coverage_report.validate_manifest(self.manifest)
        for state in ("failed", "skipped", "not-run"):
            with self.subTest(state=state):
                report = coverage_report.derive_report(self.repo)
                report["measurements"]["nixFileReach"]["state"] = state
                for probe in report["measurements"]["nixFileReach"]["probes"]:
                    probe["state"] = state
                with self.assertRaisesRegex(
                    coverage_report.CoverageError, "observed or explicit unknown"
                ):
                    coverage_report.validate_report(report, manifest=manifest)

    def test_timing_measurement_is_observed_and_budget_enforced(self) -> None:
        def measured(argv, cwd, env, timeout):
            return subprocess.CompletedProcess(argv, 0, stdout="", stderr=""), 26.33

        timing = coverage_report.collect_pre_commit_timing(self.repo, 120, measured)
        report = coverage_report.derive_report(self.repo, pre_commit_timing=timing)
        timing = report["measurements"]["timing"]
        self.assertEqual(timing["state"], "observed")
        self.assertEqual(timing["records"][0]["seconds"], 26.33)
        self.assertEqual(timing["records"][0]["budgetSeconds"], 120)

        def exceeded(argv, cwd, env, timeout):
            return subprocess.CompletedProcess(argv, 0, stdout="", stderr=""), 120.001

        with self.assertRaisesRegex(coverage_report.CoverageError, "exceeding"):
            coverage_report.collect_pre_commit_timing(self.repo, 120, exceeded)

        def timed_out(argv, cwd, env, timeout):
            raise subprocess.TimeoutExpired(argv, timeout)

        with self.assertRaisesRegex(coverage_report.CoverageError, "deadline"):
            coverage_report.collect_pre_commit_timing(self.repo, 120, timed_out)

    def test_artifact_summary_reports_named_counts_and_unknowns(self) -> None:
        report = self.ready_report()
        path = self.write_json("test/baseline/coverage-fixture.json", report)
        self.git("add", path.relative_to(self.repo).as_posix())
        summary = coverage_report.artifact_summary(self.repo, path)
        self.assertIn("nix-file-evaluation-start=1/1", summary)
        self.assertIn("python-inventory=3", summary)
        self.assertIn("shell-inventory=2", summary)
        self.assertIn("pre-commit-core=1.0/120s", summary)
        self.assertIn("pythonDynamic", summary)

    def test_source_projection_digest_records_staged_source_change(self) -> None:
        before = coverage_report.derive_report(self.repo)["sourceProjectionDigest"]
        self.write("tool.py", "def value():\n    return 2\n")
        self.git("add", "tool.py")
        after = coverage_report.derive_report(self.repo)["sourceProjectionDigest"]
        self.assertNotEqual(before, after)

    def test_source_revision_must_be_a_reachable_ancestor(self) -> None:
        path = coverage_report.write_artifact(self.repo)
        self.git("add", path.relative_to(self.repo).as_posix())
        self.git("commit", "-qm", "coverage baseline")
        report = coverage_report.load_json(path)
        report["sourceBaseRev"] = "0" * 40
        self.write_json(path.relative_to(self.repo).as_posix(), report)
        self.git("add", path.relative_to(self.repo).as_posix())
        with self.assertRaisesRegex(
            coverage_report.CoverageError, "reachable ancestor"
        ):
            coverage_report.check_artifact(self.repo)

    def test_runtime_tool_identity_drift_invalidates_artifact(self) -> None:
        report = self.ready_report()
        path = self.write_json("test/baseline/coverage-fixture.json", report)
        self.git("add", path.relative_to(self.repo).as_posix())
        self.git("commit", "-qm", "coverage baseline")

        def runner(argv, cwd, env):
            if list(argv) == ["nix", "--version"]:
                return subprocess.CompletedProcess(
                    argv, 0, stdout="nix (drifted) 99.0\n", stderr=""
                )
            return coverage_report.run_command(argv, cwd, env)

        with self.assertRaisesRegex(coverage_report.CoverageError, "tool identity"):
            coverage_report.check_artifact(self.repo, runner=runner)

    def test_tracked_artifact_symlink_is_rejected_without_following(self) -> None:
        outside = Path(self.temporary) / "outside.json"
        outside.write_text(
            json.dumps(coverage_report.derive_report(self.repo)), encoding="utf-8"
        )
        path = self.repo / "test/baseline/coverage-fixture.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.symlink_to(outside)
        self.git("add", path.relative_to(self.repo).as_posix())
        self.git("commit", "-qm", "tracked artifact symlink")
        with self.assertRaisesRegex(
            coverage_report.CoverageError, "not a regular file"
        ):
            coverage_report.check_artifact(self.repo)

    def test_check_rejects_structural_regression(self) -> None:
        report = self.ready_report()
        artifact = self.write_json("test/baseline/coverage-fixture.json", report)
        self.git("add", artifact.relative_to(self.repo).as_posix())
        self.git("commit", "-qm", "coverage artifact")
        coverage_report.check_artifact(self.repo)
        broken = copy.deepcopy(report)
        broken["structural"]["files"]["python"].remove("tool.py")
        self.write_json("test/baseline/coverage-fixture.json", broken)
        self.git("add", "test/baseline/coverage-fixture.json")
        with self.assertRaisesRegex(coverage_report.CoverageError, "regress"):
            coverage_report.check_artifact(self.repo)

    def test_check_allows_content_only_drift_until_expensive_refresh(self) -> None:
        report = self.ready_report()
        artifact = self.write_json("test/baseline/coverage-fixture.json", report)
        self.git("add", artifact.relative_to(self.repo).as_posix())
        self.git("commit", "-qm", "coverage artifact")
        self.write("tool.py", "def value():\n    return 99\n")
        self.git("add", "tool.py")
        self.assertNotEqual(
            coverage_report.derive_report(self.repo)["sourceProjectionDigest"],
            report["sourceProjectionDigest"],
        )
        coverage_report.check_artifact(self.repo)

    def test_check_allows_unstaged_content_not_read_from_worktree(self) -> None:
        report = self.ready_report()
        artifact = self.write_json("test/baseline/coverage-fixture.json", report)
        self.git("add", artifact.relative_to(self.repo).as_posix())
        self.git("commit", "-qm", "coverage artifact")
        self.write("flake.nix", "{ value = 99; }\n")
        coverage_report.check_artifact(self.repo)

    def test_check_rejects_unstaged_quality_driver(self) -> None:
        report = self.ready_report()
        artifact = self.write_json("test/baseline/coverage-fixture.json", report)
        self.git("add", artifact.relative_to(self.repo).as_posix())
        self.git("commit", "-qm", "coverage artifact")
        self.write("bin/quality", "#!/usr/bin/env bash\nprintf '%s\\n' changed\n")
        with self.assertRaisesRegex(
            coverage_report.CoverageError, "tracked source differs.*bin/quality"
        ):
            coverage_report.check_artifact(self.repo)

    def test_check_rejects_nix_reach_regression_against_head_artifact(self) -> None:
        self.write("b.nix", "{ value = 2; }\n")
        self.git("add", "b.nix")
        baseline = self.ready_report()
        reach = baseline["measurements"]["nixFileReach"]
        reach["reached"] = ["b.nix", "flake.nix"]
        reach["unreached"] = []
        reach["probes"][0]["paths"] = ["b.nix", "flake.nix"]
        path = self.write_json("test/baseline/coverage-fixture.json", baseline)
        self.git("add", path.relative_to(self.repo).as_posix())
        self.git("commit", "-qm", "coverage baseline")

        regressed = copy.deepcopy(baseline)
        regressed["sourceBaseRev"] = self.git("rev-parse", "HEAD").stdout.strip()
        regressed_reach = regressed["measurements"]["nixFileReach"]
        regressed_reach["reached"] = ["flake.nix"]
        regressed_reach["unreached"] = ["b.nix"]
        regressed_reach["probes"][0]["paths"] = ["flake.nix"]
        self.write_json(path.relative_to(self.repo).as_posix(), regressed)
        self.git("add", path.relative_to(self.repo).as_posix())
        with self.assertRaisesRegex(coverage_report.CoverageError, "reach regressed"):
            coverage_report.check_artifact(self.repo)

    def test_throwing_stub_role_change_is_the_only_reach_exemption(self) -> None:
        previous = self.ready_report()
        previous_reach = previous["measurements"]["nixFileReach"]
        previous_reach["denominator"] = ["config/ai/flake.nix", "flake.nix"]
        previous_reach["reached"] = ["config/ai/flake.nix", "flake.nix"]
        previous_reach["unreached"] = []
        previous_reach["probes"][0]["paths"] = [
            "config/ai/flake.nix",
            "flake.nix",
        ]

        current = copy.deepcopy(previous)
        current_reach = current["measurements"]["nixFileReach"]
        current_reach["reached"] = ["flake.nix"]
        current_reach["unreached"] = ["config/ai/flake.nix"]
        current_reach["probes"][0]["paths"] = ["flake.nix"]
        coverage_report.validate_non_regression(current, previous)

        current_reach["denominator"].append("other.nix")
        previous_reach["denominator"].append("other.nix")
        previous_reach["reached"].append("other.nix")
        previous_reach["probes"][0]["paths"].append("other.nix")
        current_reach["unreached"].append("other.nix")
        with self.assertRaisesRegex(coverage_report.CoverageError, "other.nix"):
            coverage_report.validate_non_regression(current, previous)

    def test_ratio_regression_is_deletion_aware_but_rejects_new_unreached_file(
        self,
    ) -> None:
        previous = self.ready_report()
        previous_reach = previous["measurements"]["nixFileReach"]
        previous_reach["denominator"] = ["a.nix", "b.nix"]
        previous_reach["reached"] = ["a.nix"]
        previous_reach["unreached"] = ["b.nix"]

        deleted = copy.deepcopy(previous)
        deleted_reach = deleted["measurements"]["nixFileReach"]
        deleted_reach["denominator"] = ["b.nix"]
        deleted_reach["reached"] = []
        deleted_reach["unreached"] = ["b.nix"]
        coverage_report.validate_non_regression(deleted, previous)

        expanded = copy.deepcopy(previous)
        expanded_reach = expanded["measurements"]["nixFileReach"]
        expanded_reach["denominator"] = ["a.nix", "b.nix", "c.nix"]
        expanded_reach["reached"] = ["a.nix"]
        expanded_reach["unreached"] = ["b.nix", "c.nix"]
        with self.assertRaisesRegex(coverage_report.CoverageError, "ratio regressed"):
            coverage_report.validate_non_regression(expanded, previous)

    def test_live_comparison_recollects_before_accepting_baseline(self) -> None:
        baseline = self.ready_report()
        path = self.write_json("test/baseline/coverage-fixture.json", baseline)
        self.git("add", path.relative_to(self.repo).as_posix())
        self.git("commit", "-qm", "coverage baseline")
        event = "@nix " + json.dumps(
            {
                "action": "msg",
                "level": 4,
                "msg": f"evaluating file '{self.repo.resolve() / 'flake.nix'}'",
            }
        )
        drv = "/nix/store/" + "0" * 32 + "-fixture.drv"

        def probe_runner(argv, cwd, env):
            return subprocess.CompletedProcess(argv, 0, stdout=drv, stderr=event)

        current = coverage_report.compare_live_coverage(
            self.repo, probe_runner=probe_runner
        )
        self.assertEqual(current["measurements"]["nixFileReach"]["state"], "observed")

    def test_manifest_digest_change_invalidates_artifact(self) -> None:
        report = coverage_report.derive_report(self.repo)
        changed = copy.deepcopy(self.manifest)
        changed["blindSpots"].append("Newly identified blind spot.")
        normalized = coverage_report.validate_manifest(changed)
        with self.assertRaisesRegex(coverage_report.CoverageError, "manifest digest"):
            coverage_report.validate_report(
                report,
                manifest=normalized,
                expected_structural=report["structural"],
            )

    def test_report_validation_runs_sensitive_scan_and_argv_schema(self) -> None:
        manifest = coverage_report.validate_manifest(self.manifest)
        report = coverage_report.derive_report(self.repo)
        report["measurements"]["pythonDynamic"]["reason"] = "API_TOKEN=injected"
        with self.assertRaisesRegex(coverage_report.CoverageError, "credential-shaped"):
            coverage_report.validate_report(
                report,
                manifest=manifest,
                expected_structural=report["structural"],
            )
        report = coverage_report.derive_report(self.repo)
        report["provenance"]["commands"][0] = "git ls-files"
        with self.assertRaisesRegex(coverage_report.CoverageError, "must be an array"):
            coverage_report.validate_report(
                report,
                manifest=manifest,
                expected_structural=report["structural"],
            )

    def test_write_creates_one_schema_valid_initial_artifact(self) -> None:
        path = coverage_report.write_artifact(self.repo)
        self.assertRegex(path.name, r"^coverage-[0-9a-f]{12}[.]json$")
        self.assertEqual(path.parent, self.repo / "test/baseline")
        value = coverage_report.load_json(path)
        manifest = coverage_report.validate_manifest(self.manifest)
        coverage_report.validate_report(
            value,
            manifest=manifest,
            expected_structural=value["structural"],
        )
        self.assertEqual(list(path.parent.glob("coverage-*.json")), [path])
        with self.assertRaisesRegex(coverage_report.CoverageError, "untracked"):
            coverage_report.write_artifact(self.repo)

    def test_write_replaces_the_sole_committed_artifact(self) -> None:
        path = coverage_report.write_artifact(self.repo)
        self.git("add", path.relative_to(self.repo).as_posix())
        self.git("commit", "-qm", "coverage baseline")
        old = coverage_report.load_json(path)
        old["sourceBaseRev"] = "0" * 40
        self.write_json(path.relative_to(self.repo).as_posix(), old)
        written = coverage_report.write_artifact(self.repo)
        self.assertEqual(written, path)
        self.assertNotEqual(coverage_report.load_json(path)["sourceBaseRev"], "0" * 40)

    def test_unknown_artifact_is_not_gate_ready(self) -> None:
        path = coverage_report.write_artifact(self.repo)
        self.git("add", path.relative_to(self.repo).as_posix())
        self.git("commit", "-qm", "coverage baseline")
        with self.assertRaisesRegex(coverage_report.CoverageError, "not gate-ready"):
            coverage_report.check_artifact(self.repo)

    def test_check_requires_exactly_one_committed_artifact(self) -> None:
        with self.assertRaisesRegex(coverage_report.CoverageError, "no committed"):
            coverage_report.check_artifact(self.repo)
        report = coverage_report.derive_report(self.repo)
        for name in ("coverage-one.json", "coverage-two.json"):
            self.write_json(f"test/baseline/{name}", report)
            self.git("add", f"test/baseline/{name}")
        self.git("commit", "-qm", "two invalid candidates")
        with self.assertRaisesRegex(coverage_report.CoverageError, "at most one"):
            coverage_report.check_artifact(self.repo)

    def test_write_refuses_symlinked_baseline_directory(self) -> None:
        outside = Path(self.temporary) / "outside"
        outside.mkdir()
        baseline = self.repo / "test/baseline"
        baseline.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(coverage_report.CoverageError, "is a symlink"):
            coverage_report.write_artifact(self.repo)
        self.assertEqual(list(outside.iterdir()), [])

    def test_atomic_write_replaces_from_same_directory(self) -> None:
        path = self.write("test/baseline/coverage-fixture.json", "old\n")
        calls: list[tuple[str, str]] = []

        def replace(source: str, target: str) -> None:
            calls.append((source, target))
            os.replace(source, target)

        coverage_report.atomic_write_json(path, {"schema": "fixture"}, replace=replace)
        self.assertEqual(len(calls), 1)
        source, target = calls[0]
        self.assertEqual(Path(source).parent, path.parent)
        self.assertNotEqual(Path(source), path)
        self.assertEqual(Path(target), path)
        self.assertEqual(json.loads(path.read_text()), {"schema": "fixture"})

    def test_atomic_replace_failure_preserves_original_and_cleans_temp(self) -> None:
        path = self.write("test/baseline/coverage-fixture.json", "original bytes\n")

        def fail_replace(source: str, target: str) -> None:
            raise OSError("injected replace failure")

        with self.assertRaisesRegex(coverage_report.CoverageError, "injected"):
            coverage_report.atomic_write_json(
                path, {"schema": "fixture"}, replace=fail_replace
            )
        self.assertEqual(path.read_text(), "original bytes\n")
        self.assertEqual(
            list(path.parent.glob(f".{path.name}.*")),
            [],
            "failed writes must not leave a temporary artifact",
        )

    def test_directory_sync_failure_reports_that_new_artifact_is_installed(
        self,
    ) -> None:
        path = self.write("test/baseline/coverage-fixture.json", "old\n")
        calls = 0

        def fsync(descriptor: int) -> None:
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("injected directory fsync failure")
            os.fsync(descriptor)

        with self.assertRaisesRegex(
            coverage_report.CoverageError, "artifact installed"
        ):
            coverage_report.atomic_write_json(path, {"schema": "new"}, fsync=fsync)
        self.assertEqual(json.loads(path.read_text()), {"schema": "new"})

    def test_directory_open_failure_reports_that_new_artifact_is_installed(
        self,
    ) -> None:
        path = self.write("test/baseline/coverage-fixture.json", "old\n")

        def fail_open(path: Path, flags: int) -> int:
            raise OSError("injected directory open failure")

        with self.assertRaisesRegex(
            coverage_report.CoverageError, "artifact installed"
        ):
            coverage_report.atomic_write_json(
                path, {"schema": "new"}, open_directory=fail_open
            )
        self.assertEqual(json.loads(path.read_text()), {"schema": "new"})


class CliTests(unittest.TestCase):
    def test_default_and_explicit_print_are_equivalent_json(self) -> None:
        outputs = []
        for argv in ([], ["--print"]):
            stream = io.StringIO()
            with (
                mock.patch.object(
                    coverage_report, "derive_report", return_value={"safe": True}
                ),
                redirect_stdout(stream),
            ):
                self.assertEqual(coverage_report.main(argv), 0)
            outputs.append(stream.getvalue())
        self.assertEqual(outputs[0], outputs[1])
        self.assertEqual(json.loads(outputs[0]), {"safe": True})

    def test_check_and_write_dispatch_to_distinct_operations(self) -> None:
        repo = Path(coverage_report.__file__).resolve().parent.parent
        artifact = repo / "test/baseline/coverage-fixture.json"
        for argv, function_name, prefix in (
            (["--check"], "check_artifact", "coverage-report:"),
            (
                ["--write", "--collect-nix-reach", "--measure-pre-commit"],
                "write_artifact",
                "coverage-report: wrote",
            ),
        ):
            stream = io.StringIO()
            with (
                mock.patch.object(
                    coverage_report, function_name, return_value=artifact
                ) as operation,
                mock.patch.object(
                    coverage_report,
                    "artifact_summary",
                    return_value="coverage-report: fixture summary",
                ),
                redirect_stdout(stream),
            ):
                self.assertEqual(coverage_report.main(argv), 0)
            operation.assert_called_once()
            self.assertIn(prefix, stream.getvalue())

    def test_write_refuses_to_erase_observations_with_structural_only_run(self) -> None:
        stderr = io.StringIO()
        with (
            mock.patch.object(coverage_report, "write_artifact") as operation,
            mock.patch("sys.stderr", stderr),
        ):
            self.assertEqual(coverage_report.main(["--write"]), 2)
        operation.assert_not_called()
        self.assertIn("requires --collect-nix-reach", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
