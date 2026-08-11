#!/usr/bin/env python3
"""Attest exact model identities from PAL chat response metadata."""

import argparse
import json
from pathlib import Path
import sys
from typing import Any


SUCCESS = {"success", "continuation_available"}


def fail(message: str) -> None:
    raise ValueError(message)


def decode_json(value: Any, source: Path) -> Any:
    if isinstance(value, str):
        try:
            return json.loads(value)
        except json.JSONDecodeError as error:
            fail(f"{source}: response text is not JSON: {error}")
    return value


def tool_output(value: Any, source: Path) -> dict[str, Any]:
    value = decode_json(value, source)
    if isinstance(value, dict) and "status" in value:
        return value

    if isinstance(value, dict):
        structured = value.get("structuredContent")
        if structured is not None:
            try:
                return tool_output(structured, source)
            except ValueError:
                pass

        content = value.get("content")
        if isinstance(content, list):
            candidates = []
            for item in content:
                if (
                    isinstance(item, dict)
                    and item.get("type") == "text"
                    and "text" in item
                ):
                    try:
                        candidates.append(tool_output(item["text"], source))
                    except ValueError:
                        continue
            if len(candidates) == 1:
                return candidates[0]
            if len(candidates) > 1:
                fail(f"{source}: ambiguous PAL tool outputs")

    fail(f"{source}: no PAL ToolOutput JSON found")


def parse_record(specification: str) -> tuple[str, Path]:
    requested, separator, filename = specification.partition("=")
    if not separator or not requested or not filename:
        fail(f"invalid dispatch record {specification!r}; expected MODEL=RESPONSE_FILE")
    return requested, Path(filename)


def attest(specification: str) -> dict[str, str]:
    requested, source = parse_record(specification)
    output = tool_output(json.loads(source.read_text(encoding="utf-8")), source)
    status = output.get("status")
    if status not in SUCCESS:
        fail(f"{source}: PAL chat status is {status!r}, not success")

    metadata = output.get("metadata")
    if not isinstance(metadata, dict):
        fail(f"{source}: PAL chat response has no identity metadata")
    returned = metadata.get("model_used")
    if returned != requested:
        fail(f"{source}: requested {requested!r}, PAL returned {returned!r}")

    record = {"requested_model": requested, "returned_model": returned}
    provider = metadata.get("provider_used")
    if isinstance(provider, str) and provider:
        record["provider"] = provider
    return record


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify exact model identities in PAL chat response files."
    )
    parser.add_argument(
        "--distinct",
        action="store_true",
        help="also require every returned model identity to differ",
    )
    parser.add_argument(
        "--expect",
        action="append",
        required=True,
        metavar="MODEL",
        help="expected requested model; repeat once per required dispatch",
    )
    parser.add_argument("dispatch", nargs="+", metavar="MODEL=RESPONSE_FILE")
    args = parser.parse_args()

    try:
        records = [attest(specification) for specification in args.dispatch]
        requested = [record["requested_model"] for record in records]
        if sorted(requested) != sorted(args.expect):
            fail(
                "dispatch records do not match expected models: "
                f"expected {args.expect!r}, got {requested!r}"
            )
        if args.distinct:
            if len(set(requested)) != len(requested):
                fail("requested model identities are duplicated")
            returned = [record["returned_model"] for record in records]
            if len(records) < 2:
                fail("distinct identity attestation requires at least two dispatches")
            if len(set(returned)) != len(returned):
                fail("returned model identities are not distinct")
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"model dispatch attestation failed: {error}", file=sys.stderr)
        return 1

    json.dump(
        {"dispatches": records, "expected_models": args.expect},
        sys.stdout,
        indent=2,
        sort_keys=True,
    )
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
