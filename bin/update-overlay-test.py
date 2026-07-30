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
import shutil
import socket
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from urllib.parse import urlsplit


SCRIPT = Path(__file__).with_name("update-overlay")
UPDATE_AGENTS = Path(__file__).with_name("update-agents")
UPGRADE_PROJECTS = Path(__file__).with_name("upgrade-projects")
UPGRADE = Path(__file__).with_name("upgrade")
SWITCH = Path(__file__).with_name("switch")
BUILD = Path(__file__).parent.parent / "build"
MODULE = runpy.run_path(str(SCRIPT))
GitHubClient = MODULE["GitHubClient"]
HashComputer = MODULE["HashComputer"]
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
require_detached_linked_worktree = MODULE["require_detached_linked_worktree"]
sync_flake_projections = MODULE["sync_flake_projections"]
resolve_flake_input_version = MODULE.get("resolve_flake_input_version")
update_catalog_target = MODULE["update_catalog_target"]
update_npm_flake_target = MODULE.get("update_npm_flake_target")
update_pypi_artifact_target = MODULE.get("update_pypi_artifact_target")
update_github_release_asset_target = MODULE.get("update_github_release_asset_target")
update_github_commit_artifact_target = MODULE.get("update_github_commit_artifact_target")
update_github_projection_target = MODULE.get("update_github_projection_target")
snapshot_catalog_record_isolation = MODULE.get(
    "snapshot_catalog_record_isolation"
)
validate_catalog_record_isolation = MODULE.get(
    "validate_catalog_record_isolation"
)
enforce_catalog_record_isolation = MODULE.get(
    "enforce_catalog_record_isolation"
)

ISSUE40_TARGETS = frozenset({"cohere-melody", "mlx"})
ISSUE41_TARGETS = frozenset({"hf-xet", "nelisp", "sherlock-db"})
ISSUE45_TARGETS = frozenset({
    "anvil-ide",
    "anvil-mcp",
    "nelisp",
    "standalone-anvil",
})
ISSUE45_BRANCHES = {
    "anvil-ide": "main",
    "anvil-mcp": "fix/anvil-root-resilience",
    "nelisp": "main",
    "standalone-anvil": "master",
}
ISSUE45_EXECUTORS = {
    "anvil-ide": "update-overlay",
    "anvil-mcp": "update-overlay",
    "nelisp": "update-agents",
    "standalone-anvil": "update-overlay",
}
ISSUE45_POLICIES = {
    "anvil-ide": "automatic",
    "anvil-mcp": "automatic",
    "nelisp": "manual",
    "standalone-anvil": "manual",
}
ISSUE45_ARTIFACT = "packages/anvil-mcp/Cargo.lock"
ISSUE39_TARGETS = frozenset(
    json.loads(
        (SCRIPT.parent.parent / "packages/pi-gallery/normalization-policy.json").read_text()
    )["targets"]
)

ISSUE34_TARGETS = frozenset({
    "pi-mcp-adapter",
    "ws",
    "git-ai",
    "llm-agents",
    "mcp-remote",
    "mcp-servers-nix",
    "pal-mcp-server",
    "pi-openai-server-compaction",
    "pi-quiet",
    "translate-tool",
    "rust-overlay",
})
ISSUE34_FLAKE_PROJECTIONS = ISSUE34_TARGETS - {"ws"}
ISSUE34_UPDATE_AGENTS = frozenset({
    "git-ai",
    "llm-agents",
    "mcp-remote",
    "mcp-servers-nix",
    "pal-mcp-server",
    "pi-mcp-adapter",
    "pi-openai-server-compaction",
    "pi-quiet",
    "rust-overlay",
    "translate-tool",
})

VENDOR_HASH = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="


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
    def test_retired_ai_nix_flags_are_rejected(self):
        for flag in ("--ai-nix-dir", "--no-ai-nix", "--only-ai-nix", "--no-ai-nix-advice"):
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
                "_record": {
                    "update": {"kind": "url-release", "policy": policy}
                },
            }

        catalog = {
            "automatic-direct": target("automatic", "update-overlay"),
            "automatic-delegated": target("automatic", "update-agents"),
            "manual-direct": target("manual", "update-overlay"),
        }
        observed = []
        mutate_path = None

        def fake_update(name, *_args):
            observed.append(name)
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
            self.assertIn("Summary: 0 updated, 1 up-to-date, 0 failed", output.getvalue())

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
            self.assertIn("Summary: 0 updated, 2 up-to-date, 0 failed", output.getvalue())

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
                self.assertIn("Dry-run attempted to mutate 1 source file", stderr.getvalue())
        finally:
            globals_.update(originals)
            sys.argv = old_argv


