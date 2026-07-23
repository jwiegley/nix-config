#!/usr/bin/env python3
"""Regress bridge-side freezes after a successful stateful dispatch."""

from __future__ import annotations

import base64
import errno
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import shlex
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time


READY_OBSERVER_TIMEOUT_SECONDS = 30.0
SUCCESS_REPLY_TIMEOUT_SECONDS = 30.0
DISPATCH_OBSERVER_TIMEOUT_SECONDS = 45.0
OWNER_DISPATCH_OBSERVER_TIMEOUT_SECONDS = 15.0
PREDISPATCH_PARSE_TIMEOUT_SECONDS = 10
PREDISPATCH_MARKER_TIMEOUT_SECONDS = 7
PREDISPATCH_REPLY_TIMEOUT_SECONDS = 12
BRIDGE_TERM_GRACE_SECONDS = 0.5
BRIDGE_REAP_TIMEOUT_SECONDS = 10.0
FRAME_EXIT_TIMEOUT_SECONDS = 5.0
HELPER_NAMES = (
    "cat",
    "rm",
    "sed",
    "tr",
    "grep",
    "date",
    "base64",
    "wc",
    "head",
    "python3",
    "sleep",
)


def json_bytes(value: object) -> bytes:
    """Serialize VALUE as compact UTF-8 JSON."""
    return json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")


def captured_generation_paths(
    expression_path: Path,
    sequence: int,
) -> tuple[Path, Path]:
    """Decode the exact request path and precommitted response stage."""
    expression = expression_path.read_text(encoding="utf-8")
    decoded: set[Path] = set()
    for payload in re.findall(
        r'base64-decode-string "([A-Za-z0-9+/=]+)"',
        expression,
    ):
        try:
            value = base64.b64decode(payload, validate=True).decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            continue
        if os.path.isabs(value):
            decoded.add(Path(value))
    request_name = f"request.{sequence}.json"
    stage_prefix = f".response-tmp.{sequence}."
    requests = [candidate for candidate in decoded if candidate.name == request_name]
    stages = [
        candidate for candidate in decoded if candidate.name.startswith(stage_prefix)
    ]
    if len(requests) != 1 or len(stages) != 1:
        raise AssertionError(
            f"captured expression lacks exact generation {sequence}: {decoded}"
        )
    return requests[0], stages[0]


def printf_wire(payload: bytes) -> str:
    """Encode PAYLOAD as process-free Bash printf escapes."""
    return "".join(f"\\x{byte:02x}" for byte in payload)


