#!/usr/bin/env python3
"""Agent supervisor for per-Codex-process dedicated Anvil Emacs daemons."""

from __future__ import annotations

import argparse
import ctypes
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
from typing import NoReturn
import select
import signal
import stat
import subprocess
import sys
import time


EXIT_USAGE = 64
EXIT_UNAVAILABLE = 69
EXIT_SOFTWARE = 70
EXIT_CONFIG = 77
LOCK_NAME = ".anvil-agent-supervisor.lock"
STATUS_NAME = ".anvil-agent-supervisor.json"
AGENT_KEY_PATTERN = re.compile(r"[0-9a-f]{32}")
LINUX_BOOT_ID_PATTERN = re.compile(
    r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
    r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
)
HOST_PATTERN = re.compile(r"[A-Za-z0-9._-]+")
SERVER_IDS = frozenset(("anvil", "emacs-eval"))
MAX_LEASE_BYTES = 8192
POLL_SECONDS = 0.25
DAEMON_STOP_SECONDS = 5.0
RESTART_BACKOFF_SECONDS = 0.5
_LINUX_BOOT_ID: str | None = None
_LINUX_BOOT_ID_INITIALIZED = False
_DARWIN_LIBPROC = None
_DARWIN_PROC_PIDINFO = None
_DARWIN_PROC_PIDINFO_INITIALIZED = False


class ConfigurationError(RuntimeError):
    """A caller supplied unsafe or inconsistent lifecycle configuration."""


def fail(message: str, status: int = EXIT_SOFTWARE) -> NoReturn:
    print(f"anvil-mcp: per-agent daemon: {message}", file=sys.stderr)
    raise SystemExit(status)


def validate_agent_key(raw: str) -> str:
    """Reject path-like or otherwise malformed owner identifiers."""
    if not isinstance(raw, str) or AGENT_KEY_PATTERN.fullmatch(raw) is None:
        raise ConfigurationError("invalid Codex owner identity hash")
    return raw


def validate_host(raw: str) -> str:
    if (
        not raw
        or raw in (".", "..")
        or HOST_PATTERN.fullmatch(raw) is None
    ):
        raise ConfigurationError(f"unsafe host component: {raw!r}")
    return raw


def validate_server_id(raw: str) -> str:
    if raw not in SERVER_IDS:
        raise ConfigurationError(f"unsupported server id: {raw!r}")
    return raw


def ensure_private_directory(path: Path) -> None:
    """Create PATH once and reject links, foreign owners, and broad modes."""
    try:
        path.mkdir(mode=0o700)
    except FileExistsError:
        pass
    except OSError as error:
        raise ConfigurationError(f"cannot create private directory {path}: {error}")

    try:
        info = path.lstat()
    except OSError as error:
        raise ConfigurationError(f"cannot inspect private directory {path}: {error}")
    if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise ConfigurationError(f"private path is not a real directory: {path}")
    if info.st_uid != os.getuid():
        raise ConfigurationError(
            f"private directory {path} is not owned by uid {os.getuid()}"
        )
    if stat.S_IMODE(info.st_mode) != 0o700:
        raise ConfigurationError(f"private directory must have mode 0700: {path}")


def prepare_instance_directories(
    runtime_root: Path,
    state_root: Path,
    host: str,
    agent_key: str,
) -> tuple[Path, Path, Path]:
    """Build HOST/agents/HEX trees without consulting HOME."""
    agent_key = validate_agent_key(agent_key)
    runtime_host = runtime_root / host
    state_host = state_root / host
    paths = (
        runtime_root,
        runtime_host,
        runtime_host / "agents",
        runtime_host / "agents" / agent_key,
        state_root,
        state_host,
        state_host / "agents",
        state_host / "agents" / agent_key,
    )
    for path in paths:
        ensure_private_directory(path)

    runtime_dir = paths[3]
    state_dir = paths[7]
    runtime_info = os.stat(runtime_dir, follow_symlinks=False)
    state_info = os.stat(state_dir, follow_symlinks=False)
    if (runtime_info.st_dev, runtime_info.st_ino) == (
        state_info.st_dev,
        state_info.st_ino,
    ):
        raise ConfigurationError("runtime and state instance directories coincide")

    leases_dir = runtime_dir / "leases"
    ensure_private_directory(leases_dir)
    return runtime_dir, state_dir, leases_dir


