#!/usr/bin/env python3
"""Exercise an installed Pi /new through an isolated pseudo-terminal."""

from __future__ import annotations

import errno
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path


CREATE_SESSION = r"""
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [packageDir, cwd, sessionDir] = process.argv.slice(1);
const moduleUrl = pathToFileURL(join(packageDir, "dist/core/session-manager.js")).href;
const { SessionManager } = await import(moduleUrl);
const manager = SessionManager.create(cwd, sessionDir);
manager.flush();
const sessionFile = manager.getSessionFile();
manager.close();
if (!sessionFile) throw new Error("packaged SessionManager did not persist a session");
process.stdout.write(sessionFile);
"""


def collect(fd: int, output: bytearray, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        readable, _, _ = select.select([fd], [], [], min(0.1, deadline - time.monotonic()))
        if not readable:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError as error:
            if error.errno == errno.EIO:
                return
            raise
        if not chunk:
            return
        output.extend(chunk)


def wait_for(fd: int, output: bytearray, needle: bytes, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while needle not in output and time.monotonic() < deadline:
        collect(fd, output, min(0.25, deadline - time.monotonic()))
    if needle not in output:
        raise RuntimeError(f"Pi did not emit {needle!r} through the PTY")


def wait_for_exit(pid: int, fd: int, output: bytearray, timeout: float) -> int | None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        collect(fd, output, min(0.1, deadline - time.monotonic()))
        waited, status = os.waitpid(pid, os.WNOHANG)
        if waited == pid:
            return status
    return None


def terminate(pid: int) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline:
        try:
            waited, _ = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            return
        if waited == pid:
            return
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} PI_BINARY PI_PACKAGE_DIR", file=sys.stderr)
        return 64

    binary = os.path.realpath(sys.argv[1])
    package_dir = os.path.realpath(sys.argv[2])
    output = bytearray()
    with tempfile.TemporaryDirectory(prefix="pi-session-replacement-") as root_name:
        root = Path(root_name)
        agent_dir = root / "agent"
        session_dir = root / "sessions"
        agent_dir.mkdir()
        session_dir.mkdir()

        env = os.environ.copy()
        env.update(
            {
                "HOME": str(root),
                "PI_CODING_AGENT_DIR": str(agent_dir),
                "PI_CODING_AGENT_SESSION_DIR": str(session_dir),
                "PI_OFFLINE": "1",
                "TERM": "xterm-256color",
                "XDG_CACHE_HOME": str(root / "cache"),
                "XDG_CONFIG_HOME": str(root / "config"),
                "XDG_DATA_HOME": str(root / "data"),
            }
        )
        generated = subprocess.run(
            ["node", "--input-type=module", "--eval", CREATE_SESSION, package_dir, str(root), str(session_dir)],
            check=True,
            capture_output=True,
            env=env,
            text=True,
            timeout=30,
        )
        session_file = Path(generated.stdout)
        if session_file.parent != session_dir or not session_file.is_file():
            raise RuntimeError("packaged SessionManager created a session outside the isolated session root")
        if not Path(f"{session_file}.index.sqlite").is_file():
            raise RuntimeError("packaged SessionManager did not create the indexed SQLite sidecar")

        argv = [
            binary,
            "--continue",
            "--offline",
            "--approve",
            "--no-extensions",
            "--no-skills",
            "--no-prompt-templates",
            "--no-themes",
            "--no-context-files",
            "--session-dir",
            str(session_dir),
        ]

        pid, fd = pty.fork()
        if pid == 0:
            os.chdir(root)
            os.execve(binary, argv, env)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))

        reaped = False
        try:
            wait_for(fd, output, b"Pi can explain its own features", 20.0)
            os.write(fd, b"/new\r")
            wait_for(fd, output, b"New session started", 20.0)
            if os.waitpid(pid, os.WNOHANG)[0] != 0:
                reaped = True
                raise RuntimeError("Pi exited after /new")

            os.write(fd, b"/session\r")
            wait_for(fd, output, b"Session Info", 10.0)
            os.write(fd, b"/quit\r")
            status = wait_for_exit(pid, fd, output, 10.0)
            if status is None:
                raise RuntimeError("Pi did not exit after /quit")
            reaped = True

            rendered = output.decode("utf-8", errors="replace")
            forbidden = ("ERR_INVALID_STATE", "statement has been finalized", "uncaught exception")
            found = [text for text in forbidden if text.lower() in rendered.lower()]
            if found:
                raise RuntimeError(f"Pi /new emitted stale-session failure markers: {found}")
            if not (os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0):
                raise RuntimeError(f"Pi did not exit cleanly after /new: wait status {status}")
        except Exception as error:
            if not reaped:
                terminate(pid)
            print(error, file=sys.stderr)
            print(output.decode("utf-8", errors="replace")[-4000:], file=sys.stderr)
            return 1
        finally:
            os.close(fd)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
