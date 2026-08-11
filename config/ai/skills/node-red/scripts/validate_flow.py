#!/usr/bin/env python3
"""Validate a complete Node-RED flow array or selected-flow edit envelope."""

import json
import re
import sys
from pathlib import Path


MAX_ENVELOPE_BYTES = 1024 * 1024
FLOW_ID_RE = re.compile(r"[0-9a-f]{1,32}(?:\.[0-9a-f]{1,32})?\Z")
DIGEST_RE = re.compile(r"sha256:[0-9a-f]{64}\Z")


class StrictJSONError(ValueError):
    """A JSON construct that the admin helper also rejects."""


def _strict_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise StrictJSONError(f"duplicate object key {key!r}")
        result[key] = value
    return result


def _reject_constant(value):
    raise StrictJSONError(f"non-finite number {value}")


def _read_json(flow_path):
    try:
        raw = Path(flow_path).read_bytes()
        data = json.loads(
            raw,
            object_pairs_hook=_strict_object,
            parse_constant=_reject_constant,
        )
    except FileNotFoundError:
        return None, 0, f"File not found: {flow_path}"
    except OSError as error:
        return None, 0, f"Cannot read file: {error}"
    except (ValueError, RecursionError) as error:
        return None, 0, f"Invalid JSON: {error}"
    return data, len(raw), None


def _selected_flow_nodes(data, raw_size):
    errors = []
    expected_keys = {"baseDigest", "flow"}
    actual_keys = set(data)
    if actual_keys != expected_keys:
        missing = sorted(expected_keys - actual_keys)
        unexpected = sorted(actual_keys - expected_keys)
        if missing:
            errors.append(f"Envelope missing keys: {', '.join(missing)}")
        if unexpected:
            errors.append(f"Envelope has unexpected keys: {', '.join(unexpected)}")

    digest = data.get("baseDigest")
    if not isinstance(digest, str) or DIGEST_RE.fullmatch(digest) is None:
        errors.append("Envelope baseDigest must match sha256:<64 lowercase hex>")

    flow = data.get("flow")
    if not isinstance(flow, dict):
        errors.append("Envelope flow must be a JSON object")
        return [], set(), set(), errors, "Selected flow envelope"

    flow_id = flow.get("id")
    if not isinstance(flow_id, str) or FLOW_ID_RE.fullmatch(flow_id) is None:
        errors.append("Selected flow id has invalid format")

    nodes = flow.get("nodes")
    configs = flow.get("configs", [])
    if not isinstance(nodes, list):
        errors.append("Selected flow nodes must be an array")
        nodes = []
    if not isinstance(configs, list):
        errors.append("Selected flow configs, when present, must be an array")
        configs = []

    try:
        normalized_size = len(
            json.dumps(
                data,
                ensure_ascii=True,
                allow_nan=False,
                separators=(",", ":"),
            ).encode("ascii")
        )
    except (ValueError, RecursionError) as error:
        errors.append(f"Envelope cannot be normalized: {error}")
        normalized_size = MAX_ENVELOPE_BYTES + 1

    if raw_size > MAX_ENVELOPE_BYTES:
        errors.append("Envelope raw input exceeds 1 MiB")
    if normalized_size > MAX_ENVELOPE_BYTES:
        errors.append("Envelope normalized input exceeds 1 MiB")

    combined = nodes + configs
    definition_indexes = set(range(len(nodes), len(combined)))
    container_ids = {flow_id} if isinstance(flow_id, str) else set()
    return combined, container_ids, definition_indexes, errors, "Selected flow envelope"


def _validation_target(data, raw_size):
    if isinstance(data, list):
        return data, set(), None, [], "Flow"
    if isinstance(data, dict):
        return _selected_flow_nodes(data, raw_size)
    return (
        [],
        set(),
        set(),
        ["Input must be a flow array or selected-flow envelope"],
        "Flow",
    )