class DarwinBSDInfo(ctypes.Structure):
    """The stable proc_bsdinfo prefix through its process start timestamp."""

    _fields_ = [
        ("pbi_flags", ctypes.c_uint32),
        ("pbi_status", ctypes.c_uint32),
        ("pbi_xstatus", ctypes.c_uint32),
        ("pbi_pid", ctypes.c_uint32),
        ("pbi_ppid", ctypes.c_uint32),
        ("pbi_uid", ctypes.c_uint32),
        ("pbi_gid", ctypes.c_uint32),
        ("pbi_ruid", ctypes.c_uint32),
        ("pbi_rgid", ctypes.c_uint32),
        ("pbi_svuid", ctypes.c_uint32),
        ("pbi_svgid", ctypes.c_uint32),
        ("pbi_rfu_1", ctypes.c_uint32),
        ("pbi_comm", ctypes.c_char * 16),
        ("pbi_name", ctypes.c_char * 32),
        ("pbi_nfiles", ctypes.c_uint32),
        ("pbi_pgid", ctypes.c_uint32),
        ("pbi_pjobc", ctypes.c_uint32),
        ("e_tdev", ctypes.c_uint32),
        ("e_tpgid", ctypes.c_uint32),
        ("pbi_nice", ctypes.c_int32),
        ("pbi_start_tvsec", ctypes.c_uint64),
        ("pbi_start_tvusec", ctypes.c_uint64),
    ]


def linux_boot_id() -> str | None:
    """Read Linux's boot generation once for this supervisor process."""
    global _LINUX_BOOT_ID, _LINUX_BOOT_ID_INITIALIZED
    if _LINUX_BOOT_ID_INITIALIZED:
        return _LINUX_BOOT_ID
    try:
        boot_id = Path("/proc/sys/kernel/random/boot_id").read_text(
            encoding="ascii"
        ).strip()
    except (FileNotFoundError, PermissionError, OSError):
        boot_id = ""
    _LINUX_BOOT_ID = (
        boot_id.lower()
        if LINUX_BOOT_ID_PATTERN.fullmatch(boot_id) is not None
        else None
    )
    _LINUX_BOOT_ID_INITIALIZED = True
    return _LINUX_BOOT_ID


def linux_process_start(pid: int) -> str | None:
    boot_id = linux_boot_id()
    if boot_id is None:
        return None
    try:
        raw = Path(f"/proc/{pid}/stat").read_text(encoding="ascii")
    except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
        return None
    closing = raw.rfind(")")
    if closing < 0:
        return None
    fields = raw[closing + 2 :].split()
    if len(fields) <= 19 or not fields[19].isdecimal():
        return None
    if fields[0] in ("Z", "X"):
        return None
    return f"linux:{boot_id}:{fields[19]}"


def darwin_proc_pidinfo():
    """Resolve and configure libproc's proc_pidinfo entry point once."""
    global _DARWIN_LIBPROC
    global _DARWIN_PROC_PIDINFO
    global _DARWIN_PROC_PIDINFO_INITIALIZED
    if _DARWIN_PROC_PIDINFO_INITIALIZED:
        return _DARWIN_PROC_PIDINFO
    try:
        _DARWIN_LIBPROC = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    except OSError:
        _DARWIN_PROC_PIDINFO = None
    else:
        proc_pidinfo = _DARWIN_LIBPROC.proc_pidinfo
        proc_pidinfo.argtypes = [
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_uint64,
            ctypes.c_void_p,
            ctypes.c_int,
        ]
        proc_pidinfo.restype = ctypes.c_int
        _DARWIN_PROC_PIDINFO = proc_pidinfo
    _DARWIN_PROC_PIDINFO_INITIALIZED = True
    return _DARWIN_PROC_PIDINFO


def darwin_process_start(pid: int) -> str | None:
    proc_pidinfo = darwin_proc_pidinfo()
    if proc_pidinfo is None:
        return None
    info = DarwinBSDInfo()
    result = proc_pidinfo(
        pid,
        3,  # PROC_PIDTBSDINFO
        0,
        ctypes.byref(info),
        ctypes.sizeof(info),
    )
    if (
        result != ctypes.sizeof(info)
        or info.pbi_pid != pid
        or info.pbi_status == 5  # SZOMB
    ):
        return None
    return f"darwin:{info.pbi_start_tvsec}:{info.pbi_start_tvusec}"


