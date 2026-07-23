#!/usr/bin/env python3
"""Exercise production watchdog policy and SIGTERM cleanup for the soak."""

from __future__ import annotations

import importlib.util
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
from unittest import mock


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def test_timeout_budget(
    soak_path: Path,
    expected_normal: float,
    expected_dispatch: float,
    cycles: int,
    margin_percent: int,
    outer_timeout: float,
    kill_after: float,
    hard_ceiling: float,
) -> None:
    """Prove Python enforces the same named phase budget derived by Nix."""
    soak = load_module(soak_path, "persistent_soak_timeout_budget_test")
    os.environ["ANVIL_SMOKE_WATCHDOG_NORMAL_SECONDS"] = f"{expected_normal:g}"
    os.environ["ANVIL_SMOKE_WATCHDOG_DISPATCH_SECONDS"] = f"{expected_dispatch:g}"
    response_timeout = soak.configure_watchdog_environment()
    timeouts = soak.configure_soak_timeout_environment(response_timeout)
    watchdog_window = min(expected_normal, expected_dispatch)
    sequential_overlap = soak.NONCE_START_TIMEOUT_SECONDS + timeouts["healthy"]
    if sequential_overlap != watchdog_window:
        raise AssertionError(
            "sequential watchdog budget drifted: "
            f"nonce={soak.NONCE_START_TIMEOUT_SECONDS:g} "
            f"healthy={timeouts['healthy']:g} watchdog={watchdog_window:g}"
        )
    with mock.patch.dict(
        os.environ,
        {"ANVIL_PERSISTENT_SOAK_HEALTHY_SECONDS": f"{watchdog_window:g}"},
    ):
        try:
            soak.configure_soak_timeout_environment(response_timeout)
        except AssertionError as error:
            if "nonce-start plus healthy-sibling bounds" not in str(error):
                raise
        else:
            raise AssertionError("legacy full-window healthy budget was accepted")

    for variable, expected_fragment in (
        ("ANVIL_PERSISTENT_SOAK_SETUP_SECONDS", "setup bound"),
        ("ANVIL_PERSISTENT_SOAK_INVENTORY_SECONDS", "inventory bound"),
    ):
        with mock.patch.dict(os.environ, {variable: "1"}):
            try:
                soak.configure_soak_timeout_environment(response_timeout)
            except AssertionError as error:
                if expected_fragment not in str(error):
                    raise
            else:
                raise AssertionError(f"undersized {variable} was accepted")

    internal = (
        timeouts["setup"]
        + cycles * timeouts["cycle"]
        + timeouts["inventory"]
        + timeouts["bridge_cleanup"]
        + timeouts["post_cleanup"]
    )
    expected_outer = internal + math.ceil(internal * margin_percent / 100)
    if (
        kill_after <= 0
        or hard_ceiling > 162 * 60
        or outer_timeout != expected_outer
        or kill_after <= timeouts["bridge_cleanup"]
        or outer_timeout + kill_after > hard_ceiling
    ):
        raise AssertionError(
            f"outer timeout drifted: actual={outer_timeout:g} "
            f"expected={expected_outer:g} internal={internal:g} "
            f"kill-after={kill_after:g} hard-ceiling={hard_ceiling:g}"
        )

    original_handler = signal.getsignal(signal.SIGALRM)
    original_timer = signal.setitimer(signal.ITIMER_REAL, 0)
    restore_started = time.monotonic()
    prior_firings: list[int] = []

    def prior_handler(signum: int, _frame: object) -> None:
        prior_firings.append(signum)

    signal.signal(signal.SIGALRM, prior_handler)
    signal.setitimer(signal.ITIMER_REAL, 0.75, 0.25)
    started = time.monotonic()
    try:
        try:
            with soak.phase_timeout("focused deadline regression", 0.05):
                time.sleep(2)
        except soak.SoakPhaseTimeout as error:
            if "focused deadline regression exceeded" not in str(error):
                raise
        else:
            raise AssertionError("whole-phase timer did not interrupt blocking work")
        elapsed = time.monotonic() - started
        restored_delay, restored_interval = signal.getitimer(signal.ITIMER_REAL)
        if (
            elapsed > 1
            or signal.getsignal(signal.SIGALRM) is not prior_handler
            or not 0 < restored_delay < 0.75
            or restored_interval != 0.25
            or prior_firings
        ):
            raise AssertionError(
                "whole-phase timer was not bounded/restored: "
                f"elapsed={elapsed:.3f} timer="
                f"{(restored_delay, restored_interval)!r} "
                f"firings={prior_firings!r}"
            )
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, original_handler)
        original_delay, original_interval = original_timer
        if original_delay > 0:
            remaining = max(
                original_delay - (time.monotonic() - restore_started),
                1e-6,
            )
            signal.setitimer(signal.ITIMER_REAL, remaining, original_interval)


