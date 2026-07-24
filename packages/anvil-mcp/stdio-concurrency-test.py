#!/usr/bin/env python3
"""Verify a second stdio bridge waits through readiness probe timeouts."""

from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import time


FIRST_PROBE_TIMEOUT_SECONDS = 5
SECOND_PROBE_TIMEOUT_SECONDS = 1
EMACSCLIENT_READINESS_TIMEOUT_SECONDS = 10
EMACSCLIENT_DISPATCH_TIMEOUT_SECONDS = 10
FIRST_READY_DELAY_SECONDS = 2
BRIDGE_WAIT_TIMEOUT_SECONDS = (
    max(EMACSCLIENT_READINESS_TIMEOUT_SECONDS, EMACSCLIENT_DISPATCH_TIMEOUT_SECONDS) + 2
)


def percent_wire(payload: bytes) -> str:
    """Encode PAYLOAD for the fake-client environment."""
    return "".join(f"%{byte:02x}" for byte in payload)


def collect_bridge_diagnostics(process: subprocess.Popen[str], debug_log: Path) -> str:
    """Return currently available stderr and debug-log text without blocking."""
    stderr_text = ""
    if process.stderr is not None:
        try:
            stderr_fd = process.stderr.fileno()
            os.set_blocking(stderr_fd, False)
            chunks: list[bytes] = []
            while True:
                try:
                    chunk = os.read(stderr_fd, 64 * 1024)
                except BlockingIOError:
                    break
                if not chunk:
                    break
                chunks.append(chunk)
            stderr_text = b"".join(chunks).decode("utf-8", errors="replace")
        except (BlockingIOError, OSError):
            stderr_text = "<unavailable>"
    try:
        debug_text = debug_log.read_text(encoding="utf-8") if debug_log.exists() else ""
    except OSError as error:
        debug_text = f"<unavailable: {error}>"
    return (
        f"returncode={process.poll()!r}\n"
        f"stderr:\n{stderr_text.strip() or '<empty>'}\n"
        f"debug log:\n{debug_text.strip() or '<empty>'}"
    )


def wait_for_file(
    path: Path,
    process: subprocess.Popen[str],
    timeout: float,
    debug_log: Path,
) -> None:
    """Wait for PATH while failing early if PROCESS exits."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            return
        if process.poll() is not None:
            raise AssertionError(
                "first bridge exited before dispatch:\n"
                f"{collect_bridge_diagnostics(process, debug_log)}"
            )
        time.sleep(0.02)
    raise AssertionError(
        f"first bridge never entered its serialized dispatch after {timeout:.1f}s:\n"
        f"{collect_bridge_diagnostics(process, debug_log)}"
    )


def start_bridge(
    stdio: Path,
    environment: dict[str, str],
    request_id: int,
    dispatch_sleep: float,
) -> subprocess.Popen[str]:
    """Start one bridge and submit a single legacy line-mode request."""
    response = {"jsonrpc": "2.0", "id": request_id, "result": request_id}
    child_env = environment | {
        "FAKE_DISPATCH_SLEEP": str(dispatch_sleep),
        "FAKE_RESPONSE_WIRE": percent_wire(
            json.dumps(response, separators=(",", ":")).encode("utf-8")
        ),
    }
    process = subprocess.Popen(
        [str(stdio), "--socket=/tmp/anvil-stdio-test", "--server-id=test"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=child_env,
    )
    assert process.stdin is not None
    process.stdin.write(
        json.dumps({"jsonrpc": "2.0", "id": request_id, "method": "test"}) + "\n"
    )
    process.stdin.close()
    return process


def finish_bridge(
    process: subprocess.Popen[str],
    timeout: float,
    debug_log: Path,
    label: str,
) -> tuple[str, str]:
    """Wait for PROCESS without asking communicate() to flush closed stdin."""
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired as error:
        diagnostics = collect_bridge_diagnostics(process, debug_log)
        cleanup_bridge(process)
        raise AssertionError(
            f"{label} stdio bridge exceeded its {timeout:.1f}s readiness budget:\n"
            f"{diagnostics}"
        ) from error
    assert process.stdout is not None
    assert process.stderr is not None
    return process.stdout.read().strip(), process.stderr.read().strip()


def cleanup_bridge(process: subprocess.Popen[str]) -> None:
    """Kill and reap PROCESS, then close all of its pipes."""
    try:
        if process.poll() is None:
            process.kill()
        process.wait(timeout=2.0)
    finally:
        for stream in (process.stdin, process.stdout, process.stderr):
            if stream is not None and not stream.closed:
                stream.close()


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} ANVIL_STDIO")
    stdio = Path(sys.argv[1]).resolve()
    if not stdio.is_file():
        raise SystemExit(f"not a file: {stdio}")

    with tempfile.TemporaryDirectory(prefix="anvil-stdio-concurrency-") as raw_tmp:
        tmp = Path(raw_tmp)
        fake_bin = tmp / "bin"
        fake_bin.mkdir()
        lock = tmp / "server.lock"
        dispatch_started = tmp / "dispatch-started"
        debug_log = tmp / "stdio.log"
        fake_client = fake_bin / "emacsclient"
        fake_client.write_text(
            r"""#!__PYTHON__
