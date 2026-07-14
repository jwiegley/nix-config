#!/usr/bin/env python3
"""Supervisor for bridge-local dedicated Anvil Emacs daemons."""

from __future__ import annotations

import argparse
import ctypes
import errno
from enum import Enum
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


EXIT_UNAVAILABLE = 69
EXIT_SOFTWARE = 70
EXIT_CONFIG = 77
LOCK_NAME = ".anvil-agent-supervisor.lock"
STATUS_NAME = ".anvil-agent-supervisor.json"
DAEMON_DIAGNOSTIC_NAME = ".anvil-daemon.log"
AGENT_KEY_PATTERN = re.compile(r"[0-9a-f]{32}")
GENERATION_PATTERN = re.compile(r"[0-9a-f]{64}")
LINUX_BOOT_ID_PATTERN = re.compile(
    r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
    r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
)
HOST_PATTERN = re.compile(r"[A-Za-z0-9._-]+")
SERVER_IDS = frozenset(("anvil", "emacs-eval"))
RECORD_FORMAT_V1 = 1
RECORD_FORMAT_V2 = 2
MAX_LEASE_BYTES = 8192
MAX_DAEMON_DIAGNOSTIC_BYTES = 128 * 1024
POLL_SECONDS = 0.25
CARETAKER_ENSURE_SECONDS = 0.5
CARETAKER_ENSURE_MAX_BACKOFF_SECONDS = 5.0
DAEMON_STOP_SECONDS = 5.0
SUPERVISOR_HANDSHAKE_SECONDS = 5.0
MAX_READY_SECONDS = 120.0
STARTUP_STATUS_RETRY_SECONDS = 4.0
RESTART_BACKOFF_INITIAL_SECONDS = 0.5
RESTART_BACKOFF_MAX_SECONDS = 60.0
RESTART_STABLE_SECONDS = 30.0
LIFECYCLE_REFRESH_SECONDS = 60.0
TRANSIENT_ERRNOS = frozenset(
    error
    for error in (
        errno.EAGAIN,
        errno.EBUSY,
        errno.EINTR,
        errno.EIO,
        errno.EMFILE,
        errno.ENFILE,
        errno.ENOSPC,
        getattr(errno, "EDQUOT", None),
    )
    if error is not None
)
_LINUX_BOOT_ID: str | None = None
_LINUX_BOOT_ID_INITIALIZED = False
_DARWIN_LIBPROC = None
_DARWIN_PROC_PIDINFO = None
_DARWIN_PROC_PIDINFO_INITIALIZED = False


class ConfigurationError(RuntimeError):
    """A caller supplied unsafe or inconsistent lifecycle configuration."""


class LifecycleState(Enum):
    """Whether a lifecycle identity is live, dead, or temporarily unreadable."""

    LIVE = "live"
    DEAD = "dead"
    UNAVAILABLE = "unavailable"


def fail(message: str, status: int = EXIT_SOFTWARE) -> NoReturn:
    print(f"anvil-mcp: per-agent daemon: {message}", file=sys.stderr)
    raise SystemExit(status)


def validate_agent_key(raw: str) -> str:
    """Reject path-like or otherwise malformed bridge identifiers."""
    if not isinstance(raw, str) or AGENT_KEY_PATTERN.fullmatch(raw) is None:
        raise ConfigurationError("invalid MCP bridge identity hash")
    return raw


def validate_generation(raw: str) -> str:
    """Validate the immutable package-generation token supplied by Nix."""
    if not isinstance(raw, str) or GENERATION_PATTERN.fullmatch(raw) is None:
        raise ConfigurationError("invalid packaged runtime generation")
    return raw


def validate_host(raw: str) -> str:
    if not raw or raw in (".", "..") or HOST_PATTERN.fullmatch(raw) is None:
        raise ConfigurationError(f"unsafe host component: {raw!r}")
    return raw


def validate_server_id(raw: str) -> str:
    if raw not in SERVER_IDS:
        raise ConfigurationError(f"unsupported server id: {raw!r}")
    return raw