def test_healthy_sibling_deadline_preserves_watchdog_window(soak_path: Path) -> None:
    """Represent the shared nonce and healthy budget as one deadline."""
    soak = load_module(soak_path, "persistent_soak_healthy_budget_test")
    deadline_for = getattr(soak, "healthy_sibling_deadline", None)
    if deadline_for is None:
        raise AssertionError("healthy sibling budget has no absolute deadline")

    cases = (
        (100.0, 35.0, 75.0, 145.0),
        (100.0, 20.0, 75.0, 130.0),
        (100.0, 35.0, 60.0, 130.0),
    )
    for started, configured, response_timeout, expected in cases:
        actual = deadline_for(started, configured, response_timeout)
        if actual != expected:
            raise AssertionError(
                "healthy sibling deadline escaped its shared watchdog budget: "
                f"started={started:g} configured={configured:g} "
                f"actual={actual:g} expected={expected:g}"
            )


def test_recovery_cycle_uses_remaining_watchdog_window(soak_path: Path) -> None:
    """Carry one absolute watchdog deadline through healthy collection."""
    soak = load_module(soak_path, "persistent_soak_recovery_budget_test")
    now = [100.0]
    observed: list[dict[str, float]] = []
    hung_receives: list[tuple[tuple[object, ...], dict[str, float]]] = []

    class StopAfterHungResponse(Exception):
        pass

    class Bridge:
        def __init__(self, name):
            self.name = name

        def send_request(self, _method, _arguments):
            return 17

        def has_complete_response(self):
            return False

        def receive_response(self, *args, **kwargs):
            if self.name != "hanging":
                raise AssertionError("healthy bridge bypassed response collection")
            hung_receives.append((args, kwargs))
            raise StopAfterHungResponse

    old_status = {"daemon_pid": 101, "supervisor_pid": 201}
    healthy_status = {"daemon_pid": 102, "supervisor_pid": 202}

    class Smoke:
        @staticmethod
        def read_running_status(path):
            return old_status if path == "old-status" else healthy_status

        @staticmethod
        def eventually(_predicate, timeout):
            if timeout != soak.NONCE_START_TIMEOUT_SECONDS:
                raise AssertionError(f"unexpected nonce timeout: {timeout:g}")
            return True

    class Module:
        @staticmethod
        def process_start_identity(pid):
            return f"identity-{pid}"

    def send_fixture_requests(_bridge, _fixtures):
        now[0] = 103.0
        return {"file": 1, "org": 2, "git": 3, "elisp": 4}

    def collect_responses(_bridge, _identifiers, **bounds):
        now[0] = 110.0
        observed.append(bounds)
        return {}

    with (
        mock.patch.object(soak.time, "monotonic", side_effect=lambda: now[0]),
        mock.patch.object(soak, "record_identity", return_value="identity-101"),
        mock.patch.object(
            soak,
            "send_fixture_requests",
            side_effect=send_fixture_requests,
        ),
        mock.patch.object(soak, "collect_responses", side_effect=collect_responses),
        mock.patch.object(soak, "validate_fixture_responses"),
    ):
        try:
            soak.run_recovery_cycle(
                0,
                [Bridge("hanging"), Bridge("healthy")],
                [
                    {"status_path": "old-status", "runtime_dir": Path("/tmp/old")},
                    {
                        "status_path": "healthy-status",
                        "runtime_dir": Path("/tmp/healthy"),
                    },
                ],
                Smoke(),
                Module(),
                {},
                set(),
                [],
                35.0,
                75.0,
                40.0,
                45.0,
            )
        except StopAfterHungResponse:
            pass
        else:
            raise AssertionError("recovery cycle escaped the hung-response fixture")

    if observed != [{"deadline": 145.0}]:
        raise AssertionError(
            "recovery cycle did not preserve the absolute watchdog deadline: "
            f"{observed!r}"
        )
    if hung_receives != [((), {"deadline": 175.0})]:
        raise AssertionError(
            "recovery cycle re-anchored its watchdog-response deadline: "
            f"{hung_receives!r}"
        )


