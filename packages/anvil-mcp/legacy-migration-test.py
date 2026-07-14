#!/usr/bin/env python3
"""Prove legacy host listeners coexist with isolated per-bridge daemons."""

from __future__ import annotations

import json
import os
from pathlib import Path
import selectors
import shutil
import stat
import subprocess
import sys
import tempfile
import time


HOST_A = "migration-a"
HOST_B = "migration-b"


def eventually(predicate, label: str, timeout: float = 30.0):
    """Return the first truthy predicate result before a bounded deadline."""
    deadline = time.monotonic() + timeout
    last_error: BaseException | None = None
    while time.monotonic() < deadline:
        try:
            result = predicate()
        except (FileNotFoundError, json.JSONDecodeError, OSError) as error:
            last_error = error
        else:
            if result:
                return result
        time.sleep(0.1)
    detail = f": {last_error}" if last_error is not None else ""
    raise AssertionError(f"{label} did not become true{detail}")


def socket_path(runtime_root: Path, host: str) -> Path:
    """Return the compatibility listener path for one physical host."""
    return runtime_root / host / "emacs" / "server"


def bridge_environment(
    base: dict[str, str],
    home: Path,
    runtime_root: Path,
    state_root: Path,
    host: str,
) -> dict[str, str]:
    """Build one hermetic host-qualified bridge or daemon environment."""
    environment = base.copy()
    for name in (
        "ALTERNATE_EDITOR",
        "ANVIL_EMACS_SOCKET",
        "XDG_CONFIG_HOME",
    ):
        environment.pop(name, None)
    environment.update(
        {
            "HOME": str(home),
            "ANVIL_EMACS_HOST": host,
            "ANVIL_EMACS_RUNTIME_ROOT": str(runtime_root),
            "ANVIL_EMACS_STATE_ROOT": str(state_root),
            "ANVIL_AGENT_GRACE_SECONDS": "0.5",
            "ANVIL_AGENT_READY_SECONDS": "120",
        }
    )
    return environment


class Bridge:
    """One persistent MCP stdio pipe."""

    def __init__(self, launcher: Path, environment: dict[str, str]) -> None:
        self.stderr_file = tempfile.TemporaryFile(mode="w+")
        self.process = subprocess.Popen(
            [str(launcher), "--server-id=anvil"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=self.stderr_file,
            env=environment,
            text=True,
            bufsize=1,
        )
        self.next_id = 1
        self.closed = False

    def diagnostics(self) -> str:
        """Return bounded stderr without disturbing subsequent writes."""
        self.stderr_file.flush()
        self.stderr_file.seek(0)
        output = self.stderr_file.read()
        self.stderr_file.seek(0, os.SEEK_END)
        return (
            f"pid={self.process.pid} rc={self.process.poll()} stderr={output[-4000:]}"
        )

    def request(
        self,
        method: str,
        params: object | None = None,
        timeout: float = 150.0,
    ) -> dict[str, object]:
        """Send one line-delimited JSON-RPC request and read its response."""
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
                f"bridge request {method} timed out: {self.diagnostics()}"
            )
        line = self.process.stdout.readline()
        if not line:
            raise AssertionError(f"bridge exited during {method}: {self.diagnostics()}")
        response = json.loads(line)
        if not isinstance(response, dict) or response.get("id") != identifier:
            raise AssertionError(f"invalid bridge response: {response!r}")
        return response

    def initialize(self) -> None:
        """Complete the MCP initialization handshake."""
        response = self.request(
            "initialize",
            {
                "protocolVersion": "2025-03-26",
                "capabilities": {},
                "clientInfo": {
                    "name": "anvil-legacy-migration-test",
                    "version": "1",
                },
            },
        )
        if "error" in response:
            raise AssertionError(f"initialize failed: {response}")

    def eval(self, expression: str):
        """Evaluate one expression and decode the tool's JSON-shaped text."""
        response = self.request(
            "tools/call",
            {
                "name": "emacs-eval",
                "arguments": {"expression": expression},
            },
        )
        if "error" in response:
            raise AssertionError(f"emacs-eval request failed: {response}")
        result = response.get("result")
        if not isinstance(result, dict) or result.get("isError") is True:
            raise AssertionError(f"emacs-eval tool failed: {response}")
        rows = result.get("content")
        if not isinstance(rows, list) or len(rows) != 1:
            raise AssertionError(f"unexpected emacs-eval content: {response}")
        text = rows[0].get("text")
        if not isinstance(text, str):
            raise AssertionError(f"missing emacs-eval text: {response}")
        return json.loads(text)

    def close(self, *, strict: bool = True) -> None:
        """Close the MCP pipe and boundedly reap its launcher."""
        if self.closed:
            return
        self.closed = True
        if self.process.poll() is None and self.process.stdin is not None:
            try:
                self.process.stdin.close()
            except BrokenPipeError:
                pass
        try:
            self.process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        returncode = self.process.returncode
        diagnostics = self.diagnostics()
        self.stderr_file.close()
        if strict and returncode != 0:
            raise AssertionError(f"bridge failed during close: {diagnostics}")