class UpdateInventoryTests(unittest.TestCase):
    def test_source_catalog_is_data_only_unique_and_consumed(self):
        root = SCRIPT.parent.parent
        catalog = load_source_catalog(root)
        self.assertIn("anvil-ide", catalog)
        self.assertIn("anvil-mcp", catalog)
        self.assertIn("pi-lens", catalog)
        for name in (
            "ascii",
            "gptel-got",
            "mitmproxy-macos-wheel",
            "nixpkgs-last-good",
            "org",
            "poppler-darwin-mutex-patch",
            "vterm-tmux",
        ):
            self.assertIn(name, catalog)
        pi_manifest = (root / "packages/pi-gallery/manifest.nix").read_text()
        self.assertIn('member "pi-lens"', pi_manifest)
        self.assertNotIn("version =", pi_manifest)
        self.assertNotIn("registry.npmjs.org", pi_manifest)
        anvil_document = json.loads((root / "sources/anvil.json").read_text())
        self.assertEqual(anvil_document["sources"]["anvil-ide"]["update"]["branch"], "main")
        self.assertEqual(
            anvil_document["sources"]["anvil-mcp"]["update"]["branch"],
            "fix/anvil-root-resilience",
        )
        self.assertTrue(ISSUE45_TARGETS <= catalog.keys())
        self.assertEqual(
            {name: catalog[name]["source"] for name in ISSUE45_TARGETS},
            {name: "catalog" for name in ISSUE45_TARGETS},
        )
        self.assertEqual(
            {name: catalog[name]["executor"] for name in ISSUE45_TARGETS},
            ISSUE45_EXECUTORS,
        )
        self.assertEqual(
            {
                name: catalog[name]["_record"]["update"].get(
                    "policy", "automatic"
                )
                for name in ISSUE45_TARGETS
            },
            ISSUE45_POLICIES,
        )
        self.assertEqual(
            {
                name: catalog[name]["_record"]["update"]["branch"]
                for name in ISSUE45_TARGETS
            },
            ISSUE45_BRANCHES,
        )
        self.assertEqual(
            {
                name: catalog[name]["_record"]["update"]["kind"]
                for name in ISSUE45_TARGETS
            },
            {name: "github-commit" for name in ISSUE45_TARGETS},
        )
        self.assertEqual(
            catalog["nelisp"]["_record"]["update"]["artifacts"],
            [ISSUE45_ARTIFACT],
        )
        self.assertEqual(
            catalog["nelisp"]["_record"]["update"]["artifactSources"],
            {ISSUE45_ARTIFACT: "Cargo.lock"},
        )
        self.assertEqual(
            {
                name
                for name in ISSUE45_TARGETS
                if catalog[name]["_record"]["update"].get("artifactSources")
            },
            {"nelisp"},
        )
        self.assertEqual(
            json.loads((root / "sources/emacs.json").read_text())["sources"]["org"]["commit"],
            "cdc16898fd46a30d7187c0a5830b2b898ffbd2de",
        )
        self.assertIn(
            'source-catalog.nix "compatibility"',
            (root / "overlays/00-last-known-good.nix").read_text(),
        )
        self.assertIn('gitSource "org"', (root / "overlays/10-emacs.nix").read_text())
        self.assertTrue(all(path.suffix == ".json" for path in (root / "sources").iterdir()))
        self.assertFalse((root / "packages/anvil-mcp/source.nix").exists())
        self.assertIn('import ../source-catalog.nix "anvil"', (root / "packages/anvil-mcp/default.nix").read_text())

        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            (temp / "sources").mkdir()
            (temp / "sources/bad.json").write_text(
                '{"schemaVersion":1,"sources":{"same":{},"same":{}}}'
            )
            with self.assertRaisesRegex(ValueError, "duplicate JSON key: same"):
                load_source_catalog(temp)
            (temp / "sources/bad.json").unlink()
            (temp / "sources/multi.json").write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {
                    "multi": {
                        "source": {
                            "fetcher": "fetchurl",
                            "url": "https://example.invalid/main",
                            "args": {"url": "https://example.invalid/main", "hash": "sha256-main"},
                        },
                        "hashes": {"cargoHash": "sha256-cargo"},
                        "artifacts": {
                            "docs": {
                                "fetcher": "fetchurl",
                                "url": "https://example.invalid/docs",
                                "args": {"url": "https://example.invalid/docs", "hash": "sha256-docs"},
                            }
                        },
                        "update": {"kind": "url-release", "policy": "automatic"},
                    }
                },
            }))
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

    def test_issue34_records_are_catalog_owned(self):
        root = SCRIPT.parent.parent
        catalog = load_source_catalog(root)
        self.assertTrue(ISSUE34_TARGETS <= catalog.keys())
        self.assertEqual(
            {name for name in ISSUE34_TARGETS if catalog[name]["source"] == "catalog"},
            ISSUE34_TARGETS,
        )
        self.assertEqual(
            {name for name in ISSUE34_TARGETS if catalog[name]["executor"] == "update-agents"},
            ISSUE34_UPDATE_AGENTS,
        )
        self.assertEqual(
            {name for name in ISSUE34_TARGETS if catalog[name]["executor"] is None},
            set(),
        )
        self.assertEqual(
            {name for name in ISSUE34_TARGETS if catalog[name]["_record"]["source"]["fetcher"] == "fetchTree"},
            ISSUE34_FLAKE_PROJECTIONS,
        )
        self.assertEqual(catalog["ws"]["_record"]["source"]["fetcher"], "fetchzip")
        self.assertEqual(catalog["ws"]["_record"]["update"]["package"], "ws")
        self.assertEqual(catalog["ws"]["executor"], "update-overlay")
        self.assertNotIn("flake.nix", catalog["rust-overlay"]["files"])
        self.assertIn("config/ai/flake.nix", catalog["rust-overlay"]["files"])

        ai_names = set(json.loads((root / "sources/ai.json").read_text())["sources"])
        pi_names = set(json.loads((root / "sources/pi.json").read_text())["sources"])
        self.assertEqual(ISSUE34_TARGETS & ai_names, {
            "git-ai", "llm-agents", "mcp-remote", "mcp-servers-nix",
            "pal-mcp-server", "rust-overlay", "translate-tool",
        })
        self.assertEqual(ISSUE34_TARGETS & pi_names, {
            "pi-mcp-adapter", "pi-openai-server-compaction", "pi-quiet", "ws",
        })
        consumer_text = "\n".join(
            (root / path).read_text()
            for path in (
                "packages/agent-resources.nix",
                "config/ai/catalog.nix",
                "test/ai/agent-resources.nix",
                "test/ai/home-manager-contract-common.nix",
            )
        )
        for duplicate in (
            "https://registry.npmjs.org/ws/-/ws-8.18.3.tgz",
            "sha256-+o96RaViEX6JAoRI5JCLDJDcIXj+XbaH0+wSM9F2pBw=",
            "sha256-Mxt5yq4UGxwVSIIC9B+fG2SS4BUNseyAL806Eb1I9YM=",
        ):
            self.assertNotIn(duplicate, consumer_text)

    def test_issue34_projection_parity_uses_selected_lock_nodes(self):
        root = SCRIPT.parent.parent
        catalog = load_source_catalog(root)
        lock = json.loads((root / "config/ai/flake.lock").read_text())
        root_inputs = lock["nodes"][lock["root"]]["inputs"]
        for name in ISSUE34_FLAKE_PROJECTIONS:
            record = catalog[name]["_record"]
            input_name = record["update"]["input"]
            node_name = root_inputs[input_name]
            self.assertIsInstance(node_name, str)
            locked = lock["nodes"][node_name]["locked"]
            self.assertEqual(
                {field: record["source"]["args"][field] for field in ("type", "owner", "repo", "rev", "narHash")},
                {field: locked[field] for field in ("type", "owner", "repo", "rev", "narHash")},
            )
        self.assertEqual(root_inputs["rust-overlay"], "rust-overlay_2")
        self.assertNotEqual(root_inputs["rust-overlay"], "rust-overlay")

    def test_issue34_projection_mutations_fail_for_the_named_field(self):
        mutations = {
            "owner does not match declared input":
                lambda _document, lock: lock["nodes"]["selected"]["original"].update(owner="other"),
            "rev does not match portable lock":
                lambda _document, lock: lock["nodes"]["selected"]["locked"].update(rev="b" * 40),
            "narHash does not match portable lock":
                lambda _document, lock: lock["nodes"]["selected"]["locked"].update(narHash="sha256-other"),
        }
        for expected, mutate in mutations.items():
            with self.subTest(expected=expected), tempfile.TemporaryDirectory() as temp_dir:
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
            with self.assertRaisesRegex(RuntimeError, "rev does not match portable lock"):
                load_source_catalog(root)

    def test_issue34_projection_rejects_literal_url_drift(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_projection_fixture(root)
            (root / "config/ai/flake.nix").write_text(
                '{\n  inputs = {\n    example.url = "github:other/project";\n  };\n}\n'
            )
            with self.assertRaisesRegex(RuntimeError, "owner does not match flake literal"):
                load_source_catalog(root)

    def test_issue34_sync_refreshes_selected_lock_projection(self):
        def make_stale(document, _lock):
            source = document["sources"]["example"]["source"]
            source["args"]["rev"] = "0" * 40
            source["args"]["narHash"] = "sha256-stale"
            source["url"] = "https://github.com/stale/project"

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_projection_fixture(root, make_stale)
            self.assertEqual(sync_flake_projections(root), 1)
            target = load_source_catalog(root)["example"]
            args = target["_record"]["source"]["args"]
            self.assertEqual(args["rev"], "a" * 40)
            self.assertEqual(args["narHash"], "sha256-selected")
            self.assertEqual(target["_record"]["source"]["url"], "https://github.com/example/project")

        env = os.environ.copy()
        env.pop("UPDATE_AGENTS_CANDIDATE", None)
        refused = subprocess.run(
            [sys.executable, str(SCRIPT), "--sync-flake-projections"],
            cwd=SCRIPT.parent.parent,
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("restricted to the update-agents candidate", refused.stderr)
        with tempfile.TemporaryDirectory() as temp_dir:
            primary = Path(temp_dir)
            (primary / ".git").mkdir()
            with self.assertRaisesRegex(RuntimeError, "detached linked worktree"):
                require_detached_linked_worktree(primary)

    def test_flake_input_copy_syncs_projected_package_version(self):
        def make_copy_stale(document, lock):
            record = document["sources"]["example"]
            record["version"] = "1.0.0"
            record["update"]["kind"] = "flake-input+copy"
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
            build_calls = []

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

            def validate_build(_root, package):
                on_disk = json.loads((root / "sources/test.json").read_text())[
                    "sources"
                ]["example"]
                build_calls.append(package)
                self.assertEqual(on_disk["hashes"]["npmDepsHash"], "sha256-new")

            self.assertEqual(
                sync_flake_projections(
                    root,
                    version_resolver=lambda _root, _input, _locked: "2.0.0",
                    dependent_hash_resolver=resolve_hash,
                    build_validator=validate_build,
                ),
                1,
            )
            record = json.loads((root / "sources/test.json").read_text())["sources"][
                "example"
            ]
            self.assertEqual(hash_calls, [("agent-resources", "npmDepsHash")])
            self.assertEqual(build_calls, ["agent-resources"])
            self.assertEqual(record["version"], "2.0.0")
            self.assertEqual(record["source"]["args"]["rev"], "a" * 40)
            self.assertEqual(record["hashes"]["npmDepsHash"], "sha256-new")

    def test_fod_hash_parser_requires_the_injected_dummy_pair(self):
        parse = MODULE["HashComputer"]._parse_dummy_hash_mismatch
        unrelated = """specified: sha256-old
got: sha256-unrelated
"""
        requested = f"""specified: {MODULE['DUMMY_SRI_HASH']}
got: sha256-requested
"""
        self.assertIsNone(parse(unrelated))
        self.assertEqual(parse(unrelated + requested), "sha256-requested")
        self.assertIsNone(parse(requested + requested.replace("requested", "second")))

    def test_package_hash_build_never_creates_a_result_link(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            build = root / "build"
            build.write_text("#!/bin/sh\nexit 0\n")
            build.chmod(0o755)
            command = MODULE["HashComputer"](root)._package_build_command(
                "agent-resources"
            )
            self.assertEqual(
                command,
                ["./build", "pkg", "agent-resources", "--no-link"],
            )
            self.assertEqual(
                MODULE["HashComputer"](root)._package_build_command(
                    "hf-xet", "python"
                ),
                ["./build", "python", "hf-xet", "--no-link"],
            )
            computer = HashComputer(root)
            build_calls = []

            def fake_build(package, build_mode):
                build_calls.append((package, build_mode))
                return SimpleNamespace(
                    returncode=1,
                    stdout=(
                        f"specified: {MODULE['DUMMY_SRI_HASH']}\n"
                        "got: sha256-cHl0aG9u\n"
                    ),
                    stderr="",
                )

            computer._run_package_build = fake_build
            self.assertEqual(
                computer._compute_fod_hash(
                    "hf-xet", "cargoDepsHash", "python"
                ),
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
                        HashComputer(root).resolve_build_tool(
                            "jq", "jq", runner=runner
                        )
                    )
            self.assertIsNone(
                HashComputer(root).resolve_build_tool(
                    "jq; builtins.abort", "jq", runner=resolved_tool
                )
            )

    def test_pi_manifest_normalizer_is_shared_complete_and_fail_closed(self):
        root = SCRIPT.parent.parent
        contract = load_pi_normalization_contract(root)
        self.assertEqual(set(contract["targets"]), ISSUE39_TARGETS)
        jq = shutil.which("jq")
        self.assertIsNotNone(jq)
        manifest = {
            "name": "example",
            "version": "1.0.0",
            "dependencies": {
                "keep": "1",
                "better-sqlite3": "1",
                "@earendil-works/pi-tui": "1",
                "@sinclair/typebox": "1",
                "typebox": "1",
            },
            "optionalDependencies": {
                "optional-keep": "1",
                "better-sqlite3": "1",
                "@earendil-works/pi-tui": "1",
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
            "pi-smart-fetch": {
                "@earendil-works/pi-tui",
                "@sinclair/typebox",
            },
            "pi-subagents": {"typebox"},
        }
        all_special_dependencies = set().union(*special.values())
        for target in sorted(ISSUE39_TARGETS):
            with self.subTest(target=target):
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
                    self.assertNotIn(
                        dependency, normalized["optionalDependencies"]
                    )
                for dependency in (
                    all_special_dependencies - special.get(target, set())
                ):
                    self.assertIn(dependency, normalized["dependencies"])
                    self.assertIn(
                        dependency, normalized["optionalDependencies"]
                    )
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
        self.assertIsNone(
            normalize_pi_manifest(
                root,
                "pi-artifacts",
                "wrong-name",
                "1.0.0",
                json.dumps(manifest),
                Path(jq),
            )
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            temporary_root = Path(temp_dir)
            gallery = temporary_root / "packages/pi-gallery"
            gallery.mkdir(parents=True)
            shutil.copy(root / "packages/pi-gallery/normalize-manifest.jq", gallery)

            def rejected_by_both(label, mutate):
                malformed = copy.deepcopy(contract)
                mutate(malformed)
                policy = gallery / "normalization-policy.json"
                policy.write_text(json.dumps(malformed))
                with self.subTest(label=label):
                    with self.assertRaises(RuntimeError):
                        load_pi_normalization_contract(temporary_root)
                    result = subprocess.run(
                        [
                            jq,
                            "--arg",
                            "target",
                            "pi-artifacts",
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
                        input=json.dumps(manifest),
                        capture_output=True,
                        text=True,
                        check=False,
                    )
                    self.assertNotEqual(result.returncode, 0)

            rejected_by_both(
                "scripts enabled",
                lambda value: value["npmDependencyFlags"].remove(
                    "--ignore-scripts"
                ),
            )
            rejected_by_both(
                "unknown contract field",
                lambda value: value.update(unexpected=True),
            )
            rejected_by_both(
                "duplicate removal",
                lambda value: value["common"]["removeTopLevel"].append(
                    "devDependencies"
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
            ISSUE39_TARGETS,
        )
        environment = dict(os.environ)
        environment.pop("UPDATE_AGENTS_CANDIDATE", None)
        refused = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--prepare-npm-locks",
                "pi-artifacts",
            ],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
        )
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("restricted to the update-agents candidate", refused.stderr)
        environment["UPDATE_AGENTS_CANDIDATE"] = "1"
        attached = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--prepare-npm-locks",
                "pi-artifacts",
            ],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
        )
        self.assertNotEqual(attached.returncode, 0)
        self.assertIn("detached linked worktree", attached.stderr)

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
            self.assertFalse(
                verify_npm_integrity(archive_path, "sha512-AAAAAAAA")
            )
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
        prior_lock = json.dumps({
            "name": "example",
            "version": "1.0.0",
            "lockfileVersion": 3,
            "packages": {"": manifest},
        }, indent=2) + "\n"
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

        flags = pi_npm_lock_flags(
            load_pi_normalization_contract(SCRIPT.parent.parent)
        )
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
        self.assertFalse(
            validate_npm_manifest_lock(json.dumps(raw), generated)
        )
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
                lambda value: value["packages"]["node_modules/keep"].pop(
                    "integrity"
                ),
            ),
            (
                "malformed integrity",
                lambda value: value["packages"]["node_modules/keep"].update(
                    integrity="not-sri"
                ),
            ),
            (
                "link package",
                lambda value: value["packages"]["node_modules/keep"].update(
                    link=True
                ),
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
            validate_npm_manifest_lock(
                json.dumps(optional_mismatch), generated
            )
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
        self.assertEqual(
            kwargs["env"]["PATH"], "/nix/store/fake-node/bin"
        )
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
            policy_path.write_text(json.dumps({
                "schemaVersion": 1,
                "npmDependencyFlags": [
                    "--ignore-scripts",
                    "--omit=dev",
                    "--omit=peer",
                    "--legacy-peer-deps",
                ],
                "common": {
                    "removeTopLevel": [],
                    "forbidDependencies": [],
                },
                "targets": {
                    "project": {
                        "removeTopLevel": [],
                        "forbidDependencies": [],
                    }
                },
            }))
            (root / "packages/pi-gallery/normalize-manifest.jq").write_text(".\n")
            lock_path = lock_dir / "project-package-lock.json"
            old_manifest = {"name": "project", "version": "1.0.0"}
            old_lock = json.dumps({
                "name": "project",
                "version": "1.0.0",
                "lockfileVersion": 3,
                "packages": {"": old_manifest},
            }, indent=2) + "\n"
            lock_path.write_text(old_lock)
            catalog_path = root / "sources/pi.json"
            catalog_path.write_text(json.dumps({
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
            }))
            target = load_source_catalog(root)["project"]
            self.assertEqual(target["executor"], "update-agents")
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
            canonical_lock = (
                "packages/pi-gallery/locks/project-package-lock.json"
            )
            for sibling_document, artifact_alias in (
                ("a.json", canonical_lock),
                ("z.json", f"./{canonical_lock}"),
            ):
                with self.subTest(sibling_document=sibling_document):
                    sibling_path = root / "sources" / sibling_document
                    sibling_record = copy.deepcopy(shared_record)
                    sibling_record["update"]["artifacts"] = [artifact_alias]
                    sibling_path.write_text(json.dumps({
                        "schemaVersion": 1,
                        "sources": {"sibling": sibling_record},
                    }))
                    with self.assertRaisesRegex(
                        RuntimeError, "exactly its normalizer target as owner"
                    ):
                        load_source_catalog(root)
                    sibling_path.unlink()

            (root / "flake.lock").write_text("{}\n")
            shared_flake_path = root / "sources/shared-flake.json"
            shared_flake_path.write_text(json.dumps({
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
            }))
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
            future_record["source"]["args"]["url"] = future_record["source"][
                "url"
            ]
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
                                "https://cdn.example.invalid/project-"
                                f"{requested}.tgz"
                            ),
                        }
                    ),
                    off_registry_hashes,
                    transaction,
                )
            self.assertEqual(status, "failed")
            self.assertEqual(off_registry_hashes.calls, [])
            self.assertEqual(transaction.original, {})

            normalized = json.dumps({
                "name": "project",
                "version": "2.0.0",
                "dependencies": {"keep": "1"},
            }, indent=2) + "\n"
            new_lock = json.dumps({
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
            }, indent=2) + "\n"
            observed = []

            def fake_normalizer(
                _root, target_name, expected_name, version, raw, jq
            ):
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

            class RepairHashes(FakeHashes):
                def __init__(self):
                    super().__init__()
                    self.validation_results = iter((False, True))

                def validate_package_build(self, package):
                    self.calls.append(("validate", package))
                    return next(self.validation_results)

            repair_hashes = RepairHashes()
            repair_hashes.compute_native_hash = lambda _source, _replacements: (
                "sha256-source-new"
            )
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
                    repair_hashes,
                    transaction,
                    manifest_reader=lambda _path: (
                        '{"name":"project","version":"2.0.0"}',
                        {"name": "project", "version": "2.0.0"},
                    ),
                    manifest_normalizer=fake_normalizer,
                    lock_generator=lambda _manifest, _prior, _npm, _flags: new_lock,
                    integrity_verifier=lambda _path, _integrity: True,
                )
            transaction.commit()
            self.assertEqual(status, "updated")
            repaired = json.loads(catalog_path.read_text())["sources"]["project"]
            self.assertEqual(repaired["hashes"]["npmDepsHash"], "sha256-npm-new")
            self.assertEqual(
                [call for call in repair_hashes.calls if call[0] == "validate"],
                [("validate", "project"), ("validate", "project")],
            )

            before_catalog = catalog_path.read_text()
            before_lock = lock_path.read_text()
            failing_target = load_source_catalog(root)["project"]
            failing_hashes = FakeHashes(valid=False)
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_npm_lock_target(
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
                    lock_generator=lambda *_args: new_lock.replace(
                        "2.0.0", "3.0.0"
                    ),
                    integrity_verifier=lambda _path, _integrity: True,
                )
            self.assertEqual(status, "failed")
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
            self.assertEqual(load_source_catalog(root)["ws"]["executor"], "update-overlay")
            document["sources"]["ws"]["update"]["package"] = "other"
            (root / "sources/test.json").write_text(json.dumps(document))
            with self.assertRaisesRegex(RuntimeError, "npm source identity"):
                load_source_catalog(root)
            document["sources"]["ws"]["update"]["package"] = "ws"
            document["sources"]["ws"]["version"] = "8.18.4"
            (root / "sources/test.json").write_text(json.dumps(document))
            with self.assertRaisesRegex(RuntimeError, "URL does not match catalog version"):
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
                catalog_path.write_text(json.dumps({
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
                }, indent=2) + "\n")
                flake_path.write_text(
                    '{ inputs.example.url = "github:example/project/' + old_rev + '"; }\n'
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
        real_delegate = globals_["delegate_to_update_agents"]
        old_argv = sys.argv
        try:
            globals_["delegate_to_update_agents"] = fake_delegate
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
            globals_["delegate_to_update_agents"] = real_delegate
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

        delegated = MODULE["delegate_to_update_agents"](
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
                catalog_path.write_text(json.dumps({
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
                                "input": "example",
                                "kind": "npm-release+flake-input",
                                "package": "example",
                            },
                        }
                    },
                }, indent=2) + "\n")
                flake_path.write_text(
                    '{ inputs.example.url = "github:example/project"; }\n'
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
                with contextlib.redirect_stdout(io.StringIO()):
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
                        ("fetchTree", {"rev": new_rev}),
                    ],
                )
                return status

            write_old_state()
            rolled_back = SourceTransaction()
            self.assertEqual(update(rolled_back), "updated")
            self.assertIn(new_rev, catalog_path.read_text())
            self.assertIn(new_rev, flake_path.read_text())
            self.assertEqual(rolled_back.rollback(), 2)
            self.assertIn(old_rev, catalog_path.read_text())
            self.assertNotIn(new_rev, flake_path.read_text())

            committed = SourceTransaction()
            self.assertEqual(update(committed), "updated")
            committed.commit()
            record = json.loads(catalog_path.read_text())["sources"]["example"]
            self.assertEqual(record["version"], "2.0.0")
            self.assertEqual(record["source"]["args"]["hash"], "sha256-tar-new")
            self.assertEqual(
                record["artifacts"]["flakeInput"]["args"]["rev"], new_rev
            )
            self.assertEqual(
                record["artifacts"]["flakeInput"]["args"]["narHash"],
                "sha256-git-new",
            )
            self.assertIn(new_rev, flake_path.read_text())

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

            drifted = json.loads(catalog_path.read_text())
            drifted["sources"]["example"]["version"] = "2.0.0"
            catalog_path.write_text(json.dumps(drifted, indent=2) + "\n")
            before_catalog = catalog_path.read_text()
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

        invalid = []
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
        insecure_fetch_url["source"]["args"]["url"] = "http://example.invalid/archive.tgz"
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
            self.assertIsNone(client.get_default_branch("example", "project"))
            self.assertIsNone(client.get_latest_commit("example", "project", "topic"))
            self.assertIsNone(
                client.get_file("example", "project", "a" * 40, "Cargo.lock")
            )
        finally:
            subprocess.run = real_run

        self.assertEqual(len(calls), 5)
        self.assertIn("releases/latest", calls[0][2])
        self.assertEqual("repos/example/project", calls[1][2])
        self.assertIn("commits/topic", calls[2][2])
        self.assertEqual("repos/example/project", calls[3][2])
        self.assertEqual(calls[4][:2], ["gh", "api"])
        self.assertIn(f"contents/Cargo.lock?ref={'a' * 40}", calls[4][2])

        successful_calls = []
        responses = [
            json.dumps({
                "content": "ZXhhY3QgY29udGVudHMK",
                "encoding": "base64",
                "type": "file",
            }),
            json.dumps([{"name": "Cargo.lock", "type": "file"}]),
            json.dumps({
                "content": "%%%",
                "encoding": "base64",
                "type": "file",
            }),
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
            self.assertIsNone(
                client.get_file("example", "project", "b" * 40, "locks")
            )
            self.assertIsNone(
                client.get_file("example", "project", "b" * 40, "bad")
            )
        finally:
            subprocess.run = real_run
        self.assertEqual(content, "exact contents\n")
        self.assertEqual(len(successful_calls), 3)
        command, kwargs = successful_calls[0]
        self.assertEqual(command[:2], ["gh", "api"])
        self.assertIn(
            f"contents/locks/Cargo%20lock?ref={'b' * 40}", command[2]
        )
        self.assertEqual(kwargs["timeout"], 60)

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
            self.assertIsNone(
                client.get_latest_commit("example", "project", "topic")
            )
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
            self.assertEqual(
                client.get_latest_release("example", "project"), "v2.0.0"
            )
            self.assertIsNone(client.last_error)
            self.assertIsNone(client.get_default_branch("example", "project"))
            self.assertIn("repository missing", client.last_error)
            self.assertEqual(
                client.get_default_branch("example", "project"), "trunk"
            )
            self.assertIsNone(client.last_error)
        finally:
            subprocess.run = real_run

        def raising_run(_command, **_kwargs):
            raise OSError("gh executable unavailable")

        subprocess.run = raising_run
        try:
            client = GitHubClient()
            self.assertIsNone(
                client.get_latest_commit("example", "project", "missing")
            )
        finally:
            subprocess.run = real_run
        self.assertIn("requested branch 'missing'", client.last_error)
        self.assertIn("default branch is unavailable", client.last_error)
        self.assertIn("gh executable unavailable", client.last_error)

    def test_cargo_lock_validation_uses_exact_checkout(self):
        revision = "c" * 40
        lock = (
            "version = 4\n\n"
            "[[package]]\n"
            'name = "project"\n'
            'version = "1.0.0"\n'
        )
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
            command for command, _kwargs in calls if command[0] == "git" and "fetch" in command
        )
        self.assertEqual(first_fetch[-2:], [
            "https://github.com/example/project",
            revision,
        ])
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
            path.write_text(json.dumps({
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
                        "update": {"kind": "url-release", "policy": "manual"},
                    }
                },
            }))
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
                json.loads(path.read_text())["sources"]["example"]["source"]["args"]["sha256"],
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

    def test_native_hash_uses_locked_fetcher_and_preserves_encoding(self):
        calls = []

        def fake_run(command, **_kwargs):
            calls.append(command)
            if command[1:3] == ["hash", "convert"]:
                return SimpleNamespace(returncode=0, stdout="nix32-new\n", stderr="")
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

        self.assertEqual(value, "nix32-new")
        self.assertIn("nix-config-ai.inputs.nixpkgs", calls[0][-1])
        self.assertEqual(calls[1][1:3], ["hash", "convert"])
        self.assertEqual(zip_value, "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
        self.assertIn("pkgs.fetchzip", calls[2][-1])
        self.assertIn("example-2.0.0.tgz", calls[2][-1])
        self.assertNotIn("example-1.0.0.tgz", calls[2][-1])

    def test_native_hash_surfaces_sanitized_actionable_nix_failure(self):
        real_shaped_stderr = (
            "\x1b[31;1merror:\x1b[0m Cannot build '/nix/store/example.drv'.\n"
            "       Last 3 log lines:\n"
            "       > fatal: repository 'https://codeberg.org/example/gone' "
            "not found\x00\n"
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
            self.assertIn("ERROR: git fetch", detail)
            self.assertIn("Unable to checkout", detail)
            self.assertNotIn("Cannot build", detail)
            self.assertNotIn("\x1b", detail)
            self.assertNotIn("\x00", detail)
            self.assertNotIn(" > ", detail)
            self.assertLessEqual(
                len(detail), MODULE["MAX_ACTIONABLE_ERROR_CHARS"]
            )
            self.assertEqual(
                hashes.compute_native_hash(source, {}),
                "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",
            )
            self.assertIsNone(hashes.last_error)
        finally:
            subprocess.run = real_run

    def test_native_hash_records_exception_conversion_and_fetchtree_failures(self):
        sri = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
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

        responses = [
            SimpleNamespace(
                returncode=1,
                stdout="",
                stderr=f"got: {sri}\n",
            ),
            SimpleNamespace(
                returncode=1,
                stdout="",
                stderr="error: invalid hash conversion\n",
            ),
        ]

        def conversion_run(_command, **_kwargs):
            return responses.pop(0)

        subprocess.run = conversion_run
        try:
            self.assertIsNone(hashes.compute_native_hash(source, {}))
        finally:
            subprocess.run = real_run
        self.assertIn("hash conversion failed", hashes.last_error)
        self.assertIn("invalid hash conversion", hashes.last_error)

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
            last_error = (
                "native fetcher build failed: fatal: repository not found"
            )

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

    def test_catalog_npm_update_rewrites_source_and_dependent_hash_atomically(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/ai.json"
            path.write_text(json.dumps({
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
            }))
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

    def test_catalog_github_release_preserves_native_tag_field(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/ai.json"
            path.write_text(json.dumps({
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
                        "update": {"kind": "github-release", "tagPrefix": "v"},
                    }
                },
            }))
            target = load_source_catalog(root)["example"]

            github = SimpleNamespace(get_latest_release=lambda _owner, _repo: "v2.0.0")
            hashes = SimpleNamespace(
                compute_native_hash=lambda _source, _replacements: "sha256-new"
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
            self.assertNotIn("rev", record["source"]["args"] )

    def test_catalog_pypi_update_preserves_fetchpypi_arguments(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            path = root / "sources/ai.json"
            path.write_text(json.dumps({
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
                        "update": {"kind": "pypi-release", "package": "example"},
                    }
                },
            }))
            target = load_source_catalog(root)["example"]
            pypi = SimpleNamespace(
                get_release=lambda _package, _record, _requested=None: (
                    "2.0.0",
                    "https://files.pythonhosted.org/example-2.0.0.tar.gz",
                    "sha256-new",
                )
            )
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
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
            self.assertEqual(record["version"], "2.0.0")
            self.assertEqual(record["source"]["args"]["version"], "2.0.0")
            self.assertEqual(record["source"]["args"]["hash"], "sha256-new")
            self.assertNotIn("url", record["source"]["args"] )
            self.assertEqual(record["source"]["url"], "https://pypi.org/project/example")

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
                "update": {"kind": "pypi-release", "package": "example"},
            }
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"example": record},
            }))
            target = load_source_catalog(root)["example"]
            self.assertEqual(target["executor"], "update-agents")

            def artifact(filename, byte):
                return {
                    "filename": filename,
                    "url": f"https://files.pythonhosted.org/{filename}",
                    "digests": {"sha256": byte * 64},
                }

            documents = {
                "example": {
                    "info": {"version": "2.0.0"},
                    "releases": {"2.0.0": [
                        artifact("example-2.0.0-cp311-cp311-macosx_14_0_arm64.whl", "1"),
                        artifact("example-2.0.0-cp313-cp313-macosx_14_0_arm64.whl", "2"),
                    ]},
                },
                "example-metal": {
                    "info": {"version": "2.0.0"},
                    "releases": {"2.0.0": [
                        artifact("example_metal-2.0.0-py3-none-macosx_14_0_arm64.whl", "3"),
                    ]},
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
                    transaction,
                )
            self.assertEqual(status, "failed")
            self.assertEqual(path.read_text(), before)
            self.assertEqual(transaction.original, {})

            calls = []
            client = PypiClient()
            client._get_metadata = lambda package: (
                calls.append(package) or documents.get(package)
            )
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_pypi_artifact_target(
                    "example",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    client,
                    transaction,
                )
            transaction.commit()
            self.assertEqual(status, "updated")
            self.assertEqual(calls, ["example", "example-metal"])
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

            updated["artifacts"]["cp311"]["args"]["version"] = "1.0.0"
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"example": updated},
            }))
            with self.assertRaisesRegex(
                RuntimeError, "compound PyPI artifact version does not match"
            ):
                load_source_catalog(root)

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
                "source": asset(
                    "tool-1.0.0-darwin-arm64", "sha256-darwin-old"
                ),
                "artifacts": {
                    "aarch64-linux": asset(
                        "tool-1.0.0-linux-arm64", "sha256-arm-old"
                    ),
                    "x86_64-linux": asset("tool-linux-x64", "sha256-linux-old")
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
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"tool": record},
            }))
            target = load_source_catalog(root)["tool"]
            self.assertEqual(target["executor"], "update-agents")
            github = SimpleNamespace(
                get_latest_release=lambda _owner, _repo: "v2.0.0"
            )

            calls = []

            def incomplete_hash(_source, replacements):
                calls.append(replacements["url"])
                return None if replacements["url"].endswith("tool-linux-x64") else "sha256-darwin"

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

            source_only = copy.deepcopy(record)
            source_only.pop("artifacts")
            source_only["update"]["assets"] = {
                "source": "tool-{version}-darwin-arm64"
            }
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"tool": source_only},
            }))
            source_only_target = load_source_catalog(root)["tool"]
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_github_release_asset_target(
                    "tool",
                    source_only_target,
                    SimpleNamespace(version=None, dry_run=False),
                    SimpleNamespace(
                        get_latest_release=lambda _owner, _repo: "v3.0.0"
                    ),
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

            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"tool": record},
            }))
            failing_target = load_source_catalog(root)["tool"]
            failing_before = path.read_text()
            failing_builds = []
            transaction = SourceTransaction()
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_github_release_asset_target(
                    "tool",
                    failing_target,
                    SimpleNamespace(version=None, dry_run=False),
                    SimpleNamespace(
                        get_latest_release=lambda _owner, _repo: "v4.0.0"
                    ),
                    SimpleNamespace(
                        compute_native_hash=hashes.compute_native_hash,
                        validate_package_build=lambda package: (
                            failing_builds.append(package) or False
                        ),
                    ),
                    transaction,
                )
            self.assertEqual(status, "failed")
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
                    path.write_text(json.dumps({
                        "schemaVersion": 1,
                        "sources": {"tool": invalid},
                    }))
                    with self.assertRaisesRegex(
                        RuntimeError, "invalid GitHub release asset projection"
                    ):
                        load_source_catalog(root)

            missing_prefix = copy.deepcopy(record)
            del missing_prefix["update"]["tagPrefix"]
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"tool": missing_prefix},
            }))
            with self.assertRaisesRegex(RuntimeError, "update strategy fields"):
                load_source_catalog(root)

            wrong_prefix = copy.deepcopy(record)
            wrong_prefix["update"]["tagPrefix"] = ""
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"tool": wrong_prefix},
            }))
            with self.assertRaisesRegex(RuntimeError, "asset URL does not match"):
                load_source_catalog(root)

            dependent_hash = copy.deepcopy(record)
            dependent_hash["hashes"] = {"cargoHash": "sha256-stale"}
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"tool": dependent_hash},
            }))
            with self.assertRaisesRegex(
                RuntimeError, "invalid GitHub release asset projection"
            ):
                load_source_catalog(root)

            updated["update"]["assets"]["source"] = "wrong-name"
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"tool": updated},
            }))
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
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"python-project": record},
            }))
            target = load_source_catalog(root)["python-project"]
            self.assertEqual(target["executor"], "update-agents")

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

            github = SimpleNamespace(
                get_latest_release=lambda _owner, _repo: "v2.0.0"
            )
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
            with contextlib.redirect_stdout(io.StringIO()):
                status = update_catalog_target(
                    "python-project",
                    failing_target,
                    SimpleNamespace(version="3.0.0", dry_run=False),
                    github,
                    SimpleNamespace(),
                    SimpleNamespace(),
                    failing,
                    transaction,
                )
            self.assertEqual(status, "failed")
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
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"python-project": wrong_fetcher},
            }))
            with self.assertRaisesRegex(
                RuntimeError,
                "requires fetchFromGitHub",
            ):
                load_source_catalog(root)

            wrong_prefix_type = copy.deepcopy(record)
            wrong_prefix_type["update"]["tagPrefix"] = 7
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"python-project": wrong_prefix_type},
            }))
            with self.assertRaisesRegex(RuntimeError, "tag prefix"):
                load_source_catalog(root)

            fetch_artifact = copy.deepcopy(record)
            fetch_artifact["artifacts"] = {
                "linux": copy.deepcopy(record["source"])
            }
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"python-project": fetch_artifact},
            }))
            with self.assertRaisesRegex(
                RuntimeError,
                "cannot also declare artifacts",
            ):
                load_source_catalog(root)

            local_artifact = copy.deepcopy(record)
            local_artifact["update"]["artifacts"] = ["projection.lock"]
            (root / "projection.lock").write_text("old\n")
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"python-project": local_artifact},
            }))
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
                "hashes": {"cargoDepsHash": "sha256-cargo-old"},
                "update": {
                    "branch": "main",
                    "buildMode": "python",
                    "kind": "github-commit",
                },
            }
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"project": record},
            }))
            target = load_source_catalog(root)["project"]
            self.assertEqual(target["executor"], "update-agents")

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
            with contextlib.redirect_stdout(io.StringIO()):
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
            self.assertIn(("source", {"rev": new_ref}), hashes.calls)
            self.assertIn(
                ("dependent", "project", "cargoDepsHash", "python"),
                hashes.calls,
            )
            updated = json.loads(path.read_text())["sources"]["project"]
            self.assertEqual(updated["source"]["args"]["rev"], new_ref)
            self.assertEqual(updated["hashes"]["cargoDepsHash"], "sha256-cargo-new")

            combined = copy.deepcopy(record)
            combined["update"]["artifacts"] = ["Cargo.lock"]
            combined["update"]["artifactSources"] = {"Cargo.lock": "Cargo.lock"}
            (root / "Cargo.lock").write_text("version = 4\n")
            path.write_text(json.dumps({
                "schemaVersion": 1,
                "sources": {"project": combined},
            }))
            with self.assertRaisesRegex(
                RuntimeError,
                "cannot also declare artifacts",
            ):
                load_source_catalog(root)

    def test_github_commit_fetches_lock_from_exact_selected_revision(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "sources").mkdir()
            (root / "packages/anvil-mcp").mkdir(parents=True)
            lock_path = root / "packages/anvil-mcp/Cargo.lock"
            old_lock = 'version = 4\n\n[[package]]\nname = "old"\nversion = "1.0.0"\n'
            new_lock = 'version = 4\n\n[[package]]\nname = "new"\nversion = "2.0.0"\n'
            lock_path.write_text(old_lock)
            path = root / "sources/anvil.json"
            old_ref = "1" * 40
            new_ref = "2" * 40
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
                    "artifacts": ["packages/anvil-mcp/Cargo.lock"],
                    "artifactSources": {
                        "packages/anvil-mcp/Cargo.lock": "Cargo.lock"
                    },
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
                "update-agents",
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

                def validate_cargo_lock(
                    self, source_url, revision, remote, content
                ):
                    self.validations.append(
                        (source_url, revision, remote, content)
                    )
                    return self.lock_valid

            def run_update(github, hashes):
                transaction = SourceTransaction()
                with contextlib.redirect_stdout(io.StringIO()):
                    status = update_github_commit_artifact_target(
                        "project",
                        load_source_catalog(root)["project"],
                        SimpleNamespace(version=None, dry_run=False),
                        github,
                        hashes,
                        transaction,
                    )
                return status, transaction

            def assert_failure_is_atomic(transaction):
                self.assertEqual(transaction.original, {})
                self.assertEqual(path.read_bytes(), before_source)
                self.assertEqual(lock_path.read_bytes(), before_lock)
                self.assertEqual(transaction.rollback(), 0)

            invalid_content_github = FakeGitHub("not a Cargo lock")
            invalid_content_hashes = FakeHashes()
            status, transaction = run_update(
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
            status, transaction = run_update(
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
            status, transaction = run_update(rollback_github, rollback_hashes)
            self.assertEqual(status, "updated")
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
            status, transaction = run_update(commit_github, commit_hashes)
            self.assertEqual(status, "updated")
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

    def test_catalog_and_cli_inventory_cover_all_update_targets(self):
        root = SCRIPT.parent.parent
        try:
            catalog = load_source_catalog(root)
        except (RuntimeError, subprocess.SubprocessError, ValueError) as error:
            self.fail(f"catalog evaluation failed: {error}")
        required = {
            "agent-browser-source",
            "anvil-mcp",
            "pi-artifacts",
            "pi-lens",
            "pi-mcp-adapter",
            "pi-smart-fetch",
            "pi-smart-web-search",
            "rust-overlay",
            "ws",
            "git-ai",
            "llm-agents",
            "translate-tool",
        }
        self.assertTrue(required <= catalog.keys())
        self.assertIn("packages/pi-gallery/locks/pi-lens-package-lock.json", catalog["pi-lens"]["files"])
        self.assertIn(
            "packages/pi-gallery/locks/pi-smart-fetch-package-lock.json",
            catalog["pi-smart-fetch"]["files"],
        )
        self.assertIn(
            "packages/pi-gallery/locks/pi-smart-web-search-package-lock.json",
            catalog["pi-smart-web-search"]["files"],
        )
        self.assertIn("sources/pi.json", catalog["pi-mcp-adapter"]["files"])
        self.assertNotIn("config/ai/catalog.nix", catalog["pi-mcp-adapter"]["files"])
        self.assertIn("packages/anvil-mcp/Cargo.lock", catalog["nelisp"]["files"])
        self.assertEqual(catalog["ws"]["_record"]["update"]["package"], "ws")

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
        names = [item["name"] for item in inventory["packages"]]
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(set(names), set(catalog))
        self.assertEqual(names, sorted(catalog))
        self.assertEqual(
            hashlib.sha256("\n".join(names).encode()).hexdigest(),
            "4e5b6cdb25ccc7617dbdefe79afc06e31ee15392f70416f59b0529397ce49261",
        )
        self.assertTrue(required <= set(names))
        self.assertTrue(all(item["inventoried"] for item in inventory["packages"]))
        self.assertEqual(set(inventory), {"packages", "schemaVersion"})
        by_name = {item["name"]: item for item in inventory["packages"]}
        relocated = {
            "agent-deck",
            "agnix",
            "browser-control-mcp",
            "claude-replay",
            "claude-vault",
            "context-hub",
            "drafts-mcp-server",
            "gguf-tools",
            "hfdownloader",
            "lazycodex-ai",
            "llama-cpp",
            "llama-swap",
            "llm-mlx",
            "omlx",
            "rustdocs-mcp-server",
        }
        catalog_owned = {
            item["name"] for item in inventory["packages"] if item["source"] == "catalog"
        }
        self.assertEqual(
            {item["name"] for item in inventory["packages"] if not item["managed"]},
            set(),
        )
        self.assertEqual(len(inventory["packages"]), 199)
        self.assertEqual(
            len([item for item in inventory["packages"] if item["managed"]]),
            199,
        )
        self.assertEqual(catalog_owned, set(catalog))
        self.assertTrue(relocated <= catalog_owned)
        self.assertTrue(all(by_name[name]["managed"] for name in relocated))
        self.assertTrue(by_name["git-ai"]["managed"])
        self.assertEqual(
            {name for name in ISSUE34_TARGETS if by_name[name]["source"] == "catalog"},
            ISSUE34_TARGETS,
        )
        self.assertEqual(
            {name for name in ISSUE34_TARGETS if by_name[name]["executor"] == "update-agents"},
            ISSUE34_UPDATE_AGENTS,
        )
        self.assertEqual(
            by_name["anvil-ide"]["version"],
            "0e6130457ac2bdc6c6db2eebeba67a5223231190",
        )
        self.assertEqual(by_name["git-ai"]["executor"], "update-agents")
        for name in ("cymbal", "rtk"):
            self.assertTrue(by_name[name]["managed"])
            self.assertEqual(by_name[name]["kind"], "github-release-asset")
            self.assertEqual(by_name[name]["executor"], "update-agents")
            self.assertEqual(by_name[name]["policy"], "manual")
        self.assertEqual(by_name["pi-ponytail"]["executor"], "update-agents")
        self.assertEqual(by_name["pi-mcp-adapter"]["executor"], "update-agents")
        self.assertEqual(by_name["pi-btw"]["executor"], "update-agents")
        self.assertEqual(
            catalog["pi-mcp-adapter"]["_record"]["update"]["buildPackage"],
            "agent-resources",
        )
        self.assertEqual(by_name["ws"]["executor"], "update-overlay")
        self.assertEqual(
            {name for name in ISSUE40_TARGETS if by_name[name]["managed"]},
            ISSUE40_TARGETS,
        )
        self.assertEqual(
            {name for name in ISSUE40_TARGETS if by_name[name]["executor"] == "update-agents"},
            ISSUE40_TARGETS,
        )
        self.assertEqual(
            {name for name in ISSUE41_TARGETS if by_name[name]["managed"]},
            ISSUE41_TARGETS,
        )
        self.assertEqual(
            {name for name in ISSUE41_TARGETS if by_name[name]["executor"] == "update-agents"},
            ISSUE41_TARGETS,
        )
        self.assertEqual(
            {name for name in ISSUE39_TARGETS if by_name[name]["managed"]},
            ISSUE39_TARGETS,
        )
        self.assertEqual(
            {
                name
                for name in ISSUE39_TARGETS
                if by_name[name]["executor"] == "update-agents"
            },
            ISSUE39_TARGETS,
        )
        self.assertTrue(
            all(
                catalog[name]["_record"]["update"].get("normalizer")
                == "pi-gallery-v1"
                for name in ISSUE39_TARGETS
            )
        )
        for item in inventory["packages"]:
            for path in item["files"]:
                self.assertTrue((root / path).is_file(), (item["name"], path))
        human = subprocess.run(
            [sys.executable, str(SCRIPT), "--inventory"],
            capture_output=True,
            text=True,
            check=False,
            cwd=root,
        )
        self.assertEqual(human.returncode, 0, human.stderr)
        self.assertEqual(
            human.stdout.splitlines()[-1],
            "199 inventoried targets; 199 executable; 0 pending executors",
        )

    def test_source_transaction_rolls_back_and_commit_preserves(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "overlay.nix"
            path.write_text("old\n")
            transaction = SourceTransaction()
            transaction.watch(path)
            path.write_text("broken\n")
            self.assertEqual(transaction.rollback(), 1)
            self.assertEqual(path.read_text(), "old\n")

            committed = SourceTransaction()
            committed.watch(path)
            path.write_text("new\n")
            committed.commit()
            committed.rollback_unless_committed()
            self.assertEqual(path.read_text(), "new\n")

    def test_explicit_catalog_record_isolation_allows_selected_and_rolls_back_sibling(self):
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

    def test_prepare_npm_locks_wiring_rejects_and_rolls_back_sibling_record(self):
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
                "executor": "update-agents",
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
                    "--prepare-npm-locks",
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

    def _create_update_agents_fixture(self, temporary: str):
        root = Path(temporary) / "repo"
        fake_bin = Path(temporary) / "bin"
        (root / "bin").mkdir(parents=True)
        (root / "config/ai").mkdir(parents=True)
        (root / "overlays/ai").mkdir(parents=True)
        fake_bin.mkdir()

        empty_lock = json.dumps(
            {"nodes": {"root": {"inputs": {}}}, "root": "root", "version": 7}
        )
        (root / "flake.lock").write_text(empty_lock + "\n")
        (root / "config/ai/flake.lock").write_text(empty_lock + "\n")
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
    "--prepare-fixed-inputs",
    "--prepare-npm-flake-inputs",
    "--prepare-npm-locks",
    "--prepare-pypi-artifacts",
    "--prepare-github-projections",
    "--sync-flake-projections",
}
if internal_modes.intersection(arguments) and os.environ.get("UPDATE_AGENTS_CANDIDATE") != "1":
    print("internal update requires update-agents candidate", file=sys.stderr)
    raise SystemExit(77)
declared = [
    "tracked.txt", "mode.sh", "binary.bin", "format.nix", "projection.json", "link",
    "regular-to-link", "link-to-regular", "renamed-old.txt", "renamed-new.txt",
    "deleted.txt", "created.txt", "fixed.txt", "npm-lock.txt", "npm-lock-second.txt",
    "pypi.txt", "github.txt",
    "new-directory/generated-lock.json"
]
if "--inventory" in arguments:
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
            "executor": "update-agents",
            "policy": "manual",
        })
    if os.environ.get("UPDATE_TEST_COPY_TARGET") == "1":
        packages.append({
            "name": "copy",
            "files": ["projection.json"],
            "input": "copy-input",
            "inventoried": True,
            "kind": "flake-input+copy",
            "managed": True,
            "executor": "update-agents",
            "policy": "automatic",
        })
    if os.environ.get("UPDATE_TEST_BUILD_TARGET") == "1":
        packages.append({
            "name": "build",
            "files": ["projection.json"],
            "input": "build-input",
            "inventoried": True,
            "kind": "flake-input+build",
            "managed": True,
            "executor": "update-agents",
            "policy": "manual",
        })
    if os.environ.get("UPDATE_TEST_NPM_FLAKE_TARGET") == "1":
        packages.append({
            "name": "npm-flake",
            "files": ["fixed.txt", "projection.json", "config/ai/flake.nix"],
            "input": "npm-flake-input",
            "inventoried": True,
            "kind": "npm-release+flake-input",
            "managed": True,
            "executor": "update-agents",
            "policy": "automatic",
        })
    if os.environ.get("UPDATE_TEST_PYPI_TARGET") == "1":
        packages.append({
            "name": "pypi",
            "files": ["pypi.txt"],
            "inventoried": True,
            "kind": "pypi-release",
            "managed": True,
            "executor": "update-agents",
            "policy": "manual",
        })
    if os.environ.get("UPDATE_TEST_NPM_LOCK_TARGET") == "1":
        packages.append({
            "name": "npm-lock",
            "files": ["npm-lock.txt"],
            "inventoried": True,
            "kind": "npm-release",
            "managed": True,
            "executor": "update-agents",
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
            "executor": "update-agents",
            "policy": "manual",
        })
    if os.environ.get("UPDATE_TEST_GITHUB_TARGET") == "1":
        packages.append({
            "name": "github",
            "files": ["github.txt"],
            "inventoried": True,
            "kind": "github-release-asset",
            "managed": True,
            "executor": "update-agents",
            "policy": "manual",
        })
    print(json.dumps({
        "schemaVersion": 1,
        "packages": packages,
    }))
