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
import secrets
import signal
import stat
import subprocess
import sys
import time
import unicodedata


EXIT_UNAVAILABLE = 69
EXIT_SOFTWARE = 70
EXIT_CONFIG = 77
LOCK_NAME = ".anvil-agent-supervisor.lock"
SESSION_GATE_PREFIX = ".anvil-agent-session-gate-"
SESSION_GATE_SUFFIX = ".lock"
STATUS_NAME = ".anvil-agent-supervisor.json"
CREATOR_MARKER_PREFIX = ".anvil-agent-creator-"
CREATOR_STAGING_PREFIX = ".anvil-agent-creator-stage-"
CREATOR_MARKER_SUFFIX = ".json"
INSTANCE_STAGING_PREFIX = ".anvil-agent-instance-stage-"
DAEMON_DIAGNOSTIC_NAME = ".anvil-daemon.log"
ACTIVITY_SOCKET_NAME = ".anvil-root-activity.sock"
WATCHDOG_SUPERVISED_ENV = "ANVIL_EMACS_WATCHDOG_SUPERVISED"
WATCHDOG_EVENT_FD_ENV = "ANVIL_EMACS_WATCHDOG_EVENT_FD"
WATCHDOG_RUN_ID_ENV = "ANVIL_EMACS_WATCHDOG_RUN_ID"
WATCHDOG_EVENT_MAX_BYTES = 512
AGENT_KEY_PATTERN = re.compile(r"[0-9a-f]{32}")
GENERATION_PATTERN = re.compile(r"[0-9a-f]{64}")
TOOL_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,127}")
AGENTDECK_INSTANCE_ID_PATTERN = re.compile(
    r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}"
)
GUARDED_OWNER_PID_ENV = "ANVIL_MCP_GUARDED_OWNER_PID"
GUARDED_OWNER_START_ENV = "ANVIL_MCP_GUARDED_OWNER_START_IDENTITY"
RESTART_REASON_PATTERN = re.compile(r"daemon-exited:-?[0-9]+")
LINUX_BOOT_ID_PATTERN = re.compile(
    r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
    r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
)
HOST_PATTERN = re.compile(r"[A-Za-z0-9._-]+")
WORKER_NAME_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
SERVER_IDS = frozenset(("anvil", "emacs-eval"))
WATCHDOG_CAUSES = frozenset(
    (
        "startup-timeout",
        "heartbeat-timeout",
        "dispatch-timeout",
        "lock-integrity-failure",
        "monitor-state-invalid",
        "durable-refresh-failure",
        "monitor-internal-error",
    )
)
WATCHDOG_PHASES = frozenset(
    (
        "startup",
        "parse",
        "dispatch",
        "tool-call",
        "result-encode",
        "response-write",
        "idle",
        "unknown",
    )
)
WATCHDOG_METHODS = frozenset(
    (
        "none",
        "initialize",
        "notifications/initialized",
        "ping",
        "tools/list",
        "tools/call",
        "resources/list",
        "resources/read",
        "resources/templates/list",
        "other",
    )
)
WATCHDOG_EVENT_KEYS = frozenset(
    (
        "schema_version",
        "run_id",
        "daemon_pid",
        "cause",
        "phase",
        "method",
        "tool",
        "observed_at_unix_ms",
        "daemon_uptime_ms",
        "heartbeat_age_ms",
        "heartbeat_limit_ms",
        "dispatch_age_ms",
        "dispatch_limit_ms",
    )
)
STATUS_KEYS = frozenset(
    (
        "daemon_pid",
        "format",
        "version",
        "generation",
        "lease_count",
        "agent_key",
        "owner_pid",
        "owner_start_identity",
        "restart_count",
        "restart_reason",
        "supervisor_pid",
        "supervisor_start_identity",
        "last_watchdog",
    )
)
RECORD_FORMAT_V1 = 1
RECORD_FORMAT_V2 = 2
MAX_LEASE_BYTES = 8192
MAX_DAEMON_DIAGNOSTIC_BYTES = 128 * 1024
MAX_DAEMON_DIAGNOSTIC_DRAIN_BYTES = 128 * 1024
# sockaddr_un.sun_path includes its terminating NUL: 104 bytes on Darwin and
# 108 on Linux.  Unknown supported-by-Python platforms use the safer ceiling.
DARWIN_UNIX_SOCKET_PATH_BYTES = 103
LINUX_UNIX_SOCKET_PATH_BYTES = 107
POLL_SECONDS = 0.25
CARETAKER_ENSURE_SECONDS = 0.5
CARETAKER_ENSURE_MAX_BACKOFF_SECONDS = 5.0
DAEMON_STOP_SECONDS = 5.0
SUPERVISOR_HANDSHAKE_SECONDS = 5.0
MAX_READY_SECONDS = 120.0
MAX_AGENT_GRACE_SECONDS = 15.0
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


class BridgeTerminationRequested(BaseException):
    """Unwind one bridge into its lease/root retirement transaction."""


def daemon_ready_expression(server_id: str) -> str:
    """Return the fail-closed readiness probe for one validated server ID."""
    if server_id not in SERVER_IDS:
        raise ConfigurationError("unsupported server id")
    return (
        "(and (fboundp 'anvil-headless--ready-p) "
        f'(anvil-headless--ready-p "{server_id}"))'
    )


class LifecycleState(Enum):
    """Whether a lifecycle identity is live, dead, or temporarily unreadable."""

    LIVE = "live"
    DEAD = "dead"
    UNAVAILABLE = "unavailable"


def fail(message: str, status: int = EXIT_SOFTWARE) -> NoReturn:
    print(f"anvil-mcp: per-agent daemon: {message}", file=sys.stderr)
    raise SystemExit(status)


def strict_json_object(payload: bytes | str) -> dict[str, object]:
    """Decode one UTF-8 JSON object without duplicate or non-finite values."""
    text = (
        payload.decode("utf-8", errors="strict")
        if isinstance(payload, bytes)
        else payload
    )

    def reject_constant(_value: str) -> NoReturn:
        raise ValueError("non-finite JSON value")

    def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key")
            result[key] = value
        return result

    value = json.loads(
        text,
        object_pairs_hook=unique_object,
        parse_constant=reject_constant,
    )
    if not isinstance(value, dict):
        raise ValueError("JSON value is not an object")
    return value


def exact_nonnegative_integer(value: object, *, positive: bool = False) -> int:
    """Return VALUE as an exact nonnegative integer, rejecting booleans."""
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError("value is not an exact integer")
    if value < (1 if positive else 0):
        raise ValueError("integer is out of range")
    return value


