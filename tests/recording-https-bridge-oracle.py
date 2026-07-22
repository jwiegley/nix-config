#!/usr/bin/env python3
"""Recording HTTPS and non-persistence oracle for the static-header bridge."""

from __future__ import annotations

import argparse
import json
import os
import secrets
import selectors
import ssl
import subprocess
import sys
import threading
import time
from contextlib import suppress
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


class OracleFailure(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise OracleFailure(message)


class RecordingServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(
        self,
        address: tuple[str, int],
        certificate: Path,
        private_key: Path,
        header_name: str,
        secret: str,
    ) -> None:
        super().__init__(address, RecordingHandler)
        self.header_name = header_name
        self.secret = secret
        self.requests: list[dict[str, Any]] = []
        self.requests_lock = threading.Lock()
        self.thread_error = False
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certificate, private_key)
        self.socket = context.wrap_socket(self.socket, server_side=True)

    def record(self, entry: dict[str, Any]) -> None:
        with self.requests_lock:
            self.requests.append(entry)

    def snapshot(self) -> list[dict[str, Any]]:
        with self.requests_lock:
            return list(self.requests)

    def handle_error(self, request: Any, client_address: Any) -> None:
        self.thread_error = True


class RecordingHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server: RecordingServer

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _send(self, status: int, body: bytes = b"", **headers: str) -> None:
        self.send_response(status)
        for name, value in headers.items():
            self.send_header(name.replace("_", "-"), value)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _handle(self) -> None:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = -1
        if length < 0 or length > 1024 * 1024:
            self._send(400)
            return

        body = self.rfile.read(length)
        header_values = self.headers.get_all(self.server.header_name) or []
        header_exact = header_values == [self.server.secret]
        body_clean = self.server.secret.encode() not in body
        path_clean = self.server.secret not in self.path
        body_method = None
        request_id = 1
        try:
            parsed = json.loads(body)
            if isinstance(parsed, dict):
                body_method = parsed.get("method")
                request_id = parsed.get("id", 1)
        except (UnicodeDecodeError, json.JSONDecodeError):
            pass

        self.server.record(
            {
                "method": self.command,
                "path": self.path,
                "headerExact": header_exact,
                "bodyClean": body_clean,
                "pathClean": path_clean,
                "bodyMethod": body_method,
            }
        )
        if not header_exact or not body_clean or not path_clean:
            self._send(403)
            return

        initialized_paths = {"/ok", "/sse-redirect", "/sse-closed"}
        if self.path in initialized_paths and body_method == "initialize":
            response = json.dumps(
                {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {
                        "protocolVersion": "2025-03-26",
                        "capabilities": {},
                        "serverInfo": {"name": "task3-oracle", "version": "1"},
                    },
                },
                separators=(",", ":"),
            ).encode()
            self._send(200, response, Content_Type="application/json")
        elif (
            self.path in initialized_paths
            and self.command == "POST"
            and body_method == "notifications/initialized"
        ):
            self._send(202)
        elif self.path == "/sse-redirect" and self.command == "GET":
            origin = f"https://127.0.0.1:{self.server.server_port}"
            self._send(307, Location=f"{origin}/redirect-target")
        elif self.path == "/sse-closed" and self.command == "GET":
            self._send(200, Content_Type="text/event-stream")
        elif self.path == "/unauthorized":
            origin = f"https://127.0.0.1:{self.server.server_port}"
            self._send(
                401,
                WWW_Authenticate=(
                    'Bearer error="invalid_token", '
                    f'resource_metadata="{origin}/.well-known/oauth-protected-resource"'
                ),
            )
        elif self.path == "/redirect-target":
            self._send(204)
        else:
            self._send(418)

    do_DELETE = _handle
    do_GET = _handle
    do_HEAD = _handle
    do_OPTIONS = _handle
    do_PATCH = _handle
    do_POST = _handle
    do_PUT = _handle


def read_events(path: Path) -> list[dict[str, Any]]:
    events = []
    for line in path.read_text().splitlines():
        if line:
            value = json.loads(line)
            require(isinstance(value, dict), "guard emitted a non-object event")
            events.append(value)
    return events


def terminate(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=1)


def collect(process: subprocess.Popen[bytes]) -> tuple[bytes, bytes]:
    if process.stdin is not None and not process.stdin.closed:
        with suppress(BrokenPipeError):
            process.stdin.close()
    stdout = process.stdout.read() if process.stdout is not None else b""
    stderr = process.stderr.read() if process.stderr is not None else b""
    return stdout, stderr