def process_start_identity(pid: int) -> str | None:
    """Return a PID-reuse-resistant operating-system start identity."""
    if pid <= 1:
        return None
    if sys.platform.startswith("linux"):
        return linux_process_start(pid)
    if sys.platform == "darwin":
        return darwin_process_start(pid)
    return None


def derive_agent_key(
    owner_pid: int,
    owner_start_identity: str,
    uid: int | None = None,
) -> str:
    """Derive a private path component for one owning Codex process."""
    if not isinstance(owner_pid, int) or owner_pid <= 1:
        raise ConfigurationError("invalid owning Codex process PID")
    if not isinstance(owner_start_identity, str) or not owner_start_identity:
        raise ConfigurationError("invalid owning Codex process start identity")
    owner_uid = os.getuid() if uid is None else uid
    if not isinstance(owner_uid, int) or owner_uid < 0:
        raise ConfigurationError("invalid owning Codex process uid")
    material = (
        f"anvil-codex-owner-v1\0{owner_uid}\0{owner_pid}\0"
        f"{owner_start_identity}"
    ).encode("utf-8")
    return hashlib.sha256(material).hexdigest()[:32]


def owner_pipe_closed(descriptor: int = 0) -> bool:
    """Detect owner-pipe failure without consuming buffered MCP input."""
    try:
        poller = select.poll()
        failure_events = select.POLLHUP | select.POLLERR | select.POLLNVAL
        poller.register(descriptor, failure_events)
        return any(
            events & failure_events
            for _descriptor, events in poller.poll(0)
        )
    except (OSError, ValueError):
        return True


def identify_owner(input_descriptor: int = 0) -> tuple[int, str]:
    """Identify the stable OS process that directly owns this MCP bridge."""
    if owner_pipe_closed(input_descriptor):
        raise ConfigurationError("owning Codex MCP input pipe is closed")
    first_pid = os.getppid()
    first_identity = process_start_identity(first_pid)
    second_pid = os.getppid()
    second_identity = process_start_identity(second_pid)
    final_pid = os.getppid()
    if first_identity is None or second_identity is None:
        raise ConfigurationError("cannot identify the owning Codex process")
    if (
        first_pid != second_pid
        or second_pid != final_pid
        or first_identity != second_identity
    ):
        raise ConfigurationError("owning Codex process changed during startup")
    if owner_pipe_closed(input_descriptor):
        raise ConfigurationError("owning Codex MCP input pipe closed during startup")
    return first_pid, first_identity


def write_all(descriptor: int, payload: bytes) -> None:
    view = memoryview(payload)
    while view:
        written = os.write(descriptor, view)
        if written <= 0:
            raise OSError(errno.EIO, "short write")
        view = view[written:]


def atomic_json(
    directory: Path,
    final_name: str,
    data: dict[str, object],
    *,
    replace: bool,
) -> Path:
    """Publish one complete, private JSON file within DIRECTORY."""
    payload = (json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n").encode()
    if len(payload) > MAX_LEASE_BYTES:
        raise ConfigurationError("lifecycle record is unexpectedly large")
    directory_fd = os.open(
        directory,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
    )
    temp_name = f".tmp-{os.getpid()}-{os.urandom(16).hex()}"
    descriptor = None
    try:
        descriptor = os.open(
            temp_name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
            dir_fd=directory_fd,
        )
        info = os.fstat(descriptor)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_nlink != 1
        ):
            raise ConfigurationError("unsafe temporary lifecycle record")
        write_all(descriptor, payload)
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = None
        if not replace:
            try:
                os.stat(final_name, dir_fd=directory_fd, follow_symlinks=False)
            except FileNotFoundError:
                pass
            else:
                raise FileExistsError(final_name)
        os.rename(
            temp_name,
            final_name,
            src_dir_fd=directory_fd,
            dst_dir_fd=directory_fd,
        )
        os.fsync(directory_fd)
        return directory / final_name
    finally:
        if descriptor is not None:
            os.close(descriptor)
        try:
            os.unlink(temp_name, dir_fd=directory_fd)
        except FileNotFoundError:
            pass
        os.close(directory_fd)


