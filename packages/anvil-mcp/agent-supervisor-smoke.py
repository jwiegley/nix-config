#!/usr/bin/env python3
"""End-to-end smoke coverage for per-MCP-bridge Anvil daemons."""

from __future__ import annotations

import importlib.util
import json
import multiprocessing
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import tempfile
import time
import traceback


HOST_ONE = "shared-home-a"
HOST_TWO = "shared-home-b"


def load_supervisor(path: Path):
    spec = importlib.util.spec_from_file_location("anvil_agent_supervisor", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load supervisor module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def eventually(predicate, timeout: float = 30.0):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            result = predicate()
        except (FileNotFoundError, json.JSONDecodeError) as error:
            last_error = error
        else:
            if result:
                return result
        time.sleep(0.1)
    if last_error is not None:
        raise AssertionError(f"condition did not become true: {last_error}")
    raise AssertionError("condition did not become true")


class BridgeProcess:
    """One real launcher process, spawned by an OwnerProxy process."""

    def __init__(self, launcher: Path, server_id: str, host: str) -> None:
        environment = os.environ.copy()
        environment.update(
            {
                "ANVIL_EMACS_HOST": host,
                "ANVIL_EMACS_WATCHDOG_STARTUP_SECONDS": "120",
                # Cold tool-schema setup can legitimately hold the root event
                # loop for several seconds.  The infinite-loop check below still
                # proves that the watchdog terminates and restarts a hung root.
                "ANVIL_EMACS_WATCHDOG_NORMAL_SECONDS": os.environ.get(
                    "ANVIL_SMOKE_WATCHDOG_NORMAL_SECONDS", "10"
                ),
                "ANVIL_EMACS_WATCHDOG_ASYNC_SECONDS": os.environ.get(
                    "ANVIL_SMOKE_WATCHDOG_ASYNC_SECONDS", "15"
                ),
                "ANVIL_EMACS_WATCHDOG_PULSE_SECONDS": "0.25",
                "ANVIL_AGENT_GRACE_SECONDS": "0.5",
                "ANVIL_AGENT_READY_SECONDS": "120",
            }
        )
        self.stderr_file = tempfile.TemporaryFile(mode="w+")
        self.process = subprocess.Popen(
            [str(launcher), f"--server-id={server_id}"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=self.stderr_file,
            env=environment,
            text=True,
            bufsize=1,
        )
        self.next_id = 1

    @property
    def pid(self) -> int:
        if self.process.pid is None:
            raise AssertionError("bridge has no PID")
        return self.process.pid

    def stderr(self) -> str:
        self.stderr_file.flush()
        self.stderr_file.seek(0)
        return self.stderr_file.read()

    def send_request(
        self,
        method: str,
        params: object | None = None,
    ) -> int:
        """Write one request without waiting, permitting pipelined calls."""
        if self.process.stdin is None:
            raise AssertionError("bridge stdin is unavailable")
        identifier = self.next_id
        self.next_id += 1
        frame: dict[str, object] = {
            "jsonrpc": "2.0",
            "id": identifier,
            "method": method,
        }
        if params is not None:
            frame["params"] = params
        self.process.stdin.write(json.dumps(frame, separators=(",", ":")) + "\n")
        self.process.stdin.flush()
        return identifier

    def receive_response(self, timeout: float = 60.0) -> dict[str, object]:
        """Read one response, allowing callers to collect out of order."""
        if self.process.stdout is None:
            raise AssertionError("bridge stdout is unavailable")
        selector = selectors.DefaultSelector()
        selector.register(self.process.stdout, selectors.EVENT_READ)
        try:
            ready = selector.select(timeout)
        finally:
            selector.close()
        if not ready:
            raise AssertionError(
                f"bridge response timed out; stderr:\n{self.stderr()}"
            )
        line = self.process.stdout.readline()
        if not line:
            raise AssertionError(
                f"bridge exited while awaiting a response with "
                f"{self.process.poll()}; stderr:\n{self.stderr()}"
            )
        response = json.loads(line)
        if not isinstance(response, dict):
            raise AssertionError(f"bridge returned a non-object response: {response!r}")
        return response

    def request(
        self,
        method: str,
        params: object | None = None,
        timeout: float = 60.0,
    ) -> dict[str, object]:
        identifier = self.send_request(method, params)
        response = self.receive_response(timeout)
        if response.get("id") != identifier:
            raise AssertionError(
                f"response id mismatch for {method}: {response!r}"
            )
        return response

    def initialize(self) -> None:
        response = self.request(
            "initialize",
            {
                "protocolVersion": "2025-03-26",
                "capabilities": {},
                "clientInfo": {
                    "name": "nix-persistent-bridge-smoke",
                    "version": "1",
                },
            },
            timeout=150,
        )
        if "error" in response:
            raise AssertionError(f"initialize failed: {response}")

    def call_tool(
        self,
        name: str,
        arguments: dict[str, object],
        timeout: float = 60.0,
    ) -> dict[str, object]:
        return self.request(
            "tools/call",
            {"name": name, "arguments": arguments},
            timeout=timeout,
        )

    def close(self) -> None:
        if self.process.poll() is None and self.process.stdin is not None:
            try:
                self.process.stdin.close()
            except BrokenPipeError:
                pass
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.stderr_file.close()


def owner_proxy_main(connection, launcher_raw: str) -> None:
    """Spawn several sibling bridges from one long-lived client process."""
    launcher = Path(launcher_raw)
    bridges: dict[str, BridgeProcess] = {}
    try:
        connection.send({"ok": True, "value": {"pid": os.getpid()}})
        while True:
            request = connection.recv()
            operation = request["operation"]
            try:
                if operation == "spawn":
                    bridge_id = request["bridge_id"]
                    if bridge_id in bridges:
                        raise AssertionError(f"duplicate bridge id: {bridge_id}")
                    bridges[bridge_id] = BridgeProcess(
                        launcher,
                        request["server_id"],
                        request["host"],
                    )
                    value = {"pid": bridges[bridge_id].process.pid}
                elif operation == "request":
                    value = bridges[request["bridge_id"]].request(
                        request["method"],
                        request.get("params"),
                        request["timeout"],
                    )
                elif operation == "close":
                    bridge = bridges.pop(request["bridge_id"], None)
                    if bridge is not None:
                        bridge.close()
                    value = None
                elif operation == "shutdown":
                    for bridge in reversed(tuple(bridges.values())):
                        bridge.close()
                    bridges.clear()
                    connection.send({"ok": True, "value": None})
                    return
                else:
                    raise AssertionError(f"unknown proxy operation: {operation}")
            except BaseException:
                connection.send({"ok": False, "error": traceback.format_exc()})
            else:
                connection.send({"ok": True, "value": value})
    except EOFError:
        pass
    finally:
        for bridge in reversed(tuple(bridges.values())):
            bridge.close()
        connection.close()


class OwnerProxy:
    """A persistent stand-in for one Codex, Claude, or agent-deck client."""

    def __init__(self, launcher: Path, name: str) -> None:
        # The harness is single-threaded here, and fork avoids Darwin's
        # import-based spawn bootstrap inside a Nix build sandbox.
        context = multiprocessing.get_context("fork")
        parent_connection, child_connection = context.Pipe()
        self.connection = parent_connection
        self.process = context.Process(
            target=owner_proxy_main,
            args=(child_connection, str(launcher)),
            name=name,
        )
        self.process.start()
        child_connection.close()
        self.bridge_ids: set[str] = set()
        if not self.connection.poll(20):
            self.process.join(timeout=0)
            exitcode = self.process.exitcode
            self.close()
            raise AssertionError(
                f"owner proxy {name} did not become ready; exitcode={exitcode}"
            )
        ready = self.connection.recv()
        if not ready.get("ok") or ready.get("value", {}).get("pid") != self.pid:
            self.close()
            raise AssertionError(f"owner proxy {name} failed startup: {ready}")

    @property
    def pid(self) -> int:
        if self.process.pid is None:
            raise AssertionError("owner proxy has no PID")
        return self.process.pid

    def rpc(self, payload: dict[str, object], timeout: float = 30.0):
        if not self.process.is_alive():
            raise AssertionError(
                f"owner proxy {self.process.name} exited with "
                f"{self.process.exitcode}"
            )
        self.connection.send(payload)
        if not self.connection.poll(timeout):
            raise AssertionError(
                f"owner proxy {self.process.name} timed out during "
                f"{payload.get('operation')}"
            )
        response = self.connection.recv()
        if not response.get("ok"):
            raise AssertionError(response.get("error", "owner proxy failed"))
        return response.get("value")

    def spawn_bridge(self, server_id: str, host: str) -> "ProxyBridge":
        bridge_id = f"bridge-{len(self.bridge_ids) + 1}-{server_id}-{host}"
        spawned = self.rpc(
            {
                "operation": "spawn",
                "bridge_id": bridge_id,
                "server_id": server_id,
                "host": host,
            }
        )
        self.bridge_ids.add(bridge_id)
        return ProxyBridge(self, bridge_id, spawned["pid"])

    def close_bridge(self, bridge_id: str) -> None:
        if bridge_id not in self.bridge_ids:
            return
        self.rpc({"operation": "close", "bridge_id": bridge_id}, timeout=20)
        self.bridge_ids.remove(bridge_id)

    def close(self) -> None:
        if self.process.is_alive():
            try:
                self.rpc({"operation": "shutdown"}, timeout=45)
            except (AssertionError, BrokenPipeError, EOFError, OSError):
                pass
        self.process.join(timeout=10)
        if self.process.is_alive():
            self.process.terminate()
            self.process.join(timeout=5)
        if self.process.is_alive():
            self.process.kill()
            self.process.join(timeout=5)
        self.bridge_ids.clear()
        self.connection.close()

    def terminate_abruptly(self) -> None:
        """Model an owning Codex process exiting with live MCP children."""
        if self.process.is_alive():
            self.process.terminate()
            self.process.join(timeout=10)
        if self.process.is_alive():
            self.process.kill()
            self.process.join(timeout=5)
        self.bridge_ids.clear()
        self.connection.close()


class ProxyBridge:
    def __init__(self, owner: OwnerProxy, bridge_id: str, pid: int) -> None:
        self.owner = owner
        self.bridge_id = bridge_id
        self.pid = pid
        self.closed = False

    def request(
        self,
        method: str,
        params: object | None = None,
        timeout: float = 60.0,
    ) -> dict[str, object]:
        return self.owner.rpc(
            {
                "operation": "request",
                "bridge_id": self.bridge_id,
                "method": method,
                "params": params,
                "timeout": timeout,
            },
            timeout=timeout + 10,
        )

    def initialize(self) -> None:
        response = self.request(
            "initialize",
            {
                "protocolVersion": "2025-03-26",
                "capabilities": {},
                "clientInfo": {
                    "name": "nix-agent-supervisor-smoke",
                    "version": "1",
                },
            },
            timeout=150,
        )
        if "error" in response:
            raise AssertionError(f"initialize failed: {response}")

    def call_tool(
        self,
        name: str,
        arguments: dict[str, object],
        timeout: float = 60.0,
    ) -> dict[str, object]:
        return self.request(
            "tools/call",
            {"name": name, "arguments": arguments},
            timeout=timeout,
        )

    def close(self) -> None:
        if self.closed:
            return
        self.owner.close_bridge(self.bridge_id)
        self.closed = True


def read_running_status(path: Path) -> dict[str, object] | bool:
    status = json.loads(path.read_text())
    if status.get("daemon_pid") is None:
        return False
    return status


def find_running_instance(
    runtime_root: Path,
    host: str,
    bridge_pid: int,
    module,
) -> tuple[Path, dict[str, object]] | bool:
    agents = runtime_root / host / "agents"
    try:
        candidates = tuple(agents.iterdir())
    except FileNotFoundError:
        return False
    for runtime_dir in candidates:
        path = runtime_dir / module.STATUS_NAME
        try:
            status = json.loads(path.read_text())
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            continue
        if status.get("owner_pid") == bridge_pid and status.get("daemon_pid"):
            return path, status
    return False


def validate_bridge_instance(
    found: tuple[Path, dict[str, object]],
    bridge: ProxyBridge,
    host: str,
    state_root: Path,
    module,
) -> dict[str, object]:
    path, status = found
    bridge_identity = module.process_start_identity(bridge.pid)
    generation = status.get("generation")
    if (
        status.get("format") != 2
        or status.get("version") != 2
        or not isinstance(generation, str)
        or module.GENERATION_PATTERN.fullmatch(generation) is None
        or status.get("owner_start_identity") != bridge_identity
        or status.get("lease_count") != 1
    ):
        raise AssertionError(f"invalid bridge lifecycle status: {status}")
    expected_key = module.derive_agent_key(
        bridge.pid,
        bridge_identity,
        generation,
    )
    if status.get("agent_key") != expected_key or path.parent.name != expected_key:
        raise AssertionError(f"bridge key did not use bridge self identity: {status}")
    runtime_dir = path.parent
    state_dir = state_root / host / "agents" / expected_key
    socket_path = runtime_dir / "emacs" / "server"
    diagnostic = runtime_dir / module.DAEMON_DIAGNOSTIC_NAME
    if not socket_path.is_socket() or not state_dir.is_dir():
        raise AssertionError(f"bridge instance paths are incomplete: {runtime_dir}")
    diagnostic_info = diagnostic.stat()
    if (
        diagnostic_info.st_mode & 0o777 != 0o600
        or diagnostic_info.st_size > module.MAX_DAEMON_DIAGNOSTIC_BYTES
    ):
        raise AssertionError(f"unsafe or unbounded daemon diagnostic: {diagnostic}")
    return {
        "bridge": bridge,
        "bridge_identity": bridge_identity,
        "diagnostic": diagnostic,
        "runtime_dir": runtime_dir,
        "socket": socket_path,
        "state_dir": state_dir,
        "status": status,
        "status_path": path,
    }


def response_text(response: dict[str, object]) -> str:
    if "error" in response:
        raise AssertionError(f"tool call failed: {response['error']}")
    result = response.get("result")
    if not isinstance(result, dict) or result.get("isError") is True:
        raise AssertionError(f"tool returned an error: {response}")
    content = result.get("content")
    if not isinstance(content, list) or len(content) != 1:
        raise AssertionError(f"unexpected tool content: {response}")
    text = content[0].get("text")
    if not isinstance(text, str):
        raise AssertionError(f"missing tool text: {response}")
    return text


def eval_value(response: dict[str, object]):
    return json.loads(response_text(response))


def snapshot_home(home: Path) -> dict[str, tuple[int, int, int]]:
    """Capture subject-visible HOME entries without following symlinks."""
    root_info = home.lstat()
    snapshot: dict[str, tuple[int, int, int]] = {
        ".": (root_info.st_mode, root_info.st_size, root_info.st_mtime_ns),
    }
    for directory, subdirectories, filenames in os.walk(home, followlinks=False):
        directory_path = Path(directory)
        for name in (*subdirectories, *filenames):
            path = directory_path / name
            info = path.lstat()
            snapshot[str(path.relative_to(home))] = (
                info.st_mode,
                info.st_size,
                info.st_mtime_ns,
            )
    return snapshot


def assert_home_unchanged(
    home: Path,
    baseline: dict[str, tuple[int, int, int]],
) -> None:
    current = snapshot_home(home)
    changed = sorted(
        name
        for name in baseline.keys() | current.keys()
        if baseline.get(name) != current.get(name)
    )
    if changed:
        raise AssertionError(
            "per-agent daemon wrote under shared HOME: "
            + ", ".join(changed[:20])
        )


def verify_home_snapshot_detects_ephemeral_child() -> None:
    """Prove create-then-remove activity remains visible through HOME."""
    with tempfile.TemporaryDirectory() as temporary:
        home = Path(temporary)
        baseline = snapshot_home(home)
        probe = home / "anvil-ephemeral-state"
        probe.write_text("temporary\n")
        probe.unlink()
        current_info = home.lstat()
        os.utime(
            home,
            ns=(
                current_info.st_atime_ns,
                max(current_info.st_mtime_ns, baseline["."][2] + 1),
            ),
        )
        try:
            assert_home_unchanged(home, baseline)
        except AssertionError:
            return
        raise AssertionError("HOME root metadata was omitted from its snapshot")


def call_after_readiness(
    bridge: ProxyBridge,
    name: str,
    arguments: dict[str, object],
    timeout: float = 150.0,
) -> dict[str, object]:
    """Retry only a request proven not to have reached the daemon."""
    deadline = time.monotonic() + timeout
    last_response = None
    while time.monotonic() < deadline:
        response = bridge.call_tool(name, arguments, timeout=30)
        if "error" not in response:
            return response
        error = response.get("error")
        data = error.get("data") if isinstance(error, dict) else None
        if not (
            isinstance(data, dict)
            and data.get("phase") == "readiness"
            and data.get("dispatched") is False
            and data.get("replayed") is False
        ):
            raise AssertionError(f"unsafe recovery response: {response}")
        last_response = response
        time.sleep(0.5)
    raise AssertionError(f"daemon did not recover before deadline: {last_response}")


def worker_pids(bridge: ProxyBridge) -> list[int]:
    expression = r"""
(progn
  (unless anvil-worker--pool
    (anvil-worker--init-pool))
  (anvil-worker-spawn)
  (let ((deadline (+ (float-time) 90)))
    (while (and (< (float-time) deadline)
                (let ((ready t))
                  (anvil-worker--map-pool
                   (lambda (worker)
                     (unless (anvil-worker--worker-alive-p worker)
                       (setq ready nil))))
                  (not ready)))
      (sleep-for 0.1)))
  (let (pids)
    (maphash
     (lambda (_name process)
       (when (process-live-p process)
         (push (process-id process) pids)))
     anvil-worker--owned-processes)
    (json-serialize (vconcat (sort pids #'<)))))
""".strip()
    encoded = eval_value(
        bridge.call_tool(
            "emacs-eval", {"expression": expression}, timeout=110
        )
    )
    if not isinstance(encoded, str):
        raise AssertionError(f"worker PID expression was not JSON: {encoded!r}")
    pids = json.loads(encoded)
    if not isinstance(pids, list) or len(pids) != 4:
        raise AssertionError(f"all four workers did not start: {pids!r}")
    if not all(isinstance(pid, int) and pid > 1 for pid in pids):
        raise AssertionError(f"invalid worker PIDs: {pids!r}")
    return pids


def assert_launcher_rejects(
    launcher: Path,
    expected_status: int,
    expected_text: str,
    *extra: str,
) -> None:
    environment = os.environ.copy()
    environment["ANVIL_EMACS_HOST"] = HOST_ONE
    completed = subprocess.run(
        [str(launcher), *extra],
        input="",
        text=True,
        capture_output=True,
        env=environment,
        # Darwin builders can briefly starve a cold Nix-store process while
        # other live-daemon checks start.  The exact status/text below, not a
        # scheduler-sensitive wall-clock threshold, proves fail-fast parsing.
        timeout=30,
        check=False,
    )
    if completed.returncode != expected_status or expected_text not in completed.stderr:
        raise AssertionError(
            f"launcher rejection mismatch: status={completed.returncode}\n"
            f"stdout={completed.stdout}\nstderr={completed.stderr}"
        )


def assert_typed_registry_probe(bridge: ProxyBridge, launcher: Path) -> None:
    """Require one real call through the direct typed-only registry."""
    response = bridge.call_tool(
        "file-read",
        {"path": str(launcher)},
    )
    if "anvil-mcp" not in response_text(response):
        raise AssertionError(f"direct typed registry stopped serving: {response}")


def verify_generation_rollover(
    old_launcher: Path,
    new_launcher: Path,
    runtime_root: Path,
    state_root: Path,
    module,
) -> None:
    """Keep an old bridge pinned while a new package generation starts."""
    old_owner = OwnerProxy(old_launcher, "old-generation-owner")
    new_owner = OwnerProxy(new_launcher, "new-generation-owner")
    old_bridge = old_owner.spawn_bridge("anvil", "generation-rollover")
    new_bridge: ProxyBridge | None = None
    instances: list[dict[str, object]] = []
    try:
        old_bridge.initialize()
        old_instance = validate_bridge_instance(
            eventually(
                lambda: find_running_instance(
                    runtime_root,
                    "generation-rollover",
                    old_bridge.pid,
                    module,
                )
            ),
            old_bridge,
            "generation-rollover",
            state_root,
            module,
        )
        instances.append(old_instance)
        old_generation = old_instance["status"]["generation"]
        old_daemon = old_instance["status"]["daemon_pid"]
        if eval_value(
            old_bridge.call_tool("emacs-eval", {"expression": "(+ 40 2)"})
        ) != 42:
            raise AssertionError("old generation failed before rollover")

        new_bridge = new_owner.spawn_bridge("anvil", "generation-rollover")
        new_bridge.initialize()
        new_instance = validate_bridge_instance(
            eventually(
                lambda: find_running_instance(
                    runtime_root,
                    "generation-rollover",
                    new_bridge.pid,
                    module,
                )
            ),
            new_bridge,
            "generation-rollover",
            state_root,
            module,
        )
        instances.append(new_instance)
        new_generation = new_instance["status"]["generation"]
        if new_generation == old_generation:
            raise AssertionError(
                f"package rollover reused generation {old_generation!r}"
            )
        if (
            new_instance["runtime_dir"] == old_instance["runtime_dir"]
            or new_instance["state_dir"] == old_instance["state_dir"]
            or new_instance["socket"] == old_instance["socket"]
        ):
            raise AssertionError("package generations shared mutable state")

        old_status = read_running_status(old_instance["status_path"])
        if (
            not old_status
            or old_status["generation"] != old_generation
            or old_status["daemon_pid"] != old_daemon
        ):
            raise AssertionError(
                f"new launcher displaced the old generation: {old_status}"
            )
        if eval_value(
            new_bridge.call_tool("emacs-eval", {"expression": "(+ 20 22)"})
        ) != 42:
            raise AssertionError("new generation did not serve a real request")
        new_bridge.close()
        if eval_value(
            old_bridge.call_tool("emacs-eval", {"expression": "(+ 21 21)"})
        ) != 42:
            raise AssertionError("closing the new generation harmed the old bridge")
        old_bridge.close()
    finally:
        if new_bridge is not None and not new_bridge.closed:
            new_bridge.close()
        if not old_bridge.closed:
            old_bridge.close()
        new_owner.close()
        old_owner.close()
    for instance in instances:
        eventually(lambda instance=instance: not instance["runtime_dir"].exists())
        eventually(lambda instance=instance: not instance["state_dir"].exists())


def verify_readiness_crash_recovery(
    launcher: Path,
    runtime_root: Path,
    state_root: Path,
    module,
) -> None:
    """Recover behind one MCP pipe when the first root dies before readiness."""
    owner = OwnerProxy(launcher, "readiness-crash-owner")
    bridge = owner.spawn_bridge("anvil", "readiness-crash")
    instance: dict[str, object] | None = None
    try:
        bridge.initialize()
        instance = validate_bridge_instance(
            eventually(
                lambda: find_running_instance(
                    runtime_root,
                    "readiness-crash",
                    bridge.pid,
                    module,
                )
            ),
            bridge,
            "readiness-crash",
            state_root,
            module,
        )
        sentinel = instance["runtime_dir"] / ".readiness-crashed-once"
        status = instance["status"]
        if not sentinel.is_file():
            raise AssertionError("readiness crash wrapper never ran")
        if (
            status.get("restart_count", 0) < 1
            or status.get("restart_reason") != "daemon-exited:70"
        ):
            raise AssertionError(
                f"readiness crash was not retained in status: {status}"
            )
        if eval_value(
            bridge.call_tool("emacs-eval", {"expression": "(+ 39 3)"})
        ) != 42:
            raise AssertionError("same bridge failed after readiness crash")
        bridge.close()
    finally:
        if not bridge.closed:
            bridge.close()
        owner.close()
    if instance is not None:
        eventually(lambda: not instance["runtime_dir"].exists())
        eventually(lambda: not instance["state_dir"].exists())


def main() -> None:
    if len(sys.argv) not in (3, 5):
        raise SystemExit(
            "usage: agent-supervisor-smoke.py /path/to/anvil-mcp "
            "/path/to/agent-supervisor.py "
            "[/path/to/rollover-anvil-mcp /path/to/readiness-crash-anvil-mcp]"
        )
    launcher = Path(sys.argv[1]).resolve()
    module = load_supervisor(Path(sys.argv[2]).resolve())
    rollover_launcher = Path(sys.argv[3]).resolve() if len(sys.argv) == 5 else None
    readiness_crash_launcher = (
        Path(sys.argv[4]).resolve() if len(sys.argv) == 5 else None
    )
    runtime_root = Path(os.environ["ANVIL_EMACS_RUNTIME_ROOT"])
    state_root = Path(os.environ["ANVIL_EMACS_STATE_ROOT"])
    home = Path.home()
    verify_home_snapshot_detects_ephemeral_child()
    home_baseline = snapshot_home(home)

    assert_launcher_rejects(
        launcher,
        64,
        "--socket cannot override a per-agent daemon",
        "--socket=/tmp/spoofed-anvil-socket",
    )
    if rollover_launcher is not None and readiness_crash_launcher is not None:
        verify_generation_rollover(
            launcher,
            rollover_launcher,
            runtime_root,
            state_root,
            module,
        )
        verify_readiness_crash_recovery(
            readiness_crash_launcher,
            runtime_root,
            state_root,
            module,
        )

    owners: list[OwnerProxy] = []
    bridges: list[ProxyBridge] = []
    main_owner = OwnerProxy(launcher, "codex-main-owner")
    owners.append(main_owner)
    other_owner = OwnerProxy(launcher, "codex-agent-deck-owner")
    owners.append(other_owner)
    main_typed = main_owner.spawn_bridge("anvil", HOST_ONE)
    main_eval = main_owner.spawn_bridge("emacs-eval", HOST_ONE)
    other_agent = other_owner.spawn_bridge("anvil", HOST_ONE)
    other_host = main_owner.spawn_bridge("anvil", HOST_TWO)
    bridges.extend((main_typed, main_eval, other_agent, other_host))
    try:
        for bridge in bridges:
            bridge.initialize()
        instances = {}
        for name, bridge, host in (
            ("main-typed", main_typed, HOST_ONE),
            ("main-eval", main_eval, HOST_ONE),
            ("other-agent", other_agent, HOST_ONE),
            ("other-host", other_host, HOST_TWO),
        ):
            found = eventually(
                lambda bridge=bridge, host=host: find_running_instance(
                    runtime_root,
                    host,
                    bridge.pid,
                    module,
                )
            )
            instances[name] = validate_bridge_instance(
                found,
                bridge,
                host,
                state_root,
                module,
            )

        # Every launcher bridge is its own lifecycle domain.  This includes
        # the two siblings created by the exact same client process.
        for field in ("agent_key", "daemon_pid", "supervisor_pid"):
            values = {instance["status"][field] for instance in instances.values()}
            if len(values) != len(instances):
                raise AssertionError(f"bridge instances shared {field}: {values}")
        for field in ("runtime_dir", "state_dir", "socket"):
            values = {instance[field] for instance in instances.values()}
            if len(values) != len(instances):
                raise AssertionError(f"bridge instances shared {field}: {values}")
        generations = {
            instance["status"]["generation"] for instance in instances.values()
        }
        if len(generations) != 1:
            raise AssertionError(f"one launcher exposed mixed generations: {generations}")
        assert_home_unchanged(home, home_baseline)

        agent_instance = instances["other-agent"]
        agent_supervisor_identity = module.process_start_identity(
            agent_instance["status"]["supervisor_pid"]
        )
        agent_daemon_identity = module.process_start_identity(
            agent_instance["status"]["daemon_pid"]
        )
        other_owner.terminate_abruptly()
        owners.remove(other_owner)
        other_agent.closed = True
        bridges.remove(other_agent)
        eventually(lambda: not agent_instance["status_path"].exists())
        eventually(lambda: not agent_instance["runtime_dir"].exists())
        eventually(lambda: not agent_instance["state_dir"].exists())
        for pid, identity in (
            (other_agent.pid, agent_instance["bridge_identity"]),
            (
                agent_instance["status"]["supervisor_pid"],
                agent_supervisor_identity,
            ),
            (agent_instance["status"]["daemon_pid"], agent_daemon_identity),
        ):
            eventually(
                lambda pid=pid, identity=identity: (
                    module.process_start_identity(pid) != identity
                )
            )

        other_host.close()
        bridges.remove(other_host)
        host_instance = instances["other-host"]
        eventually(lambda: not host_instance["runtime_dir"].exists())
        eventually(lambda: not host_instance["state_dir"].exists())

        typed_instance = instances["main-typed"]
        eval_instance = instances["main-eval"]
        bridge_identity = module.process_start_identity(main_typed.pid)
        original_supervisor_pid = typed_instance["status"]["supervisor_pid"]
        original_supervisor_identity = module.process_start_identity(
            original_supervisor_pid
        )
        original_daemon_pid = typed_instance["status"]["daemon_pid"]
        original_daemon_identity = module.process_start_identity(
            original_daemon_pid
        )
        os.kill(original_supervisor_pid, signal.SIGKILL)
        caretaker_recovered = eventually(
            lambda: (
                (current := read_running_status(typed_instance["status_path"]))
                and current["supervisor_pid"] != original_supervisor_pid
                and current["daemon_pid"] != original_daemon_pid
                and current
            ),
            timeout=150,
        )
        if module.process_start_identity(main_typed.pid) != bridge_identity:
            raise AssertionError("supervisor recovery replaced the bridge process")
        if caretaker_recovered["owner_pid"] != main_typed.pid:
            raise AssertionError(
                f"caretaker lost bridge ownership: {caretaker_recovered}"
            )
        recovery_started = time.monotonic()
        caretaker_probe = call_after_readiness(
            main_typed,
            "emacs-eval",
            {"expression": "(+ 21 21)"},
            timeout=150,
        )
        if eval_value(caretaker_probe) != 42:
            raise AssertionError(
                f"same stdio pipe did not recover: {caretaker_probe}"
            )
        if time.monotonic() - recovery_started >= 150:
            raise AssertionError("same-pipe supervisor recovery exceeded its bound")
        for pid, identity in (
            (original_supervisor_pid, original_supervisor_identity),
            (original_daemon_pid, original_daemon_identity),
        ):
            eventually(
                lambda pid=pid, identity=identity: (
                    module.process_start_identity(pid) != identity
                )
            )
        typed_instance["status"] = caretaker_recovered

        root_pid = typed_instance["status"]["daemon_pid"]
        supervisor_pid = typed_instance["status"]["supervisor_pid"]
        eval_daemon_pid = eval_instance["status"]["daemon_pid"]
        workers = worker_pids(main_typed)
        worker_identities = {
            pid: module.process_start_identity(pid) for pid in workers
        }
        if any(identity is None for identity in worker_identities.values()):
            raise AssertionError(f"worker identity disappeared: {worker_identities}")

        nonce = typed_instance["runtime_dir"] / "watchdog-dispatch-nonce"
        hanging_expression = (
            f"(progn (write-region \"once\\n\" nil {json.dumps(str(nonce))} "
            "t 'silent) (while t))"
        )
        hung_response = main_typed.call_tool(
            "emacs-eval",
            {"expression": hanging_expression},
            timeout=30,
        )
        if "error" not in hung_response:
            raise AssertionError(
                f"hung root request did not return a synthetic error: {hung_response}"
            )
        restarted = eventually(
            lambda: (
                (current := read_running_status(typed_instance["status_path"]))
                and current["daemon_pid"] != root_pid
                and current
            )
        )
        if restarted["supervisor_pid"] != supervisor_pid:
            raise AssertionError("root restart replaced the owning supervisor")
        if (
            restarted.get("restart_count", 0) < 1
            or not str(restarted.get("restart_reason", "")).startswith(
                "daemon-exited:"
            )
            or restarted.get("generation")
            != typed_instance["status"]["generation"]
        ):
            raise AssertionError(f"restart diagnostics were not retained: {restarted}")
        if nonce.read_text().splitlines() != ["once"]:
            raise AssertionError("the ambiguous hung request was replayed")
        eval_status = read_running_status(eval_instance["status_path"])
        if not eval_status or eval_status["daemon_pid"] != eval_daemon_pid:
            raise AssertionError("hung sibling restarted the independent eval daemon")
        assert_typed_registry_probe(main_eval, launcher)
        recovered = call_after_readiness(
            main_typed,
            "emacs-eval",
            {"expression": "(+ 40 2)"},
        )
        if eval_value(recovered) != 42:
            raise AssertionError(f"same bridge did not recover: {recovered}")

        restarted_pid = restarted["daemon_pid"]
        restarted_identity = module.process_start_identity(restarted_pid)
        main_typed.close()
        bridges.remove(main_typed)
        eventually(lambda: not typed_instance["runtime_dir"].exists())
        eventually(lambda: not typed_instance["state_dir"].exists())
        eventually(
            lambda: module.process_start_identity(restarted_pid)
            != restarted_identity
        )
        assert_typed_registry_probe(main_eval, launcher)

        eval_daemon_identity = module.process_start_identity(eval_daemon_pid)
        main_eval.close()
        bridges.remove(main_eval)
        eventually(lambda: not eval_instance["runtime_dir"].exists())
        eventually(lambda: not eval_instance["state_dir"].exists())
        eventually(
            lambda: module.process_start_identity(eval_daemon_pid)
            != eval_daemon_identity
        )
        for pid, identity in worker_identities.items():
            eventually(
                lambda pid=pid, identity=identity: (
                    module.process_start_identity(pid) != identity
                )
            )

        main_owner.close()
        owners.remove(main_owner)
    finally:
        for bridge in reversed(bridges):
            bridge.close()
        for owner in reversed(owners):
            owner.close()
    assert_home_unchanged(home, home_baseline)


if __name__ == "__main__":
    main()
