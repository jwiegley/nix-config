#!/usr/bin/env python3
"""
Validate Node-RED flow JSON structure.
Usage: python validate_flow.py <flow.json>
"""

import json
import sys


def validate_flow(flow_path):
    """Validate a Node-RED flow file for common issues."""
    try:
        with open(flow_path) as f:
            flow_data = json.load(f)
    except json.JSONDecodeError as e:
        return False, f"Invalid JSON: {e}"
    except FileNotFoundError:
        return False, f"File not found: {flow_path}"

    if not isinstance(flow_data, list):
        return False, "Flow must be a JSON array"

    errors = []
    warnings = []

    # Collect all node IDs and container IDs (tabs and subflow definitions)
    node_ids = set()
    container_ids = set()

    for node in flow_data:
        if "id" not in node:
            errors.append(f"Node missing 'id' field: {node.get('name', 'unnamed')}")
            continue

        node_id = node["id"]
        if node_id in node_ids:
            errors.append(f"Duplicate node ID: {node_id}")
        node_ids.add(node_id)

        if node.get("type") in ("tab", "subflow"):
            container_ids.add(node_id)

    # Validate node properties and wiring
    for node in flow_data:
        node_id = node.get("id", "unknown")
        node_type = node.get("type", "unknown")

        # Skip container definitions (tabs and subflow definitions)
        if node_type in ("tab", "subflow"):
            continue

        # Check required fields for non-container nodes
        if "type" not in node:
            errors.append(f"Node {node_id} missing 'type' field")

        # Definition nodes (config nodes) have no canvas coordinates; they
        # legitimately omit 'z' (global scope) and x/y.
        is_definition = "x" not in node and "y" not in node

        if "z" not in node:
            if not is_definition:
                errors.append(
                    f"Node {node_id} missing 'z' field (tab/subflow reference)"
                )
        elif node.get("z") and node["z"] not in container_ids:
            errors.append(
                f"Node {node_id} references non-existent tab/subflow: {node['z']}"
            )

        # Validate wires
        if "wires" in node:
            if not isinstance(node["wires"], list):
                errors.append(f"Node {node_id}: 'wires' must be an array")
            else:
                for output_idx, output_wires in enumerate(node["wires"]):
                    if not isinstance(output_wires, list):
                        errors.append(
                            f"Node {node_id}: wires[{output_idx}] must be an array"
                        )
                    else:
                        for wire_id in output_wires:
                            if wire_id not in node_ids:
                                errors.append(
                                    f"Node {node_id} wires to non-existent"
                                    f" node: {wire_id}"
                                )

        # Check coordinates (definition nodes have none by design)
        if not is_definition and ("x" not in node or "y" not in node):
            warnings.append(f"Node {node_id} missing coordinates (x, y)")

        # Validate function nodes
        if node_type == "function" and "func" in node:
            func_code = node["func"]
            if not func_code:
                warnings.append(f"Function node {node_id} has empty code")

    # Report results
    if errors:
        print("ERRORS found:")
        for error in errors:
            print(f"  ✗ {error}")

    if warnings:
        print("\nWARNINGS:")
        for warning in warnings:
            print(f"  ⚠ {warning}")

    if not errors and not warnings:
        print(f"✓ Flow is valid ({len(flow_data)} nodes)")
        return True, "Valid"

    return len(errors) == 0, f"{len(errors)} errors, {len(warnings)} warnings"


def main():
    if len(sys.argv) != 2:
        print("Usage: python validate_flow.py <flow.json>")
        sys.exit(1)

    is_valid, _message = validate_flow(sys.argv[1])
    if not is_valid:
        sys.exit(1)


if __name__ == "__main__":
    main()