def read_count(path: Path) -> int:
    """Read an invocation counter, treating a missing file as zero."""
    try:
        return int(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return 0


def safe_text(path: Path, limit: int = 4000) -> str:
    """Read bounded regular-file diagnostics without opening a FIFO."""
    try:
        if not path.is_file():
            return f"<not a regular file: {path}>"
        return path.read_text(encoding="utf-8", errors="replace")[-limit:]
    except OSError as error:
        return f"<unavailable: {error}>"


def assert_no_stage_fd_inheritance(marker: dict[str, object], label: str) -> None:
    """Require one exact stage and prove the child did not inherit its FD."""
    if marker.get("stageCount") != 1 or marker.get("fd6MatchesStage") is not False:
        raise AssertionError(
            f"{label} inherited authenticated response custody: {marker}"
        )


def replace_with_fifo(path: Path) -> None:
    """Replace PATH with a FIFO without launching another executable."""
    try:
        path.unlink()
    except FileNotFoundError:
        pass
    os.mkfifo(path)


def make_executable(path: Path, source: str) -> None:
    """Write SOURCE to PATH and make it executable by the current user."""
    path.write_text(source, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def write_fake_emacsclient(path: Path, bash: str) -> None:
    """Create a loader-light readiness probe and controlled Python client."""
    python_source = r"""#!__PYTHON__
import base64
import os
from pathlib import Path
import re
import sys
import time

if os.environ.get("FAKE_PYTHON_START_DELAY"):
    time.sleep(float(os.environ["FAKE_PYTHON_START_DELAY"]))


def emit(descriptor, payload):
    os.write(descriptor, payload)


def bump(path):
    try:
        value = int(Path(path).read_text(encoding="ascii"))
    except FileNotFoundError:
        value = 0
    value += 1
    Path(path).write_text(str(value), encoding="ascii")
    return value


def decode_wire(text):
    if re.fullmatch(r"(?:\\x[0-9A-Fa-f]{2})*", text) is None:
        raise ValueError("invalid fake response wire")
    return bytes.fromhex(text.replace("\\x", ""))


if "ALTERNATE_EDITOR" in os.environ:
    emit(2, b"ALTERNATE_EDITOR leaked into emacsclient\n")
    raise SystemExit(78)

expression = sys.argv[-1]
if len(expression) > 100000:
    emit(2, b"emacsclient expression exceeds portable argument ceiling\n")
    raise SystemExit(75)

if expression == "t":
    bump(os.environ["FAKE_PROBE_COUNT"])
    emit(1, b"t\n")
elif expression == (
    '(if t (progn (test-init) "anvil-mcp-lifecycle-complete") '
    '"anvil-mcp-headless-not-ready")'
):
    bump(os.environ["FAKE_INIT_COUNT"])
    emit(1, b'"anvil-mcp-lifecycle-complete"\n')
elif expression == (
    '(if t (progn (test-stop) "anvil-mcp-lifecycle-complete") '
    '"anvil-mcp-headless-not-ready")'
):
    bump(os.environ["FAKE_STOP_COUNT"])
    emit(1, b'"anvil-mcp-lifecycle-complete"\n')
else:
    invocation = bump(os.environ["FAKE_DISPATCH_COUNT"])
    index = invocation - 1
    if index == 0 and os.environ.get("FAKE_CAPTURED_EXPRESSION"):
        Path(os.environ["FAKE_CAPTURED_EXPRESSION"]).write_text(
            expression,
            encoding="utf-8",
        )
    try:
        wire_text = os.environ[f"FAKE_RESPONSE_WIRE_{index}"]
    except KeyError:
        emit(2, b"unexpected duplicate dispatch\n")
        raise SystemExit(64)
    Path(os.environ["FAKE_DISPATCH_COMPLETE"]).write_text(
        str(invocation),
        encoding="ascii",
    )
    with open(os.environ["FAKE_DISPATCH_ACK_FIFO"], "rb") as stream:
        stream.read(1)

    decoded = []
    for payload in re.findall(
        r'base64-decode-string "([A-Za-z0-9+/=]+)"',
        expression,
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
        emit(2, f"missing unique response stage: {decoded}\n".encode())
        raise SystemExit(70)
    stage, sequence = stages[0]
    final = stage.parent / f"response.{sequence}.json"
    proof = stage.parent / f"proof.{sequence}.json"
    wire = decode_wire(wire_text)
    publication_mode = os.environ.get("FAKE_RESPONSE_PUBLICATION_MODE", "normal")
    if publication_mode == "competitor":
        competitor = decode_wire(os.environ["FAKE_COMPETITOR_WIRE"])
        with final.open("xb") as stream:
            stream.write(competitor)
        os.chmod(final, 0o600)
        os.link(final, proof)
        response_size = len(competitor)
    elif publication_mode == "normal":
        with stage.open("wb") as stream:
            stream.write(wire)
        os.link(stage, final)
        os.link(stage, proof)
        stage.unlink()
        response_size = len(wire)
    else:
        emit(2, f"unknown fake publication mode: {publication_mode}\n".encode())
        raise SystemExit(64)
    if os.environ.get("FAKE_RESPONSE_MARKER_SIZE"):
        response_size = int(os.environ["FAKE_RESPONSE_MARKER_SIZE"])

    marker = f"anvil-mcp-response-staged:{sequence}:{response_size}"
    if index == 1:
        emit(
            2,
            ("captured-stderr-" + os.environ["FAKE_CAPTURED_STDERR"]).encode(),
        )
    if index == 2:
        cut = len(marker) // 2
        emit(
            1,
            (
                '"' + marker[:cut] + "\r\n*ERROR*: Unknown message: "
                + marker[cut:] + '"\r\n'
            ).encode(),
        )
    else:
        emit(1, ('"' + marker + '"\n').encode())
""".replace("__PYTHON__", sys.executable)
    python_path = path.with_name(f"{path.name}-stateful.py")
    make_executable(python_path, python_source)
    source = r"""#!__BASH__
set -u
if [[ -n "${ALTERNATE_EDITOR+x}" ]]; then
    printf '%s\n' 'ALTERNATE_EDITOR leaked into emacsclient' >&2
    exit 78
fi
expression=
if (( $# > 0 )); then
    expression="${!#}"
fi
if [[ "$expression" == t ]]; then
    count=0
    if [[ -e "$FAKE_PROBE_COUNT" ]]; then
        IFS= read -r count < "$FAKE_PROBE_COUNT"
        case "$count" in
        ''|*[!0-9]*)
            printf '%s\n' 'invalid fake probe count' >&2
            exit 70
            ;;
        esac
    fi
    if ! printf '%s' "$((count + 1))" > "$FAKE_PROBE_COUNT"; then
        printf '%s\n' 'failed to record fake probe count' >&2
        exit 74
    fi
    printf 't\n'
    exit 0
fi
exec __PYTHON__ -I -B __PYTHON_PATH__ "$@"
"""
    source = source.replace("__BASH__", bash)
    source = source.replace("__PYTHON__", shlex.quote(sys.executable))
    source = source.replace("__PYTHON_PATH__", shlex.quote(str(python_path)))
    make_executable(path, source)


def run_fake_readiness_fast_path_regression(bash: str) -> None:
    """Readiness must not depend on starting the stateful Python fixture."""
    with tempfile.TemporaryDirectory(prefix="anvil-fake-readiness-") as raw:
        root = Path(raw)
        fake = root / "emacsclient"
        probe_count = root / "probe-count"
        write_fake_emacsclient(fake, bash)
        environment = os.environ.copy()
        environment.pop("ALTERNATE_EDITOR", None)
        environment["FAKE_PROBE_COUNT"] = str(probe_count)
        environment["FAKE_PYTHON_START_DELAY"] = "30"
        result = subprocess.run(
            [str(fake), "--eval", "t"],
            check=False,
            capture_output=True,
            env=environment,
            timeout=10,
        )
        if result.returncode != 0 or result.stdout != b"t\n" or result.stderr:
            raise AssertionError(
                f"fake readiness fast path failed rc={result.returncode}"
            )
        if probe_count.read_text(encoding="ascii") != "1":
            raise AssertionError("readiness did not record exactly one probe")

        environment["FAKE_PROBE_COUNT"] = str(root / "missing" / "probe-count")
        failed = subprocess.run(
            [str(fake), "--eval", "t"],
            check=False,
            capture_output=True,
            env=environment,
            timeout=10,
        )
        if failed.returncode == 0 or failed.stdout:
            raise AssertionError("readiness ignored a probe-count write failure")


def write_helper_wrapper(
    path: Path,
    bash: str,
    name: str,
    real_helper: str,
    block_timeout_seconds: int = 30,
) -> None:
    """Allow known next-request work, but block response-path recovery."""
    if block_timeout_seconds <= 0:
        raise ValueError("block_timeout_seconds must be positive")
    source = r"""#!__BASH__
set -u
if [[ -e "$FAKE_DISPATCH_COMPLETE" ]]; then
    # A pipelined request may begin only after the prior reply was emitted.
    # Permit its known replay-safe framing, metadata, and staging helpers.
    # Every helper started to recover the completed dispatch remains blocked.
    case "$*" in
    *"limit = int(sys.argv[1])"*|\
    *"remaining = int(sys.argv[1])"*|\
    *"document = json.loads"*|\
    *"def generation_file(name, prefix):"*|\
    *"pieces[0] == \"response\""*|\
    *"pieces[0] == \"request\""*)
        exec __REAL_HELPER__ "$@"
        ;;
    esac
    printf '{"pid":%s,"program":"__NAME__"}\n' "$$" \
        > "$FAKE_POSTDISPATCH_HELPER"
    # Preserve the blocking FIFO-open contract, but guarantee that a
    # hard-interrupted fixture cannot survive indefinitely.
    exec __PYTHON__ -c \
        'import os, signal, sys; signal.alarm(__BLOCK_TIMEOUT_SECONDS__); os.read(os.open(sys.argv[1], os.O_RDONLY), 1)' \
        "$FAKE_HELPER_BLOCK_FIFO"
fi
exec __REAL_HELPER__ "$@"
"""
    source = source.replace("__BASH__", bash)
    source = source.replace("__PYTHON__", shlex.quote(sys.executable))
    source = source.replace("__BLOCK_TIMEOUT_SECONDS__", str(block_timeout_seconds))
    source = source.replace("__NAME__", name)
    source = source.replace("__REAL_HELPER__", shlex.quote(real_helper))
    make_executable(path, source)


def run_helper_self_expiry(
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """A blocked post-dispatch fixture self-terminates after its deadline."""
    with tempfile.TemporaryDirectory(prefix="anvil-helper-expiry-") as raw:
        root = Path(raw)
        wrapper = root / "rm"
        dispatch_complete = root / "dispatch-complete"
        helper_marker = root / "postdispatch-helper"
        helper_fifo = root / "helper-block.fifo"
        dispatch_complete.touch()
        os.mkfifo(helper_fifo)
        write_helper_wrapper(
            wrapper,
            bash,
            "rm",
            real_helpers["rm"],
            block_timeout_seconds=1,
        )
        environment = os.environ.copy()
        environment.update(
            {
                "FAKE_DISPATCH_COMPLETE": str(dispatch_complete),
                "FAKE_POSTDISPATCH_HELPER": str(helper_marker),
                "FAKE_HELPER_BLOCK_FIFO": str(helper_fifo),
            }
        )
        process = subprocess.Popen(
            [bash, str(wrapper), "-f", "--", str(root / "unused")],
            env=environment,
        )
        try:
            if not wait_until(helper_marker.is_file, 2):
                raise AssertionError("bounded helper did not reach its wait")
            marker = json.loads(helper_marker.read_text(encoding="utf-8"))
            if int(marker["pid"]) != process.pid:
                raise AssertionError("bounded helper changed process identity")
            process.wait(timeout=3)
            if process.returncode != -signal.SIGALRM:
                raise AssertionError(
                    f"bounded helper exited with {process.returncode}, not SIGALRM"
                )
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)


def write_blocking_predispatch_wrapper(
    path: Path,
    bash: str,
    name: str,
    real_helper: str,
) -> None:
    """Freeze the metadata loader while allowing binary-safe wire readers."""
    source = r"""#!__BASH__
set -u
case "$*" in
*"limit = int(sys.argv[1])"*|*"remaining = int(sys.argv[1])"*)
    exec __REAL_HELPER__ "$@"
    ;;
esac
printf '{"pid":%s,"program":"__NAME__"}\n' "$$" \
    > "$FAKE_PREDISPATCH_MARKER"
IFS= read -r _ < "$FAKE_PREDISPATCH_BLOCK_FIFO"
exit 125
"""
    source = source.replace("__BASH__", bash)
    source = source.replace("__NAME__", name)
    source = source.replace("__REAL_HELPER__", shlex.quote(real_helper))
    make_executable(path, source)


def write_delayed_python_wrapper(
    path: Path,
    bash: str,
    real_python: str,
    real_sleep: str,
) -> None:
    """Delay parser startup past the former default, then exec Python."""
    source = r"""#!__BASH__
set -u
case "$*" in
*"limit = int(sys.argv[1])"*|*"remaining = int(sys.argv[1])"*)
    exec __PYTHON__ "$@"
    ;;
esac
__SLEEP__ 3
exec __PYTHON__ "$@"
"""
    source = source.replace("__BASH__", bash)
    source = source.replace("__SLEEP__", shlex.quote(real_sleep))
    source = source.replace("__PYTHON__", shlex.quote(real_python))
    make_executable(path, source)


def write_response_prepare_pause_wrapper(
    path: Path,
    real_python: str,
) -> None:
    """Pause response preparation only after its stage inode is owned."""
    source = f"""#!{real_python}
import os
import sys

real_python = {real_python!r}
arguments = sys.argv[1:]
try:
    script_index = arguments.index("-c") + 1
except ValueError:
    script_index = -1
if script_index > 0 and script_index < len(arguments):
    script = arguments[script_index]
    if (
        "info = os.fstat(0)" in script
        and "anvil-response-fd-authenticated" in script
        and os.environ.get("FAKE_RESPONSE_VALIDATE_MODE") == "status-124"
    ):
        marker = os.environ["FAKE_RESPONSE_VALIDATE_MARKER"]
        with open(marker, "w", encoding="ascii") as stream:
            stream.write(str(os.getpid()))
        print("malformed-fd-auth")
        raise SystemExit(124)
    if (
        'pieces[0] == "response"' in script
        and "response staging interrupted" in script
    ):
        mode = os.environ.get("FAKE_RESPONSE_PREPARE_MODE")
        if mode == "pause":
            needle = "    without_term(create_stage)\\n"
            replacement = (
                needle
                + "    marker = os.environ['FAKE_RESPONSE_PREPARE_MARKER']\\n"
                + "    with open(marker, 'w', encoding='ascii') as stream:\\n"
                + "        stream.write(str(os.getpid()))\\n"
                + "    import time\\n"
                + "    time.sleep(60)\\n"
            )
        elif mode == "link-fail":
            needle = "        os.link(path, probe_path)\\n"
            replacement = (
                "        marker = os.environ['FAKE_RESPONSE_LINK_MARKER']\\n"
                + "        with open(marker, 'w', encoding='ascii') as stream:\\n"
                + "            stream.write(str(os.getpid()))\\n"
                + "        raise OSError(95, 'hard links unavailable')\\n"
            )
        else:
            needle = ""
            replacement = ""
        if needle:
            if script.count(needle) != 1:
                raise SystemExit("response-preparation injection point drifted")
            arguments[script_index] = script.replace(needle, replacement, 1)
os.execv(real_python, [real_python, *arguments])
"""
    make_executable(path, source)


def write_owner_blocking_emacsclient(path: Path, _bash: str) -> None:
    """Create a child-free client that records FD custody, then blocks."""
    source = r"""#!__PYTHON__
import base64
import json
import os
from pathlib import Path
import re
import sys


expression = sys.argv[-1]
if expression == "t":
    os.write(1, b"t\n")
    raise SystemExit(0)

count_path = Path(os.environ["FAKE_OWNER_DISPATCH_COUNT"])
try:
    count = int(count_path.read_text(encoding="ascii"))
except FileNotFoundError:
    count = 0
count += 1
count_path.write_text(str(count), encoding="ascii")

stages = []
for payload in re.findall(
    r'base64-decode-string "([A-Za-z0-9+/=]+)"',
    expression,
):
    try:
        value = base64.b64decode(payload, validate=True).decode("utf-8")
    except (ValueError, UnicodeDecodeError):
        continue
    candidate = Path(value)
    if (
        os.path.isabs(value)
        and re.fullmatch(r"\.response-tmp\.[0-9]+\..+", candidate.name)
    ):
        stages.append(candidate)

try:
    held = os.fstat(6)
except OSError:
    fd6_open = False
    fd6_matches_stage = False
else:
    fd6_open = True
    fd6_matches_stage = False
    for stage in stages:
        try:
            info = stage.stat()
        except FileNotFoundError:
            continue
        if held.st_dev == info.st_dev and held.st_ino == info.st_ino:
            fd6_matches_stage = True

marker = {
    "pid": os.getpid(),
    "parent": os.getppid(),
    "fd6Open": fd6_open,
    "fd6MatchesStage": fd6_matches_stage,
    "stageCount": len(stages),
}
Path(os.environ["FAKE_OWNER_CHILD_MARKER"]).write_text(
    json.dumps(marker, separators=(",", ":")),
    encoding="ascii",
)
with open(os.environ["FAKE_OWNER_BLOCK_FIFO"], "rb") as stream:
    stream.read(1)
raise SystemExit(125)
""".replace("__PYTHON__", sys.executable)
    make_executable(path, source)


def write_blocking_guard_python(path: Path, bash: str) -> None:
    """Create a guard interpreter that freezes before Python can load."""
    source = r"""#!__BASH__
set -u
printf '%s\n' "$$" > "$FAKE_GUARD_LOADER_MARKER"
IFS= read -r _ < "$FAKE_GUARD_LOADER_FIFO"
exit 125
""".replace("__BASH__", bash)
    make_executable(path, source)


def write_test_parent_guard(path: Path) -> None:
    """Create a portable guard implementing the packaged numeric-owner contract."""
    source = r"""import os
import select
import signal
import sys
import time


def kill_live_target(target):
    try:
        group = os.getpgid(target)
    except OSError:
        return
    try:
        if group == target:
            os.killpg(target, signal.SIGKILL)
        else:
            os.kill(target, signal.SIGKILL)
    except OSError:
        pass


def watch_processes(root, target, bridge):
    if sys.platform.startswith("linux"):
        root_fd = os.pidfd_open(root, 0)
        target_fd = os.pidfd_open(target, 0)
        bridge_fd = os.pidfd_open(bridge, 0)
        poller = select.poll()
        poller.register(root_fd, select.POLLIN)
        poller.register(target_fd, select.POLLIN)
        poller.register(bridge_fd, select.POLLIN)
        while True:
            events = poller.poll()
            if any(fd == target_fd for fd, _event in events):
                try:
                    os.killpg(target, signal.SIGKILL)
                except OSError:
                    pass
                return
            if any(fd == root_fd for fd, _event in events):
                kill_live_target(target)
                return
            if any(fd == bridge_fd for fd, _event in events):
                kill_live_target(target)
                return
    if sys.platform == "darwin":
        queue = select.kqueue()
        flags = select.KQ_EV_ADD | select.KQ_EV_ENABLE
        changes = [
            select.kevent(
                root,
                filter=select.KQ_FILTER_PROC,
                flags=flags,
                fflags=select.KQ_NOTE_EXIT,
            ),
            select.kevent(
                target,
                filter=select.KQ_FILTER_PROC,
                flags=flags,
                fflags=select.KQ_NOTE_EXIT,
            ),
            select.kevent(
                bridge,
                filter=select.KQ_FILTER_PROC,
                flags=flags,
                fflags=select.KQ_NOTE_EXIT,
            ),
        ]
        queue.control(changes, 0, 0)
        while True:
            events = queue.control(None, 3, None)
            if any(event.ident == target for event in events):
                try:
                    os.killpg(target, signal.SIGKILL)
                except OSError:
                    pass
                return
            if any(event.ident == root for event in events):
                kill_live_target(target)
                return
            if any(event.ident == bridge for event in events):
                kill_live_target(target)
                return
    raise RuntimeError(f"unsupported platform: {sys.platform}")


if len(sys.argv) < 3 or sys.argv[1] != "group":
    raise SystemExit(70)
raw_parent = os.environ.pop("ANVIL_HEADLESS_PARENT_PID", "")
raw_bridge = os.environ.pop("ANVIL_HEADLESS_BRIDGE_PID", "")
if (
    not raw_parent.isascii()
    or not raw_parent.isdecimal()
    or not raw_bridge.isascii()
    or not raw_bridge.isdecimal()
):
    raise SystemExit(70)
root_pid = int(raw_parent)
bridge_pid = int(raw_bridge)
if root_pid <= 1 or bridge_pid <= 1 or os.getppid() != root_pid:
    raise SystemExit(70)

target_pid = os.getpid()
ready_read, ready_write = os.pipe()
guard_pid = os.fork()
if guard_pid == 0:
    os.close(ready_read)
    try:
        os.setpgid(0, 0)
        null_fd = os.open(os.devnull, os.O_RDWR)
        for descriptor in (0, 1, 2):
            os.dup2(null_fd, descriptor)
        if null_fd > 2 and null_fd != ready_write:
            os.close(null_fd)
        os.write(ready_write, b"R")
        os.close(ready_write)
        watch_processes(root_pid, target_pid, bridge_pid)
        os._exit(0)
    except BaseException:
        kill_live_target(target_pid)
        os._exit(70)

os.close(ready_write)
if os.read(ready_read, 1) != b"R":
    raise SystemExit(70)
os.close(ready_read)
if os.getppid() != root_pid:
    os.kill(target_pid, signal.SIGKILL)
os.setpgid(0, 0)
if os.getppid() != root_pid:
    os.kill(target_pid, signal.SIGKILL)
os.execvpe(sys.argv[2], sys.argv[2:], os.environ)
"""
    path.write_text(source, encoding="utf-8")


def prepare_parent_guard(
    root: Path,
    parent_guard: Path | None,
    parent_guard_python: str | None,
) -> tuple[Path, str]:
    """Return a production guard or a portable test implementation."""
    if parent_guard is not None:
        if parent_guard_python is None:
            raise AssertionError("parent guard Python is missing")
        return parent_guard, parent_guard_python
    generated = root / "test-parent-guard.py"
    write_test_parent_guard(generated)
    return generated, sys.executable


def build_fixture(
    root: Path,
    real_helpers: dict[str, str],
    wires: list[str],
    bash: str,
) -> tuple[dict[str, str], dict[str, Path]]:
    """Create fake clients/helpers and return their environment and paths."""
    binary_dir = root / "bin"
    temp_dir = root / "tmp"
    binary_dir.mkdir()
    temp_dir.mkdir()

    paths = {
        "binary": binary_dir,
        "temp": temp_dir,
        "dispatch_complete": root / "dispatch-complete",
        "dispatch_ack_fifo": root / "dispatch-ack.fifo",
        "helper_block_fifo": root / "helper-block.fifo",
        "predispatch_block_fifo": root / "predispatch-block.fifo",
        "predispatch_marker": root / "predispatch-helper",
        "helper_marker": root / "postdispatch-helper",
        "dispatch_count": root / "dispatch-count",
        "captured_expression": root / "captured-expression.el",
        "probe_count": root / "probe-count",
        "init_count": root / "init-count",
        "stop_count": root / "stop-count",
        "debug_log": root / "stdio.log",
        "bridge_stderr": root / "bridge.stderr",
    }
    os.mkfifo(paths["dispatch_ack_fifo"])
    os.mkfifo(paths["helper_block_fifo"])
    os.mkfifo(paths["predispatch_block_fifo"])
    write_fake_emacsclient(binary_dir / "emacsclient", bash)
    for name, target in real_helpers.items():
        write_helper_wrapper(binary_dir / name, bash, name, target)

    environment = os.environ.copy()
    environment.update(
        {
            "PATH": f"{binary_dir}{os.pathsep}{environment['PATH']}",
            "TMPDIR": str(temp_dir),
            "FAKE_DISPATCH_COMPLETE": str(paths["dispatch_complete"]),
            "FAKE_DISPATCH_ACK_FIFO": str(paths["dispatch_ack_fifo"]),
            "FAKE_HELPER_BLOCK_FIFO": str(paths["helper_block_fifo"]),
            "FAKE_PREDISPATCH_BLOCK_FIFO": str(paths["predispatch_block_fifo"]),
            "FAKE_PREDISPATCH_MARKER": str(paths["predispatch_marker"]),
            "FAKE_POSTDISPATCH_HELPER": str(paths["helper_marker"]),
            "FAKE_DISPATCH_COUNT": str(paths["dispatch_count"]),
            "FAKE_CAPTURED_EXPRESSION": str(paths["captured_expression"]),
            "FAKE_PROBE_COUNT": str(paths["probe_count"]),
            "FAKE_INIT_COUNT": str(paths["init_count"]),
            "FAKE_STOP_COUNT": str(paths["stop_count"]),
            "FAKE_RESPONSE_WIRE_0": wires[0],
            "FAKE_RESPONSE_WIRE_1": wires[1] if len(wires) > 1 else "",
            "FAKE_RESPONSE_WIRE_2": wires[2] if len(wires) > 2 else "",
            "FAKE_CAPTURED_STDERR": "x" * 8192,
            "EMACS_MCP_DEBUG_LOG": str(paths["debug_log"]),
            "ANVIL_MCP_READINESS_MODE": "emacs",
            "ANVIL_EMACSCLIENT_PROBE_TIMEOUT": "5",
            "ANVIL_EMACSCLIENT_READINESS_TIMEOUT": "10",
            "ANVIL_EMACSCLIENT_STARTUP_DISPATCH_TIMEOUT": "10",
            "ANVIL_EMACSCLIENT_DISPATCH_TIMEOUT": "10",
            "ANVIL_EMACSCLIENT_KILL_AFTER_TIMEOUT": "1",
            "ANVIL_MCP_REQUEST_PARSE_TIMEOUT": "10",
            "ANVIL_MCP_FRAME_READ_TIMEOUT": "10",
            "ANVIL_EMACSCLIENT_RETRY_MAX": "1",
            "ANVIL_EMACSCLIENT_RETRY_DELAY_MS": "0",
            "ALTERNATE_EDITOR": str(root / "must-not-run"),
        }
    )
    return environment, paths


class BinaryReader:
    """Read line and framed replies from one unbuffered bridge pipe."""

    def __init__(
        self,
        process: subprocess.Popen[bytes],
        debug_log: Path,
        bridge_stderr: Path,
        helper_marker: Path,
        dispatch_count: Path,
    ) -> None:
        self.process = process
        self.debug_log = debug_log
        self.bridge_stderr = bridge_stderr
        self.helper_marker = helper_marker
        self.dispatch_count = dispatch_count
        self.buffer = bytearray()
        self.selector = selectors.DefaultSelector()
        if process.stdout is None:
            raise AssertionError("bridge stdout is unavailable")
        self.selector.register(process.stdout, selectors.EVENT_READ)

    def diagnostics(self) -> str:
        """Return bounded diagnostics for a failed reply."""
        helper = safe_text(self.helper_marker)
        return (
            f"pid={self.process.pid} rc={self.process.poll()} "
            f"dispatches={read_count(self.dispatch_count)} "
            f"helper={helper} "
            f"debug={safe_text(self.debug_log)} "
            f"stderr={safe_text(self.bridge_stderr)}"
        )

    def fill(self, deadline: float) -> None:
        """Read another chunk before DEADLINE."""
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not self.selector.select(remaining):
            raise AssertionError(f"bridge reply timed out: {self.diagnostics()}")
        if self.process.stdout is None:
            raise AssertionError("bridge stdout disappeared")
        chunk = os.read(self.process.stdout.fileno(), 64 * 1024)
        if not chunk:
            raise AssertionError(
                f"bridge closed stdout before reply: {self.diagnostics()}"
            )
        self.buffer.extend(chunk)

    def line(self, deadline: float) -> bytes:
        """Read one CRLF/LF-terminated line before DEADLINE."""
        while True:
            position = self.buffer.find(b"\n")
            if position >= 0:
                value = bytes(self.buffer[:position])
                del self.buffer[: position + 1]
                return value[:-1] if value.endswith(b"\r") else value
            self.fill(deadline)

    def exact(self, count: int, deadline: float) -> bytes:
        """Read exactly COUNT bytes before DEADLINE."""
        while len(self.buffer) < count:
            self.fill(deadline)
        value = bytes(self.buffer[:count])
        del self.buffer[:count]
        return value

    def close(self) -> None:
        """Close the selector without closing the process pipe."""
        self.selector.close()


def read_reply(
    reader: BinaryReader,
    expected: dict[str, object],
    *,
    framed: bool,
    timeout_seconds: float = SUCCESS_REPLY_TIMEOUT_SECONDS,
) -> None:
    """Read and validate one line or framed response."""
    deadline = time.monotonic() + timeout_seconds
    first = reader.line(deadline)
    declared: int | None
    if framed:
        if not first.lower().startswith(b"content-length:"):
            raise AssertionError(f"missing response frame: {first!r}")
        declared = int(first.split(b":", 1)[1].strip())
        if reader.line(deadline) != b"":
            raise AssertionError("missing blank response-frame line")
        body = reader.exact(declared, deadline)
    else:
        declared = None
        body = first

    wanted = json_bytes(expected)
    if body != wanted:
        raise AssertionError(f"response bytes differ: got={body!r} wanted={wanted!r}")
    if json.loads(body) != expected:
        raise AssertionError("response JSON differs")
    if framed and declared != len(wanted):
        raise AssertionError(
            f"Content-Length counted characters, not bytes: {declared} != {len(wanted)}"
        )


def send(
    process: subprocess.Popen[bytes],
    document: dict[str, object],
    *,
    framed: bool = False,
    content_length_header: str = "Content-Length",
) -> None:
    """Send one JSON-RPC document to PROCESS."""
    if process.stdin is None:
        raise AssertionError("bridge stdin is unavailable")
    body = json_bytes(document)
    if framed:
        process.stdin.write(
            f"{content_length_header}: {len(body)}\r\n\r\n".encode("ascii") + body
        )
    else:
        process.stdin.write(body + b"\n")
    process.stdin.flush()


def start_bridge(
    bash: str,
    bridge: Path,
    environment: dict[str, str],
    bridge_stderr: Path,
    *arguments: str,
    initial_input: bytes | None = None,
) -> subprocess.Popen[bytes]:
    """Start one bridge in an isolated process group."""
    options: dict[str, object] = {}
    if os.name == "posix":
        options["start_new_session"] = True
    stderr_handle = bridge_stderr.open("wb")
    input_handle = None
    try:
        if initial_input is not None:
            input_handle = tempfile.TemporaryFile()
            input_handle.write(initial_input)
            input_handle.seek(0)
        return subprocess.Popen(
            [bash, str(bridge), *arguments],
            stdin=input_handle if input_handle is not None else subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=stderr_handle,
            bufsize=0,
            env=environment,
            **options,
        )
    finally:
        if input_handle is not None:
            input_handle.close()
        stderr_handle.close()


def process_alive(pid: int) -> bool:
    """Return whether PID still exists."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def process_group_alive(pgid: int) -> bool:
    """Return whether POSIX process group PGID still exists."""
    if os.name != "posix":
        return False
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def wait_for_bridge_reap(
    process: subprocess.Popen[bytes],
    timeout: float = BRIDGE_REAP_TIMEOUT_SECONDS,
) -> None:
    """Wait boundedly for a bridge leader to become observable."""
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise AssertionError(
            f"bridge leader {process.pid} was not reaped within {timeout:.1f}s"
        ) from error


def extract_inline_python(stdio: Path, function_name: str) -> str:
    """Extract one exact Python -c body from a bridge shell function."""
    source = stdio.read_text(encoding="utf-8")
    function_start = source.index(f"{function_name}() {{")
    function_end = source.index(
        '\n\treturn "$ANVIL_MCP_RUN_STATUS"\n}\n',
        function_start,
    )
    block = source[function_start:function_end]
    command_marker = "-I -S -c '\n"
    script_start = block.index(command_marker) + len(command_marker)
    script_end = block.rindex("\n' ")
    return block[script_start:script_end]


def inject_cleanup_barrier(script: str) -> str:
    """Pause the first cleanup snapshot so the test can publish concurrently."""
    needle = "        names = os.listdir(directory)\n"
    replacement = (
        needle
        + "        race_marker = os.environ.get("
        + "'ANVIL_CLEANUP_RACE_MARKER')\n"
        + "        if race_marker and not os.path.exists(race_marker):\n"
        + "            with open(race_marker, 'w', encoding='ascii') as stream:\n"
        + "                stream.write(str(os.getpid()))\n"
        + "            race_release = os.environ['ANVIL_CLEANUP_RACE_RELEASE']\n"
        + "            while not os.path.exists(race_release):\n"
        + "                __import__('time').sleep(0.001)\n"
    )
    if script.count(needle) != 1:
        raise AssertionError("cleanup snapshot injection point drifted")
    return script.replace(needle, replacement, 1)


def run_cleanup_race_program(
    script: str,
    arguments: list[str],
    input_bytes: bytes,
    marker: Path,
    release: Path,
    publish: object,
) -> bytes:
    """Run SCRIPT through one deterministic snapshot/publication race."""
    environment = os.environ.copy()
    environment["ANVIL_CLEANUP_RACE_MARKER"] = str(marker)
    environment["ANVIL_CLEANUP_RACE_RELEASE"] = str(release)
    process = subprocess.Popen(
        [sys.executable, "-I", "-S", "-c", script, *arguments],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
    )
    try:
        deadline = time.monotonic() + 5
        while not marker.is_file():
            if process.poll() is not None:
                stdout, stderr = process.communicate()
                raise AssertionError(
                    f"cleanup race exited before barrier rc={process.returncode}: "
                    f"{stdout!r} {stderr!r}"
                )
            if time.monotonic() >= deadline:
                raise AssertionError("cleanup race did not reach snapshot barrier")
            time.sleep(0.01)
        publish()  # type: ignore[operator]
        release.touch()
        stdout, stderr = process.communicate(input=input_bytes, timeout=10)
        if process.returncode != 0:
            raise AssertionError(
                f"cleanup race failed rc={process.returncode}: {stderr!r}"
            )
        return stdout
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=2)


def run_cleanup_rescan_regression(stdio: Path) -> None:
    """Concurrent publication cannot survive metadata or EXIT cleanup."""
    metadata_script = inject_cleanup_barrier(
        extract_inline_python(stdio, "anvil_mcp_request_metadata")
    )
    exit_script = inject_cleanup_barrier(
        extract_inline_python(stdio, "anvil_mcp_cleanup_all_staged")
    )
    with tempfile.TemporaryDirectory(prefix="anvil-cleanup-race-") as raw:
        root = Path(raw).resolve()

        metadata_directory = root / "metadata"
        metadata_directory.mkdir(mode=0o700)
        metadata_temp = metadata_directory / ".response-tmp.1.race"
        metadata_temp.write_bytes(b"sensitive")
        metadata_temp.chmod(0o600)
        metadata_final = metadata_directory / "response.1.json"
        metadata_proof = metadata_directory / "proof.1.json"
        metadata_marker = root / "metadata-marker"
        metadata_release = root / "metadata-release"
        request = json_bytes({"jsonrpc": "2.0", "id": 301, "method": "test"})

        def publish_metadata() -> None:
            os.link(metadata_temp, metadata_final)
            os.link(metadata_temp, metadata_proof)
            metadata_temp.unlink()

        metadata_output = run_cleanup_race_program(
            metadata_script,
            ["16777216", "16384", str(metadata_directory)],
            request,
            metadata_marker,
            metadata_release,
            publish_metadata,
        )
        fields = metadata_output.decode("utf-8").strip().split("|", 5)
        if (
            len(fields) != 6
            or fields[0] != "request"
            or fields[1] != "0"
            or fields[2] != "inline"
            or fields[4] != str(len(request))
            or fields[5] != "301"
            or base64.b64decode(fields[3], validate=True) != request
        ):
            raise AssertionError(f"metadata cleanup corrupted parsing: {fields}")
        if list(metadata_directory.iterdir()):
            raise AssertionError("metadata cleanup left raced publication")

        exit_directory = root / "exit-published"
        exit_directory.mkdir(mode=0o700)
        exit_temp = exit_directory / ".response-tmp.1.race"
        exit_temp.write_bytes(b"sensitive")
        exit_temp.chmod(0o600)
        exit_final = exit_directory / "response.1.json"
        exit_proof = exit_directory / "proof.1.json"
        exit_marker = root / "exit-marker"
        exit_release = root / "exit-release"

        def publish_exit() -> None:
            os.link(exit_temp, exit_final)
            os.link(exit_temp, exit_proof)
            exit_temp.unlink()

        run_cleanup_race_program(
            exit_script,
            [str(exit_directory)],
            b"",
            exit_marker,
            exit_release,
            publish_exit,
        )
        if exit_directory.exists():
            raise AssertionError("EXIT cleanup left raced publication directory")

        empty_directory = root / "exit-empty"
        empty_directory.mkdir(mode=0o700)
        empty_marker = root / "empty-marker"
        empty_release = root / "empty-release"

        def publish_after_empty_snapshot() -> None:
            path = empty_directory / ".response-tmp.2.race"
            path.write_bytes(b"late")
            path.chmod(0o600)

        run_cleanup_race_program(
            exit_script,
            [str(empty_directory)],
            b"",
            empty_marker,
            empty_release,
            publish_after_empty_snapshot,
        )
        if empty_directory.exists():
            raise AssertionError("EXIT cleanup did not retry ENOTEMPTY")


class DelayedReapFixture:
    """Fake process whose exit is observable only with a sufficient budget."""

    pid = 424_242

    def __init__(self, minimum_timeout: float) -> None:
        self.minimum_timeout = minimum_timeout
        self.returncode: int | None = None
        self.wait_timeouts: list[float | None] = []

    def poll(self) -> int | None:
        """Return the synthetic process status."""
        return self.returncode

    def wait(self, timeout: float | None = None) -> int:
        """Fail short observation budgets without sleeping."""
        self.wait_timeouts.append(timeout)
        if timeout is None or timeout < self.minimum_timeout:
            raise subprocess.TimeoutExpired(["delayed-reap-fixture"], timeout)
        self.returncode = -signal.SIGKILL
        return self.returncode


def run_bridge_reap_budget_regression() -> None:
    """Prove the loaded-suite reap budget exceeds the historical two seconds."""
    too_short = DelayedReapFixture(minimum_timeout=5.0)
    try:
        wait_for_bridge_reap(too_short, timeout=2.0)  # type: ignore[arg-type]
    except AssertionError:
        pass
    else:
        raise AssertionError("historical two-second reap budget unexpectedly passed")

    bounded = DelayedReapFixture(minimum_timeout=5.0)
    wait_for_bridge_reap(bounded)  # type: ignore[arg-type]
    if bounded.wait_timeouts != [BRIDGE_REAP_TIMEOUT_SECONDS]:
        raise AssertionError(f"wrong bridge reap budget: {bounded.wait_timeouts}")

    frame_too_short = DelayedReapFixture(minimum_timeout=4.0)
    try:
        wait_for_bridge_reap(frame_too_short, timeout=3.0)  # type: ignore[arg-type]
    except AssertionError:
        pass
    else:
        raise AssertionError("historical frame-exit budget unexpectedly passed")

    frame_bounded = DelayedReapFixture(minimum_timeout=4.0)
    wait_for_bridge_reap(  # type: ignore[arg-type]
        frame_bounded,
        timeout=FRAME_EXIT_TIMEOUT_SECONDS,
    )
    if frame_bounded.wait_timeouts != [FRAME_EXIT_TIMEOUT_SECONDS]:
        raise AssertionError(f"wrong frame-exit budget: {frame_bounded.wait_timeouts}")


def terminate_bridge(process: subprocess.Popen[bytes]) -> None:
    """Kill and reap PROCESS and every descendant in its process group."""
    try:
        if os.name == "posix":
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except (PermissionError, ProcessLookupError):
                pass
            deadline = time.monotonic() + BRIDGE_TERM_GRACE_SECONDS
            while process_group_alive(process.pid) and time.monotonic() < deadline:
                time.sleep(0.02)
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except (PermissionError, ProcessLookupError):
                pass
        elif process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=BRIDGE_TERM_GRACE_SECONDS)
            except subprocess.TimeoutExpired:
                process.kill()

        if process.poll() is None:
            wait_for_bridge_reap(process)
    finally:
        for stream in (process.stdin, process.stdout):
            if stream is not None and not stream.closed:
                stream.close()


def wait_for_bridge_ready(
    debug_log: Path,
    process: subprocess.Popen[bytes],
    timeout: float = READY_OBSERVER_TIMEOUT_SECONDS,
) -> None:
    """Wait until startup logging proves the bridge entered its read loop."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if debug_log.is_file() and "MCP-READY: stdio request loop" in safe_text(
            debug_log
        ):
            return
        if process.poll() is not None:
            raise AssertionError(
                f"bridge exited during startup: {safe_text(debug_log)}"
            )
        time.sleep(0.02)
    raise AssertionError(
        f"bridge startup exceeded {timeout:.1f}s: {safe_text(debug_log)}"
    )


def unexpected_reply_summary(reader: BinaryReader, deadline: float) -> str:
    """Consume one unexpected line reply and return only bounded metadata."""
    body = reader.line(deadline)
    try:
        document = json.loads(body)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return f"unparseable-bytes={len(body)}"
    if not isinstance(document, dict):
        return f"json-type={type(document).__name__}"
    error = document.get("error")
    if not isinstance(error, dict):
        return f"id={document.get('id')!r} error-type={type(error).__name__}"
    data = error.get("data")
    if not isinstance(data, dict):
        data = {}
    return (
        f"id={document.get('id')!r} code={error.get('code')!r} "
        f"phase={data.get('phase')} dispatched={data.get('dispatched')} "
        f"rc={data.get('emacsclientRc')!r}"
    )


def wait_for_dispatch_complete(
    marker: Path,
    process: subprocess.Popen[bytes],
    ack_fifo: Path,
    expected: int,
    before_release: object | None = None,
    timeout: float = DISPATCH_OBSERVER_TIMEOUT_SECONDS,
    unexpected_reply_reader: BinaryReader | None = None,
) -> None:
    """Wait for dispatch or fail promptly when a pre-dispatch reply arrives."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if marker.is_file():
            try:
                observed = int(marker.read_text(encoding="utf-8"))
            except ValueError:
                time.sleep(0.01)
                continue
            if observed != expected:
                raise AssertionError(
                    f"expected dispatch {expected}, observed {observed}"
                )
            if before_release is not None:
                before_release()  # type: ignore[operator]
            while time.monotonic() < deadline:
                try:
                    descriptor = os.open(
                        ack_fifo,
                        os.O_WRONLY | os.O_NONBLOCK,
                    )
                except OSError as error:
                    if error.errno != errno.ENXIO:
                        raise
                    if process.poll() is not None:
                        root = marker.parent
                        raise AssertionError(
                            "bridge exited before dispatch acknowledgement: "
                            f"rc={process.returncode} "
                            f"debug={safe_text(root / 'stdio.log')} "
                            f"stderr={safe_text(root / 'bridge.stderr')}"
                        ) from error
                    time.sleep(0.01)
                    continue
                try:
                    os.write(descriptor, b"go\n")
                finally:
                    os.close(descriptor)
                return
            raise AssertionError("fake client did not open acknowledgement FIFO")
        if unexpected_reply_reader is not None and (
            unexpected_reply_reader.buffer or unexpected_reply_reader.selector.select(0)
        ):
            summary = unexpected_reply_summary(
                unexpected_reply_reader,
                min(deadline, time.monotonic() + 1),
            )
            raise AssertionError(
                f"bridge replied before stateful dispatch: {summary}; "
                f"{unexpected_reply_reader.diagnostics()}"
            )
        if process.poll() is not None:
            root = marker.parent
            raise AssertionError(
                "bridge exited before dispatch completed: "
                f"rc={process.returncode} "
                f"debug={safe_text(root / 'stdio.log')} "
                f"stderr={safe_text(root / 'bridge.stderr')}"
            )
        time.sleep(0.02)
    root = marker.parent
    raise AssertionError(
        f"stateful dispatch exceeded {timeout:.1f}s: "
        f"debug={safe_text(root / 'stdio.log')} "
        f"stderr={safe_text(root / 'bridge.stderr')}"
    )


def run_dispatch_observer_reply_regression() -> None:
    """A pre-dispatch reply must end marker observation immediately."""
    with tempfile.TemporaryDirectory(prefix="anvil-dispatch-observer-") as raw:
        root = Path(raw)
        marker = root / "dispatch-complete"
        ack_fifo = root / "dispatch-ack.fifo"
        bridge_stderr = root / "bridge.stderr"
        helper_marker = root / "postdispatch-helper"
        dispatch_count = root / "dispatch-count"
        os.mkfifo(ack_fifo)
        reply = {
            "jsonrpc": "2.0",
            "id": 32,
            "error": {
                "code": -32603,
                "message": "synthetic fixture readiness failure",
                "data": {
                    "phase": "readiness",
                    "dispatched": False,
                    "replayed": False,
                    "emacsclientRc": 124,
                },
            },
        }
        script = (
            "import sys, time; "
            f"sys.stdout.buffer.write({json_bytes(reply)!r} + b'\\n'); "
            "sys.stdout.buffer.flush(); time.sleep(30)"
        )
        stderr_handle = bridge_stderr.open("wb")
        try:
            process = subprocess.Popen(
                [sys.executable, "-I", "-S", "-c", script],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=stderr_handle,
                start_new_session=os.name == "posix",
            )
        finally:
            stderr_handle.close()
        reader = BinaryReader(
            process,
            root / "stdio.log",
            bridge_stderr,
            helper_marker,
            dispatch_count,
        )
        if not reader.selector.select(READY_OBSERVER_TIMEOUT_SECONDS):
            reader.close()
            terminate_bridge(process)
            raise AssertionError("pre-dispatch reply fixture did not publish")
        try:
            try:
                wait_for_dispatch_complete(
                    marker,
                    process,
                    ack_fifo,
                    1,
                    unexpected_reply_reader=reader,
                    timeout=5,
                )
            except AssertionError as error:
                if "phase=readiness" not in str(error):
                    raise AssertionError(
                        f"observer hid the pre-dispatch phase: {error}"
                    ) from error
            else:
                raise AssertionError("observer ignored a pre-dispatch reply")
        finally:
            reader.close()
            terminate_bridge(process)


def assert_no_capture_paths(temp_dir: Path) -> None:
    """Require stateful stderr to use only its process-lifetime sink FD."""
    captures = list(temp_dir.rglob("dispatch.*.stderr"))
    private_dirs = list(temp_dir.glob("anvil-stdio.*"))
    if captures or private_dirs:
        raise AssertionError(
            f"bridge created loader-dependent capture paths: {captures + private_dirs}"
        )


def wait_until(predicate: object, timeout: float) -> bool:
    """Poll zero-argument PREDICATE until true or TIMEOUT expires."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():  # type: ignore[operator]
            return True
        time.sleep(0.02)
    return bool(predicate())  # type: ignore[operator]


def assert_no_helper(helper_marker: Path) -> None:
    """Require that no historical helper ran after dispatch."""
    if helper_marker.exists():
        raise AssertionError(safe_text(helper_marker))


def assert_same_bridge(
    process: subprocess.Popen[bytes],
    original_pid: int,
    pipe_ids: tuple[int, int],
) -> None:
    """Require the original bridge process and both pipes to remain live."""
    if process.poll() is not None or process.pid != original_pid:
        raise AssertionError("bridge process changed")
    if process.stdin is None or process.stdout is None:
        raise AssertionError("bridge pipes disappeared")
    current = (
        os.fstat(process.stdin.fileno()).st_ino,
        os.fstat(process.stdout.fileno()).st_ino,
    )
    if current != pipe_ids:
        raise AssertionError("bridge pipe changed")


def synthetic_dispatch_error(request_id: object, rc: int) -> dict[str, object]:
    """Return the expected correlated post-dispatch bridge error."""
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {
            "code": -32603,
            "message": (
                "Bridge synthetic error: "
                "daemon response was ambiguous after one dispatch"
            ),
            "data": {
                "phase": "dispatch",
                "dispatched": True,
                "replayed": False,
                "emacsclientRc": rc,
            },
        },
    }