def ensure_private_directory(path: Path) -> None:
    """Create PATH once and reject links, foreign owners, and broad modes."""
    created = False
    try:
        path.mkdir(mode=0o700)
        created = True
    except FileExistsError:
        pass
    except OSError as error:
        raise ConfigurationError(
            f"cannot create private directory {path}: {error}"
        ) from error

    try:
        info = path.lstat()
    except OSError as error:
        raise ConfigurationError(
            f"cannot inspect private directory {path}: {error}"
        ) from error
    if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise ConfigurationError(f"private path is not a real directory: {path}")
    if info.st_uid != os.getuid():
        raise ConfigurationError(
            f"private directory {path} is not owned by uid {os.getuid()}"
        )
    if created:
        descriptor = os.open(
            path,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
        try:
            opened = os.fstat(descriptor)
            if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
                raise ConfigurationError(f"private directory changed: {path}")
            os.fchmod(descriptor, 0o700)
        finally:
            os.close(descriptor)
        current = path.lstat()
        if (current.st_dev, current.st_ino) != (info.st_dev, info.st_ino):
            raise ConfigurationError(f"private directory was replaced: {path}")
        info = current
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
        boot_id = (
            Path("/proc/sys/kernel/random/boot_id").read_text(encoding="ascii").strip()
        )
    except FileNotFoundError:
        boot_id = ""
    except OSError as error:
        if transient_supervisor_error(error):
            raise
        boot_id = ""
    _LINUX_BOOT_ID = (
        boot_id.lower()
        if LINUX_BOOT_ID_PATTERN.fullmatch(boot_id) is not None
        else None
    )
    _LINUX_BOOT_ID_INITIALIZED = True
    return _LINUX_BOOT_ID


def linux_process_start_state(pid: int) -> tuple[LifecycleState, str | None]:
    """Probe one Linux PID without confusing read failure with process death."""
    try:
        boot_id = linux_boot_id()
    except OSError:
        return LifecycleState.UNAVAILABLE, None
    if boot_id is None:
        return LifecycleState.UNAVAILABLE, None
    try:
        raw = Path(f"/proc/{pid}/stat").read_text(encoding="ascii")
    except (FileNotFoundError, ProcessLookupError):
        return LifecycleState.DEAD, None
    except OSError:
        return LifecycleState.UNAVAILABLE, None
    closing = raw.rfind(")")
    if closing < 0:
        return LifecycleState.UNAVAILABLE, None
    fields = raw[closing + 2 :].split()
    if len(fields) <= 19 or not fields[19].isdecimal():
        return LifecycleState.UNAVAILABLE, None
    if fields[0] in ("Z", "X"):
        return LifecycleState.DEAD, None
    return LifecycleState.LIVE, f"linux:{boot_id}:{fields[19]}"


def linux_process_start(pid: int) -> str | None:
    state, identity = linux_process_start_state(pid)
    return identity if state is LifecycleState.LIVE else None


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


def darwin_process_start_state(pid: int) -> tuple[LifecycleState, str | None]:
    """Probe one Darwin PID without treating libproc failure as death."""
    proc_pidinfo = darwin_proc_pidinfo()
    if proc_pidinfo is None:
        return LifecycleState.UNAVAILABLE, None
    info = DarwinBSDInfo()
    ctypes.set_errno(0)
    try:
        result = proc_pidinfo(
            pid,
            3,  # PROC_PIDTBSDINFO
            0,
            ctypes.byref(info),
            ctypes.sizeof(info),
        )
    except OSError:
        return LifecycleState.UNAVAILABLE, None
    if result == ctypes.sizeof(info) and info.pbi_pid == pid:
        if info.pbi_status == 5:  # SZOMB
            return LifecycleState.DEAD, None
        identity = f"darwin:{info.pbi_start_tvsec}:{info.pbi_start_tvusec}"
        return LifecycleState.LIVE, identity
    error_number = ctypes.get_errno()
    if result == 0 and error_number == errno.ESRCH:
        return LifecycleState.DEAD, None
    return LifecycleState.UNAVAILABLE, None


def darwin_process_start(pid: int) -> str | None:
    state, identity = darwin_process_start_state(pid)
    return identity if state is LifecycleState.LIVE else None


def process_start_state(pid: int) -> tuple[LifecycleState, str | None]:
    """Return a tri-state PID-reuse-resistant process identity probe."""
    if pid <= 1:
        return LifecycleState.DEAD, None
    if sys.platform.startswith("linux"):
        return linux_process_start_state(pid)
    if sys.platform == "darwin":
        return darwin_process_start_state(pid)
    return LifecycleState.UNAVAILABLE, None


def process_start_identity(pid: int) -> str | None:
    """Return a PID-reuse-resistant operating-system start identity."""
    state, identity = process_start_state(pid)
    return identity if state is LifecycleState.LIVE else None


def validate_process_identity(pid: int, expected: str) -> LifecycleState:
    """Validate EXPECTED while preserving temporary probe unavailability."""
    state, identity = process_start_state(pid)
    if state is not LifecycleState.LIVE:
        return state
    return LifecycleState.LIVE if identity == expected else LifecycleState.DEAD


def lifecycle_unavailable(message: str) -> OSError:
    """Return a retryable error for the supervisor's bounded backoff path."""
    return OSError(errno.EAGAIN, message)


def derive_agent_key(
    bridge_pid: int,
    bridge_start_identity: str,
    generation: str,
    uid: int | None = None,
) -> str:
    """Derive one bridge- and package-generation-qualified path component."""
    if not isinstance(bridge_pid, int) or bridge_pid <= 1:
        raise ConfigurationError("invalid MCP bridge PID")
    if not isinstance(bridge_start_identity, str) or not bridge_start_identity:
        raise ConfigurationError("invalid MCP bridge start identity")
    generation = validate_generation(generation)
    bridge_uid = os.getuid() if uid is None else uid
    if not isinstance(bridge_uid, int) or bridge_uid < 0:
        raise ConfigurationError("invalid MCP bridge uid")
    material = (
        f"anvil-mcp-bridge-v2\0{bridge_uid}\0{bridge_pid}\0"
        f"{bridge_start_identity}\0{generation}"
    ).encode("utf-8")
    return hashlib.sha256(material).hexdigest()[:32]


def input_pipe_closed(descriptor: int = 0) -> bool:
    """Detect MCP-input failure without consuming buffered requests."""
    try:
        poller = select.poll()
        failure_events = select.POLLHUP | select.POLLERR | select.POLLNVAL
        poller.register(descriptor, failure_events)
        return any(events & failure_events for _descriptor, events in poller.poll(0))
    except (OSError, ValueError):
        return True


def identify_bridge(input_descriptor: int = 0) -> tuple[int, str]:
    """Identify this exact MCP bridge process generation without its parent."""
    if input_pipe_closed(input_descriptor):
        raise ConfigurationError("MCP input pipe is closed")
    bridge_pid = os.getpid()
    bridge_identity = process_start_identity(bridge_pid)
    if bridge_identity is None:
        raise ConfigurationError("cannot identify this MCP bridge process")
    if input_pipe_closed(input_descriptor):
        raise ConfigurationError("MCP input pipe closed during startup")
    return bridge_pid, bridge_identity


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
    durable: bool = True,
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
        os.fchmod(descriptor, 0o600)
        write_all(descriptor, payload)
        if durable:
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
        if durable:
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
    generation: str,
) -> tuple[Path, dict[str, object]]:
    generation = validate_generation(generation)
    pid = os.getpid()
    identity = process_start_identity(pid)
    if identity is None:
        raise ConfigurationError("cannot obtain this bridge process start identity")
    token = os.urandom(16).hex()
    name = f"lease-{server_id}-{pid}-{token}.json"
    record: dict[str, object] = {
        "format": RECORD_FORMAT_V2,
        "version": RECORD_FORMAT_V2,
        "generation": generation,
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
    generation: str | None,
) -> tuple[LifecycleState, dict[str, object] | None]:
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
            return LifecycleState.DEAD, None
        payload = os.read(descriptor, MAX_LEASE_BYTES + 1)
        if len(payload) > MAX_LEASE_BYTES:
            return LifecycleState.DEAD, None
        record = json.loads(payload.decode("utf-8"))
        v1_keys = {
            "bridge_pid",
            "bridge_start_identity",
            "format",
            "agent_key",
            "owner_pid",
            "owner_start_identity",
            "server_id",
            "uid",
        }
        v2_keys = v1_keys | {"generation", "version"}
        if not isinstance(record, dict):
            return LifecycleState.DEAD, None
        record_format = record.get("format")
        if record_format == RECORD_FORMAT_V1:
            if set(record) != v1_keys or generation is not None:
                return LifecycleState.DEAD, None
        elif record_format == RECORD_FORMAT_V2:
            if (
                set(record) != v2_keys
                or record.get("version") != RECORD_FORMAT_V2
                or generation is None
                or record.get("generation") != generation
            ):
                return LifecycleState.DEAD, None
            try:
                validate_generation(record["generation"])
            except ConfigurationError:
                return LifecycleState.DEAD, None
        else:
            return LifecycleState.DEAD, None
        bridge_pid = record["bridge_pid"]
        if (
            not isinstance(bridge_pid, int)
            or bridge_pid <= 1
            or record["uid"] != os.getuid()
            or record["server_id"] not in SERVER_IDS
            or record["agent_key"] != agent_key
            or record["owner_pid"] != owner_pid
            or record["owner_start_identity"] != owner_start_identity
            or not isinstance(record["bridge_start_identity"], str)
        ):
            return LifecycleState.DEAD, None
        bridge_state = validate_process_identity(
            bridge_pid,
            record["bridge_start_identity"],
        )
        if bridge_state is not LifecycleState.LIVE:
            return bridge_state, None
        return LifecycleState.LIVE, record
    except (FileNotFoundError, ValueError, UnicodeError):
        return LifecycleState.DEAD, None
    except OSError as error:
        if error.errno == errno.ELOOP:
            return LifecycleState.DEAD, None
        return LifecycleState.UNAVAILABLE, None
    finally:
        if descriptor is not None:
            os.close(descriptor)


