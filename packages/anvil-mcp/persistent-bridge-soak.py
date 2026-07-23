#!/usr/bin/env python3
"""Long-lived per-bridge reliability soak for dedicated Anvil daemons."""

from __future__ import annotations

import contextlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import signal
from statistics import median
import subprocess
import sys
import time


HOST = "persistent-soak"
DIRENV_MARKER = "persistent-bridge-direnv"
COMMAND_NAME = "anvil-soak-command"
EXPECTED_TOOL_COUNT = 89
BRIDGE_COUNT = 2
FIXTURE_COMMAND_COUNT = 4
DEFAULT_CLIENT_STARTUP_SECONDS = 540.0
DEFAULT_CLIENT_TOOL_SECONDS = 540.0
DEFAULT_WATCHDOG_NORMAL_SECONDS = 45.0
DEFAULT_WATCHDOG_DISPATCH_SECONDS = 225.0
WATCHDOG_RESPONSE_GRACE_SECONDS = 30.0
YIELDING_DISPATCH_SECONDS = 50
LOCAL_COMMAND_TIMEOUT_SECONDS = 30
INSTANCE_DISCOVERY_TIMEOUT_SECONDS = 150.0
TOOLS_LIST_TIMEOUT_SECONDS = 60.0
TOOL_CALL_TIMEOUT_SECONDS = 10.0
ASYNC_SUBMISSION_TIMEOUT_SECONDS = 30.0
ASYNC_COMPATIBILITY_POLL_TIMEOUT_SECONDS = 45.0
ASYNC_PROJECT_POLL_TIMEOUT_SECONDS = 25.0
ASYNC_MARKER_TIMEOUT_SECONDS = 15.0
# The wall-clock job timer starts before submission returns.  Keep marker jobs
# alive through marker discovery and the live-root proof, then leave room for
# the looping probe to settle inside the following result-poll window.
ASYNC_MARKER_SCHEDULING_GRACE_SECONDS = 5.0
ASYNC_PULSE_TIMEOUT_SECONDS = 3.0
ASYNC_RECOVERED_LINGER_SECONDS = 5.0
ASYNC_LOOP_JOB_TIMEOUT_SECONDS = (
    ASYNC_SUBMISSION_TIMEOUT_SECONDS
    + ASYNC_MARKER_TIMEOUT_SECONDS
    + TOOL_CALL_TIMEOUT_SECONDS
    + ASYNC_PULSE_TIMEOUT_SECONDS
    + ASYNC_MARKER_SCHEDULING_GRACE_SECONDS
)
ASYNC_RECOVERED_JOB_TIMEOUT_SECONDS = (
    ASYNC_SUBMISSION_TIMEOUT_SECONDS
    + ASYNC_MARKER_TIMEOUT_SECONDS
    + ASYNC_RECOVERED_LINGER_SECONDS
    + ASYNC_MARKER_SCHEDULING_GRACE_SECONDS
)
ASYNC_RESULT_PUBLICATION_GRACE_SECONDS = 5.0
ASYNC_LOOP_SETTLE_TIMEOUT_SECONDS = (
    ASYNC_LOOP_JOB_TIMEOUT_SECONDS + ASYNC_RESULT_PUBLICATION_GRACE_SECONDS
)
ASYNC_RECOVERED_SETTLE_TIMEOUT_SECONDS = (
    ASYNC_MARKER_TIMEOUT_SECONDS + ASYNC_PROJECT_POLL_TIMEOUT_SECONDS
)
ASYNC_CHILD_EXIT_TIMEOUT_SECONDS = 10.0
WORKER_INVENTORY_TIMEOUT_SECONDS = 110.0
SETUP_SCHEDULING_GRACE_SECONDS = 40.0
INVENTORY_SCHEDULING_GRACE_SECONDS = 30.0
NONCE_START_BUDGET_SECONDS = 10.0
OLD_ROOT_EXIT_TIMEOUT_SECONDS = 15.0
CYCLE_SCHEDULING_GRACE_SECONDS = 10.0
BRIDGE_CLOSE_BOUND_SECONDS = 20.0
BRIDGE_CLEANUP_SCHEDULING_GRACE_SECONDS = 20.0
ASYNC_CHILD_ISOLATION_BOUND_SECONDS = (
    ASYNC_SUBMISSION_TIMEOUT_SECONDS
    + ASYNC_RECOVERED_SETTLE_TIMEOUT_SECONDS
    + ASYNC_CHILD_EXIT_TIMEOUT_SECONDS
)
ASYNC_ISOLATION_BOUND_SECONDS = (
    ASYNC_SUBMISSION_TIMEOUT_SECONDS
    + ASYNC_COMPATIBILITY_POLL_TIMEOUT_SECONDS
    + ASYNC_SUBMISSION_TIMEOUT_SECONDS
    + ASYNC_PROJECT_POLL_TIMEOUT_SECONDS
    + ASYNC_SUBMISSION_TIMEOUT_SECONDS
    + ASYNC_LOOP_SETTLE_TIMEOUT_SECONDS
    + ASYNC_CHILD_EXIT_TIMEOUT_SECONDS
)
DEFAULT_SETUP_TIMEOUT_SECONDS = 3366.0
DEFAULT_CYCLE_TIMEOUT_SECONDS = 230.0
DEFAULT_INVENTORY_TIMEOUT_SECONDS = 470.0
DEFAULT_BRIDGE_CLEANUP_TIMEOUT_SECONDS = 100.0
DEFAULT_POST_CLEANUP_TIMEOUT_SECONDS = 225.0
DEFAULT_HEALTHY_TIMEOUT_SECONDS = (
    min(DEFAULT_WATCHDOG_NORMAL_SECONDS, DEFAULT_WATCHDOG_DISPATCH_SECONDS)
    - NONCE_START_BUDGET_SECONDS
)
DEFAULT_RESTART_TIMEOUT_SECONDS = 60.0
DEFAULT_READINESS_TIMEOUT_SECONDS = 45.0
_TERM_DEFER_DEPTH = 0
_PENDING_TERM_SIGNAL: int | None = None
_PENDING_PHASE_TIMEOUT: SoakPhaseTimeout | None = None
PhaseTimeoutState = tuple[str, tuple[float, float], float, object, float]
_PHASE_TIMEOUT_STATE: PhaseTimeoutState | None = None


