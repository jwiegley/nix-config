#!/usr/bin/env python3
"""Remove explicitly retired managed MCP entries from mutable agent state."""

from __future__ import annotations

import argparse
import copy
import ctypes
import errno
import hashlib
import os
import secrets
import stat
import sys
from collections.abc import MutableMapping
from pathlib import Path, PurePosixPath
from typing import Any, Callable

import tomlkit
import simplejson as json


MAX_FILE_BYTES = 64 * 1024 * 1024
PLAN_KEYS = {
    "claudeManagedServers",
    "codexManagedServers",
    "manifestRoots",
    "piRoots",
    "retiredManifestMcpItems",
    "retiredManifestSkillItems",
    "retiredServers",
}


class CleanupError(Exception):
    pass


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise CleanupError("duplicate JSON key")
        result[key] = value
    return result


def reject_json_constant(_value: str) -> None:
    raise CleanupError("non-standard JSON constant")


def load_json(text: str) -> dict[str, Any]:
    try:
        value = json.loads(
            text,
            object_pairs_hook=reject_duplicate_keys,
            parse_constant=reject_json_constant,
            use_decimal=True,
        )
    except CleanupError:
        raise
    except Exception as error:
        raise CleanupError("malformed JSON") from error
    if not isinstance(value, dict):
        raise CleanupError("JSON root is not an object")
    return value


def string_list(value: Any, field: str) -> list[str]:
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise CleanupError(f"invalid plan field: {field}")
    if len(value) != len(set(value)):
        raise CleanupError(f"duplicate plan entry: {field}")
    return value


def managed_server_map(value: Any, field: str) -> dict[str, list[str]]:
    if not isinstance(value, dict):
        raise CleanupError(f"invalid plan field: {field}")
    result: dict[str, list[str]] = {}
    for root, names in value.items():
        result[relative_root(root)] = string_list(names, f"{field}.{root}")
    return result


def relative_root(value: str) -> str:
    path = PurePosixPath(value)
    if (
        path.is_absolute()
        or not path.parts
        or any(part in {"", ".", ".."} for part in path.parts)
    ):
        raise CleanupError("unsafe relative root")
    return value


def load_plan(raw: str) -> dict[str, Any]:
    plan = load_json(raw)
    if set(plan) != PLAN_KEYS:
        raise CleanupError("invalid cleanup plan keys")
    result = {
        key: string_list(plan[key], key)
        for key in (
            "manifestRoots",
            "piRoots",
            "retiredManifestMcpItems",
            "retiredManifestSkillItems",
            "retiredServers",
        )
    }
    for key in ("manifestRoots", "piRoots"):
        result[key] = [relative_root(value) for value in result[key]]
    for key in ("claudeManagedServers", "codexManagedServers"):
        result[key] = managed_server_map(plan[key], key)
    if not result["retiredServers"]:
        raise CleanupError("retired server list is empty")
    return result


def require_object(parent: dict[str, Any], key: str) -> dict[str, Any] | None:
    if key not in parent:
        return None
    value = parent[key]
    if not isinstance(value, dict):
        raise CleanupError("managed JSON container has the wrong type")
    return value


def remove_keys(table: dict[str, Any] | None, names: list[str]) -> bool:
    if table is None:
        return False
    changed = False
    for name in names:
        if name in table:
            del table[name]
            changed = True
    return changed


def managed_and_retired(plan: dict[str, Any], managed: list[str]) -> list[str]:
    return list(dict.fromkeys([*managed, *plan["retiredServers"]]))


def clean_json(
    text: str,
    kind: str,
    plan: dict[str, Any],
    managed: list[str] | None = None,
) -> str:
    value = load_json(text)
    changed = False
    if kind == "claude":
        changed = remove_keys(
            require_object(value, "mcpServers"),
            managed_and_retired(plan, managed or []),
        )
    elif kind == "pi-cache":
        changed = remove_keys(require_object(value, "servers"), plan["retiredServers"])
    elif kind == "manifest":
        items = require_object(value, "items")
        if items is not None:
            changed |= remove_keys(
                require_object(items, "mcp_servers"), plan["retiredManifestMcpItems"]
            )
            changed |= remove_keys(
                require_object(items, "skills"), plan["retiredManifestSkillItems"]
            )
    else:
        raise CleanupError("unknown JSON cleanup kind")
    if not changed:
        return text

    rendered = (
        json.dumps(
            value,
            ensure_ascii=False,
            indent=2,
            allow_nan=False,
            use_decimal=True,
        )
        + "\n"
    )
    if load_json(rendered) != value:
        raise CleanupError("JSON semantic verification failed")
    return rendered


