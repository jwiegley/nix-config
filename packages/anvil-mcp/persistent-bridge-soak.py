#!/usr/bin/env python3
"""Long-lived per-bridge reliability soak for dedicated Anvil daemons."""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import re
import selectors
from statistics import median
import subprocess
import sys
import time


HOST = "persistent-soak"
DIRENV_MARKER = "persistent-bridge-direnv"
COMMAND_NAME = "anvil-soak-command"
EXPECTED_TOOL_COUNT = 89
WARMUP_BATCH_TIMEOUT_SECONDS = 210


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_checked(argv: list[str], cwd: Path) -> None:
    completed = subprocess.run(
        argv,
        cwd=cwd,
        text=True,
        capture_output=True,
        check=False,
        env=os.environ.copy(),
    )
    if completed.returncode != 0:
        raise AssertionError(
            f"command failed ({completed.returncode}): {argv!r}\n"
            f"stdout={completed.stdout}\nstderr={completed.stderr}"
        )


def setup_fixtures(git: Path, direnv: Path) -> dict[str, Path]:
    home = Path.home()
    plain = home / "plain.txt"
    org = home / "org" / "soak.org"
    project = home / "direnv-project"
    project_file = project / "visited.txt"
    command = project / "bin" / COMMAND_NAME
    repo = home / "git-repo"

    org.parent.mkdir(parents=True)
    project.joinpath("bin").mkdir(parents=True)
    repo.mkdir(parents=True)
    plain.write_text("persistentfileneedle\n")
    org.write_text("* Persistent bridge\npersistentorgneedle\n")
    project_file.write_text("direnv visit\n")
    project.joinpath(".envrc").write_text(
        f'export ANVIL_SOAK_DIRENV={DIRENV_MARKER}\nPATH_add "$PWD/bin"\n'
    )
    command.write_text("#!/bin/sh\nprintf persistent-command\n")
    command.chmod(0o700)
    run_checked([str(direnv), "allow"], project)

    run_checked([str(git), "init", "--initial-branch=main"], repo)
    repo.joinpath("tracked.txt").write_text("tracked\n")
    run_checked([str(git), "add", "tracked.txt"], repo)
    run_checked(
        [
            str(git),
            "-c",
            "user.name=Anvil Soak",
            "-c",
            "user.email=anvil-soak@example.invalid",
            "-c",
            "commit.gpgsign=false",
            "commit",
            "-m",
            "initial",
        ],
        repo,
    )

    alternate_editor = home / "alternate-editor"
    alternate_marker = home / "alternate-editor-used"
    alternate_editor.write_text(
        '#!/bin/sh\ntouch "$ANVIL_ALTERNATE_EDITOR_MARKER"\nexit 97\n'
    )
    alternate_editor.chmod(0o700)
    os.environ["ALTERNATE_EDITOR"] = str(alternate_editor)
    os.environ["ANVIL_ALTERNATE_EDITOR_MARKER"] = str(alternate_marker)

    return {
        "plain": plain,
        "org": org,
        "project": project,
        "project_file": project_file,
        "command": command,
        "repo": repo,
        "alternate_marker": alternate_marker,
    }


def direnv_expression(project_file: Path) -> str:
    return f"""
(let* ((buffer (find-file-noselect {json.dumps(str(project_file))}))
       local)
  (unwind-protect
      (setq local
            (with-current-buffer buffer
              (vector (getenv "ANVIL_SOAK_DIRENV")
                      (executable-find "{COMMAND_NAME}"))))
    (when (buffer-live-p buffer)
      (kill-buffer buffer)))
  (json-serialize
   (vector (aref local 0)
           (aref local 1)
           (or (getenv "ANVIL_SOAK_DIRENV") "<unset>")
           (or (executable-find "{COMMAND_NAME}") "<missing>"))))
""".strip()


def async_loop_expression(project_file: Path, marker: Path) -> str:
    return f"""
(let* ((buffer (find-file-noselect {json.dumps(str(project_file))}))
       local)
  (unwind-protect
      (setq local
            (with-current-buffer buffer
              (vector (getenv "ANVIL_SOAK_DIRENV")
                      (executable-find "{COMMAND_NAME}"))))
    (when (buffer-live-p buffer)
      (kill-buffer buffer)))
  (with-temp-file {json.dumps(str(marker))}
    (insert
     (json-serialize
      (vector (emacs-pid) (aref local 0) (aref local 1)))))
  (while t))
""".strip()