def live_leases(
    leases_dir: Path,
    agent_key: str,
    owner_pid: int,
    owner_start_identity: str,
    generation: str | None,
    *,
    owner_validated: bool = False,
) -> list[dict[str, object]]:
    directory_fd = os.open(
        leases_dir,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
    )
    live: list[dict[str, object]] = []
    owner_state = (
        LifecycleState.LIVE
        if owner_validated
        else validate_process_identity(owner_pid, owner_start_identity)
    )
    if owner_state is LifecycleState.UNAVAILABLE:
        os.close(directory_fd)
        raise lifecycle_unavailable("owner process identity is unavailable")
    owner_alive = owner_state is LifecycleState.LIVE
    unavailable = False
    try:
        for name in os.listdir(directory_fd):
            if not name.startswith("lease-") or not name.endswith(".json"):
                continue
            try:
                info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            except FileNotFoundError:
                continue
            expected = (info.st_dev, info.st_ino)
            lease_state, record = (
                read_lease(
                    directory_fd,
                    name,
                    agent_key,
                    owner_pid,
                    owner_start_identity,
                    generation,
                )
                if owner_alive
                else (LifecycleState.DEAD, None)
            )
            if lease_state is LifecycleState.DEAD:
                unlink_if_identity(directory_fd, name, expected)
            elif lease_state is LifecycleState.UNAVAILABLE:
                unavailable = True
            elif record is not None:
                live.append(record)
        if unavailable:
            raise lifecycle_unavailable("lease lifecycle is unavailable")
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