def register_lease(
    leases_dir: Path,
    server_id: str,
    agent_key: str,
    owner_pid: int,
    owner_start_identity: str,
) -> tuple[Path, dict[str, object]]:
    pid = os.getpid()
    identity = process_start_identity(pid)
    if identity is None:
        raise ConfigurationError("cannot obtain this bridge process start identity")
    token = os.urandom(16).hex()
    name = f"lease-{server_id}-{pid}-{token}.json"
    record: dict[str, object] = {
        "format": 1,
        "bridge_pid": pid,
        "bridge_start_identity": identity,
        "agent_key": agent_key,
        "owner_pid": owner_pid,
        "owner_start_identity": owner_start_identity,
        "server_id": server_id,
        "uid": os.getuid(),
    }
    return atomic_json(leases_dir, name, record, replace=False), record


def unlink_if_identity(
    directory_fd: int,
    name: str,
    expected: tuple[int, int],
) -> None:
    try:
        current = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
    except FileNotFoundError:
        return
    if (current.st_dev, current.st_ino) != expected:
        return
    try:
        os.unlink(name, dir_fd=directory_fd)
    except FileNotFoundError:
        pass


def read_lease(
    directory_fd: int,
    name: str,
    agent_key: str,
    owner_pid: int,
    owner_start_identity: str,
) -> dict[str, object] | None:
    descriptor = None
    identity: tuple[int, int] | None = None
    try:
        descriptor = os.open(
            name,
            os.O_RDONLY | os.O_NOFOLLOW,
            dir_fd=directory_fd,
        )
        descriptor_info = os.fstat(descriptor)
        path_info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        identity = (descriptor_info.st_dev, descriptor_info.st_ino)
        if (
            not stat.S_ISREG(descriptor_info.st_mode)
            or descriptor_info.st_uid != os.getuid()
            or descriptor_info.st_nlink != 1
            or stat.S_IMODE(descriptor_info.st_mode) != 0o600
            or (path_info.st_dev, path_info.st_ino) != identity
        ):
            return None
        payload = os.read(descriptor, MAX_LEASE_BYTES + 1)
        if len(payload) > MAX_LEASE_BYTES:
            return None
        record = json.loads(payload.decode("utf-8"))
        if not isinstance(record, dict) or set(record) != {
            "bridge_pid",
            "bridge_start_identity",
            "format",
            "agent_key",
            "owner_pid",
            "owner_start_identity",
            "server_id",
            "uid",
        }:
            return None
        bridge_pid = record["bridge_pid"]
        if (
            record["format"] != 1
            or not isinstance(bridge_pid, int)
            or bridge_pid <= 1
            or record["uid"] != os.getuid()
            or record["server_id"] not in SERVER_IDS
            or record["agent_key"] != agent_key
            or record["owner_pid"] != owner_pid
            or record["owner_start_identity"] != owner_start_identity
            or not isinstance(record["bridge_start_identity"], str)
            or process_start_identity(bridge_pid)
            != record["bridge_start_identity"]
        ):
            return None
        return record
    except (FileNotFoundError, PermissionError, OSError, ValueError, UnicodeError):
        return None
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if identity is not None:
            # Invalid records are removed by the caller after it has learned
            # whether a parsed record was returned.
            pass


def live_leases(
    leases_dir: Path,
    agent_key: str,
    owner_pid: int,
    owner_start_identity: str,
    *,
    owner_validated: bool = False,
) -> list[dict[str, object]]:
    directory_fd = os.open(
        leases_dir,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
    )
    live: list[dict[str, object]] = []
    owner_alive = owner_validated or (
        process_start_identity(owner_pid) == owner_start_identity
    )
    try:
        for name in os.listdir(directory_fd):
            if not name.startswith("lease-") or not name.endswith(".json"):
                continue
            try:
                info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            except FileNotFoundError:
                continue
            expected = (info.st_dev, info.st_ino)
            record = (
                read_lease(
                    directory_fd,
                    name,
                    agent_key,
                    owner_pid,
                    owner_start_identity,
                )
                if owner_alive
                else None
            )
            if record is None:
                unlink_if_identity(directory_fd, name, expected)
            else:
                live.append(record)
        return live
    finally:
        os.close(directory_fd)