class SoakPhaseTimeout(TimeoutError):
    """A named soak phase exceeded its whole-phase deadline."""


def positive_environment_seconds(name: str, default: float) -> float:
    """Return a finite positive environment duration, installing DEFAULT."""
    raw = os.environ.setdefault(name, f"{default:g}")
    try:
        value = float(raw)
    except ValueError as error:
        raise AssertionError(f"invalid {name}: {raw!r}") from error
    if not math.isfinite(value) or value <= 0:
        raise AssertionError(f"invalid {name}: {raw!r}")
    return value


def configure_watchdog_environment() -> float:
    """Use production watchdogs and return a bounded hung-response wait."""
    normal = positive_environment_seconds(
        "ANVIL_SMOKE_WATCHDOG_NORMAL_SECONDS",
        DEFAULT_WATCHDOG_NORMAL_SECONDS,
    )
    dispatch = positive_environment_seconds(
        "ANVIL_SMOKE_WATCHDOG_DISPATCH_SECONDS",
        DEFAULT_WATCHDOG_DISPATCH_SECONDS,
    )
    return min(normal, dispatch) + WATCHDOG_RESPONSE_GRACE_SECONDS


def configure_soak_timeout_environment(
    recovery_response_timeout: float,
) -> dict[str, float]:
    """Load soak phase bounds and validate their overlapping-cycle policy."""
    timeouts = {
        "setup": positive_environment_seconds(
            "ANVIL_PERSISTENT_SOAK_SETUP_SECONDS",
            DEFAULT_SETUP_TIMEOUT_SECONDS,
        ),
        "cycle": positive_environment_seconds(
            "ANVIL_PERSISTENT_SOAK_CYCLE_SECONDS",
            DEFAULT_CYCLE_TIMEOUT_SECONDS,
        ),
        "inventory": positive_environment_seconds(
            "ANVIL_PERSISTENT_SOAK_INVENTORY_SECONDS",
            DEFAULT_INVENTORY_TIMEOUT_SECONDS,
        ),
        "bridge_cleanup": positive_environment_seconds(
            "ANVIL_PERSISTENT_SOAK_BRIDGE_CLEANUP_SECONDS",
            DEFAULT_BRIDGE_CLEANUP_TIMEOUT_SECONDS,
        ),
        "post_cleanup": positive_environment_seconds(
            "ANVIL_PERSISTENT_SOAK_POST_CLEANUP_SECONDS",
            DEFAULT_POST_CLEANUP_TIMEOUT_SECONDS,
        ),
        "healthy": positive_environment_seconds(
            "ANVIL_PERSISTENT_SOAK_HEALTHY_SECONDS",
            DEFAULT_HEALTHY_TIMEOUT_SECONDS,
        ),
        "restart": positive_environment_seconds(
            "ANVIL_PERSISTENT_SOAK_RESTART_SECONDS",
            DEFAULT_RESTART_TIMEOUT_SECONDS,
        ),
        "readiness": positive_environment_seconds(
            "ANVIL_PERSISTENT_SOAK_READINESS_SECONDS",
            DEFAULT_READINESS_TIMEOUT_SECONDS,
        ),
    }
    normal = float(os.environ["ANVIL_SMOKE_WATCHDOG_NORMAL_SECONDS"])
    dispatch = float(os.environ["ANVIL_SMOKE_WATCHDOG_DISPATCH_SECONDS"])
    client_startup = positive_environment_seconds(
        "ANVIL_MCP_CLIENT_STARTUP_SECONDS",
        DEFAULT_CLIENT_STARTUP_SECONDS,
    )
    client_tool = positive_environment_seconds(
        "ANVIL_MCP_CLIENT_TOOL_SECONDS",
        DEFAULT_CLIENT_TOOL_SECONDS,
    )
    overlap_window = min(normal, dispatch)
    sequential_overlap = NONCE_START_BUDGET_SECONDS + timeouts["healthy"]
    if sequential_overlap > overlap_window:
        raise AssertionError(
            "nonce-start plus healthy-sibling bounds must fit sequentially "
            "inside the watchdog overlap window: "
            f"nonce={NONCE_START_BUDGET_SECONDS:g} "
            f"healthy={timeouts['healthy']:g} watchdog={overlap_window:g}"
        )
    minimum_cycle = (
        recovery_response_timeout
        + timeouts["restart"]
        + OLD_ROOT_EXIT_TIMEOUT_SECONDS
        + timeouts["readiness"]
        + CYCLE_SCHEDULING_GRACE_SECONDS
    )
    if timeouts["cycle"] < minimum_cycle:
        raise AssertionError(
            f"cycle bound {timeouts['cycle']:g}s is below its named phases "
            f"{minimum_cycle:g}s"
        )
    minimum_setup = (
        FIXTURE_COMMAND_COUNT * LOCAL_COMMAND_TIMEOUT_SECONDS
        + BRIDGE_COUNT
        * (
            client_startup
            + INSTANCE_DISCOVERY_TIMEOUT_SECONDS
            + TOOLS_LIST_TIMEOUT_SECONDS
            + 3 * TOOL_CALL_TIMEOUT_SECONDS
            + client_tool
            + ASYNC_ISOLATION_BOUND_SECONDS
        )
        + TOOL_CALL_TIMEOUT_SECONDS
        + YIELDING_DISPATCH_SECONDS
        + WATCHDOG_RESPONSE_GRACE_SECONDS
        + SETUP_SCHEDULING_GRACE_SECONDS
    )
    if timeouts["setup"] < minimum_setup:
        raise AssertionError(
            f"setup bound {timeouts['setup']:g}s is below its sequential "
            f"nested bounds plus scheduling grace ({minimum_setup:g}s)"
        )
    minimum_inventory = (
        BRIDGE_COUNT
        * (
            ASYNC_CHILD_ISOLATION_BOUND_SECONDS
            + WORKER_INVENTORY_TIMEOUT_SECONDS
            + LOCAL_COMMAND_TIMEOUT_SECONDS
        )
        + INVENTORY_SCHEDULING_GRACE_SECONDS
    )
    if timeouts["inventory"] < minimum_inventory:
        raise AssertionError(
            f"inventory bound {timeouts['inventory']:g}s is below its "
            f"sequential nested bounds plus scheduling grace "
            f"({minimum_inventory:g}s)"
        )
    minimum_cleanup = (
        2 * BRIDGE_CLOSE_BOUND_SECONDS + BRIDGE_CLEANUP_SCHEDULING_GRACE_SECONDS
    )
    if timeouts["bridge_cleanup"] < minimum_cleanup:
        raise AssertionError(
            f"bridge cleanup bound {timeouts['bridge_cleanup']:g}s is below "
            f"two closes plus scheduling grace ({minimum_cleanup:g}s)"
        )
    return timeouts