def test_phase_timeout_ownership(soak_path: Path) -> None:
    """Defer phase alarms until acquired resources are tracked and cleaned."""
    soak = load_module(soak_path, "persistent_soak_phase_ownership_test")

    tracked = []

    class AcquiredBridge:
        def __init__(self):
            signal.raise_signal(signal.SIGALRM)

    try:
        with soak.phase_timeout("constructor ownership", 60):
            soak.construct_tracked_bridge(tracked, AcquiredBridge)
    except soak.SoakPhaseTimeout as error:
        if "constructor ownership exceeded" not in str(error):
            raise
    else:
        raise AssertionError("constructor phase alarm was not delivered")
    if len(tracked) != 1:
        raise AssertionError("phase alarm escaped before bridge registration")

    close_order: list[str] = []

    class ClosingBridge:
        def __init__(self, name: str, raise_timeout: bool = False):
            self.name = name
            self.raise_timeout = raise_timeout

        def close(self):
            close_order.append(self.name)
            if self.raise_timeout:
                raise soak.SoakPhaseTimeout(f"close {self.name}")

    try:
        soak.finalize_bridges(
            [ClosingBridge("first"), ClosingBridge("second", True)],
            [],
        )
    except soak.SoakPhaseTimeout as error:
        if "close second" not in str(error):
            raise
    else:
        raise AssertionError("explicit cleanup phase timeout was lost")
    if close_order != ["second", "first"]:
        raise AssertionError(f"cleanup stopped after phase timeout: {close_order!r}")

    alarm_order: list[str] = []

    class AlarmBridge:
        def __init__(self, name: str, raise_alarm: bool = False):
            self.name = name
            self.raise_alarm = raise_alarm

        def close(self):
            alarm_order.append(f"start:{self.name}")
            if self.raise_alarm:
                signal.raise_signal(signal.SIGALRM)
            alarm_order.append(f"done:{self.name}")

    try:
        with soak.phase_timeout("deferred cleanup", 60):
            soak.finalize_bridges(
                [AlarmBridge("first"), AlarmBridge("second", True)],
                [],
            )
    except soak.SoakPhaseTimeout as error:
        if "deferred cleanup exceeded" not in str(error):
            raise
    else:
        raise AssertionError("deferred cleanup alarm was not delivered")
    if alarm_order != [
        "start:second",
        "done:second",
        "start:first",
        "done:first",
    ]:
        raise AssertionError(f"alarm interrupted cleanup ownership: {alarm_order!r}")

    transition_order: list[str] = []

    class TransitionBridge:
        def __init__(self, name: str):
            self.name = name

        def close(self):
            transition_order.append(self.name)

    original_term_handler = signal.getsignal(signal.SIGTERM)
    original_disarm = soak.disarm_phase_timeout
    disarm_calls = 0

    def signal_at_cleanup_boundary() -> None:
        nonlocal disarm_calls
        original_disarm()
        disarm_calls += 1
        if disarm_calls == 1:
            signal.raise_signal(signal.SIGTERM)

    soak.install_signal_handlers()
    try:
        with mock.patch.object(
            soak,
            "disarm_phase_timeout",
            side_effect=signal_at_cleanup_boundary,
        ):
            try:
                soak.finalize_bridges_with_timeout(
                    [TransitionBridge("first"), TransitionBridge("second")],
                    [],
                    60,
                )
            except SystemExit as error:
                if error.code != 128 + signal.SIGTERM:
                    raise
            else:
                raise AssertionError("cleanup-boundary TERM was not delivered")
    finally:
        original_disarm()
        signal.signal(signal.SIGTERM, original_term_handler)
    if transition_order != ["second", "first"]:
        raise AssertionError(
            f"cleanup-boundary TERM skipped bridge closes: {transition_order!r}"
        )

    with soak.phase_timeout("fresh phase", 1):
        pass


def test_response_reader(soak_path: Path, smoke_path: Path) -> None:
    """Prove partial frames time out and prefetched frames remain visible."""
    soak = load_module(soak_path, "persistent_soak_reader_test")
    smoke = load_module(smoke_path, "agent_supervisor_smoke_reader_test")
    read_descriptor, write_descriptor = os.pipe()
    os.set_blocking(read_descriptor, False)
    stdout = os.fdopen(read_descriptor, "r", encoding="utf-8")
    stderr = tempfile.TemporaryFile(mode="w+")
    bridge = object.__new__(smoke.BridgeProcess)
    bridge.process = SimpleNamespace(stdout=stdout, poll=lambda: None)
    bridge.stderr_file = stderr
    bridge.response_buffer = bytearray()
    try:
        os.write(write_descriptor, b'{"jsonrpc":"2.0"')
        try:
            bridge.receive_response(timeout=0.05)
        except AssertionError as error:
            if "timed out" not in str(error):
                raise
        else:
            raise AssertionError("partial frame blocked past its response deadline")

        os.write(
            write_descriptor,
            b',"id":1}\n{"jsonrpc":"2.0","id":2}\n',
        )
        first = bridge.receive_response(timeout=1)
        if first.get("id") != 1:
            raise AssertionError(f"partial frame reassembly failed: {first!r}")
        if not soak.response_buffered(bridge):
            raise AssertionError("prefetched second frame was invisible to the soak")
        second = bridge.receive_response(timeout=1)
        if second.get("id") != 2:
            raise AssertionError(f"prefetched frame was lost: {second!r}")

        bridge.response_buffer.extend(b'{"jsonrpc":"2.0","id":3}\n')
        with mock.patch.object(
            soak.time,
            "monotonic",
            side_effect=(103.0, 146.0),
        ):
            try:
                soak.collect_responses(
                    bridge,
                    {"late": 3},
                    deadline=145.0,
                )
            except AssertionError as error:
                if "timed out" not in str(error):
                    raise
            else:
                raise AssertionError(
                    "prefetched response escaped its absolute deadline"
                )
    finally:
        os.close(write_descriptor)
        stdout.close()
        stderr.close()


