"""Exercise installed PAL directly or through a supplied launcher argument list."""

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
    matches = [
        response
        for response in responses
        if isinstance(response, dict)
        and type(response.get("id")) is int
        and response.get("id") == response_id
    ]
    if len(matches) != 1:
        fail(f"expected exactly one JSON-RPC response {response_id}")
    response = matches[0]
    if response.get("jsonrpc") != "2.0":
        fail(f"response {response_id} omitted the JSON-RPC 2.0 identity")
    has_result = "result" in response
    has_error = "error" in response
    if has_result == has_error:
        fail(f"response {response_id} must contain exactly one of result or error")
    if has_error:
        error = response["error"]
        if (
            not isinstance(error, dict)
            or not isinstance(error.get("code"), int)
            or isinstance(error.get("code"), bool)
            or not isinstance(error.get("message"), str)
            or not error["message"]
        ):
            fail(f"response {response_id} returned malformed JSON-RPC error data")
    return response


def tool_payload(response: dict[str, object], response_id: int) -> dict[str, object]:
    result = response.get("result")
    if not isinstance(result, dict):
        fail(f"response {response_id} has no result")
    is_error = result.get("isError", False)
    if not isinstance(is_error, bool) or is_error:
        fail(f"response {response_id} reported an MCP execution error")
    content = result.get("content")
    if not isinstance(content, list) or not content or not isinstance(content[0], dict):
        fail(f"response {response_id} has no tool content")
    if content[0].get("type") != "text":
        fail(f"response {response_id} returned non-text MCP content")
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
    if len(sys.argv) < 4 or (len(sys.argv) > 4 and sys.argv[4] != "--"):
        fail("expected OUT EXECUTABLE VERSION [-- EXECUTABLE-ARG ...]")
    output = Path(sys.argv[1]).resolve()
    executable = Path(sys.argv[2]).resolve()
    expected_version = sys.argv[3]
    executable_arguments = sys.argv[5:]

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
        {
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {"name": "clink", "arguments": {}},
        },
        {
            "jsonrpc": "2.0",
            "id": 5,
            "method": "prompts/list",
            "params": {},
        },
        {
            "jsonrpc": "2.0",
            "id": 6,
            "method": "prompts/get",
            "params": {"name": "clink", "arguments": {}},
        },
        {
            "jsonrpc": "2.0",
            "id": 7,
            "method": "prompts/get",
            "params": {"name": "chat", "arguments": {}},
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
            "DISABLED_TOOLS": "testgen,secaudit,docgen,tracer",
            "HOME": str(home),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "LOG_LEVEL": "WARNING",
            "PAL_MCP_UNRELATED_CANARY": "pal-mcp-contract-canary",
            "PAL_NETWORK_ATTEMPT_MARKER": str(network_attempt),
            "PAL_NETWORK_GUARD_PATH": str(guard),
            "PAL_NETWORK_GUARD_MARKER": str(marker),
            "PATH": str(executable.parent),
            "PYTHONPATH": str(guard),
            "PYTHONUTF8": "1",
            "TMPDIR": str(tmp),
            "XDG_CONFIG_HOME": str(config),
            "XDG_STATE_HOME": str(state),
        }
        process = subprocess.Popen(
            [str(executable), *executable_arguments],
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
                returncode = process.wait(timeout=30)
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

        expected_response_ids = set(range(1, 8))
        response_ids = [
            response.get("id") if isinstance(response, dict) else None
            for response in responses
        ]
        if (
            len(responses) != len(expected_response_ids)
            or any(type(response_id) is not int for response_id in response_ids)
            or set(response_ids) != expected_response_ids
        ):
            fail("stdout contained missing, duplicate, or extraneous protocol messages")

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
        capabilities = initialized.get("capabilities")
        if (
            not isinstance(capabilities, dict)
            or not isinstance(capabilities.get("tools"), dict)
            or not isinstance(capabilities.get("prompts"), dict)
        ):
            fail("initialize omitted tools or prompts capability advertisement")

        listed = response_by_id(responses, 2).get("result")
        if not isinstance(listed, dict) or not isinstance(listed.get("tools"), list):
            fail("tools/list returned no tool list")
        tool_names = {
            tool.get("name")
            for tool in listed["tools"]
            if isinstance(tool, dict) and isinstance(tool.get("name"), str)
        }
        required_tools = {"chat", "listmodels", "version"}
        if not required_tools <= tool_names:
            fail(
                f"tools/list omitted required tools: {sorted(required_tools - tool_names)}"
            )
        for required_tool in required_tools:
            matching_tools = [
                tool
                for tool in listed["tools"]
                if isinstance(tool, dict) and tool.get("name") == required_tool
            ]
            if (
                len(matching_tools) != 1
                or not isinstance(matching_tools[0].get("inputSchema"), dict)
                or matching_tools[0]["inputSchema"].get("type") != "object"
            ):
                fail(f"tools/list returned an invalid {required_tool} schema")
        if "clink" in tool_names:
            fail("tools/list exposed the disabled clink subprocess bridge")

        models = tool_payload(response_by_id(responses, 3), 3)
        if models.get("status") != "success":
            fail("provider-free listmodels call failed")
        metadata = models.get("metadata")
        if not isinstance(metadata, dict) or metadata.get("configured_providers") != 0:
            fail("provider-free listmodels did not report zero configured providers")

        denied = response_by_id(responses, 4).get("result")
        denied_content = denied.get("content") if isinstance(denied, dict) else None
        denied_is_error = denied.get("isError", False) if isinstance(denied, dict) else None
        if (
            not isinstance(denied_is_error, bool)
            or denied_is_error
            or not isinstance(denied_content, list)
            or len(denied_content) != 1
            or not isinstance(denied_content[0], dict)
            or denied_content[0].get("type") != "text"
            or denied_content[0].get("text") != "Unknown tool: clink"
        ):
            fail("tools/call did not deny the disabled clink subprocess bridge")

        prompts = response_by_id(responses, 5).get("result")
        prompt_entries = prompts.get("prompts") if isinstance(prompts, dict) else None
        prompt_names = {
            prompt.get("name")
            for prompt in prompt_entries or []
            if isinstance(prompt, dict) and isinstance(prompt.get("name"), str)
        }
        if (
            not isinstance(prompt_entries, list)
            or not {"chat", "continue"} <= prompt_names
            or "clink" in prompt_names
        ):
            fail("prompts/list exposed the disabled clink subprocess bridge")
        denied_prompt = response_by_id(responses, 6).get("error")
        if (
            not isinstance(denied_prompt, dict)
            or denied_prompt.get("code") != 0
            or denied_prompt.get("message") != "Unknown prompt: clink"
        ):
            fail("prompts/get did not deny the disabled clink subprocess bridge")
        chat_prompt = response_by_id(responses, 7).get("result")
        chat_messages = chat_prompt.get("messages") if isinstance(chat_prompt, dict) else None
        if (
            not isinstance(chat_messages, list)
            or not chat_messages
            or not all(
                isinstance(message, dict)
                and message.get("role") in {"user", "assistant"}
                and isinstance(message.get("content"), dict)
                and message["content"].get("type") == "text"
                and isinstance(message["content"].get("text"), str)
                and bool(message["content"]["text"])
                for message in chat_messages
            )
        ):
            fail("prompts/get could not resolve the surviving chat prompt")

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
