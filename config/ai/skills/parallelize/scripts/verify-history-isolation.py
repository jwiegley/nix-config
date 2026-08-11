#!/usr/bin/env python3
"""Verify the behavioral probe for a no-parent-history dispatch."""

from pathlib import Path
import json
import re
import sys
from typing import Any


ABSENT = "PARENT_HISTORY_ABSENT"
SENTINEL = re.compile(r"^PARENT_HISTORY_SENTINEL=[A-Za-z0-9_-]{16,}$")


def response_text(value: Any) -> str:
    if isinstance(value, str):
        try:
            return response_text(json.loads(value))
        except json.JSONDecodeError:
            return value
    if isinstance(value, dict) and isinstance(value.get("status"), str):
        if value["status"] not in {"success", "continuation_available"}:
            raise ValueError(f"PAL response status is {value['status']!r}")
        content = value.get("content")
        if isinstance(content, str):
            return content
    if isinstance(value, dict):
        structured = value.get("structuredContent")
        if structured is not None:
            return response_text(structured)

        content = value.get("content")
        if isinstance(content, list):
            candidates = [
                response_text(item["text"])
                for item in content
                if isinstance(item, dict)
                and item.get("type") == "text"
                and isinstance(item.get("text"), str)
            ]
            if len(candidates) == 1:
                return candidates[0]
    raise ValueError("response is neither plain text nor one PAL ToolOutput")


def main() -> int:
    if len(sys.argv) != 3:
        print(
            f"usage: {Path(sys.argv[0]).name} PARENT_HISTORY_SENTINEL=VALUE RESPONSE_FILE",
            file=sys.stderr,
        )
        return 64

    sentinel, response_path = sys.argv[1:]
    if SENTINEL.fullmatch(sentinel) is None:
        print("invalid parent-history sentinel", file=sys.stderr)
        return 64

    try:
        response = response_text(
            Path(response_path).read_text(encoding="utf-8").strip()
        ).strip()
    except (OSError, ValueError) as error:
        print(f"cannot read probe response: {error}", file=sys.stderr)
        return 1
    if response != ABSENT:
        print(
            "no-history dispatch probe failed: child did not return the exact absence marker",
            file=sys.stderr,
        )
        return 1

    print(ABSENT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