def read_status_lifecycle(
    runtime_dir: Path,
    agent_key: str,
) -> tuple[int, str, str | None, int] | None:
    """Read a trusted v1/v2 lifetime identity from private supervisor state."""
    directory_fd = None
    descriptor = None
    try:
        directory_fd = os.open(
            runtime_dir,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
        directory_info = os.fstat(directory_fd)
        if (
            not stat.S_ISDIR(directory_info.st_mode)
            or directory_info.st_uid != os.getuid()
            or stat.S_IMODE(directory_info.st_mode) != 0o700
        ):
            return None
        descriptor = os.open(
            STATUS_NAME,
            os.O_RDONLY | os.O_NOFOLLOW,
            dir_fd=directory_fd,
        )
        descriptor_info = os.fstat(descriptor)
        path_info = os.stat(
            STATUS_NAME,
            dir_fd=directory_fd,
            follow_symlinks=False,
        )
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
        if not isinstance(record, dict):
            return None
        record_format = record.get("format")
        owner_pid = record.get("owner_pid")
        owner_identity = record.get("owner_start_identity")
        if (
            record.get("agent_key") != agent_key
            or not isinstance(owner_pid, int)
            or owner_pid <= 1
            or not isinstance(owner_identity, str)
            or not owner_identity
        ):
            return None
        if record_format == RECORD_FORMAT_V1:
            if "generation" in record or "version" in record:
                return None
            return owner_pid, owner_identity, None, RECORD_FORMAT_V1
        if (
            record_format != RECORD_FORMAT_V2
            or record.get("version") != RECORD_FORMAT_V2
        ):
            return None
        generation = record.get("generation")
        try:
            generation = validate_generation(generation)
        except ConfigurationError:
            return None
        return owner_pid, owner_identity, generation, RECORD_FORMAT_V2
    except (FileNotFoundError, PermissionError, OSError, ValueError, UnicodeError):
        return None
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if directory_fd is not None:
            os.close(directory_fd)


def read_status_owner(
    runtime_dir: Path,
    agent_key: str,
) -> tuple[int, str] | None:
    """Read the lifetime PID/start identity from a safe v1 or v2 status."""
    lifecycle = read_status_lifecycle(runtime_dir, agent_key)
    if lifecycle is None:
        return None
    return lifecycle[0], lifecycle[1]


def prune_orphaned_state(
    runtime_agents: Path,
    state_agents: Path,
    current_agent_key: str,
) -> None:
    """Prune dead owners' runtime trees and their corresponding state."""
    names: set[str] = set()
    for agents_dir in (runtime_agents, state_agents):
        try:
            names.update(os.listdir(agents_dir))
        except (FileNotFoundError, PermissionError, OSError):
            continue
    for name in sorted(names):
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
            owner = read_status_owner(runtime_path, name)
            if (
                owner is None
                or validate_process_identity(owner[0], owner[1])
                is not LifecycleState.DEAD
            ):
                continue
            try:
                locked = try_supervisor_lock(runtime_path)
            except (ConfigurationError, FileNotFoundError, OSError):
                continue
            if locked is None:
                continue
            lock_descriptor, lock_identity = locked
            try:
                validate_supervisor_lock(
                    lock_descriptor,
                    runtime_path / LOCK_NAME,
                    lock_identity,
                )
                confirmed = read_status_owner(runtime_path, name)
                if (
                    confirmed is None
                    or validate_process_identity(confirmed[0], confirmed[1])
                    is not LifecycleState.DEAD
                ):
                    continue
                remove_instance_tree(runtime_path)
            except (ConfigurationError, FileNotFoundError, OSError, RuntimeError):
                continue
            finally:
                os.close(lock_descriptor)
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
                int(name) for name in os.listdir(descriptor_root) if name.isdecimal()
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
    environment.pop("ALTERNATE_EDITOR", None)
    environment.pop("ANVIL_EMACS_SOCKET", None)
    environment.pop("ANVIL_EMACS_USE_SYSTEM_LOG", None)
    return environment


def transport_environment() -> dict[str, str]:
    """Return a client environment that cannot launch a fallback editor."""
    environment = os.environ.copy()
    environment.pop("ALTERNATE_EDITOR", None)
    return environment


def open_daemon_diagnostic(runtime_dir: Path) -> int:
    """Open one private, truncate-on-launch daemon-only diagnostic file."""
    directory_fd = os.open(
        runtime_dir,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
    )
    descriptor = None
    try:
        descriptor = os.open(
            DAEMON_DIAGNOSTIC_NAME,
            os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW,
            0o600,
            dir_fd=directory_fd,
        )
        descriptor_info = os.fstat(descriptor)
        path_info = os.stat(
            DAEMON_DIAGNOSTIC_NAME,
            dir_fd=directory_fd,
            follow_symlinks=False,
        )
        identity = (descriptor_info.st_dev, descriptor_info.st_ino)
        if (
            not stat.S_ISREG(descriptor_info.st_mode)
            or descriptor_info.st_uid != os.getuid()
            or descriptor_info.st_nlink != 1
            or (path_info.st_dev, path_info.st_ino) != identity
        ):
            raise ConfigurationError("unsafe daemon diagnostic file")
        os.fchmod(descriptor, 0o600)
        os.ftruncate(descriptor, 0)
        os.lseek(descriptor, 0, os.SEEK_SET)
        return descriptor
    except BaseException:
        if descriptor is not None:
            os.close(descriptor)
        raise
    finally:
        os.close(directory_fd)


def drain_daemon_diagnostic(process: subprocess.Popen[bytes] | None) -> None:
    """Drain daemon output without blocking, retaining only a bounded prefix."""
    if process is None:
        return
    read_descriptor = getattr(process, "_anvil_diagnostic_read_fd", None)
    output_descriptor = getattr(process, "_anvil_diagnostic_output_fd", None)
    if read_descriptor is None:
        return
    written = getattr(process, "_anvil_diagnostic_written", 0)
    while True:
        try:
            chunk = os.read(read_descriptor, 16384)
        except BlockingIOError:
            break
        except OSError as error:
            if error.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                break
            raise
        if not chunk:
            os.close(read_descriptor)
            setattr(process, "_anvil_diagnostic_read_fd", None)
            break
        remaining = max(0, MAX_DAEMON_DIAGNOSTIC_BYTES - written)
        if remaining and output_descriptor is not None:
            retained = chunk[:remaining]
            write_all(output_descriptor, retained)
            written += len(retained)
            setattr(process, "_anvil_diagnostic_written", written)


def close_daemon_diagnostic(process: subprocess.Popen[bytes] | None) -> None:
    """Finish and close a daemon's supervisor-owned diagnostic descriptors."""
    if process is None:
        return
    drain_daemon_diagnostic(process)
    for attribute in (
        "_anvil_diagnostic_read_fd",
        "_anvil_diagnostic_output_fd",
    ):
        descriptor = getattr(process, attribute, None)
        if descriptor is not None:
            os.close(descriptor)
            setattr(process, attribute, None)


def start_daemon(args: argparse.Namespace) -> subprocess.Popen[bytes]:
    command = [
        args.python,
        "-I",
        "-S",
        args.parent_guard,
        "group",
        args.daemon,
    ]
    diagnostic_descriptor = open_daemon_diagnostic(args.runtime_dir)
    read_descriptor, write_descriptor = os.pipe()
    os.set_blocking(read_descriptor, False)
    try:
        process = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=write_descriptor,
            stderr=write_descriptor,
            env=daemon_environment(args),
            start_new_session=True,
            close_fds=True,
        )
    except BaseException:
        os.close(read_descriptor)
        os.close(diagnostic_descriptor)
        raise
    finally:
        os.close(write_descriptor)
    setattr(process, "_anvil_diagnostic_read_fd", read_descriptor)
    setattr(process, "_anvil_diagnostic_output_fd", diagnostic_descriptor)
    setattr(process, "_anvil_diagnostic_written", 0)
    return process


