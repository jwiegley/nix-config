#!/usr/bin/env python3
"""List the local git+file flake inputs recorded in flake.lock.

One walker, two projections, so the Makefile's verify-inputs and lock-local
targets cannot drift apart on what counts as a local git input:

  names  print one canonical root input path per line
  repos  print "<has_submodules>\t<repo_path>" per input (file:// stripped)
"""

import json
import re
import sys
import unicodedata
from urllib.parse import unquote_to_bytes, urlsplit


class LockError(ValueError):
    pass


def mapping(value: object, label: str) -> dict:
    if not isinstance(value, dict):
        raise LockError(f"{label} must be an object")
    return value


def safe_text(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise LockError(f"{label} must be a nonempty string")
    if any(
        unicodedata.category(character) in {"Cc", "Cf", "Cs"} for character in value
    ):
        raise LockError(f"{label} contains control characters")
    return value


def node_inputs(node: dict, label: str) -> dict:
    if "inputs" not in node:
        return {}
    return mapping(node["inputs"], f"{label} inputs")


def load_local_inputs() -> list[tuple[str, bool, str]]:
    with open("flake.lock", encoding="utf-8") as handle:
        lock = mapping(json.load(handle), "flake.lock")

    version = lock.get("version")
    if isinstance(version, bool) or not isinstance(version, int) or version != 7:
        raise LockError("flake.lock version must be 7")
    nodes = mapping(lock.get("nodes"), "flake.lock nodes")
    root_ref = safe_text(lock.get("root"), "flake.lock root reference")
    root = mapping(nodes.get(root_ref), f"root node {root_ref!r}")
    inputs = node_inputs(root, "root")
    local_inputs = []

    def get_node(ref: str, label: str) -> dict:
        node = mapping(nodes.get(ref), label)
        if ref != root_ref:
            mapping(node.get("locked"), f"{label} locked node")
            mapping(node.get("original"), f"{label} original node")
        return node

    def resolve_reference(
        reference: object,
        label: str,
        seen: set[tuple[str, ...]],
        direct_path: tuple[str, ...],
    ) -> tuple[str, tuple[str, ...]]:
        if isinstance(reference, str):
            return safe_text(reference, label), direct_path
        if not isinstance(reference, list):
            raise LockError(f"{label} must be a string or list of strings")
        steps = tuple(
            safe_text(raw_step, f"{label} follows step {index}")
            for index, raw_step in enumerate(reference)
        )
        if steps in seen:
            raise LockError(f"{label} contains a follows cycle")
        seen = seen | {steps}
        current = root_ref
        canonical_path: tuple[str, ...] = ()
        for step in steps:
            current_node = get_node(current, f"follows node {current!r}")
            current_inputs = node_inputs(current_node, f"follows node {current!r}")
            if step not in current_inputs:
                raise LockError(f"{label} follows missing input {step!r}")
            current, canonical_path = resolve_reference(
                current_inputs[step],
                f"{label} follows input {step!r}",
                seen,
                canonical_path + (step,),
            )
        return current, canonical_path

    for raw_name, raw_ref in inputs.items():
        name = safe_text(raw_name, "input name")
        if name.startswith("-"):
            raise LockError(f"input name {name!r} may not begin with '-'")
        ref, canonical_path = resolve_reference(
            raw_ref,
            f"input {name!r} node reference",
            set(),
            (name,),
        )
        if not canonical_path:
            continue
        node = get_node(ref, f"input {name!r} node {ref!r}")
        locked = mapping(node.get("locked"), f"input {name!r} locked node")
        locked_type = safe_text(locked.get("type"), f"input {name!r} locked type")
        submodules = locked.get("submodules", False)
        if not isinstance(submodules, bool):
            raise LockError(f"input {name!r} submodules must be boolean")
        if locked_type != "git":
            continue

        url = safe_text(locked.get("url"), f"input {name!r} git URL")
        try:
            parsed = urlsplit(url)
        except ValueError as error:
            raise LockError(f"input {name!r} has an invalid git URL") from error
        if parsed.scheme not in {"file", "git+file"}:
            continue
        if parsed.netloc not in {"", "localhost"} or parsed.query or parsed.fragment:
            raise LockError(f"input {name!r} has an unsupported file URL")
        if re.search(r"%(?![0-9A-Fa-f]{2})", parsed.path):
            raise LockError(f"input {name!r} has invalid URL escaping")
        try:
            repo = safe_text(
                unquote_to_bytes(parsed.path).decode("utf-8"),
                f"input {name!r} path",
            )
        except UnicodeDecodeError as error:
            raise LockError(f"input {name!r} path is not valid UTF-8") from error
        if not repo.startswith("/") or repo == "/":
            raise LockError(f"input {name!r} path must be an absolute repository path")
        local_inputs.append(("/".join(canonical_path), submodules, repo))

    return local_inputs


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {"names", "repos"}:
        print("usage: local-git-inputs.py {names|repos}", file=sys.stderr)
        return 2
    try:
        local_inputs = load_local_inputs()
    except (OSError, UnicodeError, json.JSONDecodeError, LockError) as error:
        print(f"local-git-inputs.py: {error}", file=sys.stderr)
        return 2

    for name, has_submodules, repo in local_inputs:
        if sys.argv[1] == "names":
            print(name)
        else:
            print(f"{int(has_submodules)}\t{repo}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