def clean_toml(text: str, plan: dict[str, Any], managed: list[str]) -> str:
    try:
        document = tomlkit.parse(text)
    except Exception as error:
        raise CleanupError("malformed TOML") from error

    mcp_servers = document.get("mcp_servers")
    if mcp_servers is None:
        return text
    if not isinstance(mcp_servers, MutableMapping):
        raise CleanupError("managed TOML container has the wrong type")

    expected = copy.deepcopy(document.unwrap())
    expected_mcp = expected.get("mcp_servers")
    if not isinstance(expected_mcp, dict):
        raise CleanupError("managed TOML container has the wrong type")

    changed = False
    for name in managed_and_retired(plan, managed):
        if name in mcp_servers:
            del mcp_servers[name]
            expected_mcp.pop(name, None)
            changed = True
    if not changed:
        return text
    if not expected_mcp:
        expected.pop("mcp_servers", None)

    rendered = tomlkit.dumps(document)
    try:
        verified = tomlkit.parse(rendered).unwrap()
    except Exception as error:
        raise CleanupError("generated invalid TOML") from error
    if verified.get("mcp_servers") == {}:
        verified.pop("mcp_servers", None)
    if verified != expected:
        raise CleanupError("TOML semantic verification failed")
    return rendered


def read_fd(fd: int, expected_size: int) -> bytes:
    if expected_size > MAX_FILE_BYTES:
        raise CleanupError("mutable config exceeds size limit")
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = os.read(fd, min(1024 * 1024, MAX_FILE_BYTES + 1 - total))
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)
        total += len(chunk)
        if total > MAX_FILE_BYTES:
            raise CleanupError("mutable config exceeds size limit")


def file_identity(info: os.stat_result, payload: bytes) -> tuple[Any, ...]:
    return (
        info.st_dev,
        info.st_ino,
        info.st_mode,
        info.st_uid,
        info.st_gid,
        info.st_nlink,
        info.st_size,
        info.st_mtime_ns,
        info.st_ctime_ns,
        hashlib.sha256(payload).digest(),
    )


def open_parent(home_fd: int, relative: str) -> tuple[int, str] | None:
    parts = PurePosixPath(relative).parts
    current = os.dup(home_fd)
    try:
        for part in parts[:-1]:
            try:
                next_fd = os.open(
                    part,
                    os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW,
                    dir_fd=current,
                )
            except FileNotFoundError:
                os.close(current)
                return None
            except OSError as error:
                raise CleanupError("refusing unsafe parent directory") from error
            os.close(current)
            current = next_fd
        parent_info = os.fstat(current)
        if not stat.S_ISDIR(parent_info.st_mode) or parent_info.st_uid != os.getuid():
            raise CleanupError("refusing parent directory not owned by current user")
        return current, parts[-1]
    except Exception:
        os.close(current)
        raise


def open_leaf(parent_fd: int, name: str) -> tuple[int, os.stat_result, bytes] | None:
    try:
        fd = os.open(
            name,
            os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC | os.O_NOFOLLOW,
            dir_fd=parent_fd,
        )
    except FileNotFoundError:
        return None
    except OSError as error:
        raise CleanupError("refusing unsafe mutable config path") from error

    try:
        info = os.fstat(fd)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_nlink != 1
        ):
            raise CleanupError("refusing non-regular or shared mutable config")
        if getattr(info, "st_flags", 0) != 0:
            raise CleanupError("refusing mutable config with file flags")
        payload = read_fd(fd, info.st_size)
        return fd, info, payload
    except Exception:
        os.close(fd)
        raise


def copy_xattrs(source_fd: int, target_fd: int) -> None:
    if sys.platform == "darwin":
        copyfile_acl_and_xattr = (1 << 0) | (1 << 2)
        libc = ctypes.CDLL(None, use_errno=True)
        if libc.fcopyfile(source_fd, target_fd, None, copyfile_acl_and_xattr) == 0:
            return
        error_number = ctypes.get_errno()
        if error_number in {errno.ENOTSUP, errno.EOPNOTSUPP}:
            return
        raise CleanupError("cannot preserve mutable config metadata")
    if not hasattr(os, "listxattr"):
        return
    try:
        names = os.listxattr(source_fd)
    except OSError as error:
        if error.errno in {errno.ENOTSUP, errno.EOPNOTSUPP}:
            return
        raise CleanupError("cannot inspect mutable config metadata") from error
    for name in names:
        try:
            os.setxattr(target_fd, name, os.getxattr(source_fd, name))
        except OSError as error:
            raise CleanupError("cannot preserve mutable config metadata") from error