def healthy_sibling_deadline(
    hang_started: float,
    configured_timeout: float,
    recovery_response_timeout: float,
) -> float:
    """Return the absolute end of the shared nonce and healthy window."""
    configured_deadline = (
        hang_started + NONCE_START_BUDGET_SECONDS + configured_timeout
    )
    watchdog_deadline = (
        hang_started
        + recovery_response_timeout
        - WATCHDOG_RESPONSE_GRACE_SECONDS
    )
    return min(configured_deadline, watchdog_deadline)


def wait_for_nonce(path: Path, *, deadline: float) -> None:
    """Wait for nonce publication inside the shared watchdog deadline."""
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        if path.exists() and time.monotonic() < deadline:
            return
        time.sleep(min(0.05, max(0.0, deadline - time.monotonic())))
    raise AssertionError("nonce did not appear before the shared watchdog deadline")


def _phase_timeout_handler(signum: int, _frame: object) -> None:
    global _PENDING_PHASE_TIMEOUT
    state = _PHASE_TIMEOUT_STATE
    if state is None:
        raise SoakPhaseTimeout(f"unexpected phase timer signal {signum}")
    name, _previous_timer, seconds, _previous_handler, _started_at = state
    error = SoakPhaseTimeout(f"{name} exceeded {seconds:g}s")
    if _TERM_DEFER_DEPTH:
        _PENDING_PHASE_TIMEOUT = error
        return
    raise error


def arm_phase_timeout(name: str, seconds: float) -> None:
    """Arm one process-local whole-phase deadline."""
    global _PHASE_TIMEOUT_STATE
    if _PHASE_TIMEOUT_STATE is not None:
        raise AssertionError("nested soak phase deadlines are unsupported")
    if _PENDING_PHASE_TIMEOUT is not None and _TERM_DEFER_DEPTH == 0:
        raise AssertionError("cannot arm a phase with a deferred timeout pending")
    if not hasattr(signal, "SIGALRM") or not hasattr(signal, "setitimer"):
        raise AssertionError("soak phase deadlines require POSIX interval timers")
    previous_handler = signal.getsignal(signal.SIGALRM)
    previous_timer = signal.setitimer(signal.ITIMER_REAL, 0)
    _PHASE_TIMEOUT_STATE = (
        name,
        previous_timer,
        seconds,
        previous_handler,
        time.monotonic(),
    )
    try:
        signal.signal(signal.SIGALRM, _phase_timeout_handler)
        signal.setitimer(signal.ITIMER_REAL, seconds)
    except BaseException:
        _PHASE_TIMEOUT_STATE = None
        signal.signal(signal.SIGALRM, previous_handler)
        signal.setitimer(signal.ITIMER_REAL, *previous_timer)
        raise