def parse_direnv_response(response: dict[str, object], smoke, command: Path) -> None:
    encoded = smoke.eval_value(response)
    if not isinstance(encoded, str):
        raise AssertionError(f"direnv response was not encoded JSON: {encoded!r}")
    values = json.loads(encoded)
    expected = [DIRENV_MARKER, str(command.resolve()), "<unset>", "<missing>"]
    if values != expected:
        raise AssertionError(
            f"buffer-local direnv mismatch: {values!r} != {expected!r}"
        )


def collect_responses(
    bridge,
    identifiers: dict[str, int],
    timeout: float,
) -> dict[str, dict[str, object]]:
    by_identifier = {identifier: name for name, identifier in identifiers.items()}
    responses: dict[str, dict[str, object]] = {}
    deadline = time.monotonic() + timeout
    while len(responses) < len(identifiers):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise AssertionError(
                f"pipelined responses exceeded {timeout}s: "
                f"received={sorted(responses)} expected={sorted(identifiers)}"
            )
        response = bridge.receive_response(remaining)
        identifier = response.get("id")
        if identifier not in by_identifier:
            raise AssertionError(f"unexpected pipelined response id: {response!r}")
        name = by_identifier[identifier]
        if name in responses:
            raise AssertionError(
                f"duplicate pipelined response for {name}: {response!r}"
            )
        responses[name] = response
    return responses


def response_buffered(bridge) -> bool:
    if bridge.process.stdout is None:
        raise AssertionError("bridge stdout is unavailable")
    selector = selectors.DefaultSelector()
    selector.register(bridge.process.stdout, selectors.EVENT_READ)
    try:
        return bool(selector.select(0))
    finally:
        selector.close()


def validate_git_response(response: dict[str, object], smoke) -> None:
    status = json.loads(smoke.response_text(response))
    if status.get("branch") != "main":
        raise AssertionError(f"git-status lost the fixture branch: {status!r}")
    if status.get("unmerged"):
        raise AssertionError(f"git-status reported an unmerged fixture: {status!r}")


def validate_fixture_responses(
    responses: dict[str, dict[str, object]],
    smoke,
    fixtures: dict[str, Path],
) -> None:
    if "persistentfileneedle" not in smoke.response_text(responses["file"]):
        raise AssertionError("file-read lost its fixture content")
    if "persistentorgneedle" not in smoke.response_text(responses["org"]):
        raise AssertionError("org-read-file lost its fixture content")
    validate_git_response(responses["git"], smoke)
    parse_direnv_response(responses["elisp"], smoke, fixtures["command"])


def send_fixture_requests(bridge, fixtures: dict[str, Path]) -> dict[str, int]:
    calls = {
        "file": (
            "file-read",
            {"path": str(fixtures["plain"])},
        ),
        "org": (
            "org-read-file",
            {"file": str(fixtures["org"])},
        ),
        "git": (
            "git-status",
            {"path": str(fixtures["repo"])},
        ),
        "elisp": (
            "emacs-eval",
            {"expression": direnv_expression(fixtures["project_file"])},
        ),
    }
    return {
        name: bridge.send_request(
            "tools/call",
            {"name": tool, "arguments": arguments},
        )
        for name, (tool, arguments) in calls.items()
    }


