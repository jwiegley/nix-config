#!/usr/bin/env python3
"""List the local git+file flake inputs recorded in flake.lock.

One walker, two projections, so the Makefile's verify-inputs and lock-local
targets cannot drift apart on what counts as a local git input:

  names  print one root input name per line
  repos  print "<has_submodules>\t<repo_path>" per input (file:// stripped)
"""

import json
import sys


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {"names", "repos"}:
        print("usage: local-git-inputs.py {names|repos}", file=sys.stderr)
        return 2
    with open("flake.lock", encoding="utf-8") as handle:
        nodes = json.load(handle)["nodes"]

    for name, key in nodes["root"]["inputs"].items():
        node = nodes.get(key if isinstance(key, str) else name, {})
        locked = node.get("locked", {})
        if locked.get("type") != "git" or "file://" not in locked.get("url", ""):
            continue
        if sys.argv[1] == "names":
            print(name)
        else:
            has_submodules = int(bool(locked.get("submodules", False)))
            repo = locked.get("url", "").replace("file://", "")
            print(f"{has_submodules}\t{repo}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