def _validate_nodes(nodes, container_ids, definition_indexes):
    errors = []
    warnings = []
    seen_ids = set(container_ids)
    all_containers = set(container_ids)
    wire_target_ids = set()

    for index, node in enumerate(nodes):
        if not isinstance(node, dict):
            errors.append(f"Node at index {index} must be a JSON object")
            continue

        node_id = node.get("id")
        if not isinstance(node_id, str) or not node_id:
            errors.append(f"Node at index {index} missing a non-empty string 'id'")
            continue
        if node_id in seen_ids:
            errors.append(f"Duplicate node ID: {node_id}")
        seen_ids.add(node_id)

        if node.get("type") in ("tab", "subflow"):
            all_containers.add(node_id)
        else:
            is_definition = (
                index in definition_indexes
                if definition_indexes is not None
                else "x" not in node and "y" not in node
            )
            if not is_definition:
                wire_target_ids.add(node_id)

    for index, node in enumerate(nodes):
        if not isinstance(node, dict):
            continue

        node_id = (
            node.get("id") if isinstance(node.get("id"), str) else f"index {index}"
        )
        node_type = node.get("type")
        if not isinstance(node_type, str) or not node_type:
            errors.append(f"Node {node_id} missing a non-empty string 'type'")
            node_type = "unknown"

        if node_type in ("tab", "subflow"):
            continue

        is_definition = (
            index in definition_indexes
            if definition_indexes is not None
            else "x" not in node and "y" not in node
        )
        if "z" not in node:
            if not is_definition:
                errors.append(
                    f"Node {node_id} missing 'z' field (tab/subflow reference)"
                )
        elif node["z"]:
            if not isinstance(node["z"], str):
                errors.append(f"Node {node_id}: 'z' must be a string")
            elif node["z"] not in all_containers:
                errors.append(
                    f"Node {node_id} references non-existent tab/subflow: {node['z']}"
                )

        wires = node.get("wires")
        if wires is not None:
            if not isinstance(wires, list):
                errors.append(f"Node {node_id}: 'wires' must be an array")
            else:
                for output_index, output_wires in enumerate(wires):
                    if not isinstance(output_wires, list):
                        errors.append(
                            f"Node {node_id}: wires[{output_index}] must be an array"
                        )
                        continue
                    for wire_id in output_wires:
                        if not isinstance(wire_id, str):
                            errors.append(
                                f"Node {node_id}: wire target must be a string"
                            )
                        elif wire_id not in wire_target_ids:
                            errors.append(
                                f"Node {node_id} wires to non-existent node: {wire_id}"
                            )

        if not is_definition and ("x" not in node or "y" not in node):
            warnings.append(f"Node {node_id} missing coordinates (x, y)")

        if node_type == "function" and "func" in node and not node["func"]:
            warnings.append(f"Function node {node_id} has empty code")

    return errors, warnings


def _report(errors, warnings, target_name, node_count):
    if errors:
        print("ERRORS found:")
        for error in errors:
            print(f"  ✗ {error}")
    if warnings:
        print("\nWARNINGS:")
        for warning in warnings:
            print(f"  ⚠ {warning}")
    if not errors and not warnings:
        print(f"✓ {target_name} is valid ({node_count} nodes)")


def validate_flow(flow_path):
    """Validate a full flow array or a helper-selected flow envelope."""
    data, raw_size, load_error = _read_json(flow_path)
    if load_error:
        print(f"ERROR: {load_error}")
        return False, load_error

    nodes, containers, definitions, shape_errors, target_name = _validation_target(
        data, raw_size
    )
    node_errors, warnings = _validate_nodes(nodes, containers, definitions)
    errors = shape_errors + node_errors
    _report(errors, warnings, target_name, len(nodes))

    if errors:
        return False, f"{len(errors)} errors, {len(warnings)} warnings"
    return True, "Valid" if not warnings else f"0 errors, {len(warnings)} warnings"


def main():
    if len(sys.argv) != 2:
        print("Usage: python validate_flow.py <flow.json>")
        return 1
    is_valid, _message = validate_flow(sys.argv[1])
    return 0 if is_valid else 1


if __name__ == "__main__":
    sys.exit(main())
