#!/usr/bin/env python3
"""Verify the cross-client timeout ladder and bounded stdio recovery."""

from __future__ import annotations

import ast
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import time


def percent_wire(payload: bytes) -> str:
    """Encode PAYLOAD for the fake-client environment."""
    return "".join(f"%{byte:02x}" for byte in payload)


def python_constants(path: Path, names: set[str]) -> dict[str, int]:
    """Read integer-valued top-level assignments from generated Python PATH."""
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    found: dict[str, int] = {}
    for node in tree.body:
        if not isinstance(node, ast.Assign) or len(node.targets) != 1:
            continue
        target = node.targets[0]
        if not isinstance(target, ast.Name) or target.id not in names:
            continue
        value = ast.literal_eval(node.value)
        if (
            isinstance(value, bool)
            or not isinstance(value, (int, float))
            or not float(value).is_integer()
        ):
            raise AssertionError(f"{target.id} is not integer-valued: {value!r}")
        found[target.id] = int(value)
    if set(found) != names:
        raise AssertionError(
            f"missing generated watchdog constants: {sorted(names - set(found))}"
        )
    return found


def shell_default(text: str, name: str) -> int:
    """Return NAME's integer ${NAME:-DEFAULT} assignment from shell TEXT."""
    match = re.search(
        rf"^{re.escape(name)}=\$\{{{re.escape(name)}:-([0-9]+)\}}$",
        text,
        re.MULTILINE,
    )
    if match is None:
        raise AssertionError(f"missing shell timeout default: {name}")
    return int(match.group(1))


def elisp_assignment(text: str, symbol: str) -> int:
    """Return SYMBOL's first integer assignment from generated Elisp TEXT."""
    match = re.search(rf"\b{re.escape(symbol)}\s+([0-9]+)\b", text)
    if match is None:
        raise AssertionError(f"missing Elisp timeout assignment: {symbol}")
    return int(match.group(1))


def cleaner_timeout(path: Path) -> int:
    """Return the fixed pre-entry direnv timeout from a generated wrapper."""
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    for node in tree.body:
        if (
            not isinstance(node, ast.Assign)
            or len(node.targets) != 1
            or not isinstance(node.targets[0], ast.Attribute)
            or not isinstance(node.targets[0].value, ast.Name)
            or node.targets[0].value.id != "sys"
            or node.targets[0].attr != "argv"
            or not isinstance(node.value, ast.List)
        ):
            continue
        elements = node.value.elts
        for index, element in enumerate(elements[:-1]):
            if (
                isinstance(element, ast.Constant)
                and element.value == "--timeout-seconds"
                and isinstance(elements[index + 1], ast.Constant)
            ):
                value = elements[index + 1].value
                if isinstance(value, str) and value.isdigit() and int(value) > 0:
                    return int(value)
    raise AssertionError("generated cleaner wrapper has no fixed timeout")


def policy_integer(policy: dict[str, object], name: str) -> int:
    """Return one positive integer timeout from POLICY."""
    value = policy.get(name)
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise AssertionError(f"invalid timeout policy value {name}={value!r}")
    return value