def probe_pid(emacsclient: Path, socket: Path) -> int | bool:
    """Return the daemon PID at SOCKET, or false while it is unavailable."""
    try:
        result = subprocess.run(
            [
                str(emacsclient),
                "-a",
                "false",
                "-s",
                str(socket),
                "-e",
                "(emacs-pid)",
            ],
            stdin=subprocess.DEVNULL,
            text=True,
            capture_output=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    if result.returncode != 0:
        return False
    try:
        return int(result.stdout.strip())
    except ValueError:
        return False


def process_is_alive(pid: int) -> bool:
    """Return whether PID still names a live process on Darwin or Linux."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def find_agent_instance(
    runtime_root: Path,
    state_root: Path,
    host: str,
    bridge_pid: int,
) -> dict[str, object] | bool:
    """Locate the status and paths owned by one per-agent launcher process."""
    agents = runtime_root / host / "agents"
    try:
        candidates = tuple(agents.iterdir())
    except FileNotFoundError:
        return False
    for runtime_dir in candidates:
        status_path = runtime_dir / ".anvil-agent-supervisor.json"
        try:
            status = json.loads(status_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            continue
        if status.get("owner_pid") != bridge_pid or not status.get("daemon_pid"):
            continue
        key = runtime_dir.name
        return {
            "runtime_dir": runtime_dir,
            "state_dir": state_root / host / "agents" / key,
            "socket": runtime_dir / "emacs" / "server",
            "status": status,
        }
    return False


def start_daemon(
    daemon: Path,
    environment: dict[str, str],
    log_path: Path,
) -> tuple[subprocess.Popen[str], object]:
    """Start one service-managed compatibility daemon."""
    log = log_path.open("w+")
    process = subprocess.Popen(
        [str(daemon)],
        stdin=subprocess.DEVNULL,
        stdout=log,
        stderr=subprocess.STDOUT,
        env=environment,
        text=True,
    )
    return process, log


def daemon_diagnostics(
    process: subprocess.Popen[str],
    log,
) -> str:
    """Return bounded daemon output for an assertion failure."""
    log.flush()
    log.seek(0)
    output = log.read()
    log.seek(0, os.SEEK_END)
    return f"pid={process.pid} rc={process.poll()} log={output[-4000:]}"


def stop_daemon(
    process: subprocess.Popen[str],
    log,
    emacsclient: Path,
    socket: Path,
    *,
    strict: bool,
) -> None:
    """Stop one compatibility daemon and require its socket to disappear."""
    if process.poll() is None and probe_pid(emacsclient, socket):
        result = subprocess.run(
            [
                str(emacsclient),
                "-a",
                "false",
                "-s",
                str(socket),
                "-e",
                "(progn (run-at-time 0.1 nil #'kill-emacs) t)",
            ],
            stdin=subprocess.DEVNULL,
            text=True,
            capture_output=True,
            timeout=5,
            check=False,
        )
        if strict and result.returncode != 0:
            raise AssertionError(
                f"failed to request compatibility daemon shutdown: {result.stderr}"
            )
    try:
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    diagnostics = daemon_diagnostics(process, log)
    if strict and process.returncode != 0:
        raise AssertionError(f"compatibility daemon failed: {diagnostics}")
    if strict:
        eventually(lambda: not socket.exists(), f"cleanup of {socket}", timeout=10)


def assert_private_directory(path: Path) -> None:
    """Require a real mode-0700 directory owned by the test user."""
    info = path.lstat()
    if (
        not stat.S_ISDIR(info.st_mode)
        or stat.S_ISLNK(info.st_mode)
        or stat.S_IMODE(info.st_mode) != 0o700
        or info.st_uid != os.getuid()
    ):
        raise AssertionError(f"unsafe migration directory: {path}")


def main() -> int:
    if len(sys.argv) != 6:
        raise SystemExit(
            f"usage: {Path(sys.argv[0]).name} "
            "LEGACY_DAEMON LEGACY_LAUNCHER CURRENT_DAEMON "
            "PER_AGENT_LAUNCHER EMACSCLIENT"
        )
    host_daemon = Path(sys.argv[1]).resolve()
    legacy_launcher = Path(sys.argv[2]).resolve()
    current_host_daemon = Path(sys.argv[3]).resolve()
    per_agent_launcher = Path(sys.argv[4]).resolve()
    emacsclient = Path(sys.argv[5]).resolve()

    runtime_root = Path(tempfile.mkdtemp(prefix="amr-", dir="/tmp"))
    state_root = Path(tempfile.mkdtemp(prefix="ams-", dir="/tmp"))
    home = Path(tempfile.mkdtemp(prefix="amh-", dir="/tmp"))
    for path in (runtime_root, state_root, home):
        assert_private_directory(path)

    base = os.environ.copy()
    environments = {
        host: bridge_environment(base, home, runtime_root, state_root, host)
        for host in (HOST_A, HOST_B)
    }
    legacy_sockets = {
        host: socket_path(runtime_root, host) for host in (HOST_A, HOST_B)
    }
    daemon_processes: dict[str, subprocess.Popen[str]] = {}
    daemon_logs: dict[str, object] = {}
    bridges: list[Bridge] = []
    agent_instance: dict[str, object] | None = None

    try:
        for host in (HOST_A, HOST_B):
            process, log = start_daemon(
                host_daemon,
                environments[host],
                home / f"{host}.log",
            )
            daemon_processes[host] = process
            daemon_logs[host] = log

        legacy_direct_pids = {}
        for host in (HOST_A, HOST_B):
            process = daemon_processes[host]
            log = daemon_logs[host]
            legacy_direct_pids[host] = eventually(
                lambda host=host, process=process, log=log: (
                    probe_pid(emacsclient, legacy_sockets[host])
                    if process.poll() is None
                    else (_ for _ in ()).throw(
                        AssertionError(daemon_diagnostics(process, log))
                    )
                ),
                f"legacy listener for {host}",
                timeout=150,
            )

        legacy_a = Bridge(legacy_launcher, environments[HOST_A])
        bridges.append(legacy_a)
        legacy_a.initialize()
        if legacy_a.eval("(emacs-pid)") != legacy_direct_pids[HOST_A]:
            raise AssertionError("legacy bridge A reached the wrong host daemon")

        legacy_b = Bridge(legacy_launcher, environments[HOST_B])
        bridges.append(legacy_b)
        legacy_b.initialize()
        if legacy_b.eval("(emacs-pid)") != legacy_direct_pids[HOST_B]:
            raise AssertionError("legacy bridge B reached the wrong host daemon")

        per_agent = Bridge(per_agent_launcher, environments[HOST_A])
        bridges.append(per_agent)
        per_agent.initialize()
        agent_instance = eventually(
            lambda: find_agent_instance(
                runtime_root,
                state_root,
                HOST_A,
                per_agent.process.pid,
            ),
            "per-agent lifecycle instance",
            timeout=150,
        )
        agent_status = agent_instance["status"]
        agent_socket = agent_instance["socket"]
        agent_pid = per_agent.eval("(emacs-pid)")
        if (
            not isinstance(agent_status, dict)
            or agent_status.get("daemon_pid") != agent_pid
            or not isinstance(agent_socket, Path)
            or not agent_socket.is_socket()
        ):
            raise AssertionError(f"invalid per-agent instance: {agent_instance}")
        if (
            len(
                {
                    legacy_direct_pids[HOST_A],
                    legacy_direct_pids[HOST_B],
                    agent_pid,
                }
            )
            != 3
        ):
            raise AssertionError("legacy and per-agent bridges shared a daemon")
        if agent_socket == legacy_sockets[HOST_A]:
            raise AssertionError("new bridge used the compatibility listener")
        if agent_socket.parent.parent.parent != runtime_root / HOST_A / "agents":
            raise AssertionError(f"per-agent socket escaped its host: {agent_socket}")
        if legacy_sockets[HOST_A] == legacy_sockets[HOST_B]:
            raise AssertionError("legacy compatibility sockets were not host-local")
        if not isinstance(agent_instance["state_dir"], Path):
            raise AssertionError("per-agent state path is malformed")
        assert_private_directory(agent_instance["state_dir"])

        if (
            legacy_a.eval("(+ 40 2)") != 42
            or legacy_b.eval("(+ 40 2)") != 42
            or per_agent.eval("(+ 40 2)") != 42
        ):
            raise AssertionError("concurrent migration bridges did not all respond")

        # Model a configuration activation that replaces the compatibility
        # service while an old launcher and its exact stdio pipe remain open.
        legacy_bridge_pid = legacy_a.process.pid
        departed_daemon_pid = legacy_direct_pids[HOST_A]
        departed_process = daemon_processes.pop(HOST_A)
        departed_log = daemon_logs.pop(HOST_A)
        stop_daemon(
            departed_process,
            departed_log,
            emacsclient,
            legacy_sockets[HOST_A],
            strict=True,
        )
        departed_log.close()
        if process_is_alive(departed_daemon_pid):
            raise AssertionError("preceding compatibility daemon survived replacement")

        # Host B and the private per-agent daemon must not depend on host A's
        # compatibility listener, even during its service-restart gap.
        if (
            legacy_b.eval("(emacs-pid)") != legacy_direct_pids[HOST_B]
            or per_agent.eval("(emacs-pid)") != agent_pid
        ):
            raise AssertionError("host A service stop disturbed an isolated bridge")

        replacement_process, replacement_log = start_daemon(
            current_host_daemon,
            environments[HOST_A],
            home / f"{HOST_A}-replacement.log",
        )
        daemon_processes[HOST_A] = replacement_process
        daemon_logs[HOST_A] = replacement_log
        replacement_pid = eventually(
            lambda: (
                probe_pid(emacsclient, legacy_sockets[HOST_A])
                if replacement_process.poll() is None
                else (_ for _ in ()).throw(
                    AssertionError(
                        daemon_diagnostics(replacement_process, replacement_log)
                    )
                )
            ),
            "replacement compatibility listener",
            timeout=150,
        )
        if replacement_pid == departed_daemon_pid:
            raise AssertionError("replacement compatibility daemon reused the old PID")
        legacy_direct_pids[HOST_A] = replacement_pid

        if (
            legacy_a.process.pid != legacy_bridge_pid
            or legacy_a.process.poll() is not None
        ):
            raise AssertionError(
                "legacy stdio bridge did not survive service replacement"
            )
        restart_result = legacy_a.eval(
            "(progn "
            "(setq anvil-migration-replay-count "
            "(1+ (if (boundp 'anvil-migration-replay-count) "
            "anvil-migration-replay-count 0))) "
            "anvil-migration-replay-count)"
        )
        if restart_result != 1:
            raise AssertionError(
                f"legacy request was lost or replayed after restart: {restart_result!r}"
            )
        if legacy_a.eval("(emacs-pid)") != replacement_pid:
            raise AssertionError("legacy bridge reached the wrong replacement daemon")
        if legacy_a.eval("anvil-migration-replay-count") != 1:
            raise AssertionError("legacy request replay counter changed unexpectedly")
        if (
            legacy_b.eval("(emacs-pid)") != legacy_direct_pids[HOST_B]
            or per_agent.eval("(emacs-pid)") != agent_pid
        ):
            raise AssertionError(
                "host A service replacement disturbed an isolated bridge"
            )

        per_agent.close()
        bridges.remove(per_agent)
        eventually(
            lambda: not process_is_alive(agent_pid),
            "per-agent daemon process cleanup",
        )
        eventually(
            lambda: not agent_instance["runtime_dir"].exists(),
            "per-agent runtime cleanup",
        )
        eventually(
            lambda: not agent_instance["state_dir"].exists(),
            "per-agent state cleanup",
        )
        if (
            legacy_a.eval("(emacs-pid)") != legacy_direct_pids[HOST_A]
            or legacy_b.eval("(emacs-pid)") != legacy_direct_pids[HOST_B]
        ):
            raise AssertionError("per-agent cleanup disturbed a legacy listener")

        legacy_a.close()
        bridges.remove(legacy_a)
        if probe_pid(emacsclient, legacy_sockets[HOST_A]) != legacy_direct_pids[HOST_A]:
            raise AssertionError("legacy listener depended on one MCP bridge pipe")

        stop_daemon(
            daemon_processes[HOST_A],
            daemon_logs[HOST_A],
            emacsclient,
            legacy_sockets[HOST_A],
            strict=True,
        )
        if legacy_b.eval("(emacs-pid)") != legacy_direct_pids[HOST_B]:
            raise AssertionError("host A cleanup disturbed host B")
        if probe_pid(emacsclient, legacy_sockets[HOST_A]):
            raise AssertionError("host A compatibility listener survived cleanup")

        legacy_b.close()
        bridges.remove(legacy_b)
        stop_daemon(
            daemon_processes[HOST_B],
            daemon_logs[HOST_B],
            emacsclient,
            legacy_sockets[HOST_B],
            strict=True,
        )
        print("legacy-migration-ok")
        return 0
    finally:
        for bridge in reversed(bridges):
            bridge.close(strict=False)
        for host in (HOST_A, HOST_B):
            process = daemon_processes.get(host)
            log = daemon_logs.get(host)
            if process is not None and log is not None:
                stop_daemon(
                    process,
                    log,
                    emacsclient,
                    legacy_sockets[host],
                    strict=False,
                )
                log.close()
        shutil.rmtree(runtime_root, ignore_errors=True)
        shutil.rmtree(state_root, ignore_errors=True)
        shutil.rmtree(home, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