def invoke_bridge(
    bridge: Path,
    guard: Path,
    certificate: Path,
    case_root: Path,
    url: str,
    header_name: str,
    env_name: str,
    secret: str,
    send_initialized: bool,
    expect_initial_response: bool,
    expect_success: bool,
    expected_methods: tuple[str, ...],
) -> tuple[int, bytes, bytes, list[dict[str, Any]]]:
    for name in (
        "cwd",
        "home",
        "tmp",
        "xdg-cache",
        "xdg-config",
        "xdg-state",
        "shims",
    ):
        (case_root / name).mkdir(parents=True, exist_ok=True)

    event_file = case_root / "guard-events.jsonl"
    event_file.write_bytes(b"")
    event_file.chmod(0o600)
    config_sentry = case_root / "config-sentry"
    config_sentry.write_text("configuration access is forbidden\n")
    browser_marker = case_root / "browser-invoked"
    browser_shim = case_root / "shims" / "browser-shim"
    browser_shim.write_text(
        f"#!/bin/sh\n: > {json.dumps(str(browser_marker))}\nexit 97\n"
    )
    browser_shim.chmod(0o700)
    for name in ("gio", "open", "sensible-browser", "xdg-open"):
        (case_root / "shims" / name).symlink_to(browser_shim.name)

    internal_args = [
        url,
        "--header",
        f"{header_name}: ${{{env_name}}}",
        "--header-only",
        "--transport",
        "http-only",
        "--silent",
    ]
    environment = os.environ.copy()
    for name in (
        "ALL_PROXY",
        "HTTPS_PROXY",
        "HTTP_PROXY",
        "NODE_OPTIONS",
        "OLDPWD",
        "all_proxy",
        "https_proxy",
        "http_proxy",
    ):
        environment.pop(name, None)
    environment.update(
        {
            "BROWSER": str(browser_shim),
            "HOME": str(case_root / "home"),
            "MCP_REMOTE_CONFIG_DIR": str(config_sentry),
            "NODE_EXTRA_CA_CERTS": str(certificate),
            "NODE_OPTIONS": f"--require={guard}",
            "NO_PROXY": "127.0.0.1,localhost",
            "PATH": f"{case_root / 'shims'}:{environment.get('PATH', '')}",
            "PWD": str(case_root / "cwd"),
            "TASK3_ORACLE_EVENT_FILE": str(event_file),
            "TASK3_ORACLE_EXPECTED_ARGS": json.dumps(internal_args, separators=(",", ":")),
            "TASK3_ORACLE_PARENT_PID": str(os.getpid()),
            "TASK3_ORACLE_SECRET_ENV_NAME": env_name,
            "TASK3_ORACLE_URL": url,
            "TMP": str(case_root / "tmp"),
            "TMPDIR": str(case_root / "tmp"),
            "TEMP": str(case_root / "tmp"),
            "XDG_CACHE_HOME": str(case_root / "xdg-cache"),
            "XDG_CONFIG_HOME": str(case_root / "xdg-config"),
            "XDG_STATE_HOME": str(case_root / "xdg-state"),
            env_name: secret,
        }
    )
    process = subprocess.Popen(
        [str(bridge), url, header_name, env_name],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
        close_fds=True,
        cwd=case_root / "cwd",
    )
    initialize = (
        json.dumps(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-03-26",
                    "capabilities": {},
                    "clientInfo": {"name": "task3-oracle-client", "version": "1"},
                },
            },
            separators=(",", ":"),
        ).encode()
        + b"\n"
    )
    initialized = (
        json.dumps(
            {
                "jsonrpc": "2.0",
                "method": "notifications/initialized",
                "params": {},
            },
            separators=(",", ":"),
        ).encode()
        + b"\n"
    )

    try:
        require(process.stdin is not None, "bridge stdin was not created")
        process.stdin.write(initialize)
        process.stdin.flush()
        first_line = b""
        if expect_initial_response:
            require(process.stdout is not None, "bridge stdout was not created")
            selector = selectors.DefaultSelector()
            selector.register(process.stdout, selectors.EVENT_READ)
            ready = selector.select(timeout=8)
            selector.close()
            require(bool(ready), "bridge produced no initial MCP response")
            first_line = process.stdout.readline()
            require(bool(first_line), "bridge closed before its initial MCP response")
        if send_initialized:
            process.stdin.write(initialized)
            process.stdin.flush()
        if expect_success:
            process.stdin.close()
        process.wait(timeout=8)
        remaining_stdout, stderr = collect(process)
        stdout = first_line + remaining_stdout
    except (BrokenPipeError, subprocess.TimeoutExpired):
        terminate(process)
        raise OracleFailure(
            "bridge process did not satisfy its bounded lifecycle"
        ) from None
    finally:
        terminate(process)

    require(secret.encode() not in stdout, "bridge stdout leaked the credential")
    require(secret.encode() not in stderr, "bridge stderr leaked the credential")
    require(
        config_sentry.read_text() == "configuration access is forbidden\n",
        "config sentry changed",
    )
    require(not browser_marker.exists(), "browser shim was invoked")
    events = read_events(event_file)
    require(
        len(events) == len(expected_methods) + 1,
        "guard observed an unexpected runtime operation",
    )
    require(
        events[0]
        == {"event": "argv", "argvExact": True, "directExec": True},
        "bridge argv or direct-exec contract differed",
    )
    for fetch, expected_method in zip(events[1:], expected_methods, strict=True):
        require(fetch.get("event") == "fetch", "guard observed a non-fetch event")
        for key in ("allowedUrl", "environmentDeleted", "redirectIsError"):
            require(fetch.get(key) is True, "outbound request violated the guard")
        require(
            fetch.get("method") == expected_method,
            "bridge used an unexpected MCP request method",
        )
    return process.returncode, stdout, stderr, events