def disarm_phase_timeout() -> None:
    """Disarm the active phase deadline and restore any prior timer."""
    global _PHASE_TIMEOUT_STATE
    state = _PHASE_TIMEOUT_STATE
    if state is None:
        return
    _name, previous_timer, _seconds, previous_handler, started_at = state
    signal.setitimer(signal.ITIMER_REAL, 0)
    _PHASE_TIMEOUT_STATE = None
    signal.signal(signal.SIGALRM, previous_handler)
    previous_delay, previous_interval = previous_timer
    if previous_delay > 0:
        remaining = max(previous_delay - (time.monotonic() - started_at), 1e-6)
        signal.setitimer(signal.ITIMER_REAL, remaining, previous_interval)


@contextlib.contextmanager
def phase_timeout(name: str, seconds: float):
    """Bound a named soak phase and always restore process timer state."""
    arm_phase_timeout(name, seconds)
    try:
        yield
    finally:
        disarm_phase_timeout()


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_checked(argv: list[str], cwd: Path) -> None:
    try:
        completed = subprocess.run(
            argv,
            cwd=cwd,
            text=True,
            capture_output=True,
            check=False,
            env=os.environ.copy(),
            timeout=LOCAL_COMMAND_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        raise AssertionError(
            f"command timed out after {LOCAL_COMMAND_TIMEOUT_SECONDS}s: {argv!r}; "
            f"stdout={error.stdout!r} stderr={error.stderr!r}"
        ) from error
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


def async_success_probe_expression(project_file: Path, marker: Path) -> str:
    """Return a finite offload that stays alive long enough to identify."""
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
  (sleep-for {ASYNC_RECOVERED_LINGER_SECONDS:g})
  (+ 20 22))
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
    *,
    deadline: float,
) -> dict[str, dict[str, object]]:
    by_identifier = {identifier: name for name, identifier in identifiers.items()}
    responses: dict[str, dict[str, object]] = {}
    while len(responses) < len(identifiers):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise AssertionError(
                "pipelined responses exceeded their absolute deadline: "
                f"received={sorted(responses)} expected={sorted(identifiers)}"
            )
        response = bridge.receive_response(deadline=deadline)
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
    return bridge.has_complete_response()


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
    listed = bridge.request("tools/list", timeout=TOOLS_LIST_TIMEOUT_SECONDS)
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
        bridge.call_tool(
            "emacs-eval",
            {"expression": "(emacs-pid)"},
            timeout=TOOL_CALL_TIMEOUT_SECONDS,
        )
    )
    timeout_response = bridge.call_tool(
        "shell-run",
        {"cmd": "sleep 2", "timeout_sec": "1"},
        timeout=TOOL_CALL_TIMEOUT_SECONDS,
    )
    if "shell timeout after 1s" not in json.dumps(timeout_response):
        raise AssertionError(
            f"shell operation did not time out explicitly: {timeout_response!r}"
        )
    root_after_timeout = smoke.eval_value(
        bridge.call_tool(
            "emacs-eval",
            {"expression": "(emacs-pid)"},
            timeout=TOOL_CALL_TIMEOUT_SECONDS,
        )
    )
    if root_after_timeout != root_before_timeout:
        raise AssertionError(
            "an operation timeout restarted or disabled the healthy bridge: "
            f"{root_before_timeout!r} -> {root_after_timeout!r}"
        )

    identifiers = send_fixture_requests(bridge, fixtures)
    # This pipelines four ordinary calls, so its aggregate bound follows the
    # MCP client's tool envelope rather than acting as a host-load benchmark.
    responses = collect_responses(
        bridge,
        identifiers,
        deadline=time.monotonic() + smoke.CLIENT_TOOL_SECONDS,
    )
    try:
        validate_fixture_responses(responses, smoke, fixtures)
    except AssertionError as error:
        raise AssertionError(f"{error}\nbridge stderr:\n{bridge.stderr()}") from error


def assert_yielding_dispatch_headroom(bridge, smoke) -> None:
    """Prove a yielding call may outlive heartbeat without losing its root."""
    root_before = smoke.eval_value(
        bridge.call_tool(
            "emacs-eval",
            {"expression": "(emacs-pid)"},
            timeout=TOOL_CALL_TIMEOUT_SECONDS,
        )
    )
    response = bridge.call_tool(
        "emacs-eval",
        {
            "expression": (
                f"(progn (sleep-for {YIELDING_DISPATCH_SECONDS}) (emacs-pid))"
            )
        },
        timeout=YIELDING_DISPATCH_SECONDS + WATCHDOG_RESPONSE_GRACE_SECONDS,
    )
    root_after = smoke.eval_value(response)
    if root_after != root_before:
        raise AssertionError(
            "yielding dispatch crossed the production watchdog: "
            f"{root_before!r} -> {root_after!r}"
        )