def validate_watchdog_event(
    value: object,
    expected_pid: int | None = None,
    expected_run_id: str | None = None,
) -> dict[str, object]:
    """Validate one complete watchdog event and return its sanitized object."""
    if not isinstance(value, dict) or set(value) != WATCHDOG_EVENT_KEYS:
        raise ValueError("watchdog event schema mismatch")
    if type(value["schema_version"]) is not int or value["schema_version"] != 1:
        raise ValueError("unsupported watchdog event schema")
    run_id = value["run_id"]
    if not isinstance(run_id, str) or AGENT_KEY_PATTERN.fullmatch(run_id) is None:
        raise ValueError("invalid watchdog run id")
    if expected_run_id is not None and run_id != expected_run_id:
        raise ValueError("watchdog run id mismatch")
    daemon_pid = exact_nonnegative_integer(value["daemon_pid"], positive=True)
    if expected_pid is not None and daemon_pid != expected_pid:
        raise ValueError("watchdog daemon pid mismatch")
    if not isinstance(value["cause"], str) or value["cause"] not in WATCHDOG_CAUSES:
        raise ValueError("invalid watchdog cause")
    if not isinstance(value["phase"], str) or value["phase"] not in WATCHDOG_PHASES:
        raise ValueError("invalid watchdog phase")
    if not isinstance(value["method"], str) or value["method"] not in WATCHDOG_METHODS:
        raise ValueError("invalid watchdog method")
    tool = value["tool"]
    if tool is not None and (
        not isinstance(tool, str) or TOOL_PATTERN.fullmatch(tool) is None
    ):
        raise ValueError("invalid watchdog tool")
    exact_nonnegative_integer(value["observed_at_unix_ms"])
    exact_nonnegative_integer(value["daemon_uptime_ms"])
    for age_name, limit_name in (
        ("heartbeat_age_ms", "heartbeat_limit_ms"),
        ("dispatch_age_ms", "dispatch_limit_ms"),
    ):
        age = value[age_name]
        limit = value[limit_name]
        if (age is None) != (limit is None):
            raise ValueError("watchdog deadline fields have mismatched nullness")
        if age is not None:
            exact_nonnegative_integer(age)
            exact_nonnegative_integer(limit)
    payload = (
        json.dumps(
            value,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")
    if len(payload) > WATCHDOG_EVENT_MAX_BYTES:
        raise ValueError("watchdog event exceeds byte limit")
    return dict(value)


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


def unix_socket_path_limit_bytes(platform: str | None = None) -> int:
    """Return the pathname-byte ceiling for this supported kernel."""
    platform = sys.platform if platform is None else platform
    if platform.startswith("linux"):
        return LINUX_UNIX_SOCKET_PATH_BYTES
    return DARWIN_UNIX_SOCKET_PATH_BYTES


def validate_root_path(raw: str | Path, label: str) -> Path:
    """Return an absolute, lexically normalized private-state root."""
    try:
        raw_path = os.fspath(raw)
    except TypeError as error:
        raise ConfigurationError(
            f"{label} is not a filesystem path: {raw!r}"
        ) from error
    if not isinstance(raw_path, str):
        raise ConfigurationError(f"{label} is not a text path: {raw!r}")
    normalized = os.path.abspath(os.path.normpath(raw_path))
    if (
        not os.path.isabs(raw_path)
        or raw_path.startswith("//")
        or raw_path != normalized
    ):
        raise ConfigurationError(
            f"{label} must be an absolute normalized path: {raw!r}"
        )
    return Path(raw_path)


def validate_distinct_paths(runtime_path: Path, state_path: Path, label: str) -> None:
    """Reject a runtime/state pair that already resolves to one location."""
    runtime_canonical = Path(os.path.realpath(os.fspath(runtime_path)))
    state_canonical = Path(os.path.realpath(os.fspath(state_path)))
    runtime_key = unicodedata.normalize("NFC", os.fspath(runtime_canonical)).casefold()
    state_key = unicodedata.normalize("NFC", os.fspath(state_canonical)).casefold()
    try:
        same_inode = os.path.samefile(runtime_path, state_path)
    except FileNotFoundError:
        same_inode = False
    except OSError as error:
        raise ConfigurationError(f"cannot compare {label} paths: {error}") from error
    if (
        runtime_path == state_path
        or runtime_canonical == state_canonical
        or runtime_key == state_key
        or same_inode
    ):
        raise ConfigurationError(
            f"{label}: runtime and state directories must be distinct"
        )


def validate_worker_names(raw_names: list[str] | tuple[str, ...]) -> tuple[str, ...]:
    """Validate the Nix-generated worker roster as safe socket basenames."""
    if not raw_names:
        raise ConfigurationError("missing packaged worker roster")
    names: list[str] = []
    seen: set[str] = set()
    for raw in raw_names:
        if (
            not isinstance(raw, str)
            or raw in ("", ".", "..")
            or WORKER_NAME_PATTERN.fullmatch(raw) is None
        ):
            raise ConfigurationError(f"unsafe worker name: {raw!r}")
        key = raw.casefold()
        if key == "server":
            raise ConfigurationError(f"reserved worker name: {raw!r}")
        if key in seen:
            raise ConfigurationError(f"duplicate worker name: {raw!r}")
        seen.add(key)
        names.append(raw)
    return tuple(names)


def validate_socket_paths(
    socket_root: Path,
    worker_names: list[str] | tuple[str, ...],
) -> tuple[Path, ...]:
    """Return every root and worker socket path or reject an impossible one."""
    worker_names = validate_worker_names(worker_names)
    socket_paths = tuple(socket_root / name for name in ("server", *worker_names))
    for socket_path in socket_paths:
        validate_socket_path(socket_path)
    return socket_paths


def validate_socket_path(
    raw: str | Path,
    label: str = "Emacs socket path",
) -> Path:
    """Validate one absolute socket pathname against the kernel ceiling."""
    socket_path = validate_root_path(raw, label)
    limit = unix_socket_path_limit_bytes()
    encoded = os.fsencode(socket_path)
    if len(encoded) > limit:
        raise ConfigurationError(
            f"{label} exceeds the platform Unix socket limit "
            f"({len(encoded)} > {limit} bytes): {socket_path}"
        )
    return socket_path


def validate_emacs_socket_paths(
    runtime_root: Path,
    host: str,
    agent_key: str,
    worker_names: list[str] | tuple[str, ...],
) -> tuple[Path, ...]:
    """Return every prospective socket path or reject before publication."""
    runtime_root = validate_root_path(runtime_root, "runtime root")
    host = validate_host(host)
    agent_key = validate_agent_key(agent_key)
    runtime_dir = runtime_root / host / "agents" / agent_key
    validate_socket_path(
        runtime_dir / ACTIVITY_SOCKET_NAME,
        "Anvil activity socket path",
    )
    socket_root = runtime_dir / "emacs"
    return validate_socket_paths(socket_root, worker_names)


def validate_host_emacs_socket_paths(
    runtime_root: Path,
    host: str,
    worker_names: list[str] | tuple[str, ...],
) -> tuple[Path, ...]:
    """Validate the shared host-daemon root and worker socket paths."""
    runtime_root = validate_root_path(runtime_root, "runtime root")
    host = validate_host(host)
    runtime_dir = runtime_root / host
    validate_socket_path(
        runtime_dir / ACTIVITY_SOCKET_NAME,
        "Anvil activity socket path",
    )
    return validate_socket_paths(runtime_dir / "emacs", worker_names)


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


def session_gate_path(runtime_agents: Path, agent_key: str) -> Path:
    """Return the persistent per-session admission/retirement lock path."""
    return runtime_agents / (
        f"{SESSION_GATE_PREFIX}{validate_agent_key(agent_key)}{SESSION_GATE_SUFFIX}"
    )


def acquire_session_gate(path: Path, timeout_seconds: float) -> int:
    """Acquire one safe session gate with a bounded nonblocking retry."""
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
            raise ConfigurationError(f"unsafe session gate: {path}")
        os.fchmod(descriptor, 0o600)
        deadline = time.monotonic() + max(0.0, timeout_seconds)
        while True:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError as error:
                if error.errno not in (errno.EACCES, errno.EAGAIN):
                    raise
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"timed out acquiring session gate: {path}")
            time.sleep(min(POLL_SECONDS, remaining))
        current = os.stat(path, follow_symlinks=False)
        if (current.st_dev, current.st_ino) != identity:
            raise ConfigurationError(f"session gate changed: {path}")
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def owner_seed_record_fields(
    agent_key: str,
    owner_pid: int,
    owner_start_identity: str,
    generation: str,
) -> dict[str, object]:
    """Return the complete v2 owner seed used before runtime publication."""
    agent_key = validate_agent_key(agent_key)
    generation = validate_generation(generation)
    return {
        "daemon_pid": None,
        "format": RECORD_FORMAT_V2,
        "version": RECORD_FORMAT_V2,
        "generation": generation,
        "lease_count": 0,
        "last_watchdog": None,
        "agent_key": agent_key,
        "owner_pid": owner_pid,
        "owner_start_identity": owner_start_identity,
        "restart_count": 0,
        "restart_reason": None,
        "supervisor_pid": None,
        "supervisor_start_identity": None,
    }


def prepare_instance_directories(
    runtime_root: Path,
    state_root: Path,
    host: str,
    agent_key: str,
    owner_pid: int,
    owner_start_identity: str,
    generation: str,
) -> tuple[Path, Path, Path]:
    """Build attributed HOST/agents/HEX trees without consulting HOME."""
    agent_key = validate_agent_key(agent_key)
    runtime_host = runtime_root / host
    runtime_agents = runtime_host / "agents"
    state_host = state_root / host
    state_agents = state_host / "agents"
    for path in (runtime_root, runtime_host, runtime_agents):
        ensure_private_directory(path)

    # New pruners honor this marker while the populated runtime tree is hidden.
    # The final runtime publication itself must also be safe from the deployed
    # pre-marker pruner during a rolling generation upgrade.
    publish_creator_marker(
        runtime_agents,
        agent_key,
        owner_pid,
        owner_start_identity,
        generation,
    )

    runtime_dir = runtime_agents / agent_key
    state_dir = state_agents / agent_key
    publish_initial_runtime_instance(
        runtime_agents,
        agent_key,
        owner_pid,
        owner_start_identity,
        generation,
    )

    # Publish state only after the final runtime name already contains a live
    # v2 status and a non-statusless leases directory.  The deployed old
    # pruner therefore preserves the runtime throughout this remaining gap.
    for path in (state_root, state_host, state_agents, state_dir):
        ensure_private_directory(path)

    runtime_info = os.stat(runtime_dir, follow_symlinks=False)
    state_info = os.stat(state_dir, follow_symlinks=False)
    if (runtime_info.st_dev, runtime_info.st_ino) == (
        state_info.st_dev,
        state_info.st_ino,
    ):
        raise ConfigurationError("runtime and state instance directories coincide")

    leases_dir = runtime_dir / "leases"
    validate_initial_runtime_instance(
        runtime_dir,
        agent_key,
        owner_pid,
        owner_start_identity,
        generation,
    )
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
    owner_pid: int,
    owner_start_identity: str,
    generation: str,
    uid: int | None = None,
) -> str:
    """Derive one external-owner- and generation-qualified path component."""
    if not isinstance(owner_pid, int) or owner_pid <= 1:
        raise ConfigurationError("invalid external MCP owner PID")
    if not isinstance(owner_start_identity, str) or not owner_start_identity:
        raise ConfigurationError("invalid external MCP owner start identity")
    generation = validate_generation(generation)
    owner_uid = os.getuid() if uid is None else uid
    if not isinstance(owner_uid, int) or owner_uid < 0:
        raise ConfigurationError("invalid external MCP owner uid")
    material = (
        f"anvil-mcp-owner-v3\0{owner_uid}\0{owner_pid}\0"
        f"{owner_start_identity}\0{generation}"
    ).encode("utf-8")
    return hashlib.sha256(material).hexdigest()[:32]


def derive_legacy_agent_key_v2(
    owner_pid: int,
    owner_start_identity: str,
    generation: str,
    uid: int | None = None,
) -> str:
    """Recompute the deployed bridge-v2 key for preserve/prune migration."""
    if not isinstance(owner_pid, int) or owner_pid <= 1:
        raise ConfigurationError("invalid legacy MCP bridge PID")
    if not isinstance(owner_start_identity, str) or not owner_start_identity:
        raise ConfigurationError("invalid legacy MCP bridge start identity")
    generation = validate_generation(generation)
    owner_uid = os.getuid() if uid is None else uid
    if not isinstance(owner_uid, int) or owner_uid < 0:
        raise ConfigurationError("invalid legacy MCP bridge uid")
    material = (
        f"anvil-mcp-bridge-v2\0{owner_uid}\0{owner_pid}\0"
        f"{owner_start_identity}\0{generation}"
    ).encode("utf-8")
    return hashlib.sha256(material).hexdigest()[:32]


def owner_key_matches_known_scheme(
    agent_key: str,
    owner_pid: int,
    owner_start_identity: str,
    generation: str,
) -> bool:
    """Recognize current and deployed owner-key namespaces during migration."""
    return agent_key in {
        derive_agent_key(owner_pid, owner_start_identity, generation),
        derive_legacy_agent_key_v2(owner_pid, owner_start_identity, generation),
    }