def synthetic_stage_error(request_id: object, rc: int) -> dict[str, object]:
    """Return the expected correlated pre-dispatch staging error."""
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {
            "code": -32603,
            "message": (
                "Bridge synthetic error: large request staging failed before dispatch"
            ),
            "data": {
                "phase": "stage",
                "dispatched": False,
                "replayed": False,
                "emacsclientRc": rc,
            },
        },
    }


def synthetic_parse_runner_error(rc: int) -> dict[str, object]:
    """Return the expected bounded pre-dispatch runner error."""
    return {
        "jsonrpc": "2.0",
        "id": None,
        "error": {
            "code": -32603,
            "message": "Bridge synthetic error: bounded JSON-RPC metadata parsing failed",
            "data": {
                "phase": "parse",
                "dispatched": False,
                "replayed": False,
                "emacsclientRc": rc,
            },
        },
    }


def synthetic_invalid_request_error() -> dict[str, object]:
    """Return the expected error for a non-finite JSON-RPC identifier."""
    return {
        "jsonrpc": "2.0",
        "id": None,
        "error": {
            "code": -32600,
            "message": "Bridge synthetic error: invalid JSON-RPC request before dispatch",
            "data": {
                "phase": "parse",
                "dispatched": False,
                "replayed": False,
                "emacsclientRc": 0,
            },
        },
    }


