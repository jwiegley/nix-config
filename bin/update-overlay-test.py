#!/usr/bin/env python3

import runpy
import tempfile
import unittest
from pathlib import Path


MODULE = runpy.run_path(Path(__file__).with_name("update-overlay"))
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


if __name__ == "__main__":
    unittest.main()
