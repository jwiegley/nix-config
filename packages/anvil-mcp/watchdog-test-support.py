#!/usr/bin/env python3
"""Shared AST loader for tests of the generated watchdog launcher."""

from __future__ import annotations

import ast
import os
from pathlib import Path
from types import ModuleType
from typing import Iterable


def required_store_path(environment_name: str) -> Path:
    """Return one required absolute generated-artifact path."""
    raw = os.environ.get(environment_name)
    if not raw:
        raise RuntimeError(f"missing required {environment_name}")
    path = Path(raw)
    if not path.is_absolute():
        raise RuntimeError(f"{environment_name} must be an absolute path")
    if not path.exists():
        raise RuntimeError(f"{environment_name} does not exist")
    if not str(path).startswith("/nix/store/"):
        raise RuntimeError(f"{environment_name} must name a realised store path")
    return path.resolve()


def _constant_assignment(node: ast.stmt) -> bool:
    """Return whether NODE only assigns generated module constants."""
    if isinstance(node, ast.Assign):
        targets = node.targets
    elif isinstance(node, ast.AnnAssign):
        targets = [node.target]
    else:
        return False
    return all(
        isinstance(target, ast.Name) and target.id.isupper() for target in targets
    )


def load_generated_launcher(
    launcher: Path,
    required_names: Iterable[str],
) -> ModuleType:
    """Load imports, constants, and definitions without running launcher main."""
    source = launcher.read_text(encoding="utf-8")
    tree = ast.parse(source, filename=str(launcher))
    body = [
        node
        for node in tree.body
        if isinstance(
            node,
            (
                ast.Import,
                ast.ImportFrom,
                ast.FunctionDef,
                ast.AsyncFunctionDef,
                ast.ClassDef,
            ),
        )
        or _constant_assignment(node)
    ]
    module = ModuleType("anvil_generated_watchdog")
    module.__file__ = str(launcher)
    exec(
        compile(ast.Module(body=body, type_ignores=[]), str(launcher), "exec"),
        module.__dict__,
    )
    missing = sorted(name for name in required_names if not hasattr(module, name))
    if missing:
        raise AssertionError(f"watchdog function drift: missing={missing}")
    return module
