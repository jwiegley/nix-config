#!/usr/bin/env python3
"""Deterministic subprocess fixture for bounded environment-runner tests."""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import time


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(64)
    mode = sys.argv[1]
    if mode == "context":
        print(
            json.dumps(
                {
                    "cwd": os.getcwd(),
                    "marker": os.environ.get("ANVIL_RUNNER_MARKER"),
                    "path": os.environ.get("PATH"),
                }
            ),
            end="",
        )
        return
    if mode == "boundary":
        sys.stdout.buffer.write(b"b" * 4096)
        return
    if mode == "empty":
        return
    if mode == "one":
        sys.stdout.buffer.write(b"x")
        return
    if mode not in ("stdout", "stderr") or len(sys.argv) != 3:
        raise SystemExit(64)

    pid_file = Path(sys.argv[2])
    child = os.fork()
    if child == 0:
        pid_file.write_text(str(os.getpid()))
        for descriptor in (0, 1, 2):
            try:
                os.close(descriptor)
            except OSError:
                pass
        time.sleep(30)
        os._exit(0)

    deadline = time.monotonic() + 5
    while not pid_file.exists() and time.monotonic() < deadline:
        time.sleep(0.001)
    stream = sys.stdout.buffer if mode == "stdout" else sys.stderr.buffer
    stream.write(b"x" * 4097)
    stream.flush()
    time.sleep(30)


if __name__ == "__main__":
    main()