def assert_requests(
    requests: list[dict[str, Any]],
    expected_path: str,
    expected: tuple[tuple[str, str | None], ...],
) -> None:
    require(
        len(requests) == len(expected),
        "bridge performed discovery, retry, or redirect traffic",
    )
    for request, (expected_method, expected_body_method) in zip(
        requests, expected, strict=True
    ):
        require(
            request.get("method") == expected_method,
            "server received an unexpected request method",
        )
        require(
            request.get("path") == expected_path,
            "server received an unexpected path",
        )
        require(
            request.get("headerExact") is True,
            "server did not receive the credential",
        )
        require(
            request.get("bodyClean") is True,
            "credential entered the MCP body",
        )
        require(
            request.get("pathClean") is True,
            "credential entered the request URL",
        )
        require(
            request.get("bodyMethod") == expected_body_method,
            "server received an unexpected MCP method",
        )


def scan_file(path: Path, needle: bytes) -> None:
    with path.open("rb") as source:
        overlap = b""
        while True:
            chunk = source.read(1024 * 1024)
            if not chunk:
                return
            data = overlap + chunk
            require(needle not in data, "credential persisted in a regular file")
            overlap = data[-max(0, len(needle) - 1) :]


def scan_tree(root: Path, secret: str) -> None:
    needle = secret.encode()
    require(needle not in os.fsencode(str(root)), "credential entered a root path")
    if root.is_symlink():
        require(needle not in os.fsencode(os.readlink(root)), "credential entered a link")
        return
    if root.is_file():
        scan_file(root, needle)
        return
    require(root.is_dir(), "scan root is neither file nor directory")
    for directory, names, files in os.walk(root, followlinks=False):
        require(needle not in os.fsencode(directory), "credential entered a directory name")
        for name in [*names, *files]:
            path = Path(directory) / name
            require(needle not in os.fsencode(name), "credential entered a filename")
            if path.is_symlink():
                require(needle not in os.fsencode(os.readlink(path)), "credential entered a link")
            elif path.is_file():
                scan_file(path, needle)
            elif not path.is_dir():
                raise OracleFailure("runtime or closure contains an unexpected special file")


def scan_closure(paths_file: Path, secret: str) -> None:
    roots = [Path(line) for line in paths_file.read_text().splitlines() if line]
    require(bool(roots), "bridge closure path list is empty")
    for root in roots:
        require(str(root).startswith("/nix/store/"), "closure contains a non-store path")
        scan_tree(root, secret)


def assert_runtime_inventory(runtime_root: Path) -> None:
    expected: dict[str, tuple[str, str | None]] = {}
    for label in ("success", "unauthorized", "sse-redirect", "sse-closed"):
        expected[label] = ("directory", None)
        for directory in (
            "cwd",
            "home",
            "tmp",
            "xdg-cache",
            "xdg-config",
            "xdg-state",
            "shims",
        ):
            expected[f"{label}/{directory}"] = ("directory", None)
        expected[f"{label}/config-sentry"] = ("file", None)
        expected[f"{label}/guard-events.jsonl"] = ("file", None)
        expected[f"{label}/shims/browser-shim"] = ("file", None)
        for name in ("gio", "open", "sensible-browser", "xdg-open"):
            expected[f"{label}/shims/{name}"] = ("symlink", "browser-shim")

    actual: dict[str, tuple[str, str | None]] = {}
    for directory, names, files in os.walk(runtime_root, followlinks=False):
        for name in [*names, *files]:
            path = Path(directory) / name
            relative = path.relative_to(runtime_root).as_posix()
            if path.is_symlink():
                actual[relative] = ("symlink", os.readlink(path))
            elif path.is_dir():
                actual[relative] = ("directory", None)
            elif path.is_file():
                actual[relative] = ("file", None)
            else:
                actual[relative] = ("special", None)
    require(actual == expected, "bridge created an unexpected runtime artifact")


