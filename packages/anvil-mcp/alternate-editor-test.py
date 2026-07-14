#!/usr/bin/env python3
"""Prove Anvil transports never invoke emacsclient's fallback editor."""

from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile


def failure(command: subprocess.CompletedProcess[str]) -> str:
    """Return compact subprocess details for an assertion failure."""
    return (
        f"rc={command.returncode} stdout={command.stdout!r} stderr={command.stderr!r}"
    )


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} ANVIL_STDIO EMACSCLIENT")
    stdio = Path(sys.argv[1]).resolve()
    emacsclient = Path(sys.argv[2]).resolve()
    if not stdio.is_file() or not emacsclient.is_file():
        raise SystemExit("stdio and emacsclient arguments must be files")

    with tempfile.TemporaryDirectory(prefix="anvil-alternate-editor-") as raw:
        temporary = Path(raw)
        missing_socket = temporary / "missing.sock"
        marker = temporary / "alternate-editor-used"
        alternate_editor = temporary / "alternate-editor"
        alternate_editor.write_text(
            f"""#!{sys.executable}
from pathlib import Path
import sys
with Path({str(marker)!r}).open("a", encoding="utf-8") as handle:
    handle.write(" ".join(sys.argv[1:]) + "\\n")
""",
            encoding="utf-8",
        )
        alternate_editor.chmod(alternate_editor.stat().st_mode | stat.S_IXUSR)

        contaminated = os.environ.copy()
        contaminated["ALTERNATE_EDITOR"] = str(alternate_editor)
        direct = subprocess.run(
            [
                str(emacsclient),
                "-a",
                str(alternate_editor),
                "-s",
                str(missing_socket),
                "-e",
                "t",
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=contaminated,
            text=True,
            timeout=5,
            check=False,
        )
        if direct.returncode != 0 or not marker.is_file():
            raise AssertionError(
                "contaminated emacsclient did not reproduce fallback: "
                + failure(direct)
            )
        marker.unlink()

        request_id = 73
        request = json.dumps(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "method": "tools/list",
                "params": {},
            },
            separators=(",", ":"),
        )
        bridge_environment = contaminated | {
            "PATH": (f"{emacsclient.parent}{os.pathsep}{contaminated.get('PATH', '')}"),
            "ANVIL_EMACSCLIENT_RETRY_MAX": "1",
            "ANVIL_EMACSCLIENT_RETRY_DELAY_MS": "0",
            "ANVIL_EMACSCLIENT_PROBE_TIMEOUT": "1",
            "ANVIL_EMACSCLIENT_TIMEOUT": "2",
        }
        bridge = subprocess.run(
            [str(stdio), f"--socket={missing_socket}", "--server-id=test"],
            input=request + "\n",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=bridge_environment,
            text=True,
            timeout=10,
            check=False,
        )
        if marker.exists():
            raise AssertionError(
                "Anvil stdio invoked ALTERNATE_EDITOR: "
                + marker.read_text(encoding="utf-8")
            )
        if bridge.returncode != 0:
            raise AssertionError("Anvil stdio failed: " + failure(bridge))
        lines = [line for line in bridge.stdout.splitlines() if line]
        if len(lines) != 1:
            raise AssertionError("unexpected bridge output: " + failure(bridge))
        response = json.loads(lines[0])
        error = response.get("error", {})
        data = error.get("data", {})
        expected = {
            "phase": "readiness",
            "dispatched": False,
            "replayed": False,
            "emacsclientRc": 1,
        }
        if response.get("id") != request_id or data != expected:
            raise AssertionError(f"unexpected bridge response: {response!r}")

    print("alternate editor test: reproduced fallback and blocked transport use")


if __name__ == "__main__":
    main()