def remove_directory_contents(directory_fd: int, device: int) -> None:
    """Remove one private tree through descriptors without following links."""
    for name in os.listdir(directory_fd):
        try:
            info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        except FileNotFoundError:
            continue
        if stat.S_ISDIR(info.st_mode) and not stat.S_ISLNK(info.st_mode):
            if info.st_dev != device:
                raise ConfigurationError("refusing to cross a filesystem boundary")
            child_fd = os.open(
                name,
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                dir_fd=directory_fd,
            )
            try:
                opened = os.fstat(child_fd)
                current = os.stat(
                    name,
                    dir_fd=directory_fd,
                    follow_symlinks=False,
                )
                identity = (opened.st_dev, opened.st_ino)
                if (
                    not stat.S_ISDIR(opened.st_mode)
                    or opened.st_uid != os.getuid()
                    or identity != (current.st_dev, current.st_ino)
                ):
                    raise ConfigurationError("private state directory changed")
                remove_directory_contents(child_fd, device)
            finally:
                os.close(child_fd)
            current = os.stat(
                name,
                dir_fd=directory_fd,
                follow_symlinks=False,
            )
            if identity != (current.st_dev, current.st_ino):
                raise ConfigurationError("private state directory was replaced")
            os.rmdir(name, dir_fd=directory_fd)
        else:
            os.unlink(name, dir_fd=directory_fd)


def remove_instance_tree(path: Path) -> None:
    """Remove one agent instance while preserving any symlink targets."""
    parent_fd = os.open(
        path.parent,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
    )
    child_fd = None
    try:
        parent_info = os.fstat(parent_fd)
        if (
            not stat.S_ISDIR(parent_info.st_mode)
            or parent_info.st_uid != os.getuid()
            or stat.S_IMODE(parent_info.st_mode) != 0o700
        ):
            raise ConfigurationError("unsafe agent-instance parent directory")
        try:
            path_info = os.stat(
                path.name,
                dir_fd=parent_fd,
                follow_symlinks=False,
            )
        except FileNotFoundError:
            return
        child_fd = os.open(
            path.name,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
            dir_fd=parent_fd,
        )
        opened = os.fstat(child_fd)
        identity = (opened.st_dev, opened.st_ino)
        if (
            not stat.S_ISDIR(opened.st_mode)
            or opened.st_uid != os.getuid()
            or identity != (path_info.st_dev, path_info.st_ino)
        ):
            raise ConfigurationError("unsafe agent-instance directory")
        remove_directory_contents(child_fd, opened.st_dev)
        os.close(child_fd)
        child_fd = None
        current = os.stat(
            path.name,
            dir_fd=parent_fd,
            follow_symlinks=False,
        )
        if identity != (current.st_dev, current.st_ino):
            raise ConfigurationError("agent-instance directory was replaced")
        os.rmdir(path.name, dir_fd=parent_fd)
    finally:
        if child_fd is not None:
            os.close(child_fd)
        os.close(parent_fd)


def prune_orphaned_state(
    runtime_agents: Path,
    state_agents: Path,
    current_agent_key: str,
) -> None:
    """Prune reboot leftovers after the local runtime hierarchy vanished."""
    try:
        names = os.listdir(state_agents)
    except FileNotFoundError:
        return
    for name in names:
        if name == current_agent_key or AGENT_KEY_PATTERN.fullmatch(name) is None:
            continue
        runtime_path = runtime_agents / name
        try:
            runtime_info = runtime_path.lstat()
        except FileNotFoundError:
            runtime_info = None
        if (
            runtime_info is not None
            and stat.S_ISDIR(runtime_info.st_mode)
            and not stat.S_ISLNK(runtime_info.st_mode)
            and runtime_info.st_uid == os.getuid()
        ):
            continue
        try:
            remove_instance_tree(state_agents / name)
        except (ConfigurationError, FileNotFoundError, OSError):
            continue


def cleanup_instance(args: argparse.Namespace) -> None:
    """Best-effort cleanup after the exact owning process generation dies."""
    for path in (args.state_dir, args.runtime_dir):
        try:
            remove_instance_tree(path)
        except (ConfigurationError, FileNotFoundError, OSError):
            continue