def test_request_preserves_absolute_deadline(smoke_path: Path) -> None:
    """Pass an absolute tool deadline unchanged into the frame reader."""
    smoke = load_module(smoke_path, "agent_supervisor_smoke_request_deadline_test")
    bridge = object.__new__(smoke.BridgeProcess)
    with (
        mock.patch.object(bridge, "send_request", return_value=23) as send_request,
        mock.patch.object(
            bridge,
            "receive_response",
            return_value={"jsonrpc": "2.0", "id": 23, "result": {}},
        ) as receive_response,
        mock.patch.object(smoke.time, "monotonic", return_value=100.0),
    ):
        for invalid in (
            {"timeout": 1.0, "deadline": 145.0},
            {"deadline": 99.0},
        ):
            try:
                bridge.call_tool("emacs-eval-result", {}, **invalid)
            except AssertionError:
                pass
            else:
                raise AssertionError(f"invalid response bounds were accepted: {invalid}")
            if send_request.called:
                raise AssertionError(
                    f"invalid response bounds dispatched a request: {invalid}"
                )
        try:
            response = bridge.call_tool("emacs-eval-result", {}, deadline=145.0)
        except TypeError as error:
            raise AssertionError("tool call cannot preserve an absolute deadline") from error
    if response.get("id") != 23:
        raise AssertionError(f"absolute-deadline tool call failed: {response!r}")
    if receive_response.call_args != mock.call(deadline=145.0):
        raise AssertionError(
            "tool call re-anchored its absolute response deadline: "
            f"{receive_response.call_args!r}"
        )


def test_async_poll_deadline(soak_path: Path) -> None:
    """Prove the nested result request cannot overrun the poll deadline."""
    soak = load_module(soak_path, "persistent_soak_async_poll_test")
    now = [100.0]
    observed: list[dict[str, float]] = []

    class Bridge:
        def call_tool(self, _name, _arguments, **bounds):
            observed.append(bounds)
            now[0] = 112.0
            return object()

    class Smoke:
        @staticmethod
        def response_text(_response) -> str:
            return "status: done\nresult: 42"

    with mock.patch.object(soak.time, "monotonic", side_effect=lambda: now[0]):
        result = soak.poll_async(Bridge(), Smoke(), "job-1-1", timeout=25.0)
    if result != "status: done\nresult: 42":
        raise AssertionError(f"unexpected async poll result: {result!r}")
    if observed != [{"deadline": 125.0}]:
        raise AssertionError(
            f"async result request re-anchored its deadline: {observed!r}"
        )


def test_async_marker_readiness(soak_path: Path) -> None:
    """Prove empty and partial marker writes cannot escape readiness polling."""
    soak = load_module(soak_path, "persistent_soak_async_marker_test")
    with tempfile.TemporaryDirectory() as temporary:
        marker = Path(temporary) / "marker.json"
        for raw in (b"", b"[123,", b"[123,\"marker\"]", b"\xff"):
            marker.write_bytes(raw)
            if soak.read_complete_async_marker(marker) is not None:
                raise AssertionError(f"partial async marker was accepted: {raw!r}")
        expected = [123, "marker", "/project/bin/command"]
        marker.write_text(json.dumps(expected), encoding="utf-8")
        if soak.read_complete_async_marker(marker) != expected:
            raise AssertionError("complete async marker was not accepted")


def test_recovered_async_requires_child(soak_path: Path) -> None:
    """Prove an in-root async fallback cannot satisfy recovery evidence."""
    soak = load_module(soak_path, "persistent_soak_recovered_async_test")
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        runtime = root / "runtime"
        project = root / "project"
        runtime.mkdir()
        project.mkdir()
        project_file = project / "visited.txt"
        command = project / "anvil-soak-command"
        project_file.write_text("project\n", encoding="utf-8")
        command.write_text("command\n", encoding="utf-8")
        marker = runtime / "recovered-async-child-test.json"
        root_pid = os.getpid()

        class Module:
            @staticmethod
            def process_start_identity(pid: int) -> str:
                return f"identity-{pid}"

        class Smoke:
            @staticmethod
            def eventually(predicate, timeout):
                result = predicate()
                if not result:
                    raise AssertionError(f"predicate failed within {timeout:g}s")
                return result

        def submit_in_root(*_args, **_kwargs) -> str:
            marker.write_text(
                json.dumps([root_pid, soak.DIRENV_MARKER, str(command.resolve())]),
                encoding="utf-8",
            )
            return "job-1-1"

        with mock.patch.object(soak, "submit_async", side_effect=submit_in_root):
            try:
                soak.assert_recovered_async_isolation(
                    object(),
                    {
                        "runtime_dir": runtime,
                        "status": {"daemon_pid": root_pid},
                        "status_path": root / "status.json",
                    },
                    Smoke(),
                    Module(),
                    {"project_file": project_file, "command": command},
                    set(),
                    "test",
                )
            except AssertionError as error:
                if "inside the root daemon" not in str(error):
                    raise
            else:
                raise AssertionError("in-root recovered async fallback was accepted")


