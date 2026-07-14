#!/usr/bin/env python3
"""Exercise production watchdog policy and SIGTERM cleanup for the soak."""

from __future__ import annotations

import importlib.util
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

    internal = (
        timeouts["setup"]
        + cycles * timeouts["cycle"]
        + timeouts["inventory"]
        + timeouts["bridge_cleanup"]
        + timeouts["post_cleanup"]
    )
    expected_outer = internal + math.ceil(internal * margin_percent / 100)
    if outer_timeout != expected_outer or outer_timeout > 2 * 60 * 60:
        raise AssertionError(
            f"outer timeout drifted: actual={outer_timeout:g} "
            f"expected={expected_outer:g} internal={internal:g}"
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
    finally:
        os.close(write_descriptor)
        stdout.close()
        stderr.close()


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
            time.sleep(2)

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
    if len(sys.argv) != 9:
        raise SystemExit(
            "usage: persistent-bridge-soak-test.py "
            "SOAK_SCRIPT SMOKE_SCRIPT SUPERVISOR_SCRIPT "
            "EXPECTED_NORMAL_SECONDS EXPECTED_DISPATCH_SECONDS "
            "CYCLES MARGIN_PERCENT OUTER_TIMEOUT_SECONDS"
        )
    soak = Path(sys.argv[1]).resolve()
    smoke = Path(sys.argv[2]).resolve()
    supervisor = Path(sys.argv[3]).resolve()
    expected_normal = float(sys.argv[4])
    expected_dispatch = float(sys.argv[5])
    cycles = int(sys.argv[6])
    margin_percent = int(sys.argv[7])
    outer_timeout = float(sys.argv[8])
    test_timeout_budget(
        soak,
        expected_normal,
        expected_dispatch,
        cycles,
        margin_percent,
        outer_timeout,
    )
    test_phase_timeout_ownership(soak)
    test_response_reader(soak, smoke)
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