def assert_static_ordering(
    lock_launcher: Path,
    parent_guard: Path,
    clean_wrapper: Path,
    stdio: Path,
    init_file: Path,
    shell_filter: Path,
    environment_init: Path,
    default_nix: Path,
    policy: dict[str, object],
) -> None:
    """Bind generated artifacts to one ordered timeout policy."""
    keys = (
        "asyncSeconds",
        "bridgeDispatchSeconds",
        "bridgeReadinessSeconds",
        "bridgeStartupDispatchSeconds",
        "clientStartupSeconds",
        "clientToolSeconds",
        "cooperativeSyncSeconds",
        "direnvExportSeconds",
        "direnvStatusSeconds",
        "emacsclientKillSeconds",
        "emacsclientProbeSeconds",
        "frameReadSeconds",
        "hostShellSeconds",
        "parentGuardReadySeconds",
        "requestParseSeconds",
        "shellSyncSeconds",
        "supervisorReadySeconds",
        "watchdogDispatchSeconds",
        "watchdogHeartbeatSeconds",
        "watchdogPulseSeconds",
        "watchdogStartupSeconds",
    )
    values = {name: policy_integer(policy, name) for name in keys}

    watchdog = python_constants(
        lock_launcher,
        {
            "DEFAULT_STARTUP_SECONDS",
            "DEFAULT_NORMAL_SECONDS",
            "DEFAULT_DISPATCH_SECONDS",
            "DEFAULT_PULSE_SECONDS",
        },
    )
    guard = python_constants(parent_guard, {"READY_TIMEOUT_SECONDS"})
    cleaner_preentry_seconds = cleaner_timeout(clean_wrapper)
    if cleaner_preentry_seconds != values["direnvStatusSeconds"]:
        raise AssertionError(
            "cleaner pre-entry timeout drift: "
            f"policy={values['direnvStatusSeconds']} "
            f"wrapper={cleaner_preentry_seconds}"
        )
    stdio_text = stdio.read_text(encoding="utf-8")
    init_text = init_file.read_text(encoding="utf-8")
    shell_filter_text = shell_filter.read_text(encoding="utf-8")
    environment_init_text = environment_init.read_text(encoding="utf-8")
    default_nix_text = default_nix.read_text(encoding="utf-8")
    generation_lines = [
        line
        for line in default_nix_text.splitlines()
        if "dedicatedGeneration = builtins.hashString" in line
    ]
    if len(generation_lines) != 1:
        raise AssertionError("dedicated generation definition is ambiguous")
    for component in (
        "${dedicatedParentGuardLauncher}",
        "${dedicatedCleanEnvironment}",
        "${dedicatedDirenvNeutral}",
    ):
        if component not in generation_lines[0]:
            raise AssertionError(f"{component} is absent from dedicated generation")
    actual = {
        "asyncSeconds": elisp_assignment(init_text, "anvil-eval-async-timeout"),
        "bridgeDispatchSeconds": shell_default(
            stdio_text, "ANVIL_EMACSCLIENT_DISPATCH_TIMEOUT"
        ),
        "bridgeReadinessSeconds": shell_default(
            stdio_text, "ANVIL_EMACSCLIENT_READINESS_TIMEOUT"
        ),
        "bridgeStartupDispatchSeconds": shell_default(
            stdio_text, "ANVIL_EMACSCLIENT_STARTUP_DISPATCH_TIMEOUT"
        ),
        "cooperativeSyncSeconds": elisp_assignment(init_text, "anvil-eval-timeout"),
        "direnvExportSeconds": elisp_assignment(
            environment_init_text, "anvil-headless--direnv-export-timeout"
        ),
        "direnvStatusSeconds": elisp_assignment(
            environment_init_text, "anvil-headless--direnv-status-timeout"
        ),
        "hostShellSeconds": elisp_assignment(init_text, "anvil-host--default-timeout"),
        "emacsclientKillSeconds": shell_default(
            stdio_text, "ANVIL_EMACSCLIENT_KILL_AFTER_TIMEOUT"
        ),
        "emacsclientProbeSeconds": shell_default(
            stdio_text, "ANVIL_EMACSCLIENT_PROBE_TIMEOUT"
        ),
        "frameReadSeconds": shell_default(stdio_text, "ANVIL_MCP_FRAME_READ_TIMEOUT"),
        "parentGuardReadySeconds": guard["READY_TIMEOUT_SECONDS"],
        "requestParseSeconds": shell_default(
            stdio_text, "ANVIL_MCP_REQUEST_PARSE_TIMEOUT"
        ),
        "shellSyncSeconds": elisp_assignment(
            init_text, "anvil-shell-filter-max-sync-timeout"
        ),
        "watchdogDispatchSeconds": watchdog["DEFAULT_DISPATCH_SECONDS"],
        "watchdogHeartbeatSeconds": watchdog["DEFAULT_NORMAL_SECONDS"],
        "watchdogPulseSeconds": watchdog["DEFAULT_PULSE_SECONDS"],
        "watchdogStartupSeconds": watchdog["DEFAULT_STARTUP_SECONDS"],
    }
    for name, observed in actual.items():
        if observed != values[name]:
            raise AssertionError(
                f"generated timeout drift for {name}: "
                f"policy={values[name]} artifact={observed}"
            )
    if "ANVIL_EMACSCLIENT_TIMEOUT" in stdio_text:
        raise AssertionError("legacy overloaded emacsclient timeout remains")
    for fragment in (
        "IFS= read -r -d '' -n",
        'anvil_mcp_run_bounded "$frame_remaining" merge descriptor "" frame-body',
        "chunk = os.read(0, min(65536, remaining))",
        'local grace="${ANVIL_EMACSCLIENT_KILL_AFTER_TIMEOUT:-1}"',
        '-t "$remaining" ignored <&7',
        'ANVIL_HEADLESS_PARENT_PID="$ANVIL_MCP_RUNNER_PID"',
        "import os; print(os.getppid())",
        "set -m",
        'kill -TERM -- "-$child"',
        'kill -KILL -- "-$child"',
    ):
        if fragment not in stdio_text:
            raise AssertionError(f"Bash-owned loader timeout is missing {fragment!r}")
    if "timeout --help" in stdio_text or "timeout --kill-after" in stdio_text:
        raise AssertionError("stdio bridge still depends on a timeout executable")
    if "perl -e 'alarm" in stdio_text:
        raise AssertionError("stdio bridge retains a soft timeout fallback")
    for name in (
        "ANVIL_EMACSCLIENT_PROBE_TIMEOUT",
        "ANVIL_EMACSCLIENT_READINESS_TIMEOUT",
        "ANVIL_EMACSCLIENT_STARTUP_DISPATCH_TIMEOUT",
        "ANVIL_EMACSCLIENT_DISPATCH_TIMEOUT",
        "ANVIL_EMACSCLIENT_KILL_AFTER_TIMEOUT",
        "ANVIL_MCP_REQUEST_PARSE_TIMEOUT",
        "ANVIL_MCP_FRAME_READ_TIMEOUT",
    ):
        if f"anvil_mcp_validate_timeout {name}" not in stdio_text:
            raise AssertionError(f"runtime timeout is not clamped: {name}")
    direct_kill_waits = stdio_text.count(
        '-t "$ANVIL_EMACSCLIENT_KILL_AFTER_TIMEOUT"'
    )
    bounded_retirement_waits = stdio_text.count(
        "\tanvil_mcp_drain_runner_output\n"
    )
    if direct_kill_waits < 1 or bounded_retirement_waits < 2:
        raise AssertionError("bounded runner cleanup lacks policy-controlled waits")
    shell_default_timeout = elisp_assignment(
        shell_filter_text, "anvil-shell-filter-max-sync-timeout"
    )
    if shell_default_timeout != values["shellSyncSeconds"]:
        raise AssertionError(
            "packaged shell timeout cap drift: "
            f"policy={values['shellSyncSeconds']} artifact={shell_default_timeout}"
        )
    if "anvil-shell-filter--bounded-sync-timeout" not in shell_filter_text:
        raise AssertionError("packaged shell tools do not enforce the synchronous cap")

    if 3 * values["watchdogPulseSeconds"] > values["watchdogHeartbeatSeconds"]:
        raise AssertionError("heartbeat is shorter than three pulse intervals")
    if not (
        values["watchdogHeartbeatSeconds"]
        < values["cooperativeSyncSeconds"]
        < values["watchdogDispatchSeconds"]
        < values["bridgeDispatchSeconds"]
    ):
        raise AssertionError(f"invalid synchronous timeout ladder: {values}")
    direnv_host_envelope = (
        2 * values["direnvStatusSeconds"]
        + values["direnvExportSeconds"]
        + values["hostShellSeconds"]
    )
    if not (
        values["hostShellSeconds"] <= values["cooperativeSyncSeconds"]
        and direnv_host_envelope < values["watchdogDispatchSeconds"]
        and values["watchdogDispatchSeconds"] < values["bridgeDispatchSeconds"]
    ):
        raise AssertionError(
            "direnv preparation plus host shell can outlive an outer watchdog"
        )
    if not (
        values["hostShellSeconds"]
        == values["shellSyncSeconds"]
        == values["cooperativeSyncSeconds"]
    ):
        raise AssertionError("bounded synchronous tool budgets drifted apart")
    if not (
        values["shellSyncSeconds"] <= values["cooperativeSyncSeconds"]
        and values["shellSyncSeconds"] < values["watchdogDispatchSeconds"]
    ):
        raise AssertionError("synchronous shell cap can outlive the root watchdog")
    tool_envelope = (
        values["frameReadSeconds"]
        + 2 * values["emacsclientKillSeconds"]
        + values["requestParseSeconds"]
        + 2 * values["emacsclientKillSeconds"]
        + values["bridgeReadinessSeconds"]
        + 2 * values["emacsclientKillSeconds"]
        + values["bridgeDispatchSeconds"]
        + 2 * values["emacsclientKillSeconds"]
    )
    if tool_envelope >= values["clientToolSeconds"]:
        raise AssertionError(
            "parse, readiness, and dispatch can outlive the MCP client tool deadline"
        )
    startup_envelope = (
        values["direnvStatusSeconds"]
        + values["supervisorReadySeconds"]
        + 4 * values["parentGuardReadySeconds"]
        + values["frameReadSeconds"]
        + 2 * values["emacsclientKillSeconds"]
        + values["requestParseSeconds"]
        + 2 * values["emacsclientKillSeconds"]
        + values["bridgeReadinessSeconds"]
        + 2 * values["emacsclientKillSeconds"]
        + values["bridgeStartupDispatchSeconds"]
        + 2 * values["emacsclientKillSeconds"]
    )
    if startup_envelope >= values["clientStartupSeconds"]:
        raise AssertionError(
            "cleaner, supervisor, parse, readiness, and initialize dispatch can outlive "
            "the MCP client startup deadline"
        )
    if values["bridgeStartupDispatchSeconds"] >= values["cooperativeSyncSeconds"]:
        raise AssertionError("initialize dispatch uses the ordinary tool budget")
    if values["emacsclientProbeSeconds"] > values["bridgeReadinessSeconds"]:
        raise AssertionError("one readiness probe exceeds the readiness budget")
    if values["asyncSeconds"] <= values["clientToolSeconds"]:
        raise AssertionError(
            "async child budget must remain independent of the synchronous client call"
        )


