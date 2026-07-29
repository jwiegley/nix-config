#!/usr/bin/env python3

import contextlib
import copy
import io
import json
import os
import re
import runpy
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace


SCRIPT = Path(__file__).with_name("update-overlay")
UPDATE_AGENTS = Path(__file__).with_name("update-agents")
UPGRADE_PROJECTS = Path(__file__).with_name("upgrade-projects")
UPGRADE = Path(__file__).with_name("upgrade")
BUILD = Path(__file__).parent.parent / "build"
MODULE = runpy.run_path(str(SCRIPT))
OverlayParser = MODULE["OverlayParser"]
OverlayUpdater = MODULE["OverlayUpdater"]
GitHubClient = MODULE["GitHubClient"]
SourceTransaction = MODULE["SourceTransaction"]
load_update_manifest = MODULE["load_update_manifest"]
load_source_catalog = MODULE["load_source_catalog"]
sync_flake_projections = MODULE["sync_flake_projections"]
update_catalog_target = MODULE["update_catalog_target"]
build_inventory = MODULE["build_inventory"]

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
    "pi-openai-server-compaction",
    "pi-quiet",
    "translate-tool",
})

VENDOR_HASH = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="
HELPER_LINE = "  buildGoHelper = prev.buildGoModule.override { go = prev.go; };"
MULTILINE_HELPER = '''  useHelper =
    package:
    package.overrideAttrs (oldAttrs: {
      env = oldAttrs.env or { };
    });'''
OVERLAY = f'''final: prev:
let
{HELPER_LINE}
{MULTILINE_HELPER}
in
{{
  actual = prev.buildGoModule rec {{
    pname = "actual";
    version = "1.0.0";
    src = prev.fetchFromGitHub {{
      owner = "example";
      repo = "actual";
      tag = "v${{version}}";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    }};
    vendorHash = "{VENDOR_HASH}";
  }};
}}
'''


