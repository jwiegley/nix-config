#!/usr/bin/env python3

import base64
import contextlib
import copy
import hashlib
import io
import json
import os
import re
import runpy
import select
import shutil
import socket
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import types
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock
from urllib.parse import urlsplit


REPO = Path(__file__).resolve().parents[2]
BIN = REPO / "bin"
SCRIPT = BIN / "update-overlay"
UPDATE_AGENTS = BIN / "update"
MODULE = runpy.run_path(str(SCRIPT))
GitHubClient = MODULE["GitHubClient"]
HashComputer = MODULE["HashComputer"]
CandidateRejected = MODULE["CandidateRejected"]
PypiClient = MODULE["PypiClient"]
NpmRegistryClient = MODULE["NpmRegistryClient"]
SourceTransaction = MODULE["SourceTransaction"]
load_source_catalog = MODULE["load_source_catalog"]
load_pi_normalization_contract = MODULE.get("load_pi_normalization_contract")
pi_npm_lock_flags = MODULE.get("pi_npm_lock_flags")
normalize_pi_manifest = MODULE.get("normalize_pi_manifest")
validate_npm_manifest_lock = MODULE.get("validate_npm_manifest_lock")
generate_npm_lock = MODULE.get("generate_npm_lock")
npm_lock_documents_equal = MODULE.get("npm_lock_documents_equal")
read_npm_tarball_manifest = MODULE.get("read_npm_tarball_manifest")
verify_npm_integrity = MODULE.get("verify_npm_integrity")
registry_only_proxy = MODULE.get("registry_only_proxy")
update_npm_lock_target = MODULE.get("update_npm_lock_target")
normalize_prime_agent_lock = MODULE.get("normalize_prime_agent_lock")
prime_agent_lock_is_normalized = MODULE.get("_prime_agent_lock_is_normalized")
require_detached_linked_worktree = MODULE["require_detached_linked_worktree"]
sync_flake_projections = MODULE["sync_flake_projections"]
print_catalog_change = MODULE["_print_catalog_change"]
update_main = MODULE["main"]
ANSI_ESCAPE_RE = MODULE["ANSI_ESCAPE_RE"]
resolve_flake_input_version = MODULE.get("resolve_flake_input_version")
validate_catalog_target = MODULE["validate_catalog_target"]
update_catalog_target = MODULE["update_catalog_target"]
update_npm_flake_target = MODULE.get("update_npm_flake_target")
update_pypi_artifact_target = MODULE.get("update_pypi_artifact_target")
prepare_update_target = MODULE.get("prepare_update_target")
update_github_release_asset_target = MODULE.get("update_github_release_asset_target")
update_github_commit_artifact_target = MODULE.get(
    "update_github_commit_artifact_target"
)
update_github_projection_target = MODULE.get("update_github_projection_target")
snapshot_catalog_record_isolation = MODULE.get("snapshot_catalog_record_isolation")
validate_catalog_record_isolation = MODULE.get("validate_catalog_record_isolation")
enforce_catalog_record_isolation = MODULE.get("enforce_catalog_record_isolation")

PI_NORMALIZATION_TARGETS = frozenset(
    json.loads(
        (
            SCRIPT.parent.parent / "packages/pi-gallery/normalization-policy.json"
        ).read_text()
    )["targets"]
)

VENDOR_HASH = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="
PYPI_CANDIDATE_BUILDS = {
    "aiologic": ("culsans", "python"),
    "aiperf": ("aiperf", "pkg"),
    "choreographer": ("aiperf", "pkg"),
    "cohere-melody": ("cohere-melody", "python"),
    "crick": ("aiperf", "pkg"),
    "espeakng-loader": ("mlx-audio", "python"),
    "mlx": ("omlx", "pkg"),
    "mlx-embeddings": ("omlx", "pkg"),
    "mtplx": ("mtplx", "pkg"),
    "phonemizer-fork": ("mlx-audio", "python"),
    "plasma-fractal": ("plasma-fractal", "pkg"),
    "plasma-wiki": ("plasma-fractal", "pkg"),
    "pyloudnorm": ("mlx-audio", "python"),
    "standard-distutils": ("pymssql", "python"),
    "unisessions": ("unisessions", "pkg"),
    "vllm-mlx": ("vllm-mlx", "pkg"),
}


def write_minimal_catalog(root):
    (root / "sources").mkdir()
    url = "https://example.invalid/actual-1.0.0.tar.gz"
    (root / "sources/test.json").write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "sources": {
                    "actual": {
                        "version": "1.0.0",
                        "source": {
                            "fetcher": "fetchurl",
                            "url": url,
                            "args": {"url": url, "hash": "sha256-old"},
                        },
                        "update": {
                            "kind": "url-release",
                            "policy": "automatic",
                        },
                    }
                },
            },
            indent=2,
        )
        + "\n"
    )


class UpdateCliTests(unittest.TestCase):
    def test_catalog_change_suppresses_equal_versions_and_reports_changed_refs(self):
        with mock.patch.dict(os.environ):
            os.environ.pop("UPDATE_VERBOSE", None)
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                print_catalog_change("project", "1.0.0", "1.0.0")
            self.assertEqual(ANSI_ESCAPE_RE.sub("", output.getvalue()), "")

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                print_catalog_change(
                    "project",
                    "1.0.0",
                    "1.0.0",
                    old_ref="1" * 40,
                    new_ref="2" * 40,
                )
            self.assertEqual(
                ANSI_ESCAPE_RE.sub("", output.getvalue()),
                "catalog/project 11111111 → 22222222 ✓\n",
            )

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                print_catalog_change(
                    "project",
                    "1.0.0",
                    "1.0.0",
                    old_ref="12345678" + "a" * 32,
                    new_ref="12345678" + "b" * 32,
                )
            self.assertEqual(
                ANSI_ESCAPE_RE.sub("", output.getvalue()),
                "catalog/project 12345678a → 12345678b ✓\n",
            )

        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            print_catalog_change(
                "project",
                "1.0.0",
                "1.0.0",
                args=SimpleNamespace(verbose=True),
            )
        self.assertEqual(
            ANSI_ESCAPE_RE.sub("", output.getvalue()),
            "catalog/project 1.0.0 → 1.0.0 ✓\n",
        )

    def test_record_target_change_emits_structured_accepted_result(self):
        target = {
            "kind": "github-commit",
            "version": "1.0.0",
            "_record": {
                "source": {"args": {"rev": "2" * 40}},
                "update": {"kind": "github-commit"},
            },
        }
        with (
            mock.patch.object(
                sys,
                "argv",
                [
                    str(SCRIPT),
                    "--record-target-change",
                    "project",
                    "--old-version",
                    "1.0.0",
                    "--old-revision",
                    "1" * 40,
                ],
            ),
            mock.patch.dict(os.environ, {"UPDATE_AGENTS_CANDIDATE": "1"}),
            mock.patch.dict(
                update_main.__globals__,
                {
                    "require_detached_linked_worktree": mock.Mock(),
                    "load_source_catalog": mock.Mock(
                        return_value={"project": target}
                    ),
                },
            ),
        ):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(update_main(), 0)
        self.assertEqual(
            json.loads(output.getvalue()),
            {"name": "project", "old": "11111111", "new": "22222222"},
        )

    def test_flake_sync_cli_reports_same_version_revision_change(self):
        for kind in ("flake-input", "flake-input+build", "flake-input+copy"):
            with self.subTest(kind=kind):
                before = {
                    "kind": kind,
                    "version": "1.0.0",
                    "_record": {
                        "source": {
                            "fetcher": "fetchTree",
                            "args": {"rev": "1" * 40},
                        },
                        "update": {"input": "project", "kind": kind},
                    },
                }
                after = copy.deepcopy(before)
                after["_record"]["source"]["args"]["rev"] = "2" * 40
                with (
                    mock.patch.object(sys, "argv", [
                        str(SCRIPT),
                        "--sync-flake-projections",
                        "project",
                    ]),
                    mock.patch.dict(
                        os.environ,
                        {"UPDATE_AGENTS_CANDIDATE": "1", "UPDATE_VERBOSE": ""},
                    ),
                    mock.patch.dict(
                        update_main.__globals__,
                        {
                            "require_detached_linked_worktree": mock.Mock(),
                            "load_source_catalog": mock.Mock(
                                side_effect=[
                                    {"project": before},
                                    {"project": after},
                                ]
                            ),
                            "sync_flake_projections": mock.Mock(return_value=1),
                        },
                    ),
                ):
                    output = io.StringIO()
                    with contextlib.redirect_stdout(output):
                        self.assertEqual(update_main(), 0)
                self.assertEqual(
                    ANSI_ESCAPE_RE.sub("", output.getvalue()),
                    "catalog/project 11111111 → 22222222 ✓\n",
                )

    def test_retired_ai_nix_flags_are_rejected(self):
        for flag in (
            "--ai-nix-dir",
            "--no-ai-nix",
            "--only-ai-nix",
            "--no-ai-nix-advice",
        ):
            with self.subTest(flag=flag):
                result = subprocess.run(
                    [sys.executable, str(SCRIPT), flag, "--all"],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 2)
                self.assertIn("unrecognized arguments", result.stderr)

    def test_retired_overlay_options_and_unknown_ids_are_rejected(self):
        cases = (
            (
                ["--all", "--overlays-dir", "overlays/ai"],
                "unrecognized arguments: --overlays-dir",
            ),
            (
                ["--all", "--no-build"],
                "--no-build is no longer supported",
            ),
            (
                ["definitely-not-a-catalog-id"],
                "unknown catalog target ID(s): definitely-not-a-catalog-id",
            ),
        )
        for arguments, expected in cases:
            with self.subTest(arguments=arguments):
                result = subprocess.run(
                    [sys.executable, str(SCRIPT), *arguments],
                    cwd=SCRIPT.parent.parent,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 2)
                self.assertIn(expected, result.stderr)

    def test_catalog_selection_preserves_manual_direct_and_filtered_all(self):
        def target(policy, executor):
            return {
                "executor": executor,
                "kind": "url-release",
                "_record": {"update": {"kind": "url-release", "policy": policy}},
            }

        catalog = {
            "automatic-direct": target("automatic", "update-overlay"),
            "automatic-delegated": target("automatic", "update"),
            "manual-direct": target("manual", "update-overlay"),
        }
        observed = []
        mutate_path = None
        reject = False

        def fake_update(name, *_args):
            observed.append(name)
            if reject:
                raise CandidateRejected("provisional")
            if mutate_path is not None:
                transaction = _args[-1]
                transaction.watch(mutate_path)
                mutate_path.write_text("changed\n")
            return "skipped"

        globals_ = MODULE["main"].__globals__
        replacements = {
            "load_source_catalog": lambda _root, **_kwargs: catalog,
            "snapshot_catalog_record_isolation": lambda *_args: {},
            "update_catalog_target": fake_update,
        }
        originals = {name: globals_[name] for name in replacements}
        old_argv = sys.argv
        try:
            globals_.update(replacements)
            sys.argv = [str(SCRIPT), "manual-direct"]
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(MODULE["main"](), 0)
            self.assertEqual(observed, ["manual-direct"])
            rendered = MODULE["ANSI_ESCAPE_RE"].sub("", output.getvalue())
            self.assertEqual(rendered, "")

            observed.clear()
            sys.argv = [str(SCRIPT), "--all", "--verbose"]
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(MODULE["main"](), 0)
            self.assertEqual(observed, ["automatic-direct"])
            self.assertIn(
                "catalog/automatic-delegated: skipped (no executor)",
                output.getvalue(),
            )
            rendered = MODULE["ANSI_ESCAPE_RE"].sub("", output.getvalue())
            self.assertEqual(
                rendered,
                "catalog/automatic-delegated: skipped (no executor)\n"
                "\nSummary: 0 updated, 2 up-to-date, 0 failed\n",
            )

            reject = True
            observed.clear()
            sys.argv = [str(SCRIPT), "manual-direct"]
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(MODULE["main"](), 1)
            self.assertEqual(observed, ["manual-direct"])
            reject = False

            with tempfile.TemporaryDirectory() as temp_dir:
                mutate_path = Path(temp_dir) / "catalog.json"
                mutate_path.write_text("original\n")
                sys.argv = [str(SCRIPT), "manual-direct", "--dry-run"]
                stderr = io.StringIO()
                with (
                    contextlib.redirect_stdout(io.StringIO()),
                    contextlib.redirect_stderr(stderr),
                ):
                    self.assertEqual(MODULE["main"](), 1)
                self.assertEqual(mutate_path.read_text(), "original\n")
                self.assertIn(
                    "Dry-run attempted to mutate 1 source file", stderr.getvalue()
                )
        finally:
            globals_.update(originals)
            sys.argv = old_argv


class UpdateInventoryTests(unittest.TestCase):
    def test_source_catalog_rejects_duplicate_ids(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            (temp / "sources").mkdir()
            (temp / "sources/bad.json").write_text(
                '{"schemaVersion":1,"sources":{"same":{},"same":{}}}'
            )
            with self.assertRaisesRegex(ValueError, "duplicate JSON key: same"):
                load_source_catalog(temp)
            (temp / "sources/bad.json").unlink()
            (temp / "sources/multi.json").write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {
                            "multi": {
                                "source": {
                                    "fetcher": "fetchurl",
                                    "url": "https://example.invalid/main",
                                    "args": {
                                        "url": "https://example.invalid/main",
                                        "hash": "sha256-main",
                                    },
                                },
                                "hashes": {"cargoHash": "sha256-cargo"},
                                "artifacts": {
                                    "docs": {
                                        "fetcher": "fetchurl",
                                        "url": "https://example.invalid/docs",
                                        "args": {
                                            "url": "https://example.invalid/docs",
                                            "hash": "sha256-docs",
                                        },
                                    }
                                },
                                "update": {
                                    "kind": "url-release",
                                    "policy": "automatic",
                                },
                            }
                        },
                    }
                )
            )
            self.assertIn("multi", load_source_catalog(temp))
            (temp / "sources/duplicate.json").write_text(
                (temp / "sources/multi.json").read_text()
            )
            with self.assertRaisesRegex(
                RuntimeError, "duplicate source catalog id: multi"
            ):
                load_source_catalog(temp)

    @staticmethod
    def _write_projection_fixture(root, mutate=None):
        (root / "sources").mkdir()
        (root / "config/ai").mkdir(parents=True)
        record = {
            "source": {
                "args": {
                    "narHash": "sha256-selected",
                    "owner": "example",
                    "repo": "project",
                    "rev": "a" * 40,
                    "type": "github",
                },
                "fetcher": "fetchTree",
                "url": "https://github.com/example/project",
            },
            "update": {"input": "example", "kind": "flake-input"},
        }
        selected = {
            "locked": copy.deepcopy(record["source"]["args"]),
            "original": {
                "owner": "example",
                "repo": "project",
                "type": "github",
            },
        }
        lock = {
            "nodes": {
                "root": {"inputs": {"example": "selected"}},
                "selected": selected,
                # A matching decoy proves validation follows root.inputs instead
                # of assuming the node key is the input name.
                "example": copy.deepcopy(selected),
            },
            "root": "root",
            "version": 7,
        }
        document = {"schemaVersion": 1, "sources": {"example": record}}
        if mutate is not None:
            mutate(document, lock)
        (root / "sources/test.json").write_text(json.dumps(document, indent=2) + "\n")
        (root / "config/ai/flake.lock").write_text(json.dumps(lock, indent=2) + "\n")
        (root / "config/ai/flake.nix").write_text(
            '{\n  inputs = {\n    example.url = "github:example/project";\n  };\n}\n'
        )
        return document, lock

    def test_issue34_projection_mutations_fail_for_the_named_field(self):
        mutations = {
            "owner does not match declared input": lambda _document, lock: lock[
                "nodes"
            ]["selected"]["original"].update(owner="other"),
            "rev does not match portable lock": lambda _document, lock: lock["nodes"][
                "selected"
            ]["locked"].update(rev="b" * 40),
            "narHash does not match portable lock": lambda _document, lock: lock[
                "nodes"
            ]["selected"]["locked"].update(narHash="sha256-other"),
        }
        for expected, mutate in mutations.items():
            with (
                self.subTest(expected=expected),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                root = Path(temp_dir)
                self._write_projection_fixture(root, mutate)
                with self.assertRaisesRegex(RuntimeError, expected):
                    load_source_catalog(root)
                deferred = load_source_catalog(
                    root,
                    validate_flake_projections=False,
                )
                self.assertIn("example", deferred)

    def test_issue34_projection_does_not_use_input_name_as_lock_node(self):
        def drift_selected(_document, lock):
            lock["nodes"]["selected"]["locked"]["rev"] = "b" * 40

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_projection_fixture(root, drift_selected)
            with self.assertRaisesRegex(
                RuntimeError, "rev does not match portable lock"
            ):
                load_source_catalog(root)

    def test_issue34_projection_rejects_literal_url_drift(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_projection_fixture(root)
            (root / "config/ai/flake.nix").write_text(
                '{\n  inputs = {\n    example.url = "github:other/project";\n  };\n}\n'
            )
            with self.assertRaisesRegex(
                RuntimeError, "owner does not match flake literal"
            ):
                load_source_catalog(root)

    def test_flake_projection_shapes_fail_closed_with_or_without_lock_validation(self):
        def wrong_fetcher(document):
            url = "https://example.invalid/project.tar.gz"
            document["sources"]["example"]["source"] = {
                "args": {"hash": "sha256-source", "url": url},
                "fetcher": "fetchurl",
                "url": url,
            }

        def missing_compound_projection(document):
            url = "https://registry.npmjs.org/example/-/example-1.0.0.tgz"
            document["sources"]["example"] = {
                "version": "1.0.0",
                "source": {
                    "args": {"hash": "sha256-source", "url": url},
                    "fetcher": "fetchurl",
                    "url": url,
                },
                "update": {
                    "buildPackage": "example",
                    "input": "example",
                    "kind": "npm-release+flake-input",
                    "package": "example",
                },
            }

        def empty_input(document):
            document["sources"]["example"]["update"]["input"] = ""

        def duplicate_owner(document):
            document["sources"]["example-copy"] = copy.deepcopy(
                document["sources"]["example"]
            )

        cases = (
            (wrong_fetcher, "requires fetchTree"),
            (missing_compound_projection, "requires fetchTree"),
            (empty_input, "no non-empty input"),
            (duplicate_owner, "multiple catalog owners"),
        )
        for mutate, expected in cases:
            for validate_projections in (False, True):
                with (
                    self.subTest(
                        case=mutate.__name__,
                        validate_projections=validate_projections,
                    ),
                    tempfile.TemporaryDirectory() as temp_dir,
                ):
                    root = Path(temp_dir)
                    document, _lock = self._write_projection_fixture(root)
                    mutate(document)
                    (root / "sources/test.json").write_text(
                        json.dumps(document, indent=2) + "\n"
                    )
                    with self.assertRaisesRegex(RuntimeError, expected):
                        load_source_catalog(
                            root,
                            validate_flake_projections=validate_projections,
                        )

    def test_issue34_sync_refreshes_selected_lock_projection(self):
        def make_stale(document, _lock):
            source = document["sources"]["example"]["source"]
            source["args"]["rev"] = "0" * 40
            source["args"]["narHash"] = "sha256-stale"

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_projection_fixture(root, make_stale)
            self.assertEqual(sync_flake_projections(root, "example"), 1)
            target = load_source_catalog(root)["example"]
            args = target["_record"]["source"]["args"]
            self.assertEqual(args["rev"], "a" * 40)
            self.assertEqual(args["narHash"], "sha256-selected")
            self.assertEqual(
                target["_record"]["source"]["url"], "https://github.com/example/project"
            )

        env = os.environ.copy()
        env.pop("UPDATE_AGENTS_CANDIDATE", None)
        refused = subprocess.run(
            [sys.executable, str(SCRIPT), "--sync-flake-projections", "example"],
            cwd=SCRIPT.parent.parent,
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("restricted to the update candidate", refused.stderr)
        with tempfile.TemporaryDirectory() as temp_dir:
            primary = Path(temp_dir)
            (primary / ".git").mkdir()
            with self.assertRaisesRegex(RuntimeError, "detached linked worktree"):
                require_detached_linked_worktree(primary)

    def test_flake_input_copy_syncs_projected_package_version(self):
        def make_copy_stale(document, lock):
            record = document["sources"]["example"]
            record["version"] = "1.0.0"
            record["update"].update(
                buildPackage="candidate-package",
                kind="flake-input+copy",
            )
            record["source"]["args"]["rev"] = "0" * 40
            record["source"]["args"]["narHash"] = "sha256-stale"
            lock["nodes"]["example"]["locked"]["rev"] = "d" * 40
            lock["nodes"]["example"]["locked"]["narHash"] = "sha256-decoy"

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_projection_fixture(root, make_copy_stale)
            seen = []
            self.assertEqual(
                sync_flake_projections(
                    root,
                    "example",
                    version_resolver=lambda _root, input_name, locked: (
                        seen.append((input_name, locked["rev"])) or "2.0.0"
                    ),
                ),
                1,
            )
            record = json.loads((root / "sources/test.json").read_text())["sources"][
                "example"
            ]
            self.assertEqual(seen, [("example", "a" * 40)])
            self.assertEqual(record["version"], "2.0.0")
            self.assertEqual(record["source"]["args"]["rev"], "a" * 40)
            self.assertEqual(record["source"]["args"]["narHash"], "sha256-selected")

    def test_flake_input_candidate_validation_observes_selected_projection(self):
        for kind in ("flake-input", "flake-input+copy"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)

                def make_stale(document, _lock):
                    record = document["sources"]["example"]
                    record["update"].update(
                        buildPackage=(
                            "pi-gallery" if kind == "flake-input+copy" else "candidate-package"
                        ),
                        kind=kind,
                    )
                    if kind == "flake-input+copy":
                        record["version"] = "1.0.0"
                        record["update"]["buildMode"] = "check"
                    record["source"]["args"]["rev"] = "0" * 40
                    record["source"]["args"]["narHash"] = "sha256-stale"

                self._write_projection_fixture(root, make_stale)
                validations = []

                def validate_build(package, mode):
                    candidate = json.loads(
                        (root / "sources/test.json").read_text()
                    )["sources"]["example"]
                    validations.append(
                        (
                            package,
                            mode,
                            candidate["source"]["args"]["rev"],
                            candidate["source"]["args"]["narHash"],
                            candidate.get("version"),
                        )
                    )
                    return True

                self.assertEqual(
                    sync_flake_projections(
                        root,
                        "example",
                        version_resolver=lambda _root, _input, _locked: "2.0.0",
                    ),
                    1,
                )
                target = load_source_catalog(root)["example"]
                with mock.patch.dict(
                    validate_catalog_target.__globals__,
                    {
                        "HashComputer": lambda candidate_root: (
                            self.assertEqual(candidate_root, root)
                            or SimpleNamespace(validate_package_build=validate_build)
                        )
                    },
                ):
                    self.assertTrue(validate_catalog_target(root, "example", target))
                self.assertEqual(
                    validations,
                    [
                        (
                            (
                                "pi-gallery"
                                if kind == "flake-input+copy"
                                else "candidate-package"
                            ),
                            "check" if kind == "flake-input+copy" else "pkg",
                            "a" * 40,
                            "sha256-selected",
                            "2.0.0" if kind == "flake-input+copy" else None,
                        )
                    ],
                )

    def test_flake_input_version_resolver_reads_locked_package_manifest(self):
        calls = []

        def fake_run(command, **kwargs):
            calls.append((command, kwargs))
            return SimpleNamespace(returncode=0, stdout="4.9.0\n", stderr="")

        locked = {
            "type": "github",
            "owner": "example",
            "repo": "ponytail",
            "rev": "a" * 40,
            "narHash": "sha256-source",
        }
        version = resolve_flake_input_version(
            Path("/repo"), "ponytail", locked, runner=fake_run
        )
        self.assertEqual(version, "4.9.0")
        command, kwargs = calls[0]
        self.assertEqual(command[:5], ["nix", "eval", "--impure", "--raw", "--expr"])
        self.assertIn("builtins.fetchTree", command[-1])
        self.assertIn('\\"repo\\": \\"ponytail\\"', command[-1])
        self.assertIn('input.outPath + "/package.json"', command[-1])
        self.assertEqual(kwargs["cwd"], Path("/repo"))

    def test_flake_input_build_syncs_version_and_dependent_hash(self):
        def make_build_stale(document, lock):
            record = document["sources"]["example"]
            record["version"] = "1.0.0"
            record["hashes"] = {"npmDepsHash": "sha256-old"}
            record["update"].update(
                kind="flake-input+build", buildPackage="agent-resources"
            )
            record["source"]["args"]["rev"] = "0" * 40
            record["source"]["args"]["narHash"] = "sha256-stale"
            lock["nodes"]["example"]["locked"]["rev"] = "d" * 40

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_projection_fixture(root, make_build_stale)
            hash_calls = []

            def resolve_hash(_root, package, hash_type):
                on_disk = json.loads((root / "sources/test.json").read_text())[
                    "sources"
                ]["example"]
                hash_calls.append((package, hash_type))
                self.assertEqual(on_disk["version"], "2.0.0")
                self.assertEqual(on_disk["source"]["args"]["rev"], "a" * 40)
                self.assertEqual(
                    on_disk["hashes"]["npmDepsHash"],
                    "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
                )
                return "sha256-new"

            build_calls = []

            def validate_build(package, mode):
                on_disk = json.loads((root / "sources/test.json").read_text())[
                    "sources"
                ]["example"]
                build_calls.append((package, mode))
                self.assertEqual(on_disk["hashes"]["npmDepsHash"], "sha256-new")
                return True

            self.assertEqual(
                sync_flake_projections(
                    root,
                    "example",
                    version_resolver=lambda _root, _input, _locked: "2.0.0",
                    dependent_hash_resolver=resolve_hash,
                ),
                1,
            )
            target = load_source_catalog(root)["example"]
            with mock.patch.dict(
                validate_catalog_target.__globals__,
                {"HashComputer": lambda _root: SimpleNamespace(
                    validate_package_build=validate_build
                )},
            ):
                self.assertTrue(validate_catalog_target(root, "example", target))
            record = json.loads((root / "sources/test.json").read_text())["sources"][
                "example"
            ]
            self.assertEqual(hash_calls, [("agent-resources", "npmDepsHash")])
            self.assertEqual(build_calls, [("agent-resources", "pkg")])
            self.assertEqual(record["version"], "2.0.0")
            self.assertEqual(record["source"]["args"]["rev"], "a" * 40)
            self.assertEqual(record["hashes"]["npmDepsHash"], "sha256-new")

    def test_fod_hash_parser_requires_the_injected_dummy_pair(self):
        parse = MODULE["HashComputer"]._parse_dummy_hash_mismatch
        unrelated = """specified: sha256-old
got: sha256-unrelated
"""
        requested = f"""specified: {MODULE["DUMMY_SRI_HASH"]}
got: sha256-requested
"""
        self.assertIsNone(parse(unrelated))
        self.assertEqual(parse(unrelated + requested), "sha256-requested")
        self.assertIsNone(parse(requested + requested.replace("requested", "second")))

    def test_fod_hash_failure_surfaces_the_underlying_builder_exception(self):
        computer = HashComputer(Path("/repo"))
        computer._run_package_build = mock.Mock(
            return_value=SimpleNamespace(
                returncode=1,
                stdout="",
                stderr="""these 3 derivations will be built:
  /nix/store/source.drv
  /nix/store/deps.drv
  /nix/store/package.drv
error: Cannot build '/nix/store/source.drv'.
Reason: builder failed with exit code 1.
Last 1 log lines:
  > FileNotFoundError: /build/pi-lens/dist/clients/lsp/interactive-install.js
error: Cannot build '/nix/store/package.drv'.
""",
            )
        )

        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            with self.assertRaisesRegex(CandidateRejected, "pi-lens npmDepsHash"):
                computer._compute_fod_hash("pi-lens", "npmDepsHash")

        diagnostic = stderr.getvalue()
        self.assertIn("FileNotFoundError", diagnostic)
        self.assertIn("dist/clients/lsp/interactive-install.js", diagnostic)
        self.assertNotIn("these 3 derivations will be built", diagnostic)

    def test_fod_hash_rejection_surfaces_failed_patch_hunk(self):
        computer = HashComputer(Path("/repo"))
        computer._run_package_build = mock.Mock(
            return_value=SimpleNamespace(
                returncode=1,
                stdout="",
                stderr="""this derivation will be built:
  /nix/store/package.drv
building '/nix/store/package.drv'...
ERROR unrelated diagnostic one
ERROR unrelated diagnostic two
ERROR unrelated diagnostic three
ERROR unrelated diagnostic four
Hunk #3 FAILED at 83.
1 out of 4 hunks FAILED -- saving rejects to file fork-context.ts.rej
error: Cannot build '/nix/store/package.drv'.
""",
            )
        )

        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            with self.assertRaisesRegex(CandidateRejected, "Hunk #3 FAILED"):
                computer._compute_fod_hash("pi-subagents", "npmDepsHash")

        diagnostic = stderr.getvalue()
        self.assertIn("Hunk #3 FAILED at 83", diagnostic)
        self.assertNotIn("this derivation will be built", diagnostic)

    def test_fod_hash_non_candidate_failures_remain_hard(self):
        computer = HashComputer(Path("/repo"))
        cases = (
            SimpleNamespace(returncode=0, stdout="", stderr="no mismatch"),
            SimpleNamespace(
                returncode=-15,
                stdout=f"specified: {MODULE['DUMMY_SRI_HASH']}\ngot: sha256-buffered\n",
                stderr="terminated",
            ),
            subprocess.TimeoutExpired(["nix", "build"], 600),
            OSError("nix unavailable"),
        )
        for result in cases:
            with self.subTest(result=type(result).__name__):
                computer._run_package_build = (
                    mock.Mock(side_effect=result)
                    if isinstance(result, Exception)
                    else mock.Mock(return_value=result)
                )
                with contextlib.redirect_stderr(io.StringIO()):
                    self.assertIsNone(
                        computer._compute_fod_hash("example", "vendorHash")
                    )

    def test_package_build_distinguishes_provisional_failure_from_runner_error(self):
        computer = HashComputer(Path("/repo"))
        computer._run_package_build = mock.Mock(
            return_value=SimpleNamespace(returncode=1, stdout="", stderr="failed")
        )
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertFalse(computer.validate_package_build("example"))

        computer._run_package_build = mock.Mock(
            return_value=SimpleNamespace(returncode=-15, stdout="", stderr="")
        )
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, "validation interrupted"):
                computer.validate_package_build("example")

        computer._run_package_build = mock.Mock(side_effect=OSError("unavailable"))
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, "validation could not run"):
                computer.validate_package_build("example")

    def test_restored_baseline_uses_the_declared_build_contract(self):
        calls = []
        computer = SimpleNamespace(
            validate_package_build=lambda package, mode: (
                calls.append((package, mode)) or True
            )
        )
        validate = MODULE["validate_catalog_target"]
        with mock.patch.dict(
            validate.__globals__, {"HashComputer": lambda _root: computer}
        ):
            cases = (
                ("projection", {"buildPackage": "built-package"}),
                ("python-tool", {"buildMode": "python"}),
                ("plain", {}),
            )
            for name, update in cases:
                self.assertTrue(
                    validate(
                        Path("/repo"), name, {"_record": {"update": update}}
                    )
                )
        self.assertEqual(
            calls,
            [("built-package", "pkg"), ("python-tool", "python"), ("plain", "pkg")],
        )

    def test_package_hash_build_composes_repo_overlays_without_host_routing(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / 'repo "quoted" ${notNixSource}'
            root.mkdir()
            computer = MODULE["HashComputer"](root)
            commands = (
                (
                    computer._package_build_command("agent-resources"),
                    'builtins.getAttr "agent-resources" pkgs',
                ),
                (
                    computer._package_build_command("hf-xet", "python"),
                    'builtins.getAttr "hf-xet" pkgs.python3Packages',
                ),
                (
                    computer._package_build_command("pi-gallery", "check"),
                    'builtins.getAttr "pi-gallery" flake.inputs.nix-config-ai.checks.${system}',
                ),
            )
            for command, package_expression in commands:
                self.assertEqual(
                    command[:5],
                    ["nix", "build", "--impure", "--no-link", "--expr"],
                )
                self.assertEqual(len(command), 6)
                expression = command[-1]
                self.assertNotIn(str(root), expression)
                self.assertIn("UPDATE_OVERLAY_REPO_DIR", expression)
                self.assertIn("flake = builtins.getFlake repoPath;", expression)
                self.assertIn("repo = flake.outPath;", expression)
                self.assertIn(
                    'overlays = import (repo + "/config/overlays.nix")',
                    expression,
                )
                self.assertIn(package_expression, expression)
                self.assertNotIn("darwinConfigurations", expression)
                self.assertNotIn("nixosConfigurations", expression)
                parsed = subprocess.run(
                    ["nix-instantiate", "--parse", "--expr", expression],
                    capture_output=True,
                    text=True,
                    timeout=60,
                    check=False,
                )
                self.assertEqual(parsed.returncode, 0, parsed.stderr)

            with mock.patch.object(
                MODULE["subprocess"],
                "run",
                return_value=SimpleNamespace(returncode=0, stdout="", stderr=""),
            ) as run:
                computer._run_package_build("agent-resources")
            self.assertEqual(
                run.call_args.kwargs["env"]["UPDATE_OVERLAY_REPO_DIR"], str(root)
            )

            computer = HashComputer(root)
            build_calls = []

            def fake_build(package, build_mode):
                build_calls.append((package, build_mode))
                return SimpleNamespace(
                    returncode=1,
                    stdout=(
                        f"specified: {MODULE['DUMMY_SRI_HASH']}\ngot: sha256-cHl0aG9u\n"
                    ),
                    stderr="",
                )

            computer._run_package_build = fake_build
            self.assertEqual(
                computer._compute_fod_hash("hf-xet", "cargoDepsHash", "python"),
                "sha256-cHl0aG9u",
            )
            self.assertEqual(build_calls, [("hf-xet", "python")])

            tool_output = root / "jq-output"
            (tool_output / "bin").mkdir(parents=True)
            jq_tool = tool_output / "bin/jq"
            jq_tool.write_text("#!/bin/sh\nexit 0\n")
            jq_tool.chmod(0o755)
            resolver_calls = []

            def resolved_tool(command, **kwargs):
                resolver_calls.append((command, kwargs))
                return SimpleNamespace(
                    returncode=0,
                    stdout=f"{tool_output}\n",
                    stderr="",
                )

            resolver = HashComputer(root)
            self.assertEqual(
                resolver.resolve_build_tool("jq", "jq", runner=resolved_tool),
                jq_tool,
            )
            self.assertEqual(
                resolver.resolve_build_tool(
                    "jq",
                    "jq",
                    runner=lambda *_args, **_kwargs: self.fail(
                        "cached tool resolution invoked Nix twice"
                    ),
                ),
                jq_tool,
            )
            self.assertEqual(len(resolver_calls), 1)

            def resolution(stdout, returncode=0):
                return lambda _command, **_kwargs: SimpleNamespace(
                    returncode=returncode,
                    stdout=stdout,
                    stderr="",
                )

            for label, runner in (
                ("nonzero", resolution("", returncode=1)),
                ("empty", resolution("")),
                ("multiple", resolution(f"{tool_output}\n{tool_output}\n")),
                ("relative", resolution("relative-output\n")),
                ("missing executable", resolution(f"{root / 'missing'}\n")),
            ):
                with self.subTest(tool_resolution=label):
                    self.assertIsNone(
                        HashComputer(root).resolve_build_tool("jq", "jq", runner=runner)
                    )
            self.assertIsNone(
                HashComputer(root).resolve_build_tool(
                    "jq; builtins.abort", "jq", runner=resolved_tool
                )
            )

    def test_package_hash_expression_evaluates_repo_overlay_authority(self):
        # agent-resources proves the portable AI overlays are composed;
        # markless and linkdups prove the root repository overlays are composed;
        # cpx must remain reachable on Darwin for cargoHash computation even
        # though normal package selection remains Linux-only.
        evaluated_drvs = {}
        for package, build_mode, evaluation_system, drv_pattern in (
            (
                "agent-resources",
                "pkg",
                None,
                r"^/nix/store/[a-z0-9]+-agent-resources\.drv$",
            ),
            (
                "markless",
                "pkg",
                None,
                r"^/nix/store/[a-z0-9]+-markless-[0-9][^/]*\.drv$",
            ),
            (
                "linkdups",
                "pkg",
                None,
                r"^/nix/store/[a-z0-9]+-linkdups-[^/]+\.drv$",
            ),
            (
                "cpx",
                "pkg",
                "aarch64-darwin",
                r"^/nix/store/[a-z0-9]+-cpx-[0-9][^/]*\.drv$",
            ),
            (
                "pi-gallery",
                "check",
                None,
                r"^/nix/store/[a-z0-9]+-pi-gallery-check\.drv$",
            ),
            (
                "pi-ponytail",
                "pkg",
                None,
                r"^/nix/store/[a-z0-9]+-pi-ponytail-[^/]+\.drv$",
            ),
        ):
            with self.subTest(package=package, system=evaluation_system):
                expression = HashComputer(REPO)._package_build_command(
                    package, build_mode
                )[-1]
                environment = dict(os.environ)
                environment["UPDATE_OVERLAY_REPO_DIR"] = str(REPO)
                command = ["nix", "eval"]
                if evaluation_system is not None:
                    command.extend(["--system", evaluation_system])
                command.extend(
                    [
                        "--impure",
                        "--raw",
                        "--expr",
                        f"({expression}).drvPath",
                    ]
                )
                evaluated = subprocess.run(
                    command,
                    capture_output=True,
                    text=True,
                    timeout=240,
                    check=False,
                    env=environment,
                )
                self.assertEqual(evaluated.returncode, 0, evaluated.stderr)
                self.assertRegex(evaluated.stdout.strip(), drv_pattern)
                evaluated_drvs[(package, build_mode)] = evaluated.stdout.strip()

        check_drv = evaluated_drvs[("pi-gallery", "check")]
        shown = subprocess.run(
            ["nix", "derivation", "show", check_drv],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        self.assertEqual(shown.returncode, 0, shown.stderr)
        derivations = json.loads(shown.stdout)["derivations"]
        check = next(iter(derivations.values()))
        input_drvs = set(check["inputs"]["drvs"])
        self.assertIn(
            Path(evaluated_drvs[("pi-ponytail", "pkg")]).name,
            input_drvs,
        )
        self.assertIn(
            Path(evaluated_drvs[("agent-resources", "pkg")]).name,
            input_drvs,
        )

    def test_cpx_hash_build_reaches_injected_dummy_on_current_system(self):
        # The Darwin drvPath subcase above proves that the Linux-only package is
        # reachable there. This real build proves the generated updater command
        # reaches cpx's fixed-output cargo dependency and reports exactly one
        # injected-hash mismatch instead of failing at package selection.
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "repo"
            shutil.copytree(
                REPO,
                root,
                ignore=shutil.ignore_patterns(
                    ".*", "__pycache__", "result", "result-*"
                ),
            )
            catalog_path = root / "sources/tools.json"
            catalog = json.loads(catalog_path.read_text())
            catalog["sources"]["cpx"]["hashes"]["cargoHash"] = MODULE[
                "DUMMY_SRI_HASH"
            ]
            catalog_path.write_text(json.dumps(catalog, indent=2) + "\n")

            computed = HashComputer(root)._compute_fod_hash("cpx", "cargoHash")
            self.assertIsNotNone(computed)
            self.assertNotEqual(computed, MODULE["DUMMY_SRI_HASH"])
            self.assertRegex(computed, r"^sha256-[A-Za-z0-9+/=]+$")

    def test_pi_mcp_adapter_patch_ignores_unrelated_imports(self):
        patch_file = (
            REPO / "packages/agent-resources/pi-mcp-adapter-xdg-config-home.patch"
        )
        base_source = """// config.ts - Config loading with import support
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { parse as parseToml } from "smol-toml";
import { getAgentPath } from "./agent-dir.ts";
import { isServerDisabled } from "./types.ts";
import { toStringRecord } from "./utils.ts";

const GENERIC_GLOBAL_CONFIG_PATH = join(homedir(), ".config", "mcp", "mcp.json");
"""
        source_shapes = {
            "original": base_source,
            "unrelated import added": base_source.replace(
                'import { getAgentPath } from "./agent-dir.ts";\n',
                'import { getAgentPath } from "./agent-dir.ts";\n'
                'import { getAgentPluginSummaries } from "./agent-plugin-loader.ts";\n',
            ),
        }
        for label, source in source_shapes.items():
            with (
                self.subTest(source_shape=label),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                root = Path(temp_dir)
                config = root / "config.ts"
                config.write_text(source)
                applied = subprocess.run(
                    [
                        "patch",
                        "--batch",
                        "--fuzz=0",
                        "--strip=1",
                        "--input",
                        str(patch_file),
                    ],
                    cwd=root,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(applied.returncode, 0, applied.stdout + applied.stderr)
                updated = config.read_text()
                self.assertIn(
                    'import { dirname, isAbsolute, join, resolve } from "node:path";',
                    updated,
                )
                self.assertIn("process.env.XDG_CONFIG_HOME?.trim()", updated)
                self.assertEqual(
                    "getAgentPluginSummaries" in updated,
                    "getAgentPluginSummaries" in source,
                )

    def test_pi_manifest_normalizer_is_shared_complete_and_fail_closed(self):
        root = SCRIPT.parent.parent
        contract = load_pi_normalization_contract(root)
        self.assertEqual(set(contract["targets"]), PI_NORMALIZATION_TARGETS)
        jq = shutil.which("jq")
        self.assertIsNotNone(jq)
        manifest = {
            "name": "example",
            "version": "1.0.0",
            "dependencies": {
                "keep": "1",
                "better-sqlite3": "1",
                "@earendil-works/pi-tui": "1",
                "@mariozechner/pi-ai": "1",
                "@mariozechner/pi-coding-agent": "1",
                "@mariozechner/pi-tui": "1",
                "@sinclair/typebox": "1",
                "typebox": "1",
            },
            "optionalDependencies": {
                "optional-keep": "1",
                "better-sqlite3": "1",
                "@earendil-works/pi-tui": "1",
                "@mariozechner/pi-ai": "1",
                "@mariozechner/pi-coding-agent": "1",
                "@mariozechner/pi-tui": "1",
                "@sinclair/typebox": "1",
                "typebox": "1",
            },
            "devDependencies": {"dev": "1"},
            "peerDependencies": {"peer": "1"},
            "peerDependenciesMeta": {"peer": {"optional": True}},
            "allowScripts": {"better-sqlite3": True},
        }
        special = {
            "pi-hashline-edit-pro": {
                "better-sqlite3",
            },
            "pi-lens": {
                "@earendil-works/pi-tui",
                "typebox",
            },
            "pi-mem": {
                "@mariozechner/pi-ai",
                "@mariozechner/pi-coding-agent",
                "@mariozechner/pi-tui",
                "@sinclair/typebox",
            },
            "pi-smart-fetch": {
                "@earendil-works/pi-tui",
                "@sinclair/typebox",
            },
            "pi-subagents": {"typebox"},
        }
        all_special_dependencies = set().union(*special.values())
        for target in sorted(PI_NORMALIZATION_TARGETS):
            with self.subTest(target=target):
                self.assertEqual(
                    set(contract["targets"][target]["defensiveForbidDependencies"]),
                    special.get(target, set()),
                )
                self.assertEqual(contract["targets"][target]["forbidDependencies"], [])
                self.assertEqual(
                    contract["targets"][target]["overrideDependencies"],
                    {},
                )
                normalized_text = normalize_pi_manifest(
                    root,
                    target,
                    "example",
                    "1.0.0",
                    json.dumps(manifest),
                    Path(jq),
                )
                self.assertIsNotNone(normalized_text)
                normalized = json.loads(normalized_text)
                self.assertNotIn("devDependencies", normalized)
                self.assertNotIn("peerDependencies", normalized)
                self.assertNotIn("peerDependenciesMeta", normalized)
                self.assertEqual(normalized["dependencies"]["keep"], "1")
                self.assertEqual(
                    normalized["optionalDependencies"]["optional-keep"], "1"
                )
                for dependency in special.get(target, set()):
                    self.assertNotIn(dependency, normalized["dependencies"])
                    self.assertNotIn(dependency, normalized["optionalDependencies"])
                for dependency in all_special_dependencies - special.get(target, set()):
                    self.assertIn(dependency, normalized["dependencies"])
                    self.assertIn(dependency, normalized["optionalDependencies"])
                if target == "pi-hashline-edit-pro":
                    self.assertNotIn("allowScripts", normalized)
                else:
                    self.assertIn("allowScripts", normalized)
        self.assertIsNone(
            normalize_pi_manifest(
                root,
                "unknown-target",
                "example",
                "1.0.0",
                json.dumps(manifest),
                Path(jq),
            )
        )
        with self.assertRaisesRegex(RuntimeError, "identity does not match"):
            normalize_pi_manifest(
                root,
                "pi-lens",
                "wrong-name",
                "1.0.0",
                json.dumps(manifest),
                Path(jq),
            )
        with tempfile.TemporaryDirectory() as temp_dir:
            temporary_root = Path(temp_dir)
            gallery = temporary_root / "packages/pi-gallery"
            gallery.mkdir(parents=True)
            shutil.copy(root / "packages/pi-gallery/normalize-manifest.jq", gallery)

            def run_policy(candidate, candidate_manifest=manifest):
                policy = gallery / "normalization-policy.json"
                policy.write_text(json.dumps(candidate))
                return subprocess.run(
                    [
                        jq,
                        "--arg",
                        "target",
                        "pi-lens",
                        "--arg",
                        "expectedName",
                        "example",
                        "--arg",
                        "expectedVersion",
                        "1.0.0",
                        "--slurpfile",
                        "policy",
                        str(policy),
                        "-f",
                        str(gallery / "normalize-manifest.jq"),
                    ],
                    input=json.dumps(candidate_manifest),
                    capture_output=True,
                    text=True,
                    check=False,
                )

            enforced = copy.deepcopy(contract)
            enforced["targets"]["pi-lens"]["forbidDependencies"] = ["keep"]
            enforced_result = run_policy(enforced)
            self.assertEqual(
                enforced_result.returncode,
                0,
                enforced_result.stdout + enforced_result.stderr,
            )
            self.assertNotIn("keep", json.loads(enforced_result.stdout)["dependencies"])

            inert = copy.deepcopy(contract)
            inert["targets"]["pi-lens"]["forbidDependencies"] = [
                "missing-enforced-dependency"
            ]
            inert_result = run_policy(inert)
            self.assertNotEqual(inert_result.returncode, 0)
            self.assertIn("inert enforced Pi npm dependencies", inert_result.stderr)
            self.assertIn("missing-enforced-dependency", inert_result.stderr)

            defensive = copy.deepcopy(contract)
            defensive["targets"]["pi-lens"]["defensiveForbidDependencies"] = [
                "future-defensive-dependency"
            ]
            defensive_result = run_policy(defensive)
            self.assertEqual(
                defensive_result.returncode,
                0,
                defensive_result.stdout + defensive_result.stderr,
            )

            inert_override = copy.deepcopy(contract)
            inert_override["targets"]["pi-lens"]["overrideDependencies"] = {
                "missing-override-dependency": "2"
            }
            inert_override_result = run_policy(inert_override)
            self.assertNotEqual(inert_override_result.returncode, 0)
            self.assertIn(
                "inert Pi npm dependency overrides", inert_override_result.stderr
            )

            def rejected(label, mutate, python_rejects=False):
                # The jq normalizer is the single policy validator: every
                # malformed contract must fail it. The Python loader
                # re-checks only the shape its own consumers index and the
                # npm argv flag tripwire, so it rejects just those cases —
                # and must ACCEPT the deep-policy mutations, documenting
                # that the duplication was deliberately removed.
                malformed = copy.deepcopy(contract)
                mutate(malformed)
                (gallery / "normalization-policy.json").write_text(
                    json.dumps(malformed)
                )
                with self.subTest(label=label):
                    if python_rejects:
                        with self.assertRaises(RuntimeError):
                            load_pi_normalization_contract(temporary_root)
                    else:
                        load_pi_normalization_contract(temporary_root)
                    result = run_policy(malformed)
                    self.assertNotEqual(result.returncode, 0)

            rejected(
                "scripts enabled",
                lambda value: value["npmDependencyFlags"].remove("--ignore-scripts"),
                python_rejects=True,
            )
            rejected(
                "unknown contract field",
                lambda value: value.update(unexpected=True),
                python_rejects=True,
            )
            rejected(
                "duplicate removal",
                lambda value: value["common"]["removeTopLevel"].append(
                    "devDependencies"
                ),
            )
            rejected(
                "invalid override value",
                lambda value: value["targets"]["pi-lens"][
                    "overrideDependencies"
                ].update(keep=""),
            )
            rejected(
                "override repeated across common and target",
                lambda value: (
                    value["common"]["overrideDependencies"].update(keep="1"),
                    value["targets"]["pi-lens"][
                        "overrideDependencies"
                    ].update(keep="2"),
                ),
            )
            rejected(
                "dependency repeated across override and forbid policies",
                lambda value: (
                    value["common"]["overrideDependencies"].update(keep="2"),
                    value["targets"]["pi-lens"][
                        "forbidDependencies"
                    ].append("keep"),
                ),
            )
            rejected(
                "dependency repeated across policies",
                lambda value: (
                    value["common"]["forbidDependencies"].append("duplicate"),
                    value["common"]["defensiveForbidDependencies"].append("duplicate"),
                ),
            )
            rejected(
                "dependency repeated across common and target policies",
                lambda value: (
                    value["common"]["forbidDependencies"].append("duplicate"),
                    value["targets"]["pi-lens"][
                        "defensiveForbidDependencies"
                    ].append("duplicate"),
                ),
            )
            rejected(
                "enforced dependency repeated across common and target",
                lambda value: (
                    value["common"]["forbidDependencies"].append("duplicate"),
                    value["targets"]["pi-lens"]["forbidDependencies"].append(
                        "duplicate"
                    ),
                ),
            )
            rejected(
                "defensive dependency repeated across common and target",
                lambda value: (
                    value["common"]["defensiveForbidDependencies"].append("duplicate"),
                    value["targets"]["pi-lens"][
                        "defensiveForbidDependencies"
                    ].append("duplicate"),
                ),
            )
        default_nix = (root / "packages/pi-gallery/default.nix").read_text()
        self.assertIn("-f ${./normalize-manifest.jq}", default_nix)
        self.assertIn("normalizationContract.npmDependencyFlags", default_nix)
        self.assertNotIn("del(.devDependencies)", default_nix)
        source_records = json.loads((root / "sources/pi.json").read_text())["sources"]
        self.assertEqual(
            {
                name
                for name, record in source_records.items()
                if record["update"].get("normalizer") == "pi-gallery-v1"
            },
            PI_NORMALIZATION_TARGETS,
        )
        environment = dict(os.environ)
        environment.pop("UPDATE_AGENTS_CANDIDATE", None)
        refused = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--prepare-target",
                "pi-lens",
            ],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
        )
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("restricted to the update candidate", refused.stderr)
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = Path(temp_dir)
            primary = fixture / "primary"
            attached = fixture / "attached"
            detached = fixture / "detached"
            empty_templates = fixture / "empty-templates"
            empty_templates.mkdir()

            git_environment = dict(os.environ)
            for key in tuple(git_environment):
                if key.startswith("GIT_CONFIG_") or key in {
                    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
                    "GIT_COMMON_DIR",
                    "GIT_DIR",
                    "GIT_INDEX_FILE",
                    "GIT_OBJECT_DIRECTORY",
                    "GIT_WORK_TREE",
                }:
                    git_environment.pop(key)
            git_environment.update(
                {
                    "GIT_CONFIG_GLOBAL": os.devnull,
                    "GIT_CONFIG_NOSYSTEM": "1",
                }
            )

            def run_git(*arguments):
                result = subprocess.run(
                    [
                        "git",
                        "-c",
                        "commit.gpgsign=false",
                        "-c",
                        f"core.hooksPath={os.devnull}",
                        "-c",
                        f"init.templateDir={empty_templates}",
                        *map(str, arguments),
                    ],
                    capture_output=True,
                    text=True,
                    env=git_environment,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)

            run_git("init", primary)
            (primary / "tracked").write_text("fixture\n")
            run_git("-C", primary, "add", "tracked")
            run_git(
                "-C",
                primary,
                "-c",
                "user.name=Update Overlay Test",
                "-c",
                "user.email=update-overlay-test@example.invalid",
                "commit",
                "-m",
                "fixture",
            )
            run_git("-C", primary, "worktree", "add", "-b", "attached", attached)
            run_git("-C", primary, "worktree", "add", "--detach", detached)

            with self.assertRaisesRegex(RuntimeError, "detached linked worktree"):
                require_detached_linked_worktree(attached)
            require_detached_linked_worktree(detached)

    def test_npm_lock_generation_and_pairing_are_frozen(self):
        manifest = {
            "name": "example",
            "version": "1.0.0",
            "dependencies": {"keep": "1"},
            "optionalDependencies": {"optional": "1"},
        }
        manifest_text = json.dumps(manifest, indent=2) + "\n"
        with tempfile.TemporaryDirectory() as temp_dir:
            archive_path = Path(temp_dir) / "package.tgz"
            payload = manifest_text.encode()
            with tarfile.open(archive_path, "w:gz") as archive:
                member = tarfile.TarInfo("package/package.json")
                member.size = len(payload)
                archive.addfile(member, io.BytesIO(payload))
            raw_manifest, raw_document = read_npm_tarball_manifest(archive_path)
            self.assertEqual(raw_manifest, manifest_text)
            self.assertEqual(raw_document, manifest)
            normalizer_globals = read_npm_tarball_manifest.__globals__
            old_compressed_limit = normalizer_globals["MAX_NPM_TARBALL_BYTES"]
            normalizer_globals["MAX_NPM_TARBALL_BYTES"] = (
                archive_path.stat().st_size - 1
            )
            try:
                with self.assertRaisesRegex(RuntimeError, "256 MiB"):
                    read_npm_tarball_manifest(archive_path)
            finally:
                normalizer_globals["MAX_NPM_TARBALL_BYTES"] = old_compressed_limit
            digest = hashlib.sha512(archive_path.read_bytes()).digest()
            integrity = f"sha512-{base64.b64encode(digest).decode()}"
            self.assertTrue(verify_npm_integrity(archive_path, integrity))
            self.assertFalse(verify_npm_integrity(archive_path, "sha512-AAAAAAAA"))
            sha1 = base64.b64encode(
                hashlib.sha1(archive_path.read_bytes()).digest()
            ).decode()
            wrong_sha512 = base64.b64encode(b"x" * 64).decode()
            self.assertFalse(
                verify_npm_integrity(
                    archive_path,
                    f"sha1-{sha1} sha512-{wrong_sha512}",
                )
            )
            self.assertTrue(
                verify_npm_integrity(
                    archive_path,
                    f"sha1-AAAAAAAA sha512-{base64.b64encode(digest).decode()}",
                )
            )

            duplicate = Path(temp_dir) / "duplicate.tgz"
            with tarfile.open(duplicate, "w:gz") as archive:
                for _index in range(2):
                    member = tarfile.TarInfo("package/package.json")
                    member.size = len(payload)
                    archive.addfile(member, io.BytesIO(payload))
            with self.assertRaisesRegex(RuntimeError, "one bounded"):
                read_npm_tarball_manifest(duplicate)

            linked = Path(temp_dir) / "linked.tgz"
            with tarfile.open(linked, "w:gz") as archive:
                member = tarfile.TarInfo("package/package.json")
                member.type = tarfile.SYMTYPE
                member.linkname = "elsewhere"
                archive.addfile(member)
            with self.assertRaisesRegex(RuntimeError, "regular file"):
                read_npm_tarball_manifest(linked)

            oversized = Path(temp_dir) / "oversized.tgz"
            oversized_payload = b"x" * (1024 * 1024 + 1)
            with tarfile.open(oversized, "w:gz") as archive:
                member = tarfile.TarInfo("package/package.json")
                member.size = len(oversized_payload)
                archive.addfile(member, io.BytesIO(oversized_payload))
            with self.assertRaisesRegex(RuntimeError, "1 MiB"):
                read_npm_tarball_manifest(oversized)

            declared_oversized = Path(temp_dir) / "declared-oversized.tgz"
            with tarfile.open(declared_oversized, "w:gz") as archive:
                member = tarfile.TarInfo("package/large.bin")
                member.size = 1025
                archive.addfile(member, io.BytesIO(b"x" * 1025))
                manifest_member = tarfile.TarInfo("package/package.json")
                manifest_member.size = len(payload)
                archive.addfile(manifest_member, io.BytesIO(payload))
            old_member_limit = normalizer_globals["MAX_NPM_TAR_MEMBER_BYTES"]
            normalizer_globals["MAX_NPM_TAR_MEMBER_BYTES"] = 1024
            try:
                with self.assertRaisesRegex(RuntimeError, "member exceeds"):
                    read_npm_tarball_manifest(declared_oversized)
            finally:
                normalizer_globals["MAX_NPM_TAR_MEMBER_BYTES"] = old_member_limit

            cumulative = Path(temp_dir) / "cumulative.tgz"
            with tarfile.open(cumulative, "w:gz") as archive:
                for name in ("package/one", "package/two"):
                    member = tarfile.TarInfo(name)
                    member.size = 800
                    archive.addfile(member, io.BytesIO(b"x" * 800))
            old_declared_limit = normalizer_globals["MAX_NPM_TAR_DECLARED_BYTES"]
            normalizer_globals["MAX_NPM_TAR_DECLARED_BYTES"] = 1500
            try:
                with self.assertRaisesRegex(RuntimeError, "declared-size"):
                    read_npm_tarball_manifest(cumulative)
            finally:
                normalizer_globals["MAX_NPM_TAR_DECLARED_BYTES"] = old_declared_limit

            too_many = Path(temp_dir) / "too-many.tgz"
            with tarfile.open(too_many, "w:gz") as archive:
                for name in ("package/one", "package/package.json"):
                    content = payload if name.endswith("package.json") else b"x"
                    member = tarfile.TarInfo(name)
                    member.size = len(content)
                    archive.addfile(member, io.BytesIO(content))
            old_member_count = normalizer_globals["MAX_NPM_TAR_MEMBERS"]
            normalizer_globals["MAX_NPM_TAR_MEMBERS"] = 1
            try:
                with self.assertRaisesRegex(RuntimeError, "member-count"):
                    read_npm_tarball_manifest(too_many)
            finally:
                normalizer_globals["MAX_NPM_TAR_MEMBERS"] = old_member_count

            for unsafe_name in (
                "/package/package.json",
                "../package/package.json",
            ):
                unsafe = Path(temp_dir) / (
                    "absolute.tgz" if unsafe_name.startswith("/") else "traversal.tgz"
                )
                with tarfile.open(unsafe, "w:gz") as archive:
                    member = tarfile.TarInfo(unsafe_name)
                    member.size = len(payload)
                    archive.addfile(member, io.BytesIO(payload))
                with self.assertRaisesRegex(RuntimeError, "unsafe member path"):
                    read_npm_tarball_manifest(unsafe)

            pax = Path(temp_dir) / "pax.tgz"
            with tarfile.open(pax, "w:gz", format=tarfile.PAX_FORMAT) as archive:
                member = tarfile.TarInfo("package/package.json")
                member.pax_headers = {"comment": "x" * 2048}
                member.size = len(payload)
                archive.addfile(member, io.BytesIO(payload))
            with self.assertRaisesRegex(RuntimeError, "extended headers"):
                read_npm_tarball_manifest(pax)

            gnu_longname = Path(temp_dir) / "gnu-longname.tgz"
            with tarfile.open(
                gnu_longname, "w:gz", format=tarfile.GNU_FORMAT
            ) as archive:
                long_member = tarfile.TarInfo("package/" + ("x" * 120))
                long_member.size = 1
                archive.addfile(long_member, io.BytesIO(b"x"))
                manifest_member = tarfile.TarInfo("package/package.json")
                manifest_member.size = len(payload)
                archive.addfile(manifest_member, io.BytesIO(payload))
            with self.assertRaisesRegex(RuntimeError, "extended headers"):
                read_npm_tarball_manifest(gnu_longname)

            gnu_longlink = Path(temp_dir) / "gnu-longlink.tgz"
            with tarfile.open(
                gnu_longlink, "w:gz", format=tarfile.GNU_FORMAT
            ) as archive:
                link = tarfile.TarInfo("package/link")
                link.type = tarfile.SYMTYPE
                link.linkname = "x" * 200
                archive.addfile(link)
                manifest_member = tarfile.TarInfo("package/package.json")
                manifest_member.size = len(payload)
                archive.addfile(manifest_member, io.BytesIO(payload))
            with self.assertRaisesRegex(RuntimeError, "extended headers"):
                read_npm_tarball_manifest(gnu_longlink)
        prior_lock = (
            json.dumps(
                {
                    "name": "example",
                    "version": "1.0.0",
                    "lockfileVersion": 3,
                    "packages": {"": manifest},
                },
                indent=2,
            )
            + "\n"
        )
        calls = []

        def fake_npm(command, **kwargs):
            calls.append((command, kwargs))
            root = Path(kwargs["cwd"])
            current = json.loads((root / "package.json").read_text())
            generated = {
                "name": current["name"],
                "version": current["version"],
                "lockfileVersion": 3,
                "packages": {
                    "": current,
                    "node_modules/keep": {
                        "version": "1.0.0",
                        "resolved": "https://registry.npmjs.org/keep/-/keep-1.0.0.tgz",
                        "integrity": VENDOR_HASH,
                    },
                    "node_modules/optional": {
                        "version": "1.0.0",
                        "resolved": (
                            "https://registry.npmjs.org/optional/-/optional-1.0.0.tgz"
                        ),
                        "integrity": VENDOR_HASH,
                    },
                },
            }
            (root / "package-lock.json").write_text(
                json.dumps(generated, indent=2) + "\n"
            )
            return SimpleNamespace(returncode=0, stdout="", stderr="")

        flags = pi_npm_lock_flags(load_pi_normalization_contract(SCRIPT.parent.parent))
        with registry_only_proxy() as proxy:
            parsed_proxy = urlsplit(proxy)
            with socket.create_connection(
                (parsed_proxy.hostname, parsed_proxy.port), timeout=5
            ) as client:
                client.sendall(
                    b"CONNECT example.invalid:443 HTTP/1.1\r\n"
                    b"Host: example.invalid:443\r\n\r\n"
                )
                self.assertIn(b"403 Forbidden", client.recv(4096))
        generated = generate_npm_lock(
            manifest_text,
            prior_lock,
            Path("/nix/store/fake-node/bin/npm"),
            flags,
            runner=fake_npm,
        )
        self.assertIsNotNone(generated)
        self.assertTrue(validate_npm_manifest_lock(manifest_text, generated))
        generated_with_requires = json.loads(generated)
        generated_with_requires["requires"] = True
        self.assertTrue(
            npm_lock_documents_equal(
                generated,
                json.dumps(generated_with_requires),
            )
        )
        generated_with_requires["requires"] = False
        self.assertFalse(
            npm_lock_documents_equal(
                generated,
                json.dumps(generated_with_requires),
            )
        )
        raw = copy.deepcopy(manifest)
        raw["devDependencies"] = {"raw-only": "1"}
        self.assertFalse(validate_npm_manifest_lock(json.dumps(raw), generated))
        generated_document = json.loads(generated)
        for label, mutate in (
            (
                "off-registry",
                lambda value: value["packages"]["node_modules/keep"].update(
                    resolved="https://example.invalid/keep.tgz"
                ),
            ),
            (
                "missing integrity",
                lambda value: value["packages"]["node_modules/keep"].pop("integrity"),
            ),
            (
                "malformed integrity",
                lambda value: value["packages"]["node_modules/keep"].update(
                    integrity="not-sri"
                ),
            ),
            (
                "link package",
                lambda value: value["packages"]["node_modules/keep"].update(link=True),
            ),
            (
                "root identity",
                lambda value: value["packages"][""].update(name="wrong"),
            ),
        ):
            malformed = copy.deepcopy(generated_document)
            mutate(malformed)
            with self.subTest(lock_mutation=label):
                self.assertFalse(
                    validate_npm_manifest_lock(
                        manifest_text,
                        json.dumps(malformed),
                    )
                )
        optional_mismatch = copy.deepcopy(manifest)
        optional_mismatch["optionalDependencies"]["optional"] = "2"
        self.assertFalse(
            validate_npm_manifest_lock(json.dumps(optional_mismatch), generated)
        )
        peer_mismatch = copy.deepcopy(manifest)
        peer_mismatch["peerDependencies"] = {"peer": "1"}
        self.assertFalse(
            validate_npm_manifest_lock(json.dumps(peer_mismatch), generated)
        )
        command, kwargs = calls[0]
        self.assertEqual(command, ["/nix/store/fake-node/bin/npm", "install", *flags])
        self.assertEqual(kwargs["env"]["CI"], "true")
        self.assertNotEqual(kwargs["env"]["HOME"], os.environ.get("HOME"))
        self.assertIn("npm_config_userconfig", kwargs["env"])
        self.assertEqual(kwargs["env"]["PATH"], "/nix/store/fake-node/bin")
        self.assertEqual(
            kwargs["env"]["npm_config_registry"],
            "https://registry.npmjs.org",
        )
        self.assertEqual(kwargs["env"]["NODE_OPTIONS"], "")
        self.assertEqual(kwargs["env"]["GIT_SSH_COMMAND"], "/usr/bin/false")
        self.assertNotIn("SSH_AUTH_SOCK", kwargs["env"])
        self.assertRegex(kwargs["env"]["HTTPS_PROXY"], r"^http://127[.]0[.]0[.]1:")
        self.assertEqual(
            kwargs["env"]["npm_config_https_proxy"],
            kwargs["env"]["HTTPS_PROXY"],
        )

        for label, hostile_manifest in (
            (
                "git dependency",
                {**manifest, "dependencies": {"bad": "git+ssh://example/repo"}},
            ),
            (
                "file dependency",
                {**manifest, "dependencies": {"bad": "file:/tmp/repo"}},
            ),
            (
                "dot dependency",
                {**manifest, "dependencies": {"bad": "."}},
            ),
            (
                "whitespace dependency",
                {**manifest, "dependencies": {"bad": " ^1.0.0 "}},
            ),
            (
                "remote dependency",
                {**manifest, "dependencies": {"bad": "https://example.invalid/a.tgz"}},
            ),
            (
                "overrides",
                {**manifest, "overrides": {"keep": "2.0.0"}},
            ),
        ):
            before_calls = len(calls)
            with self.subTest(hostile_manifest=label):
                self.assertIsNone(
                    generate_npm_lock(
                        json.dumps(hostile_manifest),
                        prior_lock,
                        Path("/nix/store/fake-node/bin/npm"),
                        flags,
                        runner=fake_npm,
                    )
                )
                self.assertEqual(len(calls), before_calls)

        def mutating_npm(_command, **kwargs):
            (Path(kwargs["cwd"]) / "package.json").write_text("{}\n")
            return SimpleNamespace(returncode=0, stdout="", stderr="")

        self.assertIsNone(
            generate_npm_lock(
                manifest_text,
                prior_lock,
                Path("/nix/store/fake-node/bin/npm"),
                flags,
                runner=mutating_npm,
            )
        )

    def test_generic_npm_metadata_does_not_impose_pi_tarball_host_policy(self):
        payload = {
            "dist-tags": {"latest": "2.0.0"},
            "versions": {
                "2.0.0": {
                    "dist": {
                        "integrity": VENDOR_HASH,
                        "tarball": "cdn-specific-metadata-value",
                    }
                }
            },
        }
        metadata_globals = NpmRegistryClient.get_version_metadata.__globals__
        original_urlopen = metadata_globals["urlopen"]
        metadata_globals["urlopen"] = lambda *_args, **_kwargs: contextlib.nullcontext(
            io.StringIO(json.dumps(payload))
        )
        try:
            metadata = NpmRegistryClient().get_version_metadata("project")
        finally:
            metadata_globals["urlopen"] = original_urlopen
        self.assertEqual(
            metadata["tarball"],
            payload["versions"]["2.0.0"]["dist"]["tarball"],
        )

    def test_pi_npm_lock_projection_updates_atomically(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            lock_dir = root / "packages/pi-gallery/locks"
            lock_dir.mkdir(parents=True)
            policy_path = root / "packages/pi-gallery/normalization-policy.json"
            policy_path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 3,
                        "npmDependencyFlags": [
                            "--ignore-scripts",
                            "--omit=dev",
                            "--omit=peer",
                            "--legacy-peer-deps",
                        ],
                        "common": {
                            "removeTopLevel": [],
                            "forbidDependencies": [],
                            "defensiveForbidDependencies": [],
                            "overrideDependencies": {},
                        },
                        "targets": {
                            "project": {
                                "removeTopLevel": [],
                                "forbidDependencies": [],
                                "defensiveForbidDependencies": [],
                                "overrideDependencies": {},
                            }
                        },
                    }
                )
            )
            (root / "packages/pi-gallery/normalize-manifest.jq").write_text(".\n")
            lock_path = lock_dir / "project-package-lock.json"
            old_manifest = {"name": "project", "version": "1.0.0"}
            old_lock = (
                json.dumps(
                    {
                        "name": "project",
                        "version": "1.0.0",
                        "lockfileVersion": 3,
                        "packages": {"": old_manifest},
                    },
                    indent=2,
                )
                + "\n"
            )
            lock_path.write_text(old_lock)
            catalog_path = root / "sources/pi.json"
            catalog_path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {
                            "project": {
                                "version": "1.0.0",
                                "source": {
                                    "fetcher": "fetchurl",
                                    "url": "https://registry.npmjs.org/project/-/project-1.0.0.tgz",
                                    "args": {
                                        "url": "https://registry.npmjs.org/project/-/project-1.0.0.tgz",
                                        "hash": "sha256-source-old",
                                    },
                                },
                                "hashes": {"npmDepsHash": "sha256-npm-old"},
                                "update": {
                                    "artifacts": [
                                        "packages/pi-gallery/locks/project-package-lock.json"
                                    ],
                                    "kind": "npm-release",
                                    "normalizer": "pi-gallery-v1",
                                    "package": "project",
                                },
                            }
                        },
                    }
                )
            )
            target = load_source_catalog(root)["project"]
            self.assertEqual(target["executor"], "update")
            valid_catalog = catalog_path.read_text()

            shared_record = {
                "version": "1.0.0",
                "source": {
                    "fetcher": "fetchurl",
                    "url": "https://example.invalid/shared-1.0.0.tgz",
                    "args": {
                        "url": "https://example.invalid/shared-1.0.0.tgz",
                        "hash": "sha256-shared",
                    },
                },
                "update": {
                    "artifacts": [
                        "packages/pi-gallery/locks/project-package-lock.json"
                    ],
                    "kind": "url-release",
                },
            }
            canonical_lock = "packages/pi-gallery/locks/project-package-lock.json"
            for sibling_document, artifact_alias in (
                ("a.json", canonical_lock),
                ("z.json", f"./{canonical_lock}"),
            ):
                with self.subTest(sibling_document=sibling_document):
                    sibling_path = root / "sources" / sibling_document
                    sibling_record = copy.deepcopy(shared_record)
                    sibling_record["update"]["artifacts"] = [artifact_alias]
                    sibling_path.write_text(
                        json.dumps(
                            {
                                "schemaVersion": 1,
                                "sources": {"sibling": sibling_record},
                            }
                        )
                    )
                    with self.assertRaisesRegex(
                        RuntimeError, "exactly its normalizer target as owner"
                    ):
                        load_source_catalog(root)
                    sibling_path.unlink()

            (root / "flake.lock").write_text("{}\n")
            shared_flake_path = root / "sources/shared-flake.json"
            shared_flake_path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {
                            f"shared-{index}": {
                                **copy.deepcopy(shared_record),
                                "source": {
                                    "fetcher": "fetchurl",
                                    "url": f"https://example.invalid/shared-{index}-1.0.0.tgz",
                                    "args": {
                                        "url": (
                                            "https://example.invalid/"
                                            f"shared-{index}-1.0.0.tgz"
                                        ),
                                        "hash": f"sha256-shared-{index}",
                                    },
                                },
                                "update": {
                                    "artifacts": ["flake.lock"],
                                    "kind": "url-release",
                                },
                            }
                            for index in (1, 2)
                        },
                    }
                )
            )
            shared_targets = load_source_catalog(root)
            self.assertTrue({"shared-1", "shared-2"} <= set(shared_targets))
            shared_flake_path.unlink()

            wrong_path = json.loads(valid_catalog)
            wrong_path["sources"]["project"]["update"]["artifacts"] = [
                "packages/pi-gallery/locks/wrong-package-lock.json"
            ]
            (lock_dir / "wrong-package-lock.json").write_text(old_lock)
            catalog_path.write_text(json.dumps(wrong_path))
            with self.assertRaisesRegex(
                RuntimeError, "invalid Pi npm normalization projection"
            ):
                load_source_catalog(root)

            future = json.loads(valid_catalog)
            future_record = copy.deepcopy(future["sources"]["project"])
            future_record["update"].pop("normalizer")
            future_record["update"]["package"] = "future"
            future_record["update"]["artifacts"] = [
                "packages/pi-gallery/locks/future-package-lock.json"
            ]
            future_record["source"]["url"] = (
                "https://registry.npmjs.org/future/-/future-1.0.0.tgz"
            )
            future_record["source"]["args"]["url"] = future_record["source"]["url"]
            future["sources"]["future"] = future_record
            (lock_dir / "future-package-lock.json").write_text(old_lock)
            catalog_path.write_text(json.dumps(future))
            with self.assertRaisesRegex(RuntimeError, "target set differs"):
                load_source_catalog(root)

            catalog_path.write_text(valid_catalog)
            real_lock = lock_dir / "project-package-lock.real"
            lock_path.rename(real_lock)
            lock_path.symlink_to(real_lock.name)
            with self.assertRaisesRegex(RuntimeError, "missing artifacts"):
                load_source_catalog(root)
            lock_path.unlink()
            real_lock.rename(lock_path)
            catalog_path.write_text(valid_catalog)

            class FakeHashes:
                def __init__(self, valid=True):
                    self.valid = valid
                    self.calls = []

                def compute_native_hash(self, _source, replacements):
                    self.calls.append(("source", replacements))
                    return "sha256-source-new"

                def realize_native_source(self, _source, replacements):
                    self.calls.append(("realize", replacements))
                    return root / "source.tgz"

                def resolve_build_tool(self, package, executable):
                    self.calls.append(("tool", package, executable))
                    return Path(f"/nix/store/fake-{package}/bin/{executable}")

                def _compute_fod_hash(self, package, hash_type):
                    self.calls.append(("dependent", package, hash_type))
                    return "sha256-npm-new"

                def validate_package_build(self, package):
                    self.calls.append(("validate", package))
                    return self.valid

            off_registry_hashes = FakeHashes()
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_npm_lock_target(
                    "project",
                    target,
                    SimpleNamespace(version="2.0.0", dry_run=False),
                    SimpleNamespace(
                        get_version_metadata=lambda _package, requested: {
                            "version": requested,
                            "integrity": "sha512-integrity",
                            "tarball": (
                                f"https://cdn.example.invalid/project-{requested}.tgz"
                            ),
                        }
                    ),
                    off_registry_hashes,
                    transaction,
                )
            self.assertEqual(status, "failed")
            self.assertEqual(off_registry_hashes.calls, [])
            self.assertEqual(transaction.original, {})

            normalized = (
                json.dumps(
                    {
                        "name": "project",
                        "version": "2.0.0",
                        "dependencies": {"keep": "1"},
                    },
                    indent=2,
                )
                + "\n"
            )
            new_lock = (
                json.dumps(
                    {
                        "name": "project",
                        "version": "2.0.0",
                        "lockfileVersion": 3,
                        "packages": {
                            "": {
                                "name": "project",
                                "version": "2.0.0",
                                "dependencies": {"keep": "1"},
                            }
                        },
                    },
                    indent=2,
                )
                + "\n"
            )

            def reject_normalization(*_args):
                raise RuntimeError(
                    "inert enforced Pi npm dependencies: missing-enforced-dependency"
                )

            diagnostic_output = io.StringIO()
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(diagnostic_output):
                status = update_npm_lock_target(
                    "project",
                    target,
                    SimpleNamespace(version="2.0.0", dry_run=False),
                    SimpleNamespace(
                        get_version_metadata=lambda _package, requested: {
                            "version": requested,
                            "integrity": "sha512-integrity",
                            "tarball": (
                                "https://registry.npmjs.org/project/-/"
                                f"project-{requested}.tgz"
                            ),
                        }
                    ),
                    FakeHashes(),
                    transaction,
                    manifest_reader=lambda _path: (
                        '{"name":"project","version":"2.0.0"}',
                        {"name": "project", "version": "2.0.0"},
                    ),
                    manifest_normalizer=reject_normalization,
                    lock_generator=lambda *_args: self.fail(
                        "lock generation ran after normalization rejection"
                    ),
                    integrity_verifier=lambda _path, _integrity: True,
                )
            self.assertEqual(status, "failed")
            self.assertIn("missing-enforced-dependency", diagnostic_output.getvalue())
            self.assertEqual(transaction.original, {})

            observed = []

            def fake_normalizer(_root, target_name, expected_name, version, raw, jq):
                observed.append(
                    ("normalize", target_name, expected_name, version, raw, jq)
                )
                return normalized

            def fake_lock_generator(manifest, prior, npm, flags):
                observed.append(("lock", manifest, prior, npm, tuple(flags)))
                return new_lock

            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_npm_lock_target(
                    "project",
                    target,
                    SimpleNamespace(version="2.0.0", dry_run=False),
                    SimpleNamespace(
                        get_version_metadata=lambda _package, requested: {
                            "version": requested,
                            "integrity": "sha512-wrong",
                            "tarball": (
                                "https://registry.npmjs.org/project/-/"
                                f"project-{requested}.tgz"
                            ),
                        }
                    ),
                    FakeHashes(),
                    transaction,
                    manifest_reader=lambda _path: self.fail(
                        "manifest read preceded integrity validation"
                    ),
                    integrity_verifier=lambda _path, _integrity: False,
                )
            self.assertEqual(status, "failed")
            self.assertEqual(transaction.original, {})
            self.assertEqual(catalog_path.read_text(), valid_catalog)
            self.assertEqual(lock_path.read_text(), old_lock)

            hashes = FakeHashes()
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_npm_lock_target(
                    "project",
                    target,
                    SimpleNamespace(version="2.0.0", dry_run=False),
                    SimpleNamespace(
                        get_version_metadata=lambda _package, requested: {
                            "version": requested,
                            "integrity": "sha512-integrity",
                            "tarball": (
                                "https://registry.npmjs.org/project/-/"
                                f"project-{requested}.tgz"
                            ),
                        }
                    ),
                    hashes,
                    transaction,
                    manifest_reader=lambda _path: (
                        '{"name":"project","version":"2.0.0"}',
                        {"name": "project", "version": "2.0.0"},
                    ),
                    manifest_normalizer=fake_normalizer,
                    lock_generator=fake_lock_generator,
                    integrity_verifier=lambda _path, _integrity: True,
                )
            transaction.commit()
            self.assertEqual(status, "updated")
            updated = json.loads(catalog_path.read_text())["sources"]["project"]
            self.assertEqual(updated["version"], "2.0.0")
            self.assertEqual(updated["source"]["args"]["hash"], "sha256-source-new")
            self.assertEqual(updated["hashes"]["npmDepsHash"], "sha256-npm-new")
            self.assertEqual(lock_path.read_text(), new_lock)
            self.assertEqual(
                [call[0] for call in hashes.calls],
                ["source", "realize", "tool", "tool", "dependent", "validate"],
            )
            self.assertEqual([item[0] for item in observed], ["normalize", "lock"])

            current_target = load_source_catalog(root)["project"]
            current_hashes = FakeHashes()
            current_hashes.compute_native_hash = lambda _source, _replacements: (
                "sha256-source-new"
            )
            transaction = SourceTransaction()
            semantic_lock = json.loads(new_lock)
            semantic_lock["requires"] = True
            semantic_lock_text = json.dumps(
                semantic_lock, sort_keys=True, separators=(",", ":")
            )
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_npm_lock_target(
                    "project",
                    current_target,
                    SimpleNamespace(version="2.0.0", dry_run=False),
                    SimpleNamespace(
                        get_version_metadata=lambda _package, requested: {
                            "version": requested,
                            "integrity": "sha512-integrity",
                            "tarball": (
                                "https://registry.npmjs.org/project/-/"
                                f"project-{requested}.tgz"
                            ),
                        }
                    ),
                    current_hashes,
                    transaction,
                    manifest_reader=lambda _path: (
                        '{"name":"project","version":"2.0.0"}',
                        {"name": "project", "version": "2.0.0"},
                    ),
                    manifest_normalizer=fake_normalizer,
                    lock_generator=lambda _manifest, _prior, _npm, _flags: (
                        semantic_lock_text
                    ),
                    integrity_verifier=lambda _path, _integrity: True,
                )
            self.assertEqual(status, "skipped")
            self.assertEqual(transaction.original, {})
            self.assertEqual(lock_path.read_text(), new_lock)

            stale_document = json.loads(catalog_path.read_text())
            stale_document["sources"]["project"]["hashes"]["npmDepsHash"] = (
                "sha256-stale"
            )
            catalog_path.write_text(json.dumps(stale_document))
            repair_target = load_source_catalog(root)["project"]

            current_failure_hashes = FakeHashes(valid=False)
            current_failure_hashes.compute_native_hash = (
                lambda _source, _replacements: "sha256-source-new"
            )
            stale_catalog = catalog_path.read_text()
            current_lock = lock_path.read_text()
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_npm_lock_target(
                    "project",
                    repair_target,
                    SimpleNamespace(version="2.0.0", dry_run=False),
                    SimpleNamespace(
                        get_version_metadata=lambda _package, requested: {
                            "version": requested,
                            "integrity": "sha512-integrity",
                            "tarball": (
                                "https://registry.npmjs.org/project/-/"
                                f"project-{requested}.tgz"
                            ),
                        }
                    ),
                    current_failure_hashes,
                    transaction,
                    manifest_reader=lambda _path: (
                        '{"name":"project","version":"2.0.0"}',
                        {"name": "project", "version": "2.0.0"},
                    ),
                    manifest_normalizer=fake_normalizer,
                    lock_generator=lambda _manifest, _prior, _npm, _flags: new_lock,
                    integrity_verifier=lambda _path, _integrity: True,
                )
            self.assertEqual(status, "failed")
            self.assertEqual(transaction.original, {})
            self.assertEqual(catalog_path.read_text(), stale_catalog)
            self.assertEqual(lock_path.read_text(), current_lock)
            self.assertEqual(
                [
                    call
                    for call in current_failure_hashes.calls
                    if call[0] in {"dependent", "validate"}
                ],
                [("validate", "project")],
            )

            before_catalog = catalog_path.read_text()
            before_lock = lock_path.read_text()
            failing_target = load_source_catalog(root)["project"]
            failing_hashes = FakeHashes(valid=False)
            transaction = SourceTransaction()
            with (
                contextlib.redirect_stdout(io.StringIO()),
                self.assertRaises(CandidateRejected),
            ):
                update_npm_lock_target(
                    "project",
                    failing_target,
                    SimpleNamespace(version="3.0.0", dry_run=False),
                    SimpleNamespace(
                        get_version_metadata=lambda _package, requested: {
                            "version": requested,
                            "integrity": "sha512-integrity",
                            "tarball": (
                                "https://registry.npmjs.org/project/-/"
                                f"project-{requested}.tgz"
                            ),
                        }
                    ),
                    failing_hashes,
                    transaction,
                    manifest_reader=lambda _path: (
                        '{"name":"project","version":"3.0.0"}',
                        {"name": "project", "version": "3.0.0"},
                    ),
                    manifest_normalizer=lambda *_args: normalized.replace(
                        "2.0.0", "3.0.0"
                    ),
                    lock_generator=lambda *_args: new_lock.replace("2.0.0", "3.0.0"),
                    integrity_verifier=lambda _path, _integrity: True,
                )
            self.assertEqual(transaction.rollback(), 2)
            self.assertEqual(catalog_path.read_text(), before_catalog)
            self.assertEqual(lock_path.read_text(), before_lock)

    def test_issue38_ws_uses_fetchzip_with_an_executor(self):
        record = {
            "version": "8.18.3",
            "source": {
                "args": {
                    "hash": "sha256-ws",
                    "url": "https://registry.npmjs.org/ws/-/ws-8.18.3.tgz",
                },
                "fetcher": "fetchzip",
                "url": "https://registry.npmjs.org/ws/-/ws-8.18.3.tgz",
            },
            "update": {"kind": "npm-release", "package": "ws"},
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            document = {"schemaVersion": 1, "sources": {"ws": record}}
            (root / "sources/test.json").write_text(json.dumps(document))
            self.assertEqual(
                load_source_catalog(root)["ws"]["executor"], "update-overlay"
            )
            document["sources"]["ws"]["update"]["package"] = "other"
            (root / "sources/test.json").write_text(json.dumps(document))
            with self.assertRaisesRegex(RuntimeError, "npm source identity"):
                load_source_catalog(root)
            document["sources"]["ws"]["update"]["package"] = "ws"
            document["sources"]["ws"]["version"] = "8.18.4"
            (root / "sources/test.json").write_text(json.dumps(document))
            with self.assertRaisesRegex(
                RuntimeError, "URL does not match catalog version"
            ):
                load_source_catalog(root)

    def test_fixed_flake_input_rewrites_literal_and_rolls_back_atomically(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            (root / "config/ai").mkdir(parents=True)
            catalog_path = root / "sources/test.json"
            flake_path = root / "config/ai/flake.nix"
            old_rev = "a" * 40
            new_rev = "b" * 40
            old_hash = "sha256-old"
            new_hash = "sha256-new"

            def write_old_state():
                catalog_path.write_text(
                    json.dumps(
                        {
                            "schemaVersion": 1,
                            "sources": {
                                "example": {
                                    "source": {
                                        "fetcher": "fetchTree",
                                        "url": "https://github.com/example/project",
                                        "args": {
                                            "owner": "example",
                                            "repo": "project",
                                            "rev": old_rev,
                                            "narHash": old_hash,
                                            "type": "github",
                                        },
                                    },
                                    "update": {
                                        "artifacts": ["config/ai/flake.nix"],
                                        "input": "example",
                                        "kind": "fixed-flake-input",
                                    },
                                }
                            },
                        },
                        indent=2,
                    )
                    + "\n"
                )
                flake_path.write_text(
                    '{ inputs.example.url = "github:example/project/'
                    + old_rev
                    + '"; }\n'
                )

            def load_target():
                document = json.loads(catalog_path.read_text())
                record = document["sources"]["example"]
                return {
                    "_document": document,
                    "_path": catalog_path,
                    "_record": record,
                    "kind": "fixed-flake-input",
                    "version": record["source"]["args"]["rev"],
                }

            class FakeGitHubClient:
                def get_default_branch(self, owner, repo):
                    self.identity = (owner, repo)
                    return "main"

                def get_latest_commit(self, owner, repo, branch):
                    self.request = (owner, repo, branch)
                    return new_rev, new_rev[:12]

            class FakeHashComputer:
                def compute_native_hash(self, source, replacements):
                    self.source = source
                    self.replacements = replacements
                    return new_hash

            def update(transaction):
                github = FakeGitHubClient()
                hashes = FakeHashComputer()
                with contextlib.redirect_stdout(io.StringIO()):
                    status = update_catalog_target(
                        "example",
                        load_target(),
                        SimpleNamespace(version=None, dry_run=False),
                        github,
                        SimpleNamespace(),
                        SimpleNamespace(),
                        hashes,
                        transaction,
                    )
                self.assertEqual(status, "updated")
                self.assertEqual(github.identity, ("example", "project"))
                self.assertEqual(github.request, ("example", "project", "main"))
                self.assertEqual(hashes.replacements, {"rev": new_rev})
                return status

            write_old_state()
            rolled_back = SourceTransaction()
            self.assertEqual(update(rolled_back), "updated")
            self.assertIn(new_rev, catalog_path.read_text())
            self.assertIn(new_rev, flake_path.read_text())
            self.assertEqual(rolled_back.rollback(), 2)
            self.assertIn(old_rev, catalog_path.read_text())
            self.assertIn(old_rev, flake_path.read_text())

            committed = SourceTransaction()
            self.assertEqual(update(committed), "updated")
            committed.commit()
            record = json.loads(catalog_path.read_text())["sources"]["example"]
            self.assertEqual(record["source"]["args"]["rev"], new_rev)
            self.assertEqual(record["source"]["args"]["narHash"], new_hash)
            self.assertIn(new_rev, flake_path.read_text())
            self.assertNotIn(old_rev, flake_path.read_text())

    def test_fixed_flake_input_direct_invocation_delegates_to_update_agents(self):
        calls = []

        def fake_delegate(nix_dir, names, args):
            calls.append((nix_dir, names, args.version, args.dry_run))
            return 17

        globals_ = MODULE["main"].__globals__
        real_delegate = globals_["delegate_to_update"]
        old_argv = sys.argv
        try:
            globals_["delegate_to_update"] = fake_delegate
            sys.argv = [
                str(SCRIPT),
                "agent-browser-source",
                "--version",
                "b" * 40,
                "--dry-run",
            ]
            with contextlib.redirect_stdout(io.StringIO()):
                status = MODULE["main"]()
        finally:
            globals_["delegate_to_update"] = real_delegate
            sys.argv = old_argv

        self.assertEqual(status, 17)
        self.assertEqual(len(calls), 1)
        nix_dir, names, version, dry_run = calls[0]
        self.assertEqual(nix_dir, SCRIPT.parent.parent.resolve())
        self.assertEqual(names, ["agent-browser-source"])
        self.assertEqual(version, "b" * 40)
        self.assertTrue(dry_run)

        runner_calls = []

        def fake_runner(command, **kwargs):
            runner_calls.append((command, kwargs))
            return SimpleNamespace(returncode=23)

        delegated = MODULE["delegate_to_update"](
            Path("/repo"),
            ["agent-browser-source"],
            SimpleNamespace(version="b" * 40, dry_run=True),
            runner=fake_runner,
        )
        self.assertEqual(delegated, 23)
        command, kwargs = runner_calls[0]
        self.assertEqual(
            command[1:],
            [
                "--target",
                "agent-browser-source",
                "--version",
                "b" * 40,
                "--dry-run",
            ],
        )
        self.assertEqual(kwargs["cwd"], Path("/repo"))
        self.assertEqual(kwargs["env"]["NIX_CONFIG_DIR"], "/repo")
        self.assertFalse(kwargs["check"])

    def test_npm_flake_input_couples_registry_and_git_coordinates(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            (root / "config/ai").mkdir(parents=True)
            catalog_path = root / "sources/test.json"
            flake_path = root / "config/ai/flake.nix"
            old_rev = "a" * 40
            new_rev = "b" * 40

            def write_old_state():
                catalog_path.write_text(
                    json.dumps(
                        {
                            "schemaVersion": 1,
                            "sources": {
                                "example": {
                                    "version": "1.0.0",
                                    "source": {
                                        "fetcher": "fetchurl",
                                        "url": "https://registry.npmjs.org/example/-/example-1.0.0.tgz",
                                        "args": {
                                            "url": "https://registry.npmjs.org/example/-/example-1.0.0.tgz",
                                            "hash": "sha256-tar-old",
                                        },
                                    },
                                    "artifacts": {
                                        "flakeInput": {
                                            "fetcher": "fetchTree",
                                            "url": "https://github.com/example/project",
                                            "args": {
                                                "owner": "example",
                                                "repo": "project",
                                                "rev": old_rev,
                                                "narHash": "sha256-git-old",
                                                "type": "github",
                                            },
                                        }
                                    },
                                    "update": {
                                        "artifacts": ["config/ai/flake.nix"],
                                        "buildPackage": "candidate-package",
                                        "input": "example",
                                        "kind": "npm-release+flake-input",
                                        "package": "example",
                                    },
                                }
                            },
                        },
                        indent=2,
                    )
                    + "\n"
                )
                flake_path.write_text(
                    '{\n  inputs = {\n    example.url = "github:example/project";\n  };\n}\n'
                )

            def load_target():
                document = json.loads(catalog_path.read_text())
                record = document["sources"]["example"]
                return {
                    "_document": document,
                    "_path": catalog_path,
                    "_record": record,
                    "kind": "npm-release+flake-input",
                    "version": record["version"],
                }

            class FakeNpmClient:
                def get_version_metadata(self, package, requested):
                    self.request = (package, requested)
                    return {
                        "version": "2.0.0",
                        "integrity": "sha512-registry",
                        "gitHead": new_rev,
                    }

            class FakeHashComputer:
                def __init__(self):
                    self.calls = []

                def compute_native_hash(self, source, replacements):
                    self.calls.append((source["fetcher"], replacements))
                    return {
                        "fetchurl": "sha256-tar-new",
                        "fetchTree": "sha256-git-new",
                    }[source["fetcher"]]

            def update(transaction):
                npm = FakeNpmClient()
                hashes = FakeHashComputer()
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    status = update_npm_flake_target(
                        "example",
                        load_target(),
                        SimpleNamespace(version=None, dry_run=False),
                        npm,
                        hashes,
                        transaction,
                    )
                self.assertEqual(npm.request, ("example", None))
                self.assertEqual(
                    hashes.calls,
                    [
                        (
                            "fetchurl",
                            {
                                "url": "https://registry.npmjs.org/example/-/example-2.0.0.tgz"
                            },
                        ),
                    ],
                )
                return status, ANSI_ESCAPE_RE.sub("", output.getvalue())

            class HeadOnlyNpmClient:
                def get_version_metadata(self, package, requested):
                    self.request = (package, requested)
                    return {
                        "version": "1.0.0",
                        "integrity": "sha512-registry",
                        "gitHead": new_rev,
                    }

            write_old_state()
            head_only = SourceTransaction()
            head_only_npm = HeadOnlyNpmClient()
            head_only_hashes = FakeHashComputer()
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(
                    update_npm_flake_target(
                        "example",
                        load_target(),
                        SimpleNamespace(version=None, dry_run=False, verbose=False),
                        head_only_npm,
                        head_only_hashes,
                        head_only,
                    ),
                    "updated",
                )
            self.assertEqual(head_only_npm.request, ("example", None))
            self.assertEqual(
                ANSI_ESCAPE_RE.sub("", output.getvalue()),
                "catalog/example aaaaaaaa → bbbbbbbb ✓\n",
            )
            self.assertEqual(head_only.rollback(), 2)

            write_old_state()
            rolled_back = SourceTransaction()
            status, output = update(rolled_back)
            self.assertEqual(status, "updated")
            self.assertEqual(output, "catalog/example 1.0.0 → 2.0.0 ✓\n")
            candidate = json.loads(catalog_path.read_text())["sources"]["example"]
            self.assertEqual(candidate["artifacts"]["flakeInput"]["args"]["rev"], old_rev)
            self.assertEqual(
                candidate["artifacts"]["flakeInput"]["args"]["narHash"],
                "sha256-git-old",
            )
            self.assertIn(new_rev, flake_path.read_text())
            self.assertEqual(rolled_back.rollback(), 2)
            self.assertIn(old_rev, catalog_path.read_text())
            self.assertNotIn(new_rev, flake_path.read_text())

            committed = SourceTransaction()
            status, output = update(committed)
            self.assertEqual(status, "updated")
            self.assertEqual(output, "catalog/example 1.0.0 → 2.0.0 ✓\n")
            committed.commit()
            record = json.loads(catalog_path.read_text())["sources"]["example"]
            self.assertEqual(record["version"], "2.0.0")
            self.assertEqual(record["source"]["args"]["hash"], "sha256-tar-new")
            self.assertEqual(record["artifacts"]["flakeInput"]["args"]["rev"], old_rev)
            self.assertEqual(
                record["artifacts"]["flakeInput"]["args"]["narHash"],
                "sha256-git-old",
            )
            self.assertIn(new_rev, flake_path.read_text())

            lock = {
                "nodes": {
                    "root": {"inputs": {"example": "selected"}},
                    "selected": {
                        "locked": {
                            "narHash": "sha256-git-new",
                            "owner": "example",
                            "repo": "project",
                            "rev": new_rev,
                            "type": "github",
                        },
                        "original": {
                            "owner": "example",
                            "repo": "project",
                            "type": "github",
                        },
                    },
                },
                "root": "root",
                "version": 7,
            }
            (root / "config/ai/flake.lock").write_text(
                json.dumps(lock, indent=2) + "\n"
            )
            builds = []

            def validate_build(package, mode):
                candidate = json.loads(catalog_path.read_text())["sources"]["example"]
                builds.append(
                    (
                        package,
                        mode,
                        candidate["version"],
                        candidate["source"]["args"]["hash"],
                        candidate["artifacts"]["flakeInput"]["args"]["rev"],
                        candidate["artifacts"]["flakeInput"]["args"]["narHash"],
                    )
                )
                return True

            self.assertEqual(
                sync_flake_projections(root, "example"),
                1,
            )
            with mock.patch.dict(
                validate_catalog_target.__globals__,
                {"HashComputer": lambda _root: SimpleNamespace(
                    validate_package_build=validate_build
                )},
            ):
                self.assertTrue(
                    validate_catalog_target(
                        root, "example", load_source_catalog(root)["example"]
                    )
                )
            self.assertEqual(
                builds,
                [
                    (
                        "candidate-package",
                        "pkg",
                        "2.0.0",
                        "sha256-tar-new",
                        new_rev,
                        "sha256-git-new",
                    )
                ],
            )

            document = json.loads(catalog_path.read_text())
            document["sources"]["other"] = {
                "source": {
                    "fetcher": "fetchTree",
                    "url": "https://github.com/other/project",
                    "args": {
                        "owner": "other",
                        "repo": "project",
                        "rev": "0" * 40,
                        "narHash": "sha256-other-old",
                        "type": "github",
                    },
                },
                "update": {
                    "buildPackage": "other-package",
                    "input": "other",
                    "kind": "flake-input",
                },
            }
            catalog_path.write_text(json.dumps(document, indent=2) + "\n")
            lock["nodes"]["root"]["inputs"]["other"] = "other-selected"
            lock["nodes"]["other-selected"] = {
                "locked": {
                    "narHash": "sha256-other-new",
                    "owner": "other",
                    "repo": "project",
                    "rev": "c" * 40,
                    "type": "github",
                },
                "original": {
                    "owner": "other",
                    "repo": "project",
                    "type": "github",
                },
            }
            (root / "config/ai/flake.lock").write_text(
                json.dumps(lock, indent=2) + "\n"
            )
            flake_path.write_text(
                "{\n  inputs = {\n"
                f'    example.url = "github:example/project/{new_rev}";\n'
                f'    other.url = "github:other/project/{"c" * 40}";\n'
                "  };\n}\n"
            )
            before_other = copy.deepcopy(document["sources"]["other"])
            self.assertEqual(
                sync_flake_projections(root, "example"),
                0,
            )
            after_selected_sync = json.loads(catalog_path.read_text())
            self.assertEqual(after_selected_sync["sources"]["other"], before_other)
            with self.assertRaisesRegex(
                RuntimeError, "other rev does not match portable lock"
            ):
                load_source_catalog(root)

            write_old_state()
            before_catalog = catalog_path.read_text()
            before_flake = flake_path.read_text()
            missing_git_head = SimpleNamespace(
                get_version_metadata=lambda _package, _requested: {
                    "version": "2.0.0",
                    "integrity": "sha512-registry",
                }
            )
            with contextlib.redirect_stdout(io.StringIO()):
                refused = update_npm_flake_target(
                    "example",
                    load_target(),
                    SimpleNamespace(version=None, dry_run=False),
                    missing_git_head,
                    FakeHashComputer(),
                    SourceTransaction(),
                )
            self.assertEqual(refused, "failed")
            self.assertEqual(catalog_path.read_text(), before_catalog)
            self.assertEqual(flake_path.read_text(), before_flake)

            write_old_state()
            before_catalog = catalog_path.read_bytes()
            before_flake = flake_path.read_bytes()

            class RejectingSameHeadHashes(FakeHashComputer):
                def validate_package_build(self, package, mode="pkg"):
                    candidate = json.loads(catalog_path.read_text())["sources"][
                        "example"
                    ]
                    self.validation = (
                        package,
                        mode,
                        candidate["version"],
                        candidate["source"]["args"]["hash"],
                        candidate["artifacts"]["flakeInput"]["args"]["rev"],
                        candidate["artifacts"]["flakeInput"]["args"]["narHash"],
                    )
                    return False

            same_head_npm = SimpleNamespace(
                get_version_metadata=lambda _package, _requested: {
                    "version": "2.0.0",
                    "integrity": "sha512-registry",
                    "gitHead": old_rev,
                }
            )
            same_head_hashes = RejectingSameHeadHashes()
            same_head_transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                same_head_status = update_npm_flake_target(
                    "example",
                    load_target(),
                    SimpleNamespace(version=None, dry_run=False),
                    same_head_npm,
                    same_head_hashes,
                    same_head_transaction,
                )
            self.assertEqual(same_head_status, "updated")
            same_head_lock = {
                "nodes": {
                    "root": {"inputs": {"example": "selected"}},
                    "selected": {
                        "locked": {
                            "narHash": "sha256-git-old",
                            "owner": "example",
                            "repo": "project",
                            "rev": old_rev,
                            "type": "github",
                        },
                        "original": {
                            "owner": "example",
                            "repo": "project",
                            "type": "github",
                        },
                    },
                },
                "root": "root",
                "version": 7,
            }
            (root / "config/ai/flake.lock").write_text(
                json.dumps(same_head_lock, indent=2) + "\n"
            )
            self.assertEqual(sync_flake_projections(root, "example"), 0)
            with mock.patch.dict(
                validate_catalog_target.__globals__,
                {"HashComputer": lambda _root: same_head_hashes},
            ):
                self.assertFalse(
                    validate_catalog_target(
                        root, "example", load_source_catalog(root)["example"]
                    )
                )
            self.assertEqual(
                same_head_hashes.validation,
                (
                    "candidate-package",
                    "pkg",
                    "2.0.0",
                    "sha256-tar-new",
                    old_rev,
                    "sha256-git-old",
                ),
            )
            self.assertEqual(same_head_transaction.rollback(), 2)
            self.assertEqual(catalog_path.read_bytes(), before_catalog)
            self.assertEqual(flake_path.read_bytes(), before_flake)

            literal_transaction = SourceTransaction()
            literal_npm = SimpleNamespace(
                get_version_metadata=lambda _package, _requested: {
                    "version": "1.0.0",
                    "integrity": "sha512-registry",
                    "gitHead": old_rev,
                }
            )
            literal_hashes = FakeHashComputer()
            literal_hashes.compute_native_hash = lambda _source, _changes: "sha256-tar-old"
            with contextlib.redirect_stdout(io.StringIO()):
                literal_status = update_npm_flake_target(
                    "example",
                    load_target(),
                    SimpleNamespace(version=None, dry_run=False),
                    literal_npm,
                    literal_hashes,
                    literal_transaction,
                )
            self.assertEqual(literal_status, "updated")
            expected_repaired_flake = (
                b'{\n  inputs = {\n    example.url = "github:example/project/'
                + old_rev.encode("ascii")
                + b'";\n  };\n}\n'
            )
            self.assertEqual(flake_path.read_bytes(), expected_repaired_flake)
            self.assertEqual(sync_flake_projections(root, "example"), 0)
            literal_validations = []

            class LiteralCandidateHashComputer:
                def __init__(self, candidate_root):
                    self.candidate_root = candidate_root

                def validate_package_build(self, package, mode):
                    candidate_bytes = (
                        self.candidate_root / "config/ai/flake.nix"
                    ).read_bytes()
                    literal_validations.append(
                        (self.candidate_root, package, mode, candidate_bytes)
                    )
                    return candidate_bytes == expected_repaired_flake

            with mock.patch.dict(
                validate_catalog_target.__globals__,
                {"HashComputer": LiteralCandidateHashComputer},
            ):
                self.assertTrue(
                    validate_catalog_target(
                        root, "example", load_source_catalog(root)["example"]
                    )
                )

            wrong_root = root / "wrong-root"
            wrong_flake = wrong_root / "config/ai/flake.nix"
            wrong_flake.parent.mkdir(parents=True)
            wrong_bytes = b"this is not the candidate flake\n"
            wrong_flake.write_bytes(wrong_bytes)
            self.assertFalse(
                LiteralCandidateHashComputer(wrong_root).validate_package_build(
                    "candidate-package", "pkg"
                )
            )

            newline_root = root / "newline-root"
            newline_flake = newline_root / "config/ai/flake.nix"
            newline_flake.parent.mkdir(parents=True)
            newline_bytes = expected_repaired_flake.replace(b"\n", b"\r\n")
            newline_flake.write_bytes(newline_bytes)
            self.assertFalse(
                LiteralCandidateHashComputer(newline_root).validate_package_build(
                    "candidate-package", "pkg"
                )
            )
            self.assertEqual(
                literal_validations,
                [
                    (
                        root,
                        "candidate-package",
                        "pkg",
                        expected_repaired_flake,
                    ),
                    (wrong_root, "candidate-package", "pkg", wrong_bytes),
                    (newline_root, "candidate-package", "pkg", newline_bytes),
                ],
            )
            literal_transaction.commit()

            no_op_transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                no_op_status = update_npm_flake_target(
                    "example",
                    load_target(),
                    SimpleNamespace(version=None, dry_run=False),
                    literal_npm,
                    literal_hashes,
                    no_op_transaction,
                )
            self.assertEqual(no_op_status, "skipped")
            self.assertEqual(no_op_transaction.original, {})

            drifted = json.loads(catalog_path.read_text())
            drifted["sources"]["example"]["version"] = "2.0.0"
            catalog_path.write_text(json.dumps(drifted, indent=2) + "\n")
            before_catalog = catalog_path.read_text()
            before_flake = flake_path.read_text()
            with contextlib.redirect_stdout(io.StringIO()):
                refused = update_npm_flake_target(
                    "example",
                    load_target(),
                    SimpleNamespace(version=None, dry_run=False),
                    FakeNpmClient(),
                    FakeHashComputer(),
                    SourceTransaction(),
                )
            self.assertEqual(refused, "failed")
            self.assertEqual(catalog_path.read_text(), before_catalog)
            self.assertEqual(flake_path.read_text(), before_flake)

    def test_source_catalog_rejects_ambiguous_native_fetcher_shapes(self):
        valid = {
            "version": "1.0.0",
            "source": {
                "fetcher": "fetchFromGitHub",
                "url": "https://github.com/example/project",
                "args": {
                    "owner": "example",
                    "repo": "project",
                    "rev": "deadbeef",
                    "hash": "sha256-source",
                },
            },
            "update": {"kind": "github-commit", "branch": "main"},
        }

        def load(record, document_extra=None):
            with tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                (root / "sources").mkdir()
                document = {"schemaVersion": 1, "sources": {"example": record}}
                document.update(document_extra or {})
                (root / "sources/test.json").write_text(json.dumps(document))
                return load_source_catalog(root)

        tag = copy.deepcopy(valid)
        tag.pop("version")
        tag["source"]["args"]["tag"] = tag["source"]["args"].pop("rev")
        tag["update"] = {"kind": "github-release"}
        self.assertEqual(load(tag)["example"]["version"], "deadbeef")

        stable = copy.deepcopy(tag)
        stable["update"]["stableOnly"] = True
        self.assertTrue(
            load(stable)["example"]["_record"]["update"]["stableOnly"]
        )

        manual = copy.deepcopy(valid)
        manual["update"].update(policy="manual", reason="Compatibility hold")
        self.assertEqual(
            load(manual)["example"]["_record"]["update"]["policy"], "manual"
        )

        invalid = []
        invalid_stable_type = copy.deepcopy(tag)
        invalid_stable_type["update"]["stableOnly"] = "yes"
        invalid.append(invalid_stable_type)

        stable_on_commit = copy.deepcopy(valid)
        stable_on_commit["update"]["stableOnly"] = True
        invalid.append(stable_on_commit)
        both_refs = copy.deepcopy(valid)
        both_refs["source"]["args"]["tag"] = "v1.0.0"
        invalid.append(both_refs)

        both_hashes = copy.deepcopy(valid)
        both_hashes["source"]["args"]["sha256"] = "sha256-other"
        invalid.append(both_hashes)

        wrong_identity = copy.deepcopy(valid)
        wrong_identity["source"]["url"] = "https://github.com/other/project"
        invalid.append(wrong_identity)

        wrong_update_field = copy.deepcopy(valid)
        wrong_update_field["update"]["package"] = "project"
        invalid.append(wrong_update_field)

        bad_artifacts = copy.deepcopy(valid)
        bad_artifacts["artifacts"] = []
        invalid.append(bad_artifacts)

        bad_hashes = copy.deepcopy(valid)
        bad_hashes["hashes"] = []
        invalid.append(bad_hashes)

        fetchurl_without_url = copy.deepcopy(valid)
        fetchurl_without_url["source"] = {
            "fetcher": "fetchurl",
            "url": "https://example.invalid/archive.tgz",
            "args": {"hash": "sha256-source"},
        }
        invalid.append(fetchurl_without_url)

        insecure_fetch_url = copy.deepcopy(fetchurl_without_url)
        insecure_fetch_url["source"]["args"]["url"] = (
            "http://example.invalid/archive.tgz"
        )
        invalid.append(insecure_fetch_url)

        commit_tag = copy.deepcopy(valid)
        commit_tag["source"]["args"]["tag"] = commit_tag["source"]["args"].pop("rev")
        invalid.append(commit_tag)

        unsafe_artifact = copy.deepcopy(valid)
        unsafe_artifact["update"]["artifacts"] = ["../outside"]
        invalid.append(unsafe_artifact)

        empty_reason = copy.deepcopy(valid)
        empty_reason["update"]["reason"] = ""
        invalid.append(empty_reason)

        unreasoned_manual = copy.deepcopy(valid)
        unreasoned_manual["update"]["policy"] = "manual"
        invalid.append(unreasoned_manual)

        bad_pypi_identity = {
            "version": "1.0.0",
            "source": {
                "fetcher": "fetchPypi",
                "url": "https://pypi.org/project/other",
                "args": {
                    "pname": "example",
                    "version": "1.0.0",
                    "hash": "sha256-source",
                },
            },
            "update": {"kind": "pypi-release", "package": "example"},
        }
        invalid.append(bad_pypi_identity)

        bad_pypi_version = copy.deepcopy(bad_pypi_identity)
        bad_pypi_version["source"]["url"] = "https://pypi.org/project/example"
        bad_pypi_version["version"] = "2.0.0"
        invalid.append(bad_pypi_version)

        for record in invalid:
            with self.subTest(record=record):
                with self.assertRaises(RuntimeError):
                    load(record)

        with self.assertRaisesRegex(RuntimeError, "document fields"):
            load(valid, {"unexpected": True})

    def test_github_client_does_not_change_declared_selection_strategy(self):
        calls = []

        def failed_run(command, **_kwargs):
            calls.append(command)
            return SimpleNamespace(returncode=1, stdout="")

        real_run = subprocess.run
        subprocess.run = failed_run
        try:
            client = GitHubClient()
            self.assertIsNone(client.get_latest_release("example", "project"))
            self.assertIsNone(client.get_latest_tag("example", "project", "v"))
            self.assertIsNone(client.get_default_branch("example", "project"))
            self.assertIsNone(client.get_latest_commit("example", "project", "topic"))
            self.assertIsNone(
                client.get_file("example", "project", "a" * 40, "Cargo.lock")
            )
        finally:
            subprocess.run = real_run

        self.assertEqual(len(calls), 6)
        self.assertIn("releases/latest", calls[0][2])
        self.assertIn("tags?per_page=100", calls[1][2])
        self.assertEqual("repos/example/project", calls[2][2])
        self.assertIn("commits/topic", calls[3][2])
        self.assertEqual("repos/example/project", calls[4][2])
        self.assertEqual(calls[5][:2], ["gh", "api"])
        self.assertIn(f"contents/Cargo.lock?ref={'a' * 40}", calls[5][2])

        successful_calls = []
        responses = [
            json.dumps(
                {
                    "content": "ZXhhY3QgY29udGVudHMK",
                    "encoding": "base64",
                    "type": "file",
                }
            ),
            json.dumps([{"name": "Cargo.lock", "type": "file"}]),
            json.dumps(
                {
                    "content": "%%%",
                    "encoding": "base64",
                    "type": "file",
                }
            ),
        ]

        def successful_run(command, **kwargs):
            successful_calls.append((command, kwargs))
            return SimpleNamespace(returncode=0, stdout=responses.pop(0))

        subprocess.run = successful_run
        try:
            client = GitHubClient()
            content = client.get_file(
                "example", "project", "b" * 40, "locks/Cargo lock"
            )
            self.assertIsNone(client.get_file("example", "project", "b" * 40, "locks"))
            self.assertIsNone(client.get_file("example", "project", "b" * 40, "bad"))
        finally:
            subprocess.run = real_run
        self.assertEqual(content, "exact contents\n")
        self.assertEqual(len(successful_calls), 3)
        command, kwargs = successful_calls[0]
        self.assertEqual(command[:2], ["gh", "api"])
        self.assertIn(f"contents/locks/Cargo%20lock?ref={'b' * 40}", command[2])
        self.assertEqual(kwargs["timeout"], 60)

    def test_github_stable_release_lookup_rejects_semantic_prereleases(self):
        calls = []
        response = SimpleNamespace(
            returncode=0,
            stdout=json.dumps(
                [
                    {"tag_name": "v0.6.3rc3", "draft": False, "prerelease": False},
                    {"tag_name": "v0.6.3-beta.1", "draft": False, "prerelease": False},
                    {"tag_name": "v0.6.3a1", "draft": False, "prerelease": False},
                    {"tag_name": "v9.0.0", "draft": True, "prerelease": False},
                    {"tag_name": "v0.6.2", "draft": False, "prerelease": False},
                ]
            ),
            stderr="",
        )

        def fake_run(command, **_kwargs):
            calls.append(command)
            return response

        real_run = subprocess.run
        subprocess.run = fake_run
        try:
            client = GitHubClient()
            self.assertEqual(
                client.get_latest_stable_release("jundot", "omlx", "v"),
                "v0.6.2",
            )
            self.assertIsNone(client.last_error)
        finally:
            subprocess.run = real_run

        self.assertEqual(len(calls), 1)
        self.assertIn("repos/jundot/omlx/releases?per_page=100", calls[0][2])

    def test_github_tag_lookup_selects_first_matching_prefix(self):
        response = SimpleNamespace(
            returncode=0,
            stdout=json.dumps(
                [
                    {"name": "nightly"},
                    {"name": "v2.0.0"},
                    {"name": "v1.0.0"},
                ]
            ),
            stderr="",
        )

        def fake_run(_command, **_kwargs):
            return response

        real_run = subprocess.run
        subprocess.run = fake_run
        try:
            client = GitHubClient()
            self.assertEqual(
                client.get_latest_tag("example", "project", "v"), "v2.0.0"
            )
            self.assertIsNone(client.last_error)
        finally:
            subprocess.run = real_run

    def test_github_commit_failure_reports_requested_and_default_branches(self):
        responses = [
            SimpleNamespace(
                returncode=1,
                stdout="",
                stderr="gh: branch topic was not found\n",
            ),
            SimpleNamespace(returncode=0, stdout="main\n", stderr=""),
        ]

        def fake_run(_command, **_kwargs):
            return responses.pop(0)

        real_run = subprocess.run
        subprocess.run = fake_run
        try:
            client = GitHubClient()
            self.assertIsNone(client.get_latest_commit("example", "project", "topic"))
        finally:
            subprocess.run = real_run

        self.assertIn("example/project", client.last_error)
        self.assertIn("requested branch 'topic'", client.last_error)
        self.assertIn("repository default branch is 'main'", client.last_error)
        self.assertIn("branch topic was not found", client.last_error)

    def test_github_diagnostics_reset_and_default_lookup_has_safe_fallback(self):
        responses = [
            SimpleNamespace(returncode=1, stdout="", stderr="release missing"),
            SimpleNamespace(
                returncode=0,
                stdout=json.dumps({"tag_name": "v2.0.0"}),
                stderr="",
            ),
            SimpleNamespace(returncode=1, stdout="", stderr="repository missing"),
            SimpleNamespace(returncode=0, stdout="trunk\n", stderr=""),
        ]

        def fake_run(_command, **_kwargs):
            return responses.pop(0)

        real_run = subprocess.run
        subprocess.run = fake_run
        try:
            client = GitHubClient()
            self.assertIsNone(client.get_latest_release("example", "project"))
            self.assertIn("release missing", client.last_error)
            self.assertEqual(client.get_latest_release("example", "project"), "v2.0.0")
            self.assertIsNone(client.last_error)
            self.assertIsNone(client.get_default_branch("example", "project"))
            self.assertIn("repository missing", client.last_error)
            self.assertEqual(client.get_default_branch("example", "project"), "trunk")
            self.assertIsNone(client.last_error)
        finally:
            subprocess.run = real_run

        def raising_run(_command, **_kwargs):
            raise OSError("gh executable unavailable")

        subprocess.run = raising_run
        try:
            client = GitHubClient()
            self.assertIsNone(client.get_latest_commit("example", "project", "missing"))
        finally:
            subprocess.run = real_run
        self.assertIn("requested branch 'missing'", client.last_error)
        self.assertIn("default branch is unavailable", client.last_error)
        self.assertIn("gh executable unavailable", client.last_error)

    def test_cargo_lock_validation_uses_exact_checkout(self):
        revision = "c" * 40
        lock = 'version = 4\n\n[[package]]\nname = "project"\nversion = "1.0.0"\n'
        calls = []
        cargo_succeeds = True

        def fake_run(command, **kwargs):
            calls.append((command, kwargs))
            if command[:3] == ["git", "init", "--quiet"]:
                Path(command[3]).mkdir(parents=True)
            elif command[0] == "git" and command[3:] == [
                "checkout",
                "--quiet",
                "--detach",
                "FETCH_HEAD",
            ]:
                checkout = Path(command[2])
                (checkout / "Cargo.toml").write_text(
                    '[package]\nname = "project"\nversion = "1.0.0"\n'
                )
                (checkout / "Cargo.lock").write_text(lock)
            if command[0] == "git" and command[-2:] == ["rev-parse", "HEAD"]:
                return SimpleNamespace(returncode=0, stdout=f"{revision}\n")
            if command[0] == "cargo":
                return SimpleNamespace(
                    returncode=0 if cargo_succeeds else 1,
                    stdout="",
                )
            return SimpleNamespace(returncode=0, stdout="")

        real_run = subprocess.run
        subprocess.run = fake_run
        try:
            computer = HashComputer(Path.cwd())
            self.assertTrue(
                computer.validate_cargo_lock(
                    "https://github.com/example/project",
                    revision,
                    "Cargo.lock",
                    lock,
                )
            )
            cargo_succeeds = False
            self.assertFalse(
                computer.validate_cargo_lock(
                    "https://github.com/example/project",
                    revision,
                    "Cargo.lock",
                    lock,
                )
            )
            before_unsafe = len(calls)
            self.assertFalse(
                computer.validate_cargo_lock(
                    "https://github.com/example/project",
                    revision,
                    "../Cargo.lock",
                    lock,
                )
            )
            self.assertEqual(len(calls), before_unsafe)
        finally:
            subprocess.run = real_run

        first_fetch = next(
            command
            for command, _kwargs in calls
            if command[0] == "git" and "fetch" in command
        )
        self.assertEqual(
            first_fetch[-2:],
            [
                "https://github.com/example/project",
                revision,
            ],
        )
        checkout_command = next(
            command
            for command, _kwargs in calls
            if command[0] == "git" and "checkout" in command
        )
        self.assertEqual(
            checkout_command[3:],
            ["checkout", "--quiet", "--detach", "FETCH_HEAD"],
        )
        cargo_command, cargo_kwargs = next(
            (command, kwargs) for command, kwargs in calls if command[0] == "cargo"
        )
        self.assertIn("--locked", cargo_command)
        self.assertIn("--offline", cargo_command)
        self.assertIn("--no-deps", cargo_command)
        self.assertEqual(cargo_kwargs["env"]["CARGO_NET_OFFLINE"], "true")

    def test_manual_url_target_has_targeted_executor(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/tools.json"
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {
                            "example": {
                                "source": {
                                    "fetcher": "fetchurl",
                                    "url": "https://example.invalid/tool",
                                    "args": {
                                        "url": "https://example.invalid/tool",
                                        "sha256": "old-hash",
                                    },
                                },
                                "update": {
                                    "kind": "url-release",
                                    "policy": "manual",
                                    "reason": "Fixture requires an explicit update",
                                },
                            }
                        },
                    }
                )
            )
            target = load_source_catalog(root)["example"]
            self.assertEqual(target["executor"], "update-overlay")

            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_catalog_target(
                    "example",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    SimpleNamespace(),
                    SimpleNamespace(),
                    SimpleNamespace(),
                    SimpleNamespace(
                        compute_native_hash=lambda _source, _replacements: "new-hash"
                    ),
                    transaction,
                )
            transaction.commit()
            self.assertEqual(status, "updated")
            self.assertEqual(
                json.loads(path.read_text())["sources"]["example"]["source"]["args"][
                    "sha256"
                ],
                "new-hash",
            )
            with contextlib.redirect_stdout(io.StringIO()):
                rejected = update_catalog_target(
                    "example",
                    load_source_catalog(root)["example"],
                    SimpleNamespace(version="2.0.0", dry_run=False),
                    SimpleNamespace(),
                    SimpleNamespace(),
                    SimpleNamespace(),
                    SimpleNamespace(
                        compute_native_hash=lambda _source, _replacements: "ignored"
                    ),
                    SourceTransaction(),
                )
            self.assertEqual(rejected, "failed")

    def test_native_hash_uses_locked_fetcher_and_normalizes_to_sri(self):
        calls = []

        def fake_run(command, **_kwargs):
            calls.append(command)
            return SimpleNamespace(
                returncode=1,
                stdout="",
                stderr="got: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n",
            )

        real_run = subprocess.run
        subprocess.run = fake_run
        try:
            value = MODULE["HashComputer"](Path("/repo")).compute_native_hash(
                {
                    "fetcher": "fetchurl",
                    "url": "https://example.invalid/tool",
                    "args": {
                        "url": "https://example.invalid/tool",
                        "sha256": "old-nix32",
                    },
                },
                {},
            )
            zip_value = MODULE["HashComputer"](Path("/repo")).compute_native_hash(
                {
                    "fetcher": "fetchzip",
                    "url": "https://registry.npmjs.org/example/-/example-1.0.0.tgz",
                    "args": {
                        "url": "https://registry.npmjs.org/example/-/example-1.0.0.tgz",
                        "hash": "sha256-old",
                    },
                },
                {"url": "https://registry.npmjs.org/example/-/example-2.0.0.tgz"},
            )
        finally:
            subprocess.run = real_run

        self.assertEqual(
            value, "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        )
        self.assertIn("nix-config-ai.inputs.nixpkgs", calls[0][-1])
        self.assertEqual(
            zip_value, "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        )
        self.assertIn("pkgs.fetchzip", calls[1][-1])
        self.assertIn("example-2.0.0.tgz", calls[1][-1])
        self.assertNotIn("example-1.0.0.tgz", calls[1][-1])

    def test_native_hash_surfaces_sanitized_actionable_nix_failure(self):
        real_shaped_stderr = (
            "\x1b[31;1merror:\x1b[0m Cannot build '/nix/store/example.drv'.\n"
            "       Last 3 log lines:\n"
            "       > \x1b]8;;https://codeberg.org/example/gone\x1b\\"
            "fatal: repository 'https://codeberg.org/example/gone' not found"
            "\x1b]8;;\x1b\\\x00\n"
            "       > ERROR: git fetch failed for the declared source\n"
            "       > Unable to checkout the requested revision\n"
            + ("       > unhelpful trailing noise\n" * 100)
        )
        responses = [
            SimpleNamespace(returncode=1, stdout="", stderr=real_shaped_stderr),
            SimpleNamespace(
                returncode=1,
                stdout="",
                stderr=(
                    "error: hash mismatch in fixed-output derivation\n"
                    "  got: sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=\n"
                ),
            ),
        ]

        def fake_run(_command, **_kwargs):
            return responses.pop(0)

        source = {
            "fetcher": "fetchurl",
            "args": {
                "url": "https://example.invalid/source.tgz",
                "hash": "sha256-old",
            },
        }
        real_run = subprocess.run
        subprocess.run = fake_run
        try:
            hashes = HashComputer(Path("/repo"))
            self.assertIsNone(hashes.compute_native_hash(source, {}))
            detail = hashes.last_error
            self.assertIsNotNone(detail)
            self.assertIn("fatal: repository", detail)
            self.assertIn("https://codeberg.org/example/gone", detail)
            self.assertIn("ERROR: git fetch", detail)
            self.assertIn("Unable to checkout", detail)
            self.assertNotIn("Cannot build", detail)
            self.assertNotIn("\x1b", detail)
            self.assertNotIn("\x00", detail)
            self.assertNotIn(" > ", detail)
            self.assertLessEqual(len(detail), MODULE["MAX_ACTIONABLE_ERROR_CHARS"])
            self.assertEqual(
                hashes.compute_native_hash(source, {}),
                "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",
            )
            self.assertIsNone(hashes.last_error)
        finally:
            subprocess.run = real_run

    def test_native_hash_records_exception_and_fetchtree_failures(self):
        source = {
            "fetcher": "fetchurl",
            "args": {
                "url": "https://example.invalid/source.tgz",
                "sha256": "old-nix32",
            },
        }
        real_run = subprocess.run

        def raising_run(_command, **_kwargs):
            raise OSError("nix executable unavailable")

        subprocess.run = raising_run
        try:
            hashes = HashComputer(Path("/repo"))
            self.assertIsNone(hashes.compute_native_hash(source, {}))
        finally:
            subprocess.run = real_run
        self.assertIn("native source hash computation failed", hashes.last_error)
        self.assertIn("nix executable unavailable", hashes.last_error)

        fetch_tree = {
            "fetcher": "fetchTree",
            "args": {
                "owner": "example",
                "repo": "project",
                "rev": "a" * 40,
                "narHash": "sha256-old",
                "type": "github",
            },
        }

        def fetch_tree_run(_command, **_kwargs):
            return SimpleNamespace(
                returncode=1,
                stdout="",
                stderr="       > Unable to resolve the declared revision\n",
            )

        subprocess.run = fetch_tree_run
        try:
            self.assertIsNone(hashes.compute_native_hash(fetch_tree, {}))
        finally:
            subprocess.run = real_run
        self.assertIn("fetchTree hash evaluation failed", hashes.last_error)
        self.assertIn("Unable to resolve", hashes.last_error)

        def invalid_json_run(_command, **_kwargs):
            return SimpleNamespace(returncode=0, stdout="not-json", stderr="")

        subprocess.run = invalid_json_run
        try:
            self.assertIsNone(hashes.compute_native_hash(fetch_tree, {}))
        finally:
            subprocess.run = real_run
        self.assertIn("native source hash computation failed", hashes.last_error)

    def test_update_callers_preserve_target_context_with_underlying_detail(self):
        target = {
            "_record": {
                "version": "1.0.0",
                "source": {
                    "fetcher": "fetchurl",
                    "url": "https://example.invalid/project-1.0.0.tgz",
                    "args": {
                        "url": "https://example.invalid/project-1.0.0.tgz",
                        "hash": "sha256-old",
                    },
                },
                "update": {"kind": "url-release"},
            },
            "_path": Path("/repo/sources/test.json"),
        }

        class FailedHashes:
            last_error = "native fetcher build failed: fatal: repository not found"

            def compute_native_hash(self, _source, _replacements):
                return None

        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = update_catalog_target(
                "project",
                target,
                SimpleNamespace(version=None, dry_run=False),
                SimpleNamespace(),
                SimpleNamespace(),
                SimpleNamespace(),
                FailedHashes(),
                SimpleNamespace(),
            )
        self.assertEqual(status, "failed")
        self.assertIn("catalog/project", output.getvalue())
        self.assertIn("hash failed: native fetcher build failed", output.getvalue())
        self.assertIn("fatal: repository not found", output.getvalue())

        commit_target = copy.deepcopy(target)
        commit_target["_record"] = {
            "version": "aaaaaaaa",
            "source": {
                "fetcher": "fetchFromGitHub",
                "url": "https://github.com/example/project",
                "args": {
                    "owner": "example",
                    "repo": "project",
                    "rev": "a" * 40,
                    "hash": "sha256-old",
                },
            },
            "update": {"kind": "github-commit", "branch": "gone"},
        }

        class FailedGitHub:
            last_error = None

            def get_latest_commit(self, _owner, _repo, _branch):
                self.last_error = (
                    "GitHub commit lookup failed for example/project; "
                    "requested branch 'gone'; repository default branch is 'main'"
                )
                return None

        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = update_catalog_target(
                "project",
                commit_target,
                SimpleNamespace(version=None, dry_run=False),
                FailedGitHub(),
                SimpleNamespace(),
                SimpleNamespace(),
                FailedHashes(),
                SimpleNamespace(),
            )
        self.assertEqual(status, "failed")
        self.assertIn("catalog/project", output.getvalue())
        self.assertIn("fetch failed: GitHub commit lookup failed", output.getvalue())
        self.assertIn("requested branch 'gone'", output.getvalue())

    def test_source_only_pypi_current_release_is_silent(self):
        artifact_url = "https://files.pythonhosted.org/example-1.0.0.whl"
        sources = {
            "fetchPypi": {
                "fetcher": "fetchPypi",
                "url": "https://pypi.org/project/example",
                "args": {
                    "pname": "example",
                    "version": "1.0.0",
                    "hash": "sha256-current",
                },
            },
            "fetchurl": {
                "fetcher": "fetchurl",
                "url": artifact_url,
                "args": {
                    "url": artifact_url,
                    "hash": "sha256-current",
                },
            },
        }

        for fetcher, source in sources.items():
            with (
                self.subTest(fetcher=fetcher),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                root = Path(temp_dir)
                (root / "sources").mkdir()
                path = root / "sources/ai.json"
                path.write_text(
                    json.dumps(
                        {
                            "schemaVersion": 1,
                            "sources": {
                                "example": {
                                    "version": "1.0.0",
                                    "source": source,
                                    "update": {
                                        "kind": "pypi-release",
                                        "package": "example",
                                        "buildPackage": "example",
                                        "buildMode": "pkg",
                                    },
                                }
                            },
                        }
                    )
                )
                before = path.read_bytes()
                target = load_source_catalog(root)["example"]
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    status = update_catalog_target(
                        "example",
                        target,
                        SimpleNamespace(version=None, dry_run=False),
                        SimpleNamespace(),
                        SimpleNamespace(),
                        SimpleNamespace(
                            get_release=lambda _package, _record, _requested=None: (
                                "1.0.0",
                                artifact_url,
                                "sha256-current",
                            )
                        ),
                        SimpleNamespace(validate_package_build=lambda *_args: True),
                        SourceTransaction(),
                    )

                self.assertEqual(status, "skipped")
                self.assertEqual(path.read_bytes(), before)
                self.assertEqual(output.getvalue(), "")

                verbose_output = io.StringIO()
                with (
                    mock.patch.dict(os.environ, {"UPDATE_VERBOSE": "1"}),
                    contextlib.redirect_stdout(verbose_output),
                ):
                    verbose_status = update_catalog_target(
                        "example",
                        load_source_catalog(root)["example"],
                        SimpleNamespace(version=None, dry_run=False),
                        SimpleNamespace(),
                        SimpleNamespace(),
                        SimpleNamespace(
                            get_release=lambda _package, _record, _requested=None: (
                                "1.0.0",
                                artifact_url,
                                "sha256-current",
                            )
                        ),
                        SimpleNamespace(validate_package_build=lambda *_args: True),
                        SourceTransaction(),
                    )
                self.assertEqual(verbose_status, "skipped")
                self.assertEqual(
                    MODULE["ANSI_ESCAPE_RE"].sub("", verbose_output.getvalue()),
                    "catalog/example ✓ up-to-date\n",
                )

    def test_catalog_npm_update_rewrites_source_and_dependent_hash_atomically(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/ai.json"
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {
                            "example": {
                                "version": "1.0.0",
                                "source": {
                                    "fetcher": "fetchzip",
                                    "url": "https://registry.npmjs.org/example/-/example-1.0.0.tgz",
                                    "args": {
                                        "url": "https://registry.npmjs.org/example/-/example-1.0.0.tgz",
                                        "hash": "sha512-old",
                                    },
                                },
                                "hashes": {"npmDepsHash": "sha256-old"},
                                "update": {"kind": "npm-release", "package": "example"},
                            }
                        },
                    }
                )
            )
            target = load_source_catalog(root)["example"]

            class FakeNpmClient:
                def get_version(self, _package, _requested=None):
                    return "2.0.0", "sha512-new"

            class FakeHashComputer:
                def compute_native_hash(self, source, _replacements):
                    self.source_fetcher = source["fetcher"]
                    return "sha256-native"

                def _compute_fod_hash(self, _package, hash_type):
                    self.hash_type = hash_type
                    return "sha256-new"

            transaction = SourceTransaction()
            hash_computer = FakeHashComputer()
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                status = update_catalog_target(
                    "example",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    SimpleNamespace(),
                    FakeNpmClient(),
                    SimpleNamespace(),
                    hash_computer,
                    transaction,
                )
            transaction.commit()
            record = json.loads(path.read_text())["sources"]["example"]
            self.assertEqual(status, "updated")
            self.assertIn(
                "catalog/example 1.0.0 → 2.0.0 ✓",
                MODULE["ANSI_ESCAPE_RE"].sub("", output.getvalue()),
            )
            self.assertEqual(record["version"], "2.0.0")
            self.assertEqual(record["source"]["args"]["hash"], "sha256-native")
            self.assertIn("example-2.0.0.tgz", record["source"]["args"]["url"])
            self.assertEqual(record["hashes"]["npmDepsHash"], "sha256-new")
            self.assertEqual(hash_computer.source_fetcher, "fetchzip")

            no_op_target = load_source_catalog(root)["example"]
            no_op_transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                no_op = update_catalog_target(
                    "example",
                    no_op_target,
                    SimpleNamespace(version=None, dry_run=False),
                    SimpleNamespace(),
                    FakeNpmClient(),
                    SimpleNamespace(),
                    FakeHashComputer(),
                    no_op_transaction,
                )
            no_op_transaction.commit()
            self.assertEqual(no_op, "skipped")

            before_failure = path.read_text()
            failing_target = load_source_catalog(root)["example"]
            failing_transaction = SourceTransaction()
            failing_npm = SimpleNamespace(
                get_version=lambda _package, _requested=None: ("3.0.0", "sha512-next")
            )
            failing_hashes = SimpleNamespace(
                compute_native_hash=lambda _source, _replacements: "sha512-next",
                _compute_fod_hash=lambda _package, _kind: None,
            )
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_catalog_target(
                    "example",
                    failing_target,
                    SimpleNamespace(version=None, dry_run=False),
                    SimpleNamespace(),
                    failing_npm,
                    SimpleNamespace(),
                    failing_hashes,
                    failing_transaction,
                )
            self.assertEqual(status, "failed")
            self.assertEqual(failing_transaction.rollback(), 1)
            self.assertEqual(path.read_text(), before_failure)

    def test_source_only_catalog_update_validates_candidate_and_rolls_back_rejection(self):
        ai_catalog = json.loads((REPO / "sources/ai.json").read_text())["sources"]
        catalog = load_source_catalog(REPO)
        updates = {
            name: target["_record"]["update"] for name, target in catalog.items()
        }
        self.assertEqual(updates["llm-agents"]["kind"], "flake-input")
        self.assertEqual(
            updates["llm-agents"]["buildPackage"], "pi-extension-tests"
        )
        self.assertEqual(updates["llm-agents"]["buildMode"], "check")
        automatic_pypi = {
            name
            for name, update in updates.items()
            if update["kind"] == "pypi-release"
            and update.get("policy", "automatic") == "automatic"
        }
        self.assertEqual(automatic_pypi, set(PYPI_CANDIDATE_BUILDS))
        for package, (build_package, build_mode) in PYPI_CANDIDATE_BUILDS.items():
            with self.subTest(package=package):
                self.assertEqual(
                    updates[package].get("buildPackage"),
                    build_package,
                )
                self.assertEqual(
                    updates[package].get("buildMode"),
                    build_mode,
                )
        mlx_audio = ai_catalog["mlx-audio"]
        self.assertEqual(mlx_audio["update"].get("buildPackage"), "mlx-audio")
        self.assertEqual(mlx_audio["update"].get("buildMode"), "python")
        mlx_vlm = ai_catalog["mlx-vlm"]
        self.assertEqual(mlx_vlm["update"].get("buildPackage"), "omlx")
        self.assertEqual(mlx_vlm["update"].get("buildMode"), "pkg")
        ddgs = ai_catalog["ddgs"]
        self.assertEqual(ddgs["update"].get("buildPackage"), "omlx")
        self.assertEqual(ddgs["update"].get("buildMode"), "pkg")
        omlx = ai_catalog["omlx"]
        self.assertEqual(omlx["version"], "0.6.2")
        self.assertTrue(omlx["update"].get("stableOnly"))
        pal = ai_catalog["pal-mcp-server"]
        self.assertEqual(pal["update"].get("buildPackage"), "pal-mcp-server")
        self.assertNotIn("buildMode", pal["update"])
        llama_cpp = ai_catalog["llama-cpp"]
        self.assertEqual(llama_cpp["update"].get("kind"), "github-release")
        self.assertEqual(llama_cpp["update"].get("tagPrefix"), "v")
        self.assertEqual(
            llama_cpp["update"].get("buildPackage"),
            "llama-cpp-update-validator",
        )
        self.assertEqual(
            llama_cpp["source"]["args"]["tag"],
            f"v{llama_cpp['version']}",
        )

        catalog = json.loads((REPO / "sources/pi.json").read_text())["sources"]
        pi_lens_update = catalog["pi-lens"]["update"]
        self.assertEqual(pi_lens_update.get("policy"), "manual")
        self.assertIn("inactive", pi_lens_update["reason"].lower())
        expected_builds = {
            "agent-browser": "agent-browser",
            "pi-agent-browser-native": "pi-agent-browser-native",
            "pi-btw": "pi-btw",
            "pi-cache-optimizer": "pi-cache-optimizer",
            "pi-caveman": "pi-caveman",
            "pi-copy-message": "pi-copy-message",
            "pi-droid-sdk": "pi-droid-sdk",
            "pi-goal-x": "pi-goal-x",
            "pi-loop": "pi-loop",
            "pi-mcp-adapter": "agent-resources",
            "pi-multi-pass": "pi-multi-pass",
            "pi-openai-server-compaction": "agent-resources",
            "pi-ponytail": "pi-gallery",
            "pi-quiet": "agent-resources",
            "pi-rewind": "pi-rewind",
            "pi-trace-extension": "pi-trace-extension",
            "ws": "agent-resources",
        }
        self.assertEqual(
            {
                name: record["update"]["buildPackage"]
                for name, record in catalog.items()
                if "buildPackage" in record["update"]
            },
            expected_builds,
        )
        pi_droid_sdk_update = catalog["pi-droid-sdk"]["update"]
        self.assertEqual(pi_droid_sdk_update.get("policy"), "manual")
        self.assertIn("tool bridge", pi_droid_sdk_update["reason"].lower())
        loaded = load_source_catalog(REPO)
        for name, package in expected_builds.items():
            with self.subTest(name=name):
                self.assertEqual(loaded[name]["executor"], "update")
                self.assertEqual(loaded[name]["_record"]["update"]["buildPackage"], package)
                expected_mode = "check" if name == "pi-ponytail" else None
                self.assertEqual(
                    loaded[name]["_record"]["update"].get("buildMode"),
                    expected_mode,
                )
        normalized_no_metadata = {
            "pi-dynamic-workflows",
            "pi-lens",
            "pi-markdown-preview",
            "pi-mem",
            "pi-smart-fetch",
            "pi-smart-web-search",
            "pi-subagents",
        }
        copy_only = {"pi-cymbal", "pi-rtk-optimizer"}
        fixed_projection = {"agent-browser-source"}
        self.assertTrue(
            all(
                catalog[name]["update"].get("normalizer") == "pi-gallery-v1"
                and "buildPackage" not in catalog[name]["update"]
                for name in normalized_no_metadata
            )
        )
        self.assertTrue(
            all(
                catalog[name]["update"]["kind"] == "npm-release"
                and not catalog[name]["update"].get("artifacts")
                and "buildPackage" not in catalog[name]["update"]
                for name in copy_only
            )
        )
        self.assertTrue(
            all(
                catalog[name]["update"]["kind"] == "fixed-flake-input"
                and "buildPackage" not in catalog[name]["update"]
                for name in fixed_projection
            )
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/pi.json"
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {
                            "example": {
                                "version": "1.0.0",
                                "source": {
                                    "fetcher": "fetchurl",
                                    "url": "https://registry.npmjs.org/example/-/example-1.0.0.tgz",
                                    "args": {
                                        "url": "https://registry.npmjs.org/example/-/example-1.0.0.tgz",
                                        "hash": "sha256-old",
                                    },
                                },
                                "update": {
                                    "buildPackage": "example-package",
                                    "kind": "npm-release",
                                    "package": "example",
                                },
                            }
                        },
                    }
                )
            )
            before = path.read_bytes()

            class RejectingHashes:
                def compute_native_hash(self, _source, _replacements):
                    return "sha256-new"

                def validate_package_build(self, package, build_mode):
                    candidate = json.loads(path.read_text())["sources"]["example"]
                    self.validation = (package, build_mode, candidate["version"])
                    return False

            hashes = RejectingHashes()
            transaction = SourceTransaction()
            with (
                contextlib.redirect_stdout(io.StringIO()),
                self.assertRaisesRegex(
                    CandidateRejected, "example final package build failed"
                ),
            ):
                prepare_update_target(
                    "example",
                    load_source_catalog(root)["example"],
                    SimpleNamespace(version=None, dry_run=False),
                    SimpleNamespace(),
                    SimpleNamespace(
                        get_version=lambda _package, _requested=None: (
                            "2.0.0",
                            "sha512-registry",
                        )
                    ),
                    SimpleNamespace(),
                    hashes,
                    transaction,
                )

            self.assertEqual(
                hashes.validation, ("example-package", "pkg", "2.0.0")
            )
            self.assertEqual(transaction.rollback(), 1)
            self.assertEqual(path.read_bytes(), before)

            for invalid in ("", 7):
                document = json.loads(before)
                document["sources"]["example"]["update"]["buildPackage"] = invalid
                path.write_text(json.dumps(document))
                with self.assertRaisesRegex(
                    RuntimeError, "invalid update build package"
                ):
                    load_source_catalog(root)

    def test_build_contract_schema_rejects_wrong_kind_and_invalid_check_shapes(self):
        github_source = {
            "fetcher": "fetchFromGitHub",
            "url": "https://github.com/example/project",
            "args": {
                "hash": "sha256-source",
                "owner": "example",
                "repo": "project",
                "tag": "v1.0.0",
            },
        }
        fetch_tree_source = {
            "fetcher": "fetchTree",
            "url": "https://github.com/example/project",
            "args": {
                "narHash": "sha256-source",
                "owner": "example",
                "repo": "project",
                "rev": "a" * 40,
                "type": "github",
            },
        }
        cases = {
            "wrong-build-kind": (
                {
                    "source": {
                        "fetcher": "fetchurl",
                        "url": "https://example.invalid/project.tar.gz",
                        "args": {
                            "hash": "sha256-source",
                            "url": "https://example.invalid/project.tar.gz",
                        },
                    },
                    "update": {
                        "buildPackage": "project",
                        "kind": "url-release",
                    },
                },
                "invalid update strategy fields",
            ),
            "wrong-check-kind": (
                {
                    "source": github_source,
                    "update": {
                        "buildMode": "check",
                        "buildPackage": "pi-gallery",
                        "kind": "github-tag",
                    },
                },
                "invalid update build mode",
            ),
            "missing-implicit-copy-package": (
                {
                    "version": "1.0.0",
                    "source": fetch_tree_source,
                    "update": {
                        "input": "project",
                        "kind": "flake-input+copy",
                    },
                },
                "invalid update strategy fields",
            ),
            "missing-pkg-copy-package": (
                {
                    "version": "1.0.0",
                    "source": fetch_tree_source,
                    "hashes": {"npmDepsHash": "sha256-deps"},
                    "update": {
                        "buildMode": "pkg",
                        "input": "project",
                        "kind": "flake-input+copy",
                    },
                },
                "invalid update strategy fields",
            ),
            "missing-python-copy-package": (
                {
                    "version": "1.0.0",
                    "source": fetch_tree_source,
                    "hashes": {"npmDepsHash": "sha256-deps"},
                    "update": {
                        "buildMode": "python",
                        "input": "project",
                        "kind": "flake-input+copy",
                    },
                },
                "invalid update strategy fields",
            ),
            "missing-check-copy-package": (
                {
                    "version": "1.0.0",
                    "source": fetch_tree_source,
                    "update": {
                        "buildMode": "check",
                        "input": "project",
                        "kind": "flake-input+copy",
                    },
                },
                "invalid update strategy fields",
            ),
            "check-with-dependent-hash": (
                {
                    "version": "1.0.0",
                    "source": fetch_tree_source,
                    "hashes": {"npmDepsHash": "sha256-deps"},
                    "update": {
                        "buildMode": "check",
                        "buildPackage": "pi-gallery",
                        "input": "project",
                        "kind": "flake-input+copy",
                    },
                },
                "invalid update build mode",
            ),
        }
        for label, (record, expected) in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                (root / "sources").mkdir()
                (root / "sources/test.json").write_text(
                    json.dumps(
                        {"schemaVersion": 1, "sources": {"project": record}},
                        indent=2,
                    )
                    + "\n"
                )
                with self.assertRaisesRegex(RuntimeError, expected):
                    load_source_catalog(root, validate_flake_projections=False)

    def test_mlx_candidate_targets_omlx_exact_version_contract(self):
        sources = json.loads((REPO / "sources/ai.json").read_text())["sources"]
        catalog = load_source_catalog(REPO)
        for source_name in (
            "mlx",
            "mlx-embeddings",
            "mlx-lm",
            "mlx-vlm",
            "dflash-mlx",
            "ddgs",
            "omlx",
        ):
            with self.subTest(source=source_name):
                update = sources[source_name]["update"]
                self.assertEqual(
                    (update.get("buildPackage"), update.get("buildMode")),
                    ("omlx", "pkg"),
                )
                self.assertEqual(catalog[source_name]["executor"], "update")
        self.assertEqual(sources["dflash-mlx"]["update"]["policy"], "manual")
        expression = HashComputer(REPO)._package_build_command("omlx", "pkg")[-1]
        self.assertIn('repoPath = builtins.getEnv "UPDATE_OVERLAY_REPO_DIR"', expression)
        self.assertIn('overlays = import (repo + "/config/overlays.nix")', expression)
        self.assertIn('builtins.getAttr "omlx" pkgs', expression)
        self.assertIn(
            "${python.interpreter} "
            "${../test/ai/overlays/omlx-ddgs-version-contract.py} ${ddgs.version}",
            (REPO / "packages/ai-llm.nix").read_text(),
        )
        self.assertIn(
            "${python.interpreter} "
            "${../test/ai/overlays/omlx-mlx-version-contract.py} ${mlx.version}",
            (REPO / "packages/ai-llm.nix").read_text(),
        )
        self.assertIn(
            "${python.interpreter} "
            "${../test/ai/overlays/omlx-direct-reference-contract.py} "
            "${mlx-embeddings.version} ${mlx-vlm.version}",
            (REPO / "packages/ai-llm.nix").read_text(),
        )

        calls = []

        class ConsumerHashes:
            def __init__(self, nix_dir):
                self.nix_dir = nix_dir

            def validate_package_build(self, package, build_mode):
                calls.append((self.nix_dir, package, build_mode))
                return True

        with mock.patch.dict(
            validate_catalog_target.__globals__, {"HashComputer": ConsumerHashes}
        ):
            for source_name in ("mlx-embeddings", "mlx-lm", "mlx-vlm", "ddgs"):
                self.assertTrue(
                    validate_catalog_target(REPO, source_name, catalog[source_name])
                )
        self.assertEqual(
            calls,
            [
                (REPO, "omlx", "pkg"),
                (REPO, "omlx", "pkg"),
                (REPO, "omlx", "pkg"),
                (REPO, "omlx", "pkg"),
            ],
        )

        contract = REPO / "test/ai/overlays/omlx-mlx-version-contract.py"

        class Total:
            @staticmethod
            def item():
                return 6

        def run_contract(requirement):
            def requirements(distribution):
                self.assertEqual(distribution, "omlx")
                return [requirement]

            def installed_version(distribution):
                self.assertEqual(distribution, "mlx")
                return "0.32.1"

            core = types.ModuleType("mlx.core")
            core.__version__ = "0.32.1"
            core.int32 = object()
            core.array = lambda values, dtype: values
            core.sum = lambda _values: Total()
            core.eval = lambda _value: None
            mlx = types.ModuleType("mlx")
            mlx.__path__ = []
            mlx.core = core
            old_argv = sys.argv
            try:
                sys.argv = [str(contract), "0.32.1"]
                with (
                    mock.patch.dict(
                        sys.modules, {"mlx": mlx, "mlx.core": core}
                    ),
                    mock.patch(
                        "importlib.metadata.requires", side_effect=requirements
                    ),
                    mock.patch(
                        "importlib.metadata.version", side_effect=installed_version
                    ),
                ):
                    runpy.run_path(str(contract))
            finally:
                sys.argv = old_argv

        run_contract("mlx==0.32.1")
        for invalid in (
            "mlx==0.32.0",
            'mlx==0.32.1; python_version < "0"',
            "mlx[bogus]==0.32.1",
        ):
            with self.subTest(requirement=invalid), self.assertRaises(SystemExit):
                run_contract(invalid)

    def test_github_commit_stale_catalog_version_rejects_and_rolls_back_exactly(
        self,
    ):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/ai.json"
            old_ref = "1" * 40
            new_ref = "2" * 40
            record = {
                "version": "0.4.7",
                "source": {
                    "fetcher": "fetchFromGitHub",
                    "url": "https://github.com/Blaizzy/mlx-audio",
                    "args": {
                        "owner": "Blaizzy",
                        "repo": "mlx-audio",
                        "rev": old_ref,
                        "hash": "sha256-source-old",
                    },
                },
                "update": {
                    "branch": "main",
                    "buildMode": "python",
                    "buildPackage": "mlx-audio",
                    "kind": "github-commit",
                },
            }
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"mlx-audio": record},
                    }
                )
            )
            before = path.read_bytes()

            class VersionMismatchHashes:
                installed_metadata_version = "0.5.0"
                installed_module_version = "0.5.0"

                def compute_native_hash(self, _source, replacements):
                    self.replacements = replacements
                    return "sha256-source-new"

                def validate_package_build(self, package, build_mode):
                    candidate = json.loads(path.read_text())["sources"]["mlx-audio"]
                    self.validation = (
                        package,
                        build_mode,
                        candidate["version"],
                        self.installed_metadata_version,
                        self.installed_module_version,
                        candidate["source"]["args"]["rev"],
                    )
                    return (
                        candidate["version"]
                        == self.installed_metadata_version
                        == self.installed_module_version
                    )

            hashes = VersionMismatchHashes()
            transaction = SourceTransaction()
            target = load_source_catalog(root)["mlx-audio"]
            self.assertEqual(target["executor"], "update")
            with (
                contextlib.redirect_stdout(io.StringIO()),
                self.assertRaisesRegex(
                    CandidateRejected, "mlx-audio final python build failed"
                ),
            ):
                update_catalog_target(
                    "mlx-audio",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    SimpleNamespace(
                        get_latest_commit=lambda _owner, _repo, _branch: (
                            new_ref,
                            new_ref[:8],
                        )
                    ),
                    SimpleNamespace(),
                    SimpleNamespace(),
                    hashes,
                    transaction,
                )

            self.assertEqual(hashes.replacements, {"rev": new_ref})
            self.assertEqual(
                hashes.validation,
                (
                    "mlx-audio",
                    "python",
                    "0.4.7",
                    "0.5.0",
                    "0.5.0",
                    new_ref,
                ),
            )
            candidate = json.loads(path.read_text())["sources"]["mlx-audio"]
            self.assertEqual(candidate["source"]["args"]["rev"], new_ref)
            self.assertEqual(candidate["source"]["args"]["hash"], "sha256-source-new")
            self.assertNotEqual(path.read_bytes(), before)
            self.assertEqual(transaction.rollback(), 1)
            self.assertEqual(path.read_bytes(), before)

            record["update"].pop("buildPackage")
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"mlx-audio": record},
                    }
                )
            )
            with self.assertRaisesRegex(RuntimeError, "invalid update build mode"):
                load_source_catalog(root)

    def test_catalog_github_release_preserves_native_tag_field(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/ai.json"
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {
                            "example": {
                                "version": "1.0.0",
                                "source": {
                                    "fetcher": "fetchFromGitHub",
                                    "url": "https://github.com/example/project",
                                    "args": {
                                        "owner": "example",
                                        "repo": "project",
                                        "tag": "v1.0.0",
                                        "hash": "sha256-old",
                                    },
                                },
                                "update": {
                                    "buildMode": "python",
                                    "buildPackage": "example-package",
                                    "kind": "github-release",
                                    "tagPrefix": "v",
                                },
                            }
                        },
                    }
                )
            )
            target = load_source_catalog(root)["example"]

            github = SimpleNamespace(get_latest_release=lambda _owner, _repo: "v2.0.0")
            builds = []
            hashes = SimpleNamespace(
                compute_native_hash=lambda _source, _replacements: "sha256-new",
                validate_package_build=lambda package, mode: (
                    builds.append((package, mode)) or True
                ),
            )
            transaction = SourceTransaction()
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                status = update_catalog_target(
                    "example",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    github,
                    SimpleNamespace(),
                    SimpleNamespace(),
                    hashes,
                    transaction,
                )
            transaction.commit()
            record = json.loads(path.read_text())["sources"]["example"]
            self.assertEqual(status, "updated")
            self.assertEqual(
                MODULE["ANSI_ESCAPE_RE"].sub("", output.getvalue()),
                "catalog/example 1.0.0 → 2.0.0 ✓\n",
            )
            self.assertEqual(record["source"]["args"]["tag"], "v2.0.0")
            self.assertNotIn("rev", record["source"]["args"])
            self.assertEqual(builds, [("example-package", "python")])

            before_rejection = path.read_bytes()
            target = load_source_catalog(root)["example"]
            transaction = SourceTransaction()
            rejecting_hashes = SimpleNamespace(
                compute_native_hash=lambda _source, _replacements: "sha256-rejected",
                validate_package_build=lambda _package, _mode: False,
            )
            with (
                contextlib.redirect_stdout(io.StringIO()),
                self.assertRaisesRegex(
                    CandidateRejected, "example final python build failed"
                ),
            ):
                update_catalog_target(
                    "example",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    SimpleNamespace(
                        get_latest_release=lambda _owner, _repo: "v3.0.0"
                    ),
                    SimpleNamespace(),
                    SimpleNamespace(),
                    rejecting_hashes,
                    transaction,
                )
            self.assertEqual(transaction.rollback(), 1)
            self.assertEqual(path.read_bytes(), before_rejection)

    def test_catalog_stable_github_release_updates_final_and_rejects_explicit_rc(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/ai.json"
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {
                            "omlx": {
                                "version": "0.6.2",
                                "source": {
                                    "fetcher": "fetchFromGitHub",
                                    "url": "https://github.com/jundot/omlx",
                                    "args": {
                                        "owner": "jundot",
                                        "repo": "omlx",
                                        "tag": "v0.6.2",
                                        "hash": "sha256-old",
                                    },
                                },
                                "update": {
                                    "buildPackage": "omlx",
                                    "kind": "github-release",
                                    "stableOnly": True,
                                    "tagPrefix": "v",
                                },
                            }
                        },
                    }
                )
            )
            target = load_source_catalog(root)["omlx"]
            github = SimpleNamespace(
                get_latest_stable_release=lambda _owner, _repo, _prefix: "v0.6.3",
                get_latest_release=lambda *_args: self.fail(
                    "stable target used default release lookup"
                ),
            )
            hashes = SimpleNamespace(
                compute_native_hash=lambda _source, _replacements: "sha256-new",
                validate_package_build=lambda _package, _mode: True,
            )
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_catalog_target(
                    "omlx",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    github,
                    SimpleNamespace(),
                    SimpleNamespace(),
                    hashes,
                    transaction,
                )
            transaction.commit()
            record = json.loads(path.read_text())["sources"]["omlx"]
            self.assertEqual(status, "updated")
            self.assertEqual(record["version"], "0.6.3")
            self.assertEqual(record["source"]["args"]["tag"], "v0.6.3")

            before_rc = path.read_bytes()
            target = load_source_catalog(root)["omlx"]
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                status = update_catalog_target(
                    "omlx",
                    target,
                    SimpleNamespace(version="0.6.4rc1", dry_run=False),
                    github,
                    SimpleNamespace(),
                    SimpleNamespace(),
                    hashes,
                    SourceTransaction(),
                )
            self.assertEqual(status, "failed")
            self.assertIn("stable release required", output.getvalue())
            self.assertEqual(path.read_bytes(), before_rc)

    def test_catalog_github_tag_preserves_native_tag_field(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/ai.json"
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {
                            "example": {
                                "version": "1.0.0",
                                "source": {
                                    "fetcher": "fetchFromGitHub",
                                    "url": "https://github.com/example/project",
                                    "args": {
                                        "owner": "example",
                                        "repo": "project",
                                        "tag": "v1.0.0",
                                        "hash": "sha256-old",
                                    },
                                },
                                "update": {
                                    "buildPackage": "example-package",
                                    "kind": "github-tag",
                                    "tagPrefix": "v",
                                },
                            }
                        },
                    }
                )
            )
            target = load_source_catalog(root)["example"]
            github = SimpleNamespace(
                get_latest_tag=lambda _owner, _repo, prefix: f"{prefix}2.0.0"
            )
            builds = []

            def validate_candidate(package, mode):
                candidate = json.loads(path.read_text())["sources"]["example"]
                builds.append(
                    (
                        package,
                        mode,
                        candidate["version"],
                        candidate["source"]["args"]["tag"],
                        candidate["source"]["args"]["hash"],
                    )
                )
                return True

            hashes = SimpleNamespace(
                compute_native_hash=lambda _source, _replacements: "sha256-new",
                validate_package_build=validate_candidate,
            )
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_catalog_target(
                    "example",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    github,
                    SimpleNamespace(),
                    SimpleNamespace(),
                    hashes,
                    transaction,
                )
            transaction.commit()
            record = json.loads(path.read_text())["sources"]["example"]
            self.assertEqual(status, "updated")
            self.assertEqual(record["source"]["args"]["tag"], "v2.0.0")
            self.assertNotIn("rev", record["source"]["args"])
            self.assertEqual(
                builds,
                [
                    (
                        "example-package",
                        "pkg",
                        "2.0.0",
                        "v2.0.0",
                        "sha256-new",
                    )
                ],
            )

            before_rejection = path.read_bytes()
            target = load_source_catalog(root)["example"]
            transaction = SourceTransaction()
            rejected_builds = []

            def reject_candidate(package, mode):
                candidate = json.loads(path.read_text())["sources"]["example"]
                rejected_builds.append(
                    (
                        package,
                        mode,
                        candidate["version"],
                        candidate["source"]["args"]["tag"],
                        candidate["source"]["args"]["hash"],
                    )
                )
                return False

            rejecting_hashes = SimpleNamespace(
                compute_native_hash=lambda _source, _replacements: "sha256-rejected",
                validate_package_build=reject_candidate,
            )
            with (
                contextlib.redirect_stdout(io.StringIO()),
                self.assertRaisesRegex(
                    CandidateRejected, "example final package build failed"
                ),
            ):
                update_catalog_target(
                    "example",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    SimpleNamespace(
                        get_latest_tag=lambda _owner, _repo, prefix: f"{prefix}3.0.0"
                    ),
                    SimpleNamespace(),
                    SimpleNamespace(),
                    rejecting_hashes,
                    transaction,
                )
            self.assertEqual(transaction.rollback(), 1)
            self.assertEqual(path.read_bytes(), before_rejection)
            self.assertEqual(
                rejected_builds,
                [
                    (
                        "example-package",
                        "pkg",
                        "3.0.0",
                        "v3.0.0",
                        "sha256-rejected",
                    )
                ],
            )

    def test_catalog_pypi_update_preserves_fetchpypi_arguments(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/ai.json"
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {
                            "example": {
                                "version": "1.0.0",
                                "source": {
                                    "fetcher": "fetchPypi",
                                    "url": "https://pypi.org/project/example",
                                    "args": {
                                        "pname": "example",
                                        "version": "1.0.0",
                                        "hash": "sha256-old",
                                    },
                                },
                                "update": {
                                    "kind": "pypi-release",
                                    "package": "example",
                                },
                            }
                        },
                    }
                )
            )
            target = load_source_catalog(root)["example"]
            pypi = SimpleNamespace(
                get_release=lambda _package, _record, _requested=None: (
                    "2.0.0",
                    "https://files.pythonhosted.org/example-2.0.0.tar.gz",
                    "sha256-new",
                )
            )
            transaction = SourceTransaction()
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                status = update_catalog_target(
                    "example",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    SimpleNamespace(),
                    SimpleNamespace(),
                    pypi,
                    SimpleNamespace(),
                    transaction,
                )
            transaction.commit()
            record = json.loads(path.read_text())["sources"]["example"]
            self.assertEqual(status, "updated")
            self.assertEqual(
                MODULE["ANSI_ESCAPE_RE"].sub("", output.getvalue()),
                "catalog/example 1.0.0 → 2.0.0 ✓\n",
            )
            self.assertEqual(record["version"], "2.0.0")
            self.assertEqual(record["source"]["args"]["version"], "2.0.0")
            self.assertEqual(record["source"]["args"]["hash"], "sha256-new")
            self.assertNotIn("url", record["source"]["args"])
            self.assertEqual(
                record["source"]["url"], "https://pypi.org/project/example"
            )

    def test_compound_pypi_resolves_every_artifact_before_writing(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/ai.json"

            def wheel(pname, python, abi, project):
                return {
                    "fetcher": "fetchPypi",
                    "url": f"https://pypi.org/project/{project}",
                    "args": {
                        "pname": pname,
                        "version": "1.0.0",
                        "format": "wheel",
                        "dist": python,
                        "python": python,
                        "abi": abi,
                        "platform": "macosx_14_0_arm64",
                        "hash": "sha256-old",
                    },
                }

            record = {
                "version": "1.0.0",
                "source": wheel("example", "cp313", "cp313", "example"),
                "artifacts": {
                    "cp311": wheel("example", "cp311", "cp311", "example"),
                    "metal": wheel("example_metal", "py3", "none", "example-metal"),
                },
                "update": {
                    "buildMode": "python",
                    "buildPackage": "example-package",
                    "kind": "pypi-release",
                    "package": "example",
                },
            }
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"example": record},
                    }
                )
            )
            target = load_source_catalog(root)["example"]
            self.assertEqual(target["executor"], "update")

            def artifact(filename, byte):
                return {
                    "filename": filename,
                    "url": f"https://files.pythonhosted.org/{filename}",
                    "digests": {"sha256": byte * 64},
                }

            documents = {
                "example": {
                    "info": {"version": "2.0.0"},
                    "releases": {
                        "2.0.0": [
                            artifact(
                                "example-2.0.0-cp311-cp311-macosx_14_0_arm64.whl", "1"
                            ),
                            artifact(
                                "example-2.0.0-cp313-cp313-macosx_14_0_arm64.whl", "2"
                            ),
                        ]
                    },
                },
                "example-metal": {
                    "info": {"version": "2.0.0"},
                    "releases": {
                        "2.0.0": [
                            artifact(
                                "example_metal-2.0.0-py3-none-macosx_14_0_arm64.whl",
                                "3",
                            ),
                        ]
                    },
                },
            }

            missing = PypiClient()
            missing_documents = copy.deepcopy(documents)
            missing_documents["example-metal"]["releases"]["2.0.0"] = []
            missing._get_metadata = lambda package: missing_documents.get(package)
            before = path.read_text()
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_pypi_artifact_target(
                    "example",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    missing,
                    SimpleNamespace(),
                    transaction,
                )
            self.assertEqual(status, "failed")
            self.assertEqual(path.read_text(), before)
            self.assertEqual(transaction.original, {})

            class RejectingCandidateHashes:
                def validate_package_build(self, package, mode):
                    candidate = json.loads(path.read_text())["sources"]["example"]
                    self.validation = (
                        package,
                        mode,
                        candidate["version"],
                        candidate["source"]["args"]["hash"],
                        candidate["artifacts"]["metal"]["args"]["hash"],
                    )
                    return False

            rejecting_client = PypiClient()
            rejecting_client._get_metadata = lambda package: documents.get(package)
            rejecting_hashes = RejectingCandidateHashes()
            before_rejection = path.read_bytes()
            transaction = SourceTransaction()
            with (
                contextlib.redirect_stdout(io.StringIO()),
                self.assertRaisesRegex(
                    CandidateRejected, "example final python build failed"
                ),
            ):
                update_pypi_artifact_target(
                    "example",
                    load_source_catalog(root)["example"],
                    SimpleNamespace(version=None, dry_run=False),
                    rejecting_client,
                    rejecting_hashes,
                    transaction,
                )
            self.assertEqual(
                rejecting_hashes.validation,
                (
                    "example-package",
                    "python",
                    "2.0.0",
                    "sha256-IiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI=",
                    "sha256-MzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzM=",
                ),
            )
            self.assertEqual(transaction.rollback(), 1)
            self.assertEqual(path.read_bytes(), before_rejection)

            calls = []
            client = PypiClient()
            client._get_metadata = lambda package: (
                calls.append(package) or documents.get(package)
            )
            transaction = SourceTransaction()

            class CandidateHashes:
                def validate_package_build(self, package, mode):
                    candidate = json.loads(path.read_text())["sources"]["example"]
                    self.validation = (
                        package,
                        mode,
                        candidate["version"],
                        candidate["source"]["args"]["hash"],
                        candidate["artifacts"]["metal"]["args"]["hash"],
                    )
                    return True

            hashes = CandidateHashes()
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                status = update_pypi_artifact_target(
                    "example",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    client,
                    hashes,
                    transaction,
                )
            transaction.commit()
            self.assertEqual(status, "updated")
            self.assertEqual(
                MODULE["ANSI_ESCAPE_RE"].sub("", output.getvalue()),
                "catalog/example 1.0.0 → 2.0.0 ✓\n",
            )
            self.assertEqual(calls, ["example", "example-metal"])
            self.assertEqual(
                hashes.validation,
                (
                    "example-package",
                    "python",
                    "2.0.0",
                    "sha256-IiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI=",
                    "sha256-MzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzM=",
                ),
            )
            updated = json.loads(path.read_text())["sources"]["example"]
            self.assertEqual(updated["version"], "2.0.0")
            self.assertEqual(
                {
                    "source": updated["source"]["args"],
                    **{
                        f"artifact:{name}": fetch["args"]
                        for name, fetch in updated["artifacts"].items()
                    },
                },
                {
                    "source": {
                        "pname": "example",
                        "version": "2.0.0",
                        "format": "wheel",
                        "dist": "cp313",
                        "python": "cp313",
                        "abi": "cp313",
                        "platform": "macosx_14_0_arm64",
                        "hash": "sha256-IiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI=",
                    },
                    "artifact:cp311": {
                        "pname": "example",
                        "version": "2.0.0",
                        "format": "wheel",
                        "dist": "cp311",
                        "python": "cp311",
                        "abi": "cp311",
                        "platform": "macosx_14_0_arm64",
                        "hash": "sha256-ERERERERERERERERERERERERERERERERERERERERERE=",
                    },
                    "artifact:metal": {
                        "pname": "example_metal",
                        "version": "2.0.0",
                        "format": "wheel",
                        "dist": "py3",
                        "python": "py3",
                        "abi": "none",
                        "platform": "macosx_14_0_arm64",
                        "hash": "sha256-MzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzM=",
                    },
                },
            )

            replay_output = io.StringIO()
            with contextlib.redirect_stdout(replay_output):
                replay_status = update_pypi_artifact_target(
                    "example",
                    load_source_catalog(root)["example"],
                    SimpleNamespace(version=None, dry_run=False),
                    client,
                    hashes,
                    SourceTransaction(),
                )
            self.assertEqual(replay_status, "skipped")
            self.assertEqual(replay_output.getvalue(), "")

            updated["artifacts"]["cp311"]["args"]["version"] = "1.0.0"
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"example": updated},
                    }
                )
            )
            with self.assertRaisesRegex(
                RuntimeError, "compound PyPI artifact version does not match"
            ):
                load_source_catalog(root)

    def test_pypi_candidates_reject_from_mutated_sources_and_roll_back_exactly(self):
        for fetcher in ("fetchPypi", "fetchurl"):
            with (
                self.subTest(fetcher=fetcher),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                root = Path(temp_dir)
                (root / "sources").mkdir()
                path = root / "sources/ai.json"
                source = {
                    "fetcher": fetcher,
                    "url": "https://pypi.org/project/example",
                    "args": {
                        "pname": "example",
                        "version": "1.0.0",
                        "hash": "sha256-old",
                    },
                }
                if fetcher == "fetchurl":
                    old_url = "https://files.pythonhosted.org/example-1.0.0.whl"
                    source = {
                        "fetcher": fetcher,
                        "url": old_url,
                        "args": {"url": old_url, "hash": "sha256-old"},
                    }
                path.write_text(
                    json.dumps(
                        {
                            "schemaVersion": 1,
                            "sources": {
                                "example": {
                                    "version": "1.0.0",
                                    "source": source,
                                    "update": {
                                        "buildMode": "python",
                                        "buildPackage": "example-package",
                                        "kind": "pypi-release",
                                        "package": "example",
                                    },
                                }
                            },
                        },
                        indent=2,
                    )
                    + "\n"
                )
                before = path.read_bytes()

                class RejectingHashes:
                    def __init__(self, catalog_path):
                        self.catalog_path = catalog_path

                    def validate_package_build(self, package, mode):
                        candidate = json.loads(self.catalog_path.read_text())["sources"][
                            "example"
                        ]
                        self.validation = (
                            package,
                            mode,
                            candidate["version"],
                            candidate["source"]["args"]["hash"],
                            candidate["source"]["args"].get("url"),
                        )
                        return False

                hashes = RejectingHashes(path)
                transaction = SourceTransaction()
                pypi = SimpleNamespace(
                    get_release=lambda _package, _record, _requested=None: (
                        "2.0.0",
                        "https://files.pythonhosted.org/example-2.0.0.whl",
                        "sha256-new",
                    )
                )
                target = load_source_catalog(root)["example"]
                self.assertEqual(target["executor"], "update")
                with (
                    contextlib.redirect_stdout(io.StringIO()),
                    self.assertRaisesRegex(
                        CandidateRejected, "example final python build failed"
                    ),
                ):
                    prepare_update_target(
                        "example",
                        target,
                        SimpleNamespace(version=None, dry_run=False),
                        SimpleNamespace(),
                        SimpleNamespace(),
                        pypi,
                        hashes,
                        transaction,
                    )

                self.assertEqual(
                    hashes.validation,
                    (
                        "example-package",
                        "python",
                        "2.0.0",
                        "sha256-new",
                        (
                            None
                            if fetcher == "fetchPypi"
                            else "https://files.pythonhosted.org/example-2.0.0.whl"
                        ),
                    ),
                )
                self.assertEqual(transaction.rollback(), 1)
                self.assertEqual(path.read_bytes(), before)

    def test_github_release_assets_resolve_as_one_projection(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/ai.json"

            def asset(filename, hash_value):
                url = f"https://github.com/example/tool/releases/download/v1.0.0/{filename}"
                return {
                    "fetcher": "fetchurl",
                    "url": url,
                    "args": {"url": url, "hash": hash_value},
                }

            record = {
                "version": "1.0.0",
                "source": asset("tool-1.0.0-darwin-arm64", "sha256-darwin-old"),
                "artifacts": {
                    "aarch64-linux": asset("tool-1.0.0-linux-arm64", "sha256-arm-old"),
                    "x86_64-linux": asset("tool-linux-x64", "sha256-linux-old"),
                },
                "update": {
                    "assets": {
                        "aarch64-linux": "tool-{version}-linux-arm64",
                        "source": "tool-{version}-darwin-arm64",
                        "x86_64-linux": "tool-linux-x64",
                    },
                    "kind": "github-release-asset",
                    "owner": "example",
                    "repo": "tool",
                    "tagPrefix": "v",
                },
            }
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"tool": record},
                    }
                )
            )
            target = load_source_catalog(root)["tool"]
            self.assertEqual(target["executor"], "update")
            github = SimpleNamespace(get_latest_release=lambda _owner, _repo: "v2.0.0")

            calls = []

            def incomplete_hash(_source, replacements):
                calls.append(replacements["url"])
                return (
                    None
                    if replacements["url"].endswith("tool-linux-x64")
                    else "sha256-darwin"
                )

            before = path.read_text()
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_github_release_asset_target(
                    "tool",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    github,
                    SimpleNamespace(compute_native_hash=incomplete_hash),
                    transaction,
                )
            self.assertEqual(status, "failed")
            self.assertEqual(path.read_text(), before)
            self.assertEqual(transaction.original, {})
            self.assertEqual(
                calls,
                [
                    "https://github.com/example/tool/releases/download/v2.0.0/tool-2.0.0-darwin-arm64",
                    "https://github.com/example/tool/releases/download/v2.0.0/tool-2.0.0-linux-arm64",
                    "https://github.com/example/tool/releases/download/v2.0.0/tool-linux-x64",
                ],
            )

            build_calls = []
            hashes = SimpleNamespace(
                compute_native_hash=lambda _source, replacements: (
                    "sha256-linux"
                    if replacements["url"].endswith("tool-linux-x64")
                    else (
                        "sha256-arm"
                        if replacements["url"].endswith("linux-arm64")
                        else "sha256-darwin"
                    )
                ),
                validate_package_build=lambda package: (
                    build_calls.append(package) or True
                ),
            )
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_github_release_asset_target(
                    "tool",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    github,
                    hashes,
                    transaction,
                )
            transaction.commit()
            self.assertEqual(status, "updated")
            self.assertEqual(build_calls, ["tool"])
            updated = json.loads(path.read_text())["sources"]["tool"]
            self.assertEqual(updated["version"], "2.0.0")
            self.assertEqual(
                updated["source"]["args"],
                {
                    "url": "https://github.com/example/tool/releases/download/v2.0.0/tool-2.0.0-darwin-arm64",
                    "hash": "sha256-darwin",
                },
            )
            self.assertEqual(
                updated["artifacts"]["aarch64-linux"]["args"],
                {
                    "url": "https://github.com/example/tool/releases/download/v2.0.0/tool-2.0.0-linux-arm64",
                    "hash": "sha256-arm",
                },
            )
            self.assertEqual(
                updated["artifacts"]["x86_64-linux"]["args"],
                {
                    "url": "https://github.com/example/tool/releases/download/v2.0.0/tool-linux-x64",
                    "hash": "sha256-linux",
                },
            )

            replay_builds = []
            replay_before = path.read_text()
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_github_release_asset_target(
                    "tool",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    github,
                    SimpleNamespace(
                        compute_native_hash=hashes.compute_native_hash,
                        validate_package_build=lambda package: (
                            replay_builds.append(package) or True
                        ),
                    ),
                    transaction,
                )
            self.assertEqual(status, "skipped")
            self.assertEqual(replay_builds, ["tool"])
            self.assertEqual(path.read_text(), replay_before)
            self.assertEqual(transaction.original, {})

            class CurrentBuildFailure:
                def compute_native_hash(self, source, _replacements):
                    return source["args"]["hash"]

                def validate_package_build(self, _package):
                    return False

            current_failure = CurrentBuildFailure()
            globals_ = MODULE["main"].__globals__
            replacements = {
                "HashComputer": lambda _root: current_failure,
                "load_source_catalog": lambda *_args, **_kwargs: {
                    "tool": load_source_catalog(root)["tool"]
                },
                "require_detached_linked_worktree": lambda _root: None,
                "snapshot_catalog_record_isolation": lambda *_args: {},
            }
            with (
                mock.patch.dict(globals_, replacements),
                mock.patch.object(
                    sys,
                    "argv",
                    [
                        str(SCRIPT),
                        "--prepare-target",
                        "tool",
                        "--version",
                        "2.0.0",
                    ],
                ),
                mock.patch.dict(os.environ, {"UPDATE_AGENTS_CANDIDATE": "1"}),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                current_failure_status = MODULE["main"]()
            self.assertEqual(current_failure_status, 1)
            self.assertEqual(path.read_text(), replay_before)

            source_only = copy.deepcopy(record)
            source_only.pop("artifacts")
            source_only["update"]["assets"] = {"source": "tool-{version}-darwin-arm64"}
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"tool": source_only},
                    }
                )
            )
            source_only_target = load_source_catalog(root)["tool"]
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_github_release_asset_target(
                    "tool",
                    source_only_target,
                    SimpleNamespace(version=None, dry_run=False),
                    SimpleNamespace(get_latest_release=lambda _owner, _repo: "v3.0.0"),
                    SimpleNamespace(
                        compute_native_hash=lambda _source, _replacements: (
                            "sha256-source-only"
                        ),
                        validate_package_build=lambda _package: True,
                    ),
                    transaction,
                )
            transaction.commit()
            self.assertEqual(status, "updated")
            source_only_updated = json.loads(path.read_text())["sources"]["tool"]
            self.assertEqual(source_only_updated["version"], "3.0.0")
            self.assertNotIn("artifacts", source_only_updated)
            self.assertEqual(
                source_only_updated["source"]["args"]["url"],
                "https://github.com/example/tool/releases/download/v3.0.0/tool-3.0.0-darwin-arm64",
            )

            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"tool": record},
                    }
                )
            )
            failing_target = load_source_catalog(root)["tool"]
            failing_before = path.read_text()
            failing_builds = []
            transaction = SourceTransaction()
            with (
                contextlib.redirect_stdout(io.StringIO()),
                self.assertRaises(CandidateRejected),
            ):
                update_github_release_asset_target(
                    "tool",
                    failing_target,
                    SimpleNamespace(version=None, dry_run=False),
                    SimpleNamespace(get_latest_release=lambda _owner, _repo: "v4.0.0"),
                    SimpleNamespace(
                        compute_native_hash=hashes.compute_native_hash,
                        validate_package_build=lambda package: (
                            failing_builds.append(package) or False
                        ),
                    ),
                    transaction,
                )
            self.assertEqual(failing_builds, ["tool"])
            self.assertNotEqual(path.read_text(), failing_before)
            self.assertEqual(transaction.rollback(), 1)
            self.assertEqual(path.read_text(), failing_before)

            invalid_asset_templates = {
                "empty": ("", "1.0.0"),
                "slash": ("nested/tool", "1.0.0"),
                "backslash": (r"nested\tool", "1.0.0"),
                "unknown-braces": ("tool-{release}", "1.0.0"),
                "repeated-token": ("tool-{version}-{version}", "1.0.0"),
                "unsafe-version": ("tool-{version}", "../1.0.0"),
            }
            for case, (template, version) in invalid_asset_templates.items():
                with self.subTest(case=case):
                    invalid = copy.deepcopy(record)
                    invalid["version"] = version
                    invalid["update"]["assets"]["source"] = template
                    path.write_text(
                        json.dumps(
                            {
                                "schemaVersion": 1,
                                "sources": {"tool": invalid},
                            }
                        )
                    )
                    with self.assertRaisesRegex(
                        RuntimeError, "invalid GitHub release asset projection"
                    ):
                        load_source_catalog(root)

            missing_prefix = copy.deepcopy(record)
            del missing_prefix["update"]["tagPrefix"]
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"tool": missing_prefix},
                    }
                )
            )
            with self.assertRaisesRegex(RuntimeError, "update strategy fields"):
                load_source_catalog(root)

            wrong_prefix = copy.deepcopy(record)
            wrong_prefix["update"]["tagPrefix"] = ""
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"tool": wrong_prefix},
                    }
                )
            )
            with self.assertRaisesRegex(RuntimeError, "asset URL does not match"):
                load_source_catalog(root)

            dependent_hash = copy.deepcopy(record)
            dependent_hash["hashes"] = {"cargoHash": "sha256-stale"}
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"tool": dependent_hash},
                    }
                )
            )
            with self.assertRaisesRegex(
                RuntimeError, "invalid GitHub release asset projection"
            ):
                load_source_catalog(root)

            updated["update"]["assets"]["source"] = "wrong-name"
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"tool": updated},
                    }
                )
            )
            with self.assertRaisesRegex(RuntimeError, "asset URL does not match"):
                load_source_catalog(root)

    def test_python_dependent_hash_uses_declared_build_mode(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/ai.json"
            record = {
                "version": "1.0.0",
                "source": {
                    "fetcher": "fetchFromGitHub",
                    "url": "https://github.com/example/project",
                    "args": {
                        "owner": "example",
                        "repo": "project",
                        "tag": "v1.0.0",
                        "hash": "sha256-source-old",
                    },
                },
                "hashes": {"cargoDepsHash": "sha256-cargo-old"},
                "update": {
                    "buildMode": "python",
                    "kind": "github-release",
                    "tagPrefix": "v",
                },
            }
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"python-project": record},
                    }
                )
            )
            target = load_source_catalog(root)["python-project"]
            self.assertEqual(target["executor"], "update")

            class FakeHashes:
                def __init__(self, valid=True):
                    self.calls = []
                    self.valid = valid

                def compute_native_hash(self, _source, replacements):
                    self.calls.append(("source", replacements))
                    return "sha256-source-new"

                def _compute_fod_hash(self, package, hash_type, build_mode):
                    self.calls.append(("dependent", package, hash_type, build_mode))
                    return "sha256-cargo-new"

                def validate_package_build(self, package, build_mode):
                    self.calls.append(("validate", package, build_mode))
                    return self.valid

            github = SimpleNamespace(get_latest_release=lambda _owner, _repo: "v2.0.0")
            hashes = FakeHashes()
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_catalog_target(
                    "python-project",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    github,
                    SimpleNamespace(),
                    SimpleNamespace(),
                    hashes,
                    transaction,
                )
            transaction.commit()
            self.assertEqual(status, "updated")
            self.assertIn(
                ("dependent", "python-project", "cargoDepsHash", "python"),
                hashes.calls,
            )
            self.assertIn(("validate", "python-project", "python"), hashes.calls)
            updated = json.loads(path.read_text())["sources"]["python-project"]
            self.assertEqual(updated["hashes"]["cargoDepsHash"], "sha256-cargo-new")

            before_failure = path.read_text()
            failing_target = load_source_catalog(root)["python-project"]
            failing = FakeHashes(valid=False)
            transaction = SourceTransaction()
            with (
                contextlib.redirect_stdout(io.StringIO()),
                self.assertRaises(CandidateRejected),
            ):
                update_catalog_target(
                    "python-project",
                    failing_target,
                    SimpleNamespace(version="3.0.0", dry_run=False),
                    github,
                    SimpleNamespace(),
                    SimpleNamespace(),
                    failing,
                    transaction,
                )
            self.assertEqual(transaction.rollback(), 1)
            self.assertEqual(path.read_text(), before_failure)

            wrong_fetcher = copy.deepcopy(record)
            wrong_fetcher["source"] = {
                "fetcher": "fetchurl",
                "url": "https://example.invalid/project-v1.0.0.tar.gz",
                "args": {
                    "url": "https://example.invalid/project-v1.0.0.tar.gz",
                    "hash": "sha256-source-old",
                },
            }
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"python-project": wrong_fetcher},
                    }
                )
            )
            with self.assertRaisesRegex(
                RuntimeError,
                "requires fetchFromGitHub",
            ):
                load_source_catalog(root)

            wrong_prefix_type = copy.deepcopy(record)
            wrong_prefix_type["update"]["tagPrefix"] = 7
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"python-project": wrong_prefix_type},
                    }
                )
            )
            with self.assertRaisesRegex(RuntimeError, "tag prefix"):
                load_source_catalog(root)

            fetch_artifact = copy.deepcopy(record)
            fetch_artifact["artifacts"] = {"linux": copy.deepcopy(record["source"])}
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"python-project": fetch_artifact},
                    }
                )
            )
            with self.assertRaisesRegex(
                RuntimeError,
                "cannot also declare artifacts",
            ):
                load_source_catalog(root)

            local_artifact = copy.deepcopy(record)
            local_artifact["update"]["artifacts"] = ["projection.lock"]
            (root / "projection.lock").write_text("old\n")
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"python-project": local_artifact},
                    }
                )
            )
            with self.assertRaisesRegex(
                RuntimeError,
                "cannot also declare artifacts",
            ):
                load_source_catalog(root)

    def test_github_commit_build_mode_uses_generic_projection_dispatch(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/tools.json"
            old_ref = "1" * 40
            new_ref = "2" * 40
            record = {
                "version": old_ref[:8],
                "source": {
                    "fetcher": "fetchFromGitHub",
                    "url": "https://github.com/example/project",
                    "args": {
                        "owner": "example",
                        "repo": "project",
                        "rev": old_ref,
                        "hash": "sha256-source-old",
                    },
                },
                "update": {
                    "branch": "main",
                    "kind": "github-commit",
                },
            }
            path.write_text(
                json.dumps(
                    {"schemaVersion": 1, "sources": {"project": record}},
                    indent=2,
                )
                + "\n"
            )
            before = path.read_bytes()
            self.assertEqual(
                load_source_catalog(root)["project"]["executor"],
                "update-overlay",
            )

            class FakeGitHub:
                def __init__(self, candidate):
                    self.candidate = candidate
                    self.calls = []

                def get_latest_commit(self, owner, repo, branch):
                    self.calls.append((owner, repo, branch))
                    return self.candidate

            class FakeSimpleHashes:
                def __init__(self, result):
                    self.result = result
                    self.calls = []

                def compute_native_hash(self, source, replacements):
                    self.calls.append(
                        (source["args"]["rev"], copy.deepcopy(replacements))
                    )
                    return self.result

            def run_simple(github, hashes):
                transaction = SourceTransaction()
                with contextlib.redirect_stdout(io.StringIO()):
                    status = update_github_projection_target(
                        "project",
                        load_source_catalog(root)["project"],
                        SimpleNamespace(version=None, dry_run=False),
                        github,
                        SimpleNamespace(),
                        SimpleNamespace(),
                        hashes,
                        transaction,
                    )
                return status, transaction

            lookup_failure = FakeGitHub(None)
            unused_hashes = FakeSimpleHashes("must-not-be-used")
            status, transaction = run_simple(lookup_failure, unused_hashes)
            self.assertEqual(status, "failed")
            self.assertEqual(
                lookup_failure.calls,
                [("example", "project", "main")],
            )
            self.assertEqual(unused_hashes.calls, [])
            self.assertEqual(path.read_bytes(), before)
            self.assertEqual(transaction.original, {})
            self.assertEqual(transaction.rollback(), 0)

            hash_failure = FakeGitHub((new_ref, new_ref[:8]))
            missing_hash = FakeSimpleHashes(None)
            status, transaction = run_simple(hash_failure, missing_hash)
            self.assertEqual(status, "failed")
            self.assertEqual(
                hash_failure.calls,
                [("example", "project", "main")],
            )
            self.assertEqual(missing_hash.calls, [(old_ref, {"rev": new_ref})])
            self.assertEqual(path.read_bytes(), before)
            self.assertEqual(transaction.original, {})
            self.assertEqual(transaction.rollback(), 0)

            rollback_github = FakeGitHub((new_ref, new_ref[:8]))
            rollback_hashes = FakeSimpleHashes("sha256-source-new")
            status, transaction = run_simple(rollback_github, rollback_hashes)
            self.assertEqual(status, "updated")
            self.assertEqual(
                rollback_github.calls,
                [("example", "project", "main")],
            )
            self.assertEqual(
                rollback_hashes.calls,
                [(old_ref, {"rev": new_ref})],
            )
            rolled_back_update = json.loads(path.read_text())["sources"]["project"]
            self.assertEqual(rolled_back_update["version"], new_ref[:8])
            self.assertEqual(rolled_back_update["source"]["args"]["rev"], new_ref)
            self.assertEqual(
                rolled_back_update["source"]["args"]["hash"],
                "sha256-source-new",
            )
            self.assertNotEqual(path.read_bytes(), before)
            self.assertEqual(transaction.rollback(), 1)
            self.assertEqual(path.read_bytes(), before)

            commit_github = FakeGitHub((new_ref, new_ref[:8]))
            commit_hashes = FakeSimpleHashes("sha256-source-new")
            status, transaction = run_simple(commit_github, commit_hashes)
            self.assertEqual(status, "updated")
            self.assertEqual(
                commit_github.calls,
                [("example", "project", "main")],
            )
            self.assertEqual(
                commit_hashes.calls,
                [(old_ref, {"rev": new_ref})],
            )
            transaction.commit()
            transaction.rollback_unless_committed()
            committed_update = json.loads(path.read_text())["sources"]["project"]
            self.assertEqual(committed_update["version"], new_ref[:8])
            self.assertEqual(committed_update["source"]["args"]["rev"], new_ref)
            self.assertEqual(
                committed_update["source"]["args"]["hash"],
                "sha256-source-new",
            )
            self.assertNotEqual(path.read_bytes(), before)

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/tools.json"
            old_ref = "1" * 40
            new_ref = "2" * 40
            record = {
                "version": "0.4.7",
                "source": {
                    "fetcher": "fetchFromGitHub",
                    "url": "https://github.com/example/project",
                    "args": {
                        "owner": "example",
                        "repo": "project",
                        "rev": old_ref,
                        "hash": "sha256-source-old",
                    },
                },
                "hashes": {"cargoDepsHash": "sha256-cargo-old"},
                "update": {
                    "branch": "main",
                    "buildMode": "python",
                    "kind": "github-commit",
                },
            }
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": {"project": record},
                    }
                )
            )
            target = load_source_catalog(root)["project"]
            self.assertEqual(target["executor"], "update")

            class FakeHashes:
                def __init__(self):
                    self.calls = []

                def compute_native_hash(self, _source, replacements):
                    self.calls.append(("source", replacements))
                    return "sha256-source-new"

                def _compute_fod_hash(self, package, hash_type, build_mode):
                    self.calls.append(("dependent", package, hash_type, build_mode))
                    return "sha256-cargo-new"

                def validate_package_build(self, package, build_mode):
                    self.calls.append(("validate", package, build_mode))
                    return True

            hashes = FakeHashes()
            transaction = SourceTransaction()
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                status = update_github_projection_target(
                    "project",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    SimpleNamespace(
                        get_latest_commit=lambda _owner, _repo, _branch: (
                            new_ref,
                            new_ref[:8],
                        )
                    ),
                    SimpleNamespace(),
                    SimpleNamespace(),
                    hashes,
                    transaction,
                )
            transaction.commit()
            self.assertEqual(status, "updated")
            self.assertEqual(
                ANSI_ESCAPE_RE.sub("", output.getvalue()),
                "catalog/project 11111111 → 22222222 ✓ +cargoDepsHash\n",
            )
            self.assertIn(("source", {"rev": new_ref}), hashes.calls)
            self.assertIn(
                ("dependent", "project", "cargoDepsHash", "python"),
                hashes.calls,
            )
            updated = json.loads(path.read_text())["sources"]["project"]
            self.assertEqual(updated["source"]["args"]["rev"], new_ref)
            self.assertEqual(updated["hashes"]["cargoDepsHash"], "sha256-cargo-new")

            (root / "Cargo.lock").write_text("version = 4\n")
            for build_fields in (
                {"buildMode": "python"},
                {"buildPackage": "project"},
            ):
                with self.subTest(build_fields=build_fields):
                    combined = copy.deepcopy(record)
                    combined["update"].pop("buildMode", None)
                    combined["update"].update(build_fields)
                    combined["update"]["artifacts"] = ["Cargo.lock"]
                    combined["update"]["artifactSources"] = {
                        "Cargo.lock": "Cargo.lock"
                    }
                    path.write_text(
                        json.dumps(
                            {
                                "schemaVersion": 1,
                                "sources": {"project": combined},
                            }
                        )
                    )
                    with self.assertRaisesRegex(
                        RuntimeError,
                        "cannot also declare artifacts",
                    ):
                        load_source_catalog(root)

    def test_github_commit_fetches_lock_from_exact_selected_revision(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            (root / "packages/project").mkdir(parents=True)
            lock_path = root / "packages/project/Cargo.lock"
            old_lock = 'version = 4\n\n[[package]]\nname = "old"\nversion = "1.0.0"\n'
            new_lock = 'version = 4\n\n[[package]]\nname = "new"\nversion = "2.0.0"\n'
            lock_path.write_text(old_lock)
            path = root / "sources/project.json"
            old_ref = "12345678" + "1" * 32
            new_ref = "12345678" + "2" * 32
            record = {
                "version": "1.0.0",
                "source": {
                    "fetcher": "fetchFromGitHub",
                    "url": "https://github.com/example/project",
                    "args": {
                        "owner": "example",
                        "repo": "project",
                        "rev": old_ref,
                        "hash": "sha256-source-old",
                    },
                },
                "update": {
                    "artifacts": ["packages/project/Cargo.lock"],
                    "artifactSources": {"packages/project/Cargo.lock": "Cargo.lock"},
                    "branch": "main",
                    "kind": "github-commit",
                },
            }
            path.write_text(
                json.dumps(
                    {"schemaVersion": 1, "sources": {"project": record}},
                    indent=2,
                )
                + "\n"
            )
            before_source = path.read_bytes()
            before_lock = lock_path.read_bytes()
            self.assertEqual(
                load_source_catalog(root)["project"]["executor"],
                "update",
            )

            expected_commit_request = ("example", "project", "main")
            expected_file_request = ("example", "project", new_ref, "Cargo.lock")
            expected_validation = (
                "https://github.com/example/project",
                new_ref,
                "Cargo.lock",
                new_lock,
            )

            class FakeGitHub:
                def __init__(self, content):
                    self.content = content
                    self.commit_requests = []
                    self.file_requests = []

                def get_latest_commit(self, owner, repo, branch):
                    self.commit_requests.append((owner, repo, branch))
                    return new_ref, new_ref[:8]

                def get_file(self, owner, repo, rev, remote):
                    self.file_requests.append((owner, repo, rev, remote))
                    return self.content

            class FakeHashes:
                def __init__(self, lock_valid=True):
                    self.lock_valid = lock_valid
                    self.hash_requests = []
                    self.validations = []

                def compute_native_hash(self, source, replacements):
                    self.hash_requests.append(
                        (source["args"]["rev"], copy.deepcopy(replacements))
                    )
                    return (
                        "sha256-source-new"
                        if replacements == {"rev": new_ref}
                        else None
                    )

                def validate_cargo_lock(self, source_url, revision, remote, content):
                    self.validations.append((source_url, revision, remote, content))
                    return self.lock_valid

            def run_update(github, hashes):
                transaction = SourceTransaction()
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    status = update_github_commit_artifact_target(
                        "project",
                        load_source_catalog(root)["project"],
                        SimpleNamespace(version=None, dry_run=False),
                        github,
                        hashes,
                        transaction,
                    )
                return status, transaction, ANSI_ESCAPE_RE.sub(
                    "", output.getvalue()
                )

            def assert_failure_is_atomic(transaction):
                self.assertEqual(transaction.original, {})
                self.assertEqual(path.read_bytes(), before_source)
                self.assertEqual(lock_path.read_bytes(), before_lock)
                self.assertEqual(transaction.rollback(), 0)

            invalid_content_github = FakeGitHub("not a Cargo lock")
            invalid_content_hashes = FakeHashes()
            status, transaction, _output = run_update(
                invalid_content_github,
                invalid_content_hashes,
            )
            self.assertEqual(status, "failed")
            self.assertEqual(
                invalid_content_github.commit_requests,
                [expected_commit_request],
            )
            self.assertEqual(
                invalid_content_github.file_requests,
                [expected_file_request],
            )
            self.assertEqual(
                invalid_content_hashes.hash_requests,
                [(old_ref, {"rev": new_ref})],
            )
            self.assertEqual(invalid_content_hashes.validations, [])
            assert_failure_is_atomic(transaction)

            invalid_source_github = FakeGitHub(new_lock)
            invalid_source_lock = FakeHashes(lock_valid=False)
            status, transaction, _output = run_update(
                invalid_source_github,
                invalid_source_lock,
            )
            self.assertEqual(status, "failed")
            self.assertEqual(
                invalid_source_github.commit_requests,
                [expected_commit_request],
            )
            self.assertEqual(
                invalid_source_github.file_requests,
                [expected_file_request],
            )
            self.assertEqual(
                invalid_source_lock.hash_requests,
                [(old_ref, {"rev": new_ref})],
            )
            self.assertEqual(
                invalid_source_lock.validations,
                [expected_validation],
            )
            assert_failure_is_atomic(transaction)

            rollback_github = FakeGitHub(new_lock)
            rollback_hashes = FakeHashes()
            status, transaction, output = run_update(
                rollback_github, rollback_hashes
            )
            self.assertEqual(status, "updated")
            self.assertEqual(
                output,
                "catalog/project 123456781 → 123456782 ✓\n",
            )
            self.assertEqual(rollback_github.commit_requests, [expected_commit_request])
            self.assertEqual(rollback_github.file_requests, [expected_file_request])
            self.assertEqual(
                rollback_hashes.hash_requests,
                [(old_ref, {"rev": new_ref})],
            )
            self.assertEqual(rollback_hashes.validations, [expected_validation])
            updated = json.loads(path.read_text())["sources"]["project"]
            self.assertEqual(updated["source"]["args"]["rev"], new_ref)
            self.assertEqual(updated["source"]["args"]["hash"], "sha256-source-new")
            self.assertEqual(lock_path.read_text(), new_lock)
            self.assertEqual(set(transaction.original), {path, lock_path})
            self.assertEqual(transaction.rollback(), 2)
            self.assertEqual(path.read_bytes(), before_source)
            self.assertEqual(lock_path.read_bytes(), before_lock)

            commit_github = FakeGitHub(new_lock)
            commit_hashes = FakeHashes()
            status, transaction, output = run_update(commit_github, commit_hashes)
            self.assertEqual(status, "updated")
            self.assertEqual(
                output,
                "catalog/project 123456781 → 123456782 ✓\n",
            )
            transaction.commit()
            transaction.rollback_unless_committed()
            self.assertEqual(commit_github.commit_requests, [expected_commit_request])
            self.assertEqual(commit_github.file_requests, [expected_file_request])
            self.assertEqual(
                commit_hashes.hash_requests,
                [(old_ref, {"rev": new_ref})],
            )
            self.assertEqual(commit_hashes.validations, [expected_validation])
            committed = json.loads(path.read_text())["sources"]["project"]
            self.assertEqual(committed["source"]["args"]["rev"], new_ref)
            self.assertEqual(
                committed["source"]["args"]["hash"],
                "sha256-source-new",
            )
            self.assertEqual(lock_path.read_text(), new_lock)
            self.assertNotEqual(path.read_bytes(), before_source)
            self.assertNotEqual(lock_path.read_bytes(), before_lock)

    def test_catalog_and_cli_inventory_are_consistent(self):
        root = SCRIPT.parent.parent
        try:
            catalog = load_source_catalog(root)
        except (RuntimeError, subprocess.SubprocessError, ValueError) as error:
            self.fail(f"catalog evaluation failed: {error}")

        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--inventory", "--json"],
            capture_output=True,
            text=True,
            check=False,
            cwd=root,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        try:
            inventory = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            self.fail(f"inventory returned invalid JSON: {error}")

        self.assertIsInstance(inventory.get("schemaVersion"), int)
        packages = inventory.get("packages")
        self.assertIsInstance(packages, list)
        names = [item["name"] for item in packages]
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(names, sorted(catalog))
        self.assertTrue(all(item.get("inventoried") for item in packages))
        inventory_by_name = {item["name"]: item for item in packages}
        for name, expected in PYPI_CANDIDATE_BUILDS.items():
            with self.subTest(name=name):
                self.assertEqual(
                    (
                        inventory_by_name[name].get("buildPackage"),
                        inventory_by_name[name].get("buildMode"),
                    ),
                    expected,
                )
        for item in packages:
            self.assertTrue(
                {"executor", "files", "kind", "name", "policy", "source"}
                <= set(item)
            )
            for relative in item["files"]:
                self.assertTrue((root / relative).is_file(), (item["name"], relative))

        human = subprocess.run(
            [sys.executable, str(SCRIPT), "--inventory"],
            capture_output=True,
            text=True,
            check=False,
            cwd=root,
        )
        self.assertEqual(human.returncode, 0, human.stderr)
        self.assertTrue(human.stdout.strip())


    def test_source_transaction_rolls_back_and_commit_preserves(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            path = root / "overlay.nix"
            binary_path = root / "catalog.bin"
            baseline = b"old\r\n"
            binary_baseline = b"\x00\xffcatalog\r\n"
            path.write_bytes(baseline)
            binary_path.write_bytes(binary_baseline)
            transaction = SourceTransaction()
            transaction.watch(path)
            transaction.watch(binary_path)
            path.write_text("broken\n")
            binary_path.write_bytes(b"changed\n")
            self.assertEqual(transaction.rollback(), 2)
            self.assertEqual(path.read_bytes(), baseline)
            self.assertEqual(binary_path.read_bytes(), binary_baseline)

            committed = SourceTransaction()
            committed.watch(path)
            path.write_bytes(b"new\r\n")
            committed.commit()
            committed.rollback_unless_committed()
            self.assertEqual(path.read_bytes(), b"new\r\n")

    def test_candidate_validation_cli_scopes_projection_and_maps_status(self):
        target = {
            "_record": {
                "update": {
                    "buildMode": "check",
                    "buildPackage": "candidate-check",
                    "kind": "flake-input+copy",
                }
            }
        }
        load_calls = []
        required_roots = []
        build_calls = []
        outcome = {"value": True}

        def load_catalog(root, **kwargs):
            load_calls.append((root, kwargs))
            return {"example": target}

        class CandidateHashComputer:
            def __init__(self, root):
                self.root = root

            def validate_package_build(self, package, mode):
                build_calls.append((self.root, package, mode))
                value = outcome["value"]
                if isinstance(value, Exception):
                    raise value
                return value

        globals_ = MODULE["main"].__globals__
        replacements = {
            "HashComputer": CandidateHashComputer,
            "load_source_catalog": load_catalog,
            "require_detached_linked_worktree": required_roots.append,
        }
        originals = {name: globals_[name] for name in replacements}
        old_argv = sys.argv
        old_candidate = os.environ.get("UPDATE_AGENTS_CANDIDATE")
        try:
            globals_.update(replacements)
            os.environ["UPDATE_AGENTS_CANDIDATE"] = "1"
            sys.argv = [
                str(SCRIPT),
                "--validate-candidate-target",
                "example",
            ]

            outcome["value"] = True
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(MODULE["main"](), 0)

            outcome["value"] = False
            rejected_stderr = io.StringIO()
            with (
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(rejected_stderr),
            ):
                self.assertEqual(MODULE["main"](), 3)
            self.assertIn(
                "candidate package build failed: example",
                rejected_stderr.getvalue(),
            )

            outcome["value"] = RuntimeError("evaluator unavailable")
            failed_stderr = io.StringIO()
            with (
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(failed_stderr),
            ):
                self.assertEqual(MODULE["main"](), 1)
            self.assertIn(
                "candidate validation failed: evaluator unavailable",
                failed_stderr.getvalue(),
            )
        finally:
            globals_.update(originals)
            sys.argv = old_argv
            if old_candidate is None:
                os.environ.pop("UPDATE_AGENTS_CANDIDATE", None)
            else:
                os.environ["UPDATE_AGENTS_CANDIDATE"] = old_candidate

        expected_root = SCRIPT.parent.parent.resolve()
        self.assertEqual(required_roots, [expected_root] * 3)
        self.assertEqual(
            load_calls,
            [
                (
                    expected_root,
                    {
                        "flake_projection_names": {"example"},
                        "validate_flake_projections": True,
                    },
                )
            ]
            * 3,
        )
        self.assertEqual(
            build_calls,
            [(expected_root, "candidate-check", "check")] * 3,
        )

    def test_explicit_catalog_record_isolation_allows_selected_and_rolls_back_sibling(
        self,
    ):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "shared.json"
            initial = {
                "schemaVersion": 1,
                "sources": {
                    "selected": {"version": "1.0.0"},
                    "sibling": {"version": "1.0.0"},
                },
            }
            path.write_text(json.dumps(initial, indent=2) + "\n")
            targets = {
                "selected": {"_path": path},
                "sibling": {"_path": path},
            }

            successful = SourceTransaction()
            snapshots = snapshot_catalog_record_isolation(
                ["selected"], targets, successful
            )
            selected_only = copy.deepcopy(initial)
            selected_only["sources"]["selected"]["version"] = "2.0.0"
            path.write_text(json.dumps(selected_only, indent=2) + "\n")
            validate_catalog_record_isolation(snapshots)
            successful.commit()
            self.assertEqual(
                json.loads(path.read_text())["sources"]["selected"]["version"],
                "2.0.0",
            )

            before_sibling_attempt = path.read_text()
            failing = SourceTransaction()
            snapshots = snapshot_catalog_record_isolation(
                ["selected"], targets, failing
            )
            sibling_mutation = json.loads(before_sibling_attempt)
            sibling_mutation["sources"]["selected"]["version"] = "3.0.0"
            sibling_mutation["sources"]["sibling"]["version"] = "9.0.0"
            path.write_text(json.dumps(sibling_mutation, indent=2) + "\n")
            with self.assertRaisesRegex(
                RuntimeError, "changed unselected data.*sibling"
            ):
                enforce_catalog_record_isolation(snapshots, failing)
            self.assertEqual(path.read_text(), before_sibling_attempt)

    def test_prepare_target_rejects_and_rolls_back_sibling_record(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "shared.json"
            initial = {
                "schemaVersion": 1,
                "sources": {
                    "selected": {"version": "1.0.0"},
                    "sibling": {"version": "1.0.0"},
                },
            }
            before = json.dumps(initial, indent=2) + "\n"
            path.write_text(before)
            target = {
                "kind": "npm-release",
                "executor": "update",
                "_path": path,
                "_record": {
                    "update": {
                        "kind": "npm-release",
                        "normalizer": "pi-gallery-v1",
                        "package": "selected",
                    }
                },
            }

            def mutate_sibling(*_args, **_kwargs):
                document = json.loads(path.read_text())
                document["sources"]["selected"]["version"] = "2.0.0"
                document["sources"]["sibling"]["version"] = "9.0.0"
                path.write_text(json.dumps(document, indent=2) + "\n")
                return "updated"

            globals_ = MODULE["main"].__globals__
            replacements = {
                "load_source_catalog": lambda _root, **_kwargs: {"selected": target},
                "require_detached_linked_worktree": lambda _root: None,
                "update_npm_lock_target": mutate_sibling,
            }
            originals = {name: globals_[name] for name in replacements}
            old_argv = sys.argv
            old_candidate = os.environ.get("UPDATE_AGENTS_CANDIDATE")
            try:
                globals_.update(replacements)
                os.environ["UPDATE_AGENTS_CANDIDATE"] = "1"
                sys.argv = [
                    str(SCRIPT),
                    "--prepare-target",
                    "selected",
                ]
                stderr = io.StringIO()
                with (
                    contextlib.redirect_stdout(io.StringIO()),
                    contextlib.redirect_stderr(stderr),
                ):
                    status = MODULE["main"]()
            finally:
                globals_.update(originals)
                sys.argv = old_argv
                if old_candidate is None:
                    os.environ.pop("UPDATE_AGENTS_CANDIDATE", None)
                else:
                    os.environ["UPDATE_AGENTS_CANDIDATE"] = old_candidate

            self.assertEqual(status, 1)
            self.assertIn("changed unselected data", stderr.getvalue())
            self.assertEqual(path.read_text(), before)

    def test_prepare_target_treats_signaled_hash_build_as_hard_and_rolls_back(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            name = "pi-mem"
            path = Path(temp_dir) / "shared.json"
            before = '{"version":"1.0.0"}\n'
            path.write_text(before)
            target = copy.deepcopy(load_source_catalog(REPO)[name])
            self.assertEqual(target["_record"]["update"]["normalizer"], "pi-gallery-v1")
            self.assertEqual(
                target["_record"]["update"]["package"], "@askjo/pi-mem"
            )
            target["_path"] = path
            computer = HashComputer(Path("/repo"))
            computer._run_package_build = mock.Mock(
                return_value=SimpleNamespace(
                    returncode=-15,
                    stdout=(
                        f"specified: {MODULE['DUMMY_SRI_HASH']}\n"
                        "got: sha256-buffered\n"
                    ),
                    stderr="terminated",
                )
            )

            def interrupted_target(
                _name,
                _target,
                _args,
                _npm_client,
                hash_computer,
                transaction,
            ):
                transaction.watch(path)
                path.write_text('{"version":"2.0.0"}\n')
                return (
                    "updated"
                    if hash_computer._compute_fod_hash(name, "npmDepsHash")
                    else "failed"
                )

            globals_ = MODULE["main"].__globals__
            replacements = {
                "HashComputer": lambda _root: computer,
                "load_source_catalog": lambda _root, **_kwargs: {
                    name: target
                },
                "require_detached_linked_worktree": lambda _root: None,
                "snapshot_catalog_record_isolation": lambda *_args: {},
                "update_npm_lock_target": interrupted_target,
            }
            with (
                mock.patch.dict(globals_, replacements),
                mock.patch.object(
                    sys,
                    "argv",
                    [str(SCRIPT), "--prepare-target", name],
                ),
                mock.patch.dict(os.environ, {"UPDATE_AGENTS_CANDIDATE": "1"}),
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(io.StringIO()),
            ):
                status = MODULE["main"]()

            self.assertEqual(status, 1)
            self.assertEqual(path.read_text(), before)
            computer._run_package_build.assert_called_once_with(name, "pkg")


    def test_prime_agent_lock_normalizer_adds_only_registry_metadata(self):
        self.assertIsNotNone(normalize_prime_agent_lock)
        self.assertIsNotNone(prime_agent_lock_is_normalized)
        upstream = {
            "name": "prime-agent",
            "version": "1.0.0",
            "lockfileVersion": 3,
            "requires": True,
            "packages": {
                "": {"name": "prime-agent", "workspaces": ["packages/*"]},
                "packages/agent": {"name": "agent", "version": "1.0.0"},
                "node_modules/@scope/tool": {
                    "version": "2.3.4",
                    "license": "MIT",
                },
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / "package-lock.json").write_text(
                json.dumps(upstream, indent=2) + "\n"
            )
            calls = []

            class Registry:
                def get_version_metadata(self, package, version):
                    calls.append((package, version))
                    return {
                        "version": version,
                        "integrity": "sha512-YWJjZA==",
                        "tarball": (
                            "https://registry.npmjs.org/@scope/tool/-/tool-2.3.4.tgz"
                        ),
                    }

            normalized_text = normalize_prime_agent_lock(
                source,
                json.dumps(upstream, indent=2) + "\n",
                Registry(),
            )
            normalized = json.loads(normalized_text)
            package = normalized["packages"]["node_modules/@scope/tool"]
            self.assertEqual(
                package["resolved"],
                "https://registry.npmjs.org/@scope/tool/-/tool-2.3.4.tgz",
            )
            self.assertEqual(package["integrity"], "sha512-YWJjZA==")
            self.assertEqual(calls, [("@scope/tool", "2.3.4")])
            self.assertTrue(prime_agent_lock_is_normalized(upstream, normalized))

            class NoRegistry:
                def get_version_metadata(self, _package, _version):
                    raise AssertionError("already-normalized lock queried the registry")

            self.assertEqual(
                normalize_prime_agent_lock(source, normalized_text, NoRegistry()),
                normalized_text,
            )
            stripped = copy.deepcopy(normalized)
            del stripped["packages"]["node_modules/@scope/tool"]["integrity"]
            self.assertFalse(prime_agent_lock_is_normalized(upstream, stripped))

    def test_prime_agent_lock_normalizer_rejects_non_registry_tarball(self):
        upstream = {
            "lockfileVersion": 3,
            "packages": {"node_modules/tool": {"version": "1.2.3"}},
        }
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / "package-lock.json").write_text(json.dumps(upstream))

            class Registry:
                def get_version_metadata(self, _package, version):
                    return {
                        "version": version,
                        "integrity": "sha512-YWJjZA==",
                        "tarball": "https://cdn.invalid/tool-1.2.3.tgz",
                    }

            with self.assertRaisesRegex(RuntimeError, "registry coordinate mismatch"):
                normalize_prime_agent_lock(source, json.dumps(upstream), Registry())


class IntegratedWorkflowTests(unittest.TestCase):
    def setUp(self):
        local_vars = subprocess.run(
            ["git", "rev-parse", "--local-env-vars"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.splitlines()
        self._git_local_env = {
            name: os.environ.pop(name) for name in local_vars if name in os.environ
        }

    def tearDown(self):
        os.environ.update(self._git_local_env)

    def _create_update_agents_fixture(
        self,
        temporary: str,
        *,
        nixos_driver: str | None = None,
        portable_inputs: tuple[str, ...] = (),
        root_inputs: tuple[str, ...] = (),
    ):
        root = Path(temporary) / "repo"
        fake_bin = Path(temporary) / "bin"
        (root / "bin").mkdir(parents=True)
        (root / "config/ai").mkdir(parents=True)
        (root / "overlays/ai").mkdir(parents=True)
        fake_bin.mkdir()
        system_config = Path(temporary) / "darwin-system"
        (system_config / "sw/bin").mkdir(parents=True)
        (system_config / "sw/bin/darwin-rebuild").write_text(
            """#!/usr/bin/env bash
set -euo pipefail
[[ $1 == activate ]]
if [[ -n ${UPDATE_TEST_EXTERNAL_LOG:-} ]]; then
  printf 'switch\n' >>"$UPDATE_TEST_EXTERNAL_LOG"
fi
if [[ ${UPDATE_TEST_FAILURE_PHASE:-} == candidate-switch ]]; then
  exit 71
fi
"""
        )
        (system_config / "sw/bin/darwin-rebuild").chmod(0o700)

        def lock(inputs):
            return (
                json.dumps(
                    {
                        "nodes": {
                            "root": {
                                "inputs": {name: name for name in inputs},
                            }
                        },
                        "root": "root",
                        "version": 7,
                    }
                )
                + "\n"
            )

        (root / "flake.lock").write_text(lock(root_inputs))
        (root / "config/ai/flake.lock").write_text(lock(portable_inputs))
        (root / ".gitignore").write_text("ignored.tmp\n")
        (root / "tracked.txt").write_text("before\n")
        (root / "tracked.txt").chmod(0o640)
        (root / "mode.sh").write_text("#!/bin/sh\nexit 0\n")
        (root / "mode.sh").chmod(0o644)
        (root / "binary.bin").write_bytes(b"\x00before\xff\n")
        (root / "binary.bin").chmod(0o644)
        (root / "format.nix").write_text("{ }\n")
        (root / "format.nix").chmod(0o644)
        (root / "projection.json").write_text("{}\n")
        (root / "projection.json").chmod(0o644)
        (root / "fixed.txt").write_text("fixed before\n")
        (root / "npm-lock.txt").write_text("npm lock before\n")
        (root / "npm-lock-second.txt").write_text("npm lock second before\n")
        (root / "pypi.txt").write_text("pypi before\n")
        (root / "github.txt").write_text("github before\n")
        (root / "shared.json").write_text(
            json.dumps(
                {
                    "sources": {
                        name: {"version": "1.0.0"}
                        for name in ("a-success", "b-rejected", "c-success")
                    }
                },
                indent=2,
            )
            + "\n"
        )
        (root / "config/ai/flake.nix").write_text("{ }\n")
        (root / "target-old").write_text("old target\n")
        (root / "target-new").write_text("new target\n")
        (root / "link").symlink_to("target-old")
        (root / "regular-to-link").write_text("regular before\n")
        (root / "regular-to-link").chmod(0o644)
        (root / "link-to-regular").symlink_to("target-old")
        (root / "renamed-old.txt").write_text("rename payload\n")
        (root / "renamed-old.txt").chmod(0o644)
        (root / "undeclared-rename-source.txt").write_text("undeclared rename\n")
        (root / "undeclared-rename-source.txt").chmod(0o644)
        (root / "deleted.txt").write_text("delete me\n")
        (root / "deleted.txt").chmod(0o604)

        updater = root / "bin/update-overlay"
        updater.write_text(
            """#!/usr/bin/env python3
import json
import os
import signal
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
arguments = sys.argv[1:]
if os.environ.get("UPDATE_TEST_INTERLEAVING_LOG"):
    with open(os.environ["UPDATE_TEST_INTERLEAVING_LOG"], "a") as log:
        log.write("overlay " + " ".join(arguments) + "\\n")
internal_modes = {
    "--prepare-target",
    "--record-target-change",
    "--validate-candidate-target",
    "--validate-target",
    "--sync-flake-projections",
}

def flake_state():
    def markers(path):
        return [
            line.removeprefix("state:")
            for line in path.read_text().splitlines()
            if line.startswith("state:")
        ]

    projection = json.loads((root / "projection.json").read_text())
    return {
        "portable": markers(root / "config/ai/flake.lock"),
        "root": markers(root / "flake.lock"),
        "projection": sorted(projection),
    }

def record_flake_state(phase, name):
    state = flake_state()
    if os.environ.get("UPDATE_TEST_STATE_LOG"):
        with open(os.environ["UPDATE_TEST_STATE_LOG"], "a") as log:
            log.write(json.dumps({"phase": phase, "name": name, **state}) + "\\n")
    return state

if internal_modes.intersection(arguments) and os.environ.get("UPDATE_AGENTS_CANDIDATE") != "1":
    print("internal update requires update candidate", file=sys.stderr)
    raise SystemExit(77)
declared = [
    "tracked.txt", "mode.sh", "binary.bin", "format.nix", "projection.json", "link",
    "regular-to-link", "link-to-regular", "renamed-old.txt", "renamed-new.txt",
    "deleted.txt", "created.txt", "fixed.txt", "npm-lock.txt", "npm-lock-second.txt",
    "pypi.txt", "github.txt",
    "new-directory/generated-lock.json"
]
if "--inventory" in arguments:
    if (
        os.environ.get("UPDATE_TEST_FINAL_INVENTORY_FAIL") == "1"
        and json.loads((root / "projection.json").read_text())
    ):
        print("unselected projection drift", file=sys.stderr)
        raise SystemExit(85)
    if os.environ.get("UPDATE_TEST_ISOLATED_TARGETS") == "1":
        packages = [{
            "name": name,
            "files": ["shared.json"],
            "inventoried": True,
            "managed": True,
            "executor": "update-overlay",
            "policy": "automatic",
            "version": "1.0.0",
        } for name in ("a-success", "b-rejected", "c-success")]
    else:
        packages = [{
            "name": "fixture",
            "files": declared,
            "inventoried": True,
            "managed": True,
            "executor": "update-overlay",
        }]
    if os.environ.get("UPDATE_TEST_FIXED_TARGET") == "1":
        packages.append({
            "name": "fixed",
            "files": ["fixed.txt", "projection.json", "config/ai/flake.nix"],
            "input": "fixed-input",
            "inventoried": True,
            "kind": "fixed-flake-input",
            "managed": True,
            "executor": "update",
            "policy": "manual",
        })
    if os.environ.get("UPDATE_TEST_COPY_TARGET") == "1":
        packages.append({
            "name": "copy",
            "buildMode": "check",
            "buildPackage": "pi-gallery",
            "files": ["projection.json"],
            "input": "copy-input",
            "inventoried": True,
            "kind": "flake-input+copy",
            "managed": True,
            "executor": "update",
            "policy": "automatic",
        })
    if os.environ.get("UPDATE_TEST_BUILD_TARGET") == "1":
        packages.append({
            "name": "build",
            "buildPackage": "agent-resources",
            "files": ["projection.json"],
            "input": "build-input",
            "inventoried": True,
            "kind": "flake-input+build",
            "managed": True,
            "executor": "update",
            "policy": "manual",
        })
    if os.environ.get("UPDATE_TEST_NPM_FLAKE_TARGET") == "1":
        packages.append({
            "name": "npm-flake",
            "buildPackage": "candidate-package",
            "files": ["fixed.txt", "projection.json", "config/ai/flake.nix"],
            "input": "npm-flake-input",
            "inventoried": True,
            "kind": "npm-release+flake-input",
            "managed": True,
            "executor": "update",
            "policy": "automatic",
            "revision": "1" * 40,
            "version": "1.0.0",
        })
    if os.environ.get("UPDATE_TEST_FLAKE_ISOLATED_TARGETS") == "1":
        packages.extend({
            "name": name,
            "buildPackage": f"{name}-package",
            "files": ["projection.json"],
            "input": f"{name}-input",
            "inventoried": True,
            "kind": "flake-input",
            "managed": True,
            "executor": "update",
            "policy": "manual",
        } for name in ("flake-a", "flake-b", "flake-c"))
    if os.environ.get("UPDATE_TEST_PYPI_TARGET") == "1":
        packages.append({
            "name": "pypi",
            "files": ["pypi.txt"],
            "inventoried": True,
            "kind": "pypi-release",
            "managed": True,
            "executor": "update",
            "policy": "manual",
        })
    if os.environ.get("UPDATE_TEST_NPM_LOCK_TARGET") == "1":
        packages.append({
            "name": "npm-lock",
            "files": ["npm-lock.txt"],
            "inventoried": True,
            "kind": "npm-release",
            "managed": True,
            "executor": "update",
            "version": "1.0.0",
            "policy": (
                "automatic"
                if os.environ.get("UPDATE_TEST_NPM_LOCK_AUTOMATIC") == "1"
                else "manual"
            ),
        })
    if os.environ.get("UPDATE_TEST_NPM_LOCK_SECOND_TARGET") == "1":
        packages.append({
            "name": "npm-lock-second",
            "files": ["npm-lock-second.txt"],
            "inventoried": True,
            "kind": "npm-release",
            "managed": True,
            "executor": "update",
            "policy": "manual",
        })
    if os.environ.get("UPDATE_TEST_GITHUB_TARGET") == "1":
        packages.append({
            "name": "github",
            "files": ["github.txt"],
            "inventoried": True,
            "kind": "github-release-asset",
            "managed": True,
            "executor": "update",
            "policy": "manual",
        })
    print(json.dumps({
        "schemaVersion": 1,
        "packages": packages,
    }))
elif "--record-target-change" in arguments:
    name = arguments[arguments.index("--record-target-change") + 1]
    old_version = arguments[arguments.index("--old-version") + 1]
    if os.environ.get("UPDATE_TEST_ISOLATED_TARGETS") == "1":
        new_version = json.loads((root / "shared.json").read_text())["sources"][name]["version"]
        if old_version != new_version:
            print(json.dumps({"name": name, "old": old_version, "new": new_version}))
    elif name == "npm-flake":
        old_revision = arguments[arguments.index("--old-revision") + 1]
        new_revision = json.loads((root / "projection.json").read_text())[name]
        if old_revision != new_revision:
            print(json.dumps({
                "name": name,
                "old": old_revision[:8],
                "new": new_revision[:8],
            }))
elif "--validate-candidate-target" in arguments:
    name = arguments[arguments.index("--validate-candidate-target") + 1]
    if os.environ.get("UPDATE_TEST_FAILURE_PHASE") == "candidate-validation":
        raise SystemExit(71)
    if os.environ.get("UPDATE_TEST_STATEFUL_FLAKE_TARGETS") == "1":
        state = record_flake_state("candidate", name)
        normalized = sorted(
            marker.removeprefix("invalid-") for marker in state["portable"]
        )
        if (
            state["portable"] != state["root"]
            or normalized != state["projection"]
            or name not in state["projection"]
        ):
            print("candidate validation observed incoherent lock state", file=sys.stderr)
            raise SystemExit(86)
        raise SystemExit(
            3
            if any(marker.startswith("invalid-") for marker in state["portable"])
            else 0
        )
    rejected = set(
        os.environ.get("UPDATE_TEST_CANDIDATE_REJECT_TARGETS", "").split(",")
    )
    if os.environ.get("UPDATE_TEST_FLAKE_CANDIDATE_REJECT") == "1":
        locks = (
            (root / "flake.lock").read_text()
            + (root / "config/ai/flake.lock").read_text()
        )
        projection = json.loads((root / "projection.json").read_text())
        if locks.count("candidate lock") != 2 or not projection.get(name):
            print("candidate validation ran before locks/projection", file=sys.stderr)
            raise SystemExit(86)
        rejected.add(name)
    raise SystemExit(3 if name in rejected else 0)
elif "--validate-target" in arguments:
    name = arguments[arguments.index("--validate-target") + 1]
    if os.environ.get("UPDATE_TEST_STATEFUL_FLAKE_TARGETS") == "1":
        state = record_flake_state("baseline", name)
        normalized = sorted(
            marker.removeprefix("invalid-") for marker in state["portable"]
        )
        if (
            state["portable"] != state["root"]
            or normalized != state["projection"]
            or name in state["projection"]
            or any(marker.startswith("invalid-") for marker in state["portable"])
        ):
            print("baseline validation observed leaked candidate state", file=sys.stderr)
            raise SystemExit(86)
        raise SystemExit(0)
    if os.environ.get("UPDATE_TEST_FLAKE_CANDIDATE_REJECT") == "1":
        locks = (
            (root / "flake.lock").read_text()
            + (root / "config/ai/flake.lock").read_text()
        )
        if "candidate lock" in locks:
            print("candidate lock survived restoration", file=sys.stderr)
            raise SystemExit(84)
    failures = set(
        os.environ.get("UPDATE_TEST_BASELINE_FAILURE_TARGETS", "").split(",")
    )
    raise SystemExit(1 if name in failures else 0)
elif "--prepare-target" in arguments:
    name = arguments[arguments.index("--prepare-target") + 1]
    if name == "fixed":
        (root / "fixed.txt").write_text("fixed after\\n")
    elif name == "npm-flake":
        (root / "fixed.txt").write_text("npm flake after\\n")
        print("catalog/npm-flake 11111111 → 22222222 ✓")
    elif name == "npm-lock":
        (root / "npm-lock.txt").write_text("npm lock after\\n")
        if os.environ.get("UPDATE_TEST_REJECT_NPM_LOCK") == "1":
            print("catalog/npm-lock final package build failed")
            raise SystemExit(3)
        if os.environ.get("UPDATE_TEST_MUTATE_OTHER_DECLARED") == "1":
            (root / "github.txt").write_text("cross-target mutation\\n")
    elif name == "npm-lock-second":
        (root / "npm-lock-second.txt").write_text("npm lock second after\\n")
        if os.environ.get("UPDATE_TEST_NPM_LOCK_SECOND_FAIL") == "1":
            raise SystemExit(83)
    elif name == "pypi":
        (root / "pypi.txt").write_text("pypi after\\n")
    elif name == "github":
        (root / "github.txt").write_text("github after\\n")
    elif name not in {"copy", "build", "flake-a", "flake-b", "flake-c"}:
        print(f"unexpected target preparation: {arguments}", file=sys.stderr)
        raise SystemExit(82)
elif "--sync-flake-projections" in arguments:
    name = arguments[arguments.index("--sync-flake-projections") + 1]
    if (
        os.environ.get("UPDATE_TEST_NO_CHANGES") != "1"
        and os.environ.get("UPDATE_TEST_ISOLATED_TARGETS") != "1"
    ):
        projection = json.loads((root / "projection.json").read_text())
        projection[name] = "2" * 40 if name == "npm-flake" else True
        (root / "projection.json").write_text(json.dumps(projection) + "\\n")
        if name == "npm-flake":
            print("catalog/npm-flake 11111111 → 22222222 ✓")
    if os.environ.get("UPDATE_TEST_SIGNAL_PHASE") == "candidate-projection":
        Path(os.environ["UPDATE_TEST_SIGNAL_MARKER"]).touch()
        os.kill(os.getppid(), signal.SIGTERM)
    if os.environ.get("UPDATE_TEST_FAILURE_PHASE") == "candidate-projection":
        raise SystemExit(71)
else:
    if os.environ.get("UPDATE_AGENTS_CANDIDATE") != "1":
        print("compound update requires update candidate", file=sys.stderr)
        raise SystemExit(77)
    if os.environ.get("UPDATE_TEST_ISOLATED_TARGETS") == "1":
        name = arguments[-1]
        document = json.loads((root / "shared.json").read_text())
        document["sources"][name]["version"] = "2.0.0"
        (root / "shared.json").write_text(json.dumps(document, indent=2) + "\\n")
        print(f"catalog/{name} fabricated → phase-output ✓")
        rejected = set(
            os.environ.get("UPDATE_TEST_REJECT_TARGETS", "b-rejected").split(",")
        )
        if name in rejected:
            print(f"catalog/{name} final package build failed")
            raise SystemExit(3)
        raise SystemExit(0)
    if os.environ.get("UPDATE_TEST_NO_CHANGES") == "1":
        raise SystemExit(0)
    (root / "tracked.txt").write_text("after\\n")
    (root / "binary.bin").write_bytes(b"\\x00after\\xfe\\n")
    (root / "format.nix").write_text("{ changed = true; }\\n")
    os.chmod(root / "mode.sh", 0o755)
    (root / "link").unlink()
    (root / "link").symlink_to("target-new")
    (root / "regular-to-link").unlink()
    (root / "regular-to-link").symlink_to("target-new")
    (root / "link-to-regular").unlink()
    (root / "link-to-regular").write_text("regular after\\n")
    (root / "renamed-old.txt").rename(root / "renamed-new.txt")
    (root / "deleted.txt").unlink()
    if os.environ.get("UPDATE_TEST_RENAME_UNDECLARED") == "1":
        (root / "undeclared-rename-source.txt").rename(root / "created.txt")
    else:
        (root / "created.txt").write_text("created\\n")
    (root / "new-directory").mkdir()
    (root / "new-directory/generated-lock.json").write_text("{}\\n")
    if os.environ.get("UPDATE_TEST_MUTATE_UNDECLARED") == "1":
        (root / "unexpected.txt").write_text("unexpected\\n")
    if os.environ.get("UPDATE_TEST_MUTATE_IGNORED") == "1":
        (root / "ignored.tmp").write_text("ignored\\n")
    if os.environ.get("UPDATE_TEST_SIGNAL_PHASE") == "candidate-update":
        Path(os.environ["UPDATE_TEST_SIGNAL_MARKER"]).touch()
        os.kill(os.getppid(), signal.SIGTERM)
    if os.environ.get("UPDATE_TEST_FAILURE_PHASE") == "candidate-update":
        if os.environ.get("UPDATE_TEST_NOISY_FAILURE") == "1":
            for index in range(30):
                print(f"noise {index}")
        print("catalog/fixture fabricated → phase-output ✓")
        raise SystemExit(71)
"""
        )
        updater.chmod(0o700)

        publisher = root / "bin/publish"
        publisher.write_text(
            """#!/usr/bin/env bash
set -euo pipefail
[[ $1 == --publish && $2 == --rev && -n $3 && $4 == --branch && -n $5 ]]
[[ $PWD == "$NIX_CONFIG_DIR" ]]
if [[ -n ${UPDATE_TEST_EXTERNAL_LOG:-} ]]; then
  printf 'push\n' >>"$UPDATE_TEST_EXTERNAL_LOG"
fi
if [[ -n ${UPDATE_TEST_PUSH_MARKER:-} ]]; then
  : >"$UPDATE_TEST_PUSH_MARKER"
fi
exit "${UPDATE_TEST_PUSH_STATUS:-0}"
"""
        )
        publisher.chmod(0o700)

        def executable(name, text):
            path = fake_bin / name
            path.write_text(text)
            path.chmod(0o700)

        executable(
            "nix",
            """#!/usr/bin/env bash
set -euo pipefail
if [[ -n ${UPDATE_TEST_COMMAND_LOG:-} ]]; then
  printf '%s\n' "$*" >>"$UPDATE_TEST_COMMAND_LOG"
fi
if [[ -n ${UPDATE_TEST_INTERLEAVING_LOG:-} ]]; then
  printf 'nix %s\n' "$*" >>"$UPDATE_TEST_INTERLEAVING_LOG"
fi
signal_phase() {
  if [[ ${UPDATE_TEST_SIGNAL_PHASE:-} == "$1" \
    && ! -e ${UPDATE_TEST_SIGNAL_MARKER:-/nonexistent} ]]; then
    : >"$UPDATE_TEST_SIGNAL_MARKER"
    kill -TERM "$PPID"
  fi
}
fail_phase() {
  if [[ ${UPDATE_TEST_FAILURE_PHASE:-} == "$1" ]]; then exit 71; fi
}
status_three_phase() {
  if [[ ${UPDATE_TEST_NIX_STATUS3_PHASE:-} == "$1" ]]; then exit 3; fi
}
mutate_phase() {
  if [[ ${UPDATE_TEST_SIGNAL_PHASE:-} == "$1" \
    || ${UPDATE_TEST_FAILURE_PHASE:-} == "$1" ]]; then
    printf '%s\n' "$1" >>"$2"
  fi
}
if [[ $1 == flake && $2 == update ]]; then
  if [[ -n ${UPDATE_TEST_BLOCK_FLAKE_MARKER:-} \
    && ! -e $UPDATE_TEST_BLOCK_FLAKE_MARKER ]]; then
    : >"$UPDATE_TEST_BLOCK_FLAKE_MARKER"
    while [[ ! -e ${UPDATE_TEST_BLOCK_FLAKE_RELEASE:?} ]]; do
      sleep 0.01
    done
  fi
  if [[ ${3:-} == --flake ]]; then
    if [[ ${UPDATE_TEST_STATEFUL_FLAKE_TARGETS:-} == 1 \
      && ${5:-} == flake-*-input ]]; then
      target=${5%-input}
      marker=$target
      if [[ $target == flake-b ]]; then marker=invalid-$target; fi
      printf 'state:%s\n' "$marker" >>config/ai/flake.lock
    fi
    if [[ ${UPDATE_TEST_FLAKE_CANDIDATE_REJECT:-} == 1 ]]; then
      printf 'candidate lock\n' >>config/ai/flake.lock
    fi
    mutate_phase candidate-portable-lock config/ai/flake.lock
    signal_phase candidate-portable-lock
    fail_phase candidate-portable-lock
    status_three_phase candidate-portable-lock
  else
    if [[ ${UPDATE_TEST_STATEFUL_FLAKE_TARGETS:-} == 1 ]]; then
      marker=$(awk '/^state:/{last=$0} END{print last}' config/ai/flake.lock)
      [[ -n $marker ]] || exit 87
      printf '%s\n' "$marker" >>flake.lock
    fi
    if [[ ${UPDATE_TEST_FLAKE_CANDIDATE_REJECT:-} == 1 ]]; then
      printf 'candidate lock\n' >>flake.lock
    fi
    mutate_phase candidate-root-lock flake.lock
    signal_phase candidate-root-lock
    fail_phase candidate-root-lock
    status_three_phase candidate-root-lock
  fi
elif [[ $1 == flake && $2 == check ]]; then
  if [[ ${UPDATE_TEST_MUTATE_LIVE:-} == 1 ]]; then
    printf 'external\n' >>"$NIX_CONFIG_DIR/external.txt"
  fi
  if [[ ${3:-} == ./config/ai ]]; then
    signal_phase candidate-portable-validation
    fail_phase candidate-portable-validation
    status_three_phase candidate-portable-validation
  else
    signal_phase candidate-root-validation
    fail_phase candidate-root-validation
    status_three_phase candidate-root-validation
  fi
elif [[ $1 == flake && $2 == show ]]; then
  signal_phase candidate-root-instantiation
  fail_phase candidate-root-instantiation
  status_three_phase candidate-root-instantiation
elif [[ $1 == build ]]; then
  if [[ -n ${UPDATE_TEST_EXTERNAL_LOG:-} ]]; then
    printf 'build\n' >>"$UPDATE_TEST_EXTERNAL_LOG"
  fi
  fail_phase candidate-build
  if [[ " $* " == *" --print-out-paths "* ]]; then
    printf '%s\n' "$UPDATE_TEST_SYSTEM_CONFIG"
  fi
else
  exit 2
fi
""",
        )
        executable("python", '#!/usr/bin/env bash\nexec python3 "$@"\n')
        executable(
            "nixfmt",
            """#!/usr/bin/env bash
set -euo pipefail
if [[ ${UPDATE_TEST_SIGNAL_PHASE:-} == candidate-format \
  || ${UPDATE_TEST_FAILURE_PHASE:-} == candidate-format ]]; then
  printf '# formatted\n' >>"$1"
fi
if [[ ${UPDATE_TEST_SIGNAL_PHASE:-} == candidate-format \
  && ! -e ${UPDATE_TEST_SIGNAL_MARKER:-/nonexistent} ]]; then
  : >"$UPDATE_TEST_SIGNAL_MARKER"
  kill -TERM "$PPID"
fi
if [[ ${UPDATE_TEST_FAILURE_PHASE:-} == candidate-format ]]; then exit 71; fi
""",
        )
        real_git = shutil.which("git") or "/usr/bin/git"
        real_chmod = shutil.which("chmod") or "/bin/chmod"
        real_jq = shutil.which("jq") or "/usr/bin/jq"
        real_mkdir = shutil.which("mkdir") or "/bin/mkdir"
        real_rm = shutil.which("rm") or "/bin/rm"
        executable(
            "git",
            """#!/usr/bin/env bash
set -euo pipefail
phase=${UPDATE_TEST_SIGNAL_PHASE:-}
marker=${UPDATE_TEST_SIGNAL_MARKER:-}
tree_failure=${UPDATE_TEST_CANDIDATE_TREE_FAILURE:-}
tree_failure_marker=${UPDATE_TEST_CANDIDATE_TREE_FAILURE_MARKER:-}
if [[ -n $tree_failure && -n $tree_failure_marker \
  && ! -e $tree_failure_marker && -f projection.json \
  && $(<projection.json) != "{}" ]]; then
  fail_tree_operation=false
  if [[ $tree_failure == add && ${1:-} == add && ${2:-} == -A \
    && ${3:-} == -- ]]; then
    fail_tree_operation=true
  elif [[ $tree_failure == write-tree && ${1:-} == write-tree && $# -eq 1 ]]; then
    fail_tree_operation=true
  fi
  if [[ $fail_tree_operation == true ]]; then
    printf '%s\n' "$tree_failure" >"$tree_failure_marker"
    exit 71
  fi
fi
for argument in "$@"; do
  if [[ $argument == verify-commit ]]; then
    if [[ ${UPDATE_TEST_MUTATE_LIVE_DURING_VERIFY:-} == 1 ]]; then
      printf 'verify edit\n' >"$NIX_CONFIG_DIR/verify-external.txt"
    fi
    exit 0
  fi
done
if [[ " $* " == *" commit -S "* ]]; then
  filtered=()
  candidate=
  previous=
  for argument in "$@"; do
    if [[ $previous == -C ]]; then candidate=$argument; fi
    previous=$argument
    [[ $argument == -S ]] || filtered+=("$argument")
  done
  if [[ ${UPDATE_TEST_HOOK_INJECT:-} == 1 ]]; then
    printf 'hook injection\n' >"$candidate/hook-extra.txt"
    "$REAL_GIT" -C "$candidate" add -- hook-extra.txt
  fi
  exec "$REAL_GIT" -c user.name=Test -c user.email=test@example.invalid \
    -c commit.gpgsign=false "${filtered[@]}"
fi
if [[ $phase == merge-failure && " $* " == *" merge --ff-only "* ]]; then
  "$REAL_GIT" "$@"
  : >"$marker"
  exit 71
fi
if [[ $phase == merge-partial-failure && " $* " == *" merge --ff-only "* ]]; then
  printf 'partial merge\n' >"$NIX_CONFIG_DIR/tracked.txt"
  "$REAL_GIT" -C "$NIX_CONFIG_DIR" add -- tracked.txt
  : >"$marker"
  exit 71
fi
if [[ $phase == merge-sigterm && " $* " == *" merge --ff-only "* ]]; then
  "$REAL_GIT" "$@"
  : >"$marker"
  kill -TERM "$PPID"
  exit 0
fi
if [[ $phase == merge-untracked || $phase == merge-ignored ]] \
  && [[ " $* " == *" merge --ff-only "* ]]; then
  "$REAL_GIT" "$@"
  if [[ $phase == merge-ignored ]]; then
    printf 'post merge\n' >"$NIX_CONFIG_DIR/ignored.tmp"
  else
    printf 'post merge\n' >"$NIX_CONFIG_DIR/post-merge.tmp"
  fi
  exit 0
fi
if [[ $phase == worktree-remove-failure \
  && " $* " == *" worktree remove --force "* ]]; then
  : >"$marker"
  if [[ -n ${UPDATE_TEST_BLOCK_CLEANUP_RELEASE:-} ]]; then
    while [[ ! -e $UPDATE_TEST_BLOCK_CLEANUP_RELEASE ]]; do sleep 0.01; done
  fi
  exit 71
fi
if [[ $phase == worktree-list-failure \
  && " $* " == *" worktree list --porcelain "* ]]; then
  exit 71
fi
if [[ $phase == partial-apply-failure && " $* " == *" apply --index "* ]]; then
  printf 'partial\n' >"$NIX_CONFIG_DIR/tracked.txt"
  "$REAL_GIT" -C "$NIX_CONFIG_DIR" add -- tracked.txt
  : >"$marker"
  exit 71
fi
if [[ ${UPDATE_TEST_FAIL_RESTORE:-} == 1 && " $* " == *" restore --source="* \
  && ! -e ${UPDATE_TEST_RESTORE_FAILURE_MARKER:-/nonexistent} ]]; then
  : >"$UPDATE_TEST_RESTORE_FAILURE_MARKER"
  exit 71
fi
if [[ ${UPDATE_TEST_FAIL_HELD_BACK_RESTORE:-} == 1 \
  && " $* " == *" read-tree --reset -u "* ]]; then
  exit 71
fi
if [[ $phase == after-apply && " $* " == *" apply --index "* ]]; then
  "$REAL_GIT" "$@"
  if [[ ! -e $marker ]]; then : >"$marker"; kill -TERM "$PPID"; fi
  exit 0
fi
if [[ $phase == after-read-tree && " $* " == *" read-tree "* ]]; then
  "$REAL_GIT" "$@"
  if [[ ! -e $marker ]]; then : >"$marker"; kill -TERM "$PPID"; fi
  exit 0
fi
if [[ " $* " == *" merge --ff-only "* \
  && -n ${UPDATE_TEST_EXTERNAL_LOG:-} ]]; then
  printf 'publish\n' >>"$UPDATE_TEST_EXTERNAL_LOG"
fi
if [[ " $* " == *" push "* ]]; then
  if [[ -n ${UPDATE_TEST_EXTERNAL_LOG:-} ]]; then
    printf 'push\n' >>"$UPDATE_TEST_EXTERNAL_LOG"
  fi
  if [[ -n ${UPDATE_TEST_PUSH_MARKER:-} ]]; then
    : >"$UPDATE_TEST_PUSH_MARKER"
  fi
  exit "${UPDATE_TEST_PUSH_STATUS:-0}"
fi
exec "$REAL_GIT" "$@"
            """,
        )
        executable(
            "jq",
            """#!/usr/bin/env bash
set -euo pipefail
if [[ ${UPDATE_TEST_JQ_FAILURE:-} == catalog-inputs \
  && " $* " == *".packages[] | .input // empty"* ]]; then
  exit 71
fi
if [[ ${UPDATE_TEST_JQ_FAILURE:-} == target-rows \
  && " $* " == *"def phase:"* ]]; then
  exit 72
fi
exec "$REAL_JQ" "$@"
""",
        )
        if nixos_driver is None:
            executable("hostname", "#!/bin/sh\nprintf 'hera\\n'\n")
        else:
            if nixos_driver not in {"executable", "missing", "nonexecutable"}:
                raise ValueError(f"unknown NixOS driver fixture: {nixos_driver}")
            executable("hostname", "#!/bin/sh\nprintf 'vps\\n'\n")
            executable(
                "nixos-rebuild",
                """#!/usr/bin/env bash
set -euo pipefail
if [[ -n ${UPDATE_TEST_EXTERNAL_LOG:-} ]]; then
  printf 'switch\n' >>"$UPDATE_TEST_EXTERNAL_LOG"
fi
if [[ ${UPDATE_TEST_FAILURE_PHASE:-} == candidate-switch ]]; then
  exit 71
fi
""",
            )
            if nixos_driver != "missing":
                (root / "build").write_text(
                    """#!/usr/bin/env bash
set -euo pipefail
[[ $# -ge 2 && $1 == -- ]] || {
  printf 'invalid driver delimiter\n' >&2
  exit 72
}
if [[ -n ${UPDATE_TEST_DRIVER_LOG:-} ]]; then
  printf '%s' "$PWD" >>"$UPDATE_TEST_DRIVER_LOG"
  printf '\t%s' "$@" >>"$UPDATE_TEST_DRIVER_LOG"
  printf '\n' >>"$UPDATE_TEST_DRIVER_LOG"
fi
shift
exec "$@"
"""
                )
                (root / "build").chmod(0o700 if nixos_driver == "executable" else 0o600)
        executable("nix-env", "#!/bin/sh\nexit 0\n")
        executable(
            "sudo",
            """#!/bin/sh
if [ -n "${UPDATE_TEST_SUDO_LOG:-}" ]; then
  printf '%s\n' "$*" >>"$UPDATE_TEST_SUDO_LOG"
fi
exec "$@"
""",
        )
        executable(
            "darwin-rebuild",
            """#!/usr/bin/env bash
set -euo pipefail
if [[ -n ${UPDATE_TEST_EXTERNAL_LOG:-} ]]; then
  printf 'switch\n' >>"$UPDATE_TEST_EXTERNAL_LOG"
fi
if [[ ${UPDATE_TEST_FAILURE_PHASE:-} == candidate-switch ]]; then
  exit 71
fi
""",
        )
        executable(
            "chmod",
            """#!/usr/bin/env bash
set -euo pipefail
"$REAL_CHMOD" "$@"
if [[ ${UPDATE_TEST_SIGNAL_PHASE:-} == after-normalize \
  && ! -e ${UPDATE_TEST_SIGNAL_MARKER:-/nonexistent} ]]; then
  : >"$UPDATE_TEST_SIGNAL_MARKER"
  kill -TERM "$PPID"
fi
            """,
        )
        executable(
            "mkdir",
            """#!/usr/bin/env bash
set -euo pipefail
"$REAL_MKDIR" "$@"
if [[ ${UPDATE_TEST_SIGNAL_PHASE:-} == lock-acquisition \
  && ${*: -1} == */update-agents.lock ]]; then
  : >"$UPDATE_TEST_SIGNAL_MARKER"
  kill -TERM "$PPID"
fi
""",
        )
        executable(
            "rm",
            """#!/usr/bin/env bash
set -euo pipefail
if [[ ${UPDATE_TEST_FAIL_QUIET_LOG_REMOVE:-} == 1 ]]; then
  for argument in "$@"; do
    if [[ $argument == "$TMPDIR"/update-output.* ]]; then exit 71; fi
  done
fi
exec "$REAL_RM" "$@"
""",
        )

        subprocess.run([real_git, "init", "-q", str(root)], check=True)
        subprocess.run(
            [real_git, "-C", str(root), "config", "core.fileMode", "true"],
            check=True,
        )
        subprocess.run(
            [real_git, "-C", str(root), "config", "diff.renames", "copies"],
            check=True,
        )
        subprocess.run([real_git, "-C", str(root), "add", "."], check=True)
        subprocess.run(
            [
                real_git,
                "-C",
                str(root),
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.invalid",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "-qm",
                "baseline",
            ],
            check=True,
        )
        baseline = subprocess.run(
            [real_git, "-C", str(root), "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        environment = {
            **os.environ,
            "NIX_CONFIG_DIR": str(root),
            "PATH": f"{fake_bin}:{os.environ['PATH']}",
            "REAL_CHMOD": real_chmod,
            "REAL_GIT": real_git,
            "REAL_JQ": real_jq,
            "REAL_MKDIR": real_mkdir,
            "REAL_RM": real_rm,
            "TMPDIR": temporary,
            "UPDATE_TEST_SYSTEM_CONFIG": str(system_config),
        }
        return root, environment, baseline

    @staticmethod
    def _update_agents_projection(root: Path):
        projection = {}
        for current, directories, files in os.walk(
            root, topdown=True, followlinks=False
        ):
            current_path = Path(current)
            if current_path == root:
                directories[:] = [name for name in directories if name != ".git"]
            directories.sort()
            files.sort()
            for entry in [*directories, *files]:
                path = current_path / entry
                name = path.relative_to(root).as_posix()
                if path.is_symlink():
                    projection[name] = ("symlink", os.readlink(path))
                elif path.is_dir():
                    projection[name] = (
                        "directory",
                        stat.S_IMODE(path.stat().st_mode),
                    )
                elif path.is_file():
                    info = path.stat()
                    projection[name] = (
                        "file",
                        stat.S_IMODE(info.st_mode),
                        path.read_bytes(),
                    )
                else:
                    projection[name] = ("missing",)
        return projection

    def _assert_update_agents_unchanged(
        self, root: Path, baseline: str, projection
    ) -> None:
        self.assertEqual(
            subprocess.run(
                ["git", "-C", str(root), "rev-parse", "HEAD"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip(),
            baseline,
        )
        self.assertEqual(
            subprocess.run(
                ["git", "-C", str(root), "status", "--porcelain"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout,
            "",
        )
        self.assertEqual(self._update_agents_projection(root), projection)
        worktrees = subprocess.run(
            ["git", "-C", str(root), "worktree", "list", "--porcelain"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        self.assertEqual(worktrees.count("worktree "), 1)
        self.assertFalse((root / ".git/update-agents.lock").exists())
        self.assertEqual(list(root.parent.glob("update.*")), [])

    def test_update_agents_publishes_declared_filesystem_identities(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            result = subprocess.run(
                [str(UPDATE_AGENTS)],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                baseline,
            )
            projection = self._update_agents_projection(root)
            self.assertEqual(projection["tracked.txt"], ("file", 0o640, b"after\n"))
            self.assertEqual(
                projection["mode.sh"], ("file", 0o755, b"#!/bin/sh\nexit 0\n")
            )
            self.assertEqual(
                projection["binary.bin"], ("file", 0o644, b"\x00after\xfe\n")
            )
            self.assertEqual(
                projection["format.nix"],
                ("file", 0o644, b"{ changed = true; }\n"),
            )
            self.assertEqual(
                projection["projection.json"],
                ("file", 0o644, b"{}\n"),
            )
            self.assertEqual(projection["link"], ("symlink", "target-new"))
            self.assertEqual(projection["regular-to-link"], ("symlink", "target-new"))
            self.assertEqual(
                projection["link-to-regular"],
                ("file", 0o644, b"regular after\n"),
            )
            self.assertNotIn("renamed-old.txt", projection)
            self.assertEqual(
                projection["renamed-new.txt"],
                ("file", 0o644, b"rename payload\n"),
            )
            self.assertEqual(
                projection["undeclared-rename-source.txt"],
                ("file", 0o644, b"undeclared rename\n"),
            )
            self.assertNotIn("deleted.txt", projection)
            self.assertEqual(projection["created.txt"], ("file", 0o644, b"created\n"))
            self.assertEqual(projection["new-directory"][0], "directory")
            self.assertEqual(
                projection["new-directory/generated-lock.json"],
                ("file", 0o644, b"{}\n"),
            )
            self.assertFalse((root / ".git/update-agents.lock").exists())
            self.assertEqual(list(root.parent.glob("update.*")), [])

    def test_update_agents_holds_back_only_rejected_shared_record(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, _baseline = self._create_update_agents_fixture(temp_dir)
            environment["UPDATE_TEST_ISOLATED_TARGETS"] = "1"

            result = subprocess.run(
                [str(UPDATE_AGENTS), "--quiet"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            versions = {
                name: record["version"]
                for name, record in json.loads(
                    (root / "shared.json").read_text()
                )["sources"].items()
            }
            self.assertEqual(
                versions,
                {
                    "a-success": "2.0.0",
                    "b-rejected": "1.0.0",
                    "c-success": "2.0.0",
                },
            )
            self.assertEqual(
                result.stdout,
                "..\n.\n....\n"
                "catalog/a-success 1.0.0 → 2.0.0 ✓\n"
                "catalog/c-success 1.0.0 → 2.0.0 ✓\n",
            )
            self.assertEqual(
                result.stderr,
                "update: held-back catalog targets:\n"
                "  b-rejected: retained 1.0.0 "
                "(package validation rejected the candidate)\n",
            )
            self.assertNotIn(
                "evaluating candidate",
                result.stdout + result.stderr,
            )

    def test_update_agents_quiet_reports_changes_only_after_push_succeeds(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            push_marker = Path(temp_dir) / "push-called"
            environment.update(
                UPDATE_TEST_ISOLATED_TARGETS="1",
                UPDATE_TEST_PUSH_MARKER=str(push_marker),
                UPDATE_TEST_PUSH_STATUS="71",
                UPDATE_TEST_REJECT_TARGETS="",
            )

            result = subprocess.run(
                [str(UPDATE_AGENTS), "--quiet", "--commit", "--push"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            self.assertEqual(result.returncode, 71)
            self.assertTrue(push_marker.exists(), "failing push was not attempted")
            self.assertNotIn("catalog/", result.stdout + result.stderr)
            self.assertNotEqual(
                subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                baseline,
            )
            self.assertEqual(
                {
                    name: record["version"]
                    for name, record in json.loads(
                        (root / "shared.json").read_text()
                    )["sources"].items()
                },
                {
                    "a-success": "2.0.0",
                    "b-rejected": "2.0.0",
                    "c-success": "2.0.0",
                },
            )

    def test_update_agents_returns_nonzero_when_every_candidate_is_held_back(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment.update(
                UPDATE_TEST_ISOLATED_TARGETS="1",
                UPDATE_TEST_REJECT_TARGETS="a-success,b-rejected,c-success",
            )

            result = subprocess.run(
                [str(UPDATE_AGENTS), "--quiet"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            self.assertEqual(result.returncode, 3)
            self.assertEqual(result.stdout, ".\n.\n.\n")
            self.assertEqual(
                result.stderr,
                "update: held-back catalog targets:\n"
                "  a-success: retained 1.0.0 "
                "(package validation rejected the candidate)\n"
                "  b-rejected: retained 1.0.0 "
                "(package validation rejected the candidate)\n"
                "  c-success: retained 1.0.0 "
                "(package validation rejected the candidate)\n"
                "update: every selected catalog candidate was held back\n",
            )
            self.assertNotIn("target checkout:", result.stderr)
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_quiet_streams_progress_before_slow_flake_update(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, _baseline = self._create_update_agents_fixture(
                temp_dir,
                portable_inputs=("uncatalogued",),
            )
            marker = Path(temp_dir) / "flake-started"
            release = Path(temp_dir) / "flake-release"
            environment.update(
                UPDATE_TEST_BLOCK_FLAKE_MARKER=str(marker),
                UPDATE_TEST_BLOCK_FLAKE_RELEASE=str(release),
                UPDATE_TEST_NO_CHANGES="1",
            )
            process = subprocess.Popen(
                [str(UPDATE_AGENTS), "--quiet", "--all-inputs"],
                cwd=root,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            try:
                deadline = time.monotonic() + 10
                while (
                    not marker.exists()
                    and process.poll() is None
                    and time.monotonic() < deadline
                ):
                    time.sleep(0.01)
                self.assertTrue(marker.exists(), "fake flake update never started")
                ready, _, _ = select.select([process.stdout], [], [], 2)
                self.assertTrue(ready, "quiet progress was not streamed")
                first = os.read(process.stdout.fileno(), 1)
                self.assertEqual(first, b".")
                self.assertIsNone(process.poll())
            finally:
                release.touch()
                stdout_tail, stderr = process.communicate(timeout=30)
            self.assertEqual(process.returncode, 0, stderr.decode())
            self.assertEqual(first + stdout_tail, b".......\n")
            self.assertEqual(stderr, b"")

    def test_update_agents_quiet_bounds_hard_failure_output(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment.update(
                UPDATE_TEST_FAILURE_PHASE="candidate-update",
                UPDATE_TEST_NOISY_FAILURE="1",
            )
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--quiet"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 71)
            self.assertEqual(result.stdout, ".\n")
            self.assertNotIn("noise 9\n", result.stderr)
            self.assertTrue(result.stderr.startswith("noise 10\n"), result.stderr)
            self.assertNotIn("fabricated", result.stderr)
            self.assertTrue(
                result.stderr.endswith(
                    "noise 29\nupdate: catalog/fixture failed (status 71)\n"
                ),
                result.stderr,
            )
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_quiet_does_not_report_rolled_back_candidate_changes(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            interleaving_log = Path(temp_dir) / "interleaving.log"
            environment.update(
                UPDATE_TEST_FAILURE_PHASE="candidate-root-validation",
                UPDATE_TEST_INTERLEAVING_LOG=str(interleaving_log),
                UPDATE_TEST_ISOLATED_TARGETS="1",
                UPDATE_TEST_REJECT_TARGETS="",
            )
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--quiet"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 71)
            self.assertNotIn("catalog/", result.stdout + result.stderr)
            events = interleaving_log.read_text().splitlines()
            self.assertIn("overlay a-success", events)
            self.assertIn("overlay b-rejected", events)
            self.assertIn("overlay c-success", events)
            self.assertIn(
                "nix flake check --no-build --option eval-cores 1 "
                "--option lazy-trees false --option eval-cache false",
                events,
            )
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_quiet_reports_changes_only_after_cleanup_succeeds(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, _baseline = self._create_update_agents_fixture(temp_dir)
            interleaving_log = Path(temp_dir) / "interleaving.log"
            environment.update(
                UPDATE_TEST_ISOLATED_TARGETS="1",
                UPDATE_TEST_INTERLEAVING_LOG=str(interleaving_log),
                UPDATE_TEST_REJECT_TARGETS="",
                UPDATE_TEST_SIGNAL_PHASE="worktree-list-failure",
            )

            result = subprocess.run(
                [str(UPDATE_AGENTS), "--quiet"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("failed to verify candidate worktree removal", result.stderr)
            self.assertNotIn("catalog/", result.stdout + result.stderr)
            self.assertEqual(
                {
                    name: record["version"]
                    for name, record in json.loads(
                        (root / "shared.json").read_text()
                    )["sources"].items()
                },
                {
                    "a-success": "2.0.0",
                    "b-rejected": "2.0.0",
                    "c-success": "2.0.0",
                },
            )
            events = interleaving_log.read_text().splitlines()
            self.assertIn(
                "overlay --record-target-change a-success --old-version 1.0.0",
                events,
            )
            self.assertIn(
                "overlay --record-target-change b-rejected --old-version 1.0.0",
                events,
            )
            self.assertIn(
                "overlay --record-target-change c-success --old-version 1.0.0",
                events,
            )

    def test_update_agents_quiet_reports_diagnostic_tail_once_on_cleanup_failure(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            _root, environment, _baseline = self._create_update_agents_fixture(
                temp_dir
            )
            environment.update(
                UPDATE_TEST_HOOK_INJECT="1",
                UPDATE_TEST_SIGNAL_PHASE="worktree-list-failure",
            )

            result = subprocess.run(
                [str(UPDATE_AGENTS), "--quiet", "--commit"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            diagnostic = "signed commit did not capture the complete transaction"
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stderr.count(diagnostic), 1, result.stderr)
            self.assertEqual(
                result.stderr.count("failed to verify candidate worktree removal"),
                1,
                result.stderr,
            )

    def test_update_agents_quiet_fails_if_diagnostic_log_cannot_be_removed(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            _root, environment, _baseline = self._create_update_agents_fixture(
                temp_dir
            )
            environment.update(
                UPDATE_TEST_FAIL_QUIET_LOG_REMOVE="1",
                UPDATE_TEST_NO_CHANGES="1",
            )

            result = subprocess.run(
                [str(UPDATE_AGENTS), "--quiet"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("failed to remove quiet diagnostic log", result.stderr)

    def test_update_agents_quiet_fails_when_requested_brew_is_unavailable(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, _baseline = self._create_update_agents_fixture(
                temp_dir
            )
            path_without_brew = os.pathsep.join(
                entry
                for entry in environment["PATH"].split(os.pathsep)
                if shutil.which("brew", path=entry) is None
            )
            self.assertIsNone(shutil.which("brew", path=path_without_brew))
            interleaving_log = Path(temp_dir) / "interleaving.log"
            environment.update(
                PATH=path_without_brew,
                UPDATE_TEST_ISOLATED_TARGETS="1",
                UPDATE_TEST_INTERLEAVING_LOG=str(interleaving_log),
                UPDATE_TEST_REJECT_TARGETS="",
            )

            result = subprocess.run(
                [str(UPDATE_AGENTS), "--quiet", "--brew"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("--brew requested but brew is unavailable", result.stderr)
            self.assertNotIn("catalog/", result.stdout + result.stderr)
            self.assertEqual(
                {
                    name: record["version"]
                    for name, record in json.loads(
                        (root / "shared.json").read_text()
                    )["sources"].items()
                },
                {
                    "a-success": "2.0.0",
                    "b-rejected": "2.0.0",
                    "c-success": "2.0.0",
                },
            )
            events = interleaving_log.read_text().splitlines()
            for name in ("a-success", "b-rejected", "c-success"):
                self.assertIn(
                    f"overlay --record-target-change {name} --old-version 1.0.0",
                    events,
                )

    def test_update_agents_requires_a_buildable_restored_baseline(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            interleaving_log = Path(temp_dir) / "interleaving.log"
            environment.update(
                UPDATE_TEST_ISOLATED_TARGETS="1",
                UPDATE_TEST_BASELINE_FAILURE_TARGETS="b-rejected",
                UPDATE_TEST_INTERLEAVING_LOG=str(interleaving_log),
            )

            result = subprocess.run(
                [str(UPDATE_AGENTS)],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("restored baseline validation failed: b-rejected", result.stderr)
            self.assertNotIn(
                "overlay c-success",
                interleaving_log.read_text(),
            )
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_restores_flake_locks_before_baseline_validation(self):
        cases = (
            ("build", "UPDATE_TEST_BUILD_TARGET"),
            ("copy", "UPDATE_TEST_COPY_TARGET"),
            ("npm-flake", "UPDATE_TEST_NPM_FLAKE_TARGET"),
        )
        for target, selector in cases:
            with self.subTest(target=target), tempfile.TemporaryDirectory() as temp_dir:
                root, environment, baseline = self._create_update_agents_fixture(
                    temp_dir
                )
                before = self._update_agents_projection(root)
                environment.update(
                    {
                        selector: "1",
                        "UPDATE_TEST_FLAKE_CANDIDATE_REJECT": "1",
                    }
                )

                result = subprocess.run(
                    [str(UPDATE_AGENTS), "--target", target],
                    capture_output=True,
                    text=True,
                    env=environment,
                    check=False,
                )

                self.assertEqual(result.returncode, 3, result.stderr)
                self.assertIn(f"{target}: retained", result.stderr)
                self.assertNotIn("candidate lock survived restoration", result.stderr)
                self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_attributes_flake_candidate_rejection_to_selected_target(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            interleaving_log = Path(temp_dir) / "interleaving.log"
            state_log = Path(temp_dir) / "state.log"
            environment.update(
                UPDATE_TEST_FLAKE_ISOLATED_TARGETS="1",
                UPDATE_TEST_INTERLEAVING_LOG=str(interleaving_log),
                UPDATE_TEST_STATEFUL_FLAKE_TARGETS="1",
                UPDATE_TEST_STATE_LOG=str(state_log),
            )

            result = subprocess.run(
                [
                    str(UPDATE_AGENTS),
                    "--target",
                    "flake-a",
                    "--target",
                    "flake-b",
                    "--target",
                    "flake-c",
                ],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("flake-b: retained", result.stderr)
            self.assertNotIn("flake-a: retained", result.stderr)
            self.assertNotIn("flake-c: retained", result.stderr)
            self.assertEqual(
                json.loads((root / "projection.json").read_text()),
                {"flake-a": True, "flake-c": True},
            )
            expected_lock_markers = ["state:flake-a", "state:flake-c"]
            for lock_path in (root / "config/ai/flake.lock", root / "flake.lock"):
                markers = [
                    line
                    for line in lock_path.read_text().splitlines()
                    if line.startswith("state:")
                ]
                self.assertEqual(markers, expected_lock_markers)

            self.assertEqual(
                [json.loads(line) for line in state_log.read_text().splitlines()],
                [
                    {
                        "phase": "candidate",
                        "name": "flake-a",
                        "portable": ["flake-a"],
                        "root": ["flake-a"],
                        "projection": ["flake-a"],
                    },
                    {
                        "phase": "candidate",
                        "name": "flake-b",
                        "portable": ["flake-a", "invalid-flake-b"],
                        "root": ["flake-a", "invalid-flake-b"],
                        "projection": ["flake-a", "flake-b"],
                    },
                    {
                        "phase": "baseline",
                        "name": "flake-b",
                        "portable": ["flake-a"],
                        "root": ["flake-a"],
                        "projection": ["flake-a"],
                    },
                    {
                        "phase": "candidate",
                        "name": "flake-c",
                        "portable": ["flake-a", "flake-c"],
                        "root": ["flake-a", "flake-c"],
                        "projection": ["flake-a", "flake-c"],
                    },
                ],
            )
            events = interleaving_log.read_text().splitlines()
            self.assertEqual(
                events,
                [
                    "overlay --inventory --json",
                    "overlay --prepare-target flake-a",
                    "nix flake update --flake ./config/ai flake-a-input",
                    "nix flake update nix-config-ai",
                    "overlay --sync-flake-projections flake-a",
                    "overlay --validate-candidate-target flake-a",
                    "overlay --prepare-target flake-b",
                    "nix flake update --flake ./config/ai flake-b-input",
                    "nix flake update nix-config-ai",
                    "overlay --sync-flake-projections flake-b",
                    "overlay --validate-candidate-target flake-b",
                    "overlay --validate-target flake-b",
                    "overlay --prepare-target flake-c",
                    "nix flake update --flake ./config/ai flake-c-input",
                    "nix flake update nix-config-ai",
                    "overlay --sync-flake-projections flake-c",
                    "overlay --validate-candidate-target flake-c",
                    "overlay --inventory --json",
                    "nix flake check ./config/ai --all-systems --no-build --no-eval-cache",
                    "nix flake show --json --drv-paths --all-systems --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                    "nix flake check --no-build --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                ],
            )
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                baseline,
            )

    def test_update_agents_treats_unselected_final_projection_drift_as_hard(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment.update(
                UPDATE_TEST_COPY_TARGET="1",
                UPDATE_TEST_FINAL_INVENTORY_FAIL="1",
            )
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "copy"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 85, result.stderr)
            self.assertIn("unselected projection drift", result.stderr)
            self.assertNotIn("retained", result.stderr)
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_fails_if_held_back_restore_fails(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment.update(
                UPDATE_TEST_ISOLATED_TARGETS="1",
                UPDATE_TEST_FAIL_HELD_BACK_RESTORE="1",
            )

            result = subprocess.run(
                [str(UPDATE_AGENTS)],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            self.assertEqual(result.returncode, 71)
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_never_treats_nix_status_three_as_a_holdback(self):
        cases = (
            ("target-portable", "candidate-portable-lock", ["--target", "fixed"]),
            ("target-root", "candidate-root-lock", ["--target", "fixed"]),
            ("all-input-root", "candidate-root-lock", ["--all-inputs"]),
            ("final-check", "candidate-portable-validation", []),
            ("final-root-instantiation", "candidate-root-instantiation", []),
        )
        for case, phase, arguments in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temp_dir:
                root, environment, baseline = self._create_update_agents_fixture(
                    temp_dir
                )
                before = self._update_agents_projection(root)
                environment["UPDATE_TEST_NIX_STATUS3_PHASE"] = phase
                if case.startswith("target-"):
                    environment["UPDATE_TEST_FIXED_TARGET"] = "1"

                result = subprocess.run(
                    [str(UPDATE_AGENTS), *arguments],
                    capture_output=True,
                    text=True,
                    env=environment,
                    check=False,
                )

                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertNotIn("held-back catalog targets", result.stderr)
                self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_treats_schedule_query_failures_as_hard(self):
        cases = (("catalog-inputs", ["--all-inputs"], 71), ("target-rows", [], 72))
        for failure, arguments, expected in cases:
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temp_dir:
                root, environment, baseline = self._create_update_agents_fixture(
                    temp_dir
                )
                before = self._update_agents_projection(root)
                environment["UPDATE_TEST_JQ_FAILURE"] = failure

                result = subprocess.run(
                    [str(UPDATE_AGENTS), *arguments],
                    capture_output=True,
                    text=True,
                    env=environment,
                    check=False,
                )

                self.assertEqual(result.returncode, expected, result.stderr)
                self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_returns_nonzero_for_one_explicit_rejection(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment.update(
                UPDATE_TEST_NPM_LOCK_TARGET="1",
                UPDATE_TEST_REJECT_NPM_LOCK="1",
            )

            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "npm-lock"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            self.assertEqual(result.returncode, 3)
            self.assertIn("npm-lock: retained 1.0.0", result.stderr)
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_runs_one_fixed_input_without_unrelated_updates(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            command_log = Path(temp_dir) / "commands.log"
            system_config_dir = Path(temp_dir) / "system-config"
            system_config_dir.mkdir()
            environment["UPDATE_TEST_FIXED_TARGET"] = "1"
            environment["UPDATE_TEST_COMMAND_LOG"] = str(command_log)
            environment["UPDATE_AGENTS_SYSTEM_CONFIG_DIR"] = str(system_config_dir)
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "fixed"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                baseline,
            )
            self.assertEqual((root / "fixed.txt").read_text(), "fixed after\n")
            self.assertEqual((root / "tracked.txt").read_text(), "before\n")
            self.assertEqual(
                (root / "projection.json").read_text(), '{"fixed": true}\n'
            )
            commands = command_log.read_text().splitlines()
            self.assertEqual(
                commands,
                [
                    "flake update --flake ./config/ai fixed-input",
                    "flake update nix-config-ai",
                    "flake check ./config/ai --all-systems --no-build --no-eval-cache",
                    "flake show --json --drv-paths --all-systems --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                    "flake check --no-build --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                ],
            )

        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment["UPDATE_TEST_FIXED_TARGET"] = "1"
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "fixed", "--dry-run"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("authoritative tree unchanged", result.stdout)
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_config_dir_resolution_precedence(self):
        # Every other test in this suite pins NIX_CONFIG_DIR, which has the
        # highest precedence, so this test exercises the remaining order: the
        # system config dir, then a PRIMARY nix-config work tree at the
        # invocation (flake.nix plus config/ai, not a linked worktree), then
        # ~/src/nix.
        real_git = shutil.which("git") or "/usr/bin/git"

        def commit_flake_marker(root):
            (root / "flake.nix").write_text("{ }\n")
            subprocess.run(
                [real_git, "-C", str(root), "add", "flake.nix"], check=True
            )
            subprocess.run(
                [
                    real_git,
                    "-C",
                    str(root),
                    "-c",
                    "user.name=Test",
                    "-c",
                    "user.email=test@example.invalid",
                    "-c",
                    "commit.gpgsign=false",
                    "commit",
                    "-qm",
                    "flake marker",
                ],
                check=True,
            )
            return subprocess.run(
                [real_git, "-C", str(root), "rev-parse", "HEAD"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip()

        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, _ = self._create_update_agents_fixture(temp_dir)
            baseline = commit_flake_marker(root)
            before = self._update_agents_projection(root)
            environment.pop("NIX_CONFIG_DIR")
            # A wrong resolution must not be able to reach a real checkout.
            environment["HOME"] = temp_dir
            environment["UPDATE_AGENTS_SYSTEM_CONFIG_DIR"] = str(
                Path(temp_dir) / "absent"
            )
            environment["UPDATE_TEST_FIXED_TARGET"] = "1"

            with self.subTest(resolution="invoking primary work tree"):
                result = subprocess.run(
                    [str(UPDATE_AGENTS), "--target", "fixed", "--dry-run"],
                    capture_output=True,
                    text=True,
                    env=environment,
                    cwd=str(root / "config"),
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("authoritative tree unchanged", result.stdout)
                self._assert_update_agents_unchanged(root, baseline, before)

            with self.subTest(resolution="linked worktree refused"):
                worktree = Path(temp_dir) / "linked-worktree"
                subprocess.run(
                    [
                        real_git,
                        "-C",
                        str(root),
                        "worktree",
                        "add",
                        "-q",
                        "--detach",
                        str(worktree),
                    ],
                    check=True,
                )
                result = subprocess.run(
                    [str(UPDATE_AGENTS), "--target", "fixed", "--dry-run"],
                    capture_output=True,
                    text=True,
                    env=environment,
                    cwd=str(worktree),
                    check=False,
                )
                # The linked worktree must not be targeted: resolution falls
                # through to $HOME/src/nix, which does not exist here, so the
                # run fails instead of pulling and publishing a worktree.
                self.assertNotEqual(result.returncode, 0)
                subprocess.run(
                    [
                        real_git,
                        "-C",
                        str(root),
                        "worktree",
                        "remove",
                        "--force",
                        str(worktree),
                    ],
                    check=True,
                )
                self._assert_update_agents_unchanged(root, baseline, before)

            decoy = Path(temp_dir) / "decoy"
            (decoy / "config/ai").mkdir(parents=True)
            (decoy / "flake.nix").write_text("{ }\n")
            subprocess.run([real_git, "init", "-q", str(decoy)], check=True)
            subprocess.run([real_git, "-C", str(decoy), "add", "."], check=True)
            subprocess.run(
                [
                    real_git,
                    "-C",
                    str(decoy),
                    "-c",
                    "user.name=Test",
                    "-c",
                    "user.email=test@example.invalid",
                    "-c",
                    "commit.gpgsign=false",
                    "commit",
                    "-qm",
                    "decoy",
                ],
                check=True,
            )
            neutral = Path(temp_dir) / "neutral"
            neutral.mkdir()

            with self.subTest(resolution="system config dir wins from a neutral cwd"):
                environment["UPDATE_AGENTS_SYSTEM_CONFIG_DIR"] = str(root)
                result = subprocess.run(
                    [str(UPDATE_AGENTS), "--target", "fixed", "--dry-run"],
                    capture_output=True,
                    text=True,
                    env=environment,
                    cwd=str(neutral),
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("authoritative tree unchanged", result.stdout)
                self.assertIn(f"target checkout: {root}", result.stderr)
                self._assert_update_agents_unchanged(root, baseline, before)

            with self.subTest(resolution="implicit retarget refused"):
                # Standing in a DIFFERENT nix-config checkout while the
                # system checkout owns the host must fail loudly, naming
                # both candidates, instead of silently transacting.
                result = subprocess.run(
                    [str(UPDATE_AGENTS), "--target", "fixed", "--dry-run"],
                    capture_output=True,
                    text=True,
                    env=environment,
                    cwd=str(decoy),
                    check=False,
                )
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("refusing implicit retarget", result.stderr)
                self.assertIn(str(decoy), result.stderr)
                self.assertIn(str(root), result.stderr)
                self._assert_update_agents_unchanged(root, baseline, before)

            with self.subTest(resolution="hostile git selectors are scrubbed"):
                # A leaked GIT_DIR/GIT_WORK_TREE must not redirect target
                # selection or the transaction at another repository.
                hostile = dict(environment)
                hostile["GIT_DIR"] = str(decoy / ".git")
                hostile["GIT_WORK_TREE"] = str(decoy)
                hostile["GIT_INDEX_FILE"] = str(decoy / ".git/index")
                result = subprocess.run(
                    [str(UPDATE_AGENTS), "--target", "fixed", "--dry-run"],
                    capture_output=True,
                    text=True,
                    env=hostile,
                    cwd=str(neutral),
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("authoritative tree unchanged", result.stdout)
                self.assertIn(f"target checkout: {root}", result.stderr)
                self.assertFalse((decoy / ".git/update-agents.lock").exists())
                self.assertFalse((decoy / ".git/worktrees").exists())
                self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_routes_flake_input_copy_through_named_locks(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            command_log = Path(temp_dir) / "commands.log"
            interleaving_log = Path(temp_dir) / "interleaving.log"
            environment["UPDATE_TEST_BUILD_TARGET"] = "1"
            environment["UPDATE_TEST_COPY_TARGET"] = "1"
            environment["UPDATE_TEST_COMMAND_LOG"] = str(command_log)
            environment["UPDATE_TEST_INTERLEAVING_LOG"] = str(interleaving_log)
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "copy"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                baseline,
            )
            self.assertEqual((root / "fixed.txt").read_text(), "fixed before\n")
            self.assertEqual((root / "tracked.txt").read_text(), "before\n")
            self.assertEqual(
                (root / "projection.json").read_text(), '{"copy": true}\n'
            )
            self.assertEqual(
                command_log.read_text().splitlines(),
                [
                    "flake update --flake ./config/ai copy-input",
                    "flake update nix-config-ai",
                    "flake check ./config/ai --all-systems --no-build --no-eval-cache",
                    "flake show --json --drv-paths --all-systems --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                    "flake check --no-build --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                ],
            )
            events = interleaving_log.read_text().splitlines()
            ordered = [
                "overlay --prepare-target copy",
                "nix flake update --flake ./config/ai copy-input",
                "nix flake update nix-config-ai",
                "overlay --sync-flake-projections copy",
                "overlay --validate-candidate-target copy",
            ]
            position = -1
            for event in ordered:
                position = events.index(event, position + 1)
            self.assertEqual(
                events.count("overlay --validate-candidate-target copy"), 1
            )
            self.assertNotIn(
                "overlay --validate-candidate-target build", events
            )

        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, _baseline = self._create_update_agents_fixture(temp_dir)
            command_log = Path(temp_dir) / "commands.log"
            interleaving_log = Path(temp_dir) / "interleaving.log"
            environment["UPDATE_TEST_COPY_TARGET"] = "1"
            environment["UPDATE_TEST_COMMAND_LOG"] = str(command_log)
            environment["UPDATE_TEST_INTERLEAVING_LOG"] = str(interleaving_log)
            environment["UPDATE_TEST_NO_CHANGES"] = "1"
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--quiet"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "......\n")
            self.assertEqual(result.stderr, "")
            self.assertEqual(
                command_log.read_text().splitlines()[0],
                "flake update --flake ./config/ai copy-input",
            )
            self.assertNotIn(
                "overlay --validate-candidate-target copy",
                interleaving_log.read_text().splitlines(),
            )

            verbose_result = subprocess.run(
                [str(UPDATE_AGENTS), "--verbose"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(verbose_result.returncode, 0, verbose_result.stderr)
            self.assertIn("target checkout:", verbose_result.stderr)
            self.assertIn("evaluating candidate", verbose_result.stderr)

    def test_update_agents_routes_flake_input_build_through_named_locks(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            command_log = Path(temp_dir) / "commands.log"
            environment["UPDATE_TEST_BUILD_TARGET"] = "1"
            environment["UPDATE_TEST_COMMAND_LOG"] = str(command_log)
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "build"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                baseline,
            )
            self.assertEqual((root / "fixed.txt").read_text(), "fixed before\n")
            self.assertEqual((root / "tracked.txt").read_text(), "before\n")
            self.assertEqual(
                (root / "projection.json").read_text(), '{"build": true}\n'
            )
            self.assertEqual(
                command_log.read_text().splitlines(),
                [
                    "flake update --flake ./config/ai build-input",
                    "flake update nix-config-ai",
                    "flake check ./config/ai --all-systems --no-build --no-eval-cache",
                    "flake show --json --drv-paths --all-systems --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                    "flake check --no-build --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                ],
            )

        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment["UPDATE_TEST_BUILD_TARGET"] = "1"
            environment["UPDATE_TEST_FAILURE_PHASE"] = "candidate-projection"
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "build"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self._assert_update_agents_unchanged(root, baseline, before)

        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment["UPDATE_TEST_BUILD_TARGET"] = "1"
            environment["UPDATE_TEST_FAILURE_PHASE"] = "candidate-validation"
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "build"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 71, result.stderr)
            self.assertNotIn("retained", result.stderr)
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_candidate_tree_capture_failures_abort_before_validation_or_publication(
        self,
    ):
        for operation in ("add", "write-tree"):
            with (
                self.subTest(operation=operation),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                root, environment, baseline = self._create_update_agents_fixture(
                    temp_dir
                )
                before = self._update_agents_projection(root)
                failure_marker = Path(temp_dir) / f"{operation}.failed"
                interleaving_log = Path(temp_dir) / f"{operation}.events"
                external_log = Path(temp_dir) / f"{operation}.external"
                push_marker = Path(temp_dir) / f"{operation}.pushed"
                external_log.write_text("")
                environment.update(
                    UPDATE_TEST_BUILD_TARGET="1",
                    UPDATE_TEST_CANDIDATE_TREE_FAILURE=operation,
                    UPDATE_TEST_CANDIDATE_TREE_FAILURE_MARKER=str(failure_marker),
                    UPDATE_TEST_EXTERNAL_LOG=str(external_log),
                    UPDATE_TEST_INTERLEAVING_LOG=str(interleaving_log),
                    UPDATE_TEST_PUSH_MARKER=str(push_marker),
                )

                result = subprocess.run(
                    [
                        str(UPDATE_AGENTS),
                        "--target",
                        "build",
                        "--commit",
                        "--push",
                    ],
                    capture_output=True,
                    text=True,
                    env=environment,
                    check=False,
                )

                self.assertEqual(result.returncode, 71, result.stderr)
                self.assertEqual(failure_marker.read_text(), f"{operation}\n")
                self.assertNotIn("retained", result.stderr)
                self.assertEqual(
                    interleaving_log.read_text().splitlines(),
                    [
                        "overlay --inventory --json",
                        "overlay --prepare-target build",
                        "nix flake update --flake ./config/ai build-input",
                        "nix flake update nix-config-ai",
                        "overlay --sync-flake-projections build",
                    ],
                )
                self.assertEqual(external_log.read_text(), "")
                self.assertFalse(push_marker.exists())
                self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_routes_npm_flake_input_as_one_named_transaction(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            command_log = Path(temp_dir) / "commands.log"
            interleaving_log = Path(temp_dir) / "interleaving.log"
            environment["UPDATE_TEST_NPM_FLAKE_TARGET"] = "1"
            environment["UPDATE_TEST_COMMAND_LOG"] = str(command_log)
            environment["UPDATE_TEST_INTERLEAVING_LOG"] = str(interleaving_log)
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--quiet", "--target", "npm-flake"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                result.stdout,
                ".....\ncatalog/npm-flake 11111111 → 22222222 ✓\n",
            )
            self.assertEqual(result.stderr, "")
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                baseline,
            )
            self.assertEqual((root / "fixed.txt").read_text(), "npm flake after\n")
            self.assertEqual((root / "tracked.txt").read_text(), "before\n")
            self.assertEqual(
                command_log.read_text().splitlines(),
                [
                    "flake update --flake ./config/ai npm-flake-input",
                    "flake update nix-config-ai",
                    "flake check ./config/ai --all-systems --no-build --no-eval-cache",
                    "flake show --json --drv-paths --all-systems --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                    "flake check --no-build --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                ],
            )
            events = interleaving_log.read_text().splitlines()
            ordered = [
                "overlay --prepare-target npm-flake",
                "nix flake update --flake ./config/ai npm-flake-input",
                "nix flake update nix-config-ai",
                "overlay --sync-flake-projections npm-flake",
                "overlay --validate-candidate-target npm-flake",
                "overlay --record-target-change npm-flake --old-version 1.0.0 --old-revision "
                + "1" * 40,
            ]
            position = -1
            for event in ordered:
                position = events.index(event, position + 1)

        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, _baseline = self._create_update_agents_fixture(temp_dir)
            command_log = Path(temp_dir) / "commands.log"
            environment["UPDATE_TEST_NPM_FLAKE_TARGET"] = "1"
            environment["UPDATE_TEST_COMMAND_LOG"] = str(command_log)
            result = subprocess.run(
                [str(UPDATE_AGENTS)],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((root / "fixed.txt").read_text(), "npm flake after\n")
            self.assertIn("npm-flake-input", command_log.read_text().splitlines()[0])

        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment.update(
                UPDATE_TEST_CANDIDATE_REJECT_TARGETS="npm-flake",
                UPDATE_TEST_NO_CHANGES="1",
                UPDATE_TEST_NPM_FLAKE_TARGET="1",
            )
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "npm-flake"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 3, result.stderr)
            self.assertIn("npm-flake: retained", result.stderr)
            self._assert_update_agents_unchanged(root, baseline, before)

        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            interleaving_log = Path(temp_dir) / "interleaving.log"
            environment.update(
                UPDATE_TEST_FIXED_TARGET="1",
                UPDATE_TEST_GITHUB_TARGET="1",
                UPDATE_TEST_INTERLEAVING_LOG=str(interleaving_log),
                UPDATE_TEST_NPM_FLAKE_TARGET="1",
                UPDATE_TEST_PYPI_TARGET="1",
            )
            result = subprocess.run(
                [
                    str(UPDATE_AGENTS),
                    "--dry-run",
                    "--target",
                    "pypi",
                    "--target",
                    "github",
                    "--target",
                    "npm-flake",
                    "--target",
                    "fixed",
                ],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            events = interleaving_log.read_text().splitlines()
            ordered = [
                "overlay --prepare-target pypi",
                "overlay --prepare-target github",
                "overlay --prepare-target npm-flake",
                "nix flake update --flake ./config/ai npm-flake-input",
                "overlay --sync-flake-projections npm-flake",
                "overlay --validate-candidate-target npm-flake",
                "overlay --prepare-target fixed",
                "nix flake update --flake ./config/ai fixed-input",
                "overlay --sync-flake-projections fixed",
            ]
            position = -1
            for event in ordered:
                position = events.index(event, position + 1)
            self.assertEqual(events.count("overlay --inventory --json"), 2)
            self.assertIn("authoritative tree unchanged", result.stdout)
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_routes_compound_pypi_without_lock_updates(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            command_log = Path(temp_dir) / "commands.log"
            environment["UPDATE_TEST_PYPI_TARGET"] = "1"
            environment["UPDATE_TEST_COMMAND_LOG"] = str(command_log)
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "pypi"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                baseline,
            )
            self.assertEqual((root / "pypi.txt").read_text(), "pypi after\n")
            self.assertEqual((root / "projection.json").read_text(), "{}\n")
            self.assertEqual(
                command_log.read_text().splitlines(),
                [
                    "flake check ./config/ai --all-systems --no-build --no-eval-cache",
                    "flake show --json --drv-paths --all-systems --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                    "flake check --no-build --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                ],
            )

        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment["UPDATE_TEST_PYPI_TARGET"] = "1"
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "pypi", "--dry-run"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("authoritative tree unchanged", result.stdout)
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_routes_npm_lock_projection_without_lock_updates(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            command_log = Path(temp_dir) / "commands.log"
            environment["UPDATE_TEST_NPM_LOCK_TARGET"] = "1"
            environment["UPDATE_TEST_COMMAND_LOG"] = str(command_log)
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "npm-lock"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                baseline,
            )
            self.assertEqual((root / "npm-lock.txt").read_text(), "npm lock after\n")
            self.assertEqual((root / "projection.json").read_text(), "{}\n")
            self.assertEqual(
                command_log.read_text().splitlines(),
                [
                    "flake check ./config/ai --all-systems --no-build --no-eval-cache",
                    "flake show --json --drv-paths --all-systems --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                    "flake check --no-build --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                ],
            )

        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment["UPDATE_TEST_NPM_LOCK_TARGET"] = "1"
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "npm-lock", "--dry-run"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("authoritative tree unchanged", result.stdout)
            self._assert_update_agents_unchanged(root, baseline, before)

        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment.update(
                UPDATE_TEST_NPM_LOCK_TARGET="1",
                UPDATE_TEST_MUTATE_OTHER_DECLARED="1",
            )
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "npm-lock"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("undeclared updater mutation", result.stderr)
            self._assert_update_agents_unchanged(root, baseline, before)

        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment.update(
                UPDATE_TEST_NPM_LOCK_TARGET="1",
                UPDATE_TEST_NPM_LOCK_SECOND_TARGET="1",
                UPDATE_TEST_NPM_LOCK_SECOND_FAIL="1",
            )
            result = subprocess.run(
                [
                    str(UPDATE_AGENTS),
                    "--target",
                    "npm-lock",
                    "--target",
                    "npm-lock-second",
                ],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_all_inputs_runs_automatic_targets_after_uncatalogued_locks(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, _baseline = self._create_update_agents_fixture(temp_dir)
            interleaving_log = Path(temp_dir) / "interleaving.log"
            environment.update(
                UPDATE_TEST_COPY_TARGET="1",
                UPDATE_TEST_INTERLEAVING_LOG=str(interleaving_log),
                UPDATE_TEST_NPM_LOCK_AUTOMATIC="1",
                UPDATE_TEST_NPM_LOCK_TARGET="1",
            )
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--all-inputs"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            events = interleaving_log.read_text().splitlines()
            root_lock = events.index("nix flake update nix-config-ai")
            portable_target = events.index(
                "nix flake update --flake ./config/ai copy-input"
            )
            direct_target = events.index("overlay fixture")
            npm_locks = events.index("overlay --prepare-target npm-lock")
            projection_syncs = [
                index
                for index, event in enumerate(events)
                if event.startswith("overlay --sync-flake-projections")
            ]
            inventory_checks = [
                index
                for index, event in enumerate(events)
                if event == "overlay --inventory --json"
            ]
            self.assertEqual(len(inventory_checks), 2)
            self.assertLess(root_lock, portable_target)
            self.assertEqual(
                [events[index] for index in projection_syncs],
                ["overlay --sync-flake-projections copy"],
            )
            self.assertLess(portable_target, projection_syncs[0])
            self.assertLess(projection_syncs[0], npm_locks)
            self.assertLess(npm_locks, direct_target)
            self.assertLess(direct_target, inventory_checks[-1])
            self.assertEqual((root / "npm-lock.txt").read_text(), "npm lock after\n")

    def test_all_inputs_separates_uncatalogued_and_named_catalog_inputs(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, _baseline = self._create_update_agents_fixture(
                temp_dir,
                portable_inputs=(
                    "portable-only",
                    "copy-input",
                    "build-input",
                    "fixed-input",
                ),
                root_inputs=("root-only", "nix-config-ai"),
            )
            interleaving_log = Path(temp_dir) / "interleaving.log"
            environment.update(
                UPDATE_TEST_BUILD_TARGET="1",
                UPDATE_TEST_COPY_TARGET="1",
                UPDATE_TEST_FIXED_TARGET="1",
                UPDATE_TEST_INTERLEAVING_LOG=str(interleaving_log),
            )

            result = subprocess.run(
                [str(UPDATE_AGENTS), "--all-inputs"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            events = interleaving_log.read_text().splitlines()
            self.assertEqual(
                events,
                [
                    "overlay --inventory --json",
                    "nix flake update --flake ./config/ai portable-only",
                    "nix flake update root-only",
                    "nix flake update nix-config-ai",
                    "overlay --prepare-target fixed",
                    "nix flake update --flake ./config/ai fixed-input",
                    "nix flake update nix-config-ai",
                    "overlay --sync-flake-projections fixed",
                    "overlay --prepare-target build",
                    "nix flake update --flake ./config/ai build-input",
                    "nix flake update nix-config-ai",
                    "overlay --sync-flake-projections build",
                    "overlay --validate-candidate-target build",
                    "overlay --prepare-target copy",
                    "nix flake update --flake ./config/ai copy-input",
                    "nix flake update nix-config-ai",
                    "overlay --sync-flake-projections copy",
                    "overlay --validate-candidate-target copy",
                    "overlay fixture",
                    "overlay --inventory --json",
                    "nix flake check ./config/ai --all-systems --no-build --no-eval-cache",
                    "nix flake show --json --drv-paths --all-systems --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                    "nix flake check --no-build --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                ],
            )
            self.assertNotIn("overlay --sync-flake-projections", events)
            self.assertEqual(
                json.loads((root / "projection.json").read_text()),
                {"fixed": True, "build": True, "copy": True},
            )

    def test_update_agents_routes_github_projection_without_lock_updates(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            command_log = Path(temp_dir) / "commands.log"
            environment["UPDATE_TEST_GITHUB_TARGET"] = "1"
            environment["UPDATE_TEST_COMMAND_LOG"] = str(command_log)
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "github"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                baseline,
            )
            self.assertEqual((root / "github.txt").read_text(), "github after\n")
            self.assertEqual((root / "projection.json").read_text(), "{}\n")
            self.assertEqual(
                command_log.read_text().splitlines(),
                [
                    "flake check ./config/ai --all-systems --no-build --no-eval-cache",
                    "flake show --json --drv-paths --all-systems --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                    "flake check --no-build --option eval-cores 1 --option lazy-trees false --option eval-cache false",
                ],
            )

        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment["UPDATE_TEST_GITHUB_TARGET"] = "1"
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "github", "--dry-run"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("authoritative tree unchanged", result.stdout)
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_rejects_undeclared_candidate_mutation(self):
        for environment_name in (
            "UPDATE_TEST_MUTATE_UNDECLARED",
            "UPDATE_TEST_MUTATE_IGNORED",
            "UPDATE_TEST_RENAME_UNDECLARED",
        ):
            with (
                self.subTest(environment_name=environment_name),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                root, environment, baseline = self._create_update_agents_fixture(
                    temp_dir
                )
                before = self._update_agents_projection(root)
                environment[environment_name] = "1"
                result = subprocess.run(
                    [str(UPDATE_AGENTS)],
                    capture_output=True,
                    text=True,
                    env=environment,
                    check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("undeclared updater mutation", result.stderr)
                self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_sigterm_rolls_back_every_publication_phase(self):
        for phase in ("after-apply", "after-normalize", "after-read-tree"):
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as temp_dir:
                root, environment, baseline = self._create_update_agents_fixture(
                    temp_dir
                )
                before = self._update_agents_projection(root)
                marker = Path(temp_dir) / "signal-delivered"
                environment.update(
                    {
                        "UPDATE_TEST_SIGNAL_PHASE": phase,
                        "UPDATE_TEST_SIGNAL_MARKER": str(marker),
                    }
                )
                result = subprocess.run(
                    [str(UPDATE_AGENTS)],
                    capture_output=True,
                    text=True,
                    env=environment,
                    check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(marker.is_file())
                self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_partial_apply_failure_restores_baseline(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            marker = Path(temp_dir) / "partial-apply-injected"
            environment.update(
                {
                    "UPDATE_TEST_SIGNAL_PHASE": "partial-apply-failure",
                    "UPDATE_TEST_SIGNAL_MARKER": str(marker),
                }
            )
            result = subprocess.run(
                [str(UPDATE_AGENTS)],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(marker.is_file())
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_restore_fallback_recovers_baseline(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            signal_marker = Path(temp_dir) / "signal-delivered"
            restore_marker = Path(temp_dir) / "restore-failure-injected"
            environment.update(
                {
                    "UPDATE_TEST_SIGNAL_PHASE": "after-apply",
                    "UPDATE_TEST_SIGNAL_MARKER": str(signal_marker),
                    "UPDATE_TEST_FAIL_RESTORE": "1",
                    "UPDATE_TEST_RESTORE_FAILURE_MARKER": str(restore_marker),
                }
            )
            result = subprocess.run(
                [str(UPDATE_AGENTS)],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(signal_marker.is_file())
            self.assertTrue(restore_marker.is_file())
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_rolls_back_interrupted_commit_publication(self):
        for phase in ("merge-failure", "merge-partial-failure", "merge-sigterm"):
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as temp_dir:
                root, environment, baseline = self._create_update_agents_fixture(
                    temp_dir
                )
                before = self._update_agents_projection(root)
                marker = Path(temp_dir) / "merge-interrupted"
                environment.update(
                    {
                        "UPDATE_TEST_SIGNAL_PHASE": phase,
                        "UPDATE_TEST_SIGNAL_MARKER": str(marker),
                    }
                )
                result = subprocess.run(
                    [str(UPDATE_AGENTS), "--commit"],
                    capture_output=True,
                    text=True,
                    env=environment,
                    check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(marker.is_file())
                self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_successful_commit_preserves_filesystem_identities(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--commit"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            head = subprocess.run(
                ["git", "-C", str(root), "rev-parse", "HEAD"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip()
            self.assertNotEqual(head, baseline)
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "status", "--porcelain"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout,
                "",
            )
            projection = self._update_agents_projection(root)
            self.assertEqual(projection["tracked.txt"], ("file", 0o640, b"after\n"))
            self.assertEqual(projection["mode.sh"][1], 0o755)
            self.assertEqual(projection["link"], ("symlink", "target-new"))
            self.assertNotIn("deleted.txt", projection)
            self.assertFalse((root / ".git/update-agents.lock").exists())
            self.assertEqual(list(root.parent.glob("update.*")), [])

    def test_update_agents_rejects_post_merge_untracked_mutation(self):
        for phase, path_name in (
            ("merge-untracked", "post-merge.tmp"),
            ("merge-ignored", "ignored.tmp"),
        ):
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as temp_dir:
                root, environment, baseline = self._create_update_agents_fixture(
                    temp_dir
                )
                before = self._update_agents_projection(root)
                environment["UPDATE_TEST_SIGNAL_PHASE"] = phase
                result = subprocess.run(
                    [str(UPDATE_AGENTS), "--commit"],
                    capture_output=True,
                    text=True,
                    env=environment,
                    check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    "published commit differs from validated candidate", result.stderr
                )
                self.assertEqual((root / path_name).read_text(), "post merge\n")
                after = self._update_agents_projection(root)
                external = after.pop(path_name)
                self.assertEqual(external[0], "file")
                self.assertEqual(after, before)
                self.assertEqual(
                    subprocess.run(
                        ["git", "-C", str(root), "rev-parse", "HEAD"],
                        capture_output=True,
                        text=True,
                        check=True,
                    ).stdout.strip(),
                    baseline,
                )
                self.assertFalse((root / ".git/update-agents.lock").exists())

    def test_update_agents_revalidates_after_commit_verification(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment["UPDATE_TEST_MUTATE_LIVE_DURING_VERIFY"] = "1"
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--commit"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("live repository changed before publication", result.stderr)
            self.assertEqual(
                (root / "verify-external.txt").read_text(), "verify edit\n"
            )
            after = self._update_agents_projection(root)
            external = after.pop("verify-external.txt")
            self.assertEqual(external[0], "file")
            self.assertEqual(after, before)
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                baseline,
            )
            self.assertFalse((root / ".git/update-agents.lock").exists())

    def test_update_agents_rejects_commit_hook_tree_mutation(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment["UPDATE_TEST_HOOK_INJECT"] = "1"
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--commit"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                "signed commit did not capture the complete transaction", result.stderr
            )
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_quiet_reports_outer_failure_before_cleanup_finishes(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            marker = Path(temp_dir) / "cleanup-started"
            release = Path(temp_dir) / "cleanup-release"
            environment.update(
                UPDATE_TEST_HOOK_INJECT="1",
                UPDATE_TEST_SIGNAL_PHASE="worktree-remove-failure",
                UPDATE_TEST_SIGNAL_MARKER=str(marker),
                UPDATE_TEST_BLOCK_CLEANUP_RELEASE=str(release),
            )
            process = subprocess.Popen(
                [str(UPDATE_AGENTS), "--quiet", "--commit"],
                cwd=root,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            diagnostic = b"signed commit did not capture the complete transaction"
            stderr_head = b""
            try:
                deadline = time.monotonic() + 30
                while (
                    not marker.exists()
                    and process.poll() is None
                    and time.monotonic() < deadline
                ):
                    time.sleep(0.01)
                self.assertTrue(marker.exists(), "cleanup never reached worktree removal")
                while diagnostic not in stderr_head and time.monotonic() < deadline:
                    ready, _, _ = select.select([process.stderr], [], [], 0.1)
                    if ready:
                        chunk = os.read(process.stderr.fileno(), 4096)
                        if not chunk:
                            break
                        stderr_head += chunk
                self.assertIn(diagnostic, stderr_head)
                self.assertIsNone(process.poll())
            finally:
                release.touch()
                stdout, stderr_tail = process.communicate(timeout=30)
            self.assertEqual(process.returncode, 1, stderr_head + stderr_tail)
            self.assertTrue(stdout.endswith(b"\n"), stdout)
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_sigterm_during_lock_acquisition_releases_lock(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            marker = Path(temp_dir) / "lock-created"
            environment.update(
                {
                    "UPDATE_TEST_SIGNAL_PHASE": "lock-acquisition",
                    "UPDATE_TEST_SIGNAL_MARKER": str(marker),
                }
            )
            result = subprocess.run(
                [str(UPDATE_AGENTS)],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(marker.is_file())
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_prunes_failed_candidate_removal(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, _baseline = self._create_update_agents_fixture(temp_dir)
            real_git = environment["REAL_GIT"]
            unrelated = Path(temp_dir) / "unrelated-worktree"
            subprocess.run(
                [
                    real_git,
                    "-C",
                    str(root),
                    "worktree",
                    "add",
                    "--detach",
                    str(unrelated),
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            unrelated_git_dir = Path(
                subprocess.run(
                    [
                        real_git,
                        "-C",
                        str(unrelated),
                        "rev-parse",
                        "--path-format=absolute",
                        "--git-dir",
                    ],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip()
            )
            shutil.rmtree(unrelated)
            self.assertTrue(unrelated_git_dir.is_dir())
            marker = Path(temp_dir) / "remove-failure-injected"
            environment.update(
                {
                    "UPDATE_TEST_SIGNAL_PHASE": "worktree-remove-failure",
                    "UPDATE_TEST_SIGNAL_MARKER": str(marker),
                }
            )
            result = subprocess.run(
                [str(UPDATE_AGENTS)],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(marker.is_file())
            worktrees = subprocess.run(
                ["git", "-C", str(root), "worktree", "list", "--porcelain"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout
            self.assertEqual(worktrees.count("worktree "), 2)
            self.assertTrue(unrelated_git_dir.is_dir())
            self.assertNotIn("/candidate\n", worktrees)
            self.assertFalse((root / ".git/update-agents.lock").exists())
            self.assertEqual(list(root.parent.glob("update.*")), [])

    def test_update_agents_fails_closed_when_worktree_verification_fails(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, _baseline = self._create_update_agents_fixture(temp_dir)
            environment["UPDATE_TEST_SIGNAL_PHASE"] = "worktree-list-failure"
            result = subprocess.run(
                [str(UPDATE_AGENTS)],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("failed to verify candidate worktree removal", result.stderr)
            self.assertFalse((root / ".git/update-agents.lock").exists())
            self.assertEqual(list(root.parent.glob("update.*")), [])

    def test_update_agents_sigterm_discards_every_candidate_phase(self):
        for phase in (
            "candidate-portable-lock",
            "candidate-root-lock",
            "candidate-projection",
            "candidate-update",
            "candidate-format",
            "candidate-portable-validation",
            "candidate-root-instantiation",
            "candidate-root-validation",
        ):
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as temp_dir:
                root, environment, baseline = self._create_update_agents_fixture(
                    temp_dir
                )
                before = self._update_agents_projection(root)
                marker = Path(temp_dir) / "signal-delivered"
                environment.update(
                    {
                        "UPDATE_TEST_SIGNAL_PHASE": phase,
                        "UPDATE_TEST_SIGNAL_MARKER": str(marker),
                    }
                )
                if phase in {
                    "candidate-portable-lock",
                    "candidate-root-lock",
                    "candidate-projection",
                }:
                    environment["UPDATE_TEST_COPY_TARGET"] = "1"
                result = subprocess.run(
                    [str(UPDATE_AGENTS)],
                    capture_output=True,
                    text=True,
                    env=environment,
                    check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(marker.is_file())
                self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_failure_discards_every_candidate_phase(self):
        for phase in (
            "candidate-portable-lock",
            "candidate-root-lock",
            "candidate-projection",
            "candidate-update",
            "candidate-format",
            "candidate-portable-validation",
            "candidate-root-instantiation",
            "candidate-root-validation",
        ):
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as temp_dir:
                root, environment, baseline = self._create_update_agents_fixture(
                    temp_dir
                )
                before = self._update_agents_projection(root)
                environment["UPDATE_TEST_FAILURE_PHASE"] = phase
                if phase in {
                    "candidate-portable-lock",
                    "candidate-root-lock",
                    "candidate-projection",
                }:
                    environment["UPDATE_TEST_COPY_TARGET"] = "1"
                result = subprocess.run(
                    [str(UPDATE_AGENTS)],
                    capture_output=True,
                    text=True,
                    env=environment,
                    check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_refuses_concurrent_live_edit_before_publication(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            environment["UPDATE_TEST_MUTATE_LIVE"] = "1"
            result = subprocess.run(
                [str(UPDATE_AGENTS)],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("live repository changed before publication", result.stderr)
            self.assertEqual(
                (root / "external.txt").read_text(), "external\nexternal\n"
            )
            after = self._update_agents_projection(root)
            external = after.pop("external.txt")
            self.assertEqual(external[0], "file")
            self.assertEqual(external[2], b"external\nexternal\n")
            self.assertEqual(after, before)
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                baseline,
            )
            worktrees = subprocess.run(
                ["git", "-C", str(root), "worktree", "list", "--porcelain"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout
            self.assertEqual(worktrees.count("worktree "), 1)
            self.assertFalse((root / ".git/update-agents.lock").exists())

    def test_update_agents_discards_failed_candidate_transaction(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "repo"
            fake_bin = Path(temp_dir) / "bin"
            (root / "bin").mkdir(parents=True)
            (root / "config/ai").mkdir(parents=True)
            (root / "overlays/ai").mkdir(parents=True)
            fake_bin.mkdir()
            (root / "bin/update-overlay").write_text(SCRIPT.read_text())
            (root / "bin/update-overlay").chmod(0o700)
            empty_lock = json.dumps(
                {"nodes": {"root": {"inputs": {}}}, "root": "root", "version": 7}
            )
            (root / "flake.lock").write_text(empty_lock + "\n")
            (root / "config/ai/flake.lock").write_text(empty_lock + "\n")
            (root / "overlays/ai/package.nix").write_text("baseline\n")
            write_minimal_catalog(root)

            def executable(name, text):
                path = fake_bin / name
                path.write_text(text)
                path.chmod(0o700)

            executable(
                "nix",
                """#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == eval ]]; then
  printf '{"schemaVersion":1,"targets":{}}\n'
elif [[ $1 == flake && $2 == update ]]; then
  :
elif [[ $1 == flake && $2 == check ]]; then
  exit 23
fi
""",
            )
            executable(
                "python3",
                """#!/usr/bin/env bash
set -euo pipefail
if [[ ${2:-} == --inventory || ${2:-} == --sync-flake-projections ]]; then
  exec "$REAL_PYTHON3" "$@"
fi
"$REAL_PYTHON3" -c 'from pathlib import Path; p = Path("sources/test.json"); p.write_text(p.read_text().replace("1.0.0", "1.0.1"))'
""",
            )
            executable("nixfmt", "#!/usr/bin/env bash\nexit 0\n")

            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(["git", "-C", str(root), "add", "."], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(root),
                    "-c",
                    "user.name=Test",
                    "-c",
                    "user.email=test@example.invalid",
                    "-c",
                    "commit.gpgsign=false",
                    "commit",
                    "-qm",
                    "baseline",
                ],
                check=True,
            )
            baseline = subprocess.run(
                ["git", "-C", str(root), "rev-parse", "HEAD"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip()
            env = {
                **os.environ,
                "NIX_CONFIG_DIR": str(root),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "REAL_PYTHON3": sys.executable,
            }
            result = subprocess.run(
                [str(UPDATE_AGENTS)],
                capture_output=True,
                text=True,
                env=env,
                check=False,
            )
            self.assertEqual(result.returncode, 23, result.stderr)
            status = subprocess.run(
                ["git", "-C", str(root), "status", "--porcelain"],
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertEqual(status.stdout, "")
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                baseline,
            )
            worktrees = subprocess.run(
                ["git", "-C", str(root), "worktree", "list", "--porcelain"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout
            self.assertEqual(worktrees.count("worktree "), 1)
            self.assertFalse((root / ".git/update-agents.lock").exists())

    def test_update_agents_never_pushes_after_failed_signed_commit(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "repo"
            fake_bin = Path(temp_dir) / "bin"
            push_marker = Path(temp_dir) / "push-called"
            (root / "bin").mkdir(parents=True)
            (root / "config/ai").mkdir(parents=True)
            (root / "overlays/ai").mkdir(parents=True)
            fake_bin.mkdir()
            (root / "bin/update-overlay").write_text(SCRIPT.read_text())
            (root / "bin/update-overlay").chmod(0o700)
            empty_lock = json.dumps(
                {"nodes": {"root": {"inputs": {}}}, "root": "root", "version": 7}
            )
            (root / "flake.lock").write_text(empty_lock + "\n")
            (root / "config/ai/flake.lock").write_text(empty_lock + "\n")
            (root / "overlays/ai/package.nix").write_text("baseline\n")
            write_minimal_catalog(root)

            real_git = shutil.which("git") or "/usr/bin/git"

            def executable(name, text):
                path = fake_bin / name
                path.write_text(text)
                path.chmod(0o700)

            executable(
                "nix",
                """#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == eval ]]; then
  printf '{"schemaVersion":1,"targets":{}}\n'
elif [[ $1 == flake && $2 == update ]]; then
  :
elif [[ $1 == flake && $2 == check ]]; then
  exit 0
fi
""",
            )
            executable(
                "python3",
                """#!/usr/bin/env bash
set -euo pipefail
if [[ ${2:-} == --inventory || ${2:-} == --sync-flake-projections ]]; then
  exec "$REAL_PYTHON3" "$@"
fi
"$REAL_PYTHON3" -c 'from pathlib import Path; p = Path("sources/test.json"); p.write_text(p.read_text().replace("1.0.0", "1.0.1"))'
""",
            )
            executable("nixfmt", "#!/usr/bin/env bash\nexit 0\n")
            executable(
                "git",
                """#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  if [[ $arg == commit ]]; then exit 42; fi
  if [[ $arg == push ]]; then : > "$PUSH_MARKER"; exit 0; fi
done
exec "$REAL_GIT" "$@"
""",
            )

            subprocess.run([real_git, "init", "-q", str(root)], check=True)
            subprocess.run([real_git, "-C", str(root), "add", "."], check=True)
            subprocess.run(
                [
                    real_git,
                    "-C",
                    str(root),
                    "-c",
                    "user.name=Test",
                    "-c",
                    "user.email=test@example.invalid",
                    "-c",
                    "commit.gpgsign=false",
                    "commit",
                    "-qm",
                    "baseline",
                ],
                check=True,
            )
            baseline = subprocess.run(
                [real_git, "-C", str(root), "rev-parse", "HEAD"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip()
            env = {
                **os.environ,
                "NIX_CONFIG_DIR": str(root),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "PUSH_MARKER": str(push_marker),
                "REAL_GIT": real_git,
                "REAL_PYTHON3": sys.executable,
            }
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--commit", "--push"],
                capture_output=True,
                text=True,
                env=env,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                "signed commit failed",
                result.stderr,
                f"status={result.returncode}\nstdout={result.stdout}",
            )
            self.assertFalse(push_marker.exists())
            self.assertEqual(
                subprocess.run(
                    [real_git, "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                baseline,
            )
            self.assertEqual(
                subprocess.run(
                    [real_git, "-C", str(root), "status", "--porcelain"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout,
                "",
            )

    def test_update_nixos_build_driver_contract_and_failures(self):
        cases = (
            ("success", "executable", None, ["build", "switch", "publish", "push"], 2),
            ("build-fails", "executable", "candidate-build", ["build"], 1),
            (
                "switch-fails",
                "executable",
                "candidate-switch",
                ["build", "switch"],
                2,
            ),
            ("missing", "missing", None, [], 0),
            ("nonexecutable", "nonexecutable", None, [], 0),
        )
        for (
            name,
            driver_mode,
            failure_phase,
            expected_external,
            expected_count,
        ) in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp_dir:
                root, environment, baseline = self._create_update_agents_fixture(
                    temp_dir, nixos_driver=driver_mode
                )
                before = self._update_agents_projection(root)
                external_log = Path(temp_dir) / "external.log"
                driver_log = Path(temp_dir) / "driver.log"
                push_marker = Path(temp_dir) / "push-called"
                environment.update(
                    {
                        "UPDATE_TEST_DRIVER_LOG": str(driver_log),
                        "UPDATE_TEST_EXTERNAL_LOG": str(external_log),
                        "UPDATE_TEST_PUSH_MARKER": str(push_marker),
                    }
                )
                if failure_phase is not None:
                    environment["UPDATE_TEST_FAILURE_PHASE"] = failure_phase

                result = subprocess.run(
                    [str(UPDATE_AGENTS), "--commit", "--switch", "--push"],
                    capture_output=True,
                    text=True,
                    env=environment,
                    check=False,
                )

                observed_external = (
                    external_log.read_text().splitlines()
                    if external_log.exists()
                    else []
                )
                self.assertEqual(observed_external, expected_external)
                invocations = (
                    [line.split("\t") for line in driver_log.read_text().splitlines()]
                    if driver_log.exists()
                    else []
                )
                self.assertEqual(len(invocations), expected_count)
                if invocations:
                    self.assertEqual(
                        invocations[0][:9],
                        [
                            str(root),
                            "--",
                            "nix",
                            "build",
                            "--max-jobs",
                            "1",
                            "--cores",
                            "1",
                            "--no-link",
                        ],
                    )
                    candidate, attribute = invocations[0][9].split("#", 1)
                    self.assertEqual(
                        attribute,
                        "nixosConfigurations.ovh-vps.config.system.build.toplevel",
                    )
                    if len(invocations) == 2:
                        self.assertEqual(
                            invocations[1],
                            [
                                str(root),
                                "--",
                                "nixos-rebuild",
                                "switch",
                                "--max-jobs",
                                "1",
                                "--cores",
                                "1",
                                "--flake",
                                f"{candidate}#ovh-vps",
                            ],
                        )
                if name == "success":
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertTrue(push_marker.is_file())
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(push_marker.exists())
                    self._assert_update_agents_unchanged(root, baseline, before)
                if driver_mode != "executable":
                    self.assertIn(
                        "NixOS build driver is missing or not executable", result.stderr
                    )

    def test_update_build_failure_never_switches_publishes_or_pushes(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            external_log = Path(temp_dir) / "external.log"
            push_marker = Path(temp_dir) / "push-called"
            environment.update(
                {
                    "UPDATE_TEST_EXTERNAL_LOG": str(external_log),
                    "UPDATE_TEST_FAILURE_PHASE": "candidate-build",
                    "UPDATE_TEST_PUSH_MARKER": str(push_marker),
                }
            )

            result = subprocess.run(
                [str(UPDATE_AGENTS), "--commit", "--switch", "--push"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(external_log.read_text().splitlines(), ["build"])
            self.assertFalse(push_marker.exists())
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_switch_failure_never_publishes_or_pushes(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            external_log = Path(temp_dir) / "external.log"
            push_marker = Path(temp_dir) / "push-called"
            environment.update(
                {
                    "UPDATE_TEST_EXTERNAL_LOG": str(external_log),
                    "UPDATE_TEST_FAILURE_PHASE": "candidate-switch",
                    "UPDATE_TEST_PUSH_MARKER": str(push_marker),
                }
            )

            result = subprocess.run(
                [str(UPDATE_AGENTS), "--commit", "--switch", "--push"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(external_log.read_text().splitlines(), ["build", "switch"])
            self.assertFalse(push_marker.exists())
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_success_orders_build_switch_publication_and_push(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            external_log = Path(temp_dir) / "external.log"
            command_log = Path(temp_dir) / "commands.log"
            push_marker = Path(temp_dir) / "push-called"
            sudo_log = Path(temp_dir) / "sudo.log"
            environment.update(
                {
                    "UPDATE_TEST_COMMAND_LOG": str(command_log),
                    "UPDATE_TEST_EXTERNAL_LOG": str(external_log),
                    "UPDATE_TEST_PUSH_MARKER": str(push_marker),
                    "UPDATE_TEST_SUDO_LOG": str(sudo_log),
                }
            )

            result = subprocess.run(
                [str(UPDATE_AGENTS), "--commit", "--switch", "--push"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                external_log.read_text().splitlines(),
                ["build", "switch", "publish", "push"],
            )
            darwin_builds = [
                command
                for command in command_log.read_text().splitlines()
                if "#darwinConfigurations.hera.system" in command
            ]
            self.assertEqual(len(darwin_builds), 1)
            self.assertTrue(
                darwin_builds[0].startswith("build --no-link --print-out-paths ")
            )
            system_config = environment["UPDATE_TEST_SYSTEM_CONFIG"]
            self.assertEqual(
                sudo_log.read_text().splitlines(),
                [
                    f"nix-env -p /nix/var/nix/profiles/system --set {system_config}",
                    f"{system_config}/sw/bin/darwin-rebuild activate",
                ],
            )
            self.assertTrue(push_marker.exists())
            self.assertNotEqual(
                subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                baseline,
            )
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "status", "--porcelain"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout,
                "",
            )

    def test_update_no_change_is_idempotent_and_skips_publication(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            before = self._update_agents_projection(root)
            external_log = Path(temp_dir) / "external.log"
            push_marker = Path(temp_dir) / "push-called"
            environment.update(
                {
                    "UPDATE_TEST_EXTERNAL_LOG": str(external_log),
                    "UPDATE_TEST_NO_CHANGES": "1",
                    "UPDATE_TEST_PUSH_MARKER": str(push_marker),
                }
            )

            result = subprocess.run(
                [str(UPDATE_AGENTS), "--commit", "--switch", "--push"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("no changes", result.stdout)
            self.assertEqual(external_log.read_text().splitlines(), ["build", "switch"])
            self.assertFalse(push_marker.exists())
            self._assert_update_agents_unchanged(root, baseline, before)

    def test_update_agents_rejects_concurrent_transaction(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "repo"
            root.mkdir()
            (root / "tracked").write_text("baseline\n")
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(["git", "-C", str(root), "add", "tracked"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(root),
                    "-c",
                    "user.name=Test",
                    "-c",
                    "user.email=test@example.invalid",
                    "-c",
                    "commit.gpgsign=false",
                    "commit",
                    "-qm",
                    "baseline",
                ],
                check=True,
            )
            (root / ".git/update-agents.lock").mkdir()
            result = subprocess.run(
                [str(UPDATE_AGENTS)],
                capture_output=True,
                text=True,
                env={**os.environ, "NIX_CONFIG_DIR": str(root)},
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("another update transaction is active", result.stderr)
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "status", "--porcelain"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout,
                "",
            )

    def test_root_inputs_do_not_reference_external_filesystems(self):
        root = SCRIPT.parent.parent
        lock = json.loads((root / "flake.lock").read_text())
        for name, node_ref in lock["nodes"]["root"]["inputs"].items():
            node_name = node_ref if isinstance(node_ref, str) else node_ref[0]
            locked = lock["nodes"][node_name]["locked"]
            locator = locked.get("url", locked.get("path", ""))
            with self.subTest(input=name):
                self.assertNotIn("file:///", locator)
                self.assertFalse(locator.startswith("/"), locator)

    # ---- whole-closure lock purity -------------------------------------
    #
    # The check above inspects only the root flake's DIRECT inputs, which is
    # precisely why a real leak went unnoticed: `obr` committed its own
    # flake.lock pinning org2jsonl at `git+file:///Users/johnw/src/org2jsonl`,
    # Nix folded that transitive lock into this repo's closure, and the
    # root-inputs-only walk never reached depth 2. An external consumer could
    # not fetch this lock, and nothing said so.
    #
    # These helpers walk the entire closure. They are kept separate from the
    # check above rather than replacing it: that one also asserts things about
    # flake.nix text and about direct inputs specifically, and narrowing it
    # would trade one blind spot for another.

    @staticmethod
    def _closure_routes(lock):
        """Every node reachable from root, mapped to the shortest route to it.

        A lock's `inputs` values are either a node name or a list describing a
        `follows` path; both forms are followed, or a `follows` edge would hide
        whatever it points at.
        """
        nodes = lock["nodes"]

        def resolve(reference, depth=0):
            """Resolve an `inputs` value to a node name.

            A list-valued reference is a `follows` path anchored at ROOT, not at
            the node that declares it — e.g. `["nix-config-ai", "nixpkgs"]` means
            root's nix-config-ai input, then its nixpkgs. Resolving it relative to
            the declaring node instead recurses forever on a real lock, because
            follows chains readily point back through nodes already being walked.
            """
            if isinstance(reference, str):
                return reference
            if depth > 64:
                return None  # pathological lock; refuse to hang
            current = "root"
            for step in reference:
                nxt = (nodes.get(current, {}).get("inputs") or {}).get(step)
                if nxt is None:
                    return None
                current = nxt if isinstance(nxt, str) else resolve(nxt, depth + 1)
                if current is None:
                    return None
            return current

        routes = {"root": ("root",)}
        queue = [("root", ("root",))]
        while queue:
            name, route = queue.pop(0)
            for input_name, reference in (
                nodes.get(name, {}).get("inputs") or {}
            ).items():
                target = resolve(reference)
                if target is None or target in routes:
                    continue
                routes[target] = route + (input_name,)
                queue.append((target, route + (input_name,)))
        return routes

    @classmethod
    def _closure_impurities(cls, lock):
        """Closure nodes an external consumer could not fetch.

        Returns {node_name: (route, locator)}. A locator is unfetchable when it
        names this machine's filesystem: a file:// URL, a `path` node with an
        absolute path, or a bare absolute path.
        """
        nodes = lock["nodes"]
        offenders = {}
        for name, route in cls._closure_routes(lock).items():
            if name == "root":
                continue
            locked = nodes.get(name, {}).get("locked") or {}
            locator = locked.get("url") or locked.get("path") or ""
            unfetchable = (
                "file://" in locator
                or locator.startswith("/")
                or (locked.get("type") == "path" and locator.startswith("/"))
            )
            if unfetchable:
                offenders[name] = ("/".join(route[1:]) or "root", locator)
        return offenders

    # Nodes knowingly tolerated as unfetchable. Every entry needs a reason and an
    # owning issue. The assertion below is an EXACT-SET comparison, so a stale
    # entry fails just as loudly as a new leak — an allowlist that silently
    # outlives its cause is how the original blind spot survived.
    KNOWN_UNFETCHABLE_ROOT_NODES: dict[str, str] = {}

    def test_root_lock_closure_has_no_unfetchable_locators(self):
        """Named for what it proves: no locator points at this filesystem.

        It does NOT attempt a fetch, so it cannot prove the closure is
        retrievable — only that nothing in it is local-only. Overstating that
        would be the false-evidence pattern removed under #48.
        """
        root = SCRIPT.parent.parent
        lock = json.loads((root / "flake.lock").read_text())
        offenders = self._closure_impurities(lock)
        self.assertEqual(
            set(offenders),
            set(self.KNOWN_UNFETCHABLE_ROOT_NODES),
            "root lock closure impurities changed; routes: %s"
            % {k: v[0] for k, v in sorted(offenders.items())},
        )

    def test_portable_lock_closure_has_no_unfetchable_locators(self):
        root = SCRIPT.parent.parent
        lock = json.loads((root / "config/ai/flake.lock").read_text())
        offenders = self._closure_impurities(lock)
        self.assertEqual(
            offenders,
            {},
            "portable lock closure must stay fetchable; external consumers "
            "depend on it directly",
        )

    def test_closure_walk_descends_past_direct_inputs(self):
        """The negative test, and the reason the deepened walk exists.

        A synthetic lock places a file:// leak at depth 2 — reachable only
        through an intermediate node, exactly like the real obr -> org2jsonl
        case. The old root-inputs-only walk cannot see it, so this fails if the
        walk is ever narrowed back.
        """
        synthetic = {
            "nodes": {
                "root": {"inputs": {"intermediate": "intermediate"}},
                "intermediate": {
                    "inputs": {"leaky": "leaky"},
                    "locked": {"type": "github", "url": "https://example.invalid/ok"},
                },
                "leaky": {
                    "locked": {"type": "git", "url": "file:///Users/someone/local"},
                },
            },
            "root": "root",
            "version": 7,
        }
        offenders = self._closure_impurities(synthetic)
        self.assertIn("leaky", offenders, "depth-2 leak not detected")
        self.assertEqual(offenders["leaky"][0], "intermediate/leaky")
        self.assertNotIn("intermediate", offenders)

        # Prove the same lock is invisible to a root-inputs-only walk, so this
        # test genuinely discriminates rather than passing either way.
        shallow = {}
        for name, ref in synthetic["nodes"]["root"]["inputs"].items():
            node = synthetic["nodes"][ref if isinstance(ref, str) else ref[0]]
            locator = node.get("locked", {}).get("url", "")
            if "file://" in locator:
                shallow[name] = locator
        self.assertEqual(shallow, {}, "the shallow walk should miss a depth-2 leak")

    def test_closure_walk_follows_follows_edges(self):
        """A `follows` edge must not hide what it resolves to.

        This is what #24's fix relies on: obr's org2jsonl was redirected via
        `follows`, and if the walk ignored follows edges it would report a clean
        closure without having looked.
        """
        synthetic = {
            "nodes": {
                "root": {"inputs": {"a": "a", "shared": "shared"}},
                "a": {
                    # Root-anchored follows path, as Nix writes them.
                    "inputs": {"dep": ["shared"]},
                    "locked": {"type": "github", "url": "https://example.invalid/a"},
                },
                "shared": {"locked": {"type": "git", "url": "file:///local/shared"}},
            },
            "root": "root",
            "version": 7,
        }
        routes = self._closure_routes(synthetic)
        self.assertIn("shared", routes)
        offenders = self._closure_impurities(synthetic)
        self.assertIn("shared", offenders)

    # ---- heuristic production source-coordinate gate --------------------
    #
    # Scan common inline fetcher forms that bypass the source catalog. This is a
    # lexical guard, not a complete Nix parser; the exact-set allowlist makes
    # both newly detected and stale exceptions visible.

    # Production seams: flake.nix plus every .nix under these roots. `test`/
    # `tests` path components are excluded because fixtures are not production;
    # doc/ and the top-level test/ tree are simply not roots. sources/*.json is
    # catalog DATA, not a seam.
    _SEAM_ROOTS = ("overlays", "packages", "config", "flake")

    # Fetchers recognized when directly applied to an inline attrset. Dependency
    # hashes, bare filesystem src values, flake inputs, and standalone URL strings
    # are outside this lexical scanner.
    _FETCHERS = (
        "fetchFromGitHub",
        "fetchFromGitLab",
        "fetchFromGitiles",
        "fetchgit",
        "fetchurl",
        "fetchzip",
        "fetchpatch",
        "fetchPypi",
        "fetchTree",
        "fetchTarball",
        "fetchCrate",
        "fetchsvn",
        "fetchhg",
        "fetchGit",
    )
    _FETCH_TOKEN = re.compile(
        r"(?<![\w\"'])(?:[A-Za-z_][\w'-]*\.)?(" + "|".join(_FETCHERS) + r")\b"
    )
    # Coordinate-like fields used by the lexical inline-fetcher heuristic.
    _COORD_FIELD = re.compile(
        r"\b(owner|repo|url|urls|rev|tag|hash|sha256|sha512|pname|domain)\s*=\s*"
        r'(?:"([^"]*)"|\[\s*"([^"]*)")'
    )

    # Known inline source-coordinate literals, tolerated transitionally. EXACT
    # SET: a removed entry (e.g. once migrated to sources/*.json) fails just as
    # loudly as a new inline literal. The key embeds the coordinate, so a version
    # bump to the tolerated source re-surfaces it for re-review -- the intended
    # pressure toward catalog ownership. Every entry names its owning issue.
    KNOWN_INLINE_SOURCE_LITERALS: dict[str, str] = {}

    @staticmethod
    def _mask_nix(text):
        """Blank comment and string bytes, preserving length and newlines.

        Structural scans run on the mask so ordinary fetcher names or braces in
        comments and strings are ignored. Line comments (#..), block
        comments (/* */), double-quoted ("..") and Nix indented ('' .. '')
        strings are handled. Antiquotation (${..}) inside a string is blanked
        rather than re-entered as code, so that form is outside this heuristic.
        """
        out = list(text)
        i, n = 0, len(text)
        while i < n:
            c = text[i]
            two = text[i : i + 2]
            if c == "#":
                while i < n and text[i] != "\n":
                    out[i] = " "
                    i += 1
                continue
            if two == "/*":
                while i < n and text[i : i + 2] != "*/":
                    if text[i] != "\n":
                        out[i] = " "
                    i += 1
                for _ in range(min(2, n - i)):
                    out[i] = " "
                    i += 1
                continue
            if two == "''":
                out[i] = out[i + 1] = " "
                i += 2
                while i < n:
                    if text[i : i + 2] == "''":
                        out[i] = out[i + 1] = " "
                        i += 2
                        break
                    if text[i] != "\n":
                        out[i] = " "
                    i += 1
                continue
            if c == '"':
                out[i] = " "
                i += 1
                while i < n and text[i] != '"':
                    if text[i] == "\\" and i + 1 < n:
                        out[i] = out[i + 1] = " "
                        i += 2
                        continue
                    if text[i] != "\n":
                        out[i] = " "
                    i += 1
                if i < n:
                    out[i] = " "
                    i += 1
                continue
            i += 1
        return "".join(out)

    @staticmethod
    def _match_brace(mask, open_idx):
        """Index after the matching brace, or len(mask) if it is unclosed."""
        depth = 0
        for j in range(open_idx, len(mask)):
            if mask[j] == "{":
                depth += 1
            elif mask[j] == "}":
                depth -= 1
                if depth == 0:
                    return j + 1
        return len(mask)

    @classmethod
    def _inline_fetcher_offenders(cls, text):
        """Inline fetcher-literal coordinates in one seam's text.

        Returns lexical [(line, fetcher, locator)] candidates for a fetcher
        applied directly to an inline `{ .. }` with a coordinate-like field.
        A fetcher applied to an expression (`prev.fetchFromGitHub
        source.source.args`) has no following `{` and is not a hit -- that is the
        sanctioned catalog-resolved form.
        """
        mask = cls._mask_nix(text)
        hits = []
        for m in cls._FETCH_TOKEN.finditer(mask):
            fetcher = m.group(1)
            j = m.end()
            while j < len(mask) and mask[j] in " \t\n\r":
                j += 1
            if j >= len(mask) or mask[j] != "{":
                continue
            end = cls._match_brace(mask, j)
            block = text[j:end]
            block_mask = mask[j:end]
            coordinates = [
                coordinate
                for coordinate in cls._COORD_FIELD.finditer(block)
                if block_mask[coordinate.start(1) : coordinate.end(1)]
                == coordinate.group(1)
            ]
            if not coordinates:
                continue
            coord = coordinates[0]
            owner = next(
                (coordinate for coordinate in coordinates if coordinate.group(1) == "owner"),
                None,
            )
            repo = next(
                (coordinate for coordinate in coordinates if coordinate.group(1) == "repo"),
                None,
            )
            if owner and repo:
                owner_value = owner.group(2) if owner.group(2) is not None else owner.group(3)
                repo_value = repo.group(2) if repo.group(2) is not None else repo.group(3)
                locator = f"{owner_value}/{repo_value}"
            else:
                value = coord.group(2) if coord.group(2) is not None else coord.group(3)
                locator = f"{coord.group(1)}={value}"
            hits.append((text.count("\n", 0, j) + 1, fetcher, locator))
        return hits

    @classmethod
    def _iter_production_seams(cls, root):
        """Yield (relpath, text) for each production .nix seam under root."""
        paths = [root / "flake.nix"]
        for name in cls._SEAM_ROOTS:
            paths.extend((root / name).rglob("*.nix"))
        for path in sorted(set(paths)):
            if not path.is_file():
                continue
            rel = path.relative_to(root)
            if any(part in ("test", "tests") for part in rel.parts):
                continue
            yield rel, path.read_text()

    @classmethod
    def _production_inline_offenders(cls, root):
        """Stable offender key -> (relpath, line) across all production seams."""
        offenders = {}
        for rel, text in cls._iter_production_seams(root):
            for line, fetcher, locator in cls._inline_fetcher_offenders(text):
                offenders[f"{rel}: {fetcher} {locator}"] = (str(rel), line)
        return offenders

    def test_production_seams_have_no_undeclared_inline_source_coordinates(self):
        """No detected production inline coordinate is off-catalog.

        Every candidate found by the lexical scanner is either catalog-resolved
        or listed in KNOWN_INLINE_SOURCE_LITERALS. This does NOT
        prove those catalog records are themselves fetchable -- load_source_catalog
        validates their shape; the closure-purity tests cover locator hygiene.
        """
        root = SCRIPT.parent.parent
        offenders = self._production_inline_offenders(root)
        self.assertEqual(
            set(offenders),
            set(self.KNOWN_INLINE_SOURCE_LITERALS),
            "production inline source-coordinate set changed; offenders: %s"
            % {k: "%s:%d" % v for k, v in sorted(offenders.items())},
        )

    def test_inline_source_gate_flags_each_fetcher_kind(self):
        """Representative fetcher negatives plus positive controls.

        Each represented inline literal is flagged; each sanctioned form
        (catalog-resolved application, commented-out fetcher, a `fetcher ==
        "..."` string, and a runtime/service URL that is not a fetcher argument)
        is not -- the gate does not confuse runtime endpoints with sources.
        """
        header = "final: prev: {\n  broken = prev.stdenv.mkDerivation {\n    "
        footer = "\n  };\n}\n"
        rejected = {
            "fetchFromGitHub": 'src = prev.fetchFromGitHub {\n      owner = "evil";\n'
            '      repo = "sneak"; rev = "v1"; hash = "sha256-A";\n    };',
            "fetchgit": 'src = fetchgit {\n      url = "https://x.invalid/r.git";\n'
            '      rev = "abc"; hash = "sha256-B";\n    };',
            "fetchurl": 'src = fetchurl {\n      url = "https://x.invalid/a.tar.gz";\n'
            '      hash = "sha256-C";\n    };',
            "fetchzip": 'src = fetchzip {\n      url = "https://x.invalid/a.zip";\n'
            '      hash = "sha256-D";\n    };',
            "fetchpatch": 'p = fetchpatch {\n      url = "https://x.invalid/p.patch";\n'
            '      hash = "sha256-E";\n    };',
            "fetchPypi": 'src = fetchPypi {\n      pname = "evil"; version = "1.0";\n'
            '      hash = "sha256-F";\n    };',
            "fetchTree (pinned flake URL)": 'src = builtins.fetchTree {\n      type = "github";\n'
            '      owner = "evil"; repo = "flake"; rev = "dead";\n    };',
        }
        for kind, body in rejected.items():
            with self.subTest(reject=kind):
                hits = self._inline_fetcher_offenders(header + body + footer)
                self.assertEqual(len(hits), 1, hits)
        allowed = {
            "catalog-resolved": "src = prev.fetchFromGitHub sources.foo.source.args;",
            "catalog-resolved-paren": 'src = prev.fetchFromGitHub (sourceArgs "fetchFromGitHub" n);',
            "commented-out": '# src = fetchFromGitHub { owner = "a"; repo = "b"; };',
            "block-commented": '/* src = fetchurl { url = "https://x"; hash = "y"; }; */',
            "commented-coordinate": 'src = fetchurl { # url = "https://x";\n };',
            "fetcher-string-compare": 'assert source.source.fetcher == "fetchFromGitHub";',
            "runtime-service-url": 'services.x.endpoint = "https://api.example.com/v1";',
            "lockfile-patch-url": "substituteInPlace lock --replace-fail "
            '"https://registry.npmjs.org/ws/-/ws-1.0.0.tgz" "x";',
        }
        for kind, body in allowed.items():
            with self.subTest(allow=kind):
                hits = self._inline_fetcher_offenders(header + body + footer)
                self.assertEqual(hits, [], hits)

    def test_inline_source_gate_exact_set_rejects_new_and_stale(self):
        """The exact-set comparison discriminates in both directions.

        A newly introduced inline literal appears in the offender set (so the
        real-tree assertEqual would fail); a stale allowlist entry that no longer
        matches any offender also breaks equality. Neither can be papered over.
        """
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            (temp / "overlays").mkdir()
            (temp / "overlays/30-injected.nix").write_text(
                "final: prev: {\n"
                "  malware = prev.stdenv.mkDerivation {\n"
                '    pname = "malware";\n'
                "    src = prev.fetchFromGitHub {\n"
                '      owner = "attacker"; repo = "backdoor";\n'
                '      rev = "0"; hash = "sha256-Z";\n'
                "    };\n  };\n}\n"
            )
            offenders = self._production_inline_offenders(temp)
            key = "overlays/30-injected.nix: fetchFromGitHub attacker/backdoor"
            self.assertIn(key, offenders)
            # New literal, empty allowlist -> sets differ (would fail the gate).
            self.assertNotEqual(set(offenders), set())
            # Stale entry not matching any offender -> also breaks equality.
            self.assertNotEqual(set(offenders), set(offenders) | {"stale/entry"})

    def test_root_consumes_portable_input_authority_transitively(self):
        root = SCRIPT.parent.parent
        root_lock = json.loads((root / "flake.lock").read_text())
        portable_lock = json.loads((root / "config/ai/flake.lock").read_text())
        root_node = root_lock["nodes"]["root"]
        portable_root = portable_lock["nodes"]["root"]
        shared_names = set(portable_root["inputs"])
        self.assertFalse(shared_names & set(root_node["inputs"]))
        self.assertIn("nix-config-ai", root_node["inputs"])
        root_ai = root_lock["nodes"][root_node["inputs"]["nix-config-ai"]]
        self.assertEqual(set(root_ai["inputs"]), shared_names)

        def follow_node(lock, path):
            node_name = "root"
            for input_name in path:
                reference = lock["nodes"][node_name]["inputs"][input_name]
                node_name = (
                    reference
                    if isinstance(reference, str)
                    else follow_node(lock, reference)
                )
            return node_name

        def canonical_reference(lock, reference):
            name = (
                reference
                if isinstance(reference, str)
                else follow_node(lock, reference)
            )
            return canonical_node(lock, name)

        def canonical_node(lock, name):
            node = lock["nodes"][name]
            return {
                "flake": node.get("flake", True),
                "locked": node.get("locked"),
                "inputs": {
                    child: canonical_reference(lock, reference)
                    for child, reference in node.get("inputs", {}).items()
                },
            }

        def canonical_inputs(lock, node):
            return {
                name: canonical_reference(lock, reference)
                for name, reference in node.get("inputs", {}).items()
            }

        root_graph = canonical_inputs(root_lock, root_ai)
        portable_graph = canonical_inputs(portable_lock, portable_root)
        self.assertEqual(root_graph, portable_graph)

        drifted = copy.deepcopy(portable_lock)
        llm_node = drifted["nodes"][drifted["nodes"]["root"]["inputs"]["llm-agents"]]
        llm_nixpkgs = llm_node["inputs"]["nixpkgs"]
        drifted["nodes"][llm_nixpkgs]["locked"]["rev"] = "transitive-drift"
        self.assertNotEqual(
            root_graph, canonical_inputs(drifted, drifted["nodes"]["root"])
        )


if __name__ == "__main__":
    unittest.main()
