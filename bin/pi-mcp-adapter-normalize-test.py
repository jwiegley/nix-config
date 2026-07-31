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
        legacy = "  let status = `🔌 MCP: ${connectedCount}/${enabledCount} servers`;"
        compact = "  let status = `🔌 MCP: ${connectedCount}/${enabledCount}`;"
        source = f"before\n{legacy}\nafter\n"
        result = MODULE.normalize_status(source)
        self.assertIn(compact, result)
        self.assertNotIn(legacy, result)

    def test_modern_status_is_compacted_without_dropping_disabled_count(self):
        modern = (
            '  let status = `${enabledCount} ${enabledCount === 1 ? "server" : '
            '"servers"} enabled`;\n'
            '  if (connectedCount > 0) status += ` (${connectedCount} connected)`;'
        )
        compact = "  let status = `${connectedCount}/${enabledCount}`;"
        source = (
            f"before\n{modern}\n"
            "  if (disabledCount > 0) status += ` (${disabledCount} disabled)`;\n"
            "  const formattedStatus = formatMcpStatus(state.config, status);\n"
        )
        result = MODULE.normalize_status(source)
        self.assertIn(compact, result)
        self.assertNotIn(modern, result)
        self.assertIn("disabledCount", result)
        self.assertIn("formatMcpStatus(state.config, status)", result)

    def test_native_compact_setting_needs_no_patch(self):
        source = (
            'const footerStatus = state.config.settings?.mcpFooterStatus ?? "full";\n'
            'const status = footerStatus === "compact" ? "compact" : "full";\n'
        )
        self.assertEqual(MODULE.normalize_status(source), source)

    def test_unknown_or_ambiguous_status_is_rejected(self):
        legacy = "  let status = `🔌 MCP: ${connectedCount}/${enabledCount} servers`;"
        modern = (
            '  let status = `${enabledCount} ${enabledCount === 1 ? "server" : '
            '"servers"} enabled`;\n'
            '  if (connectedCount > 0) status += ` (${connectedCount} connected)`;'
        )
        native = 'state.config.settings?.mcpFooterStatus ?? "full"'
        for source in ("no status\n", f"{legacy}\n{modern}\n", f"{legacy}\n{native}\n"):
            with self.subTest(source=source), self.assertRaisesRegex(
                RuntimeError, "exactly one known shape"
            ):
                MODULE.normalize_status(source)


if __name__ == "__main__":
    unittest.main()
