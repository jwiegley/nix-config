#!/usr/bin/env python3

"""Run unittest names while treating skipped tests as a failed authority."""

import importlib.util
import sys
import unittest
from pathlib import Path


def main(argv: list[str] | None = None) -> int:
    names = list(sys.argv[1:] if argv is None else argv)
    if not names:
        print("unittest-strict: at least one test name is required", file=sys.stderr)
        return 2
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    loaded_module_names: list[str] = []
    for index, name in enumerate(names):
        path = Path(name)
        if path.is_file():
            path = path.resolve()
            module_name = f"_strict_{index}_{path.stem.replace('-', '_')}"
            spec = importlib.util.spec_from_file_location(module_name, path)
            if spec is None or spec.loader is None:
                print(f"unittest-strict: cannot load {path}", file=sys.stderr)
                return 2
            module = importlib.util.module_from_spec(spec)
            sys.modules[module_name] = module
            loaded_module_names.append(module_name)
            spec.loader.exec_module(module)
            selected = loader.loadTestsFromModule(module)
        else:
            selected = loader.loadTestsFromName(name)
        if selected.countTestCases() == 0:
            print(f"unittest-strict: test authority is empty: {name}", file=sys.stderr)
            for module_name in loaded_module_names:
                sys.modules.pop(module_name, None)
            return 2
        suite.addTests(selected)
    if loader.errors:
        for error in loader.errors:
            print(error, file=sys.stderr)
        for module_name in loaded_module_names:
            sys.modules.pop(module_name, None)
        return 2
    try:
        result = unittest.TextTestRunner().run(suite)
    finally:
        for module_name in loaded_module_names:
            sys.modules.pop(module_name, None)
    if result.skipped:
        print(
            f"unittest-strict: {len(result.skipped)} skipped test(s) are non-pass",
            file=sys.stderr,
        )
        return 1
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