elif "--prepare-fixed-inputs" in arguments:
    if arguments != ["--prepare-fixed-inputs", "fixed"]:
        print(f"unexpected fixed preparation: {arguments}", file=sys.stderr)
        raise SystemExit(78)
    (root / "fixed.txt").write_text("fixed after\\n")
elif "--prepare-npm-flake-inputs" in arguments:
    if arguments != ["--prepare-npm-flake-inputs", "npm-flake"]:
        print(f"unexpected npm flake preparation: {arguments}", file=sys.stderr)
        raise SystemExit(79)
    (root / "fixed.txt").write_text("npm flake after\\n")
elif "--prepare-npm-locks" in arguments:
    if arguments not in (
        ["--prepare-npm-locks", "npm-lock"],
        ["--prepare-npm-locks", "npm-lock", "npm-lock-second"],
    ):
        print(f"unexpected npm lock preparation: {arguments}", file=sys.stderr)
        raise SystemExit(82)
    (root / "npm-lock.txt").write_text("npm lock after\\n")
    if "npm-lock-second" in arguments:
        (root / "npm-lock-second.txt").write_text("npm lock second after\\n")
        if os.environ.get("UPDATE_TEST_NPM_LOCK_SECOND_FAIL") == "1":
            raise SystemExit(83)
    if os.environ.get("UPDATE_TEST_MUTATE_OTHER_DECLARED") == "1":
        (root / "github.txt").write_text("cross-target mutation\\n")