def run(args: argparse.Namespace) -> None:
    bridge = args.bridge.resolve()
    guard = args.guard.resolve()
    certificate = args.certificate.resolve()
    private_key = args.private_key.resolve()
    runtime_root = args.runtime_root.resolve()
    closure_paths = args.closure_paths.resolve()
    for path, label in (
        (bridge, "bridge"),
        (guard, "guard"),
        (certificate, "certificate"),
        (private_key, "private key"),
        (closure_paths, "closure list"),
    ):
        require(path.is_file(), f"{label} input is missing")
    require(os.access(bridge, os.X_OK), "bridge is not executable")

    runtime_root.mkdir(parents=True, exist_ok=False)
    secret = f"task3-{secrets.token_hex(32)}"
    env_name = "TASK3_BRIDGE_TOKEN"
    header_name = "x-task3-bridge-key"
    server = RecordingServer(
        ("127.0.0.1", 0), certificate, private_key, header_name, secret
    )
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    origin = f"https://127.0.0.1:{server.server_port}"
    report: dict[str, Any] = {"cases": {}}

    try:
        for (
            label,
            path,
            send_initialized,
            expect_initial_response,
            success,
            expected_requests,
        ) in (
            ("success", "/ok", False, True, True, (("POST", "initialize"),)),
            (
                "unauthorized",
                "/unauthorized",
                False,
                False,
                False,
                (("POST", "initialize"),),
            ),
            (
                "sse-redirect",
                "/sse-redirect",
                True,
                True,
                False,
                (
                    ("POST", "initialize"),
                    ("POST", "notifications/initialized"),
                    ("GET", None),
                ),
            ),
            (
                "sse-closed",
                "/sse-closed",
                True,
                True,
                False,
                (
                    ("POST", "initialize"),
                    ("POST", "notifications/initialized"),
                    ("GET", None),
                ),
            ),
        ):
            before = len(server.snapshot())
            status, stdout, stderr, events = invoke_bridge(
                bridge,
                guard,
                certificate,
                runtime_root / label,
                f"{origin}{path}",
                header_name,
                env_name,
                secret,
                send_initialized,
                expect_initial_response,
                success,
                tuple(method for method, _body_method in expected_requests),
            )
            time.sleep(0.1)
            requests = server.snapshot()[before:]
            assert_requests(requests, path, expected_requests)
            lines = [line for line in stdout.splitlines() if line]
            if expect_initial_response:
                require(len(lines) == 1, "initial bridge output shape differed")
                response = json.loads(lines[0])
                require(
                    response.get("jsonrpc") == "2.0" and response.get("id") == 1,
                    "bridge returned an invalid initial envelope",
                )
            else:
                require(stdout == b"", "pre-initialize failure wrote to stdout")

            if success:
                require(status == 0, "successful bridge exited nonzero")
                require(stderr == b"", "successful bridge wrote to stderr")
            else:
                require(status != 0, "failing transport returned success")
                require(
                    stderr == b"agent-http-header-bridge: transport failed\n",
                    "failing transport error differed",
                )
                require(0 < len(stderr) <= 512, "transport error was not bounded")
            report["cases"][label] = {
                "exitStatus": status,
                "requests": requests,
                "guardEvents": events,
            }
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    require(not server.thread_error, "recording server failed internally")
    assert_runtime_inventory(runtime_root)
    (runtime_root / "oracle-report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n"
    )
    scan_tree(runtime_root.parent, secret)
    scan_closure(closure_paths, secret)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bridge", type=Path, required=True)
    parser.add_argument("--guard", type=Path, required=True)
    parser.add_argument("--certificate", type=Path, required=True)
    parser.add_argument("--private-key", type=Path, required=True)
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--closure-paths", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    try:
        run(parse_args())
    except OracleFailure as error:
        print(f"agent-http-header-bridge oracle: {error}", file=sys.stderr)
        return 1
    except Exception:
        print("agent-http-header-bridge oracle: harness failed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