def submit_async(bridge, smoke, expression: str, timeout: int | str) -> str:
    response = bridge.call_tool(
        "emacs-eval-async",
        {"expression": expression, "timeout": timeout},
        timeout=ASYNC_SUBMISSION_TIMEOUT_SECONDS,
    )
    text = smoke.response_text(response)
    match = re.search(r"\bjob-[0-9]+-[0-9]+\b", text)
    if match is None:
        raise AssertionError(f"async submission returned no job ID: {text}")
    return match.group(0)


def poll_async(
    bridge,
    smoke,
    job_id: str,
    timeout: float | None = None,
    *,
    deadline: float | None = None,
) -> str:
    if timeout is not None and deadline is not None:
        raise AssertionError("async poll timeout and deadline are mutually exclusive")
    if deadline is None:
        if timeout is None:
            raise AssertionError("async poll requires a timeout or deadline")
        deadline = time.monotonic() + timeout
    elif deadline <= time.monotonic():
        raise AssertionError("async poll deadline has already expired")
    last = ""
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        last = smoke.response_text(
            bridge.call_tool(
                "emacs-eval-result",
                {"job-id": job_id},
                deadline=deadline,
            )
        )
        if "status: done" in last or "status: error" in last:
            return last
        remaining = deadline - time.monotonic()
        if remaining > 0:
            time.sleep(min(0.1, remaining))
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
        try:
            completed = subprocess.run(
                [str(ps), "-axo", "pid=,ppid="],
                text=True,
                capture_output=True,
                check=True,
                timeout=LOCAL_COMMAND_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired as error:
            raise AssertionError(
                f"process snapshot timed out after {LOCAL_COMMAND_TIMEOUT_SECONDS}s; "
                f"stdout={error.stdout!r} stderr={error.stderr!r}"
            ) from error
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


def assert_pulse_changes(
    path: Path,
    before: str,
    timeout: float | None = None,
    *,
    deadline: float | None = None,
) -> None:
    if timeout is not None and deadline is not None:
        raise AssertionError("pulse timeout and deadline are mutually exclusive")
    if deadline is None:
        deadline = time.monotonic() + (
            ASYNC_PULSE_TIMEOUT_SECONDS if timeout is None else timeout
        )
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            current = path.read_text()
        except FileNotFoundError:
            current = ""
        if current and current != before and time.monotonic() < deadline:
            return
        time.sleep(min(0.05, max(0.0, deadline - time.monotonic())))
    raise AssertionError(f"root watchdog pulse stopped changing: {path}")


def read_complete_async_marker(path: Path) -> list[object] | None:
    """Return a complete child marker, tolerating an in-progress write."""
    try:
        child_info = json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError, UnicodeDecodeError):
        return None
    if (
        not isinstance(child_info, list)
        or len(child_info) != 3
        or not isinstance(child_info[0], int)
    ):
        return None
    return child_info


def wait_for_async_marker(
    bridge,
    smoke,
    job_id: str,
    marker: Path,
    *,
    deadline: float,
) -> list[object]:
    """Wait for a complete marker or fail with bounded job-state metadata."""
    marker_deadline = min(
        deadline,
        time.monotonic() + ASYNC_MARKER_TIMEOUT_SECONDS,
    )
    while True:
        remaining = marker_deadline - time.monotonic()
        if remaining <= 0:
            break
        child_info = read_complete_async_marker(marker)
        if child_info is not None and time.monotonic() < marker_deadline:
            return child_info
        time.sleep(min(0.05, max(0.0, marker_deadline - time.monotonic())))
    marker_error = AssertionError("condition did not become true")
    try:
        marker_size = marker.stat().st_size
    except FileNotFoundError:
        marker_exists = False
        marker_size = 0
    else:
        marker_exists = True
    now = time.monotonic()
    diagnostic_deadline = min(deadline, now + TOOL_CALL_TIMEOUT_SECONDS)
    if diagnostic_deadline <= now:
        job_state = "<diagnostic deadline exhausted>"
    else:
        try:
            response = bridge.call_tool(
                "emacs-eval-result",
                {"job-id": job_id},
                deadline=diagnostic_deadline,
            )
            job_state = smoke.response_text(response)[:2000]
        except SoakPhaseTimeout:
            raise
        except Exception as diagnostic_error:
            job_state = f"<diagnostic {type(diagnostic_error).__name__}>"
    raise AssertionError(
        "async child marker did not become complete: "
        f"exists={marker_exists} bytes={marker_size} job-state:\n{job_state}"
    ) from marker_error