def fake_emacsclient(path: Path) -> None:
    """Create a stateful fake client that can stall readiness and dispatch."""
    path.write_text(
        r"""#!__PYTHON__
import base64
import json
import os
from pathlib import Path
import re
import signal
import sys
import time


def bump(name):
    path = Path(os.environ[name])
    try:
        value = int(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        value = 0
    path.write_text(str(value + 1), encoding="utf-8")
    return value + 1


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
if expression == "t":
    attempt = bump("FAKE_PROBE_COUNT")
    failures = int(os.environ["FAKE_PROBE_FAILURES"])
    if attempt <= failures:
        print("can't find socket", file=sys.stderr)
        raise SystemExit(71)
    if attempt <= failures + int(os.environ["FAKE_PROBE_TIMEOUTS"]):
        time.sleep(float(os.environ["FAKE_STALL_SECONDS"]))
    print("t")
else:
    bump("FAKE_DISPATCH_COUNT")
    if os.environ.get("FAKE_TRAP_TERM") == "1":
        signal.signal(signal.SIGTERM, lambda _signum, _frame: None)
    time.sleep(float(os.environ["FAKE_DISPATCH_STALL_SECONDS"]))
    publish_response(expression)
""".replace("__PYTHON__", sys.executable),
        encoding="utf-8",
    )
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def read_count(path: Path) -> int:
    """Return a fake-client call count."""
    try:
        return int(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return 0


def run_bridge_case(
    stdio: Path,
    root: Path,
    *,
    request_id: int,
    probe_timeouts: int,
    readiness_timeout: int,
    dispatch_timeout: int,
    client_timeout: float,
    probe_failures: int = 0,
    startup_dispatch_timeout: int = 2,
    dispatch_stall: float = 4,
    method: str = "test",
    params: dict[str, object] | None = None,
    trap_term: bool = False,
    framed: bool = False,
) -> tuple[dict[str, object], float, int, int]:
    """Run one bounded request through the production bridge."""
    probe_count = root / f"probe-{request_id}.count"
    dispatch_count = root / f"dispatch-{request_id}.count"
    response = {"jsonrpc": "2.0", "id": request_id, "result": "unexpected"}
    environment = os.environ.copy()
    environment.update(
        {
            "PATH": f"{root / 'bin'}{os.pathsep}{environment['PATH']}",
            "FAKE_PROBE_COUNT": str(probe_count),
            "FAKE_DISPATCH_COUNT": str(dispatch_count),
            "FAKE_PROBE_TIMEOUTS": str(probe_timeouts),
            "FAKE_PROBE_FAILURES": str(probe_failures),
            "FAKE_STALL_SECONDS": "4",
            "FAKE_DISPATCH_STALL_SECONDS": str(dispatch_stall),
            "FAKE_TRAP_TERM": "1" if trap_term else "0",
            "FAKE_RESPONSE_WIRE": percent_wire(
                json.dumps(response, separators=(",", ":")).encode("utf-8")
            ),
            "ANVIL_EMACSCLIENT_PROBE_TIMEOUT": "1",
            "ANVIL_EMACSCLIENT_READINESS_TIMEOUT": str(readiness_timeout),
            "ANVIL_EMACSCLIENT_STARTUP_DISPATCH_TIMEOUT": str(startup_dispatch_timeout),
            "ANVIL_EMACSCLIENT_DISPATCH_TIMEOUT": str(dispatch_timeout),
            "ANVIL_EMACSCLIENT_KILL_AFTER_TIMEOUT": "1",
            "ANVIL_MCP_REQUEST_PARSE_TIMEOUT": "1",
            "ANVIL_EMACSCLIENT_RETRY_DELAY_MS": "0",
            "ANVIL_EMACSCLIENT_RETRY_MAX": "10",
        }
    )
    document: dict[str, object] = {
        "jsonrpc": "2.0",
        "id": request_id,
        "method": method,
    }
    if params is not None:
        document["params"] = params
    request = json.dumps(document, separators=(",", ":"))
    if framed:
        request_bytes = request.encode("utf-8")
        wire_input = f"Content-Length: {len(request_bytes)}\r\n\r\n{request}"
    else:
        wire_input = request + "\n"

    started = time.monotonic()
    completed = subprocess.run(
        [str(stdio), "--socket=/tmp/anvil-timeout-test", "--server-id=test"],
        input=wire_input,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
        timeout=client_timeout,
        check=False,
    )
    elapsed = time.monotonic() - started
    if completed.returncode != 0:
        raise AssertionError(
            f"bridge case {request_id} failed rc={completed.returncode}: "
            f"{completed.stderr}"
        )

    if framed:
        header, separator, body = completed.stdout.partition("\n\n")
        if not separator or not header.lower().startswith("content-length:"):
            raise AssertionError(
                f"bridge case {request_id} returned invalid framing: "
                f"{completed.stdout!r}"
            )
        length = int(header.split(":", 1)[1].strip())
        response_document = json.loads(body[:length])
    else:
        lines = [line for line in completed.stdout.splitlines() if line.strip()]
        if len(lines) != 1:
            raise AssertionError(
                f"bridge case {request_id} returned {len(lines)} replies: "
                f"{completed.stdout!r}"
            )
        response_document = json.loads(lines[0])
    return (
        response_document,
        elapsed,
        read_count(probe_count),
        read_count(dispatch_count),
    )


def assert_error(
    response: dict[str, object],
    *,
    phase: str,
    dispatched: bool,
) -> None:
    """Require a correlated at-most-once bridge error."""
    error = response.get("error")
    if not isinstance(error, dict):
        raise AssertionError(f"missing bridge error: {response}")
    data = error.get("data")
    if not isinstance(data, dict):
        raise AssertionError(f"missing bridge error data: {response}")
    expected = {
        "phase": phase,
        "dispatched": dispatched,
        "replayed": False,
    }
    for key, value in expected.items():
        actual = data.get(key)
        if type(actual) is not type(value) or actual != value:
            raise AssertionError(f"wrong {key} for {phase} timeout: {actual!r}")


def assert_dynamic_ordering(stdio: Path, policy: dict[str, object]) -> None:
    """Prove bounded recovery, hard kills, and startup-method selection."""
    with tempfile.TemporaryDirectory(prefix="anvil-timeout-ordering-") as raw:
        root = Path(raw)
        binary_dir = root / "bin"
        binary_dir.mkdir()
        fake_emacsclient(binary_dir / "emacsclient")

        response, elapsed, probes, dispatches = run_bridge_case(
            stdio,
            root,
            request_id=1,
            probe_timeouts=0,
            probe_failures=1,
            readiness_timeout=20,
            dispatch_timeout=2,
            client_timeout=30,
        )
        assert_error(response, phase="dispatch", dispatched=True)
        if elapsed >= 30:
            raise AssertionError(f"combined timeout outlived client: {elapsed:.3f}s")
        if probes < 2:
            raise AssertionError("readiness timeout was not retried")
        if dispatches != 1:
            raise AssertionError(f"ambiguous request was dispatched {dispatches} times")

        response, elapsed, _probes, dispatches = run_bridge_case(
            stdio,
            root,
            request_id=2,
            probe_timeouts=99,
            readiness_timeout=4,
            dispatch_timeout=2,
            client_timeout=10,
        )
        assert_error(response, phase="readiness", dispatched=False)
        if elapsed >= 10:
            raise AssertionError(f"readiness failure outlived client: {elapsed:.3f}s")
        if dispatches != 0:
            raise AssertionError("request dispatched after readiness exhaustion")

        response, elapsed, _probes, dispatches = run_bridge_case(
            stdio,
            root,
            request_id=3,
            probe_timeouts=0,
            readiness_timeout=4,
            dispatch_timeout=1,
            client_timeout=5,
            dispatch_stall=10,
            trap_term=True,
        )
        assert_error(response, phase="dispatch", dispatched=True)
        if elapsed >= 4:
            raise AssertionError(
                f"TERM-resistant emacsclient escaped hard kill: {elapsed:.3f}s"
            )
        if dispatches != 1:
            raise AssertionError(
                f"TERM-resistant request was dispatched {dispatches} times"
            )

        response, elapsed, _probes, dispatches = run_bridge_case(
            stdio,
            root,
            request_id=4,
            probe_timeouts=0,
            readiness_timeout=4,
            startup_dispatch_timeout=1,
            dispatch_timeout=3,
            client_timeout=6,
            dispatch_stall=2,
            method="initialize",
            framed=True,
        )
        assert_error(response, phase="dispatch", dispatched=True)
        if elapsed >= 4:
            raise AssertionError(
                f"framed initialize ignored its startup cap: {elapsed:.3f}s"
            )
        if dispatches != 1:
            raise AssertionError(f"framed initialize was dispatched {dispatches} times")

        response, elapsed, _probes, dispatches = run_bridge_case(
            stdio,
            root,
            request_id=5,
            probe_timeouts=0,
            readiness_timeout=4,
            startup_dispatch_timeout=1,
            dispatch_timeout=3,
            client_timeout=6,
            dispatch_stall=2,
            method="tools/call",
            params={"method": "initialize", "id": 99},
        )
        expected = {
            "jsonrpc": "2.0",
            "id": 5,
            "result": "unexpected",
        }
        if response != expected:
            raise AssertionError(
                f"nested initialize selected the startup cap: {response}"
            )
        if elapsed >= 4 or dispatches != 1:
            raise AssertionError(
                f"ordinary request used the wrong dispatch budget: "
                f"elapsed={elapsed:.3f}s dispatches={dispatches}"
            )

        valid_overrides = {
            "ANVIL_EMACSCLIENT_PROBE_TIMEOUT": "1",
            "ANVIL_EMACSCLIENT_READINESS_TIMEOUT": "4",
            "ANVIL_EMACSCLIENT_STARTUP_DISPATCH_TIMEOUT": "2",
            "ANVIL_EMACSCLIENT_DISPATCH_TIMEOUT": "3",
            "ANVIL_EMACSCLIENT_KILL_AFTER_TIMEOUT": "1",
            "ANVIL_MCP_REQUEST_PARSE_TIMEOUT": "1",
            "ANVIL_MCP_FRAME_READ_TIMEOUT": "1",
        }
        maxima = {
            "ANVIL_EMACSCLIENT_PROBE_TIMEOUT": policy_integer(
                policy, "emacsclientProbeSeconds"
            ),
            "ANVIL_EMACSCLIENT_READINESS_TIMEOUT": policy_integer(
                policy, "bridgeReadinessSeconds"
            ),
            "ANVIL_EMACSCLIENT_STARTUP_DISPATCH_TIMEOUT": policy_integer(
                policy, "bridgeStartupDispatchSeconds"
            ),
            "ANVIL_EMACSCLIENT_DISPATCH_TIMEOUT": policy_integer(
                policy, "bridgeDispatchSeconds"
            ),
            "ANVIL_EMACSCLIENT_KILL_AFTER_TIMEOUT": policy_integer(
                policy, "emacsclientKillSeconds"
            ),
            "ANVIL_MCP_REQUEST_PARSE_TIMEOUT": policy_integer(
                policy, "requestParseSeconds"
            ),
            "ANVIL_MCP_FRAME_READ_TIMEOUT": policy_integer(policy, "frameReadSeconds"),
        }
        request = '{"jsonrpc":"2.0","id":6,"method":"test"}\n'
        for name, maximum in maxima.items():
            environment = os.environ.copy()
            environment.update(valid_overrides)
            environment["PATH"] = f"{binary_dir}{os.pathsep}{environment['PATH']}"
            environment[name] = str(maximum + 1)
            completed = subprocess.run(
                [
                    str(stdio),
                    "--socket=/tmp/anvil-timeout-test",
                    "--server-id=test",
                ],
                input=request,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=environment,
                timeout=3,
                check=False,
            )
            if completed.returncode != 64 or name not in completed.stderr:
                raise AssertionError(
                    f"oversize {name} did not fail closed: "
                    f"rc={completed.returncode} stderr={completed.stderr!r}"
                )


def main() -> int:
    if len(sys.argv) != 10:
        raise SystemExit(
            "usage: timeout-ordering-test.py "
            "LOCK_LAUNCHER PARENT_GUARD CLEAN_WRAPPER ANVIL_STDIO INIT_FILE "
            "SHELL_FILTER ENVIRONMENT_INIT DEFAULT_NIX POLICY_JSON"
        )
    lock_launcher = Path(sys.argv[1]).resolve()
    parent_guard = Path(sys.argv[2]).resolve()
    clean_wrapper = Path(sys.argv[3]).resolve()
    stdio = Path(sys.argv[4]).resolve()
    init_file = Path(sys.argv[5]).resolve()
    shell_filter = Path(sys.argv[6]).resolve()
    environment_init = Path(sys.argv[7]).resolve()
    default_nix = Path(sys.argv[8]).resolve()
    policy = json.loads(sys.argv[9])
    if not isinstance(policy, dict):
        raise AssertionError("timeout policy must be a JSON object")

    assert_static_ordering(
        lock_launcher,
        parent_guard,
        clean_wrapper,
        stdio,
        init_file,
        shell_filter,
        environment_init,
        default_nix,
        policy,
    )
    print("timeout-ordering-static-ok", flush=True)
    assert_dynamic_ordering(stdio, policy)
    print("timeout-ordering-dynamic-ok", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