def create_temp(parent_fd: int) -> tuple[int, str]:
    for _ in range(100):
        name = f".retired-mcp.{os.getpid()}.{secrets.token_hex(8)}"
        try:
            fd = os.open(
                name,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
                0o600,
                dir_fd=parent_fd,
            )
            return fd, name
        except FileExistsError:
            continue
    raise CleanupError("cannot create temporary mutable config")


def revalidate(parent_fd: int, name: str, expected: tuple[Any, ...]) -> None:
    opened = open_leaf(parent_fd, name)
    if opened is None:
        raise CleanupError("mutable config disappeared during cleanup")
    fd, info, payload = opened
    try:
        if file_identity(info, payload) != expected:
            raise CleanupError("mutable config changed during cleanup")
    finally:
        os.close(fd)


def update_file(
    home_fd: int,
    relative: str,
    transform: Callable[[str], str],
    dry_run: bool,
) -> None:
    parent = open_parent(home_fd, relative)
    if parent is None:
        return
    parent_fd, name = parent
    source_fd = -1
    temp_fd = -1
    temp_name: str | None = None
    try:
        opened = open_leaf(parent_fd, name)
        if opened is None:
            return
        source_fd, info, payload = opened
        try:
            text = payload.decode("utf-8")
        except UnicodeDecodeError as error:
            raise CleanupError("mutable config is not UTF-8") from error
        rendered = transform(text)
        encoded = rendered.encode("utf-8")
        if encoded == payload or dry_run:
            return

        expected = file_identity(info, payload)
        temp_fd, temp_name = create_temp(parent_fd)
        os.fchown(temp_fd, info.st_uid, info.st_gid)
        os.fchmod(temp_fd, stat.S_IMODE(info.st_mode))
        copy_xattrs(source_fd, temp_fd)
        view = memoryview(encoded)
        while view:
            written = os.write(temp_fd, view)
            if written <= 0:
                raise CleanupError("cannot write temporary mutable config")
            view = view[written:]
        os.fsync(temp_fd)
        os.close(temp_fd)
        temp_fd = -1

        revalidate(parent_fd, name, expected)
        os.replace(temp_name, name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
        temp_name = None
        os.fsync(parent_fd)
    finally:
        if source_fd >= 0:
            os.close(source_fd)
        if temp_fd >= 0:
            os.close(temp_fd)
        if temp_name is not None:
            try:
                os.unlink(temp_name, dir_fd=parent_fd)
            except FileNotFoundError:
                pass
        os.close(parent_fd)


def process(home: Path, plan: dict[str, Any], dry_run: bool) -> None:
    if not home.is_absolute():
        raise CleanupError("cleanup home must be absolute")
    try:
        home_info = os.lstat(home)
    except OSError as error:
        raise CleanupError("cannot inspect cleanup home") from error
    if not stat.S_ISDIR(home_info.st_mode) or stat.S_ISLNK(home_info.st_mode):
        raise CleanupError("refusing unsafe cleanup home")
    if home_info.st_uid != os.getuid():
        raise CleanupError("cleanup home is not owned by current user")

    home_fd = os.open(home, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW)
    try:
        for root, managed in plan["codexManagedServers"].items():
            for filename in ("config.toml", "config.toml.bak"):
                update_file(
                    home_fd,
                    f"{root}/{filename}",
                    lambda text, names=managed: clean_toml(text, plan, names),
                    dry_run,
                )
        for root, managed in plan["claudeManagedServers"].items():
            update_file(
                home_fd,
                f"{root}/.claude.json",
                lambda text, names=managed: clean_json(text, "claude", plan, names),
                dry_run,
            )
        for root in plan["piRoots"]:
            update_file(
                home_fd,
                f"{root}/mcp-cache.json",
                lambda text: clean_json(text, "pi-cache", plan),
                dry_run,
            )
        for root in plan["manifestRoots"]:
            update_file(
                home_fd,
                f"{root}/.prompt-deploy-manifest.json",
                lambda text: clean_json(text, "manifest", plan),
                dry_run,
            )
    finally:
        os.close(home_fd)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--home", required=True)
    parser.add_argument("--plan-json", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        process(Path(args.home), load_plan(args.plan_json), args.dry_run)
    except CleanupError as error:
        print(f"nix-managed AI: retired MCP cleanup: {error}", file=sys.stderr)
        return 1
    except Exception:
        print(
            "nix-managed AI: retired MCP cleanup: internal cleanup failure",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