def derive_managed_agent_key(
    instance_id: str,
    generation: str,
    uid: int | None = None,
) -> str:
    """Derive one stable root key for an agent-deck session and protocol."""
    if (
        not isinstance(instance_id, str)
        or AGENTDECK_INSTANCE_ID_PATTERN.fullmatch(instance_id) is None
    ):
        raise ConfigurationError("invalid agent-deck instance identity")
    generation = validate_generation(generation)
    owner_uid = os.getuid() if uid is None else uid
    if not isinstance(owner_uid, int) or owner_uid < 0:
        raise ConfigurationError("invalid agent-deck owner uid")
    material = (
        f"anvil-agentdeck-session-v1\0{owner_uid}\0{instance_id}\0{generation}"
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


def agent_deck_instance_id() -> str | None:
    """Return a validated session identity; malformed presence fails closed."""
    if "AGENTDECK_INSTANCE_ID" not in os.environ:
        return None
    instance_id = os.environ.get("AGENTDECK_INSTANCE_ID")
    if (
        not isinstance(instance_id, str)
        or AGENTDECK_INSTANCE_ID_PATTERN.fullmatch(instance_id) is None
    ):
        raise ConfigurationError("invalid AGENTDECK_INSTANCE_ID")
    return instance_id


def agent_deck_managed_bridge() -> bool:
    """Return whether a validated agent-deck session owns this bridge."""
    return agent_deck_instance_id() is not None


def identify_bridge(
    input_descriptor: int = 0,
    *,
    managed: bool | None = None,
) -> tuple[int, str]:
    """Identify the exact external process generation owning this bridge."""
    guarded_pid_raw = os.environ.pop(GUARDED_OWNER_PID_ENV, None)
    guarded_start_identity = os.environ.pop(GUARDED_OWNER_START_ENV, None)
    if input_pipe_closed(input_descriptor):
        raise ConfigurationError("MCP input pipe is closed")
    if managed is None:
        managed = agent_deck_managed_bridge()
    if not managed:
        bridge_pid = os.getpid()
        bridge_identity = process_start_identity(bridge_pid)
        if bridge_identity is None:
            raise ConfigurationError("cannot identify this MCP bridge process")
        if input_pipe_closed(input_descriptor):
            raise ConfigurationError("MCP input pipe closed during startup")
        return bridge_pid, bridge_identity
    if (
        guarded_pid_raw is None
        or not guarded_pid_raw.isascii()
        or not guarded_pid_raw.isdecimal()
        or guarded_start_identity is None
        or not guarded_start_identity
    ):
        raise ConfigurationError("missing guarded external MCP owner identity")
    owner_pid = int(guarded_pid_raw)
    if owner_pid <= 1:
        raise ConfigurationError("invalid guarded external MCP owner process")
    if os.getppid() != owner_pid:
        raise ConfigurationError("external MCP owner changed before startup")
    owner_state = validate_process_identity(owner_pid, guarded_start_identity)
    if owner_state is LifecycleState.UNAVAILABLE:
        raise ConfigurationError("external MCP owner identity is unavailable")
    if owner_state is LifecycleState.DEAD:
        raise ConfigurationError("external MCP owner process generation changed")
    if os.getppid() != owner_pid:
        raise ConfigurationError("external MCP owner changed during startup")
    if input_pipe_closed(input_descriptor):
        raise ConfigurationError("MCP input pipe closed during startup")
    return owner_pid, guarded_start_identity


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
    temp_name: str | None = None,
    no_clobber: bool = False,
) -> Path:
    """Publish one complete, private JSON file within DIRECTORY."""
    payload = (json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n").encode()
    if len(payload) > MAX_LEASE_BYTES:
        raise ConfigurationError("lifecycle record is unexpectedly large")
    if temp_name is None:
        temp_name = f".tmp-{os.getpid()}-{os.urandom(16).hex()}"
    if (
        not isinstance(temp_name, str)
        or not temp_name
        or temp_name in (".", "..", final_name)
        or "/" in temp_name
    ):
        raise ConfigurationError("unsafe temporary lifecycle record name")
    directory_fd = os.open(
        directory,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
    )
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
        if no_clobber:
            if replace:
                raise ConfigurationError("no-clobber publication cannot replace")
            rename_noreplace(directory_fd, temp_name, final_name)
        else:
            if not replace:
                try:
                    os.stat(
                        final_name,
                        dir_fd=directory_fd,
                        follow_symlinks=False,
                    )
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


def creator_marker_name(agent_key: str) -> str:
    """Return the parent-level marker name for one generation-qualified key."""
    return (
        f"{CREATOR_MARKER_PREFIX}{validate_agent_key(agent_key)}{CREATOR_MARKER_SUFFIX}"
    )


def creator_marker_agent_key(name: str) -> str | None:
    """Extract a valid agent key from a parent-level creator marker name."""
    if not name.startswith(CREATOR_MARKER_PREFIX) or not name.endswith(
        CREATOR_MARKER_SUFFIX
    ):
        return None
    key = name[len(CREATOR_MARKER_PREFIX) : -len(CREATOR_MARKER_SUFFIX)]
    try:
        return validate_agent_key(key)
    except ConfigurationError:
        return None


def creator_staging_name(
    agent_key: str,
    owner_pid: int,
    generation: str,
) -> str:
    """Name an attributable pre-publication file for interrupted-start cleanup."""
    agent_key = validate_agent_key(agent_key)
    generation = validate_generation(generation)
    if not isinstance(owner_pid, int) or owner_pid <= 1:
        raise ConfigurationError("invalid creator PID")
    return (
        f"{CREATOR_STAGING_PREFIX}{agent_key}-{owner_pid}-{generation}-"
        f"{os.urandom(16).hex()}{CREATOR_MARKER_SUFFIX}"
    )


def creator_staging_details(name: str) -> tuple[str, int, str] | None:
    """Parse a creator staging name without trusting its file contents."""
    if not name.startswith(CREATOR_STAGING_PREFIX) or not name.endswith(
        CREATOR_MARKER_SUFFIX
    ):
        return None
    body = name[len(CREATOR_STAGING_PREFIX) : -len(CREATOR_MARKER_SUFFIX)]
    parts = body.split("-")
    if len(parts) != 4:
        return None
    agent_key, pid_text, generation, token = parts
    try:
        agent_key = validate_agent_key(agent_key)
        generation = validate_generation(generation)
    except ConfigurationError:
        return None
    if (
        not pid_text.isdecimal()
        or int(pid_text) <= 1
        or AGENT_KEY_PATTERN.fullmatch(token) is None
    ):
        return None
    return agent_key, int(pid_text), generation


def instance_staging_name(
    agent_key: str,
    owner_pid: int,
    generation: str,
) -> str:
    """Name one hidden runtime tree before its atomic publication."""
    agent_key = validate_agent_key(agent_key)
    generation = validate_generation(generation)
    if not isinstance(owner_pid, int) or owner_pid <= 1:
        raise ConfigurationError("invalid creator PID")
    return (
        f"{INSTANCE_STAGING_PREFIX}{agent_key}-{owner_pid}-{generation}-"
        f"{os.urandom(16).hex()}"
    )


def instance_staging_details(name: str) -> tuple[str, int, str] | None:
    """Parse an attributed hidden runtime directory name."""
    if not name.startswith(INSTANCE_STAGING_PREFIX):
        return None
    parts = name[len(INSTANCE_STAGING_PREFIX) :].split("-")
    if len(parts) != 4:
        return None
    agent_key, pid_text, generation, token = parts
    try:
        agent_key = validate_agent_key(agent_key)
        generation = validate_generation(generation)
    except ConfigurationError:
        return None
    if (
        not pid_text.isdecimal()
        or int(pid_text) <= 1
        or AGENT_KEY_PATTERN.fullmatch(token) is None
    ):
        return None
    return agent_key, int(pid_text), generation


def rename_noreplace(
    directory_fd: int,
    source: str,
    destination: str,
) -> None:
    """Atomically rename one path while refusing any destination."""
    library = ctypes.CDLL(None, use_errno=True)
    source_bytes = os.fsencode(source)
    destination_bytes = os.fsencode(destination)
    if sys.platform == "darwin":
        rename = getattr(library, "renameatx_np", None)
        if rename is None:
            raise ConfigurationError("renameatx_np is unavailable")
        rename.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        rename.restype = ctypes.c_int
        result = rename(
            directory_fd,
            source_bytes,
            directory_fd,
            destination_bytes,
            0x00000004,  # RENAME_EXCL
        )
    elif sys.platform.startswith("linux"):
        rename = getattr(library, "renameat2", None)
        if rename is None:
            raise ConfigurationError("renameat2 is unavailable")
        rename.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        rename.restype = ctypes.c_int
        result = rename(
            directory_fd,
            source_bytes,
            directory_fd,
            destination_bytes,
            0x00000001,  # RENAME_NOREPLACE
        )
    else:
        raise ConfigurationError("atomic no-replace rename is unsupported")
    if result != 0:
        error_number = ctypes.get_errno()
        raise OSError(
            error_number,
            os.strerror(error_number),
            destination,
        )


def prune_instance_staging(
    runtime_agents: Path,
    name: str,
) -> tuple[str, bool] | None:
    """Preserve a live hidden runtime tree or remove a dead one safely."""
    details = instance_staging_details(name)
    if details is None:
        return None
    agent_key, owner_pid, generation = details
    staging = runtime_agents / name
    try:
        info = staging.lstat()
        if (
            not stat.S_ISDIR(info.st_mode)
            or stat.S_ISLNK(info.st_mode)
            or info.st_uid != os.getuid()
            or stat.S_IMODE(info.st_mode) != 0o700
        ):
            return agent_key, False
        staging_identity = (info.st_dev, info.st_ino)
        owner_state, current_identity = process_start_state(owner_pid)
        if owner_state is LifecycleState.UNAVAILABLE:
            return agent_key, False
        if owner_state is LifecycleState.LIVE and current_identity is not None:
            creator_state, creator, _creator_identity = read_creator_lifecycle(
                runtime_agents,
                agent_key,
            )
            if (
                creator_state is LifecycleState.LIVE
                and creator is not None
                and creator.get("owner_pid") == owner_pid
                and creator.get("owner_start_identity") == current_identity
                and creator.get("generation") == generation
            ):
                return agent_key, False
            try:
                if owner_key_matches_known_scheme(
                    agent_key,
                    owner_pid,
                    current_identity,
                    generation,
                ):
                    return agent_key, False
            except ConfigurationError:
                return agent_key, False
        remove_instance_tree(
            staging,
            expected_identity=staging_identity,
        )
        return agent_key, not os.path.lexists(staging)
    except (ConfigurationError, FileNotFoundError, PermissionError, OSError):
        return agent_key, not os.path.lexists(staging)


def prune_creator_staging(runtime_agents: Path, name: str) -> str | None:
    """Reap one safe staging inode only after its encoded creator is dead."""
    details = creator_staging_details(name)
    if details is None:
        return None
    agent_key, owner_pid, generation = details
    directory_fd = None
    descriptor = None
    try:
        directory_fd = os.open(
            runtime_agents,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
        directory_info = os.fstat(directory_fd)
        if (
            not stat.S_ISDIR(directory_info.st_mode)
            or directory_info.st_uid != os.getuid()
            or stat.S_IMODE(directory_info.st_mode) != 0o700
        ):
            return agent_key
        try:
            info = os.stat(
                name,
                dir_fd=directory_fd,
                follow_symlinks=False,
            )
        except FileNotFoundError:
            return agent_key
        identity = (info.st_dev, info.st_ino)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or stat.S_IMODE(info.st_mode) != 0o600
            or info.st_nlink not in (1, 2)
        ):
            return agent_key
        try:
            descriptor = os.open(
                name,
                os.O_RDONLY | os.O_NOFOLLOW,
                dir_fd=directory_fd,
            )
            opened = os.fstat(descriptor)
            if (opened.st_dev, opened.st_ino) != identity:
                return agent_key
            payload = os.read(descriptor, MAX_LEASE_BYTES + 1)
            record = json.loads(payload.decode("utf-8"))
        except OSError:
            return agent_key
        except (ValueError, UnicodeError):
            # A creator may die after publishing only a prefix.  The encoded
            # exact owner identity, not parseability of that incomplete
            # payload, decides whether the captured staging inode is stale.
            record = None
        if info.st_nlink == 2:
            try:
                marker_info = os.stat(
                    creator_marker_name(agent_key),
                    dir_fd=directory_fd,
                    follow_symlinks=False,
                )
            except FileNotFoundError:
                return agent_key
            if (marker_info.st_dev, marker_info.st_ino) != identity:
                return agent_key

        owner_state, current_identity = process_start_state(owner_pid)
        if owner_state is LifecycleState.UNAVAILABLE:
            return agent_key
        if owner_state is LifecycleState.LIVE:
            if current_identity is None:
                return agent_key
            if (
                isinstance(record, dict)
                and record.get("agent_key") == agent_key
                and record.get("owner_pid") == owner_pid
                and record.get("owner_start_identity") == current_identity
                and record.get("generation") == generation
                and record.get("uid") == os.getuid()
            ):
                return agent_key
            try:
                known_owner_key = owner_key_matches_known_scheme(
                    agent_key,
                    owner_pid,
                    current_identity,
                    generation,
                )
            except ConfigurationError:
                return agent_key
            if known_owner_key:
                return agent_key

        unlink_if_identity(directory_fd, name, identity)
        os.fsync(directory_fd)
        return agent_key
    except OSError:
        return agent_key
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if directory_fd is not None:
            os.close(directory_fd)


def creator_record(
    agent_key: str,
    owner_pid: int,
    owner_start_identity: str,
    generation: str,
) -> dict[str, object]:
    """Build a marker whose contents cryptographically bind to AGENT_KEY."""
    agent_key = validate_agent_key(agent_key)
    generation = validate_generation(generation)
    owner_state = validate_process_identity(owner_pid, owner_start_identity)
    if owner_state is LifecycleState.UNAVAILABLE:
        raise lifecycle_unavailable("creator process identity is unavailable")
    if owner_state is not LifecycleState.LIVE:
        raise ConfigurationError("creator process generation is not live")
    return {
        "agent_key": agent_key,
        "format": RECORD_FORMAT_V2,
        "generation": generation,
        "owner_pid": owner_pid,
        "owner_start_identity": owner_start_identity,
        "uid": os.getuid(),
        "version": RECORD_FORMAT_V2,
    }


def read_creator_lifecycle(
    runtime_agents: Path,
    agent_key: str,
) -> tuple[
    LifecycleState | None,
    dict[str, object] | None,
    tuple[int, int] | None,
]:
    """Read one safe creator marker; None means that no marker was published."""
    name = creator_marker_name(agent_key)
    directory_fd = None
    descriptor = None
    try:
        directory_fd = os.open(
            runtime_agents,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
        directory_info = os.fstat(directory_fd)
        if (
            not stat.S_ISDIR(directory_info.st_mode)
            or directory_info.st_uid != os.getuid()
            or stat.S_IMODE(directory_info.st_mode) != 0o700
        ):
            return LifecycleState.UNAVAILABLE, None, None
        try:
            descriptor = os.open(
                name,
                os.O_RDONLY | os.O_NOFOLLOW,
                dir_fd=directory_fd,
            )
        except FileNotFoundError:
            return None, None, None
        descriptor_info = os.fstat(descriptor)
        try:
            path_info = os.stat(
                name,
                dir_fd=directory_fd,
                follow_symlinks=False,
            )
        except FileNotFoundError:
            return LifecycleState.UNAVAILABLE, None, None
        identity = (descriptor_info.st_dev, descriptor_info.st_ino)
        if (
            not stat.S_ISREG(descriptor_info.st_mode)
            or descriptor_info.st_uid != os.getuid()
            or descriptor_info.st_nlink != 1
            or stat.S_IMODE(descriptor_info.st_mode) != 0o600
            or (path_info.st_dev, path_info.st_ino) != identity
        ):
            return LifecycleState.UNAVAILABLE, None, identity
        payload = os.read(descriptor, MAX_LEASE_BYTES + 1)
        if len(payload) > MAX_LEASE_BYTES:
            return LifecycleState.UNAVAILABLE, None, identity
        record = json.loads(payload.decode("utf-8"))
        expected_keys = {
            "agent_key",
            "format",
            "generation",
            "owner_pid",
            "owner_start_identity",
            "uid",
            "version",
        }
        if (
            not isinstance(record, dict)
            or set(record) != expected_keys
            or record.get("format") != RECORD_FORMAT_V2
            or record.get("version") != RECORD_FORMAT_V2
            or record.get("uid") != os.getuid()
            or record.get("agent_key") != agent_key
        ):
            return LifecycleState.UNAVAILABLE, None, identity
        owner_pid = record.get("owner_pid")
        owner_identity = record.get("owner_start_identity")
        generation = record.get("generation")
        if (
            not isinstance(owner_pid, int)
            or owner_pid <= 1
            or not isinstance(owner_identity, str)
            or not owner_identity
        ):
            return LifecycleState.UNAVAILABLE, None, identity
        try:
            generation = validate_generation(generation)
        except ConfigurationError:
            return LifecycleState.UNAVAILABLE, None, identity
        return (
            validate_process_identity(owner_pid, owner_identity),
            record,
            identity,
        )
    except FileNotFoundError:
        return None, None, None
    except (OSError, ValueError, UnicodeError):
        return LifecycleState.UNAVAILABLE, None, None
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if directory_fd is not None:
            os.close(directory_fd)


def publish_creator_marker(
    runtime_agents: Path,
    agent_key: str,
    owner_pid: int,
    owner_start_identity: str,
    generation: str,
) -> Path:
    """Publish creator identity atomically before making its runtime tree."""
    record = creator_record(
        agent_key,
        owner_pid,
        owner_start_identity,
        generation,
    )
    def compatible(existing_record: dict[str, object] | None) -> bool:
        return bool(
            existing_record is not None
            and existing_record.get("agent_key") == agent_key
            and existing_record.get("generation") == generation
            and existing_record.get("format") == RECORD_FORMAT_V2
            and existing_record.get("version") == RECORD_FORMAT_V2
            and existing_record.get("uid") == os.getuid()
        )

    state, existing, identity = read_creator_lifecycle(runtime_agents, agent_key)
    if state is not None:
        if state is LifecycleState.LIVE and compatible(existing):
            return runtime_agents / creator_marker_name(agent_key)
        if state is LifecycleState.DEAD and identity is not None:
            if not remove_dead_creator_marker(runtime_agents, agent_key, identity):
                raise ConfigurationError("dead creator marker changed")
        else:
            raise ConfigurationError("unsafe or mismatched creator marker")
    try:
        marker = atomic_json(
            runtime_agents,
            creator_marker_name(agent_key),
            record,
            replace=False,
            temp_name=creator_staging_name(
                agent_key,
                owner_pid,
                generation,
            ),
            no_clobber=True,
        )
    except FileExistsError:
        marker = runtime_agents / creator_marker_name(agent_key)
    state, existing, _identity = read_creator_lifecycle(runtime_agents, agent_key)
    if state is not LifecycleState.LIVE or not compatible(existing):
        raise ConfigurationError("creator marker publication could not be verified")
    return marker


def remove_cycle_creator_marker(runtime_agents: Path, agent_key: str) -> None:
    """Remove the exact creator marker while the session gate is held."""
    _state, _record, identity = read_creator_lifecycle(runtime_agents, agent_key)
    if identity is None:
        return
    directory_fd = os.open(
        runtime_agents,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
    )
    try:
        unlink_if_identity(
            directory_fd,
            creator_marker_name(agent_key),
            identity,
        )
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def validate_initial_runtime_instance(
    runtime_dir: Path,
    agent_key: str,
    owner_pid: int,
    owner_start_identity: str,
    generation: str,
) -> None:
    """Require one pinned, populated runtime owned by this exact generation."""
    directory_fd = None
    leases_fd = None
    try:
        path_info = runtime_dir.lstat()
        directory_fd = os.open(
            runtime_dir,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
        directory_info = os.fstat(directory_fd)
        identity = (directory_info.st_dev, directory_info.st_ino)
        if (
            not stat.S_ISDIR(directory_info.st_mode)
            or directory_info.st_uid != os.getuid()
            or stat.S_IMODE(directory_info.st_mode) != 0o700
            or identity != (path_info.st_dev, path_info.st_ino)
        ):
            raise ConfigurationError("published runtime directory is unsafe")

        lifecycle = read_status_lifecycle(
            runtime_dir,
            agent_key,
            directory_fd=directory_fd,
        )
        if (
            lifecycle is None
            or lifecycle[2] != generation
            or lifecycle[3] != RECORD_FORMAT_V2
        ):
            raise ConfigurationError("published runtime owner status is unavailable")

        leases_info = os.stat(
            "leases",
            dir_fd=directory_fd,
            follow_symlinks=False,
        )
        leases_fd = os.open(
            "leases",
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
            dir_fd=directory_fd,
        )
        opened_leases = os.fstat(leases_fd)
        if (
            not stat.S_ISDIR(opened_leases.st_mode)
            or opened_leases.st_uid != os.getuid()
            or stat.S_IMODE(opened_leases.st_mode) != 0o700
            or (opened_leases.st_dev, opened_leases.st_ino)
            != (leases_info.st_dev, leases_info.st_ino)
        ):
            raise ConfigurationError("published runtime leases directory is unsafe")

        current = runtime_dir.lstat()
        if identity != (current.st_dev, current.st_ino):
            raise ConfigurationError("published runtime directory changed")
        lifecycle = read_status_lifecycle(
            runtime_dir,
            agent_key,
            directory_fd=directory_fd,
        )
        if (
            lifecycle is None
            or lifecycle[2] != generation
            or lifecycle[3] != RECORD_FORMAT_V2
        ):
            raise ConfigurationError("published runtime owner status changed")
        current_leases = os.stat(
            "leases",
            dir_fd=directory_fd,
            follow_symlinks=False,
        )
        if (opened_leases.st_dev, opened_leases.st_ino) != (
            current_leases.st_dev,
            current_leases.st_ino,
        ):
            raise ConfigurationError("published runtime leases directory changed")
    except FileNotFoundError as error:
        raise ConfigurationError(
            "published runtime directory is unavailable"
        ) from error
    except OSError as error:
        raise ConfigurationError(
            f"cannot validate published runtime directory: {error}"
        ) from error
    finally:
        if leases_fd is not None:
            os.close(leases_fd)
        if directory_fd is not None:
            os.close(directory_fd)


def publish_initial_runtime_instance(
    runtime_agents: Path,
    agent_key: str,
    owner_pid: int,
    owner_start_identity: str,
    generation: str,
) -> Path:
    """Publish a populated runtime directory atomically under its final key."""
    agent_key = validate_agent_key(agent_key)
    generation = validate_generation(generation)
    runtime_dir = runtime_agents / agent_key
    try:
        runtime_dir.lstat()
    except FileNotFoundError:
        pass
    else:
        validate_initial_runtime_instance(
            runtime_dir,
            agent_key,
            owner_pid,
            owner_start_identity,
            generation,
        )
        return runtime_dir

    staging_name = instance_staging_name(agent_key, owner_pid, generation)
    staging = runtime_agents / staging_name
    staged_identity: tuple[int, int] | None = None
    try:
        try:
            staging.mkdir(mode=0o700)
        except FileExistsError as error:
            raise ConfigurationError("runtime staging name collision") from error
        ensure_private_directory(staging)
        staged_info = staging.lstat()
        staged_identity = (staged_info.st_dev, staged_info.st_ino)
        ensure_private_directory(staging / "leases")
        atomic_json(
            staging,
            STATUS_NAME,
            owner_seed_record_fields(
                agent_key,
                owner_pid,
                owner_start_identity,
                generation,
            ),
            replace=False,
            durable=True,
        )
        directory_fd = os.open(
            runtime_agents,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
        try:
            parent_info = os.fstat(directory_fd)
            if (
                not stat.S_ISDIR(parent_info.st_mode)
                or parent_info.st_uid != os.getuid()
                or stat.S_IMODE(parent_info.st_mode) != 0o700
            ):
                raise ConfigurationError("unsafe runtime agents directory")
            try:
                rename_noreplace(
                    directory_fd,
                    staging_name,
                    agent_key,
                )
            except OSError as error:
                if error.errno not in (errno.EEXIST, errno.ENOTEMPTY):
                    raise
            else:
                final_info = os.stat(
                    agent_key,
                    dir_fd=directory_fd,
                    follow_symlinks=False,
                )
                if (final_info.st_dev, final_info.st_ino) != staged_identity:
                    raise ConfigurationError("published runtime directory changed")
                os.fsync(directory_fd)
        finally:
            os.close(directory_fd)

        if staged_identity is not None and os.path.lexists(staging):
            remove_instance_tree(
                staging,
                expected_identity=staged_identity,
            )
        validate_initial_runtime_instance(
            runtime_dir,
            agent_key,
            owner_pid,
            owner_start_identity,
            generation,
        )
        return runtime_dir
    except BaseException:
        if staged_identity is not None and os.path.lexists(staging):
            try:
                remove_instance_tree(
                    staging,
                    expected_identity=staged_identity,
                )
            except (ConfigurationError, FileNotFoundError, OSError):
                pass
        raise


def remove_dead_creator_marker(
    runtime_agents: Path,
    agent_key: str,
    expected_identity: tuple[int, int],
) -> bool:
    """Unlink the same marker only while its exact creator remains dead."""
    state, _record, identity = read_creator_lifecycle(runtime_agents, agent_key)
    if state is None:
        return True
    if state is not LifecycleState.DEAD or identity != expected_identity:
        return False
    directory_fd = os.open(
        runtime_agents,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
    )
    try:
        directory_info = os.fstat(directory_fd)
        if (
            not stat.S_ISDIR(directory_info.st_mode)
            or directory_info.st_uid != os.getuid()
            or stat.S_IMODE(directory_info.st_mode) != 0o700
        ):
            return False
        unlink_if_identity(
            directory_fd,
            creator_marker_name(agent_key),
            expected_identity,
        )
        os.fsync(directory_fd)
        return True
    finally:
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
        lease_owner_pid = record["owner_pid"]
        lease_owner_identity = record["owner_start_identity"]
        if (
            not isinstance(bridge_pid, int)
            or bridge_pid <= 1
            or not isinstance(lease_owner_pid, int)
            or lease_owner_pid <= 1
            or not isinstance(lease_owner_identity, str)
            or not lease_owner_identity
            or record["uid"] != os.getuid()
            or record["server_id"] not in SERVER_IDS
            or record["agent_key"] != agent_key
            or not isinstance(record["bridge_start_identity"], str)
        ):
            return LifecycleState.DEAD, None
        owner_state = validate_process_identity(
            lease_owner_pid,
            lease_owner_identity,
        )
        if owner_state is not LifecycleState.LIVE:
            return owner_state, None
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
            lease_state, record = read_lease(
                directory_fd,
                name,
                agent_key,
                owner_pid,
                owner_start_identity,
                generation,
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


def remove_directory_contents(
    directory_fd: int,
    device: int,
    *,
    final_names: tuple[str, ...] = (),
) -> None:
    """Remove one private tree through descriptors without following links."""
    for name in os.listdir(directory_fd):
        if name in final_names:
            continue
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
                    or identity != (info.st_dev, info.st_ino)
                    or identity != (current.st_dev, current.st_ino)
                ):
                    raise ConfigurationError("private state directory changed")
                if stat.S_IMODE(opened.st_mode) != 0o700:
                    # Read-only caches are common beneath private tmp trees.
                    # Widen only the validated, owner-owned open directory.
                    os.fchmod(child_fd, 0o700)
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
    for final_name in final_names:
        try:
            os.unlink(final_name, dir_fd=directory_fd)
        except FileNotFoundError:
            pass


def remove_instance_tree(
    path: Path,
    *,
    final_names: tuple[str, ...] = (),
    expected_identity: tuple[int, int] | None = None,
) -> None:
    """Remove one exact agent instance without following links."""
    try:
        parent_fd = os.open(
            path.parent,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
    except FileNotFoundError:
        return
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
        path_identity = (path_info.st_dev, path_info.st_ino)
        if expected_identity is not None and path_identity != expected_identity:
            raise ConfigurationError("agent-instance directory identity changed")
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
            or identity != path_identity
        ):
            raise ConfigurationError("unsafe agent-instance directory")
        remove_directory_contents(
            child_fd,
            opened.st_dev,
            final_names=final_names,
        )
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
    *,
    directory_fd: int | None = None,
) -> tuple[int, str, str | None, int] | None:
    """Read a trusted v1/v2 lifetime identity from private supervisor state."""
    close_directory = directory_fd is None
    descriptor = None
    try:
        if directory_fd is None:
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
        if close_directory and directory_fd is not None:
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
    """Prune dead creators' runtime trees, state twins, and ownership markers."""
    def lease_context(
        lifecycle: tuple[int, str, str | None, int] | None,
        creator: dict[str, object] | None,
    ) -> tuple[int, str, str | None] | None:
        if lifecycle is not None:
            return lifecycle[0], lifecycle[1], lifecycle[2]
        if creator is None:
            return None
        owner_pid = creator.get("owner_pid")
        owner_identity = creator.get("owner_start_identity")
        generation = creator.get("generation")
        if (
            not isinstance(owner_pid, int)
            or owner_pid <= 1
            or not isinstance(owner_identity, str)
            or not owner_identity
        ):
            return None
        try:
            generation = validate_generation(generation)
        except ConfigurationError:
            return None
        return owner_pid, owner_identity, generation

    def root_has_live_leases(
        runtime_path: Path,
        name: str,
        context: tuple[int, str, str | None] | None,
    ) -> bool:
        if context is None:
            return False
        try:
            leases = live_leases(
                runtime_path / "leases",
                name,
                context[0],
                context[1],
                context[2],
            )
        except FileNotFoundError:
            return False
        return bool(leases)

    def prune_candidate(name: str) -> None:
        try:
            entries = os.listdir(runtime_agents)
        except (FileNotFoundError, PermissionError, OSError):
            return
        for entry in entries:
            instance_details = instance_staging_details(entry)
            if instance_details is not None and instance_details[0] == name:
                result = prune_instance_staging(runtime_agents, entry)
                if result is not None and not result[1]:
                    return
                continue
            creator_details = creator_staging_details(entry)
            if creator_details is not None and creator_details[0] == name:
                prune_creator_staging(runtime_agents, entry)

        creator_state, creator, creator_identity = read_creator_lifecycle(
            runtime_agents,
            name,
        )
        if creator_state in (LifecycleState.LIVE, LifecycleState.UNAVAILABLE):
            return

        runtime_path = runtime_agents / name
        state_path = state_agents / name
        try:
            runtime_info = runtime_path.lstat()
        except FileNotFoundError:
            runtime_info = None
        safe_runtime = (
            runtime_info is not None
            and stat.S_ISDIR(runtime_info.st_mode)
            and not stat.S_ISLNK(runtime_info.st_mode)
            and runtime_info.st_uid == os.getuid()
            and stat.S_IMODE(runtime_info.st_mode) == 0o700
        )
        if runtime_info is not None and not safe_runtime:
            return

        if safe_runtime:
            lifecycle = read_status_lifecycle(runtime_path, name)
            try:
                if root_has_live_leases(
                    runtime_path,
                    name,
                    lease_context(lifecycle, creator),
                ):
                    return
            except (ConfigurationError, OSError):
                return
            owner = read_status_owner(runtime_path, name)
            # A deployed pre-marker creator publishes its empty runtime name
            # before state, leases, or owner status.  No elapsed-time rule can
            # distinguish a dead partial tree from that live process paused at
            # an arbitrary syscall.  Preserve this legacy ambiguity forever;
            # new generations are attributable through their creator marker.
            if creator_state is None and owner is None:
                return
            if owner is not None and (
                validate_process_identity(owner[0], owner[1])
                is not LifecycleState.DEAD
            ):
                return
            try:
                locked = try_supervisor_lock(runtime_path)
            except (ConfigurationError, FileNotFoundError, OSError):
                return
            if locked is None:
                return
            lock_descriptor, lock_identity = locked
            reaped = False
            try:
                validate_supervisor_lock(
                    lock_descriptor,
                    runtime_path / LOCK_NAME,
                    lock_identity,
                )
                confirmed_creator, confirmed_record, confirmed_creator_identity = (
                    read_creator_lifecycle(runtime_agents, name)
                )
                if creator_state is LifecycleState.DEAD:
                    if (
                        confirmed_creator is not LifecycleState.DEAD
                        or confirmed_creator_identity != creator_identity
                    ):
                        return
                elif confirmed_creator is not None:
                    return

                confirmed_lifecycle = read_status_lifecycle(runtime_path, name)
                try:
                    if root_has_live_leases(
                        runtime_path,
                        name,
                        lease_context(confirmed_lifecycle, confirmed_record),
                    ):
                        return
                except (ConfigurationError, OSError):
                    return
                confirmed = (
                    None
                    if confirmed_lifecycle is None
                    else (confirmed_lifecycle[0], confirmed_lifecycle[1])
                )
                if creator_state is LifecycleState.DEAD:
                    if confirmed is not None and (
                        validate_process_identity(confirmed[0], confirmed[1])
                        is not LifecycleState.DEAD
                    ):
                        return
                    remove_instance_tree(state_path)
                elif (
                    confirmed is None
                    or validate_process_identity(confirmed[0], confirmed[1])
                    is not LifecycleState.DEAD
                ):
                    return
                else:
                    remove_instance_tree(state_path)

                # Keep the named, locked inode reachable while deleting the
                # deferred owner record.  Once LOCK_NAME is unlinked, another
                # supervisor may create a replacement, so perform no further
                # runtime-tree unlinks after that point.
                remove_instance_tree(
                    runtime_path,
                    final_names=(STATUS_NAME, LOCK_NAME),
                )
                reaped = True
            except (ConfigurationError, FileNotFoundError, OSError, RuntimeError):
                return
            finally:
                os.close(lock_descriptor)

            if (
                reaped
                and creator_state is LifecycleState.DEAD
                and creator_identity is not None
            ):
                try:
                    remove_dead_creator_marker(
                        runtime_agents,
                        name,
                        creator_identity,
                    )
                except (ConfigurationError, FileNotFoundError, OSError):
                    pass
            return

        try:
            remove_instance_tree(state_path)
        except (ConfigurationError, FileNotFoundError, OSError):
            return
        if creator_state is LifecycleState.DEAD and creator_identity is not None:
            try:
                remove_dead_creator_marker(
                    runtime_agents,
                    name,
                    creator_identity,
                )
            except (ConfigurationError, FileNotFoundError, OSError):
                return

    names: set[str] = set()
    for agents_dir in (runtime_agents, state_agents):
        try:
            entries = os.listdir(agents_dir)
        except (FileNotFoundError, PermissionError, OSError):
            continue
        for entry in entries:
            if AGENT_KEY_PATTERN.fullmatch(entry) is not None:
                names.add(entry)
            elif agents_dir == runtime_agents:
                instance_details = instance_staging_details(entry)
                if instance_details is not None:
                    names.add(instance_details[0])
                    continue
                creator_details = creator_staging_details(entry)
                if creator_details is not None:
                    names.add(creator_details[0])
                    continue
                marker_key = creator_marker_agent_key(entry)
                if marker_key is not None:
                    names.add(marker_key)

    for name in sorted(names):
        if name == current_agent_key:
            continue
        try:
            gate_descriptor = acquire_session_gate(
                session_gate_path(runtime_agents, name),
                0.0,
            )
        except (ConfigurationError, OSError):
            continue
        try:
            prune_candidate(name)
        finally:
            os.close(gate_descriptor)


def cleanup_instance(args: argparse.Namespace) -> None:
    """Best-effort cleanup of one retired session cycle."""
    cleanup_complete = True
    for path in (args.state_dir, args.runtime_dir):
        try:
            remove_instance_tree(path)
        except (ConfigurationError, FileNotFoundError, OSError):
            cleanup_complete = False
        if os.path.lexists(path):
            cleanup_complete = False
    if not cleanup_complete:
        return

    try:
        remove_cycle_creator_marker(args.runtime_dir.parent, args.agent_key)
    except (ConfigurationError, FileNotFoundError, OSError):
        pass


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
    environment.pop("ANVIL_MCP_READINESS_MODE", None)
    environment.pop("ANVIL_EMACS_SOCKET", None)
    environment.pop("ANVIL_EMACS_USE_SYSTEM_LOG", None)
    environment.pop(WATCHDOG_SUPERVISED_ENV, None)
    environment.pop(WATCHDOG_EVENT_FD_ENV, None)
    environment.pop(WATCHDOG_RUN_ID_ENV, None)
    environment.pop(GUARDED_OWNER_PID_ENV, None)
    environment.pop(GUARDED_OWNER_START_ENV, None)
    environment.pop("AGENTDECK_INSTANCE_ID", None)
    return environment


def create_watchdog_event_pipe() -> tuple[int, int]:
    """Return fresh nonblocking read/write ends with the writer above fd 9."""
    read_descriptor: int | None = None
    write_descriptor: int | None = None
    high_write_descriptor: int | None = None
    try:
        read_descriptor, write_descriptor = os.pipe()
        high_write_descriptor = fcntl.fcntl(write_descriptor, fcntl.F_DUPFD, 10)
        os.close(write_descriptor)
        write_descriptor = None
        os.set_blocking(read_descriptor, False)
        os.set_blocking(high_write_descriptor, False)
        os.set_inheritable(read_descriptor, False)
        os.set_inheritable(high_write_descriptor, False)
        return read_descriptor, high_write_descriptor
    except BaseException:
        for descriptor in (
            read_descriptor,
            write_descriptor,
            high_write_descriptor,
        ):
            if descriptor is not None:
                try:
                    os.close(descriptor)
                except OSError:
                    pass
        raise


def transport_environment() -> dict[str, str]:
    """Return a client environment that cannot launch a fallback editor."""
    environment = os.environ.copy()
    environment.pop("ALTERNATE_EDITOR", None)
    environment.pop(GUARDED_OWNER_PID_ENV, None)
    environment.pop(GUARDED_OWNER_START_ENV, None)
    environment.pop("AGENTDECK_INSTANCE_ID", None)
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
    drained = 0
    while drained < MAX_DAEMON_DIAGNOSTIC_DRAIN_BYTES:
        try:
            chunk = os.read(
                read_descriptor,
                min(16384, MAX_DAEMON_DIAGNOSTIC_DRAIN_BYTES - drained),
            )
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
        drained += len(chunk)
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
    pending_error: BaseException | None = None
    try:
        drain_daemon_diagnostic(process)
    except BaseException as error:
        pending_error = error
    for attribute in (
        "_anvil_diagnostic_read_fd",
        "_anvil_diagnostic_output_fd",
    ):
        descriptor = getattr(process, attribute, None)
        setattr(process, attribute, None)
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError as error:
                if pending_error is None:
                    pending_error = error
    if pending_error is not None:
        raise pending_error


def read_watchdog_event(
    process: subprocess.Popen[bytes],
    expected_pid: int,
    expected_run_id: str,
) -> dict[str, object] | None:
    """Read and close one process-specific watchdog event capability."""
    descriptor = getattr(process, "_anvil_watchdog_event_read_fd", None)
    if descriptor is None:
        return None
    setattr(process, "_anvil_watchdog_event_read_fd", None)
    try:
        try:
            payload = os.read(descriptor, WATCHDOG_EVENT_MAX_BYTES + 1)
        except BlockingIOError:
            return None
        if (
            not payload
            or len(payload) > WATCHDOG_EVENT_MAX_BYTES
            or not payload.endswith(b"\n")
            or payload.count(b"\n") != 1
            or b"\r" in payload
        ):
            return None
        try:
            value = strict_json_object(payload[:-1])
            return validate_watchdog_event(value, expected_pid, expected_run_id)
        except (TypeError, ValueError, UnicodeError):
            return None
    finally:
        os.close(descriptor)


def finalize_daemon_exit(
    process: subprocess.Popen[bytes] | None,
) -> dict[str, object] | None:
    """Ingest one exit event and close all supervisor-owned diagnostics."""
    if process is None:
        return None
    event: dict[str, object] | None = None
    pending_error: BaseException | None = None
    try:
        event = read_watchdog_event(
            process,
            process.pid,
            getattr(process, "_anvil_watchdog_run_id", ""),
        )
    except BaseException as error:
        pending_error = error
    try:
        close_daemon_diagnostic(process)
    except BaseException as error:
        if pending_error is None:
            pending_error = error
    if pending_error is not None:
        raise pending_error
    return event


def start_daemon(args: argparse.Namespace) -> subprocess.Popen[bytes]:
    command = [
        args.python,
        "-I",
        "-S",
        args.parent_guard,
        "group",
        args.daemon,
    ]
    diagnostic_descriptor: int | None = None
    read_descriptor: int | None = None
    write_descriptor: int | None = None
    event_read_descriptor: int | None = None
    event_write_descriptor: int | None = None
    process: subprocess.Popen[bytes] | None = None
    try:
        diagnostic_descriptor = open_daemon_diagnostic(args.runtime_dir)
        read_descriptor, write_descriptor = os.pipe()
        os.set_blocking(read_descriptor, False)
        event_read_descriptor, event_write_descriptor = create_watchdog_event_pipe()
        run_id = secrets.token_hex(16)
        environment = daemon_environment(args)
        environment.update(
            {
                WATCHDOG_SUPERVISED_ENV: "1",
                WATCHDOG_EVENT_FD_ENV: str(event_write_descriptor),
                WATCHDOG_RUN_ID_ENV: run_id,
            }
        )
        process = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=write_descriptor,
            stderr=write_descriptor,
            env=environment,
            start_new_session=True,
            close_fds=True,
            pass_fds=(event_write_descriptor,),
        )
        os.close(write_descriptor)
        write_descriptor = None
        os.close(event_write_descriptor)
        event_write_descriptor = None
        setattr(process, "_anvil_diagnostic_read_fd", read_descriptor)
        setattr(process, "_anvil_diagnostic_output_fd", diagnostic_descriptor)
        setattr(process, "_anvil_diagnostic_written", 0)
        setattr(process, "_anvil_watchdog_event_read_fd", event_read_descriptor)
        setattr(process, "_anvil_watchdog_run_id", run_id)
        return process
    except BaseException:
        if process is not None:
            try:
                stop_daemon(process)
            except BaseException:
                pass
        for descriptor in (
            read_descriptor,
            write_descriptor,
            diagnostic_descriptor,
            event_read_descriptor,
            event_write_descriptor,
        ):
            if descriptor is not None:
                try:
                    os.close(descriptor)
                except OSError:
                    pass
        raise


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
            # SIGKILL cannot be ignored, but an uninterruptible kernel wait can
            # still prevent reaping indefinitely.  Bound this second wait.
            process.wait(timeout=DAEMON_STOP_SECONDS)


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
    return owner_seed_record_fields(
        args.agent_key,
        args.owner_pid,
        args.owner_start_identity,
        args.generation,
    )


def publish_owner_seed_if_absent(args: argparse.Namespace) -> None:
    """Publish bridge identity under the lock used by richer status writers."""
    deadline = time.monotonic() + STARTUP_STATUS_RETRY_SECONDS
    failures = 0
    def compatible(existing_owner):
        return bool(
            existing_owner is not None
            and existing_owner[2] == args.generation
            and existing_owner[3] == RECORD_FORMAT_V2
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
                if compatible(existing_owner):
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
                if existing_owner is not None and not compatible(existing_owner):
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
    last_watchdog: dict[str, object] | None = None,
) -> dict[str, object]:
    record = owner_seed_record(args)
    daemon_pid = None if daemon is None or daemon.poll() is not None else daemon.pid
    record.update(
        {
            "daemon_pid": daemon_pid,
            "lease_count": lease_count,
            "last_watchdog": last_watchdog,
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


def status_entry_identity(runtime_dir: Path) -> tuple[int, int] | None:
    """Capture the current status pathname identity through its private parent."""
    directory_fd = os.open(
        runtime_dir,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
    )
    try:
        directory_info = os.fstat(directory_fd)
        if (
            not stat.S_ISDIR(directory_info.st_mode)
            or directory_info.st_uid != os.getuid()
            or stat.S_IMODE(directory_info.st_mode) != 0o700
        ):
            raise ConfigurationError("unsafe supervisor runtime directory")
        try:
            status_info = os.stat(
                STATUS_NAME,
                dir_fd=directory_fd,
                follow_symlinks=False,
            )
        except FileNotFoundError:
            return None
        return status_info.st_dev, status_info.st_ino
    finally:
        os.close(directory_fd)


def invalidate_status_entry(
    runtime_dir: Path,
    expected_identity: tuple[int, int] | None,
) -> None:
    """Unlink only the status pathname captured before a failed transaction."""
    if expected_identity is None:
        return
    directory_fd = os.open(
        runtime_dir,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
    )
    try:
        directory_info = os.fstat(directory_fd)
        if (
            not stat.S_ISDIR(directory_info.st_mode)
            or directory_info.st_uid != os.getuid()
            or stat.S_IMODE(directory_info.st_mode) != 0o700
        ):
            return
        unlink_if_identity(directory_fd, STATUS_NAME, expected_identity)
    finally:
        os.close(directory_fd)


def publish_terminal_status(
    args: argparse.Namespace,
    record: dict[str, object],
) -> None:
    """Publish terminal state with the same bounded retry policy as startup."""
    publish_startup_status(args, record)


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
    last_watchdog: dict[str, object] | None = None
    last_lease_count = 0
    empty_since: float | None = None
    next_start = 0.0
    next_refresh = 0.0
    status_cache: dict[str, object] | None = None
    status_failures = 0
    next_status_attempt = 0.0
    transient_failures = 0
    stopping = False
    retiring = False
    retirement_gate_descriptor: int | None = None
    exit_transaction_failed = False

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
                leases = live_leases(
                    args.leases_dir,
                    args.agent_key,
                    args.owner_pid,
                    args.owner_start_identity,
                    args.generation,
                    owner_validated=True,
                )
                last_lease_count = len(leases)
                now = time.monotonic()
                drain_daemon_diagnostic(daemon)
                if daemon is not None and daemon.poll() is not None:
                    restart_reason = f"daemon-exited:{daemon.returncode}"
                    restart_count += 1
                    try:
                        last_watchdog = finalize_daemon_exit(daemon)
                    except BaseException:
                        exit_transaction_failed = True
                        raise
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
                        retirement_gate_descriptor = acquire_session_gate(
                            getattr(
                                args,
                                "session_gate_path",
                                session_gate_path(
                                    args.runtime_dir.parent,
                                    args.agent_key,
                                ),
                            ),
                            args.grace_seconds + (2 * DAEMON_STOP_SECONDS) + 2.0,
                        )
                        try:
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
                                last_lease_count = len(leases)
                                empty_since = None
                            else:
                                try:
                                    stop_daemon(daemon)
                                    finalize_daemon_exit(daemon)
                                    last_watchdog = None
                                except BaseException:
                                    exit_transaction_failed = True
                                    raise
                                daemon = None
                                daemon_started_at = None
                                daemon_observed_stable = False
                                daemon_failures = 0
                                next_start = 0.0
                                last_lease_count = 0
                                terminal = status_record(
                                    args,
                                    None,
                                    0,
                                    restart_count,
                                    restart_reason,
                                    None,
                                )
                                publish_terminal_status(args, terminal)
                                status_cache = terminal
                                retiring = True
                                break
                        finally:
                            if not retiring:
                                os.close(retirement_gate_descriptor)
                                retirement_gate_descriptor = None

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
                    last_watchdog,
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
                if exit_transaction_failed:
                    raise
                if not transient_supervisor_error(error):
                    raise
                transient_failures += 1
                retry_deadline = time.monotonic() + restart_backoff_seconds(
                    transient_failures
                )
                while not stopping:
                    remaining = retry_deadline - time.monotonic()
                    if remaining <= 0:
                        break
                    time.sleep(min(POLL_SECONDS, remaining))
                if stopping:
                    break
                continue
            transient_failures = 0
            time.sleep(POLL_SECONDS)
    finally:
        prior_error = sys.exc_info()[1]
        transaction_error: BaseException | None = (
            prior_error if exit_transaction_failed else None
        )
        captured_status_identity: tuple[int, int] | None = None
        try:
            try:
                captured_status_identity = status_entry_identity(args.runtime_dir)
            except BaseException as error:
                if transaction_error is None:
                    transaction_error = error
            try:
                stop_daemon(daemon)
            except BaseException as error:
                if transaction_error is None:
                    transaction_error = error
            try:
                finalize_daemon_exit(daemon)
            except BaseException as error:
                if transaction_error is None:
                    transaction_error = error
            daemon = None
            last_watchdog = None
            if transaction_error is None:
                try:
                    publish_terminal_status(
                        args,
                        status_record(
                            args,
                            None,
                            last_lease_count,
                            restart_count,
                            restart_reason,
                            None,
                        ),
                    )
                except BaseException as error:
                    transaction_error = error
            if transaction_error is not None:
                try:
                    invalidate_status_entry(
                        args.runtime_dir,
                        captured_status_identity,
                    )
                except BaseException:
                    pass
                if prior_error is None:
                    raise transaction_error
            elif retiring:
                cleanup_instance(args)
        finally:
            os.close(lock_descriptor)
            if retirement_gate_descriptor is not None and not retiring:
                os.close(retirement_gate_descriptor)


def waitpid_bounded(pid: int, timeout_seconds: float) -> bool:
    """Reap PID without allowing an uninterruptible child to hang the bridge."""
    deadline = time.monotonic() + timeout_seconds
    while True:
        try:
            waited, _status = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            return True
        except InterruptedError:
            continue
        if waited == pid:
            return True
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        time.sleep(min(0.01, remaining))


def remember_supervisor_child(args: argparse.Namespace, child_pid: int) -> None:
    """Retain ownership of a supervisor child until a later bounded reap."""
    children = getattr(args, "_supervisor_child_pids", None)
    if children is None:
        children = set()
        args._supervisor_child_pids = children
    children.add(child_pid)


def spawn_supervisor_if_absent(
    args: argparse.Namespace,
    *,
    handshake_seconds: float = SUPERVISOR_HANDSHAKE_SECONDS,
) -> bool:
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
        handshake_seconds,
    )
    ready = os.read(ready_read, 1) if readable else b""
    os.close(ready_read)
    if ready != b"R":
        try:
            os.kill(child_pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        if not waitpid_bounded(child_pid, DAEMON_STOP_SECONDS):
            remember_supervisor_child(args, child_pid)
            raise TimeoutError(
                "agent supervisor did not become ready and could not be reaped"
            )
        raise TimeoutError("agent supervisor did not become ready")
    remember_supervisor_child(args, child_pid)
    return True


def safe_socket_ready(
    socket_path: Path,
    emacsclient: str,
    server_id: str,
    timeout_seconds: float = 2.0,
) -> bool:
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
            [
                emacsclient,
                "-a",
                "false",
                "-s",
                str(socket_path),
                "-e",
                daemon_ready_expression(server_id),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=transport_environment(),
            timeout=timeout_seconds,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0 and result.stdout.strip() == b"t"


def wait_for_daemon(args: argparse.Namespace) -> None:
    deadline = time.monotonic() + args.ready_seconds
    socket_path = args.runtime_dir / "emacs" / "server"
    failures = 0
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        owner_state = validate_process_identity(
            args.owner_pid,
            args.owner_start_identity,
        )
        if owner_state is LifecycleState.DEAD:
            raise ConfigurationError("external MCP owner process generation changed")
        if owner_state is LifecycleState.UNAVAILABLE:
            time.sleep(min(POLL_SECONDS, remaining))
            continue
        delay = POLL_SECONDS
        try:
            spawn_supervisor_if_absent(
                args,
                handshake_seconds=min(SUPERVISOR_HANDSHAKE_SECONDS, remaining),
            )
        except TimeoutError:
            failures += 1
            delay = restart_backoff_seconds(failures)
        except OSError as error:
            if not transient_supervisor_error(error):
                raise
            failures += 1
            delay = restart_backoff_seconds(failures)
        else:
            failures = 0
        remaining = deadline - time.monotonic()
        if remaining > 0 and safe_socket_ready(
            socket_path,
            args.emacsclient,
            args.server_id,
            min(2.0, remaining),
        ):
            status = read_bridge_retirement_status(args)
            if status is not None:
                supervisor_pid = status.get("supervisor_pid")
                supervisor_identity = status.get("supervisor_start_identity")
                daemon_pid = status.get("daemon_pid")
                daemon_identity = (
                    None
                    if not isinstance(daemon_pid, int)
                    else process_start_identity(daemon_pid)
                )
                if (
                    status.get("lease_count", 0) >= 1
                    and isinstance(supervisor_pid, int)
                    and isinstance(supervisor_identity, str)
                    and isinstance(daemon_pid, int)
                    and isinstance(daemon_identity, str)
                    and validate_process_identity(supervisor_pid, supervisor_identity)
                    is LifecycleState.LIVE
                    and validate_process_identity(daemon_pid, daemon_identity)
                    is LifecycleState.LIVE
                ):
                    args._active_supervisor_identity = (
                        supervisor_pid,
                        supervisor_identity,
                    )
                    args._active_daemon_identity = (daemon_pid, daemon_identity)
                    return
        remaining = deadline - time.monotonic()
        if remaining > 0:
            time.sleep(min(delay, remaining))
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
    # Root startup replaces runtime_dir/tmp on every watchdog restart.  Keep
    # the bridge's response transaction directory outside that daemon-owned
    # tree so the same MCP pipe can recover after the root is relaunched.
    temporary_path = args.runtime_dir / "transport-tmp"
    ensure_private_directory(temporary_path)
    environment = transport_environment()
    environment["ANVIL_EMACS_SOCKET"] = str(socket_path)
    environment["ANVIL_EMACS_RUNTIME_DIR"] = str(args.runtime_dir)
    environment["ANVIL_MCP_PARENT_GUARD"] = args.parent_guard
    environment["ANVIL_MCP_PARENT_GUARD_PYTHON"] = args.python
    environment["ANVIL_HEADLESS_PARENT_PID"] = str(os.getpid())
    # The bridge constructs a fixed predicate from its validated server ID.
    # Overwrite any project-provided mode after transport sanitization.
    environment["ANVIL_MCP_READINESS_MODE"] = "headless"
    environment["TMPDIR"] = str(temporary_path)
    environment["TMP"] = str(temporary_path)
    environment["TEMP"] = str(temporary_path)
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
        pass
    try:
        process.wait(timeout=DAEMON_STOP_SECONDS)
        return
    except subprocess.TimeoutExpired:
        try:
            process.kill()
        except ProcessLookupError:
            pass
    try:
        process.wait(timeout=DAEMON_STOP_SECONDS)
    except subprocess.TimeoutExpired as error:
        raise TimeoutError("stdio bridge did not exit after SIGKILL") from error


def read_bridge_retirement_status(
    args: argparse.Namespace,
) -> dict[str, object] | None:
    """Read the exact supervisor lease/daemon state for bridge retirement."""
    directory_fd = None
    status_fd = None
    try:
        directory_fd = os.open(
            args.runtime_dir,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
        validate_probe_runtime_entry(args.runtime_dir, directory_fd)
        status_fd = os.open(
            STATUS_NAME,
            os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
            dir_fd=directory_fd,
        )
        validate_probe_status_entry(directory_fd, status_fd)
        payload = os.read(status_fd, MAX_LEASE_BYTES + 1)
        if (
            not payload
            or len(payload) > MAX_LEASE_BYTES
            or not payload.endswith(b"\n")
            or payload.count(b"\n") != 1
            or b"\r" in payload
        ):
            return None
        record = strict_json_object(payload[:-1])
        if (
            set(record) != STATUS_KEYS
            or record.get("format") != RECORD_FORMAT_V2
            or record.get("version") != RECORD_FORMAT_V2
            or record.get("agent_key") != args.agent_key
            or record.get("generation") != args.generation
        ):
            return None
        lease_count = exact_nonnegative_integer(record.get("lease_count"))
        daemon_pid = record.get("daemon_pid")
        if daemon_pid is not None:
            daemon_pid = exact_nonnegative_integer(daemon_pid, positive=True)
        supervisor_pid = record.get("supervisor_pid")
        supervisor_identity = record.get("supervisor_start_identity")
        if (supervisor_pid is None) != (supervisor_identity is None):
            return None
        if supervisor_pid is not None:
            supervisor_pid = exact_nonnegative_integer(
                supervisor_pid,
                positive=True,
            )
        if supervisor_identity is not None and (
            not isinstance(supervisor_identity, str) or not supervisor_identity
        ):
            return None
        record["lease_count"] = lease_count
        record["daemon_pid"] = daemon_pid
        record["supervisor_pid"] = supervisor_pid
        return record
    except (
        FileNotFoundError,
        PermissionError,
        OSError,
        TypeError,
        ValueError,
        UnicodeError,
    ):
        return None
    finally:
        if status_fd is not None:
            os.close(status_fd)
        if directory_fd is not None:
            os.close(directory_fd)


def wait_for_bridge_retirement(args: argparse.Namespace) -> None:
    """Bound the final bridge's internal wait for owned-root retirement."""
    deadline = time.monotonic() + bridge_retirement_timeout(args)
    active_supervisor = getattr(args, "_active_supervisor_identity", None)
    active_daemon = getattr(args, "_active_daemon_identity", None)
    if active_supervisor is None:
        raise ConfigurationError("active Anvil root identity was not observed")
    while True:
        try:
            leases = live_leases(
                args.leases_dir,
                args.agent_key,
                args.owner_pid,
                args.owner_start_identity,
                args.generation,
            )
        except FileNotFoundError:
            # Cleanup removes the leases directory before the exact root
            # identities necessarily become observable as dead.  Treat the
            # missing entry as progress, not as either success or failure.
            leases = []
        except OSError as error:
            if not transient_supervisor_error(error):
                raise
        else:
            # A surviving sibling keeps the same canonical root.  The final
            # bridge performs this internal wait; callers need no process-tree
            # retirement contract of their own.
            if leases:
                return
            # Terminal JSON is only a progress marker: the supervisor writes
            # it before deleting its trees and exiting.  Never acknowledge
            # retirement from that record alone.
            read_bridge_retirement_status(args)
        supervisor_state = validate_process_identity(*active_supervisor)
        daemon_state = (
            LifecycleState.DEAD
            if active_daemon is None
            else validate_process_identity(*active_daemon)
        )
        if (
            supervisor_state is LifecycleState.DEAD
            and daemon_state is LifecycleState.DEAD
            and not os.path.lexists(args.runtime_dir)
            and not os.path.lexists(args.state_dir)
        ):
            return
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("shared Anvil root did not retire after final lease")
        time.sleep(min(POLL_SECONDS, remaining))


def bridge_retirement_timeout(args: argparse.Namespace) -> float:
    """Return the Anvil-internal final-bridge retirement bound."""
    return args.grace_seconds + (2 * DAEMON_STOP_SECONDS) + 2.0


def capture_active_retirement_identity(args: argparse.Namespace) -> None:
    """Ensure and capture the exact root identities before lease removal."""
    deadline = time.monotonic() + min(STARTUP_STATUS_RETRY_SECONDS, args.ready_seconds)
    failures = 0
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("active Anvil root status was unavailable")
        try:
            spawn_supervisor_if_absent(
                args,
                handshake_seconds=min(SUPERVISOR_HANDSHAKE_SECONDS, remaining),
            )
        except TimeoutError:
            failures += 1
        except OSError as error:
            if not transient_supervisor_error(error):
                raise
            failures += 1
        else:
            failures = 0
        status = read_bridge_retirement_status(args)
        if status is not None and status.get("lease_count", 0) >= 1:
            supervisor = (
                status.get("supervisor_pid"),
                status.get("supervisor_start_identity"),
            )
            daemon_pid = status.get("daemon_pid")
            daemon = None
            daemon_valid = daemon_pid is None
            if isinstance(daemon_pid, int):
                daemon_identity = process_start_identity(daemon_pid)
                if isinstance(daemon_identity, str):
                    daemon = (daemon_pid, daemon_identity)
                    daemon_valid = True
            if (
                isinstance(supervisor[0], int)
                and isinstance(supervisor[1], str)
                and daemon_valid
                and validate_process_identity(*supervisor) is LifecycleState.LIVE
                and (
                    daemon is None
                    or validate_process_identity(*daemon) is LifecycleState.LIVE
                )
            ):
                args._active_supervisor_identity = supervisor
                args._active_daemon_identity = daemon
                return
        remaining = deadline - time.monotonic()
        if remaining > 0:
            delay = POLL_SECONDS if failures == 0 else restart_backoff_seconds(failures)
            time.sleep(min(delay, remaining))


def unlink_bridge_lease(args: argparse.Namespace, lease_path: Path) -> None:
    """Remove a bridge lease with bounded retry on transient filesystems."""
    deadline = time.monotonic() + bridge_retirement_timeout(args)
    failures = 0
    while True:
        try:
            lease_path.unlink()
            return
        except FileNotFoundError:
            return
        except OSError as error:
            if not transient_supervisor_error(error):
                raise
            failures += 1
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("bridge lease could not be removed") from error
            time.sleep(min(restart_backoff_seconds(failures), remaining))


def caretake_stdio_bridge(args: argparse.Namespace) -> int:
    """Keep supervisor availability while stdio directly owns the MCP pipes."""
    process = start_stdio_bridge(args)
    ensure_failures = 0
    next_ensure = 0.0
    try:
        while process.poll() is None:
            reap_supervisor_children(args)
            now = time.monotonic()
            if now >= next_ensure:
                owner_state = validate_process_identity(
                    args.owner_pid,
                    args.owner_start_identity,
                )
                if owner_state is LifecycleState.DEAD:
                    raise ConfigurationError(
                        "external MCP owner process generation changed"
                    )
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
        returncode = process.poll()
        if returncode is None:
            return EXIT_SOFTWARE
        return returncode if returncode >= 0 else 128 - returncode
    finally:
        if process.poll() is None:
            stop_stdio_bridge(process)
        reap_supervisor_children(args)


def bridge_transaction(args: argparse.Namespace) -> None:
    gate_descriptor: int | None = None
    lease_path: Path | None = None
    stdio_status = 0
    try:
        try:
            args.server_id = validate_server_id(args.server_id)
            args.host = validate_host(args.host)
            args.generation = validate_generation(args.generation)
            runtime_root = validate_root_path(args.runtime_root, "runtime root")
            state_root = validate_root_path(args.state_root, "state root")
            validate_distinct_paths(runtime_root, state_root, "Anvil root")
            args.worker_names = validate_worker_names(args.worker_names)
            # Every agent key has the same fixed width.  Validate the complete
            # prospective roster before consulting the MCP pipe or publishing any
            # directory, so impossible configuration always fails deterministically.
            validate_emacs_socket_paths(
                runtime_root,
                args.host,
                "0" * 32,
                args.worker_names,
            )
            args.agentdeck_instance_id = agent_deck_instance_id()
            args.owner_pid, args.owner_start_identity = identify_bridge(
                managed=args.agentdeck_instance_id is not None,
            )
            args.agent_key = (
                derive_managed_agent_key(
                    args.agentdeck_instance_id,
                    args.generation,
                )
                if args.agentdeck_instance_id is not None
                else derive_agent_key(
                    args.owner_pid,
                    args.owner_start_identity,
                    args.generation,
                )
            )
            runtime_host = runtime_root / args.host
            runtime_agents = runtime_host / "agents"
            for path in (runtime_root, runtime_host, runtime_agents):
                ensure_private_directory(path)
            args.session_gate_path = session_gate_path(runtime_agents, args.agent_key)
            gate_descriptor = acquire_session_gate(
                args.session_gate_path,
                args.ready_seconds,
            )
            args._bridge_termination_deferred = True
            try:
                runtime_dir, state_dir, leases_dir = prepare_instance_directories(
                    runtime_root,
                    state_root,
                    args.host,
                    args.agent_key,
                    args.owner_pid,
                    args.owner_start_identity,
                    args.generation,
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
            finally:
                descriptor = gate_descriptor
                gate_descriptor = None
                if descriptor is not None:
                    os.close(descriptor)
                args._bridge_termination_deferred = False
                checkpoint = getattr(args, "_bridge_termination_checkpoint", None)
                if checkpoint is not None:
                    checkpoint()

            wait_for_daemon(args)
            stdio_status = caretake_stdio_bridge(args)
        except ConfigurationError as error:
            fail(str(error), EXIT_CONFIG)
        except TimeoutError as error:
            fail(str(error), EXIT_UNAVAILABLE)
        except OSError as error:
            fail(f"cannot run MCP bridge transaction: {error}")
    finally:
        if gate_descriptor is not None:
            os.close(gate_descriptor)
            gate_descriptor = None
        args._bridge_termination_deferred = False
        if lease_path is not None:
            capture_error: BaseException | None = None
            capture_attempted = False
            while True:
                try:
                    if not capture_attempted:
                        try:
                            capture_active_retirement_identity(args)
                        except (ConfigurationError, TimeoutError, OSError) as error:
                            capture_error = error
                        capture_attempted = True
                    unlink_bridge_lease(args, lease_path)
                    if capture_error is not None:
                        raise capture_error
                    wait_for_bridge_retirement(args)
                    break
                except BridgeTerminationRequested:
                    continue
                except ConfigurationError as error:
                    fail(str(error), EXIT_CONFIG)
                except TimeoutError as error:
                    fail(str(error), EXIT_UNAVAILABLE)
                except OSError as error:
                    fail(f"cannot confirm MCP bridge retirement: {error}")

    if getattr(args, "_bridge_termination_pending", False):
        raise BridgeTerminationRequested()
    if stdio_status != 0:
        raise SystemExit(stdio_status)


def bridge_main(args: argparse.Namespace) -> None:
    """Run one bridge with signal-safe cleanup spanning its whole lifetime."""
    termination_pending = False
    termination_raised = False
    previous_handlers: dict[int, object] = {}

    def request_termination(_signum: int, _frame: object) -> None:
        nonlocal termination_pending, termination_raised
        termination_pending = True
        args._bridge_termination_pending = True
        if getattr(args, "_bridge_termination_deferred", False):
            return
        if termination_raised:
            return
        termination_raised = True
        raise BridgeTerminationRequested()

    def termination_checkpoint() -> None:
        nonlocal termination_raised
        if termination_pending and not termination_raised:
            termination_raised = True
            raise BridgeTerminationRequested()

    args._bridge_termination_deferred = False
    args._bridge_termination_pending = False
    args._bridge_termination_checkpoint = termination_checkpoint
    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        previous_handlers[signum] = signal.getsignal(signum)
        signal.signal(signum, request_termination)
    try:
        try:
            bridge_transaction(args)
        except BridgeTerminationRequested:
            return
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
        for attribute in (
            "_bridge_termination_checkpoint",
            "_bridge_termination_deferred",
            "_bridge_termination_pending",
        ):
            try:
                delattr(args, attribute)
            except AttributeError:
                pass


def host_socket_preflight_main(args: argparse.Namespace) -> None:
    """Validate shared-host roots and socket paths without publishing state."""
    try:
        runtime_root = validate_root_path(args.runtime_root, "runtime root")
        state_root = validate_root_path(args.state_root, "state root")
        validate_distinct_paths(runtime_root, state_root, "Anvil root")
        if bool(args.runtime_dir) != bool(args.state_dir):
            raise ConfigurationError(
                "exact runtime and state directories must be set together"
            )
        if args.runtime_dir:
            runtime_dir = validate_root_path(args.runtime_dir, "runtime directory")
            state_dir = validate_root_path(args.state_dir, "state directory")
            validate_distinct_paths(runtime_dir, state_dir, "exact Anvil directory")
            validate_socket_path(
                runtime_dir / ACTIVITY_SOCKET_NAME,
                "Anvil activity socket path",
            )
            validate_socket_paths(runtime_dir / "emacs", args.worker_names)
        else:
            validate_host_emacs_socket_paths(
                runtime_root,
                args.host,
                args.worker_names,
            )
    except ConfigurationError as error:
        fail(str(error), EXIT_CONFIG)


def parse_host_socket_preflight_arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--state-root", required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--runtime-dir")
    parser.add_argument("--state-dir")
    parser.add_argument(
        "--worker-name", action="append", dest="worker_names", required=True
    )
    return parser.parse_args(argv)


def explicit_socket_preflight_main(args: argparse.Namespace) -> None:
    """Validate one caller-supplied host socket without publishing state."""
    try:
        validate_socket_path(args.socket)
    except ConfigurationError as error:
        fail(str(error), EXIT_CONFIG)


def validate_probe_status(
    record: object,
    agent_key: str,
    *,
    managed: bool = False,
) -> bytes:
    """Validate one current status record and render its bounded summary."""
    if not isinstance(record, dict) or set(record) != STATUS_KEYS:
        raise ValueError("status schema mismatch")
    if (
        type(record["format"]) is not int
        or record["format"] != RECORD_FORMAT_V2
        or type(record["version"]) is not int
        or record["version"] != RECORD_FORMAT_V2
    ):
        raise ValueError("unsupported status format")
    validate_generation(record["generation"])
    if record["agent_key"] != agent_key:
        raise ValueError("status agent key mismatch")
    lease_count = exact_nonnegative_integer(record["lease_count"])
    restart_count = exact_nonnegative_integer(record["restart_count"])
    del lease_count

    owner_pid = exact_nonnegative_integer(record["owner_pid"], positive=True)
    owner_identity = record["owner_start_identity"]
    if not isinstance(owner_identity, str) or not owner_identity:
        raise ValueError("invalid status owner identity")
    if (
        not managed
        and validate_process_identity(owner_pid, owner_identity)
        is not LifecycleState.LIVE
    ):
        raise ValueError("status owner is not live")

    supervisor_pid = exact_nonnegative_integer(
        record["supervisor_pid"],
        positive=True,
    )
    supervisor_identity = record["supervisor_start_identity"]
    if not isinstance(supervisor_identity, str) or not supervisor_identity:
        raise ValueError("invalid status supervisor identity")
    if (
        validate_process_identity(supervisor_pid, supervisor_identity)
        is not LifecycleState.LIVE
    ):
        raise ValueError("status supervisor is not live")

    daemon_pid = record["daemon_pid"]
    if daemon_pid is not None:
        exact_nonnegative_integer(daemon_pid, positive=True)
    restart_reason = record["restart_reason"]
    if restart_count == 0:
        if restart_reason is not None:
            raise ValueError("unexpected restart reason")
    elif (
        not isinstance(restart_reason, str)
        or RESTART_REASON_PATTERN.fullmatch(restart_reason) is None
    ):
        raise ValueError("invalid restart reason")

    watchdog = record["last_watchdog"]
    if watchdog is None:
        cause = "none"
        phase = "unknown"
        tool = "none"
    else:
        event = validate_watchdog_event(watchdog)
        if restart_count == 0:
            raise ValueError("watchdog event has no restart")
        cause = str(event["cause"])
        phase = str(event["phase"])
        tool_value = event["tool"]
        tool = "none" if tool_value is None else str(tool_value)
    payload = (
        f"root-restarts={restart_count} cause={cause} phase={phase} tool={tool}\n"
    ).encode("ascii", errors="strict")
    if len(payload) > 256:
        raise ValueError("probe summary exceeds byte limit")
    return payload


def probe_status_is_managed(
    runtime_dir: Path,
    agent_key: str,
    record: dict[str, object],
) -> bool:
    """Prove that status belongs to a session-keyed rather than owner-keyed root."""
    _state, creator, _identity = read_creator_lifecycle(
        runtime_dir.parent,
        agent_key,
    )
    if creator is None or creator.get("generation") != record.get("generation"):
        return False
    try:
        return not owner_key_matches_known_scheme(
            agent_key,
            creator["owner_pid"],
            creator["owner_start_identity"],
            creator["generation"],
        )
    except (ConfigurationError, KeyError, TypeError):
        return False


def validate_probe_runtime_entry(
    runtime_dir: Path, directory_fd: int
) -> tuple[int, int]:
    """Return one still-current private runtime-directory identity."""
    directory_info = os.fstat(directory_fd)
    path_info = os.stat(runtime_dir, follow_symlinks=False)
    identity = (directory_info.st_dev, directory_info.st_ino)
    if (
        not stat.S_ISDIR(directory_info.st_mode)
        or directory_info.st_uid != os.getuid()
        or stat.S_IMODE(directory_info.st_mode) != 0o700
        or (path_info.st_dev, path_info.st_ino) != identity
    ):
        raise ConfigurationError("unsafe probe runtime directory")
    return identity


def validate_probe_status_entry(directory_fd: int, status_fd: int) -> tuple[int, int]:
    """Return one still-current private status-entry identity."""
    descriptor_info = os.fstat(status_fd)
    status_info = os.stat(
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
        or (status_info.st_dev, status_info.st_ino) != identity
    ):
        raise ConfigurationError("unsafe probe status entry")
    return identity


def read_probe_summary(runtime_raw: str, agent_key_raw: str) -> bytes:
    """Read one private status entry without following or blocking on it."""
    runtime_dir = validate_root_path(runtime_raw, "runtime directory")
    agent_key = validate_agent_key(agent_key_raw)
    if runtime_dir.name != agent_key:
        raise ConfigurationError("runtime directory identity mismatch")
    directory_fd = os.open(
        runtime_dir,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
    )
    status_fd: int | None = None
    try:
        directory_identity = validate_probe_runtime_entry(runtime_dir, directory_fd)
        status_fd = os.open(
            STATUS_NAME,
            os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
            dir_fd=directory_fd,
        )
        status_identity = validate_probe_status_entry(directory_fd, status_fd)
        payload = os.read(status_fd, MAX_LEASE_BYTES + 1)
        if (
            not payload
            or len(payload) > MAX_LEASE_BYTES
            or not payload.endswith(b"\n")
            or payload.count(b"\n") != 1
            or b"\r" in payload
        ):
            raise ValueError("invalid probe status frame")
        record = strict_json_object(payload[:-1])
        summary = validate_probe_status(
            record,
            agent_key,
            managed=probe_status_is_managed(runtime_dir, agent_key, record),
        )
        if (
            validate_probe_runtime_entry(runtime_dir, directory_fd)
            != directory_identity
            or validate_probe_status_entry(directory_fd, status_fd) != status_identity
        ):
            raise ConfigurationError("probe status changed during read")
        return summary
    finally:
        if status_fd is not None:
            os.close(status_fd)
        os.close(directory_fd)


def probe_summary_main(runtime_dir: str, agent_key: str) -> None:
    """Emit only a validated summary, failing without diagnostic output."""
    try:
        payload = read_probe_summary(runtime_dir, agent_key)
        sys.stdout.write(payload.decode("ascii"))
    except BaseException:
        raise SystemExit(EXIT_UNAVAILABLE) from None


def parse_explicit_socket_preflight_arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", required=True)
    return parser.parse_args(argv)


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
    parser.add_argument(
        "--worker-name", action="append", dest="worker_names", required=True
    )
    parser.add_argument("--grace-seconds", type=float, default=5.0)
    parser.add_argument("--ready-seconds", type=float, default=120.0)
    args = parser.parse_args(argv)
    if not (0.25 <= args.grace_seconds <= MAX_AGENT_GRACE_SECONDS):
        parser.error(
            f"--grace-seconds must be between 0.25 and {MAX_AGENT_GRACE_SECONDS:g}"
        )
    if not (1 <= args.ready_seconds <= MAX_READY_SECONDS):
        parser.error(f"--ready-seconds must be between 1 and {MAX_READY_SECONDS:g}")
    return args


def main(argv: list[str] | None = None) -> None:
    argv = sys.argv[1:] if argv is None else argv
    if not argv:
        raise SystemExit(EXIT_CONFIG)
    if argv[0] == "--probe-summary":
        if len(argv) != 5 or argv[1] != "--runtime-dir" or argv[3] != "--agent-key":
            raise SystemExit(EXIT_CONFIG)
        probe_summary_main(argv[2], argv[4])
        return
    if argv[:1] == ["--validate-host-sockets"]:
        host_socket_preflight_main(parse_host_socket_preflight_arguments(argv[1:]))
        return
    if argv[:1] == ["--validate-explicit-socket"]:
        explicit_socket_preflight_main(
            parse_explicit_socket_preflight_arguments(argv[1:])
        )
        return
    bridge_main(parse_arguments(argv))


if __name__ == "__main__":
    main()