def stop_daemon(process: subprocess.Popen[bytes] | None) -> None:
    if process is None:
        return
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=DAEMON_STOP_SECONDS)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=DAEMON_STOP_SECONDS)
            except subprocess.TimeoutExpired:
                pass
    close_daemon_diagnostic(process)


def restart_backoff_seconds(failures: int) -> float:
    """Return a capped delay for at least one consecutive failure."""
    delay = RESTART_BACKOFF_INITIAL_SECONDS
    for _unused in range(max(0, min(failures - 1, 64))):
        delay = min(RESTART_BACKOFF_MAX_SECONDS, delay * 2)
        if delay >= RESTART_BACKOFF_MAX_SECONDS:
            break
    return delay


def transient_supervisor_error(error: OSError) -> bool:
    return error.errno in TRANSIENT_ERRNOS


def refresh_private_record(directory_fd: int, name: str) -> bool:
    """Refresh one unchanged private record through a validated descriptor."""
    descriptor = None
    try:
        descriptor = os.open(
            name,
            os.O_RDONLY | os.O_NOFOLLOW,
            dir_fd=directory_fd,
        )
        descriptor_info = os.fstat(descriptor)
        path_info = os.stat(
            name,
            dir_fd=directory_fd,
            follow_symlinks=False,
        )
        if (
            not stat.S_ISREG(descriptor_info.st_mode)
            or descriptor_info.st_uid != os.getuid()
            or descriptor_info.st_nlink != 1
            or stat.S_IMODE(descriptor_info.st_mode) != 0o600
            or (descriptor_info.st_dev, descriptor_info.st_ino)
            != (path_info.st_dev, path_info.st_ino)
        ):
            return False
        os.utime(descriptor)
        return True
    except (FileNotFoundError, PermissionError, OSError):
        return False
    finally:
        if descriptor is not None:
            os.close(descriptor)


def refresh_lifecycle_records(
    lock_descriptor: int,
    runtime_dir: Path,
    leases_dir: Path,
) -> bool:
    """Keep long-lived lifecycle records safe from age-based cleaners."""
    os.utime(lock_descriptor)
    runtime_fd = os.open(
        runtime_dir,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
    )
    try:
        status_present = refresh_private_record(runtime_fd, STATUS_NAME)
    finally:
        os.close(runtime_fd)

    leases_fd = os.open(
        leases_dir,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
    )
    try:
        for name in os.listdir(leases_fd):
            if name.startswith("lease-") and name.endswith(".json"):
                refresh_private_record(leases_fd, name)
    finally:
        os.close(leases_fd)
    return status_present


def owner_seed_record(args: argparse.Namespace) -> dict[str, object]:
    """Return trusted bridge ownership without claiming a live daemon."""
    return {
        "daemon_pid": None,
        "format": RECORD_FORMAT_V2,
        "version": RECORD_FORMAT_V2,
        "generation": args.generation,
        "lease_count": 0,
        "agent_key": args.agent_key,
        "owner_pid": args.owner_pid,
        "owner_start_identity": args.owner_start_identity,
        "restart_count": 0,
        "restart_reason": None,
        "supervisor_pid": None,
        "supervisor_start_identity": None,
    }