def warm_bridge(bridge, smoke, fixtures: dict[str, Path]) -> None:
    listed = bridge.request("tools/list", timeout=60)
    tools = listed.get("result", {}).get("tools")
    if not isinstance(tools, list) or len(tools) != EXPECTED_TOOL_COUNT:
        raise AssertionError(f"unexpected tool registry: {listed!r}")
    async_tool = next(
        (
            tool
            for tool in tools
            if isinstance(tool, dict) and tool.get("name") == "emacs-eval-async"
        ),
        None,
    )
    input_schema = (
        async_tool.get("inputSchema") if isinstance(async_tool, dict) else None
    )
    properties = (
        input_schema.get("properties") if isinstance(input_schema, dict) else None
    )
    timeout_schema = properties.get("timeout") if isinstance(properties, dict) else None
    if not isinstance(timeout_schema, dict) or timeout_schema.get("type") != "number":
        raise AssertionError(f"async timeout schema is not numeric: {async_tool!r}")

    root_before_timeout = smoke.eval_value(
        bridge.call_tool("emacs-eval", {"expression": "(emacs-pid)"}, timeout=10)
    )
    timeout_response = bridge.call_tool(
        "shell-run",
        {"cmd": "sleep 2", "timeout_sec": "1"},
        timeout=10,
    )
    if "shell timeout after 1s" not in json.dumps(timeout_response):
        raise AssertionError(
            f"shell operation did not time out explicitly: {timeout_response!r}"
        )
    root_after_timeout = smoke.eval_value(
        bridge.call_tool("emacs-eval", {"expression": "(emacs-pid)"}, timeout=10)
    )
    if root_after_timeout != root_before_timeout:
        raise AssertionError(
            "an operation timeout restarted or disabled the healthy bridge: "
            f"{root_before_timeout!r} -> {root_after_timeout!r}"
        )

    identifiers = send_fixture_requests(bridge, fixtures)
    # This pipelines five ordinary calls, so its aggregate bound follows the
    # MCP client's tool envelope rather than acting as a host-load benchmark.
    responses = collect_responses(
        bridge,
        identifiers,
        timeout=WARMUP_BATCH_TIMEOUT_SECONDS,
    )
    validate_fixture_responses(responses, smoke, fixtures)


def submit_async(bridge, smoke, expression: str, timeout: int | str) -> str:
    response = bridge.call_tool(
        "emacs-eval-async",
        {"expression": expression, "timeout": timeout},
        timeout=30,
    )
    text = smoke.response_text(response)
    match = re.search(r"\bjob-[0-9]+-[0-9]+\b", text)
    if match is None:
        raise AssertionError(f"async submission returned no job ID: {text}")
    return match.group(0)


def poll_async(bridge, smoke, job_id: str, timeout: float) -> str:
    deadline = time.monotonic() + timeout
    last = ""
    while time.monotonic() < deadline:
        last = smoke.response_text(
            bridge.call_tool(
                "emacs-eval-result",
                {"job-id": job_id},
                timeout=10,
            )
        )
        if "status: done" in last or "status: error" in last:
            return last
        time.sleep(0.1)
    raise AssertionError(f"async job {job_id} did not settle: {last}")


def record_identity(records: set[tuple[int, str]], module, pid: int) -> str:
    identity = module.process_start_identity(pid)
    if identity is None:
        raise AssertionError(f"process {pid} disappeared before it was recorded")
    records.add((pid, identity))
    return identity


def process_parent_map(ps: Path) -> dict[int, int]:
    """Snapshot PID to PPID without depending on a shell or procps on Linux."""
    parents: dict[int, int] = {}
    if sys.platform == "linux":
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit():
                continue
            try:
                raw = entry.joinpath("stat").read_text()
                fields = raw[raw.rfind(")") + 2 :].split()
                parents[int(entry.name)] = int(fields[1])
            except (FileNotFoundError, IndexError, PermissionError, ValueError):
                continue
        return parents
    if sys.platform == "darwin":
        completed = subprocess.run(
            [str(ps), "-axo", "pid=,ppid="],
            text=True,
            capture_output=True,
            check=True,
        )
        for line in completed.stdout.splitlines():
            fields = line.split()
            if len(fields) == 2:
                parents[int(fields[0])] = int(fields[1])
        return parents
    raise AssertionError(f"unsupported process platform: {sys.platform}")


def descendant_pids(root_pid: int, parents: dict[int, int]) -> set[int]:
    descendants: set[int] = set()
    frontier = {root_pid}
    while frontier:
        children = {
            pid
            for pid, parent in parents.items()
            if parent in frontier and pid not in descendants
        }
        descendants.update(children)
        frontier = children
    return descendants