def assert_async_compatibility(bridge, smoke) -> None:
    """Prove callers with the legacy string timeout remain compatible."""
    compatibility_job = submit_async(
        bridge,
        smoke,
        "(+ 20 22)",
        timeout="30",
    )
    compatibility_result = poll_async(
        bridge,
        smoke,
        compatibility_job,
        timeout=ASYNC_COMPATIBILITY_POLL_TIMEOUT_SECONDS,
    )
    if (
        "status: done" not in compatibility_result
        or "result: 42" not in compatibility_result
    ):
        raise AssertionError(
            f"cached string timeout caller failed: {compatibility_result}"
        )


def assert_project_async_execution(bridge, smoke, fixtures: dict[str, Path]) -> None:
    """Prove a finite async job receives its project environment."""
    finite_job = submit_async(
        bridge,
        smoke,
        direnv_expression(fixtures["project_file"]),
        timeout=15,
    )
    finite_result = poll_async(
        bridge,
        smoke,
        finite_job,
        timeout=ASYNC_PROJECT_POLL_TIMEOUT_SECONDS,
    )
    if (
        "status: done" not in finite_result
        or DIRENV_MARKER not in finite_result
        or COMMAND_NAME not in finite_result
    ):
        raise AssertionError(
            f"finite async job lost the project environment: {finite_result}"
        )


def assert_async_execution(bridge, smoke, fixtures: dict[str, Path]) -> None:
    """Prove compatibility and project-aware async jobs complete."""
    assert_async_compatibility(bridge, smoke)
    assert_project_async_execution(bridge, smoke, fixtures)


def assert_async_isolation(
    bridge,
    instance: dict[str, object],
    smoke,
    module,
    fixtures: dict[str, Path],
    records: set[tuple[int, str]],
    suffix: str,
) -> None:
    assert_async_execution(bridge, smoke, fixtures)

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
        timeout=ASYNC_LOOP_JOB_TIMEOUT_SECONDS,
    )
    settle_deadline = time.monotonic() + ASYNC_LOOP_SETTLE_TIMEOUT_SECONDS
    child_info = wait_for_async_marker(
        bridge,
        smoke,
        job_id,
        marker,
        deadline=settle_deadline,
    )
    child_pid, local_marker, executable = child_info
    child_identity = record_identity(records, module, child_pid)
    if child_pid == root_pid:
        raise AssertionError("async expression ran inside the root daemon")
    if local_marker != DIRENV_MARKER or executable != str(
        fixtures["command"].resolve()
    ):
        raise AssertionError(f"async child lost direnv: {child_info!r}")

    root_probe_started = time.monotonic()
    root_probe_deadline = min(
        settle_deadline,
        root_probe_started + TOOL_CALL_TIMEOUT_SECONDS,
    )
    if root_probe_deadline <= root_probe_started:
        raise AssertionError("async root-probe deadline has already expired")
    current_root = smoke.eval_value(
        bridge.call_tool(
            "emacs-eval",
            {"expression": "(emacs-pid)"},
            deadline=root_probe_deadline,
        )
    )
    if current_root != root_pid:
        raise AssertionError(
            f"root changed while async child ran: {current_root!r} != {root_pid}"
        )
    pulse_started = time.monotonic()
    pulse_deadline = min(
        settle_deadline,
        pulse_started + ASYNC_PULSE_TIMEOUT_SECONDS,
    )
    if pulse_deadline <= pulse_started:
        raise AssertionError("async pulse deadline has already expired")
    assert_pulse_changes(pulse, pulse_before, deadline=pulse_deadline)

    terminal = poll_async(
        bridge,
        smoke,
        job_id,
        deadline=settle_deadline,
    )
    if "status: error" not in terminal or "timeout" not in terminal.lower():
        raise AssertionError(f"looping async job did not time out: {terminal}")
    smoke.eventually(
        lambda: module.process_start_identity(child_pid) != child_identity,
        timeout=ASYNC_CHILD_EXIT_TIMEOUT_SECONDS,
    )
    status = smoke.read_running_status(instance["status_path"])
    if (
        not status
        or status["daemon_pid"] != root_pid
        or module.process_start_identity(root_pid) != root_identity
    ):
        raise AssertionError(f"async timeout damaged the root daemon: {status!r}")