def test_cleanup_contract(smoke_path: Path) -> None:
    """Prove cleanup attempts siblings, retains failures, and reports leaks."""
    smoke = load_module(smoke_path, "agent_supervisor_smoke_cleanup_test")
    events: list[str] = []

    class Closing:
        def __init__(self, name: str, failures: int = 0) -> None:
            self.name = name
            self.failures = failures

        def close(self) -> None:
            events.append(self.name)
            if self.failures:
                self.failures -= 1
                raise RuntimeError(self.name)

    mapping = {
        "good": Closing("mapping-good"),
        "flaky": Closing("mapping-flaky", failures=1),
    }
    errors = smoke.close_bridge_mapping(mapping)
    if len(errors) != 1 or list(mapping) != ["flaky"]:
        raise AssertionError(
            f"failed bridge ownership was lost: {mapping!r} {errors!r}"
        )
    if events != ["mapping-flaky", "mapping-good"]:
        raise AssertionError(f"mapping cleanup stopped early: {events!r}")
    if smoke.close_bridge_mapping(mapping) or mapping:
        raise AssertionError("retained bridge could not be retried")

    events.clear()
    resources = [Closing("resource-good"), Closing("resource-flaky", failures=1)]
    owners = [Closing("owner-good")]
    errors = smoke.attempt_close_resources(resources, owners)
    if len(errors) != 1 or events != [
        "resource-flaky",
        "resource-good",
        "owner-good",
    ]:
        raise AssertionError(f"resource cleanup stopped early: {events!r} {errors!r}")

    class RetryBridge:
        attempts = 0

        def __init__(self, *_args, **_kwargs) -> None:
            self.process = SimpleNamespace(pid=777)

        def close(self) -> None:
            type(self).attempts += 1
            if type(self).attempts == 1:
                raise RuntimeError("retry bridge")

    class RetryConnection:
        def __init__(self) -> None:
            self.requests = iter(
                [
                    {
                        "operation": "spawn",
                        "bridge_id": "bridge-1",
                        "server_id": "anvil",
                        "host": "test",
                    },
                    {"operation": "shutdown"},
                    {"operation": "shutdown"},
                ]
            )
            self.responses: list[dict[str, object]] = []
            self.closed = False

        def recv(self):
            return next(self.requests)

        def send(self, response) -> None:
            self.responses.append(response)

        def close(self) -> None:
            self.closed = True

    connection = RetryConnection()
    with mock.patch.object(smoke, "BridgeProcess", RetryBridge):
        smoke.owner_proxy_main(connection, "/unused-launcher")
    if RetryBridge.attempts != 2:
        raise AssertionError("owner proxy exited instead of retrying failed cleanup")
    if not connection.closed or [item.get("ok") for item in connection.responses] != [
        True,
        True,
        False,
        True,
    ]:
        raise AssertionError(
            f"owner proxy cleanup retry protocol failed: {connection.responses!r}"
        )

    retry_owner = object.__new__(smoke.OwnerProxy)
    retry_owner.process = mock.Mock()
    retry_owner.process.pid = 4241
    retry_owner.process.name = "retry-owner"
    retry_owner.process.is_alive.return_value = True
    retry_owner.bridge_ids = {"bridge-1"}
    retry_owner.connection = mock.Mock()
    retry_owner.connection_closed = False
    retry_owner.rpc = mock.Mock(side_effect=AssertionError("child cleanup failed"))
    try:
        retry_owner.close()
    except AssertionError:
        pass
    else:
        raise AssertionError("owner close hid a child cleanup failure")
    if retry_owner.bridge_ids != {"bridge-1"} or retry_owner.connection_closed:
        raise AssertionError("owner close discarded retryable child ownership")
    retry_owner.process.join.assert_not_called()

    bridge = object.__new__(smoke.BridgeProcess)
    bridge.process = mock.Mock()
    bridge.process.poll.return_value = None
    bridge.process.stdin = None
    bridge.process.wait.side_effect = [
        subprocess.TimeoutExpired(["bridge"], 10),
        subprocess.TimeoutExpired(["bridge"], 5),
        subprocess.TimeoutExpired(["bridge"], 5),
    ]
    bridge.stderr_file = tempfile.TemporaryFile(mode="w+")
    try:
        bridge.close()
    except subprocess.TimeoutExpired:
        pass
    else:
        raise AssertionError("bridge close hid its failed post-KILL reap")
    if not bridge.stderr_file.closed:
        raise AssertionError("bridge close leaked its diagnostic descriptor")

    owner = object.__new__(smoke.OwnerProxy)
    owner.process = mock.Mock()
    owner.process.pid = 4242
    owner.process.name = "stuck-owner"
    owner.process.is_alive.return_value = True
    owner.bridge_ids = {"bridge-1"}
    owner.connection = mock.Mock()
    owner.connection_closed = False
    owner.rpc = mock.Mock(return_value=None)
    try:
        owner.close()
    except TimeoutError:
        pass
    else:
        raise AssertionError("owner close hid its failed post-KILL reap")
    if owner.bridge_ids != {"bridge-1"}:
        raise AssertionError("owner close forgot live bridge ownership")