import base64
import fcntl
import json
import os
from pathlib import Path
import re
import sys
import time


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


expression = sys.argv[-1]
with open(os.environ["FAKE_SERVER_LOCK"], "a+", encoding="utf-8") as handle:
    fcntl.flock(handle, fcntl.LOCK_EX)
    if expression == "t":
        time.sleep(float(os.environ["FAKE_READY_SLEEP"]))
        print("t")
    else:
        Path(os.environ["FAKE_DISPATCH_STARTED"]).touch()
        time.sleep(float(os.environ["FAKE_DISPATCH_SLEEP"]))
        publish_response(expression)
""".replace("__PYTHON__", sys.executable),
            encoding="utf-8",
        )
        fake_client.chmod(fake_client.stat().st_mode | stat.S_IXUSR)

        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{fake_bin}{os.pathsep}{environment['PATH']}",
                "FAKE_SERVER_LOCK": str(lock),
                "FAKE_DISPATCH_STARTED": str(dispatch_started),
                "FAKE_READY_SLEEP": "0",
                "EMACS_MCP_DEBUG_LOG": str(debug_log),
                "ANVIL_EMACSCLIENT_PROBE_TIMEOUT": str(SECOND_PROBE_TIMEOUT_SECONDS),
                "ANVIL_EMACSCLIENT_READINESS_TIMEOUT": str(
                    EMACSCLIENT_READINESS_TIMEOUT_SECONDS
                ),
                "ANVIL_EMACSCLIENT_DISPATCH_TIMEOUT": str(
                    EMACSCLIENT_DISPATCH_TIMEOUT_SECONDS
                ),
                "ANVIL_EMACSCLIENT_RETRY_DELAY_MS": "0",
            }
        )

        first: subprocess.Popen[str] | None = None
        second: subprocess.Popen[str] | None = None
        try:
            first_environment = environment | {
                "ANVIL_EMACSCLIENT_PROBE_TIMEOUT": str(FIRST_PROBE_TIMEOUT_SECONDS),
                "FAKE_READY_SLEEP": str(FIRST_READY_DELAY_SECONDS),
            }
            first = start_bridge(
                stdio, first_environment, request_id=1, dispatch_sleep=4.0
            )
            wait_for_file(
                dispatch_started,
                first,
                timeout=BRIDGE_WAIT_TIMEOUT_SECONDS,
                debug_log=debug_log,
            )
            second = start_bridge(stdio, environment, request_id=2, dispatch_sleep=0.0)

            first_out, first_err = finish_bridge(
                first,
                timeout=BRIDGE_WAIT_TIMEOUT_SECONDS,
                debug_log=debug_log,
                label="first",
            )
            second_out, second_err = finish_bridge(
                second,
                timeout=BRIDGE_WAIT_TIMEOUT_SECONDS,
                debug_log=debug_log,
                label="second",
            )
            if first.returncode != 0 or second.returncode != 0:
                raise AssertionError(
                    "bridge failed:\n"
                    f"first rc={first.returncode} stderr={first_err}\n"
                    f"second rc={second.returncode} stderr={second_err}"
                )
            expected_first = json.dumps(
                {"jsonrpc": "2.0", "id": 1, "result": 1}, separators=(",", ":")
            )
            expected_second = json.dumps(
                {"jsonrpc": "2.0", "id": 2, "result": 2}, separators=(",", ":")
            )
            if first_out != expected_first or second_out != expected_second:
                raise AssertionError(
                    f"unexpected replies: first={first_out!r}, second={second_out!r}"
                )
            log = debug_log.read_text(encoding="utf-8")
            if "MCP-PROBE-TIMEOUT" not in log:
                raise AssertionError(
                    "second bridge did not exercise a readiness timeout"
                )
            if "phase=readiness dispatched=false" in log:
                raise AssertionError(
                    "a replayable readiness timeout escaped to the MCP client"
                )

            print(
                "stdio concurrency test: second bridge queued after readiness timeouts"
            )
        finally:
            for process in (second, first):
                if process is not None:
                    cleanup_bridge(process)


if __name__ == "__main__":
    main()