def ofd_lock_bytes() -> tuple[int, bytes]:
    if sys.platform == "darwin":
        class Flock(ctypes.Structure):
            _fields_ = [
                ("l_start", ctypes.c_longlong),
                ("l_len", ctypes.c_longlong),
                ("l_pid", ctypes.c_int),
                ("l_type", ctypes.c_short),
                ("l_whence", ctypes.c_short),
            ]

        command = getattr(fcntl, "F_OFD_SETLK", 90)
    elif sys.platform.startswith("linux"):
        class Flock(ctypes.Structure):
            _fields_ = [
                ("l_type", ctypes.c_short),
                ("l_whence", ctypes.c_short),
                ("l_start", ctypes.c_longlong),
                ("l_len", ctypes.c_longlong),
                ("l_pid", ctypes.c_int),
            ]

        command = getattr(fcntl, "F_OFD_SETLK", 37)
    else:
        raise ConfigurationError(f"OFD locks are unsupported on {sys.platform}")

    lock = Flock()
    lock.l_type = fcntl.F_WRLCK
    lock.l_whence = os.SEEK_SET
    return command, bytes(lock)


def try_supervisor_lock(runtime_dir: Path) -> tuple[int, tuple[int, int]] | None:
    path = runtime_dir / LOCK_NAME
    descriptor = os.open(
        path,
        os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW,
        0o600,
    )
    try:
        descriptor_info = os.fstat(descriptor)
        path_info = os.stat(path, follow_symlinks=False)
        identity = (descriptor_info.st_dev, descriptor_info.st_ino)
        if (
            not stat.S_ISREG(descriptor_info.st_mode)
            or descriptor_info.st_uid != os.getuid()
            or descriptor_info.st_nlink != 1
            or (path_info.st_dev, path_info.st_ino) != identity
        ):
            raise ConfigurationError(f"unsafe supervisor lock: {path}")
        os.fchmod(descriptor, 0o600)
        command, data = ofd_lock_bytes()
        try:
            fcntl.fcntl(descriptor, command, data)
        except OSError as error:
            if error.errno in (errno.EACCES, errno.EAGAIN):
                os.close(descriptor)
                return None
            raise
        return descriptor, identity
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        raise


def validate_supervisor_lock(
    descriptor: int,
    path: Path,
    expected: tuple[int, int],
) -> None:
    descriptor_info = os.fstat(descriptor)
    path_info = os.stat(path, follow_symlinks=False)
    if (
        not stat.S_ISREG(descriptor_info.st_mode)
        or descriptor_info.st_uid != os.getuid()
        or descriptor_info.st_nlink != 1
        or (descriptor_info.st_dev, descriptor_info.st_ino) != expected
        or (path_info.st_dev, path_info.st_ino) != expected
    ):
        raise RuntimeError("supervisor lock identity changed")


def close_descriptors_except(keep: set[int]) -> None:
    candidates = None
    for descriptor_root in ("/dev/fd", "/proc/self/fd"):
        try:
            candidates = [
                int(name)
                for name in os.listdir(descriptor_root)
                if name.isdecimal()
            ]
            break
        except OSError:
            continue
    if candidates is not None:
        for descriptor in candidates:
            if descriptor >= 3 and descriptor not in keep:
                try:
                    os.close(descriptor)
                except OSError as error:
                    if error.errno != errno.EBADF:
                        raise
        return

    try:
        limit = int(os.sysconf("SC_OPEN_MAX"))
    except (OSError, TypeError, ValueError):
        limit = 65536
    limit = max(256, min(limit, 65536))
    cursor = 3
    for descriptor in sorted(fd for fd in keep if fd >= 3):
        os.closerange(cursor, descriptor)
        cursor = descriptor + 1
    os.closerange(cursor, limit)


def daemon_environment(args: argparse.Namespace) -> dict[str, str]:
    environment = os.environ.copy()
    environment.update(
        {
            "ANVIL_EMACS_HOST": args.host,
            "ANVIL_EMACS_LOCK_CONFLICT_STATUS": "75",
            "ANVIL_EMACS_RUNTIME_DIR": str(args.runtime_dir),
            "ANVIL_EMACS_STATE_DIR": str(args.state_dir),
            "ANVIL_HEADLESS_PARENT_PID": str(os.getpid()),
        }
    )
    environment.pop("ANVIL_EMACS_SOCKET", None)
    environment.pop("ANVIL_EMACS_USE_SYSTEM_LOG", None)
    return environment


def start_daemon(args: argparse.Namespace) -> subprocess.Popen[bytes]:
    command = [
        args.python,
        "-I",
        "-S",
        args.parent_guard,
        "group",
        args.daemon,
    ]
    return subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=daemon_environment(args),
        start_new_session=True,
        close_fds=True,
    )


