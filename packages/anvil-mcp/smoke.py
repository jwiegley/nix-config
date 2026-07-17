#!/usr/bin/env python3
"""End-to-end smoke test for the packaged NeLisp Anvil MCP runtime."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

EXPECTED_TOOLS = {
    "anvil-host--dispatch",
    "anvil-host--info-cpu-darwin",
    "anvil-host--info-cpu-linux",
    "anvil-host--info-cpu-windows",
    "anvil-host--info-disk-unix",
    "anvil-host--info-disk-windows",
    "anvil-host--info-emacs",
    "anvil-host--info-gpu-darwin",
    "anvil-host--info-gpu-linux",
    "anvil-host--info-gpu-windows",
    "anvil-host--info-net-darwin",
    "anvil-host--info-net-linux",
    "anvil-host--info-net-windows",
    "anvil-host--info-os-darwin",
    "anvil-host--info-os-linux",
    "anvil-host--info-os-windows",
    "anvil-host--info-ram-darwin",
    "anvil-host--info-ram-linux",
    "anvil-host--info-ram-windows",
    "anvil-host--info-uptime-unix",
    "anvil-host--info-uptime-windows",
    "anvil-host-env",
    "anvil-host-helpers-list",
    "anvil-host-info",
    "anvil-host-which",
    "anvil-shell",
    "anvil-shell-by-os",
    "data-delete-path",
    "data-get-path",
    "data-list-keys",
    "data-set-path",
    "directory-list",
    "file-append",
    "file-exists-p",
    "file-read",
    "file-replace-string",
    "file-write",
    "shell-filter",
    "shell-gain",
    "shell-run",
    "shell-tee-get",
    "shell-tee-grep",
}


def request(identifier: int | None, method: str, params: object | None = None) -> str:
    frame: dict[str, object] = {"jsonrpc": "2.0", "method": method}
    if identifier is not None:
        frame["id"] = identifier
    if params is not None:
        frame["params"] = params
    return json.dumps(frame, separators=(",", ":"))


def response_by_id(
    responses: list[dict[str, object]], identifier: int
) -> dict[str, object]:
    matches = [response for response in responses if response.get("id") == identifier]
    if len(matches) != 1:
        raise AssertionError(
            f"expected one response for id {identifier}, found {len(matches)}"
        )
    return matches[0]


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: smoke.py /path/to/anvil-mcp")

    launcher = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="anvil-mcp-smoke-") as temp_home:
        frames = [
            request(
                1,
                "initialize",
                {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "nix-smoke", "version": "1"},
                },
            ),
            request(None, "notifications/initialized"),
            request(2, "tools/list"),
            request(
                3,
                "tools/call",
                {
                    "name": "file-exists-p",
                    "arguments": {"path": str(launcher)},
                },
            ),
            request(
                4,
                "tools/call",
                {
                    "name": "shell-run",
                    "arguments": {"cmd": "printf anvil-smoke"},
                },
            ),
            request(5, "shutdown"),
            request(None, "exit"),
        ]
        env = os.environ.copy()
        env.update({"EMACS": "/definitely-missing", "HOME": temp_home})
        completed = subprocess.run(
            [str(launcher), "--server-id=anvil"],
            check=False,
            env=env,
            input="\n".join(frames) + "\n",
            text=True,
            capture_output=True,
            timeout=20,
        )

    if completed.returncode != 0:
        raise AssertionError(
            f"server exited {completed.returncode}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    if "bootstrap failed" in completed.stderr:
        raise AssertionError(f"runtime used a failed bootstrap:\n{completed.stderr}")

    output_lines = [line for line in completed.stdout.splitlines() if line.strip()]
    responses = [json.loads(line) for line in output_lines]
    if len(responses) != 5:
        raise AssertionError(
            f"expected 5 responses, found {len(responses)}: {responses}"
        )

    initialized = response_by_id(responses, 1)["result"]
    assert isinstance(initialized, dict)
    assert initialized["protocolVersion"] == "2024-11-05"
    assert initialized["serverInfo"]["name"] == "nelisp-runtime-mcp"
    assert "tools" in initialized["capabilities"]

    listed = response_by_id(responses, 2)["result"]
    assert isinstance(listed, dict)
    tools = listed["tools"]
    assert isinstance(tools, list)
    names = [tool["name"] for tool in tools]
    if len(names) != len(set(names)):
        raise AssertionError(f"duplicate tools returned: {names}")
    if names == ["hello"]:
        raise AssertionError("runtime exposed the placeholder registry")
    if set(names) != EXPECTED_TOOLS:
        missing = sorted(EXPECTED_TOOLS - set(names))
        unexpected = sorted(set(names) - EXPECTED_TOOLS)
        raise AssertionError(
            f"unexpected tool surface: missing={missing}, unexpected={unexpected}"
        )
    exists_result = response_by_id(responses, 3)["result"]
    assert exists_result["isError"] is False
    assert exists_result["value"]["exists"] is True
    assert exists_result["value"]["kind"] == "file"

    shell_result = response_by_id(responses, 4)["result"]
    assert shell_result["isError"] is False
    assert shell_result["value"]["exit"] == 0
    assert shell_result["value"]["compressed"] == "anvil-smoke"

    assert response_by_id(responses, 5)["result"] is None
    print(f"PASS: {len(names)} Anvil tools, file and shell calls succeeded")


if __name__ == "__main__":
    main()