def run_nonfinite_identifier(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """Prove a huge-exponent id stays valid JSON and never dispatches."""
    with tempfile.TemporaryDirectory(prefix="anvil-stdio-nonfinite-") as raw_root:
        root = Path(raw_root)
        expected = {
            "jsonrpc": "2.0",
            "id": 42,
            "result": "finite-id-recovery",
        }
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes(expected))],
            bash,
        )
        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            "--socket=/tmp/anvil-nonfinite-id-test",
            "--server-id=test",
        )
        reader = BinaryReader(
            process,
            paths["debug_log"],
            paths["bridge_stderr"],
            paths["helper_marker"],
            paths["dispatch_count"],
        )
        clean = False
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            original_pid = process.pid
            if process.stdin is None or process.stdout is None:
                raise AssertionError("bridge pipes are unavailable")
            pipe_ids = (
                os.fstat(process.stdin.fileno()).st_ino,
                os.fstat(process.stdout.fileno()).st_ino,
            )
            process.stdin.write(b'{"jsonrpc":"2.0","id":1e999,"method":"test"}\n')
            process.stdin.flush()
            read_reply(reader, synthetic_invalid_request_error(), framed=False)
            if read_count(paths["probe_count"]) != 0:
                raise AssertionError("non-finite id reached daemon readiness")
            if read_count(paths["dispatch_count"]) != 0:
                raise AssertionError("non-finite id reached stateful Emacs")
            assert_same_bridge(process, original_pid, pipe_ids)

            send(
                process,
                {"jsonrpc": "2.0", "id": 42, "method": "test"},
            )
            wait_for_dispatch_complete(
                paths["dispatch_complete"],
                process,
                paths["dispatch_ack_fifo"],
                1,
            )
            read_reply(reader, expected, framed=False)
            paths["dispatch_complete"].unlink()
            assert_no_helper(paths["helper_marker"])
            assert_same_bridge(process, original_pid, pipe_ids)
            process.stdin.close()
            process.wait(timeout=5)
            if process.returncode != 0:
                raise AssertionError(reader.diagnostics())
            clean = True
        finally:
            reader.close()
            if not clean:
                terminate_bridge(process)
            elif process.stdout is not None and not process.stdout.closed:
                process.stdout.close()


def run_predispatch_freeze(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """Prove a loader-frozen parser is killed and the same pipe recovers."""
    with tempfile.TemporaryDirectory(prefix="anvil-stdio-predispatch-") as raw_root:
        root = Path(raw_root)
        expected = {
            "jsonrpc": "2.0",
            "id": 32,
            "result": "post-timeout-ok",
        }
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes(expected))],
            bash,
        )
        environment["ANVIL_MCP_REQUEST_PARSE_TIMEOUT"] = str(
            PREDISPATCH_PARSE_TIMEOUT_SECONDS
        )
        python_wrapper = paths["binary"] / "python3"
        write_blocking_predispatch_wrapper(
            python_wrapper,
            bash,
            "python3",
            real_helpers["python3"],
        )
        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            "--socket=/tmp/anvil-predispatch-test",
            "--server-id=test",
        )
        reader = BinaryReader(
            process,
            paths["debug_log"],
            paths["bridge_stderr"],
            paths["helper_marker"],
            paths["dispatch_count"],
        )
        clean = False
        frozen_pid: int | None = None
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            original_pid = process.pid
            if process.stdin is None or process.stdout is None:
                raise AssertionError("bridge pipes are unavailable")
            pipe_ids = (
                os.fstat(process.stdin.fileno()).st_ino,
                os.fstat(process.stdout.fileno()).st_ino,
            )
            send(
                process,
                {"jsonrpc": "2.0", "id": 31, "method": "test"},
            )
            if not wait_until(
                paths["predispatch_marker"].is_file,
                PREDISPATCH_MARKER_TIMEOUT_SECONDS,
            ):
                raise AssertionError(
                    f"frozen pre-dispatch helper did not start: {reader.diagnostics()}"
                )
            marker = json.loads(paths["predispatch_marker"].read_text(encoding="utf-8"))
            frozen_pid = int(marker["pid"])
            read_reply(
                reader,
                synthetic_parse_runner_error(124),
                framed=False,
                timeout_seconds=PREDISPATCH_REPLY_TIMEOUT_SECONDS,
            )
            if read_count(paths["dispatch_count"]) != 0:
                raise AssertionError("pre-dispatch failure reached stateful Emacs")
            if not wait_until(lambda: not process_alive(frozen_pid), 2):
                raise AssertionError("bounded runner leaked its frozen child")
            assert_same_bridge(process, original_pid, pipe_ids)

            write_helper_wrapper(
                python_wrapper,
                bash,
                "python3",
                real_helpers["python3"],
            )
            send(
                process,
                {"jsonrpc": "2.0", "id": 32, "method": "test"},
            )
            wait_for_dispatch_complete(
                paths["dispatch_complete"],
                process,
                paths["dispatch_ack_fifo"],
                1,
                unexpected_reply_reader=reader,
            )
            read_reply(reader, expected, framed=False)
            paths["dispatch_complete"].unlink()
            assert_no_helper(paths["helper_marker"])
            assert_same_bridge(process, original_pid, pipe_ids)
            process.stdin.close()
            process.wait(timeout=5)
            if process.returncode != 0:
                raise AssertionError(reader.diagnostics())
            clean = True
        finally:
            reader.close()
            if not clean:
                terminate_bridge(process)
            elif process.stdout is not None and not process.stdout.closed:
                process.stdout.close()
        if frozen_pid is None:
            raise AssertionError("pre-dispatch regression recorded no child pid")


def run_default_parse_budget(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """Prove the default parser budget survives three seconds of host load."""
    with tempfile.TemporaryDirectory(prefix="anvil-stdio-parse-default-") as raw_root:
        root = Path(raw_root)
        expected = {
            "jsonrpc": "2.0",
            "id": 30,
            "result": "default-parse-ok",
        }
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes(expected))],
            bash,
        )
        environment.pop("ANVIL_MCP_REQUEST_PARSE_TIMEOUT")
        write_delayed_python_wrapper(
            paths["binary"] / "python3",
            bash,
            real_helpers["python3"],
            real_helpers["sleep"],
        )
        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            "--socket=/tmp/anvil-parse-default-test",
            "--server-id=test",
        )
        reader = BinaryReader(
            process,
            paths["debug_log"],
            paths["bridge_stderr"],
            paths["helper_marker"],
            paths["dispatch_count"],
        )
        clean = False
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            send(process, {"jsonrpc": "2.0", "id": 30, "method": "test"})
            wait_for_dispatch_complete(
                paths["dispatch_complete"],
                process,
                paths["dispatch_ack_fifo"],
                1,
            )
            read_reply(reader, expected, framed=False)
            paths["dispatch_complete"].unlink()
            process.stdin.close()
            process.wait(timeout=5)
            if process.returncode != 0:
                raise AssertionError(reader.diagnostics())
            clean = True
        finally:
            reader.close()
            if not clean:
                terminate_bridge(process)
            elif process.stdout is not None and not process.stdout.closed:
                process.stdout.close()