elif "--prepare-pypi-artifacts" in arguments:
    if arguments != ["--prepare-pypi-artifacts", "pypi"]:
        print(f"unexpected PyPI preparation: {arguments}", file=sys.stderr)
        raise SystemExit(80)
    (root / "pypi.txt").write_text("pypi after\\n")
elif "--prepare-github-projections" in arguments:
    if arguments != ["--prepare-github-projections", "github"]:
        print(f"unexpected GitHub preparation: {arguments}", file=sys.stderr)
        raise SystemExit(81)
    (root / "github.txt").write_text("github after\\n")
elif "--sync-flake-projections" in arguments:
    (root / "projection.json").write_text('{"projected": true}\\n')
    if os.environ.get("UPDATE_TEST_SIGNAL_PHASE") == "candidate-projection":
        Path(os.environ["UPDATE_TEST_SIGNAL_MARKER"]).touch()
        os.kill(os.getppid(), signal.SIGTERM)
    if os.environ.get("UPDATE_TEST_FAILURE_PHASE") == "candidate-projection":
        raise SystemExit(71)
else:
    if os.environ.get("UPDATE_AGENTS_CANDIDATE") != "1":
        print("compound update requires update-agents candidate", file=sys.stderr)
        raise SystemExit(77)
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
        raise SystemExit(71)