def publish_owner_seed_if_absent(args: argparse.Namespace) -> None:
    """Publish bridge identity under the lock used by richer status writers."""
    deadline = time.monotonic() + STARTUP_STATUS_RETRY_SECONDS
    failures = 0
    expected_owner = (
        args.owner_pid,
        args.owner_start_identity,
        args.generation,
        RECORD_FORMAT_V2,
    )
    while True:
        lock_descriptor = None
        try:
            locked = try_supervisor_lock(args.runtime_dir)
            if locked is None:
                existing_owner = read_status_lifecycle(
                    args.runtime_dir,
                    args.agent_key,
                )
                if existing_owner == expected_owner:
                    return
                if existing_owner is not None:
                    raise ConfigurationError(
                        "existing bridge status does not match this generation"
                    )
            else:
                lock_descriptor, lock_identity = locked
                validate_supervisor_lock(
                    lock_descriptor,
                    args.runtime_dir / LOCK_NAME,
                    lock_identity,
                )
                existing_owner = read_status_lifecycle(
                    args.runtime_dir,
                    args.agent_key,
                )
                if existing_owner is not None and existing_owner != expected_owner:
                    raise ConfigurationError(
                        "existing bridge status does not match this generation"
                    )
                if existing_owner is None:
                    write_status(args, owner_seed_record(args))
                return
        except ConfigurationError:
            raise
        except RuntimeError as error:
            raise TimeoutError("agent supervisor lock validation failed") from error
        except OSError as error:
            if not transient_supervisor_error(error):
                raise
        finally:
            if lock_descriptor is not None:
                os.close(lock_descriptor)
        failures += 1
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("agent supervisor owner status was unavailable")
        time.sleep(min(restart_backoff_seconds(failures), remaining))


def status_record(
    args: argparse.Namespace,
    daemon: subprocess.Popen[bytes] | None,
    lease_count: int,
    restart_count: int = 0,
    restart_reason: str | None = None,
) -> dict[str, object]:
    record = owner_seed_record(args)
    record.update(
        {
            "daemon_pid": (
                None if daemon is None or daemon.poll() is not None else daemon.pid
            ),
            "lease_count": lease_count,
            "restart_count": restart_count,
            "restart_reason": restart_reason,
            "supervisor_pid": os.getpid(),
            "supervisor_start_identity": process_start_identity(os.getpid()),
        }
    )
    return record


def write_status(args: argparse.Namespace, record: dict[str, object]) -> None:
    atomic_json(
        args.runtime_dir,
        STATUS_NAME,
        record,
        replace=True,
        durable=False,
    )


def publish_startup_status(
    args: argparse.Namespace,
    record: dict[str, object],
) -> None:
    """Publish required startup state with bounded transient retries."""
    deadline = time.monotonic() + STARTUP_STATUS_RETRY_SECONDS
    failures = 0
    while True:
        try:
            write_status(args, record)
            return
        except OSError as error:
            if not transient_supervisor_error(error):
                raise
            failures += 1
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise
            time.sleep(min(restart_backoff_seconds(failures), remaining))