def run_guard_loader_owner_death(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
    parent_guard: Path | None,
    parent_guard_python: str | None,
) -> None:
    """Prove owner death kills a guard interpreter frozen before readiness."""
    if os.name != "posix":
        return
    with tempfile.TemporaryDirectory(prefix="anvil-stdio-guard-loader-") as raw_root:
        root = Path(raw_root)
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes({"unused": True}))],
            bash,
        )
        guard, _guard_python = prepare_parent_guard(
            root,
            parent_guard,
            parent_guard_python,
        )
        loader_marker = root / "guard-loader"
        loader_fifo = root / "guard-loader.fifo"
        os.mkfifo(loader_fifo)
        blocking_python = root / "guard-python"
        write_blocking_guard_python(blocking_python, bash)
        environment.update(
            {
                "ANVIL_MCP_PARENT_GUARD": str(guard),
                "ANVIL_MCP_PARENT_GUARD_PYTHON": str(blocking_python),
                "FAKE_GUARD_LOADER_MARKER": str(loader_marker),
                "FAKE_GUARD_LOADER_FIFO": str(loader_fifo),
            }
        )
        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            "--socket=/tmp/anvil-guard-loader-test",
            "--server-id=test",
        )
        loader_pid: int | None = None
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            send(
                process,
                {"jsonrpc": "2.0", "id": 55, "method": "test"},
            )
            if not wait_until(loader_marker.is_file, 15):
                raise AssertionError(
                    "guard interpreter did not freeze before readiness: "
                    f"rc={process.poll()} "
                    f"debug={safe_text(paths['debug_log'])} "
                    f"stderr={safe_text(paths['bridge_stderr'])}"
                )
            loader_pid = int(loader_marker.read_text(encoding="utf-8"))
            if os.getpgid(loader_pid) != process.pid:
                raise AssertionError(
                    "guard loader escaped the owner group before it was ready"
                )
            os.killpg(process.pid, signal.SIGKILL)
            wait_for_bridge_reap(process)
            if not wait_until(lambda: not process_alive(loader_pid), 3):
                raise AssertionError(
                    f"frozen guard interpreter survived owner death: {loader_pid}"
                )
            if read_count(paths["dispatch_count"]) != 0:
                raise AssertionError("guard-loader freeze reached stateful Emacs")
            if not wait_until(lambda: not process_group_alive(process.pid), 3):
                raise AssertionError("guard-loader owner group survived")
        finally:
            if loader_pid is not None and process_alive(loader_pid):
                try:
                    os.kill(loader_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            terminate_bridge(process)


def run_owner_death_case(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
    parent_guard: Path | None,
    parent_guard_python: str | None,
    *,
    guarded: bool,
    pid_only: bool = False,
) -> None:
    """Contrast historical leaks with guarded bridge-owner cleanup."""
    if os.name != "posix":
        return
    label = "guarded-pid" if pid_only else ("guarded" if guarded else "unguarded")
    with tempfile.TemporaryDirectory(prefix=f"anvil-stdio-owner-{label}-") as raw_root:
        root = Path(raw_root)
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes({"unused": True}))],
            bash,
        )
        child_marker = root / "owner-child"
        child_count = root / "owner-dispatch-count"
        child_fifo = root / "owner-child.fifo"
        os.mkfifo(child_fifo)
        environment.update(
            {
                "FAKE_OWNER_CHILD_MARKER": str(child_marker),
                "FAKE_OWNER_DISPATCH_COUNT": str(child_count),
                "FAKE_OWNER_BLOCK_FIFO": str(child_fifo),
            }
        )
        write_owner_blocking_emacsclient(
            paths["binary"] / "emacsclient",
            bash,
        )
        if guarded:
            guard, guard_python = prepare_parent_guard(
                root,
                parent_guard,
                parent_guard_python,
            )
            environment["ANVIL_MCP_PARENT_GUARD"] = str(guard)
            environment["ANVIL_MCP_PARENT_GUARD_PYTHON"] = guard_python

        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            f"--socket=/tmp/anvil-owner-{label}-test",
            "--server-id=test",
            initial_input=(
                json_bytes({"jsonrpc": "2.0", "id": 61, "method": "test"}) + b"\n"
            ),
        )
        child_pid: int | None = None
        child_group: int | None = None
        runner_pid: int | None = None
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            if not wait_until(
                child_marker.is_file,
                OWNER_DISPATCH_OBSERVER_TIMEOUT_SECONDS,
            ):
                raise AssertionError(
                    f"{label} dispatch did not enter the blocking client: "
                    f"rc={process.poll()} "
                    f"debug={safe_text(paths['debug_log'])} "
                    f"stderr={safe_text(paths['bridge_stderr'])}"
                )
            marker = json.loads(child_marker.read_text(encoding="utf-8"))
            assert_no_stage_fd_inheritance(marker, f"{label} client")
            child_pid = int(marker["pid"])
            runner_pid = int(marker["parent"])
            child_group = os.getpgid(child_pid)
            if (
                runner_pid in (process.pid, child_pid)
                or not process_alive(runner_pid)
                or os.getpgid(runner_pid) != process.pid
            ):
                raise AssertionError(
                    f"{label} did not identify the live bounded runner: "
                    f"bridge={process.pid} runner={runner_pid} child={child_pid}"
                )
            if child_group != child_pid:
                raise AssertionError(
                    f"{label} client is not its process-group leader: "
                    f"pid={child_pid} pgid={child_group}"
                )
            if read_count(child_count) != 1:
                raise AssertionError(f"{label} request was not dispatched once")

            if pid_only:
                os.kill(process.pid, signal.SIGKILL)
            else:
                os.killpg(process.pid, signal.SIGKILL)
            wait_for_bridge_reap(process)
            if guarded:
                if not wait_until(
                    lambda: not process_group_alive(child_group),
                    5,
                ):
                    raise AssertionError(
                        "guarded client group survived bridge-owner death"
                    )
                if pid_only and runner_pid is not None:
                    if not wait_until(lambda: not process_alive(runner_pid), 5):
                        raise AssertionError(
                            "bounded runner survived bridge-PID-only death"
                        )
                    if not wait_until(
                        lambda: not process_group_alive(process.pid),
                        5,
                    ):
                        raise AssertionError(
                            "bridge group survived bridge-PID-only death"
                        )
            elif not process_group_alive(child_group):
                raise AssertionError(
                    "negative control did not reproduce the orphaned client"
                )
            if read_count(child_count) != 1:
                raise AssertionError(f"{label} request was replayed")
        finally:
            if child_group is not None and process_group_alive(child_group):
                try:
                    os.killpg(child_group, signal.SIGKILL)
                except (PermissionError, ProcessLookupError):
                    pass
                if not wait_until(
                    lambda: not process_group_alive(child_group),
                    3,
                ):
                    raise AssertionError(f"{label} client group resisted test cleanup")
            if runner_pid is not None and process_alive(runner_pid):
                try:
                    os.kill(runner_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            terminate_bridge(process)


def run_runner_death_recovery(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
    parent_guard: Path | None,
    parent_guard_python: str | None,
) -> None:
    """Kill only the bounded runner and require same-pipe recovery."""
    if os.name != "posix":
        return
    with tempfile.TemporaryDirectory(prefix="anvil-stdio-runner-death-") as raw_root:
        root = Path(raw_root)
        expected = {
            "jsonrpc": "2.0",
            "id": 72,
            "result": "runner-recovery-ok",
        }
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes(expected))],
            bash,
        )
        guard, guard_python = prepare_parent_guard(
            root,
            parent_guard,
            parent_guard_python,
        )
        environment["ANVIL_MCP_PARENT_GUARD"] = str(guard)
        environment["ANVIL_MCP_PARENT_GUARD_PYTHON"] = guard_python
        child_marker = root / "runner-child"
        child_count = root / "runner-dispatch-count"
        child_fifo = root / "runner-child.fifo"
        os.mkfifo(child_fifo)
        environment.update(
            {
                "FAKE_OWNER_CHILD_MARKER": str(child_marker),
                "FAKE_OWNER_DISPATCH_COUNT": str(child_count),
                "FAKE_OWNER_BLOCK_FIFO": str(child_fifo),
            }
        )
        write_owner_blocking_emacsclient(
            paths["binary"] / "emacsclient",
            bash,
        )

        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            "--socket=/tmp/anvil-runner-death-test",
            "--server-id=test",
        )
        reader = BinaryReader(
            process,
            paths["debug_log"],
            paths["bridge_stderr"],
            paths["helper_marker"],
            paths["dispatch_count"],
        )
        child_pid: int | None = None
        child_group: int | None = None
        clean = False
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            original_pid = process.pid
            if process.stdin is None or process.stdout is None:
                raise AssertionError("bridge pipes are unavailable")
            pipe_ids = (
                os.fstat(process.stdin.fileno()).st_ino,
                os.fstat(process.stdout.fileno()).st_ino,
            )
            send(
                process,
                {"jsonrpc": "2.0", "id": 71, "method": "test"},
            )
            if not wait_until(child_marker.is_file, 5):
                raise AssertionError("runner-death client did not start")
            marker = json.loads(child_marker.read_text(encoding="utf-8"))
            assert_no_stage_fd_inheritance(marker, "runner-death client")
            child_pid = int(marker["pid"])
            runner_pid = int(marker["parent"])
            child_group = os.getpgid(child_pid)
            if child_group != child_pid:
                raise AssertionError("guarded client lacks its own process group")
            if runner_pid in (process.pid, child_pid) or not process_alive(runner_pid):
                raise AssertionError(f"invalid bounded runner identity: {runner_pid}")

            os.kill(runner_pid, signal.SIGKILL)
            read_reply(
                reader,
                synthetic_dispatch_error(71, 124),
                framed=False,
            )
            if not wait_until(
                lambda: not process_group_alive(child_group),
                5,
            ):
                raise AssertionError("runner death leaked its guarded client")
            if process_alive(runner_pid):
                raise AssertionError("killed bounded runner still exists")
            if read_count(child_count) != 1:
                raise AssertionError("runner-death request was replayed")
            assert_same_bridge(process, original_pid, pipe_ids)

            write_fake_emacsclient(
                paths["binary"] / "emacsclient",
                bash,
            )
            send(
                process,
                {"jsonrpc": "2.0", "id": 72, "method": "test"},
            )
            wait_for_dispatch_complete(
                paths["dispatch_complete"],
                process,
                paths["dispatch_ack_fifo"],
                1,
            )
            read_reply(reader, expected, framed=False)
            paths["dispatch_complete"].unlink()
            assert_same_bridge(process, original_pid, pipe_ids)
            process.stdin.close()
            process.wait(timeout=5)
            if process.returncode != 0:
                raise AssertionError(reader.diagnostics())
            clean = True
        finally:
            reader.close()
            if child_group is not None and process_group_alive(child_group):
                try:
                    os.killpg(child_group, signal.SIGKILL)
                except (PermissionError, ProcessLookupError):
                    pass
            if not clean:
                terminate_bridge(process)
            elif process.stdout is not None and not process.stdout.closed:
                process.stdout.close()


