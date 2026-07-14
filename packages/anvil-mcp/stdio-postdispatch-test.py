#!/usr/bin/env python3
"""Regress bridge-side freezes after a successful stateful dispatch."""

from __future__ import annotations

import base64
import errno
import json
import os
from pathlib import Path
import selectors
import shutil
import shlex
import signal
import stat
import subprocess
import sys
import tempfile
import time


REPLY_TIMEOUT_SECONDS = 3.0
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


def percent_wire(payload: bytes) -> str:
    """Encode PAYLOAD for anvil-stdio's process-free response wire."""
    return "".join(f"%{byte:02x}" for byte in payload)


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
    """Create a builtin-only Bash emacsclient with controlled responses."""
    source = r"""#!__BASH__
set -u

if [[ -n ${ALTERNATE_EDITOR+x} ]]; then
    printf 'ALTERNATE_EDITOR leaked into emacsclient\n' >&2
    exit 78
fi

bump() {
    local path=$1
    local value=0
    if [[ -r "$path" ]]; then
        IFS= read -r value < "$path" || :
    fi
    value=$((value + 1))
    printf '%s' "$value" > "$path"
    BUMP_VALUE=$value
}

expression=${!#}
case "$expression" in
    t)
        bump "$FAKE_PROBE_COUNT"
        printf 't\n'
        ;;
    '(test-init)')
        bump "$FAKE_INIT_COUNT"
        printf 't\n'
        ;;
    '(test-stop)')
        bump "$FAKE_STOP_COUNT"
        printf 't\n'
        ;;
    *)
        bump "$FAKE_DISPATCH_COUNT"
        index=$((BUMP_VALUE - 1))
        case "$index" in
            0) wire=$FAKE_RESPONSE_WIRE_0 ;;
            1) wire=$FAKE_RESPONSE_WIRE_1 ;;
            2) wire=$FAKE_RESPONSE_WIRE_2 ;;
            *)
                printf 'unexpected duplicate dispatch\n' >&2
                exit 64
                ;;
        esac
        printf '%s' "$BUMP_VALUE" > "$FAKE_DISPATCH_COMPLETE"
        IFS= read -r _ < "$FAKE_DISPATCH_ACK_FIFO"
        if [[ "$index" -eq 1 ]]; then
            printf 'captured-stderr-%s' "$FAKE_CAPTURED_STDERR" >&2
        fi
        if [[ "$index" -eq 2 ]]; then
            cut=$((${#wire} / 2))
            printf '"%s\r\n*ERROR*: Unknown message: %s"\r\n' \
                "${wire:0:cut}" "${wire:cut}"
        else
            printf '"%s"\n' "$wire"
        fi
        ;;
esac
""".replace("__BASH__", bash)
    make_executable(path, source)


def write_helper_wrapper(
    path: Path,
    bash: str,
    name: str,
    real_helper: str,
) -> None:
    """Forward before dispatch; otherwise record and block on a FIFO."""
    source = r"""#!__BASH__
set -u
if [[ -e "$FAKE_DISPATCH_COMPLETE" ]]; then
    printf '{"pid":%s,"program":"__NAME__"}\n' "$$" \
        > "$FAKE_POSTDISPATCH_HELPER"
    IFS= read -r _ < "$FAKE_HELPER_BLOCK_FIFO"
    exit 125
fi
exec __REAL_HELPER__ "$@"
"""
    source = source.replace("__BASH__", bash)
    source = source.replace("__NAME__", name)
    source = source.replace("__REAL_HELPER__", shlex.quote(real_helper))
    make_executable(path, source)


def write_blocking_predispatch_wrapper(path: Path, bash: str, name: str) -> None:
    """Create a builtin-only helper that simulates a loader-frozen child."""
    source = r"""#!__BASH__
set -u
printf '{"pid":%s,"program":"__NAME__"}\n' "$$" \
    > "$FAKE_PREDISPATCH_MARKER"
IFS= read -r _ < "$FAKE_PREDISPATCH_BLOCK_FIFO"
exit 125
"""
    source = source.replace("__BASH__", bash)
    source = source.replace("__NAME__", name)
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
__SLEEP__ 3
exec __PYTHON__ "$@"
"""
    source = source.replace("__BASH__", bash)
    source = source.replace("__SLEEP__", shlex.quote(real_sleep))
    source = source.replace("__PYTHON__", shlex.quote(real_python))
    make_executable(path, source)


def write_owner_blocking_emacsclient(path: Path, bash: str) -> None:
    """Create an emacsclient that publishes its PID, then blocks."""
    source = r"""#!__BASH__
set -u

