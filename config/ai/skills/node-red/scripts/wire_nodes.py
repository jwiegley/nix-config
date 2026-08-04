#!/usr/bin/env python3
"""
Helper to wire Node-RED nodes together programmatically.
Usage: python wire_nodes.py <flow.json> <source_id> <target_id> [output_port]
"""

import json
import sys


def wire_nodes(flow_path, source_id, target_id, output_port=0):
    """Wire two nodes together in a flow."""
    try:
        with open(flow_path) as f:
            flow_data = json.load(f)
    except (json.JSONDecodeError, FileNotFoundError) as e:
        print(f"Error loading flow: {e}")
        return False

    # Find source node
    source_node = None
    for node in flow_data:
        if node.get("id") == source_id:
            source_node = node
            break

    if not source_node:
        print(f"Source node '{source_id}' not found")
        return False

    # Verify target exists
    target_exists = any(node.get("id") == target_id for node in flow_data)
    if not target_exists:
        print(f"Target node '{target_id}' not found")
        return False

    # Initialize wires if needed
    if "wires" not in source_node:
        source_node["wires"] = []

    # Ensure we have enough output ports
    while len(source_node["wires"]) <= output_port:
        source_node["wires"].append([])

    # Add wire if not already present
    if target_id not in source_node["wires"][output_port]:
        source_node["wires"][output_port].append(target_id)
        print(f"✓ Wired {source_id} (output {output_port}) -> {target_id}")
    else:
        print(f"Wire already exists: {source_id} -> {target_id}")

    # Save the flow
    with open(flow_path, "w") as f:
        json.dump(flow_data, f, indent=2)

    return True


def main():
    if len(sys.argv) < 4:
        print(
            "Usage: python wire_nodes.py"
            " <flow.json> <source_id> <target_id> [output_port]"
        )
        sys.exit(1)

    flow_path = sys.argv[1]
    source_id = sys.argv[2]
    target_id = sys.argv[3]
    output_port = int(sys.argv[4]) if len(sys.argv) > 4 else 0

    success = wire_nodes(flow_path, source_id, target_id, output_port)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