def run_idle_then_partial_first_line(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """Keep idle stdin alive, then bound partial byte and NUL inputs."""
    cases = (
        ("ascii", b"Content-Len", False),
        ("utf8-lead", b"\xc3", True),
        ("nul", b"\x00", True),
    )
    for label, payload, utf8_locale in cases:
        with tempfile.TemporaryDirectory(
            prefix=f"anvil-stdio-first-byte-{label}-"
        ) as raw_root:
            root = Path(raw_root)
            environment, paths = build_fixture(
                root,
                real_helpers,
                [printf_wire(json_bytes({"unused": True}))],
                bash,
            )
            environment["ANVIL_MCP_FRAME_READ_TIMEOUT"] = "1"
            if utf8_locale:
                environment["LANG"] = "C.UTF-8"
                environment["LC_ALL"] = "C.UTF-8"
            process = start_bridge(
                bash,
                stdio,
                environment,
                paths["bridge_stderr"],
                f"--socket=/tmp/anvil-first-byte-{label}-test",
                "--server-id=test",
            )
            try:
                wait_for_bridge_ready(paths["debug_log"], process)
                if label == "ascii":
                    time.sleep(1.75)
                    if process.poll() is not None:
                        raise AssertionError("idle bridge died before a request began")
                    if read_count(paths["dispatch_count"]) != 0:
                        raise AssertionError("idle bridge reached stateful Emacs")
                if process.stdin is None:
                    raise AssertionError("bridge stdin is unavailable")

                process.stdin.write(payload)
                process.stdin.flush()
                wait_for_bridge_reap(
                    process,
                    timeout=FRAME_EXIT_TIMEOUT_SECONDS,
                )
                if process.returncode == 0:
                    raise AssertionError(f"{label} first input exited successfully")
                if read_count(paths["dispatch_count"]) != 0:
                    raise AssertionError(f"{label} first input reached stateful Emacs")
                if not wait_until(lambda: not process_group_alive(process.pid), 2):
                    raise AssertionError(f"{label} bridge group survived exit")
            finally:
                terminate_bridge(process)


def run_nul_wire_rejection(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """Reject raw NUL after synchronizing with the intended bounded reader."""
    cases = (
        (
            "legacy-embedded",
            b'{"jsonrpc":"2.0","id":7,\x00"method":"tools/call"}\n',
            "line",
            1,
        ),
        (
            "header-embedded",
            b"Content-Length: 2\r\nX-Test:\x00bad\r\n\r\n{}",
            "line",
            2,
        ),
        (
            "body-partial",
            b"Content-Length: 100\r\n\r\n\x00",
            "body",
            1,
        ),
        (
            "body-forged-status",
            b"Content-Length: 100\r\n\r\n\x000\n",
            "body",
            1,
        ),
    )
    for label, payload, expected_tag, expected_occurrence in cases:
        attempt_failures: list[str] = []
        for attempt in range(1, 4):
            with tempfile.TemporaryDirectory(
                prefix=f"anvil-stdio-nul-{label}-{attempt}-"
            ) as raw_root:
                root = Path(raw_root)
                environment, paths = build_fixture(
                    root,
                    real_helpers,
                    [printf_wire(json_bytes({"unused": True}))],
                    bash,
                )
                marker = root / "python-reader-pids"
                wrapper = paths["binary"] / "python3"
                real_python = real_helpers["python3"]
                make_executable(
                    wrapper,
                    f"""#!{real_python}
import os
import sys


code = " ".join(sys.argv[1:])
tag = (
    "body"
    if "remaining = int(sys.argv[1])" in code
    else "line"
    if "limit = int(sys.argv[1])" in code
    else ""
)
if tag:
    descriptor = os.open(
        os.environ["ANVIL_TEST_PYTHON_MARKER"],
        os.O_APPEND | os.O_CREAT | os.O_WRONLY,
        0o600,
    )
    try:
        os.write(
            descriptor,
            f"{{tag}}|{{os.getpid()}}|{{os.getppid()}}\\n".encode("ascii"),
        )
    finally:
        os.close(descriptor)
os.execv({real_python!r}, [{real_python!r}, *sys.argv[1:]])
""",
                )
                environment.update(
                    {
                        "ANVIL_TEST_PYTHON_MARKER": str(marker),
                        "ANVIL_MCP_FRAME_READ_TIMEOUT": "10",
                    }
                )
                process = start_bridge(
                    bash,
                    stdio,
                    environment,
                    paths["bridge_stderr"],
                    f"--socket=/tmp/anvil-nul-{label}-test",
                    "--server-id=test",
                )

                def reader_records() -> list[list[str]]:
                    return [
                        line.split("|")
                        for line in safe_text(marker).splitlines()
                        if line.count("|") == 2
                    ]

                attempt_completed = False
                try:
                    wait_for_bridge_ready(paths["debug_log"], process)
                    if process.stdin is None:
                        raise AssertionError("bridge stdin is unavailable")
                    prefix, separator, suffix = payload.partition(b"\x00")
                    if separator != b"\x00":
                        raise AssertionError(f"{label} fixture has no NUL byte")
                    process.stdin.write(prefix)
                    process.stdin.flush()

                    def target_reader_started() -> bool:
                        return (
                            sum(
                                record[0] == expected_tag for record in reader_records()
                            )
                            >= expected_occurrence
                        )

                    if not wait_until(target_reader_started, 4.0):
                        attempt_failures.append(
                            f"attempt={attempt} rc={process.poll()} "
                            f"marker={safe_text(marker)!r} "
                            f"debug={safe_text(paths['debug_log'])!r} "
                            f"stderr={safe_text(paths['bridge_stderr'])!r}"
                        )
                        continue
                    process.stdin.write(separator + suffix)
                    process.stdin.flush()
                    try:
                        wait_for_bridge_reap(process, timeout=4.0)
                    except AssertionError as error:
                        attempt_failures.append(
                            f"attempt={attempt} reader did not reject NUL "
                            f"promptly: {error}; marker={safe_text(marker)!r} "
                            f"debug={safe_text(paths['debug_log'])!r} "
                            f"stderr={safe_text(paths['bridge_stderr'])!r}"
                        )
                        continue
                    if process.returncode == 0:
                        raise AssertionError(f"{label} NUL input exited successfully")
                    if read_count(paths["dispatch_count"]) != 0:
                        raise AssertionError(
                            f"{label} NUL input reached stateful Emacs"
                        )
                    records = reader_records()
                    if (
                        sum(record[0] == expected_tag for record in records)
                        < expected_occurrence
                    ):
                        raise AssertionError(
                            f"{label} lost the expected reader record: {records!r}"
                        )
                    identities = {
                        int(identity)
                        for _tag, child, parent in records
                        for identity in (child, parent)
                    }
                    if not wait_until(
                        lambda: all(not process_alive(pid) for pid in identities),
                        3,
                    ):
                        survivors = [pid for pid in identities if process_alive(pid)]
                        raise AssertionError(
                            f"{label} left reader/runner identities alive: {survivors}"
                        )
                    if not wait_until(
                        lambda: not process_group_alive(process.pid),
                        3,
                    ):
                        raise AssertionError(f"{label} bridge group survived exit")
                    assert_no_capture_paths(paths["temp"])
                    attempt_completed = True
                finally:
                    terminate_bridge(process)
                    if not attempt_completed:
                        if read_count(paths["dispatch_count"]) != 0:
                            raise AssertionError(
                                f"{label} synchronization attempt dispatched"
                            )
                        records = reader_records()
                        identities = {
                            int(identity)
                            for _tag, child, parent in records
                            for identity in (child, parent)
                        }
                        if not wait_until(
                            lambda: all(not process_alive(pid) for pid in identities),
                            3,
                        ):
                            survivors = [
                                pid for pid in identities if process_alive(pid)
                            ]
                            raise AssertionError(
                                f"{label} retry left reader/runner identities "
                                f"alive: {survivors}"
                            )
                        if not wait_until(
                            lambda: not process_group_alive(process.pid),
                            3,
                        ):
                            raise AssertionError(
                                f"{label} retry left the bridge group alive"
                            )
                        assert_no_capture_paths(paths["temp"])
            break
        else:
            raise AssertionError(
                f"{label} did not prove prompt NUL rejection through "
                f"{expected_tag} reader occurrence {expected_occurrence} "
                f"after three clean attempts: " + " | ".join(attempt_failures)
            )


def run_cumulative_frame_budget(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
    parent_guard: Path | None = None,
    parent_guard_python: str | None = None,
    *,
    _attempt: int = 1,
) -> None:
    """Prove headers and body consume one guarded absolute frame deadline."""
    guarded = parent_guard is not None
    suffix = "guarded" if guarded else "plain"
    retry_reason: str | None = None
    with tempfile.TemporaryDirectory(
        prefix=f"anvil-stdio-frame-budget-{suffix}-"
    ) as raw_root:
        root = Path(raw_root)
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes({"unused": True}))],
            bash,
        )
        environment["ANVIL_MCP_FRAME_READ_TIMEOUT"] = "10"
        if guarded:
            guard, guard_python = prepare_parent_guard(
                root,
                parent_guard,
                parent_guard_python,
            )
            environment.update(
                {
                    "ANVIL_MCP_PARENT_GUARD": str(guard),
                    "ANVIL_MCP_PARENT_GUARD_PYTHON": guard_python,
                }
            )
        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            f"--socket=/tmp/anvil-frame-budget-{suffix}-test",
            "--server-id=test",
        )
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            if process.stdin is None:
                raise AssertionError("bridge stdin is unavailable")

            started = time.monotonic()
            process.stdin.write(b"Content-Length: 64\r\n")
            process.stdin.flush()
            header_release = started + 7.0
            time.sleep(max(0.0, header_release - time.monotonic()))
            process.stdin.write(b"X-Test: budget\r\n\r\n{")
            process.stdin.flush()

            # A shared ten-second deadline plus bounded cleanup finishes before
            # 14.75s.  Resetting the body budget cannot finish before about 16s.
            deadline = started + 14.75
            try:
                process.wait(timeout=max(0.1, deadline - time.monotonic()))
            except subprocess.TimeoutExpired as error:
                raise AssertionError(
                    "frame stages reset the cumulative deadline"
                ) from error
            if process.returncode == 0:
                raise AssertionError("incomplete cumulative frame exited successfully")
            if "MCP-FRAMING: body reader start" not in safe_text(paths["debug_log"]):
                retry_reason = "cumulative frame never entered the body reader"
            if read_count(paths["dispatch_count"]) != 0:
                raise AssertionError(
                    "incomplete cumulative frame reached stateful Emacs"
                )
            if not wait_until(lambda: not process_group_alive(process.pid), 2):
                raise AssertionError("cumulative-frame bridge group survived exit")
            if retry_reason is not None:
                assert_no_capture_paths(paths["temp"])
        finally:
            terminate_bridge(process)

    if retry_reason is not None:
        if _attempt >= 3:
            raise AssertionError(
                f"{retry_reason} after {_attempt} clean {suffix} attempts"
            )
        run_cumulative_frame_budget(
            stdio,
            bash,
            real_helpers,
            parent_guard,
            parent_guard_python,
            _attempt=_attempt + 1,
        )


def run_stalled_frame_header(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """Prove a partial framed header cannot retain an open bridge pipe."""
    with tempfile.TemporaryDirectory(prefix="anvil-stdio-stalled-header-") as raw_root:
        root = Path(raw_root)
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes({"unused": True}))],
            bash,
        )
        environment["ANVIL_MCP_FRAME_READ_TIMEOUT"] = "1"
        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            "--socket=/tmp/anvil-stalled-header-test",
            "--server-id=test",
        )
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            if process.stdin is None:
                raise AssertionError("bridge stdin is unavailable")
            process.stdin.write(b"Content-Length: 40\r\nX-Test: stalled")
            process.stdin.flush()
            process.wait(timeout=4)
            if process.returncode == 0:
                raise AssertionError("stalled frame header exited successfully")
            if read_count(paths["dispatch_count"]) != 0:
                raise AssertionError("stalled frame header reached stateful Emacs")
            if not wait_until(lambda: not process_group_alive(process.pid), 2):
                raise AssertionError("stalled-header reader survived bridge exit")
        finally:
            terminate_bridge(process)


def run_truncated_frame(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """Prove an incomplete frame exits instead of desynchronizing the pipe."""
    with tempfile.TemporaryDirectory(prefix="anvil-stdio-truncated-") as raw_root:
        root = Path(raw_root)
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes({"unused": True}))],
            bash,
        )
        environment["ANVIL_MCP_FRAME_READ_TIMEOUT"] = "1"
        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            "--socket=/tmp/anvil-truncated-frame-test",
            "--server-id=test",
        )
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            if process.stdin is None:
                raise AssertionError("bridge stdin is unavailable")
            process.stdin.write(b'Content-Length: 40\r\n\r\n{"id":')
            process.stdin.flush()
            process.wait(timeout=4)
            if process.returncode == 0:
                raise AssertionError("truncated frame exited successfully")
            if read_count(paths["dispatch_count"]) != 0:
                raise AssertionError("truncated frame reached stateful Emacs")
            if not wait_until(lambda: not process_group_alive(process.pid), 2):
                raise AssertionError("truncated-frame reader survived bridge exit")
        finally:
            terminate_bridge(process)


def run_negative_control(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """Prove the historical post-dispatch grep hangs boundedly."""
    with tempfile.TemporaryDirectory(prefix="anvil-stdio-negative-") as raw_root:
        root = Path(raw_root)
        request_document = {
            "jsonrpc": "2.0",
            "id": 91,
            "method": "test",
        }
        request_bytes = json_bytes(request_document)
        metadata = (
            f"request|0|inline|{base64.b64encode(request_bytes).decode('ascii')}|"
            f"{len(request_bytes)}|91"
        )

        vulnerable = root / "anvil-stdio-vulnerable.sh"
        source = stdio.read_text(encoding="utf-8")
        needle = "\t# The marker is intentionally tiny"
        injected = (
            "\tgrep -c '\\*ERROR\\*' /dev/null >/dev/null\n\n"
            "\t# The marker is intentionally tiny"
        )
        if source.count(needle) != 1:
            raise AssertionError("negative-control injection point drifted")
        metadata_anchor = "# Emit a correlated at-most-once error."
        if source.count(metadata_anchor) != 1:
            raise AssertionError("metadata override injection point drifted")
        metadata_override = (
            "anvil_mcp_request_metadata() {\n"
            f"\tANVIL_MCP_RUN_OUTPUT={shlex.quote(metadata)}\n"
            "\tANVIL_MCP_RUN_STATUS=0\n"
            "\treturn 0\n"
            "}\n\n"
        )
        source = source.replace(needle, injected, 1)
        source = source.replace(
            metadata_anchor,
            metadata_override + metadata_anchor,
            1,
        )
        vulnerable.write_text(source, encoding="utf-8")

        expected = {
            "jsonrpc": "2.0",
            "id": 91,
            "result": "negative-control",
        }
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes(expected))],
            bash,
        )
        process = start_bridge(
            bash,
            vulnerable,
            environment,
            paths["bridge_stderr"],
            "--socket=/tmp/anvil-postdispatch-negative",
            "--server-id=test",
        )
        reader = BinaryReader(
            process,
            paths["debug_log"],
            paths["bridge_stderr"],
            paths["helper_marker"],
            paths["dispatch_count"],
        )
        helper_pid: int | None = None
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            assert_no_capture_paths(paths["temp"])
            send(process, request_document)
            wait_for_dispatch_complete(
                paths["dispatch_complete"],
                process,
                paths["dispatch_ack_fifo"],
                1,
            )
            try:
                read_reply(
                    reader,
                    expected,
                    framed=False,
                    timeout_seconds=3.0,
                )
            except AssertionError:
                pass
            else:
                raise AssertionError(
                    "negative control unexpectedly returned a response"
                )
            wait_until(
                lambda: paths["helper_marker"].is_file() or process.poll() is not None,
                SUCCESS_REPLY_TIMEOUT_SECONDS,
            )
            if not paths["helper_marker"].is_file():
                raise AssertionError(
                    "negative control did not reach post-dispatch grep: "
                    f"{reader.diagnostics()}"
                )
            marker = json.loads(paths["helper_marker"].read_text(encoding="utf-8"))
            if marker.get("program") != "grep":
                raise AssertionError(f"wrong helper blocked: {marker}")
            helper_pid = int(marker["pid"])
            if read_count(paths["dispatch_count"]) != 1:
                raise AssertionError("negative control replayed its request")
        finally:
            reader.close()
            terminate_bridge(process)
        if helper_pid is None:
            raise AssertionError("negative control recorded no helper pid")
        if not wait_until(
            lambda: not process_alive(helper_pid),
            BRIDGE_REAP_TIMEOUT_SECONDS,
        ):
            raise AssertionError(
                f"negative-control helper survived cleanup: {helper_pid}"
            )
        if not wait_until(
            lambda: not process_group_alive(process.pid),
            BRIDGE_REAP_TIMEOUT_SECONDS,
        ):
            raise AssertionError("negative-control process group survived")