def supervisor_loop(
    args: argparse.Namespace,
    lock_descriptor: int,
    lock_identity: tuple[int, int],
) -> None:
    daemon: subprocess.Popen[bytes] | None = None
    daemon_started_at: float | None = None
    daemon_observed_stable = False
    daemon_failures = 0
    restart_count = 0
    restart_reason: str | None = None
    empty_since: float | None = None
    next_start = 0.0
    next_refresh = 0.0
    status_cache: dict[str, object] | None = None
    status_failures = 0
    next_status_attempt = 0.0
    transient_failures = 0
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
            try:
                validate_supervisor_lock(
                    lock_descriptor,
                    args.runtime_dir / LOCK_NAME,
                    lock_identity,
                )
                owner_state = validate_process_identity(
                    args.owner_pid,
                    args.owner_start_identity,
                )
                if owner_state is LifecycleState.UNAVAILABLE:
                    raise lifecycle_unavailable("owner process identity is unavailable")
                if owner_state is LifecycleState.DEAD:
                    owner_dead = True
                    live_leases(
                        args.leases_dir,
                        args.agent_key,
                        args.owner_pid,
                        args.owner_start_identity,
                        args.generation,
                    )
                    break
                leases = live_leases(
                    args.leases_dir,
                    args.agent_key,
                    args.owner_pid,
                    args.owner_start_identity,
                    args.generation,
                    owner_validated=True,
                )
                now = time.monotonic()
                drain_daemon_diagnostic(daemon)
                if daemon is not None and daemon.poll() is not None:
                    restart_reason = f"daemon-exited:{daemon.returncode}"
                    restart_count += 1
                    close_daemon_diagnostic(daemon)
                    if daemon_observed_stable:
                        daemon_failures = 0
                    daemon_failures += 1
                    daemon = None
                    daemon_started_at = None
                    daemon_observed_stable = False
                    next_start = max(
                        next_start,
                        now + restart_backoff_seconds(daemon_failures),
                    )
                elif (
                    daemon is not None
                    and daemon_started_at is not None
                    and now - daemon_started_at >= RESTART_STABLE_SECONDS
                ):
                    daemon_observed_stable = True

                if leases:
                    empty_since = None
                    if daemon is None and now >= next_start:
                        daemon = start_daemon(args)
                        daemon_started_at = now
                        daemon_observed_stable = False
                else:
                    if empty_since is None:
                        empty_since = now
                    if now - empty_since >= args.grace_seconds:
                        stop_daemon(daemon)
                        daemon = None
                        daemon_started_at = None
                        daemon_observed_stable = False
                        daemon_failures = 0
                        next_start = 0.0
                        # Remain briefly as the bridge-lifetime supervisor.
                        # This closes lease-removal races before bridge death.
                        refreshed = live_leases(
                            args.leases_dir,
                            args.agent_key,
                            args.owner_pid,
                            args.owner_start_identity,
                            args.generation,
                            owner_validated=True,
                        )
                        if refreshed:
                            leases = refreshed
                            empty_since = None

                if now >= next_refresh:
                    if not refresh_lifecycle_records(
                        lock_descriptor,
                        args.runtime_dir,
                        args.leases_dir,
                    ):
                        status_cache = None
                    next_refresh = now + LIFECYCLE_REFRESH_SECONDS

                record = status_record(
                    args,
                    daemon,
                    len(leases),
                    restart_count,
                    restart_reason,
                )
                if record != status_cache and now >= next_status_attempt:
                    try:
                        write_status(args, record)
                    except OSError as error:
                        if not transient_supervisor_error(error):
                            raise
                        status_failures += 1
                        next_status_attempt = now + restart_backoff_seconds(
                            status_failures
                        )
                    else:
                        status_cache = record
                        status_failures = 0
                        next_status_attempt = 0.0
            except OSError as error:
                if not transient_supervisor_error(error):
                    raise
                transient_failures += 1
                retry_deadline = time.monotonic() + restart_backoff_seconds(
                    transient_failures
                )
                while not stopping:
                    owner_state = validate_process_identity(
                        args.owner_pid,
                        args.owner_start_identity,
                    )
                    if owner_state is LifecycleState.DEAD:
                        owner_dead = True
                        break
                    remaining = retry_deadline - time.monotonic()
                    if remaining <= 0:
                        break
                    time.sleep(min(POLL_SECONDS, remaining))
                if owner_dead or stopping:
                    break
                continue
            transient_failures = 0
            time.sleep(POLL_SECONDS)
    finally:
        stop_daemon(daemon)
        if owner_dead:
            cleanup_instance(args)
        # Preserve a trusted owner identity after an externally requested or
        # fatal supervisor exit.  A replacement supervisor overwrites this
        # record; if no replacement starts, a later agent can still prove the
        # owner generation died and safely reap both instance trees.
        os.close(lock_descriptor)


def spawn_supervisor_if_absent(args: argparse.Namespace) -> bool:
    locked = try_supervisor_lock(args.runtime_dir)
    if locked is None:
        return False
    lock_descriptor, lock_identity = locked
    try:
        validate_supervisor_lock(
            lock_descriptor,
            args.runtime_dir / LOCK_NAME,
            lock_identity,
        )
        # Seed only authenticated owner identity.  The child replaces this
        # before readiness with its own identity, but a failed fork or child
        # publication still leaves enough evidence for later safe pruning.
        publish_startup_status(args, owner_seed_record(args))
    except ConfigurationError:
        os.close(lock_descriptor)
        raise
    except RuntimeError as error:
        os.close(lock_descriptor)
        raise TimeoutError("agent supervisor lock validation failed") from error
    except OSError as error:
        os.close(lock_descriptor)
        if transient_supervisor_error(error):
            raise TimeoutError(
                "agent supervisor owner status was unavailable"
            ) from error
        raise
    except BaseException:
        os.close(lock_descriptor)
        raise
    try:
        ready_read, ready_write = os.pipe()
    except OSError:
        os.close(lock_descriptor)
        raise
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
            os.chdir("/")
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
            # Replace the parent seed with this child's identity before
            # readiness.  A transient store failure retries within the
            # parent's bounded handshake; a persistent failure emits no R.
            publish_startup_status(args, status_record(args, None, 0))
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
    readable, _, _ = select.select(
        [ready_read],
        [],
        [],
        SUPERVISOR_HANDSHAKE_SECONDS,
    )
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
        raise TimeoutError("agent supervisor did not become ready")
    children = getattr(args, "_supervisor_child_pids", None)
    if children is None:
        children = set()
        args._supervisor_child_pids = children
    children.add(child_pid)
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
            [emacsclient, "-a", "false", "-s", str(socket_path), "-e", "t"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=transport_environment(),
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
        owner_state = validate_process_identity(
            args.owner_pid,
            args.owner_start_identity,
        )
        if owner_state is LifecycleState.DEAD:
            raise ConfigurationError("MCP bridge process generation changed")
        if owner_state is LifecycleState.UNAVAILABLE:
            time.sleep(POLL_SECONDS)
            continue
        spawn_supervisor_if_absent(args)
        if safe_socket_ready(socket_path, args.emacsclient):
            return
        time.sleep(POLL_SECONDS)
    raise TimeoutError(f"dedicated Emacs did not become ready at {socket_path}")


def reap_supervisor_children(args: argparse.Namespace) -> None:
    """Reap only supervisor children created by this bridge caretaker."""
    children = getattr(args, "_supervisor_child_pids", None)
    if not children:
        return
    for pid in tuple(children):
        try:
            waited, _status = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            children.discard(pid)
        else:
            if waited == pid:
                children.discard(pid)


def start_stdio_bridge(args: argparse.Namespace) -> subprocess.Popen[bytes]:
    """Launch stdio on inherited pipes without observing MCP request bytes."""
    socket_path = args.runtime_dir / "emacs" / "server"
    environment = transport_environment()
    environment["ANVIL_EMACS_SOCKET"] = str(socket_path)
    environment["ANVIL_MCP_PARENT_GUARD"] = args.parent_guard
    environment["ANVIL_MCP_PARENT_GUARD_PYTHON"] = args.python
    environment["ANVIL_HEADLESS_PARENT_PID"] = str(os.getpid())
    return subprocess.Popen(
        [
            args.python,
            "-I",
            "-S",
            args.parent_guard,
            "group",
            args.stdio,
            f"--socket={socket_path}",
            f"--server-id={args.server_id}",
        ],
        stdin=None,
        stdout=None,
        stderr=None,
        env=environment,
        close_fds=True,
    )


def stop_stdio_bridge(process: subprocess.Popen[bytes]) -> None:
    """Boundedly stop the inherited-pipe child when its caretaker must exit."""
    if process.poll() is not None:
        return
    try:
        process.terminate()
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=DAEMON_STOP_SECONDS)
        return
    except subprocess.TimeoutExpired:
        try:
            process.kill()
        except ProcessLookupError:
            return
    try:
        process.wait(timeout=DAEMON_STOP_SECONDS)
    except subprocess.TimeoutExpired:
        pass


