"""Exercise the installed PAL MCP server without credentials or network access."""

from __future__ import annotations

import json
import os
import select
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import BinaryIO

PROTOCOL_BYTE_LIMIT = 1024 * 1024


def fail(message: str, *, stderr: str = "") -> None:
    detail = f"\nPAL stderr:\n{stderr}" if stderr else ""
    raise SystemExit(f"PAL MCP contract: {message}{detail}")


def response_by_id(responses: list[object], response_id: int) -> dict[str, object]:
    for response in responses:
        if isinstance(response, dict) and response.get("id") == response_id:
            return response
    fail(f"missing JSON-RPC response {response_id}")


def tool_payload(response: dict[str, object], response_id: int) -> dict[str, object]:
    result = response.get("result")
    if not isinstance(result, dict):
        fail(f"response {response_id} has no result")
    content = result.get("content")
    if not isinstance(content, list) or not content or not isinstance(content[0], dict):
        fail(f"response {response_id} has no tool content")
    text = content[0].get("text")
    if not isinstance(text, str):
        fail(f"response {response_id} has no text payload")
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as error:
        fail(f"response {response_id} tool payload is not JSON: {error}")
    if not isinstance(payload, dict):
        fail(f"response {response_id} tool payload is not an object")
    return payload


def parse_response(line: bytes) -> object:
    try:
        return json.loads(line.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(
            f"stdout contains non-JSON protocol data: {error}"
        ) from error


def consume_responses(
    buffer: bytearray, responses: list[object], response_id: int | None = None
) -> bool:
    found = False
    while True:
        newline = buffer.find(b"\n")
        if newline < 0:
            return found
        line = bytes(buffer[:newline])
        del buffer[: newline + 1]
        response = parse_response(line)
        responses.append(response)
        if (
            response_id is not None
            and isinstance(response, dict)
            and response.get("id") == response_id
        ):
            found = True


def append_protocol_bytes(
    buffer: bytearray, chunk: bytes, bytes_read: list[int]
) -> None:
    bytes_read[0] += len(chunk)
    if bytes_read[0] > PROTOCOL_BYTE_LIMIT:
        raise RuntimeError("stdout exceeded the 1 MiB protocol limit")
    buffer.extend(chunk)


def read_response(
    process: subprocess.Popen[bytes],
    responses: list[object],
    response_id: int,
    buffer: bytearray,
    bytes_read: list[int],
) -> None:
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if consume_responses(buffer, responses, response_id):
            return
        remaining = deadline - time.monotonic()
        ready, _, _ = select.select([process.stdout], [], [], remaining)
        if not ready:
            break
        chunk = os.read(process.stdout.fileno(), 4096)
        if not chunk:
            break
        append_protocol_bytes(buffer, chunk, bytes_read)
    raise RuntimeError(f"missing JSON-RPC response {response_id}")


def drain_stderr(
    stream: BinaryIO, buffer: bytearray, overflow: threading.Event
) -> None:
    limit = 1024 * 1024
    while chunk := stream.read(4096):
        remaining = limit - len(buffer)
        if remaining > 0:
            buffer.extend(chunk[:remaining])
        if len(chunk) > remaining:
            overflow.set()


def main() -> None:
    if len(sys.argv) != 4:
        fail("expected OUT EXECUTABLE VERSION")
    output = Path(sys.argv[1]).resolve()
    executable = Path(sys.argv[2]).resolve()
    expected_version = sys.argv[3]

    requests = [
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-03-26",
                "capabilities": {},
                "clientInfo": {"name": "nix-check", "version": "1"},
            },
        },
        {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "listmodels", "arguments": {}},
        },
    ]
    with tempfile.TemporaryDirectory(prefix="pal-mcp-contract-") as temporary:
        root = Path(temporary)
        home = root / "home"
        config = root / "config"
        state = root / "state"
        tmp = root / "tmp"
        guard = root / "guard"
        for directory in (home, config, state, tmp, guard):
            directory.mkdir(mode=0o700)
        marker = guard / "loaded"
        network_attempt = guard / "network-attempt"
        (guard / "sitecustomize.py").write_text(
            """\
import os
from pathlib import Path
import socket

def blocked(*_args, **_kwargs):
    Path(os.environ["PAL_NETWORK_ATTEMPT_MARKER"]).touch()
    raise OSError("PAL MCP install check forbids network access")

socket.getaddrinfo = blocked
socket.socket.connect = blocked
socket.socket.connect_ex = blocked
Path(os.environ["PAL_NETWORK_GUARD_MARKER"]).touch()
"""
        )

        environment = {
            "DEFAULT_MODEL": "auto",
            "HOME": str(home),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "LOG_LEVEL": "WARNING",
            "PAL_MCP_UNRELATED_CANARY": "pal-mcp-contract-canary",
            "PAL_NETWORK_ATTEMPT_MARKER": str(network_attempt),
            "PAL_NETWORK_GUARD_MARKER": str(marker),
            "PATH": str(executable.parent),
            "PYTHONPATH": str(guard),
            "PYTHONUTF8": "1",
            "TMPDIR": str(tmp),
            "XDG_CONFIG_HOME": str(config),
            "XDG_STATE_HOME": str(state),
        }
        process = subprocess.Popen(
            [str(executable)],
            cwd=root,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
            env=environment,
        )
        stderr_buffer = bytearray()
        stderr_overflow = threading.Event()
        stderr_thread = threading.Thread(
            target=drain_stderr,
            args=(process.stderr, stderr_buffer, stderr_overflow),
            daemon=True,
        )
        stderr_thread.start()
        responses: list[object] = []
        stdout_buffer = bytearray()
        stdout_bytes_read = [0]
        protocol_error = ""
        try:
            for request in requests:
                process.stdin.write((json.dumps(request) + "\n").encode())
                response_id = request.get("id")
                if isinstance(response_id, int):
                    read_response(
                        process,
                        responses,
                        response_id,
                        stdout_buffer,
                        stdout_bytes_read,
                    )
        except (BrokenPipeError, RuntimeError) as error:
            protocol_error = str(error)
        finally:
            process.stdin.close()
            try:
                returncode = process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                returncode = process.wait(timeout=5)
                if not protocol_error:
                    protocol_error = (
                        "server did not exit after the provider-free handshake"
                    )
            stdout_deadline = time.monotonic() + 5
            while time.monotonic() < stdout_deadline:
                remaining = stdout_deadline - time.monotonic()
                ready, _, _ = select.select([process.stdout], [], [], remaining)
                if not ready:
                    if not protocol_error:
                        protocol_error = "stdout remained open after server exit"
                    break
                chunk = os.read(process.stdout.fileno(), 4096)
                if not chunk:
                    break
                try:
                    append_protocol_bytes(stdout_buffer, chunk, stdout_bytes_read)
                except RuntimeError as error:
                    if not protocol_error:
                        protocol_error = str(error)
            try:
                consume_responses(stdout_buffer, responses)
                if stdout_buffer:
                    responses.append(parse_response(bytes(stdout_buffer)))
                    stdout_buffer.clear()
            except RuntimeError as error:
                protocol_error = str(error)
            stderr_thread.join(timeout=5)
            if stderr_thread.is_alive() and not protocol_error:
                protocol_error = "stderr reader did not finish"
            stderr = stderr_buffer.decode("utf-8", errors="replace")
            if stderr_overflow.is_set() and not protocol_error:
                protocol_error = "stderr exceeded the 1 MiB diagnostic limit"

        if protocol_error:
            fail(protocol_error, stderr=stderr)
        if returncode != 0:
            fail(
                f"server exited with status {returncode}",
                stderr=stderr,
            )

        initialized = response_by_id(responses, 1).get("result")
        if not isinstance(initialized, dict):
            fail("initialize response has no result")
        if initialized.get("protocolVersion") != "2025-03-26":
            fail("initialize negotiated an unexpected protocol version")
        server_info = initialized.get("serverInfo")
        if not isinstance(server_info, dict) or server_info.get("name") != "PAL":
            fail("initialize returned an unexpected server identity")
        if server_info.get("version") != expected_version:
            fail("initialize returned a version that differs from the package")

        listed = response_by_id(responses, 2).get("result")
        if not isinstance(listed, dict) or not isinstance(listed.get("tools"), list):
            fail("tools/list returned no tool list")
        tool_names = {
            tool.get("name")
            for tool in listed["tools"]
            if isinstance(tool, dict) and isinstance(tool.get("name"), str)
        }
        required_tools = {"chat", "clink", "listmodels", "version"}
        if not required_tools <= tool_names:
            fail(
                f"tools/list omitted required tools: {sorted(required_tools - tool_names)}"
            )

        models = tool_payload(response_by_id(responses, 3), 3)
        if models.get("status") != "success":
            fail("provider-free listmodels call failed")
        metadata = models.get("metadata")
        if not isinstance(metadata, dict) or metadata.get("configured_providers") != 0:
            fail("provider-free listmodels did not report zero configured providers")

        if not marker.is_file():
            fail("network guard did not load")
        if network_attempt.exists():
            fail("provider-free startup attempted network access")
        forbidden_messages = ("Could not set up file logging", "Permission denied")
        if any(message in stderr for message in forbidden_messages):
            fail("server attempted immutable file logging", stderr=stderr)
        canary = environment["PAL_MCP_UNRELATED_CANARY"]
        if canary in stderr or canary in json.dumps(responses):
            fail("server disclosed an unrelated environment value")
        for tree in (output, root):
            for name in ("mcp_server.log", "mcp_activity.log"):
                if any(tree.rglob(name)):
                    fail(f"server created forbidden persistent log {name}")


if __name__ == "__main__":
    main()