def stop_daemon(process: subprocess.Popen[bytes] | None) -> None:
    if process is None or process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=DAEMON_STOP_SECONDS)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=DAEMON_STOP_SECONDS)
    except subprocess.TimeoutExpired:
        pass


def write_status(
    args: argparse.Namespace,
    daemon: subprocess.Popen[bytes] | None,
    lease_count: int,
) -> None:
    daemon_pid = None if daemon is None or daemon.poll() is not None else daemon.pid
    atomic_json(
        args.runtime_dir,
        STATUS_NAME,
        {
            "daemon_pid": daemon_pid,
            "format": 1,
            "lease_count": lease_count,
            "agent_key": args.agent_key,
            "owner_pid": args.owner_pid,
            "owner_start_identity": args.owner_start_identity,
            "supervisor_pid": os.getpid(),
            "supervisor_start_identity": process_start_identity(os.getpid()),
        },
        replace=True,
    )


def supervisor_loop(
    args: argparse.Namespace,
    lock_descriptor: int,
    lock_identity: tuple[int, int],
) -> None:
    daemon: subprocess.Popen[bytes] | None = None
    empty_since: float | None = None
    next_start = 0.0
    stopping = False
    owner_dead = False

    def request_stop(_signum: int, _frame: object) -> None:
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGHUP, request_stop)

    try:
        while not stopping:
            validate_supervisor_lock(
                lock_descriptor,
                args.runtime_dir / LOCK_NAME,
                lock_identity,
            )
            if (
                process_start_identity(args.owner_pid)
                != args.owner_start_identity
            ):
                owner_dead = True
                live_leases(
                    args.leases_dir,
                    args.agent_key,
                    args.owner_pid,
                    args.owner_start_identity,
                )
                break
            leases = live_leases(
                args.leases_dir,
                args.agent_key,
                args.owner_pid,
                args.owner_start_identity,
                owner_validated=True,
            )
            now = time.monotonic()
            if daemon is not None and daemon.poll() is not None:
                daemon = None
                next_start = max(next_start, now + RESTART_BACKOFF_SECONDS)

            if leases:
                empty_since = None
                if daemon is None and now >= next_start:
                    daemon = start_daemon(args)
            else:
                if empty_since is None:
                    empty_since = now
                if now - empty_since >= args.grace_seconds:
                    stop_daemon(daemon)
                    daemon = None
                    # Remain as a lightweight owner-lifetime supervisor. This
                    # closes registration-vs-cleanup races and lets a later
                    # bridge in the same Codex process restart the daemon.
                    refreshed = live_leases(
                        args.leases_dir,
                        args.agent_key,
                        args.owner_pid,
                        args.owner_start_identity,
                        owner_validated=True,
                    )
                    if refreshed:
                        leases = refreshed
                        empty_since = None
                        next_start = 0.0

            write_status(args, daemon, len(leases))
            time.sleep(POLL_SECONDS)
    finally:
        stop_daemon(daemon)
        try:
            (args.runtime_dir / STATUS_NAME).unlink()
        except FileNotFoundError:
            pass
        if owner_dead:
            cleanup_instance(args)
        os.close(lock_descriptor)