def caretake_stdio_bridge(args: argparse.Namespace) -> int:
    """Keep supervisor availability while stdio directly owns the MCP pipes."""
    process = start_stdio_bridge(args)
    stopping = False
    ensure_failures = 0
    next_ensure = 0.0
    previous_handlers: dict[int, object] = {}

    def request_stop(_signum: int, _frame: object) -> None:
        nonlocal stopping
        stopping = True

    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        previous_handlers[signum] = signal.getsignal(signum)
        signal.signal(signum, request_stop)
    try:
        while not stopping and process.poll() is None:
            reap_supervisor_children(args)
            now = time.monotonic()
            if now >= next_ensure:
                owner_state = validate_process_identity(
                    args.owner_pid,
                    args.owner_start_identity,
                )
                if owner_state is LifecycleState.DEAD:
                    raise ConfigurationError("MCP bridge process generation changed")
                if owner_state is LifecycleState.UNAVAILABLE:
                    ensure_failures += 1
                    next_ensure = now + min(
                        CARETAKER_ENSURE_MAX_BACKOFF_SECONDS,
                        restart_backoff_seconds(ensure_failures),
                    )
                else:
                    try:
                        spawn_supervisor_if_absent(args)
                    except TimeoutError:
                        ensure_failures += 1
                        next_ensure = now + min(
                            CARETAKER_ENSURE_MAX_BACKOFF_SECONDS,
                            restart_backoff_seconds(ensure_failures),
                        )
                    except OSError as error:
                        if not transient_supervisor_error(error):
                            raise
                        ensure_failures += 1
                        next_ensure = now + min(
                            CARETAKER_ENSURE_MAX_BACKOFF_SECONDS,
                            restart_backoff_seconds(ensure_failures),
                        )
                    else:
                        ensure_failures = 0
                        next_ensure = now + CARETAKER_ENSURE_SECONDS
            try:
                process.wait(timeout=POLL_SECONDS)
            except subprocess.TimeoutExpired:
                pass
        if stopping:
            stop_stdio_bridge(process)
        returncode = process.poll()
        if returncode is None:
            return EXIT_SOFTWARE
        return returncode if returncode >= 0 else 128 - returncode
    finally:
        if process.poll() is None:
            stop_stdio_bridge(process)
        reap_supervisor_children(args)
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)


def bridge_main(args: argparse.Namespace) -> None:
    try:
        args.server_id = validate_server_id(args.server_id)
        args.host = validate_host(args.host)
        args.generation = validate_generation(args.generation)
        args.owner_pid, args.owner_start_identity = identify_bridge()
        args.agent_key = derive_agent_key(
            args.owner_pid,
            args.owner_start_identity,
            args.generation,
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
        # Make every published instance attributable before pruning siblings or
        # registering a lease.  The supervisor lock preserves an existing
        # richer record while serializing repair of invalid status.
        publish_owner_seed_if_absent(args)
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
            args.generation,
        )
    except ConfigurationError as error:
        fail(str(error), EXIT_CONFIG)
    except TimeoutError as error:
        fail(str(error), EXIT_UNAVAILABLE)
    except OSError as error:
        fail(f"cannot prepare MCP bridge: {error}")

    try:
        wait_for_daemon(args)
        stdio_status = caretake_stdio_bridge(args)
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
    if stdio_status != 0:
        raise SystemExit(stdio_status)


def parse_arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server-id", required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--generation", required=True)
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
    if not (0.25 <= args.grace_seconds <= 300):
        parser.error("--grace-seconds must be between 0.25 and 300")
    if not (1 <= args.ready_seconds <= MAX_READY_SECONDS):
        parser.error(f"--ready-seconds must be between 1 and {MAX_READY_SECONDS:g}")
    return args


def main(argv: list[str] | None = None) -> None:
    bridge_main(parse_arguments(sys.argv[1:] if argv is None else argv))


if __name__ == "__main__":
    main()