def run_positive(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """Prove the fixed bridge survives every post-dispatch adversary."""
    with tempfile.TemporaryDirectory(prefix="anvil-stdio-postdispatch-") as raw_root:
        root = Path(raw_root)
        first = {
            "jsonrpc": "2.0",
            "id": 1,
            "result": "line-ok",
        }
        third = {
            "jsonrpc": "2.0",
            "id": "framed-雪",
            "result": "λ雪🙂\\path" * 1280,
        }
        third_bytes = json_bytes(third)
        if len(third_bytes) == len(third_bytes.decode("utf-8")):
            raise AssertionError("framed fixture is not multibyte")
        if len(printf_wire(third_bytes)) <= 49_152:
            raise AssertionError("framed fixture does not cross a decoder chunk")

        environment, paths = build_fixture(
            root,
            real_helpers,
            [
                printf_wire(json_bytes(first)),
                r"\x7b\x00\x7d",
                printf_wire(third_bytes),
            ],
            bash,
        )
        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            "--init-function=test-init",
            "--stop-function=test-stop",
            "--socket=/tmp/anvil-postdispatch-test",
            "--server-id=test",
        )
        reader = BinaryReader(
            process,
            paths["debug_log"],
            paths["bridge_stderr"],
            paths["helper_marker"],
            paths["dispatch_count"],
        )
        clean = False
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            assert_no_capture_paths(paths["temp"])
            if not wait_until(
                lambda: read_count(paths["init_count"]) == 1,
                5,
            ):
                raise AssertionError("init did not complete during startup")
            lifecycle_log = paths["debug_log"].open("rb")
            original_pid = process.pid
            if process.stdin is None or process.stdout is None:
                raise AssertionError("bridge pipes are unavailable")
            pipe_ids = (
                os.fstat(process.stdin.fileno()).st_ino,
                os.fstat(process.stdout.fileno()).st_ino,
            )
            send(
                process,
                {"jsonrpc": "2.0", "id": 1, "method": "test"},
            )
            wait_for_dispatch_complete(
                paths["dispatch_complete"],
                process,
                paths["dispatch_ack_fifo"],
                1,
                (
                    lambda: (
                        replace_with_fifo(paths["debug_log"])
                        if os.name == "posix"
                        else None
                    )
                ),
            )
            read_reply(reader, first, framed=False)
            assert_no_helper(paths["helper_marker"])
            if os.name == "posix":
                mode = paths["debug_log"].stat().st_mode
                if not stat.S_ISFIFO(mode):
                    raise AssertionError("debug-log race was not injected")
            paths["dispatch_complete"].unlink()
            assert_same_bridge(process, original_pid, pipe_ids)

            send(
                process,
                {"jsonrpc": "2.0", "id": 2, "method": "test"},
            )
            wait_for_dispatch_complete(
                paths["dispatch_complete"],
                process,
                paths["dispatch_ack_fifo"],
                2,
            )
            read_reply(
                reader,
                synthetic_dispatch_error(2, 70),
                framed=False,
            )
            assert_no_helper(paths["helper_marker"])
            paths["dispatch_complete"].unlink()
            assert_same_bridge(process, original_pid, pipe_ids)

            send(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": "framed-雪",
                    "method": "test",
                    "params": {"x": "ą🙂\\path"},
                },
                framed=True,
                content_length_header="CONTENT-LENGTH",
            )
            wait_for_dispatch_complete(
                paths["dispatch_complete"],
                process,
                paths["dispatch_ack_fifo"],
                3,
            )
            read_reply(reader, third, framed=True)
            assert_no_helper(paths["helper_marker"])
            paths["dispatch_complete"].unlink()
            assert_same_bridge(process, original_pid, pipe_ids)
            assert_no_capture_paths(paths["temp"])

            if read_count(paths["dispatch_count"]) != 3:
                raise AssertionError(
                    f"request replayed: "
                    f"{read_count(paths['dispatch_count'])} dispatches"
                )
            if read_count(paths["init_count"]) != 1:
                raise AssertionError("init was not dispatched exactly once")
            if read_count(paths["probe_count"]) != 4:
                raise AssertionError(
                    f"unexpected pre-stop readiness count: "
                    f"{read_count(paths['probe_count'])}"
                )

            process.stdin.close()
            process.wait(timeout=5)
            if process.returncode != 0:
                raise AssertionError(reader.diagnostics())
            if read_count(paths["stop_count"]) != 1:
                raise AssertionError("stop was not dispatched exactly once")
            if read_count(paths["probe_count"]) != 5:
                raise AssertionError(
                    f"unexpected final readiness count: "
                    f"{read_count(paths['probe_count'])}"
                )
            lifecycle_log.seek(0)
            lifecycle_text = lifecycle_log.read().decode("utf-8", errors="replace")
            for expected in ("MCP-INIT-RC: 0", "MCP-STOP-RC: 0"):
                if lifecycle_text.count(expected) != 1:
                    raise AssertionError(
                        f"missing or duplicate lifecycle log {expected!r}: "
                        f"{lifecycle_text[-4000:]}"
                    )
            assert_no_helper(paths["helper_marker"])
            if not wait_until(
                lambda: not process_group_alive(process.pid),
                2,
            ):
                raise AssertionError("detached cleanup process survived bridge exit")
            clean = True
        finally:
            reader.close()
            if lifecycle_log is not None:
                lifecycle_log.close()
            if not clean:
                terminate_bridge(process)
            else:
                for stream in (process.stdout,):
                    if stream is not None and not stream.closed:
                        stream.close()


def run_response_prepare_interruption(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """A timed-out stage helper must retain no canonical artifacts."""
    with tempfile.TemporaryDirectory(prefix="anvil-response-prepare-timeout-") as raw:
        root = Path(raw)
        unused = {
            "jsonrpc": "2.0",
            "id": 201,
            "result": "must-not-dispatch",
        }
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes(unused))],
            bash,
        )
        pause_marker = root / "response-prepare-paused"
        write_response_prepare_pause_wrapper(
            paths["binary"] / "python3",
            real_helpers["python3"],
        )
        environment["FAKE_RESPONSE_PREPARE_MODE"] = "pause"
        environment["FAKE_RESPONSE_PREPARE_MARKER"] = str(pause_marker)
        environment["ANVIL_MCP_REQUEST_PARSE_TIMEOUT"] = "1"
        symlink_temp = root / "tmp-link"
        symlink_temp.symlink_to(paths["temp"], target_is_directory=True)
        environment["TMPDIR"] = str(symlink_temp)
        request = json_bytes({"jsonrpc": "2.0", "id": 201, "method": "test"}) + b"\n"
        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            "--socket=/tmp/anvil-response-prepare-timeout",
            "--server-id=test",
            initial_input=request,
        )
        reader = BinaryReader(
            process,
            paths["debug_log"],
            paths["bridge_stderr"],
            paths["helper_marker"],
            paths["dispatch_count"],
        )
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            read_reply(
                reader,
                synthetic_stage_error(201, 124),
                framed=False,
                timeout_seconds=15,
            )
            process.wait(timeout=15)
            if process.returncode != 74:
                raise AssertionError(
                    f"response-preparation timeout returned {process.returncode}: "
                    f"{reader.diagnostics()}"
                )
            if not pause_marker.is_file():
                raise AssertionError("response preparer never created its stage")
            if read_count(paths["dispatch_count"]) != 0:
                raise AssertionError("response-preparation failure reached dispatch")
            if list(paths["temp"].glob("anvil-mcp.*")):
                raise AssertionError("interrupted response stage was orphaned")
            if not wait_until(lambda: not process_group_alive(process.pid), 2):
                raise AssertionError("response-preparation helper survived timeout")
        finally:
            reader.close()
            terminate_bridge(process)


def run_response_fd_validation_status_preserved(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """FD authentication retains a bounded helper's exact nonzero status."""
    with tempfile.TemporaryDirectory(prefix="anvil-response-fd-status-") as raw:
        root = Path(raw)
        unused = {
            "jsonrpc": "2.0",
            "id": 202,
            "result": "must-not-dispatch",
        }
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes(unused))],
            bash,
        )
        validator_marker = root / "response-fd-validator"
        write_response_prepare_pause_wrapper(
            paths["binary"] / "python3",
            real_helpers["python3"],
        )
        environment["FAKE_RESPONSE_VALIDATE_MODE"] = "status-124"
        environment["FAKE_RESPONSE_VALIDATE_MARKER"] = str(validator_marker)
        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            "--socket=/tmp/anvil-response-fd-status",
            "--server-id=test",
        )
        reader = BinaryReader(
            process,
            paths["debug_log"],
            paths["bridge_stderr"],
            paths["helper_marker"],
            paths["dispatch_count"],
        )
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            send(
                process,
                {"jsonrpc": "2.0", "id": 202, "method": "test"},
            )
            read_reply(
                reader,
                synthetic_stage_error(202, 124),
                framed=False,
                timeout_seconds=10,
            )
            process.wait(timeout=10)
            if process.returncode != 74:
                raise AssertionError(
                    f"response-FD validation returned {process.returncode}: "
                    f"{reader.diagnostics()}"
                )
            if not validator_marker.is_file():
                raise AssertionError("response-FD validator was not exercised")
            if read_count(paths["dispatch_count"]) != 0:
                raise AssertionError("response-FD validation failure reached dispatch")
            if list(paths["temp"].glob("anvil-mcp.*")):
                raise AssertionError("response-FD validation left staged artifacts")
            if not wait_until(lambda: not process_group_alive(process.pid), 2):
                raise AssertionError("response-FD validation helper survived exit")
        finally:
            reader.close()
            terminate_bridge(process)


def run_response_link_capability_failure(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """An unsupported hard link fails before dispatch without artifacts."""
    with tempfile.TemporaryDirectory(prefix="anvil-response-link-failure-") as raw:
        root = Path(raw)
        unused = {
            "jsonrpc": "2.0",
            "id": 203,
            "result": "must-not-dispatch",
        }
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes(unused))],
            bash,
        )
        link_marker = root / "response-link-probed"
        write_response_prepare_pause_wrapper(
            paths["binary"] / "python3",
            real_helpers["python3"],
        )
        environment["FAKE_RESPONSE_PREPARE_MODE"] = "link-fail"
        environment["FAKE_RESPONSE_LINK_MARKER"] = str(link_marker)
        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            "--socket=/tmp/anvil-response-link-failure",
            "--server-id=test",
        )
        reader = BinaryReader(
            process,
            paths["debug_log"],
            paths["bridge_stderr"],
            paths["helper_marker"],
            paths["dispatch_count"],
        )
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            send(
                process,
                {"jsonrpc": "2.0", "id": 203, "method": "test"},
            )
            read_reply(
                reader,
                synthetic_stage_error(203, 1),
                framed=False,
                timeout_seconds=5,
            )
            process.wait(timeout=5)
            if process.returncode != 74:
                raise AssertionError(
                    f"link preflight failure returned {process.returncode}: "
                    f"{reader.diagnostics()}"
                )
            if not link_marker.is_file():
                raise AssertionError("hard-link preflight was not exercised")
            if read_count(paths["dispatch_count"]) != 0:
                raise AssertionError("unsupported hard link reached dispatch")
            if list(paths["temp"].glob("anvil-mcp.*")):
                raise AssertionError("failed hard-link preflight left artifacts")
        finally:
            reader.close()
            terminate_bridge(process)


def run_competitor_inode_rejection(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """A different final/proof inode can never supply MCP response bytes."""
    with tempfile.TemporaryDirectory(prefix="anvil-response-competitor-") as raw:
        root = Path(raw)
        legitimate = {
            "jsonrpc": "2.0",
            "id": 204,
            "result": "legitimate-but-unwritten",
        }
        competitor = {
            "jsonrpc": "2.0",
            "id": 204,
            "result": "COMPETITOR-INODE-MUST-NEVER-REACH-STDOUT",
        }
        competitor_bytes = json_bytes(competitor)
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes(legitimate))],
            bash,
        )
        environment["FAKE_RESPONSE_PUBLICATION_MODE"] = "competitor"
        environment["FAKE_COMPETITOR_WIRE"] = printf_wire(competitor_bytes)
        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            "--socket=/tmp/anvil-response-competitor",
            "--server-id=test",
        )
        reader = BinaryReader(
            process,
            paths["debug_log"],
            paths["bridge_stderr"],
            paths["helper_marker"],
            paths["dispatch_count"],
        )
        clean = False
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            send(
                process,
                {"jsonrpc": "2.0", "id": 204, "method": "test"},
            )
            wait_for_dispatch_complete(
                paths["dispatch_complete"],
                process,
                paths["dispatch_ack_fifo"],
                1,
            )
            read_reply(
                reader,
                synthetic_dispatch_error(204, 70),
                framed=False,
            )
            if competitor_bytes in bytes(reader.buffer):
                raise AssertionError("competitor inode bytes remained on MCP stdout")
            if "COMPETITOR-INODE" in safe_text(paths["bridge_stderr"]):
                raise AssertionError("competitor inode leaked through bridge stderr")
            if read_count(paths["dispatch_count"]) != 1:
                raise AssertionError("competitor rejection replayed the request")
            paths["dispatch_complete"].unlink()
            process.stdin.close()
            process.wait(timeout=5)
            if process.returncode != 0:
                raise AssertionError(reader.diagnostics())
            if list(paths["temp"].glob("anvil-mcp.*")):
                raise AssertionError("competitor transaction survived bridge EOF")
            if process_group_alive(process.pid):
                raise AssertionError("competitor bridge group survived EOF")
            clean = True
        finally:
            reader.close()
            if not clean:
                terminate_bridge(process)
            elif process.stdout is not None and not process.stdout.closed:
                process.stdout.close()


def run_request_symlink_retirement(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """A swapped large-request symlink fails closed without touching its target."""
    with tempfile.TemporaryDirectory(prefix="anvil-request-symlink-") as raw:
        root = Path(raw)
        document = {
            "jsonrpc": "2.0",
            "id": 205,
            "method": "test",
            "params": {"payload": "x" * (32 * 1024)},
        }
        document_bytes = json_bytes(document)
        response = {"jsonrpc": "2.0", "id": 205, "result": "must-not-emit"}
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes(response))],
            bash,
        )
        sentinel = root / "outside-sentinel"
        sentinel_bytes = b"external-target-must-remain-unchanged\n"
        sentinel.write_bytes(sentinel_bytes)
        sentinel.chmod(0o600)
        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            "--socket=/tmp/anvil-request-symlink",
            "--server-id=test",
        )
        clean = False
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            send(process, document)

            def replace_request_with_symlink() -> None:
                directories = list(paths["temp"].glob("anvil-mcp.*"))
                if len(directories) != 1:
                    raise AssertionError(
                        f"missing symlink-test transaction: {directories}"
                    )
                request = directories[0] / "request.1.json"
                if (
                    request.is_symlink()
                    or not request.is_file()
                    or request.read_bytes() != document_bytes
                ):
                    raise AssertionError("large request was not staged exactly")
                request.unlink()
                request.symlink_to(sentinel)

            wait_for_dispatch_complete(
                paths["dispatch_complete"],
                process,
                paths["dispatch_ack_fifo"],
                1,
                replace_request_with_symlink,
            )
            process.wait(timeout=5)
            stdout = process.stdout.read() if process.stdout is not None else b""
            if process.returncode != 74:
                raise AssertionError(
                    f"request symlink returned {process.returncode}: "
                    f"stdout={stdout!r} stderr={safe_text(paths['bridge_stderr'])}"
                )
            if stdout:
                raise AssertionError(f"request symlink emitted MCP bytes: {stdout!r}")
            if sentinel.read_bytes() != sentinel_bytes:
                raise AssertionError("request retirement modified the symlink target")
            if read_count(paths["dispatch_count"]) != 1:
                raise AssertionError("request symlink replayed the dispatch")
            if list(paths["temp"].glob("anvil-mcp.*")):
                raise AssertionError("request-symlink transaction survived exit")
            if process_group_alive(process.pid):
                raise AssertionError("request-symlink bridge group survived exit")
            clean = True
        finally:
            if process.stdin is not None and not process.stdin.closed:
                try:
                    process.stdin.close()
                except BrokenPipeError:
                    pass
            if not clean:
                terminate_bridge(process)
            elif process.stdout is not None and not process.stdout.closed:
                process.stdout.close()


