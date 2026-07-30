#!/usr/bin/env python3

import argparse
from pathlib import Path


LEGACY_STATUS = """  let status = `🔌 MCP: ${connectedCount}/${enabledCount} servers`;"""
MODERN_STATUS = """  let status = `${enabledCount} ${enabledCount === 1 ? "server" : "servers"} enabled`;
  if (connectedCount > 0) status += ` (${connectedCount} connected)`;"""
COMPACT_LEGACY_STATUS = """  let status = `🔌 MCP: ${connectedCount}/${enabledCount}`;"""
COMPACT_MODERN_STATUS = """  let status = `${connectedCount}/${enabledCount}`;"""


def normalize_status(text: str) -> str:
    legacy_count = text.count(LEGACY_STATUS)
    modern_count = text.count(MODERN_STATUS)
    if legacy_count + modern_count != 1:
        raise RuntimeError(
            "pi-mcp-adapter status renderer must match exactly one known shape"
        )
    if legacy_count:
        return text.replace(LEGACY_STATUS, COMPACT_LEGACY_STATUS, 1)
    return text.replace(MODERN_STATUS, COMPACT_MODERN_STATUS, 1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    args.path.write_text(normalize_status(args.path.read_text()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
