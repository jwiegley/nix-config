#!/usr/bin/env python3
"""Prove one stdio bridge survives daemon failure and reconnects."""

from __future__ import annotations

import json
import os
from pathlib import Path
import selectors
import stat
import subprocess
import sys
import tempfile


def percent_wire(payload: bytes) -> str:
    """Encode PAYLOAD for the fake-client environment."""
    return "".join(f"%{byte:02x}" for byte in payload)


def write_fake_emacsclient(path: Path) -> None:
    """Create a fake client controlled by a mutable daemon-state file."""
    path.write_text(
        r"""#!__PYTHON__
import base64
import json
import os
from pathlib import Path
import re
import sys


def bump(name):
    path = Path(os.environ[name])
    try:
        value = int(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        value = 0
    path.write_text(str(value + 1), encoding="utf-8")


def decode_wire(text):
    if re.fullmatch(r"(?:%[0-9A-Fa-f]{2})*", text) is None:
        raise ValueError("invalid fake response wire")
    return bytes.fromhex(text.replace("%", ""))


def publish_response(expression):
    decoded = []
    for payload in re.findall(
        r'base64-decode-string "([A-Za-z0-9+/=]+)"', expression
    ):
        try:
            value = base64.b64decode(payload, validate=True).decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            continue
        if os.path.isabs(value):
            decoded.append(Path(value))
    stages = []
    for candidate in decoded:
        match = re.fullmatch(r"\.response-tmp\.([0-9]+)\..+", candidate.name)
        if match is not None and int(match.group(1)) > 0:
            stages.append((candidate, int(match.group(1))))
    if len(stages) != 1:
        print(f"missing unique response stage: {decoded}", file=sys.stderr)
        raise SystemExit(70)
    stage, sequence = stages[0]
    wire = decode_wire(os.environ["FAKE_RESPONSE_WIRE"])
    final = stage.parent / f"response.{sequence}.json"
    proof = stage.parent / f"proof.{sequence}.json"
    with stage.open("wb") as stream:
        stream.write(wire)
    os.link(stage, final)
    os.link(stage, proof)
    stage.unlink()
    marker = f"anvil-mcp-response-staged:{sequence}:{len(wire)}"
    print(json.dumps(marker))


mode = Path(os.environ["FAKE_DAEMON_MODE"]).read_text(encoding="utf-8").strip()
expression = sys.argv[-1]
if expression == "t":
    bump("FAKE_PROBE_COUNT")
    if mode == "down":
        print("Connection refused", file=sys.stderr)
        raise SystemExit(1)
    print("t")
else:
    bump("FAKE_DISPATCH_COUNT")
    if mode == "dispatch-fail":
        print("daemon exited during dispatch", file=sys.stderr)
        raise SystemExit(1)
    publish_response(expression)
""".replace("__PYTHON__", sys.executable),
        encoding="utf-8",
    )
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def read_count(path: Path) -> int:
    """Read a fake-client invocation count."""
    try:
        return int(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return 0


def diagnostics(process: subprocess.Popen[str], debug_log: Path) -> str:
    """Return bounded bridge diagnostics for assertion failures."""
    debug = (
        debug_log.read_text(encoding="utf-8")
        if debug_log.exists()
        else "<no debug log>"
    )
    return f"pid={process.pid} rc={process.poll()} debug={debug[-4000:]}"


def read_reply(
    process: subprocess.Popen[str],
    debug_log: Path,
    *,
    timeout: float = 8,
) -> dict[str, object]:
    """Read one line-delimited bridge response with a hard deadline."""
    if process.stdout is None:
        raise AssertionError("bridge stdout is unavailable")
    selector = selectors.DefaultSelector()
    try:
        selector.register(process.stdout, selectors.EVENT_READ)
        if not selector.select(timeout):
            raise AssertionError(
                f"bridge reply timed out after {timeout}s: "
                f"{diagnostics(process, debug_log)}"
            )
    finally:
        selector.close()
    line = process.stdout.readline()
    if not line:
        raise AssertionError(
            f"bridge exited before reply: {diagnostics(process, debug_log)}"
        )
    if line.lower().startswith("content-length:"):
        try:
            length = int(line.split(":", 1)[1].strip())
        except ValueError as error:
            raise AssertionError(f"invalid response framing: {line!r}") from error
        separator = process.stdout.readline()
        if separator.strip():
            raise AssertionError(f"missing blank framing separator: {separator!r}")
        payload = process.stdout.read(length)
        response = json.loads(payload)
    else:
        response = json.loads(line)
    if not isinstance(response, dict):
        raise AssertionError(f"bridge returned non-object JSON: {response!r}")
    return response


def send_document(
    process: subprocess.Popen[str],
    debug_log: Path,
    document: dict[str, object],
    *,
    framed: bool = False,
) -> dict[str, object]:
    """Send DOCUMENT through the still-open bridge and read its reply."""
    if process.stdin is None:
        raise AssertionError("bridge stdin is unavailable")
    request = json.dumps(document, separators=(",", ":"))
    if framed:
        request_bytes = request.encode("utf-8")
        process.stdin.write(f"Content-Length: {len(request_bytes)}\r\n\r\n{request}")
    else:
        process.stdin.write(request + "\n")
    process.stdin.flush()
    return read_reply(process, debug_log)


def send_request(
    process: subprocess.Popen[str],
    debug_log: Path,
    request_id: object,
    *,
    method: str = "test",
    params: dict[str, object] | None = None,
    framed: bool = False,
) -> dict[str, object]:
    """Send one request through the still-open bridge and read its reply."""
    document: dict[str, object] = {
        "jsonrpc": "2.0",
        "id": request_id,
        "method": method,
    }
    if params is not None:
        document["params"] = params
    return send_document(process, debug_log, document, framed=framed)


def assert_no_reply(
    process: subprocess.Popen[str],
    debug_log: Path,
    *,
    timeout: float = 0.5,
) -> None:
    """Require that a notification remains silent."""
    if process.stdout is None:
        raise AssertionError("bridge stdout is unavailable")
    selector = selectors.DefaultSelector()
    try:
        selector.register(process.stdout, selectors.EVENT_READ)
        if selector.select(timeout):
            raise AssertionError(
                "notification unexpectedly produced output: "
                f"{diagnostics(process, debug_log)}"
            )
    finally:
        selector.close()


def assert_error(
    response: dict[str, object],
    *,
    request_id: object,
    phase: str,
    dispatched: bool,
) -> None:
    """Require the expected correlated at-most-once synthetic error."""
    if response.get("id") != request_id:
        raise AssertionError(f"wrong response id: {response}")
    error = response.get("error")
    if not isinstance(error, dict):
        raise AssertionError(f"missing synthetic error: {response}")
    data = error.get("data")
    if not isinstance(data, dict):
        raise AssertionError(f"missing synthetic error data: {response}")
    expected = {
        "phase": phase,
        "dispatched": dispatched,
        "replayed": False,
    }
    for key, value in expected.items():
        if data.get(key) != value:
            raise AssertionError(f"wrong {key}: {data.get(key)!r}")


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} ANVIL_STDIO")
    stdio = Path(sys.argv[1]).resolve()
    if not stdio.is_file():
        raise SystemExit(f"not a file: {stdio}")

    with tempfile.TemporaryDirectory(prefix="anvil-stdio-reconnect-") as raw:
        root = Path(raw)
        binary_dir = root / "bin"
        binary_dir.mkdir()
        write_fake_emacsclient(binary_dir / "emacsclient")

        mode = root / "daemon-mode"
        probe_count = root / "probe-count"
        dispatch_count = root / "dispatch-count"
        debug_log = root / "stdio.log"
        success = {"jsonrpc": "2.0", "id": 3, "result": "rebound"}
        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{binary_dir}{os.pathsep}{environment['PATH']}",
                "FAKE_DAEMON_MODE": str(mode),
                "FAKE_PROBE_COUNT": str(probe_count),
                "FAKE_DISPATCH_COUNT": str(dispatch_count),
                "FAKE_RESPONSE_WIRE": percent_wire(
                    json.dumps(success, separators=(",", ":")).encode("utf-8")
                ),
                "EMACS_MCP_DEBUG_LOG": str(debug_log),
                "ANVIL_EMACSCLIENT_PROBE_TIMEOUT": "2",
                "ANVIL_EMACSCLIENT_READINESS_TIMEOUT": "4",
                "ANVIL_EMACSCLIENT_STARTUP_DISPATCH_TIMEOUT": "2",
                "ANVIL_EMACSCLIENT_DISPATCH_TIMEOUT": "2",
                "ANVIL_EMACSCLIENT_KILL_AFTER_TIMEOUT": "1",
                "ANVIL_MCP_REQUEST_PARSE_TIMEOUT": "1",
                "ANVIL_EMACSCLIENT_RETRY_DELAY_MS": "0",
                "ANVIL_EMACSCLIENT_RETRY_MAX": "2",
            }
        )
        process = subprocess.Popen(
            [str(stdio), "--socket=/tmp/anvil-reconnect-test", "--server-id=test"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env=environment,
        )
        original_pid = process.pid
        try:
            mode.write_text("dispatch-fail", encoding="utf-8")
            assert_error(
                send_request(process, debug_log, 1),
                request_id=1,
                phase="dispatch",
                dispatched=True,
            )
            if process.poll() is not None:
                raise AssertionError("bridge died after ambiguous dispatch failure")

            escaped_id = 'abc"def\\tail'
            assert_error(
                send_request(
                    process,
                    debug_log,
                    escaped_id,
                    method="tools/call",
                    params={"id": 99},
                    framed=True,
                ),
                request_id=escaped_id,
                phase="dispatch",
                dispatched=True,
            )
            assert_error(
                send_request(process, debug_log, -7),
                request_id=-7,
                phase="dispatch",
                dispatched=True,
            )

            if process.stdin is None:
                raise AssertionError("bridge stdin disappeared")
            notification = {
                "jsonrpc": "2.0",
                "method": "test",
                "params": {"id": 123},
            }
            process.stdin.write(json.dumps(notification, separators=(",", ":")) + "\n")
            process.stdin.flush()
            assert_no_reply(process, debug_log)

            process.stdin.write('{"jsonrpc":\n')
            process.stdin.flush()
            malformed = read_reply(process, debug_log)
            assert_error(
                malformed,
                request_id=None,
                phase="parse",
                dispatched=False,
            )
            if malformed["error"].get("code") != -32700:
                raise AssertionError(
                    f"malformed input returned the wrong error: {malformed}"
                )

            mode.write_text("down", encoding="utf-8")
            assert_error(
                send_request(process, debug_log, 2),
                request_id=2,
                phase="readiness",
                dispatched=False,
            )
            if process.poll() is not None or process.pid != original_pid:
                raise AssertionError("bridge was replaced during daemon outage")

            mode.write_text("up", encoding="utf-8")
            recovered = send_request(process, debug_log, 3)
            if recovered != success:
                raise AssertionError(
                    f"bridge did not rebind after recovery: {recovered}"
                )
            if process.poll() is not None or process.pid != original_pid:
                raise AssertionError("bridge did not survive successful rebind")
            if read_count(dispatch_count) != 5:
                raise AssertionError(
                    "a failed request was replayed, a notification was skipped, "
                    "or a readiness/parse failure was dispatched"
                )
            if read_count(probe_count) < 7:
                raise AssertionError("readiness was not re-probed across recovery")

            if process.stdin is None:
                raise AssertionError("bridge stdin disappeared")
            process.stdin.close()
            process.wait(timeout=8)
            if process.returncode != 0:
                raise AssertionError(
                    f"bridge failed on clean EOF: {diagnostics(process, debug_log)}"
                )
            print("stdio-reconnect-ok")
            return 0
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=2)


if __name__ == "__main__":
    raise SystemExit(main())