class OverlayParserTests(unittest.TestCase):
    def test_discovers_nested_ai_overlays_but_ignores_test_fixtures(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "ai").mkdir()
            (root / "tests").mkdir()
            (root / "root.nix").write_text(OVERLAY)
            (root / "ai" / "nested.nix").write_text(
                OVERLAY.replace('pname = "actual"', 'pname = "nested"')
                .replace("actual =", "nested =")
            )
            (root / "tests" / "ignored.nix").write_text(
                OVERLAY.replace('pname = "actual"', 'pname = "ignored"')
                .replace("actual =", "ignored =")
            )

            packages = OverlayParser(root).find_all_packages()
            self.assertIn("actual", packages)
            self.assertIn("nested", packages)
            self.assertNotIn("ignored", packages)

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

    def test_let_helper_does_not_absorb_output_packages(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            overlay_path = Path(temp_dir) / "overlay.nix"
            overlay_path.write_text(OVERLAY)

            parser = OverlayParser(Path(temp_dir))
            updater = OverlayUpdater()

            for helper_name, helper_block in (
                ("buildGoHelper", HELPER_LINE),
                ("useHelper", MULTILINE_HELPER),
            ):
                with self.subTest(helper=helper_name):
                    self.assertEqual(
                        parser._extract_package_block(OVERLAY, helper_name),
                        helper_block,
                    )
                    self.assertIsNone(parser.find_package(helper_name))

                    start_idx, end_idx = updater._find_package_block_lines(
                        OVERLAY, helper_name
                    )
                    self.assertEqual(
                        "\n".join(OVERLAY.splitlines()[start_idx : end_idx + 1]),
                        helper_block,
                    )

                    before = overlay_path.read_text()
                    changed = updater.set_dummy_hash(
                        overlay_path, helper_name, "vendorHash", VENDOR_HASH
                    )
                    self.assertFalse(changed)
                    self.assertEqual(overlay_path.read_text(), before)

            self.assertEqual(parser.find_package("actual").version, "1.0.0")


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

    def test_issue34_manifest_records_are_catalog_owned(self):
        root = SCRIPT.parent.parent
        manifest = load_update_manifest(root)
        catalog = load_source_catalog(root)
        self.assertEqual(manifest, {})
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
            {"pi-mcp-adapter", "rust-overlay", "ws"},
        )
        self.assertEqual(
            {name for name in ISSUE34_TARGETS if catalog[name]["_record"]["source"]["fetcher"] == "fetchTree"},
            ISSUE34_FLAKE_PROJECTIONS,
        )
        self.assertEqual(catalog["ws"]["_record"]["source"]["fetcher"], "fetchzip")
        self.assertEqual(catalog["ws"]["_record"]["update"]["package"], "ws")
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
        forged = subprocess.run(
            [sys.executable, str(SCRIPT), "--sync-flake-projections"],
            cwd=SCRIPT.parent.parent,
            capture_output=True,
            text=True,
            env={
                **env,
                "UPDATE_AGENTS_CANDIDATE": "1",
                "GIT_DIR": str(SCRIPT.parent.parent / ".git"),
            },
            check=False,
        )
        self.assertNotEqual(forged.returncode, 0)
        self.assertIn("detached linked worktree", forged.stderr)

    def test_issue34_ws_uses_fetchzip_without_gaining_an_executor(self):
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
            self.assertIsNone(load_source_catalog(root)["ws"]["executor"])
            document["sources"]["ws"]["update"]["package"] = "other"
            (root / "sources/test.json").write_text(json.dumps(document))
            with self.assertRaisesRegex(RuntimeError, "npm source identity"):
                load_source_catalog(root)


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
        finally:
            subprocess.run = real_run

        self.assertEqual(len(calls), 3)
        self.assertIn("releases/latest", calls[0][2])
        self.assertEqual("repos/example/project", calls[1][2])
        self.assertIn("commits/topic", calls[2][2])

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
        finally:
            subprocess.run = real_run

        self.assertEqual(value, "nix32-new")
        self.assertIn("nix-config-ai.inputs.nixpkgs", calls[0][-1])
        self.assertEqual(calls[1][1:3], ["hash", "convert"])

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
                            "fetcher": "fetchurl",
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
                def compute_native_hash(self, _source, _replacements):
                    return "sha512-new"

                def _compute_fod_hash(self, _package, hash_type):
                    self.hash_type = hash_type
                    return "sha256-new"

            transaction = SourceTransaction()
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                status = update_catalog_target(
                    "example",
                    target,
                    SimpleNamespace(version=None, dry_run=False),
                    SimpleNamespace(),
                    FakeNpmClient(),
                    SimpleNamespace(),
                    FakeHashComputer(),
                    transaction,
                )
            transaction.commit()
            record = json.loads(path.read_text())["sources"]["example"]
            self.assertEqual(status, "updated")
            self.assertEqual(record["version"], "2.0.0")
            self.assertEqual(record["source"]["args"]["hash"], "sha512-new")
            self.assertIn("example-2.0.0.tgz", record["source"]["args"]["url"])
            self.assertEqual(record["hashes"]["npmDepsHash"], "sha256-new")

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

    def test_manifest_and_cli_inventory_cover_hidden_update_targets(self):
        root = SCRIPT.parent.parent
        try:
            manifest = load_update_manifest(root)
            self.assertEqual(manifest, {})
            manifest.update(load_source_catalog(root))
        except (RuntimeError, subprocess.SubprocessError, ValueError) as error:
            self.fail(f"manifest evaluation failed: {error}")
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
        self.assertTrue(required <= manifest.keys())
        self.assertIn("packages/pi-gallery/locks/pi-lens-package-lock.json", manifest["pi-lens"]["files"])
        self.assertIn(
            "packages/pi-gallery/locks/pi-smart-fetch-package-lock.json",
            manifest["pi-smart-fetch"]["files"],
        )
        self.assertIn(
            "packages/pi-gallery/locks/pi-smart-web-search-package-lock.json",
            manifest["pi-smart-web-search"]["files"],
        )
        self.assertIn("sources/pi.json", manifest["pi-mcp-adapter"]["files"])
        self.assertNotIn("config/ai/catalog.nix", manifest["pi-mcp-adapter"]["files"])
        self.assertIn("packages/anvil-mcp/Cargo.lock", manifest["nelisp"]["files"])
        self.assertEqual(manifest["ws"]["_record"]["update"]["package"], "ws")

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
        self.assertTrue(required <= set(names))
        self.assertTrue(all(item["inventoried"] for item in inventory["packages"]))
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
        package_owned = {
            item["name"] for item in inventory["packages"] if item["source"] == "packages"
        }
        catalog_owned = {
            item["name"] for item in inventory["packages"] if item["source"] == "catalog"
        }
        pending = {
            "agent-browser-source",
            "betterwright",
            "cohere-melody",
            "cymbal",
            "hf-xet",
            "mlx",
            "nelisp",
            "pi-artifacts",
            "pi-btw",
            "pi-dynamic-workflows",
            "pi-hashline-edit-pro",
            "pi-insights",
            "pi-lens",
            "pi-markdown-preview",
            "pi-mcp-adapter",
            "pi-ponytail",
            "pi-subagents",
            "pi-smart-fetch",
            "pi-smart-web-search",
            "rust-overlay",
            "rtk",
            "sherlock-db",
            "ws",
        }
        self.assertEqual(
            {item["name"] for item in inventory["packages"] if not item["managed"]},
            pending,
        )
        self.assertFalse(package_owned & relocated)
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
        self.assertFalse(by_name["pi-lens"]["managed"])
        self.assertIsNone(by_name["pi-lens"]["executor"])
        for item in inventory["packages"]:
            for path in item["files"]:
                self.assertTrue((root / path).is_file(), (item["name"], path))

    def test_inventory_rejects_duplicate_overlay_owners(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "one.nix").write_text(OVERLAY)
            (root / "two.nix").write_text(OVERLAY)
            source = SimpleNamespace(name="test", parser=OverlayParser(root))
            with self.assertRaisesRegex(RuntimeError, "duplicate overlay owners for actual"):
                build_inventory([source], {}, root)

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

    def test_failed_dependent_hash_rolls_back_complete_update(self):
        class FakeGitHubClient:
            def get_latest_release(self, _owner, _repo):
                return "v2.0.0"

        class FakeHashComputer:
            def __init__(self, _repo_dir):
                pass

            def compute_src_hash(self, _owner, _repo, _rev):
                return "sha256-CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC="

            def compute_vendor_hash(self, _package_name):
                return None

            def compute_cargo_hash(self, _package_name):
                return None

            def compute_npm_deps_hash(self, _package_name):
                return None

        with tempfile.TemporaryDirectory() as temp_dir:
            overlay = Path(temp_dir) / "overlay.nix"
            overlay.write_text(OVERLAY)
            before = overlay.read_text()
            globals_ = MODULE["main"].__globals__
            old_github = globals_["GitHubClient"]
            old_hash = globals_["HashComputer"]
            old_argv = sys.argv
            try:
                globals_["GitHubClient"] = FakeGitHubClient
                globals_["HashComputer"] = FakeHashComputer
                sys.argv = [str(SCRIPT), "--overlays-dir", temp_dir, "actual"]
                with contextlib.redirect_stdout(io.StringIO()):
                    status = MODULE["main"]()
            finally:
                globals_["GitHubClient"] = old_github
                globals_["HashComputer"] = old_hash
                sys.argv = old_argv
            self.assertEqual(status, 1)
            self.assertEqual(overlay.read_text(), before)


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
declared = [
    "tracked.txt", "mode.sh", "binary.bin", "format.nix", "projection.json", "link",
    "regular-to-link", "link-to-regular", "renamed-old.txt", "renamed-new.txt",
    "deleted.txt", "created.txt", "new-directory/generated-lock.json"
]
if "--inventory" in arguments:
    print(json.dumps({
        "schemaVersion": 1,
        "packages": [{
            "name": "fixture",
            "files": declared,
            "inventoried": True,
            "managed": True,
            "executor": "update-overlay",
        }],
        "unsupportedOverlayAttributes": [],
    }))
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
            (root / "overlays/ai/package.nix").write_text(OVERLAY)

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
echo overlay-change >> overlays/ai/package.nix
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
            (root / "overlays/ai/package.nix").write_text(OVERLAY)

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
echo overlay-change >> overlays/ai/package.nix
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
            'nix flake update --flake ./config/ai "${ai_inputs[@]}"', update_agents
        )
        self.assertNotIn("\n    nixpkgs\n", update_agents)
        self.assertNotIn("\n    rust-overlay\n", update_agents)
        for manifest_only in (
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
            with self.subTest(manifest_only=manifest_only):
                self.assertNotIn(f"\n    {manifest_only}\n", update_agents)
        self.assertIn(
            "python bin/update-overlay --all --overlays-dir overlays/ai", update_agents
        )
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
        manifest = load_update_manifest(root)
        manifest.update(load_source_catalog(root))
        expected_inputs = {
            name for name, target in manifest.items()
            if target.get("executor") == "update-agents"
        }
        block = re.search(r"ai_inputs=\((.*?)\n\)", update_agents, re.DOTALL)
        if block is None:
            self.fail("update-agents has no ai_inputs array")
        declared_inputs = {
            line.strip() for line in block.group(1).splitlines() if line.strip()
        }
        self.assertEqual(declared_inputs, expected_inputs)
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
        self.assertIn('exec "$script_dir/upgrade-projects"', upgrade)
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
    # `tests` path components are excluded to match OverlayParser's own
    # production rule (bin/update-overlay:144); doc/ and the top-level test/
    # tree are simply not roots. sources/*.json is catalog DATA, not a seam.
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