def test_cleanup_exit_bound(smoke_path: Path) -> None:
    """Prove persistent child-cleanup failure cannot hang Python shutdown."""
    program = r"""
import importlib.util
from pathlib import Path
import os
import sys

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("cleanup_bound_smoke", path)
if spec is None or spec.loader is None:
    raise RuntimeError(f"cannot load {path}")
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


def stubborn_proxy(connection, _launcher):
    connection.send({"ok": True, "value": {"pid": os.getpid()}})
    while True:
        request = connection.recv()
        if request["operation"] != "shutdown":
            raise AssertionError(request)
        connection.send({"ok": False, "error": "persistent child cleanup failure"})


smoke.owner_proxy_main = stubborn_proxy
owner = smoke.OwnerProxy(Path("/unused"), "persistent-cleanup-owner")
owner.bridge_ids.add("bridge-1")
try:
    smoke.close_smoke_resources([], [owner])
except RuntimeError as error:
    if "persistent child cleanup failure" not in str(error):
        raise
else:
    raise AssertionError("persistent cleanup failure was not reported")
if owner.is_alive() or not owner.connection_closed:
    raise AssertionError("forced cleanup left the owner proxy live")
print("cleanup-exit-bound-ok")
"""
    completed = subprocess.run(
        [sys.executable, "-I", "-B", "-u", "-c", program, str(smoke_path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    if completed.returncode != 0 or completed.stdout.strip() != "cleanup-exit-bound-ok":
        raise AssertionError(
            f"bounded cleanup subprocess failed rc={completed.returncode}: "
            f"stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )


def wait_for_file(path: Path, process: subprocess.Popen[str]) -> None:
    """Wait for PATH while ensuring PROCESS has not exited early."""
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if path.exists():
            return
        returncode = process.poll()
        if returncode is not None:
            stdout, stderr = process.communicate()
            raise AssertionError(
                f"soak main exited {returncode} before readiness: "
                f"stdout={stdout!r} stderr={stderr!r}"
            )
        time.sleep(0.02)
    raise AssertionError(f"soak main did not reach signal point: {path}")


def wait_for_launcher_starts(
    path: Path, process: subprocess.Popen[str], expected: int
) -> None:
    """Wait for EXPECTED launcher start records without losing process custody."""
    deadline = time.monotonic() + 30
    observed: list[str] = []
    while time.monotonic() < deadline:
        if path.exists():
            observed = path.read_text(encoding="utf-8").splitlines()
            starts = [line for line in observed if line.startswith("start:")]
            if len(starts) >= expected:
                return
        returncode = process.poll()
        if returncode is not None:
            stdout, stderr = process.communicate()
            raise AssertionError(
                f"soak main exited {returncode} before {expected} launcher starts: "
                f"launcher={observed!r} stdout={stdout!r} stderr={stderr!r}"
            )
        time.sleep(0.02)
    raise AssertionError(
        f"launchers did not reach {expected} start records: "
        f"launcher={observed!r}"
    )


def write_fake_launcher(path: Path) -> None:
    """Create a real child process that exits only after bridge stdin closes."""
    path.write_text(
        f"""#!{sys.executable}
import os
from pathlib import Path
import signal
import sys
import time

signal.signal(signal.SIGTERM, lambda _signum, _frame: None)
log = Path(os.environ["ANVIL_SOAK_TEST_LAUNCHER_LOG"])
with log.open("a", encoding="utf-8") as stream:
    stream.write(f"start:{{os.getpid()}}\\n")
for _line in sys.stdin:
    pass
time.sleep(float(os.environ.get("ANVIL_SOAK_TEST_CLOSE_DELAY", "0")))
with log.open("a", encoding="utf-8") as stream:
    stream.write(f"exit:{{os.getpid()}}\\n")
""",
        encoding="utf-8",
    )
    path.chmod(0o700)


def process_exists(pid: int) -> bool:
    """Return whether PID still names a process."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def run_signal_scenario(
    soak: Path,
    smoke: Path,
    supervisor: Path,
    scenario: str,
    expected_normal: float,
    expected_dispatch: float,
) -> None:
    """Signal production main between constructors or with both bridges live."""
    with tempfile.TemporaryDirectory(prefix=f"anvil-soak-{scenario}-") as raw:
        root = Path(raw)
        home = root / "home"
        runtime = root / "runtime"
        state = root / "state"
        for directory in (home, runtime, state):
            directory.mkdir()
        launcher = root / "launcher"
        launcher_log = root / "launcher.log"
        ready = root / "ready"
        aggregate_log = root / "aggregate.log"
        write_fake_launcher(launcher)

        program = r"""
import importlib.util
import os
from pathlib import Path
import sys
import time


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


soak = load(sys.argv[1], "persistent_soak")
smoke = load(sys.argv[2], "agent_supervisor_smoke")
supervisor = sys.argv[3]
launcher = sys.argv[4]
scenario = sys.argv[5]
ready = Path(sys.argv[6])
aggregate_log = Path(sys.argv[7])
expected_normal = float(sys.argv[8])
expected_dispatch = float(sys.argv[9])

for name in (
    "ANVIL_SMOKE_WATCHDOG_NORMAL_SECONDS",
    "ANVIL_SMOKE_WATCHDOG_DISPATCH_SECONDS",
):
    os.environ.pop(name, None)
response_timeout = soak.configure_watchdog_environment()
if float(os.environ["ANVIL_SMOKE_WATCHDOG_NORMAL_SECONDS"]) != expected_normal:
    raise AssertionError("soak normal watchdog drifted from production")
if float(os.environ["ANVIL_SMOKE_WATCHDOG_DISPATCH_SECONDS"]) != expected_dispatch:
    raise AssertionError("soak dispatch watchdog drifted from production")
expected_response = min(expected_normal, expected_dispatch) + 30
if response_timeout != expected_response:
    raise AssertionError(f"unexpected recovery response timeout: {response_timeout}")

if scenario == "between":
    class ClosingBridge:
        def __init__(self, name, fail=False):
            self.name = name
            self.fail = fail

        def close(self):
            with aggregate_log.open("a", encoding="utf-8") as stream:
                stream.write(self.name + "\n")
            if self.fail:
                raise RuntimeError(self.name)

    try:
        soak.finalize_bridges(
            [ClosingBridge("first"), ClosingBridge("second", fail=True)],
            [],
        )
    except RuntimeError as error:
        if "cleanup failed: RuntimeError: second" not in str(error):
            raise AssertionError(f"unexpected cleanup error: {error!r}") from error
    else:
        raise AssertionError("cleanup error was not preserved")
    if aggregate_log.read_text(encoding="utf-8").splitlines() != [
        "second",
        "first",
    ]:
        raise AssertionError("finalize_bridges stopped after the first close error")

base_bridge = smoke.BridgeProcess


class InstrumentedBridge(base_bridge):
    constructed = 0

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.order = type(self).constructed
        type(self).constructed += 1
        with aggregate_log.open("a", encoding="utf-8") as stream:
            stream.write(f"constructed:{self.pid}\n")
        if scenario == "during" and self.order == 1:
            ready.write_text("inside second constructor\n", encoding="utf-8")
            while soak._PENDING_TERM_SIGNAL is None:
                time.sleep(0.02)

    def initialize(self):
        if scenario == "both" and self.order == 0:
            ready.write_text("both bridges live\n", encoding="utf-8")
            time.sleep(60)
        if scenario == "cleanup" and self.order == 0:
            raise RuntimeError("enter production finalizer")
        return super().initialize()

    def close(self):
        pid = self.pid
        with aggregate_log.open("a", encoding="utf-8") as stream:
            stream.write(f"close:{pid}\n")
        if scenario == "cleanup" and not ready.exists():
            ready.write_text("first cleanup in progress\n", encoding="utf-8")
        super().close()
        with aggregate_log.open("a", encoding="utf-8") as stream:
            stream.write(f"closed:{pid}\n")


smoke.BridgeProcess = InstrumentedBridge
original_construct = soak.construct_tracked_bridge
construct_calls = [0]


def instrumented_construct(bridges, bridge_type, *args):
    if scenario == "between" and construct_calls[0] == 1:
        ready.write_text("between constructors\n", encoding="utf-8")
        time.sleep(60)
    construct_calls[0] += 1
    return original_construct(bridges, bridge_type, *args)


soak.construct_tracked_bridge = instrumented_construct
soak.load_module = lambda _path, _name: smoke
soak.setup_fixtures = lambda _git, _direnv: {}
sys.argv = [
    str(soak.__file__),
    launcher,
    supervisor,
    str(smoke.__file__),
    launcher,
    launcher,
    launcher,
]
soak.main()
"""

        environment = os.environ.copy()
        environment.update(
            {
                "HOME": str(home),
                "ANVIL_EMACS_RUNTIME_ROOT": str(runtime),
                "ANVIL_EMACS_STATE_ROOT": str(state),
                "ANVIL_SOAK_TEST_LAUNCHER_LOG": str(launcher_log),
                "ANVIL_SOAK_TEST_CLOSE_DELAY": "60",
            }
        )
        process = subprocess.Popen(
            [
                sys.executable,
                "-I",
                "-B",
                "-u",
                "-c",
                program,
                str(soak),
                str(smoke),
                str(supervisor),
                str(launcher),
                scenario,
                str(ready),
                str(aggregate_log),
                f"{expected_normal:g}",
                f"{expected_dispatch:g}",
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            start_new_session=True,
        )
        try:
            wait_for_file(ready, process)
            wait_for_launcher_starts(
                launcher_log,
                process,
                1 if scenario == "between" else 2,
            )
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=50)
        except BaseException as error:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
            stdout, stderr = process.communicate(timeout=5)
            raise AssertionError(
                f"{scenario} harness failed: {error}; "
                f"stdout={stdout!r} stderr={stderr!r}"
            ) from error
        if process.returncode != 143:
            raise AssertionError(
                f"{scenario} SIGTERM exited {process.returncode}: "
                f"stdout={stdout!r} stderr={stderr!r}"
            )
        if "persistent latency summary: cycles=0" not in stdout:
            raise AssertionError(f"{scenario} partial summary missing: {stdout!r}")

        lines = launcher_log.read_text(encoding="utf-8").splitlines()
        starts = [
            int(line.split(":", 1)[1]) for line in lines if line.startswith("start:")
        ]
        expected = 1 if scenario == "between" else 2
        close_lines = aggregate_log.read_text(encoding="utf-8").splitlines()
        constructed = [
            int(line.split(":", 1)[1])
            for line in close_lines
            if line.startswith("constructed:")
        ]
        closes = [
            int(line.split(":", 1)[1])
            for line in close_lines
            if line.startswith("close:")
        ]
        closed = [
            int(line.split(":", 1)[1])
            for line in close_lines
            if line.startswith("closed:")
        ]
        expected_order = list(reversed(constructed))
        if (
            len(constructed) != expected
            or set(starts) != set(constructed)
            or closes != expected_order
            or closed != expected_order
        ):
            raise AssertionError(
                f"{scenario} bridges were not fully closed in reverse order: "
                f"launcher={lines!r} aggregate={close_lines!r}"
            )
        leaked = [pid for pid in constructed if process_exists(pid)]
        if leaked:
            raise AssertionError(f"{scenario} left launcher processes alive: {leaked}")


def main() -> None:
    if len(sys.argv) != 11:
        raise SystemExit(
            "usage: persistent-bridge-soak-test.py "
            "SOAK_SCRIPT SMOKE_SCRIPT SUPERVISOR_SCRIPT "
            "EXPECTED_NORMAL_SECONDS EXPECTED_DISPATCH_SECONDS "
            "CYCLES MARGIN_PERCENT OUTER_TIMEOUT_SECONDS KILL_AFTER_SECONDS "
            "HARD_CEILING_SECONDS"
        )
    soak = Path(sys.argv[1]).resolve()
    smoke = Path(sys.argv[2]).resolve()
    supervisor = Path(sys.argv[3]).resolve()
    expected_normal = float(sys.argv[4])
    expected_dispatch = float(sys.argv[5])
    cycles = int(sys.argv[6])
    margin_percent = int(sys.argv[7])
    outer_timeout = float(sys.argv[8])
    kill_after = float(sys.argv[9])
    hard_ceiling = float(sys.argv[10])
    test_timeout_budget(
        soak,
        expected_normal,
        expected_dispatch,
        cycles,
        margin_percent,
        outer_timeout,
        kill_after,
        hard_ceiling,
    )
    test_healthy_sibling_deadline_preserves_watchdog_window(soak)
    test_recovery_cycle_uses_remaining_watchdog_window(soak)
    test_phase_timeout_ownership(soak)
    test_response_reader(soak, smoke)
    test_request_preserves_absolute_deadline(smoke)
    test_async_poll_deadline(soak)
    test_async_marker_readiness(soak)
    test_recovered_async_requires_child(soak)
    test_cleanup_contract(smoke)
    test_cleanup_exit_bound(smoke)
    for scenario in ("between", "during", "both", "cleanup"):
        run_signal_scenario(
            soak,
            smoke,
            supervisor,
            scenario,
            expected_normal,
            expected_dispatch,
        )
    print("persistent-soak-policy-and-sigterm-ok")


if __name__ == "__main__":
    main()