expression=${!#}
if [[ "$expression" == t ]]; then
    printf 't\n'
    exit 0
fi

value=0
if [[ -r "$FAKE_OWNER_DISPATCH_COUNT" ]]; then
    IFS= read -r value < "$FAKE_OWNER_DISPATCH_COUNT" || :
fi
value=$((value + 1))
printf '%s' "$value" > "$FAKE_OWNER_DISPATCH_COUNT"
printf '{"pid":%s,"parent":%s}\n' "$$" "$PPID" \
    > "$FAKE_OWNER_CHILD_MARKER"
IFS= read -r _ < "$FAKE_OWNER_BLOCK_FIFO"
exit 125
""".replace("__BASH__", bash)
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


def watch_processes(root, target):
    if sys.platform.startswith("linux"):
        root_fd = os.pidfd_open(root, 0)
        target_fd = os.pidfd_open(target, 0)
        poller = select.poll()
        poller.register(root_fd, select.POLLIN)
        poller.register(target_fd, select.POLLIN)
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
        ]
        queue.control(changes, 0, 0)
        while True:
            events = queue.control(None, 2, None)
            if any(event.ident == target for event in events):
                try:
                    os.killpg(target, signal.SIGKILL)
                except OSError:
                    pass
                return
            if any(event.ident == root for event in events):
                kill_live_target(target)
                return
    raise RuntimeError(f"unsupported platform: {sys.platform}")


if len(sys.argv) < 3 or sys.argv[1] != "group":
    raise SystemExit(70)
raw_parent = os.environ.pop("ANVIL_HEADLESS_PARENT_PID", "")
if not raw_parent.isascii() or not raw_parent.isdecimal():
    raise SystemExit(70)
root_pid = int(raw_parent)
if root_pid <= 1 or os.getppid() != root_pid:
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
        watch_processes(root_pid, target_pid)
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
            "FAKE_PROBE_COUNT": str(paths["probe_count"]),
            "FAKE_INIT_COUNT": str(paths["init_count"]),
            "FAKE_STOP_COUNT": str(paths["stop_count"]),
            "FAKE_RESPONSE_WIRE_0": wires[0],
            "FAKE_RESPONSE_WIRE_1": wires[1] if len(wires) > 1 else "",
            "FAKE_RESPONSE_WIRE_2": wires[2] if len(wires) > 2 else "",
            "FAKE_CAPTURED_STDERR": "x" * 8192,
            "EMACS_MCP_DEBUG_LOG": str(paths["debug_log"]),
            "ANVIL_EMACSCLIENT_PROBE_TIMEOUT": "5",
            "ANVIL_EMACSCLIENT_READINESS_TIMEOUT": "10",
            "ANVIL_EMACSCLIENT_STARTUP_DISPATCH_TIMEOUT": "5",
            "ANVIL_EMACSCLIENT_DISPATCH_TIMEOUT": "5",
            "ANVIL_EMACSCLIENT_KILL_AFTER_TIMEOUT": "1",
            "ANVIL_MCP_REQUEST_PARSE_TIMEOUT": "10",
            "ANVIL_MCP_FRAME_READ_TIMEOUT": "2",
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
    timeout_seconds: float = REPLY_TIMEOUT_SECONDS,
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
) -> subprocess.Popen[bytes]:
    """Start one bridge in an isolated process group."""
    options: dict[str, object] = {}
    if os.name == "posix":
        options["start_new_session"] = True
    stderr_handle = bridge_stderr.open("wb")
    try:
        return subprocess.Popen(
            [bash, str(bridge), *arguments],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=stderr_handle,
            bufsize=0,
            env=environment,
            **options,
        )
    finally:
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
    timeout: float = 15.0,
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


def wait_for_dispatch_complete(
    marker: Path,
    process: subprocess.Popen[bytes],
    ack_fifo: Path,
    expected: int,
    before_release: object | None = None,
    timeout: float = 15.0,
) -> None:
    """Wait for dispatch, inject races, then release the fake client."""
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
                        raise AssertionError(
                            "bridge exited before dispatch acknowledgement"
                        ) from error
                    time.sleep(0.01)
                    continue
                try:
                    os.write(descriptor, b"go\n")
                finally:
                    os.close(descriptor)
                return
            raise AssertionError("fake client did not open acknowledgement FIFO")
        if process.poll() is not None:
            raise AssertionError("bridge exited before dispatch completed")
        time.sleep(0.02)
    raise AssertionError(f"stateful dispatch exceeded {timeout:.1f}s")


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
            [percent_wire(json_bytes(expected))],
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
            [percent_wire(json_bytes(expected))],
            bash,
        )
        environment["ANVIL_MCP_REQUEST_PARSE_TIMEOUT"] = "5"
        python_wrapper = paths["binary"] / "python3"
        write_blocking_predispatch_wrapper(python_wrapper, bash, "python3")
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
            if not wait_until(paths["predispatch_marker"].is_file, 5):
                raise AssertionError("frozen pre-dispatch helper did not start")
            marker = json.loads(paths["predispatch_marker"].read_text(encoding="utf-8"))
            frozen_pid = int(marker["pid"])
            read_reply(
                reader,
                synthetic_parse_runner_error(124),
                framed=False,
                timeout_seconds=7,
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
            [percent_wire(json_bytes(expected))],
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
            [percent_wire(json_bytes({"unused": True}))],
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
            if not wait_until(loader_marker.is_file, 5):
                raise AssertionError(
                    "guard interpreter did not freeze before readiness: "
                    f"{safe_text(paths['bridge_stderr'])}"
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
) -> None:
    """Contrast the historical helper leak with guarded owner cleanup."""
    if os.name != "posix":
        return
    label = "guarded" if guarded else "unguarded"
    with tempfile.TemporaryDirectory(prefix=f"anvil-stdio-owner-{label}-") as raw_root:
        root = Path(raw_root)
        environment, paths = build_fixture(
            root,
            real_helpers,
            [percent_wire(json_bytes({"unused": True}))],
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
        )
        child_pid: int | None = None
        child_group: int | None = None
        try:
            wait_for_bridge_ready(paths["debug_log"], process)
            send(
                process,
                {"jsonrpc": "2.0", "id": 61, "method": "test"},
            )
            if not wait_until(child_marker.is_file, 5):
                raise AssertionError(
                    f"{label} dispatch did not enter the blocking client"
                )
            marker = json.loads(child_marker.read_text(encoding="utf-8"))
            child_pid = int(marker["pid"])
            child_group = os.getpgid(child_pid)
            if child_group != child_pid:
                raise AssertionError(
                    f"{label} client is not its process-group leader: "
                    f"pid={child_pid} pgid={child_group}"
                )
            if read_count(child_count) != 1:
                raise AssertionError(f"{label} request was not dispatched once")

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
            [percent_wire(json_bytes(expected))],
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
                [percent_wire(json_bytes({"unused": True}))],
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


def run_cumulative_frame_budget(
    stdio: Path,
    bash: str,
    real_helpers: dict[str, str],
    parent_guard: Path | None = None,
    parent_guard_python: str | None = None,
) -> None:
    """Prove headers and body consume one guarded absolute frame deadline."""
    guarded = parent_guard is not None
    suffix = "guarded" if guarded else "plain"
    with tempfile.TemporaryDirectory(
        prefix=f"anvil-stdio-frame-budget-{suffix}-"
    ) as raw_root:
        root = Path(raw_root)
        environment, paths = build_fixture(
            root,
            real_helpers,
            [percent_wire(json_bytes({"unused": True}))],
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
                raise AssertionError("cumulative frame never entered the body reader")
            if read_count(paths["dispatch_count"]) != 0:
                raise AssertionError(
                    "incomplete cumulative frame reached stateful Emacs"
                )
            if not wait_until(lambda: not process_group_alive(process.pid), 2):
                raise AssertionError("cumulative-frame bridge group survived exit")
        finally:
            terminate_bridge(process)


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
            [percent_wire(json_bytes({"unused": True}))],
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
            [percent_wire(json_bytes({"unused": True}))],
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
        metadata = f"request|0|{base64.b64encode(request_bytes).decode('ascii')}|91"

        vulnerable = root / "anvil-stdio-vulnerable.sh"
        source = stdio.read_text(encoding="utf-8")
        needle = '\tanvil_mcp_capture_finish\n\tif [ "$_anvil_client_rc" -ne 0 ]; then'
        injected = (
            "\tanvil_mcp_capture_finish\n"
            "\tgrep -c '\\*ERROR\\*' /dev/null >/dev/null\n"
            '\tif [ "$_anvil_client_rc" -ne 0 ]; then'
        )
        if source.count(needle) != 1:
            raise AssertionError("negative-control injection point drifted")
        metadata_anchor = "# Emit a correlated at-most-once error."
        if source.count(metadata_anchor) != 1:
            raise AssertionError("metadata override injection point drifted")
        metadata_override = (
            "anvil_mcp_request_metadata() {\n"
            f"\tprintf '%s' {shlex.quote(metadata)}\n"
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
            [percent_wire(json_bytes(expected))],
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
                read_reply(reader, expected, framed=False)
            except AssertionError:
                pass
            else:
                raise AssertionError(
                    "negative control unexpectedly returned a response"
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
        if len(percent_wire(third_bytes)) <= 49_152:
            raise AssertionError("framed fixture does not cross a decoder chunk")

        environment, paths = build_fixture(
            root,
            real_helpers,
            [
                percent_wire(json_bytes(first)),
                "%7b%00%7d",
                percent_wire(third_bytes),
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

    real_helpers: dict[str, str] = {}
    for name in HELPER_NAMES:
        program = shutil.which(name)
        if program is None:
            raise AssertionError(f"required helper is unavailable: {name}")
        real_helpers[name] = program

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
    run_runner_death_recovery(
        stdio,
        bash,
        real_helpers,
        parent_guard,
        parent_guard_python,
    )
    run_default_parse_budget(stdio, bash, real_helpers)
    run_idle_then_partial_first_line(stdio, bash, real_helpers)
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
    run_positive(stdio, bash, real_helpers)
    print(f"stdio-postdispatch-ok bash={bash}")
    return 0


def handle_term(signum: int, _frame: object) -> None:
    """Turn an outer timeout into normal unwinding and child cleanup."""
    raise SystemExit(128 + signum)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, handle_term)
    raise SystemExit(main())