def spawn_supervisor_if_absent(args: argparse.Namespace) -> bool:
    locked = try_supervisor_lock(args.runtime_dir)
    if locked is None:
        return False
    lock_descriptor, lock_identity = locked
    ready_read, ready_write = os.pipe()
    try:
        child_pid = os.fork()
    except OSError:
        os.close(ready_read)
        os.close(ready_write)
        os.close(lock_descriptor)
        raise
    if child_pid == 0:
        os.close(ready_read)
        try:
            os.setsid()
            null_descriptor = os.open(os.devnull, os.O_RDWR)
            for descriptor in (0, 1, 2):
                os.dup2(null_descriptor, descriptor)
            if null_descriptor > 2:
                os.close(null_descriptor)
            close_descriptors_except({lock_descriptor, ready_write})
            validate_supervisor_lock(
                lock_descriptor,
                args.runtime_dir / LOCK_NAME,
                lock_identity,
            )
            os.write(ready_write, b"R")
            os.close(ready_write)
            supervisor_loop(args, lock_descriptor, lock_identity)
            os._exit(0)
        except BaseException:
            try:
                os.close(ready_write)
            except OSError:
                pass
            os._exit(EXIT_SOFTWARE)

    os.close(ready_write)
    os.close(lock_descriptor)
    readable, _, _ = select.select([ready_read], [], [], 5.0)
    ready = os.read(ready_read, 1) if readable else b""
    os.close(ready_read)
    if ready != b"R":
        try:
            os.kill(child_pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            os.waitpid(child_pid, 0)
        except ChildProcessError:
            pass
        raise RuntimeError("agent supervisor did not become ready")
    return True


def safe_socket_ready(socket_path: Path, emacsclient: str) -> bool:
    try:
        info = socket_path.lstat()
    except FileNotFoundError:
        return False
    if (
        not stat.S_ISSOCK(info.st_mode)
        or info.st_uid != os.getuid()
        or info.st_nlink != 1
    ):
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISSOCK(info.st_mode):
            raise ConfigurationError(f"unsafe Emacs socket path: {socket_path}")
        return False
    try:
        result = subprocess.run(
            [emacsclient, "-s", str(socket_path), "-e", "t"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=2.0,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0 and result.stdout.strip() == b"t"


def wait_for_daemon(args: argparse.Namespace) -> None:
    deadline = time.monotonic() + args.ready_seconds
    socket_path = args.runtime_dir / "emacs" / "server"
    while time.monotonic() < deadline:
        if (
            process_start_identity(args.owner_pid)
            != args.owner_start_identity
        ):
            raise ConfigurationError("owning Codex process exited")
        spawn_supervisor_if_absent(args)
        if safe_socket_ready(socket_path, args.emacsclient):
            return
        time.sleep(POLL_SECONDS)
    raise TimeoutError(f"dedicated Emacs did not become ready at {socket_path}")


def bridge_main(args: argparse.Namespace) -> None:
    try:
        args.server_id = validate_server_id(args.server_id)
        args.host = validate_host(args.host)
        args.owner_pid, args.owner_start_identity = identify_owner()
        args.agent_key = derive_agent_key(
            args.owner_pid,
            args.owner_start_identity,
        )
        runtime_dir, state_dir, leases_dir = prepare_instance_directories(
            Path(args.runtime_root),
            Path(args.state_root),
            args.host,
            args.agent_key,
        )
        args.runtime_dir = runtime_dir
        args.state_dir = state_dir
        args.leases_dir = leases_dir
        prune_orphaned_state(
            runtime_dir.parent,
            state_dir.parent,
            args.agent_key,
        )
        lease_path, _record = register_lease(
            leases_dir,
            args.server_id,
            args.agent_key,
            args.owner_pid,
            args.owner_start_identity,
        )
    except ConfigurationError as error:
        fail(str(error), EXIT_CONFIG)

    try:
        wait_for_daemon(args)
        socket_path = runtime_dir / "emacs" / "server"
        environment = os.environ.copy()
        environment["ANVIL_EMACS_SOCKET"] = str(socket_path)
        os.execve(
            args.stdio,
            [
                args.stdio,
                f"--socket={socket_path}",
                f"--server-id={args.server_id}",
            ],
            environment,
        )
    except ConfigurationError as error:
        fail(str(error), EXIT_CONFIG)
    except TimeoutError as error:
        fail(str(error), EXIT_UNAVAILABLE)
    except OSError as error:
        fail(f"cannot start MCP bridge: {error}")
    finally:
        try:
            lease_path.unlink()
        except FileNotFoundError:
            pass


def parse_arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server-id", required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--state-root", required=True)
    parser.add_argument("--daemon", required=True)
    parser.add_argument("--stdio", required=True)
    parser.add_argument("--emacsclient", required=True)
    parser.add_argument("--python", required=True)
    parser.add_argument("--parent-guard", required=True)
    parser.add_argument("--grace-seconds", type=float, default=5.0)
    parser.add_argument("--ready-seconds", type=float, default=120.0)
    args = parser.parse_args(argv)
    if args.grace_seconds < 0.25 or args.grace_seconds > 300:
        parser.error("--grace-seconds must be between 0.25 and 300")
    if args.ready_seconds < 1 or args.ready_seconds > 300:
        parser.error("--ready-seconds must be between 1 and 300")
    return args


def main(argv: list[str] | None = None) -> None:
    bridge_main(parse_arguments(sys.argv[1:] if argv is None else argv))


if __name__ == "__main__":
    main()
