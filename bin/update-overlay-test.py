#!/usr/bin/env python3

import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("update-overlay")
MODULE = runpy.run_path(SCRIPT)
OverlayParser = MODULE["OverlayParser"]
OverlayUpdater = MODULE["OverlayUpdater"]

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

        self.assertIn("nix flake update\n", update_agents)
        self.assertIn("nix flake update --flake ./config/ai", update_agents)
        self.assertIn("python bin/update-overlay --all", update_agents)
        self.assertEqual(update_agents.count('git_pull_clean "$config_dir"'), 1)
        self.assertNotIn("commit_and_push_if_changed", update_agents)


if __name__ == "__main__":
    unittest.main()