def assert_recovered_async_isolation(
    bridge,
    instance: dict[str, object],
    smoke,
    module,
    fixtures: dict[str, Path],
    records: set[tuple[int, str]],
    suffix: str,
) -> None:
    """Prove a recovered root still offloads a successful project-aware job."""
    runtime_dir = instance["runtime_dir"]
    if not isinstance(runtime_dir, Path):
        raise AssertionError(f"invalid runtime directory: {runtime_dir!r}")
    marker = runtime_dir / f"recovered-async-child-{suffix}.json"
    marker.unlink(missing_ok=True)
    root_pid = instance["status"]["daemon_pid"]
    root_identity = record_identity(records, module, root_pid)

    job_id = submit_async(
        bridge,
        smoke,
        async_success_probe_expression(fixtures["project_file"], marker),
        timeout=ASYNC_RECOVERED_JOB_TIMEOUT_SECONDS,
    )
    settle_deadline = time.monotonic() + ASYNC_RECOVERED_SETTLE_TIMEOUT_SECONDS
    child_info = wait_for_async_marker(
        bridge,
        smoke,
        job_id,
        marker,
        deadline=settle_deadline,
    )
    child_pid, local_marker, executable = child_info
    child_identity = record_identity(records, module, child_pid)
    if child_pid == root_pid:
        raise AssertionError("recovered async expression ran inside the root daemon")
    if local_marker != DIRENV_MARKER or executable != str(
        fixtures["command"].resolve()
    ):
        raise AssertionError(f"recovered async child lost direnv: {child_info!r}")

    terminal = poll_async(
        bridge,
        smoke,
        job_id,
        deadline=settle_deadline,
    )
    if "status: done" not in terminal or "result: 42" not in terminal:
        raise AssertionError(f"recovered async child did not complete: {terminal}")
    smoke.eventually(
        lambda: module.process_start_identity(child_pid) != child_identity,
        timeout=ASYNC_CHILD_EXIT_TIMEOUT_SECONDS,
    )
    status = smoke.read_running_status(instance["status_path"])
    if (
        not status
        or status["daemon_pid"] != root_pid
        or module.process_start_identity(root_pid) != root_identity
    ):
        raise AssertionError(f"recovered async work damaged the root: {status!r}")


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
    recovery_response_timeout: float,
    restart_timeout: float,
    readiness_timeout: float,
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
    recovery_deadline = hang_started + recovery_response_timeout
    healthy_deadline = healthy_sibling_deadline(
        hang_started,
        healthy_timeout,
        recovery_response_timeout,
    )
    hang_identifier = hanging.send_request(
        "tools/call",
        {"name": "emacs-eval", "arguments": {"expression": expression}},
    )
    wait_for_nonce(nonce, deadline=healthy_deadline)
    if response_buffered(hanging):
        raise AssertionError("hung request completed before sibling work began")

    sibling_started = time.monotonic()
    identifiers = send_fixture_requests(healthy, fixtures)
    if time.monotonic() >= healthy_deadline:
        raise AssertionError(
            "healthy sibling requests exhausted the shared watchdog window"
        )
    responses = collect_responses(healthy, identifiers, deadline=healthy_deadline)
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

    if time.monotonic() >= recovery_deadline:
        raise AssertionError(
            "hung response exceeded its absolute watchdog-response deadline"
        )
    hung_response = hanging.receive_response(deadline=recovery_deadline)
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
        timeout=restart_timeout,
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
        timeout=OLD_ROOT_EXIT_TIMEOUT_SECONDS,
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
        timeout=readiness_timeout,
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


def handle_term(signum: int, _frame: object) -> None:
    """Convert the outer timeout's TERM into normal Python unwinding."""
    global _PENDING_TERM_SIGNAL
    if _TERM_DEFER_DEPTH:
        _PENDING_TERM_SIGNAL = signum
        return
    raise SystemExit(128 + signum)


def install_signal_handlers() -> None:
    """Install the termination contract used by the standalone soak check."""
    global _PENDING_PHASE_TIMEOUT, _PENDING_TERM_SIGNAL
    if _TERM_DEFER_DEPTH:
        raise AssertionError("cannot install signal handlers inside a deferral")
    _PENDING_PHASE_TIMEOUT = None
    _PENDING_TERM_SIGNAL = None
    signal.signal(signal.SIGTERM, handle_term)


@contextlib.contextmanager
def defer_termination():
    """Delay TERM and phase unwinding across resource-ownership gaps."""
    global _PENDING_PHASE_TIMEOUT, _PENDING_TERM_SIGNAL, _TERM_DEFER_DEPTH
    _TERM_DEFER_DEPTH += 1
    try:
        yield
    finally:
        _TERM_DEFER_DEPTH -= 1
        if _TERM_DEFER_DEPTH == 0:
            signum = _PENDING_TERM_SIGNAL
            phase_error = _PENDING_PHASE_TIMEOUT
            _PENDING_TERM_SIGNAL = None
            _PENDING_PHASE_TIMEOUT = None
            if signum is not None:
                raise SystemExit(128 + signum)
            if phase_error is not None:
                raise phase_error


def construct_tracked_bridge(bridges, bridge_type, *args):
    """Construct and register a bridge without an interruptible ownership gap."""
    with defer_termination():
        bridge = bridge_type(*args)
        bridges.append(bridge)
    return bridge


def print_latency_summary(samples: list[dict[str, float]]) -> None:
    """Emit useful partial latency evidence without requiring full success."""
    print(f"persistent latency summary: cycles={len(samples)}", flush=True)
    if not samples:
        return
    for name in sorted(set().union(*(sample.keys() for sample in samples))):
        values = [sample[name] for sample in samples if name in sample]
        print(
            f"latency {name}: min={min(values):.3f}s "
            f"median={median(values):.3f}s max={max(values):.3f}s",
            flush=True,
        )