"""
        )
        updater.chmod(0o700)

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
mutate_phase() {
  if [[ ${UPDATE_TEST_SIGNAL_PHASE:-} == "$1" \
    || ${UPDATE_TEST_FAILURE_PHASE:-} == "$1" ]]; then
    printf '%s\n' "$1" >>"$2"
  fi
}
if [[ $1 == flake && $2 == update ]]; then
  if [[ ${3:-} == --flake ]]; then
    mutate_phase candidate-portable-lock config/ai/flake.lock
    signal_phase candidate-portable-lock
    fail_phase candidate-portable-lock
  else
    mutate_phase candidate-root-lock flake.lock
    signal_phase candidate-root-lock
    fail_phase candidate-root-lock
  fi
elif [[ $1 == flake && $2 == check ]]; then
  if [[ ${UPDATE_TEST_MUTATE_LIVE:-} == 1 ]]; then
    printf 'external\n' >>"$NIX_CONFIG_DIR/external.txt"
  fi
  if [[ ${3:-} == ./config/ai ]]; then
    signal_phase candidate-portable-validation
    fail_phase candidate-portable-validation
  else
    signal_phase candidate-root-validation
    fail_phase candidate-root-validation
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
        real_mkdir = shutil.which("mkdir") or "/bin/mkdir"
        executable(
            "git",
            """#!/usr/bin/env bash
