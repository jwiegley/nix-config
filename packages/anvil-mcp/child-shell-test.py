#!/usr/bin/env python3
"""Exercise the direct-Python dedicated child-shell trampoline."""

from __future__ import annotations

import json
import os
from pathlib import Path
import select
import shlex
import signal
import stat
import subprocess
import sys
import tempfile
import time


EXIT_SOFTWARE = 70
COLD_START_TIMEOUT_SECONDS = 60
MAX_LAUNCH_SECONDS = 4.0
LATENCY_RUNS = 8
DESCENDANT_READY_TIMEOUT_SECONDS = 10.0
DESCENDANT_EXIT_TIMEOUT_SECONDS = 5.0


class ProcessExitWatcher:
    """Wait for one exact process to exit without confusing PID reuse."""

    def __init__(self, pid: int) -> None:
        self.pid = pid
        self.pidfd: int | None = None
        self.queue: select.kqueue | None = None
        self.already_gone = False
        if sys.platform.startswith("linux"):
            try:
                self.pidfd = os.pidfd_open(pid, 0)
            except ProcessLookupError:
                self.already_gone = True
        elif sys.platform == "darwin":
            self.queue = select.kqueue()
            change = select.kevent(
                pid,
                filter=select.KQ_FILTER_PROC,
                flags=select.KQ_EV_ADD | select.KQ_EV_ENABLE,
                fflags=select.KQ_NOTE_EXIT,
            )
            try:
                self.queue.control([change], 0, 0)
            except ProcessLookupError:
                self.already_gone = True
                self.queue.close()
                self.queue = None
        else:
            raise AssertionError(f"unsupported watcher platform: {sys.platform}")

    def wait(self, timeout: float) -> bool:
        """Return whether the watched process exited within TIMEOUT."""
        if self.already_gone:
            return True
        if self.pidfd is not None:
            readable, _, _ = select.select([self.pidfd], [], [], timeout)
            return bool(readable)
        assert self.queue is not None
        return bool(self.queue.control(None, 1, timeout))

    def close(self) -> None:
        """Release the platform watcher."""
        if self.pidfd is not None:
            os.close(self.pidfd)
            self.pidfd = None
        if self.queue is not None:
            self.queue.close()
            self.queue = None


def write_probe(path: Path) -> None:
    """Create a target that reports argv, environment, and guarded FDs."""
    path.write_text(
        f"""#!{sys.executable}
import errno
import json
import os
import sys


def closed(descriptor):
    try:
        os.fstat(descriptor)
    except OSError as error:
        return error.errno == errno.EBADF
    return False


print(json.dumps(
    {{
        "argv": sys.argv,
        "parent_pid": os.environ.get("ANVIL_HEADLESS_PARENT_PID"),
        "real_shell": os.environ.get("ANVIL_HEADLESS_REAL_SHELL"),
        "sentinel": os.environ.get("ANVIL_CHILD_SENTINEL"),
        "fd8_closed": closed(8),
        "fd9_closed": closed(9),
    }},
    separators=(",", ":"),
))
""",
        encoding="utf-8",
    )
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def run_launcher(
    launcher: Path,
    probe: Path,
    command: str,
) -> tuple[subprocess.CompletedProcess[str], float]:
    """Run LAUNCHER with lock descriptors deliberately inherited."""
    environment = os.environ.copy()
    environment.update(
        {
            "ANVIL_HEADLESS_PARENT_PID": str(os.getpid()),
            "ANVIL_HEADLESS_REAL_SHELL": str(probe),
            "ANVIL_CHILD_SENTINEL": "preserved",
        }
    )
    read_fd, write_fd = os.pipe()

    def expose_lock_descriptors() -> None:
        os.dup2(read_fd, 8, inheritable=True)
        os.dup2(write_fd, 9, inheritable=True)

    started = time.monotonic()
    try:
        completed = subprocess.run(
            [str(launcher), "-c", command],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            text=True,
            timeout=5,
            check=False,
            pass_fds=(read_fd, write_fd),
            preexec_fn=expose_lock_descriptors,
        )
    finally:
        os.close(read_fd)
        os.close(write_fd)
    return completed, time.monotonic() - started


