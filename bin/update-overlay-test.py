#!/usr/bin/env python3

import contextlib
import io
import json
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("update-overlay")
MODULE = runpy.run_path(str(SCRIPT))
OverlayParser = MODULE["OverlayParser"]
OverlayUpdater = MODULE["OverlayUpdater"]
SourceTransaction = MODULE["SourceTransaction"]
load_update_manifest = MODULE["load_update_manifest"]

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
    def test_manifest_and_cli_inventory_cover_hidden_update_targets(self):
        root = SCRIPT.parent.parent
        try:
            manifest = load_update_manifest(root)
        except (RuntimeError, subprocess.SubprocessError, ValueError) as error:
            self.fail(f"manifest evaluation failed: {error}")
        required = {
            "agent-browser-source",
            "anvil-mcp",
            "bigpowers",
            "pi-artifacts",
            "pi-lens",
            "pi-mcp-adapter",
            "pi-subagentura",
            "pi-web-access",
            "rust-overlay",
        }
        self.assertTrue(required <= manifest.keys())

        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--inventory", "--json"],
            capture_output=True,
            text=True,
            check=False,
            cwd=root,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        inventory = json.loads(result.stdout)
        names = [item["name"] for item in inventory["packages"]]
        self.assertEqual(len(names), len(set(names)))
        self.assertTrue(required <= set(names))
        self.assertTrue(all(item["managed"] for item in inventory["packages"]))
        for item in inventory["packages"]:
            for path in item["files"]:
                self.assertTrue((root / path).is_file(), (item["name"], path))

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
    def test_active_commands_have_one_repository_update_transaction(self):
        root = SCRIPT.parent.parent
        update_agents = (root / "bin" / "update-agents").read_text()
        build = (root / "build").read_text()
        makefile = (root / "Makefile").read_text()
        upgrade = (root / "bin" / "upgrade").read_text()
        active = "\n".join((update_agents, build, makefile, upgrade))

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

        self.assertIn('nix flake update "${ai_inputs[@]}"', update_agents)
        self.assertNotIn("    nix flake update\n", update_agents)
        for required_input in (
            "bigpowers",
            "git-ai",
            "llm-agents",
            "mcp-servers-nix",
            "pi-btw",
            "pi-mcp-adapter",
            "pi-subagentura",
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
            "pi-web-access",
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
        self.assertIn('commit -S -m "$message"', update_agents)
        self.assertIn("--switch/--push require --commit", update_agents)
        self.assertNotIn("git -C \"$repo\" add -A", update_agents)
        self.assertNotIn("commit_and_push_if_changed", update_agents)
        self.assertIn("nix flake update --flake ./config/ai", makefile)


if __name__ == "__main__":
    unittest.main()
