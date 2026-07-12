#!/usr/bin/env python3
"""End-to-end smoke coverage for per-Codex-process Anvil daemons."""

from __future__ import annotations

import importlib.util
import json
import multiprocessing
import os
from pathlib import Path
import selectors
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
    """One real launcher process, owned directly by an OwnerProxy process."""

    def __init__(self, launcher: Path, server_id: str, host: str) -> None:
        environment = os.environ.copy()
        environment.update(
            {
                "ANVIL_EMACS_HOST": host,
                "ANVIL_EMACS_WATCHDOG_STARTUP_SECONDS": "120",
                # Cold tool-schema setup can legitimately hold the root event
                # loop for several seconds.  The infinite-loop check below still
                # proves that the watchdog terminates and restarts a hung root.
                "ANVIL_EMACS_WATCHDOG_NORMAL_SECONDS": "10",
                "ANVIL_EMACS_WATCHDOG_ASYNC_SECONDS": "15",
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

    def stderr(self) -> str:
        self.stderr_file.flush()
        self.stderr_file.seek(0)
        return self.stderr_file.read()

    def request(
        self,
        method: str,
        params: object | None = None,
        timeout: float = 60.0,
    ) -> dict[str, object]:
        if self.process.stdin is None or self.process.stdout is None:
            raise AssertionError("bridge pipes are unavailable")
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

        selector = selectors.DefaultSelector()
        selector.register(self.process.stdout, selectors.EVENT_READ)
        try:
            ready = selector.select(timeout)
        finally:
            selector.close()
        if not ready:
            raise AssertionError(
                f"bridge request {method} timed out; stderr:\n{self.stderr()}"
            )
        line = self.process.stdout.readline()
        if not line:
            raise AssertionError(
                f"bridge exited during {method} with {self.process.poll()}; "
                f"stderr:\n{self.stderr()}"
            )
        response = json.loads(line)
        if response.get("id") != identifier:
            raise AssertionError(
                f"response id mismatch for {method}: {response!r}"
            )
        return response

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
    """Own several bridges exactly as one Codex OS process would."""
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
    """A persistent stand-in for one Codex or agent-deck OS process."""

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


def status_path(runtime_root: Path, host: str, agent_key: str, module) -> Path:
    return runtime_root / host / "agents" / agent_key / module.STATUS_NAME


def read_running_status(path: Path) -> dict[str, object] | bool:
    status = json.loads(path.read_text())
    if status.get("daemon_pid") is None:
        return False
    return status


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
        timeout=10,
        check=False,
    )
    if completed.returncode != expected_status or expected_text not in completed.stderr:
        raise AssertionError(
            f"launcher rejection mismatch: status={completed.returncode}\n"
            f"stdout={completed.stdout}\nstderr={completed.stderr}"
        )


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(
            "usage: agent-supervisor-smoke.py /path/to/anvil-mcp "
            "/path/to/agent-supervisor.py"
        )
    launcher = Path(sys.argv[1]).resolve()
    module = load_supervisor(Path(sys.argv[2]).resolve())
    runtime_root = Path(os.environ["ANVIL_EMACS_RUNTIME_ROOT"])
    state_root = Path(os.environ["ANVIL_EMACS_STATE_ROOT"])

    assert_launcher_rejects(
        launcher,
        64,
        "--socket cannot override a per-agent daemon",
        "--socket=/tmp/spoofed-anvil-socket",
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

        main_owner_identity = eventually(
            lambda: module.process_start_identity(main_owner.pid)
        )
        other_owner_identity = eventually(
            lambda: module.process_start_identity(other_owner.pid)
        )
        main_agent_key = module.derive_agent_key(
            main_owner.pid,
            main_owner_identity,
        )
        other_agent_key = module.derive_agent_key(
            other_owner.pid,
            other_owner_identity,
        )
        main_status_path = status_path(
            runtime_root,
            HOST_ONE,
            main_agent_key,
            module,
        )
        agent_status_path = status_path(
            runtime_root,
            HOST_ONE,
            other_agent_key,
            module,
        )
        host_status_path = status_path(
            runtime_root,
            HOST_TWO,
            main_agent_key,
            module,
        )
        main_status = eventually(lambda: read_running_status(main_status_path))
        agent_status = eventually(lambda: read_running_status(agent_status_path))
        host_status = eventually(lambda: read_running_status(host_status_path))

        # Both MCP servers (and therefore internal subagents) in one Codex OS
        # process share one pool, while a separate Codex/agent-deck process does not.
        if main_status["lease_count"] != 2:
            raise AssertionError(
                f"same-owner bridges did not converge: {main_status}"
            )
        if (
            main_status["owner_pid"] != main_owner.pid
            or main_status["owner_start_identity"] != main_owner_identity
            or main_status["agent_key"] != main_agent_key
        ):
            raise AssertionError(f"main owner identity was not retained: {main_status}")
        if (
            agent_status["owner_pid"] != other_owner.pid
            or agent_status["agent_key"] != other_agent_key
        ):
            raise AssertionError(
                f"separate Codex owner identity was not retained: {agent_status}"
            )
        pids = {
            main_status["daemon_pid"],
            agent_status["daemon_pid"],
            host_status["daemon_pid"],
        }
        supervisors = {
            main_status["supervisor_pid"],
            agent_status["supervisor_pid"],
            host_status["supervisor_pid"],
        }
        if len(pids) != 3 or len(supervisors) != 3:
            raise AssertionError("owner or host instances shared a process")
        runtime_dir = runtime_root / HOST_ONE / "agents" / main_agent_key
        state_dir = state_root / HOST_ONE / "agents" / main_agent_key
        sockets = {
            runtime_dir / "emacs" / "server",
            runtime_root
            / HOST_ONE
            / "agents"
            / other_agent_key
            / "emacs"
            / "server",
            runtime_root
            / HOST_TWO
            / "agents"
            / main_agent_key
            / "emacs"
            / "server",
        }
        if len(sockets) != 3 or not all(path.is_socket() for path in sockets):
            raise AssertionError(f"isolated sockets are missing: {sockets}")
        if str(Path.home()) in str(runtime_dir) or str(Path.home()) in str(state_dir):
            raise AssertionError("per-agent state leaked into shared HOME")

        agent_runtime_dir = (
            runtime_root / HOST_ONE / "agents" / other_agent_key
        )
        agent_state_dir = state_root / HOST_ONE / "agents" / other_agent_key
        other_bridge_identity = module.process_start_identity(other_agent.pid)
        agent_supervisor_identity = module.process_start_identity(
            agent_status["supervisor_pid"]
        )
        agent_daemon_identity = module.process_start_identity(
            agent_status["daemon_pid"]
        )
        other_owner.terminate_abruptly()
        owners.remove(other_owner)
        other_agent.closed = True
        bridges.remove(other_agent)
        eventually(lambda: not agent_status_path.exists())
        eventually(lambda: not agent_runtime_dir.exists())
        eventually(lambda: not agent_state_dir.exists())
        for pid, identity in (
            (other_agent.pid, other_bridge_identity),
            (agent_status["supervisor_pid"], agent_supervisor_identity),
            (agent_status["daemon_pid"], agent_daemon_identity),
        ):
            eventually(
                lambda pid=pid, identity=identity: (
                    module.process_start_identity(pid) != identity
                )
            )

        other_host.close()
        bridges.remove(other_host)
        eventually(
            lambda: (
                (current := json.loads(host_status_path.read_text()))
                and current["lease_count"] == 0
                and current["daemon_pid"] is None
            )
        )

        root_pid = main_status["daemon_pid"]
        supervisor_pid = main_status["supervisor_pid"]
        workers = worker_pids(main_typed)
        worker_identities = {
            pid: module.process_start_identity(pid) for pid in workers
        }
        if any(identity is None for identity in worker_identities.values()):
            raise AssertionError(f"worker identity disappeared: {worker_identities}")

        nonce = runtime_dir / "watchdog-dispatch-nonce"
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
                (current := read_running_status(main_status_path))
                and current["daemon_pid"] != root_pid
                and current
            )
        )
        if restarted["supervisor_pid"] != supervisor_pid:
            raise AssertionError("root restart replaced the owning supervisor")
        if nonce.read_text().splitlines() != ["once"]:
            raise AssertionError("the ambiguous hung request was replayed")
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
        surviving = eventually(
            lambda: (
                (current := read_running_status(main_status_path))
                and current["lease_count"] == 1
                and current
            )
        )
        if surviving["daemon_pid"] != restarted_pid:
            raise AssertionError("one bridge exit stopped the shared agent daemon")
        surviving_probe = main_eval.call_tool("anvil-worker-probe", {})
        if "error" in surviving_probe:
            raise AssertionError(
                f"surviving typed bridge lost the daemon: {surviving_probe}"
            )

        main_eval.close()
        bridges.remove(main_eval)
        idle = eventually(
            lambda: (
                (current := json.loads(main_status_path.read_text()))
                and current["lease_count"] == 0
                and current["daemon_pid"] is None
                and current
            )
        )
        if idle["supervisor_pid"] != supervisor_pid:
            raise AssertionError("idle state replaced the owner supervisor")
        eventually(
            lambda: module.process_start_identity(restarted_pid)
            != restarted_identity
        )
        for pid, identity in worker_identities.items():
            eventually(
                lambda pid=pid, identity=identity: (
                    module.process_start_identity(pid) != identity
                )
            )

        host_runtime_dir = runtime_root / HOST_TWO / "agents" / main_agent_key
        host_state_dir = state_root / HOST_TWO / "agents" / main_agent_key
        main_owner.close()
        owners.remove(main_owner)
        eventually(lambda: not runtime_dir.exists())
        eventually(lambda: not state_dir.exists())
        eventually(lambda: not host_runtime_dir.exists())
        eventually(lambda: not host_state_dir.exists())
    finally:
        for bridge in reversed(bridges):
            bridge.close()
        for owner in reversed(owners):
            owner.close()


if __name__ == "__main__":
    main()