def finalize_bridges(bridges, samples: list[dict[str, float]]) -> None:
    """Print partial evidence and attempt every bridge close in reverse order."""
    errors: list[Exception] = []
    phase_errors: list[SoakPhaseTimeout] = []
    try:
        with defer_termination():
            try:
                print_latency_summary(samples)
            finally:
                for bridge in reversed(bridges):
                    try:
                        bridge.close()
                    except SoakPhaseTimeout as error:
                        phase_errors.append(error)
                    except Exception as error:
                        errors.append(error)
    except SoakPhaseTimeout as error:
        phase_errors.append(error)
    if errors:
        details = "; ".join(f"{type(error).__name__}: {error}" for error in errors)
        raise RuntimeError(
            f"persistent soak bridge cleanup failed: {details}"
        ) from errors[0]
    if phase_errors:
        raise phase_errors[0]


def finalize_bridges_with_timeout(
    bridges,
    samples: list[dict[str, float]],
    timeout: float,
) -> None:
    """Transfer every bridge into bounded cleanup without a signal gap."""
    with defer_termination():
        disarm_phase_timeout()
        with phase_timeout("bridge cleanup", timeout):
            finalize_bridges(bridges, samples)


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
    if cycles < 1 or cycles > 100:
        raise AssertionError(f"invalid soak cycle count: {cycles}")

    recovery_response_timeout = configure_watchdog_environment()
    phase_timeouts = configure_soak_timeout_environment(recovery_response_timeout)
    os.environ["GIT_OPTIONAL_LOCKS"] = "0"
    os.environ["GIT_CONFIG_NOSYSTEM"] = "1"
    os.environ["GIT_CONFIG_GLOBAL"] = "/dev/null"
    install_signal_handlers()

    bridges = []
    instances: list[dict[str, object]] = []
    records: set[tuple[int, str]] = set()
    descendant_records: set[tuple[int, str | None]] = set()
    nonce_records: list[tuple[Path, str]] = []
    latency_samples: list[dict[str, float]] = []
    succeeded = False
    fixtures: dict[str, Path] | None = None
    home_baseline: dict[str, tuple[int, int, int]] | None = None
    arm_phase_timeout("setup", phase_timeouts["setup"])
    try:
        fixtures = setup_fixtures(git, direnv)
        home_baseline = smoke.snapshot_home(Path.home())
        for _index in range(BRIDGE_COUNT):
            construct_tracked_bridge(
                bridges,
                smoke.BridgeProcess,
                launcher,
                "anvil",
                HOST,
            )
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
                timeout=INSTANCE_DISCOVERY_TIMEOUT_SECONDS,
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
        assert_yielding_dispatch_headroom(bridges[0], smoke)
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

        disarm_phase_timeout()
        for cycle in range(cycles):
            with phase_timeout(
                f"recovery cycle {cycle + 1}/{cycles}",
                phase_timeouts["cycle"],
            ):
                sample = run_recovery_cycle(
                    cycle,
                    bridges,
                    instances,
                    smoke,
                    module,
                    fixtures,
                    records,
                    nonce_records,
                    phase_timeouts["healthy"],
                    recovery_response_timeout,
                    phase_timeouts["restart"],
                    phase_timeouts["readiness"],
                )
                latency_samples.append(sample)
                print(
                    f"persistent recovery cycle {cycle + 1}/{cycles} passed "
                    f"(sibling={sample['sibling']:.3f}s "
                    f"dispatch={sample['dispatch']:.3f}s "
                    f"restart={sample['restart']:.3f}s "
                    f"readiness={sample['readiness']:.3f}s)"
                )

        with phase_timeout(
            "post-recovery async and pre-cleanup inventory",
            phase_timeouts["inventory"],
        ):
            assert_nonce_records(nonce_records)
            assert_no_latency_growth(latency_samples)
            for index, (bridge, instance) in enumerate(zip(bridges, instances)):
                expected_root = instance["status"]["daemon_pid"]
                expected_identity = record_identity(records, module, expected_root)
                assert_recovered_async_isolation(
                    bridge,
                    instance,
                    smoke,
                    module,
                    fixtures,
                    records,
                    str(index),
                )
                current = smoke.read_running_status(instance["status_path"])
                if (
                    not current
                    or current["daemon_pid"] != expected_root
                    or module.process_start_identity(expected_root)
                    != expected_identity
                ):
                    raise AssertionError(
                        "post-recovery async work changed the root daemon: "
                        f"{current!r}"
                    )
                for pid in smoke.worker_pids(bridge):
                    record_identity(records, module, pid)
                descendant_records.update(
                    record_descendant_tree(module, bridge.pid, ps)
                )
            assert_nonce_records(nonce_records)
        succeeded = True
    finally:
        finalize_bridges_with_timeout(
            bridges,
            latency_samples,
            phase_timeouts["bridge_cleanup"],
        )

    if not succeeded:
        raise AssertionError("persistent bridge soak did not complete")
    if fixtures is None or home_baseline is None:
        raise AssertionError("persistent bridge setup did not record its baseline")
    with phase_timeout("post-cleanup verification", phase_timeouts["post_cleanup"]):
        for instance in instances:
            smoke.eventually(
                lambda instance=instance: not instance["runtime_dir"].exists()
            )
            smoke.eventually(
                lambda instance=instance: not instance["state_dir"].exists()
            )
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