set -euo pipefail
phase=${UPDATE_TEST_SIGNAL_PHASE:-}
marker=${UPDATE_TEST_SIGNAL_MARKER:-}
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
exec "$REAL_GIT" "$@"
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
            "REAL_MKDIR": real_mkdir,
            "TMPDIR": temporary,
        }
        return root, environment, baseline

    @staticmethod
    def _update_agents_projection(root: Path):
        projection = {}
        for current, directories, files in os.walk(root, topdown=True, followlinks=False):
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
        self.assertEqual(list(root.parent.glob("update-agents.*")), [])

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
            self.assertEqual(projection["mode.sh"], ("file", 0o755, b"#!/bin/sh\nexit 0\n"))
            self.assertEqual(projection["binary.bin"], ("file", 0o644, b"\x00after\xfe\n"))
            self.assertEqual(
                projection["format.nix"],
                ("file", 0o644, b"{ changed = true; }\n"),
            )
            self.assertEqual(
                projection["projection.json"],
                ("file", 0o644, b'{"projected": true}\n'),
            )
            self.assertEqual(projection["link"], ("symlink", "target-new"))
            self.assertEqual(
                projection["regular-to-link"], ("symlink", "target-new")
            )
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
            self.assertEqual(list(root.parent.glob("update-agents.*")), [])

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
            self.assertEqual((root / "projection.json").read_text(), '{"projected": true}\n')
            commands = command_log.read_text().splitlines()
            self.assertEqual(
                commands,
                [
                    "flake update --flake ./config/ai fixed-input",
                    "flake update nix-config-ai",
                    "flake check ./config/ai --all-systems --no-build",
                    "flake check --no-build",
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

    def test_update_agents_routes_flake_input_copy_through_named_locks(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            command_log = Path(temp_dir) / "commands.log"
            environment["UPDATE_TEST_COPY_TARGET"] = "1"
            environment["UPDATE_TEST_COMMAND_LOG"] = str(command_log)
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
            self.assertEqual((root / "projection.json").read_text(), '{"projected": true}\n')
            self.assertEqual(
                command_log.read_text().splitlines(),
                [
                    "flake update --flake ./config/ai copy-input",
                    "flake update nix-config-ai",
                    "flake check ./config/ai --all-systems --no-build",
                    "flake check --no-build",
                ],
            )

        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, _baseline = self._create_update_agents_fixture(
                temp_dir
            )
            command_log = Path(temp_dir) / "commands.log"
            environment["UPDATE_TEST_COPY_TARGET"] = "1"
            environment["UPDATE_TEST_COMMAND_LOG"] = str(command_log)
            result = subprocess.run(
                [str(UPDATE_AGENTS)],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                command_log.read_text().splitlines()[0],
                "flake update --flake ./config/ai git-ai llm-agents mcp-remote "
                "mcp-servers-nix pal-mcp-server pi-openai-server-compaction "
                "pi-quiet translate-tool copy-input",
            )

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
            self.assertEqual((root / "projection.json").read_text(), '{"projected": true}\n')
            self.assertEqual(
                command_log.read_text().splitlines(),
                [
                    "flake update --flake ./config/ai build-input",
                    "flake update nix-config-ai",
                    "flake check ./config/ai --all-systems --no-build",
                    "flake check --no-build",
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

    def test_update_agents_routes_npm_flake_input_as_one_named_transaction(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, baseline = self._create_update_agents_fixture(temp_dir)
            command_log = Path(temp_dir) / "commands.log"
            environment["UPDATE_TEST_NPM_FLAKE_TARGET"] = "1"
            environment["UPDATE_TEST_COMMAND_LOG"] = str(command_log)
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--target", "npm-flake"],
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
            self.assertEqual((root / "fixed.txt").read_text(), "npm flake after\n")
            self.assertEqual((root / "tracked.txt").read_text(), "before\n")
            self.assertEqual(
                command_log.read_text().splitlines(),
                [
                    "flake update --flake ./config/ai npm-flake-input",
                    "flake update nix-config-ai",
                    "flake check ./config/ai --all-systems --no-build",
                    "flake check --no-build",
                ],
            )

        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, _baseline = self._create_update_agents_fixture(
                temp_dir
            )
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
            root, environment, baseline = self._create_update_agents_fixture(
                temp_dir
            )
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
                "overlay --prepare-pypi-artifacts pypi",
                "overlay --prepare-github-projections github",
                "overlay --prepare-npm-flake-inputs npm-flake",
                "overlay --prepare-fixed-inputs fixed",
                "nix flake update --flake ./config/ai "
                "npm-flake-input fixed-input",
                "overlay --sync-flake-projections",
            ]
            positions = [events.index(event) for event in ordered]
            self.assertEqual(positions, sorted(positions))
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
                    "flake check ./config/ai --all-systems --no-build",
                    "flake check --no-build",
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
                    "flake check ./config/ai --all-systems --no-build",
                    "flake check --no-build",
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

    def test_all_inputs_prepares_npm_locks_after_lock_sync_before_generic_update(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root, environment, _baseline = self._create_update_agents_fixture(
                temp_dir
            )
            interleaving_log = Path(temp_dir) / "interleaving.log"
            environment.update(
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
            portable_lock = events.index("nix flake update --flake ./config/ai")
            root_lock = events.index("nix flake update")
            projection_sync = events.index("overlay --sync-flake-projections")
            npm_locks = events.index("overlay --prepare-npm-locks npm-lock")
            inventory_checks = [
                index
                for index, event in enumerate(events)
                if event == "overlay --inventory --json"
            ]
            generic_update = events.index("overlay --all")
            self.assertEqual(len(inventory_checks), 2)
            self.assertLess(portable_lock, projection_sync)
            self.assertLess(root_lock, projection_sync)
            self.assertLess(projection_sync, npm_locks)
            self.assertLess(npm_locks, inventory_checks[-1])
            self.assertLess(inventory_checks[-1], generic_update)
            self.assertLess(npm_locks, generic_update)
            self.assertEqual((root / "npm-lock.txt").read_text(), "npm lock after\n")

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
                    "flake check ./config/ai --all-systems --no-build",
                    "flake check --no-build",
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
                root, environment, baseline = self._create_update_agents_fixture(temp_dir)
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
                root, environment, baseline = self._create_update_agents_fixture(temp_dir)
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
            self.assertEqual(list(root.parent.glob("update-agents.*")), [])

    def test_update_agents_rejects_post_merge_untracked_mutation(self):
        for phase, path_name in (
            ("merge-untracked", "post-merge.tmp"),
            ("merge-ignored", "ignored.tmp"),
        ):
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as temp_dir:
                root, environment, baseline = self._create_update_agents_fixture(temp_dir)
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
            self.assertEqual((root / "verify-external.txt").read_text(), "verify edit\n")
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
            self.assertIn("signed commit did not capture the complete transaction", result.stderr)
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
                [real_git, "-C", str(root), "worktree", "add", "--detach", str(unrelated)],
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
            self.assertEqual(list(root.parent.glob("update-agents.*")), [])

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
            self.assertEqual(list(root.parent.glob("update-agents.*")), [])

    def test_update_agents_sigterm_discards_every_candidate_phase(self):
        for phase in (
            "candidate-portable-lock",
            "candidate-root-lock",
            "candidate-projection",
            "candidate-update",
            "candidate-format",
            "candidate-portable-validation",
            "candidate-root-validation",
        ):
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as temp_dir:
                root, environment, baseline = self._create_update_agents_fixture(temp_dir)
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

    def test_update_agents_failure_discards_every_candidate_phase(self):
        for phase in (
            "candidate-portable-lock",
            "candidate-root-lock",
            "candidate-projection",
            "candidate-update",
            "candidate-format",
            "candidate-portable-validation",
            "candidate-root-validation",
        ):
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as temp_dir:
                root, environment, baseline = self._create_update_agents_fixture(temp_dir)
                before = self._update_agents_projection(root)
                environment["UPDATE_TEST_FAILURE_PHASE"] = phase
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
            self.assertEqual((root / "external.txt").read_text(), "external\nexternal\n")
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
            empty_lock = json.dumps({"nodes": {"root": {"inputs": {}}}, "root": "root", "version": 7})
            (root / "flake.lock").write_text(empty_lock + "\n")
            (root / "config/ai/flake.lock").write_text(empty_lock + "\n")
            (root / "overlays/ai/package.nix").write_text("baseline\n")
            write_minimal_catalog(root)

            def executable(name, text):
                path = fake_bin / name
                path.write_text(text)
                path.chmod(0o700)

            executable("nix", """#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == eval ]]; then
  printf '{"schemaVersion":1,"targets":{}}\n'
elif [[ $1 == flake && $2 == update ]]; then
  :
elif [[ $1 == flake && $2 == check ]]; then
  exit 23
fi
""")
            executable("python", """#!/usr/bin/env bash
set -euo pipefail
if [[ ${2:-} == --sync-flake-projections ]]; then exec python3 "$@"; fi
echo catalog-change >> sources/test.json
""")
            executable("nixfmt", "#!/usr/bin/env bash\nexit 0\n")

            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(["git", "-C", str(root), "add", "."], check=True)
            subprocess.run(
                ["git", "-C", str(root), "-c", "user.name=Test",
                 "-c", "user.email=test@example.invalid", "commit", "-qm", "baseline"],
                check=True,
            )
            baseline = subprocess.run(
                ["git", "-C", str(root), "rev-parse", "HEAD"],
                capture_output=True, text=True, check=True,
            ).stdout.strip()
            env = {
                **os.environ,
                "NIX_CONFIG_DIR": str(root),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
            }
            result = subprocess.run(
                [str(UPDATE_AGENTS)], capture_output=True, text=True, env=env, check=False
            )
            self.assertEqual(result.returncode, 23)
            status = subprocess.run(
                ["git", "-C", str(root), "status", "--porcelain"],
                capture_output=True, text=True, check=True,
            )
            self.assertEqual(status.stdout, "")
            self.assertEqual(
                subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True, text=True, check=True,
                ).stdout.strip(),
                baseline,
            )
            worktrees = subprocess.run(
                ["git", "-C", str(root), "worktree", "list", "--porcelain"],
                capture_output=True, text=True, check=True,
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
            empty_lock = json.dumps({"nodes": {"root": {"inputs": {}}}, "root": "root", "version": 7})
            (root / "flake.lock").write_text(empty_lock + "\n")
            (root / "config/ai/flake.lock").write_text(empty_lock + "\n")
            (root / "overlays/ai/package.nix").write_text("baseline\n")
            write_minimal_catalog(root)

            real_git = shutil.which("git") or "/usr/bin/git"

            def executable(name, text):
                path = fake_bin / name
                path.write_text(text)
                path.chmod(0o700)

            executable("nix", """#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == eval ]]; then
  printf '{"schemaVersion":1,"targets":{}}\n'
elif [[ $1 == flake && $2 == update ]]; then
  :
elif [[ $1 == flake && $2 == check ]]; then
  exit 0
fi
""")
            executable("python", """#!/usr/bin/env bash
set -euo pipefail
if [[ ${2:-} == --sync-flake-projections ]]; then exec python3 "$@"; fi
echo catalog-change >> sources/test.json
""")
            executable("nixfmt", "#!/usr/bin/env bash\nexit 0\n")
            executable("git", """#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  if [[ $arg == commit ]]; then exit 42; fi
  if [[ $arg == push ]]; then : > "$PUSH_MARKER"; exit 0; fi
done
exec "$REAL_GIT" "$@"
""")

            subprocess.run([real_git, "init", "-q", str(root)], check=True)
            subprocess.run([real_git, "-C", str(root), "add", "."], check=True)
            subprocess.run(
                [real_git, "-C", str(root), "-c", "user.name=Test",
                 "-c", "user.email=test@example.invalid", "commit", "-qm", "baseline"],
                check=True,
            )
            baseline = subprocess.run(
                [real_git, "-C", str(root), "rev-parse", "HEAD"],
                capture_output=True, text=True, check=True,
            ).stdout.strip()
            env = {
                **os.environ,
                "NIX_CONFIG_DIR": str(root),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "PUSH_MARKER": str(push_marker),
                "REAL_GIT": real_git,
            }
            result = subprocess.run(
                [str(UPDATE_AGENTS), "--commit", "--push"],
                capture_output=True, text=True, env=env, check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("signed commit failed", result.stderr)
            self.assertFalse(push_marker.exists())
            self.assertEqual(
                subprocess.run(
                    [real_git, "-C", str(root), "rev-parse", "HEAD"],
                    capture_output=True, text=True, check=True,
                ).stdout.strip(),
                baseline,
            )
            self.assertEqual(
                subprocess.run(
                    [real_git, "-C", str(root), "status", "--porcelain"],
                    capture_output=True, text=True, check=True,
                ).stdout,
                "",
            )

    def test_update_agents_rejects_concurrent_transaction(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "repo"
            root.mkdir()
            (root / "tracked").write_text("baseline\n")
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(["git", "-C", str(root), "add", "tracked"], check=True)
            subprocess.run(
                ["git", "-C", str(root), "-c", "user.name=Test",
                 "-c", "user.email=test@example.invalid", "commit", "-qm", "baseline"],
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
                    capture_output=True, text=True, check=True,
                ).stdout,
                "",
            )

    def test_active_commands_have_one_repository_update_transaction(self):
        root = SCRIPT.parent.parent
        update_agents = (root / "bin" / "update-agents").read_text()
        build = (root / "build").read_text()
        makefile = (root / "Makefile").read_text()
        upgrade = (root / "bin" / "upgrade").read_text()
        upgrade_projects = (root / "bin" / "upgrade-projects").read_text()
        switch = (root / "bin" / "switch").read_text()
        update_remote = (root / "bin" / "update-remote").read_text()
        active = "\n".join((update_agents, build, makefile, upgrade, upgrade_projects, switch, update_remote))

        for retired in (
            "AI_NIX_DIR",
            "NO_AI_NIX_OVERRIDE",
            "--override-input ai-nix",
            "--no-ai-nix",
            "--only-ai-nix",
            "src/ai-nix",
            "jwiegley/ai-nix",
        ):
            with self.subTest(retired=retired):
                self.assertNotIn(retired, active)

        self.assertNotIn('nix flake update "${ai_inputs[@]}"', update_agents)
        self.assertIn("nix flake update nix-config-ai", update_agents)
        for required_input in (
            "git-ai",
            "llm-agents",
            "mcp-remote",
            "mcp-servers-nix",
            "pal-mcp-server",
            "pi-openai-server-compaction",
            "pi-quiet",
            "translate-tool",
        ):
            with self.subTest(required_input=required_input):
                self.assertIn(required_input, update_agents)
        self.assertIn(
            'nix flake update --flake ./config/ai "${ai_inputs[@]}" "${lock_target_inputs[@]}"',
            update_agents,
        )
        self.assertNotIn("\n    nixpkgs\n", update_agents)
        self.assertNotIn("\n    rust-overlay\n", update_agents)
        for catalog_routed in (
            "agent-browser-source",
            "pi-agent-browser-native",
            "pi-artifacts",
            "pi-dynamic-workflows",
            "pi-hashline-edit-pro",
            "pi-insights",
            "pi-lens",
            "pi-mcp-adapter",
            "pi-smart-fetch",
            "pi-smart-web-search",
            "ponytail",
        ):
            with self.subTest(catalog_routed=catalog_routed):
                self.assertNotIn(f"\n    {catalog_routed}\n", update_agents)
        self.assertIn("python bin/update-overlay --all", update_agents)
        self.assertNotIn("--overlays-dir", update_agents)
        self.assertEqual(update_agents.count('git_pull_clean "$config_dir"'), 1)
        self.assertIn("run_commit=false", update_agents)
        self.assertIn("run_switch=false", update_agents)
        self.assertIn("run_push=false", update_agents)
        self.assertIn("run_brew=false", update_agents)
        self.assertIn('commit -S -m "Update AI agents"', update_agents)
        self.assertIn("--switch/--push require --commit", update_agents)
        self.assertNotIn("git -C \"$repo\" add -A", update_agents)
        self.assertNotIn("commit_and_push_if_changed", update_agents)
        self.assertIn("bin/update-agents --all-inputs --brew", makefile)
        self.assertIn("if [[ $run_all_inputs == true ]]", update_agents)
        self.assertIn("nix flake update --flake ./config/ai", update_agents)
        catalog = load_source_catalog(root)
        expected_inputs = {
            name for name, target in catalog.items()
            if target.get("executor") == "update-agents"
            and target.get("kind") == "flake-input"
        }
        block = re.search(r"ai_inputs=\((.*?)\n\)", update_agents, re.DOTALL)
        if block is None:
            self.fail("update-agents has no ai_inputs array")
        declared_inputs = {
            line.strip() for line in block.group(1).splitlines() if line.strip()
        }
        self.assertEqual(declared_inputs, expected_inputs)
        self.assertIn("--prepare-fixed-inputs", update_agents)
        self.assertIn(
            "export UPDATE_AGENTS_CANDIDATE=1",
            update_agents,
        )
        self.assertNotIn(
            "UPDATE_AGENTS_CANDIDATE=1 python bin/update-overlay --sync-flake-projections",
            update_agents,
        )
        self.assertIn("transaction_baseline=", update_agents)
        self.assertIn("trap cleanup_transaction EXIT", update_agents)
        self.assertIn('git -C "$config_dir" worktree add', update_agents)
        self.assertIn(
            'git -C "$config_dir" -c core.hooksPath=/dev/null',
            update_agents,
        )
        self.assertIn('merge --ff-only "$committed_head"', update_agents)
        self.assertIn("nix flake check --no-build", update_agents)
        self.assertNotIn("rollback_transaction", update_agents)
        self.assertIn("refusing external action without a newly signed commit", update_agents)
        self.assertIn("set -euo pipefail", upgrade)
        self.assertRegex(upgrade, r"(?m)^\s*\./bin/update-agents --commit\s*$")
        self.assertIn(
            'exec "${installed_upgrade_projects:-$script_dir/upgrade-projects}"',
            upgrade,
        )
        self.assertNotIn("set +e", upgrade)
        self.assertNotIn("if [[ $?", upgrade_projects)
        self.assertIn("if (run_project_body", upgrade_projects)
        self.assertIn("failures=$((failures + 1))", upgrade_projects)
        self.assertIn("exit 1", upgrade_projects)
        self.assertIn('nix_flake_output_for_host "$host"', switch)
        self.assertIn('nixos-rebuild switch --flake ".#$output"', switch)
        self.assertNotIn("nixos-rebuild switch", update_remote)
        self.assertIn("&& switch", update_remote)
        self.assertNotIn("./bin/update-agents --no-switch --no-brew", upgrade)

    def test_overlay_manifests_are_explicit_and_inputs_do_not_leak_through_pkgs(self):
        root = SCRIPT.parent.parent
        composition = (root / "config/overlays.nix").read_text()
        root_declared = re.findall(r"\.\./overlays/([0-9][^/\s]+\.nix)", composition)
        root_actual = [path.name for path in (root / "overlays").glob("[0-9]*.nix")]
        self.assertEqual(len(root_declared), len(set(root_declared)))
        self.assertEqual(sorted(root_declared), sorted(root_actual))
        self.assertNotIn("readDir", composition)

        ai_composition = (root / "overlays/ai/default.nix").read_text()
        ai_declared = re.findall(r"import \./([0-9][^/\s]+\.nix)", ai_composition)
        ai_actual = [path.name for path in (root / "overlays/ai").glob("[0-9]*.nix")]
        self.assertEqual(len(ai_declared), len(set(ai_declared)))
        self.assertEqual(sorted(ai_declared), sorted(ai_actual))

        production_nix = [
            root / "flake.nix",
            *root.glob("config/**/*.nix"),
            *root.glob("flake/**/*.nix"),
            *root.glob("overlays/**/*.nix"),
        ]
        forbidden = (
            "pkgs.inputs",
            "prev.inputs",
            "final.inputs",
            "inherit (prev) inputs",
            "(_final: _prev: { inherit inputs; })",
        )
        for path in production_nix:
            text = path.read_text()
            for expression in forbidden:
                with self.subTest(path=path.relative_to(root), expression=expression):
                    self.assertNotIn(expression, text)

    def test_upgrade_projects_continues_and_returns_aggregate_failure(self):
        projects = (
            "src/category-theory/master",
            "src/ltl/coq",
            "src/notes/haskell",
            "src/org-jw",
            "src/pushme",
            "src/gitlib",
            "src/hours",
            "src/renamer",
            "src/simple-amount",
            "src/sizes",
            "src/three-partition",
            "src/trade-journal",
            "src/una",
            "src/comparable",
            "src/rag-client",
            "src/hf",
            "src/ledger/main",
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            home = temp / "home"
            fake_bin = temp / "bin"
            logs = temp / "logs"
            trace = temp / "trace"
            fake_bin.mkdir()
            for project in projects:
                directory = home / project
                directory.mkdir(parents=True)
                (directory / ".envrc").write_text("")
            for command in ("cabal", "cargo", "rag-client", "huggingface-cli"):
                path = fake_bin / command
                path.write_text(
                    "#!/usr/bin/env bash\n"
                    "printf '%s|%s|%s\\n' \"$(basename \"$0\")\" \"$PWD\" \"$*\" >> \"$UPGRADE_TRACE\"\n"
                    "[[ $(basename \"$0\") != rag-client ]] || exit 23\n"
                    "exit 0\n"
                )
                path.chmod(0o700)
            nix = fake_bin / "nix"
            nix.write_text(
                "#!/usr/bin/env bash\n"
                "printf 'nix|%s|%s\\n' \"$PWD\" \"$*\" >> \"$UPGRADE_TRACE\"\n"
                "[[ $PWD != */org-jw ]] || exit 19\n"
                "exit 0\n"
            )
            nix.chmod(0o700)
            result = subprocess.run(
                [str(UPGRADE_PROJECTS)],
                capture_output=True,
                text=True,
                check=False,
                env={
                    **os.environ,
                    "HOME": str(home),
                    "PATH": f"{fake_bin}:{os.environ['PATH']}",
                    "UPGRADE_LOG_DIR": str(logs),
                    "UPGRADE_TRACE": str(trace),
                },
            )
            self.assertEqual(result.returncode, 1)
            self.assertEqual(sum(line.endswith("FAIL") for line in result.stdout.splitlines()), 2)
            self.assertIn("2 failure(s)", result.stderr)

            events = [line.split("|", 2) for line in trace.read_text().splitlines()]
            nix_directories = {directory for command, directory, _ in events if command == "nix"}
            self.assertEqual(nix_directories, {str(home / project) for project in projects})
            command_counts = {
                command: sum(event[0] == command for event in events)
                for command in ("nix", "cabal", "cargo", "rag-client", "huggingface-cli")
            }
            self.assertEqual(
                command_counts,
                {"nix": 17, "cabal": 22, "cargo": 1, "rag-client": 1, "huggingface-cli": 1},
            )
            expected_logs = {
                "category-theory-build.log", "ltl-coq-build.log", "notes-haskell-build.log",
                "org-jw-build.log", "pushme-build.log", "gitlib-build.log", "hours-build.log",
                "renamer-build.log", "simple-amount-build.log", "sizes-build.log",
                "three-partition-build.log", "trade-journal-build.log", "una-build.log",
                "comparable-build.log", "rag-client-build.log", "hf-build.log", "ledger-build.log",
            }
            self.assertEqual({path.name for path in logs.iterdir()}, expected_logs)

    def test_root_inputs_do_not_reference_external_filesystems(self):
        root = SCRIPT.parent.parent
        flake_text = (root / "flake.nix").read_text()
        self.assertNotIn("git+file:", flake_text)
        self.assertNotRegex(flake_text, r"file:///|path:/")

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
            for input_name, reference in (nodes.get(name, {}).get("inputs") or {}).items():
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


    # ---- production source-coordinate completeness gate ----------------
    #
    # Issue #25 (DoD item 3): every production Internet source coordinate must
    # be catalog-owned (sources/*.json, resolved as `<fetcher> X.source.args`)
    # or a validated flake-declaration projection -- never a bare fetch literal
    # inlined into a package body. The catalog LOADER already validates records
    # it is given (load_source_catalog / _validate_fetch_record); what it cannot
    # see is a NEW inline literal that never became a record. This walks the
    # production seams and rejects exactly that, with an EXACT-SET allowlist so a
    # stale exception fails as loudly as a new leak (as with
    # KNOWN_UNFETCHABLE_ROOT_NODES above).

    # Production seams: flake.nix plus every .nix under these roots. `test`/
    # `tests` path components are excluded because fixtures are not production;
    # doc/ and the top-level test/ tree are simply not roots. sources/*.json is
    # catalog DATA, not a seam.
    _SEAM_ROOTS = ("overlays", "packages", "config", "flake")

    # Fetchers whose inline argument attrset is a package-source coordinate.
    # Bare and qualified (prev./final./pkgs./builtins.) call forms are both
    # recognized, so a catalog bypass cannot hide behind a `prev.` prefix.
    # builtins.fetchTree/fetchGit/fetchTarball are here because a pinned flake
    # or tarball URL is a source coordinate too. Deliberately NOT covered, and
    # why: fetchNpmDeps / npmDepsHash / cargoHash / vendorHash (dependency-hash
    # mechanisms, not the `src` coordinate); bare filesystem `src = /path`
    # literals and flake INPUT locators (owned by the external-filesystem and
    # whole-closure purity checks above -- one mechanism, per cross-stream X4);
    # and arbitrary URL strings that are not a fetcher argument (runtime/service
    # endpoints, lockfile-patch strings) -- see the runtime-URL positive control.
    _FETCHERS = (
        "fetchFromGitHub", "fetchFromGitLab", "fetchFromGitiles", "fetchgit",
        "fetchurl", "fetchzip", "fetchpatch", "fetchPypi", "fetchTree",
        "fetchTarball", "fetchCrate", "fetchsvn", "fetchhg", "fetchGit",
    )
    _FETCH_TOKEN = re.compile(
        r"(?<![\w\"'])(?:[A-Za-z_][\w'-]*\.)?(" + "|".join(_FETCHERS) + r")\b"
    )
    # A coordinate field bound to a string literal (also the first element of a
    # `urls = [ "..." ]` list). Its presence in an inline `{ .. }` is what makes
    # the attrset a literal source coordinate rather than a reference.
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

    # Root flake inputs whose coordinate is neither a fetchable remote nor a
    # repo-internal path. Empty: all current inputs are github:/git+ssh:/path:.
    KNOWN_UNCLASSIFIED_FLAKE_INPUTS: dict[str, str] = {}

    @staticmethod
    def _mask_nix(text):
        """Blank comment and string bytes, preserving length and newlines.

        Structural scans run on the mask so a fetcher name or brace inside a
        comment or string literal is invisible. Line comments (#..), block
        comments (/* */), double-quoted ("..") and Nix indented ('' .. '')
        strings are handled. Antiquotation (${..}) inside a string is blanked
        whole rather than re-entered as code -- a conservative limitation;
        fetchers are never invoked inside string antiquotation in this tree.
        """
        out = list(text)
        i, n = 0, len(text)
        while i < n:
            c = text[i]
            two = text[i:i + 2]
            if c == "#":
                while i < n and text[i] != "\n":
                    out[i] = " "
                    i += 1
                continue
            if two == "/*":
                while i < n and text[i:i + 2] != "*/":
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
                    if text[i:i + 2] == "''":
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
        """Index just past the '}' matching the '{' at open_idx, in the mask."""
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

        Returns [(line, fetcher, locator)]. A hit is a fetcher applied directly
        to an inline `{ .. }` that binds a coordinate field to a string literal.
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
            block = text[j:cls._match_brace(mask, j)]
            coord = cls._COORD_FIELD.search(block)
            if not coord:
                continue
            owner = re.search(r'\bowner\s*=\s*"([^"]*)"', block)
            repo = re.search(r'\brepo\s*=\s*"([^"]*)"', block)
            if owner and repo:
                locator = f"{owner.group(1)}/{repo.group(1)}"
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

    @staticmethod
    def _classify_flake_input_url(url):
        """Classify a flake input coordinate.

        repo-internal-path : path:./x or path:x (repo-local)      -> allowed
        external-filesystem: path:/abs, file://, git+file://       -> reject
        remote             : github:/git+ssh:/git+https:/https:... -> allowed
        unknown            : anything else                         -> reject
        """
        if url.startswith("git+file:") or url.startswith("file:"):
            return "external-filesystem"
        if url.startswith("path:"):
            rest = url[len("path:"):]
            return "external-filesystem" if rest.startswith("/") else "repo-internal-path"
        if re.match(r"[a-z][a-z0-9+.-]*:", url):
            return "remote"
        return "unknown"

    def test_production_seams_have_no_undeclared_inline_source_coordinates(self):
        """No production .nix body inlines a fetch coordinate off-catalog.

        Named for what it proves: every fetcher in a production seam is either
        applied to a catalog record (`<fetcher> X.source.args`) or listed, with a
        reason and owning issue, in KNOWN_INLINE_SOURCE_LITERALS. It does NOT
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
        """Negative fixture per source kind + positive controls.

        Each undeclared inline literal is flagged; each sanctioned form
        (catalog-resolved application, commented-out fetcher, a `fetcher ==
        "..."` string, and a runtime/service URL that is not a fetcher argument)
        is not -- the gate does not confuse runtime endpoints with sources.
        """
        header = "final: prev: {\n  broken = prev.stdenv.mkDerivation {\n    "
        footer = "\n  };\n}\n"
        rejected = {
            "fetchFromGitHub":
                'src = prev.fetchFromGitHub {\n      owner = "evil";\n'
                '      repo = "sneak"; rev = "v1"; hash = "sha256-A";\n    };',
            "fetchgit":
                'src = fetchgit {\n      url = "https://x.invalid/r.git";\n'
                '      rev = "abc"; hash = "sha256-B";\n    };',
            "fetchurl":
                'src = fetchurl {\n      url = "https://x.invalid/a.tar.gz";\n'
                '      hash = "sha256-C";\n    };',
            "fetchzip":
                'src = fetchzip {\n      url = "https://x.invalid/a.zip";\n'
                '      hash = "sha256-D";\n    };',
            "fetchpatch":
                'p = fetchpatch {\n      url = "https://x.invalid/p.patch";\n'
                '      hash = "sha256-E";\n    };',
            "fetchPypi":
                'src = fetchPypi {\n      pname = "evil"; version = "1.0";\n'
                '      hash = "sha256-F";\n    };',
            "fetchTree (pinned flake URL)":
                'src = builtins.fetchTree {\n      type = "github";\n'
                '      owner = "evil"; repo = "flake"; rev = "dead";\n    };',
        }
        for kind, body in rejected.items():
            with self.subTest(reject=kind):
                hits = self._inline_fetcher_offenders(header + body + footer)
                self.assertEqual(len(hits), 1, hits)
        allowed = {
            "catalog-resolved":
                "src = prev.fetchFromGitHub sources.foo.source.args;",
            "catalog-resolved-paren":
                'src = prev.fetchFromGitHub (sourceArgs "fetchFromGitHub" n);',
            "commented-out":
                '# src = fetchFromGitHub { owner = "a"; repo = "b"; };',
            "block-commented":
                '/* src = fetchurl { url = "https://x"; hash = "y"; }; */',
            "fetcher-string-compare":
                'assert source.source.fetcher == "fetchFromGitHub";',
            "runtime-service-url":
                'services.x.endpoint = "https://api.example.com/v1";',
            "lockfile-patch-url":
                'substituteInPlace lock --replace-fail '
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

    def test_flake_input_coordinates_are_internal_or_declared(self):
        """Flake input coordinates are repo-internal paths or fetchable remotes.

        Confirms the allowed classes the gate must tolerate (issue #25): the
        repo-internal path inputs and the stock-trader git+ssh remote. Synthetic
        filesystem coordinates are rejected. This complements -- does not
        duplicate -- test_root_inputs_do_not_reference_external_filesystems and
        the whole-closure purity walk, which own the lock/text leak dimension.
        """
        root = SCRIPT.parent.parent
        rejected = {}
        for rel in ("flake.nix", "config/ai/flake.nix"):
            text = (root / rel).read_text()
            for url in re.findall(r'\burl\s*=\s*"([^"]*)"', text):
                kind = self._classify_flake_input_url(url)
                if kind not in ("remote", "repo-internal-path"):
                    rejected[f"{rel}: {url}"] = kind
        self.assertEqual(
            set(rejected),
            set(self.KNOWN_UNCLASSIFIED_FLAKE_INPUTS),
            "flake input coordinate classification changed: %s" % rejected,
        )
        classify = self._classify_flake_input_url
        self.assertEqual(classify("path:./config/ai"), "repo-internal-path")
        self.assertEqual(classify("path:./config/certs"), "repo-internal-path")
        self.assertEqual(
            classify("git+ssh://gitea/johnw/stock-trader.git?rev=51d789"),
            "remote",
        )
        self.assertEqual(classify("github:owner/repo/deadbeef"), "remote")
        for bad in (
            "git+file:///Users/johnw/src/x",
            "path:/Users/johnw/src/x",
            "file:///tmp/x",
        ):
            with self.subTest(bad=bad):
                self.assertEqual(classify(bad), "external-filesystem")
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
                node_name = reference if isinstance(reference, str) else follow_node(lock, reference)
            return node_name

        def canonical_reference(lock, reference):
            name = reference if isinstance(reference, str) else follow_node(lock, reference)
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
        self.assertNotEqual(root_graph, canonical_inputs(drifted, drifted["nodes"]["root"]))

        root_flake = (root / "flake.nix").read_text()
        self.assertIn('nix-config-ai.url = "path:./config/ai"', root_flake)
        self.assertNotIn("agent-browser-source = {", root_flake)

    def test_profile_symlinked_scripts_find_packaged_routing_library(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            closure_bin = root / "nix-scripts/bin"
            closure_lib = root / "nix-scripts/libexec/nix-scripts"
            home_manager_bin = root / "home-manager-path/bin"
            profile_bin = root / "profile/bin"
            fake_bin = root / "fake-bin"
            for directory in (
                closure_bin,
                closure_lib,
                home_manager_bin,
                profile_bin,
                fake_bin,
            ):
                directory.mkdir(parents=True)
            (fake_bin / "bash").symlink_to(shutil.which("bash") or "/bin/bash")

            shutil.copy2(SCRIPT.parent / "lib/host-routing.sh", closure_lib)
            shutil.copy2(UPGRADE_PROJECTS, closure_bin)
            for source in (SWITCH, UPGRADE, UPDATE_AGENTS):
                target = closure_bin / source.name
                shutil.copy2(source, target)
                packaged = target.read_text()
                self.assertEqual(packaged.count("installed_routing_path="), 1)
                packaged = packaged.replace(
                    "installed_routing_path=",
                    f"installed_routing_path={closure_lib / 'host-routing.sh'}",
                )
                if source == UPGRADE:
                    self.assertEqual(packaged.count("installed_upgrade_projects="), 1)
                    packaged = packaged.replace(
                        "installed_upgrade_projects=",
                        f"installed_upgrade_projects={closure_bin / 'upgrade-projects'}",
                    )
                target.write_text(packaged)
                (home_manager_bin / source.name).symlink_to(target)
                (profile_bin / source.name).symlink_to(
                    Path("../../home-manager-path/bin") / source.name
                )

            def executable(name, text):
                path = fake_bin / name
                path.write_text(text)
                path.chmod(0o755)

            executable("hostname", "#!/bin/sh\nprintf 'hera\\n'\n")
            executable("uname", "#!/bin/sh\nprintf 'Darwin\\n'\n")
            executable(
                "u",
                '#!/bin/sh\nprintf "%s\\n" "$*" >"$PROFILE_TEST_LOG"\n',
            )
            log = root / "u.log"
            environment = {
                **os.environ,
                "HOME": str(root),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "PROFILE_TEST_LOG": str(log),
            }

            switched = subprocess.run(
                [str(profile_bin / "switch")],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(switched.returncode, 0, switched.stderr)
            self.assertEqual(log.read_text(), "switch\n")

            update_help = subprocess.run(
                [str(profile_bin / "update-agents"), "--help"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(update_help.returncode, 0, update_help.stderr)
            self.assertIn("usage: update-agents", update_help.stdout)

            conflict = subprocess.run(
                [str(profile_bin / "upgrade"), "--host-only", "--projects-only"],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )
            self.assertEqual(conflict.returncode, 2, conflict.stderr)
            self.assertIn("mutually exclusive", conflict.stderr)

    def test_host_routing_table_covers_system_and_shared_consumers(self):
        routing = SCRIPT.parent / "lib" / "host-routing.sh"
        result = subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; normalize_nix_host Andoria-08; '
                'nix_flake_output_for_host vps; nix_flake_output_for_host vulcan',
                "host-routing-test",
                str(routing),
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertEqual(result.stdout.splitlines(), ["shared-work", "ovh-vps", "vulcan"])

        # Every one of the eight fleet hosts must route to a switch target. The
        # table used to normalize all eight but resolve an output for only four,
        # so the shared-work group fell through to `return 1` and bin/switch
        # silently used a floating `home-manager/master` instead.
        #
        # shared-work resolves to `jwiegley`, unqualified — the attribute the work
        # machines' own ~/.config/home-manager flake exports (confirmed live on
        # andoria-08). Not `jwiegley@x86_64-linux`, which is this repo's synthetic
        # CI fixture pinned to hostname="linux".
        every_host = [
            "hera",
            "clio",
            "vulcan",
            "vps",
            "andoria-08",
            "andoria-t2",
            "delphi-3bd4",
            "gpu-server",
        ]
        routed = subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; shift; for h in "$@"; do '
                'nix_flake_output_for_host "$h" || { echo "UNROUTED:$h"; exit 1; }; done',
                "host-routing-test",
                str(routing),
                *every_host,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(
            routed.returncode,
            0,
            "a fleet host has no switch target: %s%s" % (routed.stdout, routed.stderr),
        )
        self.assertEqual(
            routed.stdout.splitlines(),
            [
                "hera",
                "clio",
                "vulcan",
                "ovh-vps",
                "jwiegley",
                "jwiegley",
                "jwiegley",
                "jwiegley",
            ],
        )

        # Normalization must be IDEMPOTENT, because nix_flake_output_for_host
        # normalizes its argument and bin/switch passes a value it already
        # normalized. hera/clio/vulcan/vps survived a second pass only by
        # accident of their glob patterns; shared-work did not, so bin/switch
        # failed for every work machine. Testing the function with raw hostnames
        # (above) cannot catch that — this exercises the real call path.
        idempotent = subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; shift; for h in "$@"; do '
                'once=$(normalize_nix_host "$h") || { echo "UNNORM:$h"; exit 1; }; '
                'twice=$(normalize_nix_host "$once") || { echo "NOTIDEMPOTENT:$once"; exit 1; }; '
                '[ "$once" = "$twice" ] || { echo "DRIFT:$once->$twice"; exit 1; }; '
                'nix_flake_output_for_host "$once" >/dev/null || '
                '{ echo "UNROUTED-AFTER-NORMALIZE:$once"; exit 1; }; done',
                "host-routing-test",
                str(routing),
                *every_host,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(
            idempotent.returncode,
            0,
            "normalization is not idempotent, or a normalized label does not "
            "route: %s%s" % (idempotent.stdout, idempotent.stderr),
        )

        # And an unknown host must still be refused rather than silently routed to
        # a default. The positive case above cannot show this: every one of the
        # eight resolves, so the failure branch is never taken.
        unknown = subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; nix_flake_output_for_host "$2"',
                "host-routing-test",
                str(routing),
                "definitely-not-a-fleet-host",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(
            unknown.returncode, 0, "an unknown host was routed instead of refused"
        )
        self.assertEqual(unknown.stdout, "")

        minimal_env = {**os.environ, "PATH": "/usr/bin:/bin"}
        build_help = subprocess.run(
            [str(BUILD), "--help"], capture_output=True, text=True, env=minimal_env, check=False
        )
        self.assertEqual(build_help.returncode, 0, build_help.stderr)
        self.assertIn("Usage: ./build", build_help.stdout)
        conflict = subprocess.run(
            [str(UPGRADE), "--host-only", "--projects-only"],
            capture_output=True,
            text=True,
            env=minimal_env,
            check=False,
        )
        self.assertEqual(conflict.returncode, 2)
        self.assertIn("mutually exclusive", conflict.stderr)

    def test_independent_ai_packages_are_owned_under_packages(self):
        root = SCRIPT.parent.parent
        ownership = {
            "30-ai-mcp.nix": ("ai-mcp.nix", ["pal-mcp-server", "rustdocs-mcp-server"]),
            "30-ai-python.nix": ("ai-python-extensions.nix", []),
            "30-ai-llm.nix": ("ai-llm.nix", ["aiperf", "guidellm", "omlx"]),
        }
        for overlay_name, (package_name, package_names) in ownership.items():
            overlay = (root / "overlays/ai" / overlay_name).read_text()
            package = (root / "packages" / package_name).read_text()
            self.assertIn(f"packages/{package_name}", overlay)
            for name in package_names:
                with self.subTest(overlay=overlay_name, package=name):
                    self.assertIn(f'pname = "{name}"', package)
                    self.assertNotIn(f'pname = "{name}"', overlay)

        python_overlay = (root / "overlays/ai/30-ai-python.nix").read_text()
        python_packages = (root / "packages/ai-python-extensions.nix").read_text()
        llm_mlx_package = (root / "packages/llm-mlx.nix").read_text()
        self.assertIn("./llm-mlx.nix", python_packages)
        self.assertIn('pname = "llm-mlx"', llm_mlx_package)
        self.assertNotIn('pname = "llm-mlx"', python_overlay)
        for name in (
            "mlx-speech",
            "mlx-embeddings",
            "dflash-mlx",
            "pyloudnorm",
            "phonemizer-fork",
            "espeakng-loader",
            "cohere-melody",
            "mlx-audio",
            "standard-distutils",
            "aiologic",
            "culsans",
        ):
            with self.subTest(overlay="30-ai-python.nix", package=name):
                self.assertIn(f'pname = "{name}"', python_packages)
                self.assertNotIn(f'pname = "{name}"', python_overlay)


if __name__ == "__main__":
    unittest.main()
