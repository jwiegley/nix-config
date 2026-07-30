#!/usr/bin/env python3

import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).parent.parent / "packages/pi-mcp-adapter-normalize.py"
SPEC = importlib.util.spec_from_file_location("pi_mcp_adapter_normalize", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class NormalizeStatusTests(unittest.TestCase):
    def test_legacy_status_is_compacted(self):
        source = f"before\n{MODULE.LEGACY_STATUS}\nafter\n"
        result = MODULE.normalize_status(source)
        self.assertIn(MODULE.COMPACT_LEGACY_STATUS, result)
        self.assertNotIn(MODULE.LEGACY_STATUS, result)

    def test_modern_status_is_compacted_without_dropping_disabled_count(self):
        source = (
            f"before\n{MODULE.MODERN_STATUS}\n"
            "  if (disabledCount > 0) status += ` (${disabledCount} disabled)`;\n"
            "  const formattedStatus = formatMcpStatus(state.config, status);\n"
        )
        result = MODULE.normalize_status(source)
        self.assertIn(MODULE.COMPACT_MODERN_STATUS, result)
        self.assertNotIn(MODULE.MODERN_STATUS, result)
        self.assertIn("disabledCount", result)
        self.assertIn("formatMcpStatus(state.config, status)", result)

    def test_unknown_or_ambiguous_status_is_rejected(self):
        for source in ("no status\n", f"{MODULE.LEGACY_STATUS}\n{MODULE.MODERN_STATUS}\n"):
            with self.subTest(source=source), self.assertRaisesRegex(
                RuntimeError, "exactly one known shape"
            ):
                MODULE.normalize_status(source)


if __name__ == "__main__":
    unittest.main()