def run_oversized_marker(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """An absurd advisory marker cannot reach Bash integer comparison."""
    with tempfile.TemporaryDirectory(prefix="anvil-response-marker-overflow-") as raw:
        root = Path(raw)
        expected = {
            "jsonrpc": "2.0",
            "id": 202,
            "result": "marker-overflow-ok",
        }
        environment, paths = build_fixture(
            root,
            real_helpers,
            [printf_wire(json_bytes(expected))],
            bash,
        )
        environment["FAKE_RESPONSE_MARKER_SIZE"] = "9" * 1024
        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            "--socket=/tmp/anvil-marker-overflow",
            "--server-id=test",
        )
        reader = BinaryReader(
            process,
            paths["debug_log"],
            paths["bridge_stderr"],
            paths["helper_marker"],
            paths["dispatch_count"],
        )
        clean = False
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            original_pid = process.pid
            if process.stdin is None or process.stdout is None:
                raise AssertionError("bridge pipes are unavailable")
            pipe_ids = (
                os.fstat(process.stdin.fileno()).st_ino,
                os.fstat(process.stdout.fileno()).st_ino,
            )
            send(
                process,
                {"jsonrpc": "2.0", "id": 202, "method": "test"},
                framed=True,
            )
            wait_for_dispatch_complete(
                paths["dispatch_complete"],
                process,
                paths["dispatch_ack_fifo"],
                1,
            )
            read_reply(reader, expected, framed=True)
            assert_same_bridge(process, original_pid, pipe_ids)
            assert_no_helper(paths["helper_marker"])
            if "integer expression expected" in safe_text(paths["bridge_stderr"]):
                raise AssertionError("oversized marker reached Bash arithmetic")
            paths["dispatch_complete"].unlink()
            process.stdin.close()
            process.wait(timeout=5)
            if process.returncode != 0:
                raise AssertionError(reader.diagnostics())
            if list(paths["temp"].glob("anvil-mcp.*")):
                raise AssertionError("marker-overflow transaction survived EOF")
            clean = True
        finally:
            reader.close()
            if not clean:
                terminate_bridge(process)
            elif process.stdout is not None and not process.stdout.closed:
                process.stdout.close()


def run_large_request_metadata(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
) -> None:
    """Prove large and pipelined requests preserve framing and the same pipe."""
    with tempfile.TemporaryDirectory(prefix="anvil-stdio-large-request-") as raw_root:
        root = Path(raw_root)
        first = synthetic_dispatch_error("large|pipe", 70)
        second = {
            "jsonrpc": "2.0",
            "id": "second|pip",
            "result": "recovery-ok",
        }
        large_document = {
            "jsonrpc": "2.0",
            "id": "large|pipe",
            "method": "test",
            "params": {"raw": "雪" + ("x" * (512 * 1024))},
        }
        second_large_document = {
            "jsonrpc": "2.0",
            "id": "second|pip",
            "method": "test",
            "params": {"raw": "火" + ("y" * (512 * 1024))},
        }
        large_bytes = json_bytes(large_document)
        second_large_bytes = json_bytes(second_large_document)
        if len(second_large_bytes) != len(large_bytes):
            raise AssertionError("large ABA fixtures must have equal byte size")
        environment, paths = build_fixture(
            root,
            real_helpers,
            [
                r"\x7b\x00\x7d",
                printf_wire(json_bytes(second)),
            ],
            bash,
        )
        environment["ANVIL_MCP_FRAME_READ_TIMEOUT"] = "10"
        symlink_temp = root / "tmp-link"
        symlink_temp.symlink_to(paths["temp"], target_is_directory=True)
        environment["TMPDIR"] = str(symlink_temp)
        process = start_bridge(
            bash,
            stdio,
            environment,
            paths["bridge_stderr"],
            "--socket=/tmp/anvil-large-request-test",
            "--server-id=test",
        )
        reader = BinaryReader(
            process,
            paths["debug_log"],
            paths["bridge_stderr"],
            paths["helper_marker"],
            paths["dispatch_count"],
        )
        clean = False
        second_sender: threading.Thread | None = None
        second_send_errors: list[BaseException] = []
        captured_request: Path | None = None
        captured_stage: Path | None = None
        delayed_release_observed = False
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            original_pid = process.pid
            if process.stdin is None or process.stdout is None:
                raise AssertionError("bridge pipes are unavailable")
            pipe_ids = (
                os.fstat(process.stdin.fileno()).st_ino,
                os.fstat(process.stdout.fileno()).st_ino,
            )
            try:
                send(process, large_document, framed=True)

                def send_second() -> None:
                    try:
                        send(process, second_large_document, framed=True)
                    except BaseException as error:
                        second_send_errors.append(error)

                second_sender = threading.Thread(
                    target=send_second,
                    name="anvil-second-large-request",
                    daemon=True,
                )
                second_sender.start()
            except BrokenPipeError as error:
                raise AssertionError(reader.diagnostics()) from error

            def assert_staged_request() -> None:
                directories = list(paths["temp"].glob("anvil-mcp.*"))
                if len(directories) != 1:
                    raise AssertionError(
                        f"expected one private staging directory: {directories}"
                    )
                directory = directories[0]
                if stat.S_IMODE(directory.stat().st_mode) != 0o700:
                    raise AssertionError("request staging directory is not mode 0700")
                staged = directory / "request.1.json"
                if (
                    not staged.is_file()
                    or staged.is_symlink()
                    or stat.S_IMODE(staged.stat().st_mode) != 0o600
                    or staged.read_bytes() != large_bytes
                ):
                    raise AssertionError("first staged request is not exact")
                stages = list(directory.glob(".response-tmp.1.*"))
                if len(stages) != 1:
                    raise AssertionError(
                        f"missing unique first response stage: {stages}"
                    )
                response_stage = stages[0]
                response_stat = response_stage.lstat()
                if (
                    not stat.S_ISREG(response_stat.st_mode)
                    or response_stage.is_symlink()
                    or response_stat.st_size != 0
                    or response_stat.st_nlink != 1
                    or stat.S_IMODE(response_stat.st_mode) != 0o600
                ):
                    raise AssertionError("first response stage is not safe")
                for name in ("response.1.json", "proof.1.json"):
                    if (directory / name).exists():
                        raise AssertionError(f"premature response publication: {name}")
                # Simulate emacsclient returning before Emacs evaluates: leave
                # the full request path in place for Bash retirement.

            def assert_second_staged_request() -> None:
                nonlocal delayed_release_observed
                directories = list(paths["temp"].glob("anvil-mcp.*"))
                if len(directories) != 1:
                    raise AssertionError(
                        f"expected one private staging directory: {directories}"
                    )
                directory = directories[0]
                if (
                    captured_request.resolve()
                    != (directory / "request.1.json").resolve()
                ):
                    raise AssertionError("captured request path changed generation")
                if (
                    captured_stage.parent.resolve() != directory.resolve()
                    or not captured_stage.name.startswith(".response-tmp.1.")
                ):
                    raise AssertionError("captured response stage changed generation")
                # Releasing the actual generation-1 expression now begins with
                # this exact read.  Retirement makes it fail before deletion,
                # handler dispatch, or response publication can occur.
                try:
                    captured_request.read_bytes()
                except FileNotFoundError:
                    delayed_release_observed = True
                else:
                    raise AssertionError("retired generation remained readable")
                if captured_stage.exists():
                    raise AssertionError("retired response stage reappeared")
                for name in ("response.1.json", "proof.1.json"):
                    if (directory / name).exists():
                        raise AssertionError(f"retired publication survived: {name}")
                response_stages = list(directory.glob(".response-tmp.2.*"))
                if len(response_stages) != 1:
                    raise AssertionError(
                        f"missing unique second response stage: {response_stages}"
                    )
                names = sorted(child.name for child in directory.iterdir())
                expected_names = sorted(["request.2.json", response_stages[0].name])
                if names != expected_names:
                    raise AssertionError(
                        f"retired generation did not converge: {names}"
                    )
                staged = directory / "request.2.json"
                if (
                    staged.is_symlink()
                    or stat.S_IMODE(staged.stat().st_mode) != 0o600
                    or staged.read_bytes() != second_large_bytes
                ):
                    raise AssertionError("second staged request is not exact")
                response_stage = response_stages[0]
                response_stat = response_stage.lstat()
                if (
                    response_stage.is_symlink()
                    or response_stat.st_size != 0
                    or response_stat.st_nlink != 1
                    or stat.S_IMODE(response_stat.st_mode) != 0o600
                ):
                    raise AssertionError("second response stage is not safe")

            wait_for_dispatch_complete(
                paths["dispatch_complete"],
                process,
                paths["dispatch_ack_fifo"],
                1,
                assert_staged_request,
            )
            read_reply(reader, first, framed=True)
            assert_no_helper(paths["helper_marker"])
            captured_request, captured_stage = captured_generation_paths(
                paths["captured_expression"],
                1,
            )
            paths["dispatch_complete"].unlink()
            assert_same_bridge(process, original_pid, pipe_ids)
            if second_sender is None:
                raise AssertionError("second large-request sender did not start")
            second_sender.join(timeout=10)
            if second_sender.is_alive():
                raise AssertionError("second large-request write stayed blocked")
            if second_send_errors:
                raise AssertionError(reader.diagnostics()) from second_send_errors[0]
            second_sender = None

            wait_for_dispatch_complete(
                paths["dispatch_complete"],
                process,
                paths["dispatch_ack_fifo"],
                2,
                assert_second_staged_request,
            )
            read_reply(reader, second, framed=True)
            assert_no_helper(paths["helper_marker"])
            paths["dispatch_complete"].unlink()
            assert_same_bridge(process, original_pid, pipe_ids)
            if read_count(paths["dispatch_count"]) != 2:
                raise AssertionError("large request was replayed")
            if not delayed_release_observed:
                raise AssertionError("captured generation was never released")

            process.stdin.close()
            process.wait(timeout=5)
            if process.returncode != 0:
                raise AssertionError(reader.diagnostics())
            if list(paths["temp"].glob("anvil-mcp.*")):
                raise AssertionError("large-request transaction survived EOF")
            if not wait_until(lambda: not process_group_alive(process.pid), 2):
                raise AssertionError("large-request process group survived exit")
            clean = True
        finally:
            reader.close()
            if not clean:
                terminate_bridge(process)
            if second_sender is not None:
                second_sender.join(timeout=2)
            if clean:
                for stream in (process.stdout,):
                    if stream is not None and not stream.closed:
                        stream.close()


def main() -> int:
    """Run negative and positive regressions with an explicit Bash."""
    if len(sys.argv) not in (3, 5):
        raise SystemExit(
            f"usage: {Path(sys.argv[0]).name} "
            "ANVIL_STDIO BASH [PARENT_GUARD GUARD_PYTHON]"
        )
    stdio = Path(sys.argv[1]).resolve()
    bash = str(Path(sys.argv[2]).resolve())
    parent_guard = Path(sys.argv[3]).resolve() if len(sys.argv) == 5 else None
    parent_guard_python = (
        str(Path(sys.argv[4]).resolve()) if len(sys.argv) == 5 else None
    )
    if not stdio.is_file():
        raise SystemExit(f"not a file: {stdio}")
    if not Path(bash).is_file():
        raise SystemExit(f"not a file: {bash}")
    if parent_guard is not None and not parent_guard.is_file():
        raise SystemExit(f"not a file: {parent_guard}")
    if parent_guard_python is not None and not Path(parent_guard_python).is_file():
        raise SystemExit(f"not a file: {parent_guard_python}")

    run_bridge_reap_budget_regression()
    run_cleanup_rescan_regression(stdio)
    run_fake_readiness_fast_path_regression(bash)
    run_dispatch_observer_reply_regression()

    real_helpers: dict[str, str] = {}
    for name in HELPER_NAMES:
        program = shutil.which(name)
        if program is None:
            raise AssertionError(f"required helper is unavailable: {name}")
        real_helpers[name] = program

    run_helper_self_expiry(bash, real_helpers)
    run_negative_control(stdio, bash, real_helpers)
    run_nonfinite_identifier(stdio, bash, real_helpers)
    run_predispatch_freeze(stdio, bash, real_helpers)
    run_guard_loader_owner_death(
        stdio,
        bash,
        real_helpers,
        parent_guard,
        parent_guard_python,
    )
    run_owner_death_case(
        stdio,
        bash,
        real_helpers,
        parent_guard,
        parent_guard_python,
        guarded=False,
    )
    run_owner_death_case(
        stdio,
        bash,
        real_helpers,
        parent_guard,
        parent_guard_python,
        guarded=True,
    )
    run_owner_death_case(
        stdio,
        bash,
        real_helpers,
        parent_guard,
        parent_guard_python,
        guarded=True,
        pid_only=True,
    )
    run_runner_death_recovery(
        stdio,
        bash,
        real_helpers,
        parent_guard,
        parent_guard_python,
    )
    run_default_parse_budget(stdio, bash, real_helpers)
    run_idle_then_partial_first_line(stdio, bash, real_helpers)
    run_nul_wire_rejection(stdio, bash, real_helpers)
    run_stalled_frame_header(stdio, bash, real_helpers)
    run_truncated_frame(stdio, bash, real_helpers)
    run_cumulative_frame_budget(stdio, bash, real_helpers)
    if parent_guard is not None:
        run_cumulative_frame_budget(
            stdio,
            bash,
            real_helpers,
            parent_guard,
            parent_guard_python,
        )
    run_response_prepare_interruption(stdio, bash, real_helpers)
    run_response_fd_validation_status_preserved(stdio, bash, real_helpers)
    run_response_link_capability_failure(stdio, bash, real_helpers)
    run_competitor_inode_rejection(stdio, bash, real_helpers)
    run_request_symlink_retirement(stdio, bash, real_helpers)
    run_oversized_marker(stdio, bash, real_helpers)
    run_large_request_metadata(stdio, bash, real_helpers)
    run_positive(stdio, bash, real_helpers)
    print(f"stdio-postdispatch-ok bash={bash}")
    return 0


def handle_term(signum: int, _frame: object) -> None:
    """Turn an outer timeout into normal unwinding and child cleanup."""
    raise SystemExit(128 + signum)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, handle_term)
    raise SystemExit(main())