def record_descendant_tree(
    module,
    bridge_pid: int,
    ps: Path,
) -> set[tuple[int, str | None]]:
    """Record every live or zombie descendant, including stdio and guards."""
    parents = process_parent_map(ps)
    records: set[tuple[int, str | None]] = set()
    for pid in descendant_pids(bridge_pid, parents):
        identity = module.process_start_identity(pid)
        if identity is not None or pid in parents:
            records.add((pid, identity))
    if not records:
        raise AssertionError(f"bridge {bridge_pid} exposed no descendants")
    return records


def descendant_record_gone(module, pid: int, identity: str | None, ps: Path) -> bool:
    if identity is None:
        return pid not in process_parent_map(ps)
    return module.process_start_identity(pid) != identity


def assert_pulse_changes(path: Path, before: str, timeout: float = 3.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            current = path.read_text()
        except FileNotFoundError:
            current = ""
        if current and current != before:
            return
        time.sleep(0.05)
    raise AssertionError(f"root watchdog pulse stopped changing: {path}")


def assert_async_isolation(
    bridge,
    instance: dict[str, object],
    smoke,
    module,
    fixtures: dict[str, Path],
    records: set[tuple[int, str]],
    suffix: str,
) -> None:
    compatibility_job = submit_async(
        bridge,
        smoke,
        "(+ 20 22)",
        timeout="5",
    )
    compatibility_result = poll_async(bridge, smoke, compatibility_job, timeout=10)
    if (
        "status: done" not in compatibility_result
        or "result: 42" not in compatibility_result
    ):
        raise AssertionError(
            f"cached string timeout caller failed: {compatibility_result}"
        )

    finite_job = submit_async(
        bridge,
        smoke,
        direnv_expression(fixtures["project_file"]),
        timeout=15,
    )
    finite_result = poll_async(bridge, smoke, finite_job, timeout=25)
    if (
        "status: done" not in finite_result
        or DIRENV_MARKER not in finite_result
        or COMMAND_NAME not in finite_result
    ):
        raise AssertionError(
            f"finite async job lost the project environment: {finite_result}"
        )

    runtime_dir = instance["runtime_dir"]
    if not isinstance(runtime_dir, Path):
        raise AssertionError(f"invalid runtime directory: {runtime_dir!r}")
    marker = runtime_dir / f"async-child-{suffix}.json"
    pulse = runtime_dir / ".anvil-root-pulse"
    marker.unlink(missing_ok=True)
    pulse_before = pulse.read_text()
    root_pid = instance["status"]["daemon_pid"]
    root_identity = record_identity(records, module, root_pid)

    job_id = submit_async(
        bridge,
        smoke,
        async_loop_expression(fixtures["project_file"], marker),
        timeout=15,
    )
    smoke.eventually(marker.exists, timeout=15)
    child_info = json.loads(marker.read_text())
    if (
        not isinstance(child_info, list)
        or len(child_info) != 3
        or not isinstance(child_info[0], int)
    ):
        raise AssertionError(f"invalid async child marker: {child_info!r}")
    child_pid, local_marker, executable = child_info
    child_identity = record_identity(records, module, child_pid)
    if child_pid == root_pid:
        raise AssertionError("async expression ran inside the root daemon")
    if local_marker != DIRENV_MARKER or executable != str(
        fixtures["command"].resolve()
    ):
        raise AssertionError(f"async child lost direnv: {child_info!r}")

    current_root = smoke.eval_value(
        bridge.call_tool("emacs-eval", {"expression": "(emacs-pid)"}, timeout=10)
    )
    if current_root != root_pid:
        raise AssertionError(
            f"root changed while async child ran: {current_root!r} != {root_pid}"
        )
    assert_pulse_changes(pulse, pulse_before)

    terminal = poll_async(bridge, smoke, job_id, timeout=25)
    if "status: error" not in terminal or "timeout" not in terminal.lower():
        raise AssertionError(f"looping async job did not time out: {terminal}")
    smoke.eventually(
        lambda: module.process_start_identity(child_pid) != child_identity,
        timeout=10,
    )
    status = smoke.read_running_status(instance["status_path"])
    if (
        not status
        or status["daemon_pid"] != root_pid
        or module.process_start_identity(root_pid) != root_identity
    ):
        raise AssertionError(f"async timeout damaged the root daemon: {status!r}")


def assert_synthetic_dispatch_error(response: dict[str, object]) -> None:
    error = response.get("error")
    data = error.get("data") if isinstance(error, dict) else None
    if not (
        isinstance(data, dict)
        and data.get("phase") == "dispatch"
        and data.get("dispatched") is True
        and data.get("replayed") is False
    ):
        raise AssertionError(f"hung request lacked at-most-once metadata: {response!r}")


def assert_nonce_records(records: list[tuple[Path, str]]) -> None:
    for nonce, token in records:
        if nonce.read_text().splitlines() != [token]:
            raise AssertionError(
                f"delayed replay changed {nonce}: {nonce.read_text()!r}"
            )


def assert_no_latency_growth(samples: list[dict[str, float]]) -> None:
    if len(samples) < 10:
        return
    for name in ("sibling", "dispatch", "restart", "readiness"):
        first = median(sample[name] for sample in samples[:5])
        last = median(sample[name] for sample in samples[-5:])
        limit = max(first * 3, first + 5)
        if last > limit:
            raise AssertionError(
                f"{name} latency degraded: first median={first:.3f}s "
                f"last median={last:.3f}s limit={limit:.3f}s"
            )
        print(
            f"latency {name}: first={first:.3f}s last={last:.3f}s "
            f"max={max(sample[name] for sample in samples):.3f}s"
        )


def run_recovery_cycle(
    cycle: int,
    bridges: list,
    instances: list[dict[str, object]],
    smoke,
    module,
    fixtures: dict[str, Path],
    records: set[tuple[int, str]],
    nonce_records: list[tuple[Path, str]],
    healthy_timeout: float,
) -> dict[str, float]:
    hanging_index = cycle % 2
    healthy_index = 1 - hanging_index
    hanging = bridges[hanging_index]
    healthy = bridges[healthy_index]
    hanging_instance = instances[hanging_index]
    healthy_instance = instances[healthy_index]

    old_status = smoke.read_running_status(hanging_instance["status_path"])
    healthy_status = smoke.read_running_status(healthy_instance["status_path"])
    if not old_status or not healthy_status:
        raise AssertionError("bridge status disappeared before a recovery cycle")
    old_root = old_status["daemon_pid"]
    old_root_identity = record_identity(records, module, old_root)
    old_supervisor = old_status["supervisor_pid"]
    healthy_root = healthy_status["daemon_pid"]
    healthy_identity = module.process_start_identity(healthy_root)

    nonce = hanging_instance["runtime_dir"] / f"hang-cycle-{cycle:02d}.txt"
    token = f"cycle-{cycle:02d}"
    expression = (
        f"(progn (write-region {json.dumps(token + chr(10))} nil "
        f"{json.dumps(str(nonce))} t 'silent) (while t))"
    )
    hang_started = time.monotonic()
    hang_identifier = hanging.send_request(
        "tools/call",
        {"name": "emacs-eval", "arguments": {"expression": expression}},
    )
    smoke.eventually(nonce.exists, timeout=10)
    if response_buffered(hanging):
        raise AssertionError("hung request completed before sibling work began")

    sibling_started = time.monotonic()
    identifiers = send_fixture_requests(healthy, fixtures)
    responses = collect_responses(healthy, identifiers, timeout=healthy_timeout)
    validate_fixture_responses(responses, smoke, fixtures)
    sibling_elapsed = time.monotonic() - sibling_started

    during_hang = smoke.read_running_status(hanging_instance["status_path"])
    if (
        not during_hang
        or during_hang["daemon_pid"] != old_root
        or module.process_start_identity(old_root) != old_root_identity
        or response_buffered(hanging)
    ):
        raise AssertionError(
            "sibling work did not finish while the original root was still hung: "
            f"{during_hang!r}"
        )

    hung_response = hanging.receive_response(timeout=40)
    dispatch_elapsed = time.monotonic() - hang_started
    if hung_response.get("id") != hang_identifier:
        raise AssertionError(f"hung response id mismatch: {hung_response!r}")
    assert_synthetic_dispatch_error(hung_response)
    nonce_records.append((nonce, token))
    assert_nonce_records([(nonce, token)])

    restart_started = time.monotonic()
    restarted = smoke.eventually(
        lambda: (
            (current := smoke.read_running_status(hanging_instance["status_path"]))
            and current["daemon_pid"] != old_root
            and current
        ),
        timeout=150,
    )
    restart_elapsed = time.monotonic() - restart_started
    if (
        restarted["supervisor_pid"] != old_supervisor
        or restarted["agent_key"] != old_status["agent_key"]
        or restarted["generation"] != old_status["generation"]
        or restarted["lease_count"] != 1
    ):
        raise AssertionError(f"recovery changed bridge ownership: {restarted!r}")
    smoke.eventually(
        lambda: module.process_start_identity(old_root) != old_root_identity,
        timeout=15,
    )

    healthy_after = smoke.read_running_status(healthy_instance["status_path"])
    if (
        not healthy_after
        or healthy_after["daemon_pid"] != healthy_root
        or module.process_start_identity(healthy_root) != healthy_identity
    ):
        raise AssertionError(
            f"hung bridge disturbed its healthy sibling: {healthy_after!r}"
        )

    readiness_started = time.monotonic()
    recovered = smoke.call_after_readiness(
        hanging,
        "emacs-eval",
        {"expression": "(+ 40 2)"},
        timeout=150,
    )
    readiness_elapsed = time.monotonic() - readiness_started
    if smoke.eval_value(recovered) != 42:
        raise AssertionError(f"same bridge did not recover: {recovered!r}")
    assert_nonce_records([(nonce, token)])
    hanging_instance["status"] = restarted
    record_identity(records, module, restarted["daemon_pid"])
    return {
        "sibling": sibling_elapsed,
        "dispatch": dispatch_elapsed,
        "restart": restart_elapsed,
        "readiness": readiness_elapsed,
    }


def assert_empty_agents(root: Path) -> bool:
    agents = root / HOST / "agents"
    try:
        return not any(agents.iterdir())
    except FileNotFoundError:
        return True


def main() -> None:
    if len(sys.argv) != 7:
        raise SystemExit(
            "usage: persistent-bridge-soak.py /path/to/anvil-mcp "
            "/path/to/agent-supervisor.py /path/to/agent-supervisor-smoke.py "
            "/path/to/git /path/to/direnv /path/to/ps"
        )

    launcher = Path(sys.argv[1]).resolve()
    supervisor_path = Path(sys.argv[2]).resolve()
    smoke = load_module(Path(sys.argv[3]).resolve(), "anvil_agent_smoke")
    git = Path(sys.argv[4]).resolve()
    direnv = Path(sys.argv[5]).resolve()
    ps = Path(sys.argv[6]).resolve()
    module = smoke.load_supervisor(supervisor_path)
    runtime_root = Path(os.environ["ANVIL_EMACS_RUNTIME_ROOT"])
    state_root = Path(os.environ["ANVIL_EMACS_STATE_ROOT"])
    cycles = int(os.environ.get("ANVIL_PERSISTENT_SOAK_CYCLES", "25"))
    healthy_timeout = float(
        os.environ.get(
            "ANVIL_PERSISTENT_SOAK_HEALTHY_SECONDS",
            str(WARMUP_BATCH_TIMEOUT_SECONDS),
        )
    )
    if cycles < 1 or cycles > 100:
        raise AssertionError(f"invalid soak cycle count: {cycles}")
    if healthy_timeout <= 0 or healthy_timeout > WARMUP_BATCH_TIMEOUT_SECONDS:
        raise AssertionError(f"invalid healthy sibling deadline: {healthy_timeout}")

    os.environ.setdefault("ANVIL_SMOKE_WATCHDOG_NORMAL_SECONDS", "20")
    os.environ.setdefault("ANVIL_SMOKE_WATCHDOG_ASYNC_SECONDS", "20")
    os.environ["GIT_OPTIONAL_LOCKS"] = "0"
    os.environ["GIT_CONFIG_NOSYSTEM"] = "1"
    os.environ["GIT_CONFIG_GLOBAL"] = "/dev/null"

    fixtures = setup_fixtures(git, direnv)
    home_baseline = smoke.snapshot_home(Path.home())
    bridges = [
        smoke.BridgeProcess(launcher, "anvil", HOST),
        smoke.BridgeProcess(launcher, "anvil", HOST),
    ]
    instances: list[dict[str, object]] = []
    records: set[tuple[int, str]] = set()
    descendant_records: set[tuple[int, str | None]] = set()
    nonce_records: list[tuple[Path, str]] = []
    latency_samples: list[dict[str, float]] = []
    succeeded = False
    try:
        for bridge in bridges:
            record_identity(records, module, bridge.pid)
            bridge.initialize()
            found = smoke.eventually(
                lambda bridge=bridge: smoke.find_running_instance(
                    runtime_root,
                    HOST,
                    bridge.pid,
                    module,
                ),
                timeout=150,
            )
            instance = smoke.validate_bridge_instance(
                found,
                bridge,
                HOST,
                state_root,
                module,
            )
            instances.append(instance)
            record_identity(records, module, instance["status"]["supervisor_pid"])
            record_identity(records, module, instance["status"]["daemon_pid"])

        for field in ("agent_key", "daemon_pid", "supervisor_pid"):
            values = {instance["status"][field] for instance in instances}
            if len(values) != len(instances):
                raise AssertionError(f"persistent bridges shared {field}: {values}")
        for field in ("runtime_dir", "state_dir", "socket"):
            values = {instance[field] for instance in instances}
            if len(values) != len(instances):
                raise AssertionError(f"persistent bridges shared {field}: {values}")
        generations = {instance["status"]["generation"] for instance in instances}
        if len(generations) != 1:
            raise AssertionError(f"bridges exposed mixed generations: {generations}")

        for bridge in bridges:
            warm_bridge(bridge, smoke, fixtures)
        for index, (bridge, instance) in enumerate(zip(bridges, instances)):
            assert_async_isolation(
                bridge,
                instance,
                smoke,
                module,
                fixtures,
                records,
                str(index),
            )

        for cycle in range(cycles):
            sample = run_recovery_cycle(
                cycle,
                bridges,
                instances,
                smoke,
                module,
                fixtures,
                records,
                nonce_records,
                healthy_timeout,
            )
            latency_samples.append(sample)
            print(
                f"persistent recovery cycle {cycle + 1}/{cycles} passed "
                f"(sibling={sample['sibling']:.3f}s "
                f"dispatch={sample['dispatch']:.3f}s "
                f"restart={sample['restart']:.3f}s "
                f"readiness={sample['readiness']:.3f}s)"
            )

        assert_nonce_records(nonce_records)
        assert_no_latency_growth(latency_samples)
        for bridge in bridges:
            for pid in smoke.worker_pids(bridge):
                record_identity(records, module, pid)
            descendant_records.update(record_descendant_tree(module, bridge.pid, ps))
        assert_nonce_records(nonce_records)
        succeeded = True
    finally:
        for bridge in reversed(bridges):
            bridge.close()

    if not succeeded:
        raise AssertionError("persistent bridge soak did not complete")
    for instance in instances:
        smoke.eventually(lambda instance=instance: not instance["runtime_dir"].exists())
        smoke.eventually(lambda instance=instance: not instance["state_dir"].exists())
    for pid, identity in records:
        smoke.eventually(
            lambda pid=pid, identity=identity: (
                module.process_start_identity(pid) != identity
            ),
            timeout=20,
        )
    for pid, identity in descendant_records:
        smoke.eventually(
            lambda pid=pid, identity=identity: descendant_record_gone(
                module, pid, identity, ps
            ),
            timeout=20,
        )
    smoke.eventually(lambda: assert_empty_agents(runtime_root), timeout=20)
    smoke.eventually(lambda: assert_empty_agents(state_root), timeout=20)
    smoke.assert_home_unchanged(Path.home(), home_baseline)
    if fixtures["alternate_marker"].exists():
        raise AssertionError("persistent bridge soak invoked ALTERNATE_EDITOR")
    print(
        f"PASS: {cycles} persistent per-bridge recovery cycles with "
        "async isolation, direnv, pipelined file/Org/Git/Elisp, and cleanup"
    )


if __name__ == "__main__":
    main()