def decode_probe(
    completed: subprocess.CompletedProcess[str],
    probe: Path,
    command: str,
) -> None:
    """Require one successful, sanitized handoff to PROBE."""
    if completed.returncode != 0:
        raise AssertionError(
            f"child launcher failed: rc={completed.returncode} "
            f"stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )
    if completed.stderr:
        raise AssertionError(f"child launcher wrote stderr: {completed.stderr!r}")
    payload = json.loads(completed.stdout)
    expected_argv = [str(probe), "-c", command]
    if payload.get("argv") != expected_argv:
        raise AssertionError(f"wrong child argv: {payload!r}")
    expected = {
        "parent_pid": None,
        "real_shell": None,
        "sentinel": "preserved",
        "fd8_closed": True,
        "fd9_closed": True,
    }
    for key, value in expected.items():
        if payload.get(key) != value:
            raise AssertionError(f"wrong {key}: {payload!r}")


def assert_committed_group_survives_leader_exit(
    guard: Path,
) -> None:
    """Prove committed cleanup survives a dead and reaped group leader."""
    with tempfile.TemporaryDirectory(prefix="anvil-guard-commit-") as raw:
        directory = Path(raw)
        instrumented_guard = directory / "guard.py"
        target_marker = directory / "target-pids"
        reaped_marker = directory / "leader-reaped"
        signal_marker = directory / "guard-signal"
        diagnostic = directory / "stderr"
        descendant_hold = directory / "descendant-hold"
        owner_hold = directory / "owner-hold"
        guard_release = directory / "guard-release"
        os.mkfifo(descendant_hold, 0o600)
        os.mkfifo(owner_hold, 0o600)
        os.mkfifo(guard_release, 0o600)
        descendant_hold_fd = os.open(
            descendant_hold,
            os.O_RDWR | os.O_NONBLOCK,
        )
        owner_hold_fd = os.open(owner_hold, os.O_RDWR | os.O_NONBLOCK)
        guard_release_fd = os.open(
            guard_release,
            os.O_RDWR | os.O_NONBLOCK,
        )

        source = guard.read_text(encoding="utf-8")
        constant = "READY_TIMEOUT_SECONDS = 5.0\n"
        if source.count(constant) != 1:
            raise AssertionError("parent guard readiness constant drifted")
        helper = """
TEST_SIGNAL_MARKER = os.environ.get("ANVIL_TEST_SIGNAL_MARKER", "")
TEST_SIGNAL_RELEASE = os.environ.get("ANVIL_TEST_SIGNAL_RELEASE", "")


def test_guard_signal_barrier():
    if not TEST_SIGNAL_MARKER or not TEST_SIGNAL_RELEASE:
        return
    marker_fd = os.open(
        TEST_SIGNAL_MARKER,
        os.O_WRONLY | os.O_CREAT | os.O_TRUNC,
        0o600,
    )
    try:
        os.write(marker_fd, b"signal")
    finally:
        os.close(marker_fd)
    release_fd = os.open(TEST_SIGNAL_RELEASE, os.O_RDONLY)
    try:
        os.read(release_fd, 1)
    finally:
        os.close(release_fd)
"""
        source = source.replace(constant, constant + helper, 1)
        handler_prefix = "    def stop_guard(_signum, _frame):\n"
        handler_calls = (
            "        terminate_target(target_pid, group, state)",
            "        terminate_target(target_pid, group)",
        )
        handler_call = next(
            (
                call
                for call in handler_calls
                if source.count(handler_prefix + call) == 1
            ),
            None,
        )
        if handler_call is None:
            raise AssertionError("parent guard signal handler drifted")
        source = source.replace(
            handler_prefix + handler_call,
            handler_prefix + "        test_guard_signal_barrier()\n" + handler_call,
            1,
        )
        exec_anchor = "try:\n    os.execvpe(program_argv[0], program_argv, os.environ)"
        if source.count(exec_anchor) != 1:
            raise AssertionError("parent guard exec point drifted")
        source = source.replace(
            exec_anchor,
            'os.environ["ANVIL_TEST_MONITOR_PID"] = str(guard_pid)\n\n' + exec_anchor,
            1,
        )
        instrumented_guard.write_text(source, encoding="utf-8")

        target = directory / "target.py"
        target.write_text(
            """import os
import signal
import sys

marker, hold = sys.argv[1:]
guard = int(os.environ["ANVIL_TEST_MONITOR_PID"])
descendant = os.fork()
if descendant == 0:
    descriptor = os.open(hold, os.O_RDONLY)
    try:
        os.read(descriptor, 1)
    finally:
        os.close(descriptor)
    os._exit(0)

with open(marker, "w", encoding="utf-8") as handle:
    handle.write(f"{os.getpid()} {descendant} {guard}\\n")
while True:
    signal.pause()
""",
            encoding="utf-8",
        )

        owner_pid = os.fork()
        if owner_pid == 0:
            environment = os.environ.copy()
            environment.update(
                {
                    "ANVIL_HEADLESS_PARENT_PID": str(os.getpid()),
                    "ANVIL_TEST_SIGNAL_MARKER": str(signal_marker),
                    "ANVIL_TEST_SIGNAL_RELEASE": str(guard_release),
                }
            )
            try:
                with diagnostic.open("w", encoding="utf-8") as stderr:
                    process = subprocess.Popen(
                        [
                            sys.executable,
                            "-I",
                            str(instrumented_guard),
                            "external-group",
                            sys.executable,
                            "-I",
                            str(target),
                            str(target_marker),
                            str(descendant_hold),
                        ],
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL,
                        stderr=stderr,
                        env=environment,
                    )
                    returncode = process.wait()
                reaped_marker.write_text(str(returncode), encoding="utf-8")
                with owner_hold.open("rb", buffering=0) as stream:
                    stream.read(1)
                os._exit(0)
            except BaseException:
                os._exit(EXIT_SOFTWARE)

        owner_reaped = False
        leader_pid: int | None = None
        descendant_pid: int | None = None
        guard_pid: int | None = None
        leader_watcher: ProcessExitWatcher | None = None
        descendant_watcher: ProcessExitWatcher | None = None
        guard_watcher: ProcessExitWatcher | None = None
        group_exited = False
        try:
            deadline = time.monotonic() + DESCENDANT_READY_TIMEOUT_SECONDS
            while not target_marker.exists() and time.monotonic() < deadline:
                waited, _status = os.waitpid(owner_pid, os.WNOHANG)
                if waited == owner_pid:
                    owner_reaped = True
                    break
                time.sleep(0.02)
            if not target_marker.exists():
                details = (
                    diagnostic.read_text(encoding="utf-8")
                    if diagnostic.exists()
                    else ""
                )
                raise AssertionError(
                    f"committed group never became ready; stderr={details!r}"
                )

            target_fields = target_marker.read_text(encoding="utf-8").split()
            if len(target_fields) != 3 or not all(
                field.isdecimal() for field in target_fields
            ):
                raise AssertionError(
                    f"invalid committed-group marker: {target_fields!r}"
                )
            leader_pid, descendant_pid, guard_pid = map(int, target_fields)
            if len({guard_pid, leader_pid, descendant_pid}) != 3:
                raise AssertionError("committed group identities are not distinct")
            if os.getpgid(leader_pid) != leader_pid:
                raise AssertionError("target is not the committed group leader")
            if os.getpgid(descendant_pid) != leader_pid:
                raise AssertionError("descendant escaped the committed group")

            leader_watcher = ProcessExitWatcher(leader_pid)
            descendant_watcher = ProcessExitWatcher(descendant_pid)
            guard_watcher = ProcessExitWatcher(guard_pid)
            os.kill(guard_pid, signal.SIGTERM)
            deadline = time.monotonic() + DESCENDANT_EXIT_TIMEOUT_SECONDS
            while not signal_marker.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            if not signal_marker.exists():
                raise AssertionError("guard signal handler did not reach its barrier")

            os.kill(leader_pid, signal.SIGKILL)
            if not leader_watcher.wait(DESCENDANT_EXIT_TIMEOUT_SECONDS):
                raise AssertionError("committed group leader did not exit")

            deadline = time.monotonic() + DESCENDANT_EXIT_TIMEOUT_SECONDS
            while not reaped_marker.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            if not reaped_marker.exists():
                raise AssertionError("owner did not reap the committed group leader")
            if descendant_watcher.wait(0):
                raise AssertionError("descendant exited before committed cleanup")

            os.kill(owner_pid, signal.SIGKILL)
            os.waitpid(owner_pid, 0)
            owner_reaped = True
            os.write(guard_release_fd, b"release")
            if not descendant_watcher.wait(DESCENDANT_EXIT_TIMEOUT_SECONDS):
                raise AssertionError(
                    "committed descendant survived reaped-leader cleanup"
                )
            if not guard_watcher.wait(DESCENDANT_EXIT_TIMEOUT_SECONDS):
                raise AssertionError("committed guard survived group cleanup")
            group_exited = True
        finally:
            if not owner_reaped:
                try:
                    os.kill(owner_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    os.waitpid(owner_pid, 0)
                except ChildProcessError:
                    pass
            if not group_exited and leader_pid is not None:
                try:
                    os.killpg(leader_pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
            for watcher in (leader_watcher, descendant_watcher, guard_watcher):
                if watcher is not None:
                    watcher.close()
            os.close(descendant_hold_fd)
            os.close(owner_hold_fd)
            os.close(guard_release_fd)


def assert_parent_death_reaps_descendant(
    launcher: Path,
    real_shell: Path,
) -> None:
    """Prove abrupt root death kills the shell's complete process group."""
    with tempfile.TemporaryDirectory(prefix="anvil-child-reap-") as raw:
        directory = Path(raw)
        marker = directory / "pids"
        diagnostic = directory / "stderr"
        hold = directory / "hold"
        os.mkfifo(hold, 0o600)
        hold_fd = os.open(hold, os.O_RDWR | os.O_NONBLOCK)
        blocked_read = f"IFS= read -r _ < {shlex.quote(str(hold))}"
        command = (
            f"{shlex.quote(str(real_shell))} -c "
            f"{shlex.quote(blocked_read)} & descendant=$!; "
            f'printf \'%s %s\\n\' "$$" "$descendant" > '
            f"{shlex.quote(str(marker))}; "
            f"{blocked_read}"
        )
        root_pid = os.fork()
        if root_pid == 0:
            environment = os.environ.copy()
            environment.update(
                {
                    "ANVIL_HEADLESS_PARENT_PID": str(os.getpid()),
                    "ANVIL_HEADLESS_REAL_SHELL": str(real_shell),
                }
            )
            try:
                with diagnostic.open("w", encoding="utf-8") as stderr:
                    completed = subprocess.run(
                        [str(launcher), "-c", command],
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL,
                        stderr=stderr,
                        env=environment,
                        check=False,
                    )
                os._exit(completed.returncode if completed.returncode >= 0 else 1)
            except BaseException:
                os._exit(EXIT_SOFTWARE)

        root_reaped = False
        shell_pid: int | None = None
        descendant_pid: int | None = None
        shell_watcher: ProcessExitWatcher | None = None
        descendant_watcher: ProcessExitWatcher | None = None
        group_exited = False
        try:
            deadline = time.monotonic() + DESCENDANT_READY_TIMEOUT_SECONDS
            while not marker.exists() and time.monotonic() < deadline:
                waited, _status = os.waitpid(root_pid, os.WNOHANG)
                if waited == root_pid:
                    root_reaped = True
                    break
                time.sleep(0.02)
            if not marker.exists():
                details = (
                    diagnostic.read_text(encoding="utf-8")
                    if diagnostic.exists()
                    else ""
                )
                raise AssertionError(
                    "guarded shell never published its process group; "
                    f"stderr={details!r}"
                )

            fields = marker.read_text(encoding="utf-8").split()
            if len(fields) != 2 or not all(field.isdecimal() for field in fields):
                raise AssertionError(f"invalid process marker: {fields!r}")
            shell_pid, descendant_pid = map(int, fields)
            if shell_pid <= 1 or descendant_pid <= 1 or shell_pid == descendant_pid:
                raise AssertionError(
                    f"invalid shell process group: {shell_pid}, {descendant_pid}"
                )
            if os.getpgid(shell_pid) != shell_pid:
                raise AssertionError("guarded shell is not its process-group leader")
            if os.getpgid(descendant_pid) != shell_pid:
                raise AssertionError("background descendant escaped the shell group")

            shell_watcher = ProcessExitWatcher(shell_pid)
            descendant_watcher = ProcessExitWatcher(descendant_pid)
            os.kill(root_pid, signal.SIGKILL)
            os.waitpid(root_pid, 0)
            root_reaped = True
            if not shell_watcher.wait(DESCENDANT_EXIT_TIMEOUT_SECONDS):
                raise AssertionError(f"guarded shell {shell_pid} survived root death")
            if not descendant_watcher.wait(DESCENDANT_EXIT_TIMEOUT_SECONDS):
                raise AssertionError(
                    f"background descendant {descendant_pid} survived root death"
                )
            group_exited = True
        finally:
            if not root_reaped:
                try:
                    os.kill(root_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    os.waitpid(root_pid, 0)
                except ChildProcessError:
                    pass
            if not group_exited and shell_pid is not None:
                try:
                    os.killpg(shell_pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
            if shell_watcher is not None:
                shell_watcher.close()
            if descendant_watcher is not None:
                descendant_watcher.close()
            os.close(hold_fd)


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(
            f"usage: {Path(sys.argv[0]).name} CHILD_LAUNCHER PARENT_GUARD REAL_SHELL"
        )
    launcher = Path(sys.argv[1]).resolve()
    guard = Path(sys.argv[2]).resolve()
    real_shell = Path(sys.argv[3]).resolve()
    source = launcher.read_text(encoding="utf-8")
    if not source.startswith("#!") or not source.splitlines()[0].endswith(" -I"):
        raise AssertionError("child launcher lacks a direct isolated-Python shebang")
    if "runpy.run_path" not in source or str(guard) not in source:
        raise AssertionError("child launcher does not run the pinned guard in-process")
    if "exec " in source or "subprocess" in source or "/bin/bash" in source:
        raise AssertionError("child launcher reintroduced an intermediate process hop")

    guard_source = guard.read_text(encoding="utf-8")
    main_start = guard_source.index('group = mode in ("group", "external-group")')
    fork_index = guard_source.index("guard_pid = os.fork()", main_start)
    ready_index = guard_source.index("ready = os.read(", fork_index)
    target_group_index = guard_source.index("os.setpgid(0, 0)", ready_index)
    guard_group_index = guard_source.index(
        "os.setpgid(guard_pid, target_pid)",
        target_group_index,
    )
    commit_index = guard_source.index('os.write(commit_write, b"C")', guard_group_index)
    ack_index = guard_source.index(
        "acknowledged = os.read(ready_read, 1)",
        commit_index,
    )
    exec_index = guard_source.index("os.execvpe(", ack_index)
    if not (
        fork_index
        < ready_index
        < target_group_index
        < guard_group_index
        < commit_index
        < ack_index
        < exec_index
    ):
        raise AssertionError("parent guard R/C/A ordering is not fail-closed")

    commit_read_index = guard_source.index("marker = os.read(commit_fd, 1)")
    commit_state_index = guard_source.index(
        'state["committed"] = group',
        commit_read_index,
    )
    commit_ack_index = guard_source.index(
        'os.write(ready_fd, b"A")',
        commit_state_index,
    )
    if not commit_read_index < commit_state_index < commit_ack_index:
        raise AssertionError("monitor acknowledges before recording group commitment")
    if "os.getpgid(target_pid)" in guard_source:
        raise AssertionError("parent guard queries a possibly reused target PID")

    terminate_start = guard_source.index("def terminate_group(")
    terminate_end = guard_source.index(
        "def close_guard_descriptors(",
        terminate_start,
    )
    terminate_source = guard_source[terminate_start:terminate_end]
    for fragment in (
        "os.killpg(target_pid",
        'if group and state["committed"]',
        "terminate_group(target_pid)",
        "os.kill(target_pid",
    ):
        if fragment not in terminate_source:
            raise AssertionError(
                f"parent guard lacks committed cleanup fragment {fragment!r}"
            )

    missing_environment = os.environ.copy()
    missing_environment.pop("ANVIL_HEADLESS_REAL_SHELL", None)
    cold_started = time.monotonic()
    missing = subprocess.run(
        [str(launcher), "-c", "true"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=missing_environment,
        text=True,
        timeout=COLD_START_TIMEOUT_SECONDS,
        check=False,
    )
    cold_elapsed = time.monotonic() - cold_started
    if (
        missing.returncode != EXIT_SOFTWARE
        or "missing real shell for dedicated child" not in missing.stderr
    ):
        raise AssertionError(f"missing-shell failure was not closed: {missing!r}")

    with tempfile.TemporaryDirectory(prefix="anvil-child-shell-") as raw:
        probe = Path(raw) / "probe"
        write_probe(probe)
        durations: list[float] = []
        for iteration in range(LATENCY_RUNS):
            command = f"probe-{iteration}"
            completed, elapsed = run_launcher(launcher, probe, command)
            decode_probe(completed, probe, command)
            if elapsed >= MAX_LAUNCH_SECONDS:
                raise AssertionError(
                    f"child launch {iteration} took {elapsed:.3f}s "
                    f"(limit {MAX_LAUNCH_SECONDS:.1f}s)"
                )
            durations.append(elapsed)

        assert_committed_group_survives_leader_exit(guard)
        assert_parent_death_reaps_descendant(
            launcher,
            real_shell,
        )

    print(
        "child-shell-test-ok descendant-reaped "
        f"cold={cold_elapsed:.3f}s runs={len(durations)} "
        f"max={max(durations):.3f}s"
    )


if __name__ == "__main__":
    main()
