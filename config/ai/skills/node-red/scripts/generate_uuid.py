#!/usr/bin/env python3
"""
Generate valid Node-RED node IDs (16 hexadecimal characters).
Usage: python generate_uuid.py [count]
"""

import secrets
import sys


def generate_node_id():
    """Generate a Node-RED compatible ID (16 hex characters)."""
    return secrets.token_hex(8)


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 1

    for i in range(count):
        node_id = generate_node_id()
        if count == 1:
            print(node_id)
        else:
            print(f"ID {i + 1}: {node_id}")


if __name__ == "__main__":
    main()
