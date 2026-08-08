#!/usr/bin/env python3
"""Fail-closed offline hardening for a bootstrapped Syncthing 2.1.3 config."""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

CONFIG_VERSION = "52"
NEEDS_UPDATE = 3


class BootstrapError(RuntimeError):
    pass


def parse_peer_policy(value: str) -> dict[str, object]:
    try:
        policy = json.loads(value)
    except json.JSONDecodeError as error:
        raise argparse.ArgumentTypeError("peer policy is not valid JSON") from error
    required = {"deviceID", "addresses", "networks", "autoAcceptFolders"}
    if not isinstance(policy, dict) or set(policy) != required:
        raise argparse.ArgumentTypeError("peer policy has unexpected fields")
    if not isinstance(policy["deviceID"], str) or not policy["deviceID"]:
        raise argparse.ArgumentTypeError("peer policy has no device ID")
    for field in ("addresses", "networks"):
        values = policy[field]
        if (
            not isinstance(values, list)
            or not values
            or not all(isinstance(item, str) and item for item in values)
        ):
            raise argparse.ArgumentTypeError(f"peer policy has invalid {field}")
    if not isinstance(policy["autoAcceptFolders"], bool):
        raise argparse.ArgumentTypeError("peer policy has invalid auto-accept setting")
    return policy


def parse_default_policy(value: str) -> dict[str, object]:
    try:
        policy = json.loads(value)
    except json.JSONDecodeError as error:
        raise argparse.ArgumentTypeError("default policy is not valid JSON") from error
    if not isinstance(policy, dict) or set(policy) != {"folder", "ignores"}:
        raise argparse.ArgumentTypeError("default policy has unexpected fields")

    folder = policy["folder"]
    expected_folder_fields = {
        "disableFsync",
        "fsWatcherDelayS",
        "fsWatcherEnabled",
        "fsWatcherTimeoutS",
        "maxConcurrentWrites",
        "path",
        "rescanIntervalS",
        "scanProgressIntervalS",
    }
    if not isinstance(folder, dict) or set(folder) != expected_folder_fields:
        raise argparse.ArgumentTypeError("default folder policy has unexpected fields")
    if not isinstance(folder["path"], str) or not folder["path"]:
        raise argparse.ArgumentTypeError("default folder policy has no path")
    if type(folder["fsWatcherEnabled"]) is not bool:
        raise argparse.ArgumentTypeError("default folder watcher setting is invalid")
    if (
        type(folder["fsWatcherDelayS"]) not in (int, float)
        or folder["fsWatcherDelayS"] < 0
    ):
        raise argparse.ArgumentTypeError("default folder watcher delay is invalid")
    if (
        type(folder["fsWatcherTimeoutS"]) not in (int, float)
        or folder["fsWatcherTimeoutS"] < 0
    ):
        raise argparse.ArgumentTypeError("default folder watcher timeout is invalid")
    for field in ("rescanIntervalS", "scanProgressIntervalS", "maxConcurrentWrites"):
        if type(folder[field]) is not int:
            raise argparse.ArgumentTypeError(f"default folder {field} is invalid")
    if type(folder["disableFsync"]) is not bool:
        raise argparse.ArgumentTypeError("default folder fsync setting is invalid")

    ignores = policy["ignores"]
    if (
        not isinstance(ignores, list)
        or not ignores
        or not all(isinstance(pattern, str) and pattern for pattern in ignores)
        or len(ignores) != len(set(ignores))
    ):
        raise argparse.ArgumentTypeError("default ignore policy is invalid")
    return policy


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--apply", action="store_true")
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--local-device-id", required=True)
    parser.add_argument(
        "--peer-policy",
        dest="peer_policies",
        action="append",
        type=parse_peer_policy,
        required=True,
    )
    parser.add_argument("--listen-address", required=True)
    parser.add_argument("--gui-socket", required=True)
    parser.add_argument("--default-policy", type=parse_default_policy, required=True)
    parser.add_argument("--documents", type=Path, required=True)
    parser.add_argument("--desktop", type=Path, required=True)
    return parser.parse_args()


def read_regular_file(path: Path) -> tuple[bytes, os.stat_result]:
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode):
        raise BootstrapError("config.xml must be a regular file")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags)
    try:
        opened = os.fstat(fd)
        if (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
            raise BootstrapError("config.xml changed during validation")
        chunks: list[bytes] = []
        while chunk := os.read(fd, 1024 * 1024):
            chunks.append(chunk)
    finally:
        os.close(fd)
    return b"".join(chunks), before


def replace_values(parent: ET.Element, tag: str, values: list[str]) -> bool:
    existing = [child.text or "" for child in parent.findall(tag)]
    if existing == values:
        return False
    for child in list(parent.findall(tag)):
        parent.remove(child)
    for value in values:
        element = ET.SubElement(parent, tag)
        element.text = value
    return True


def normalize_inactive_default(parent: ET.Element, tag: str) -> bool:
    existing = [child.text or "" for child in parent.findall(tag)]
    if existing in ([], ["default"]):
        return False
    return replace_values(parent, tag, ["default"])


def xml_scalar(value: object) -> str:
    if type(value) is bool:
        return str(value).lower()
    if type(value) is float and value.is_integer():
        return str(int(value))
    return str(value)


def apply_folder_policy(folder: ET.Element, policy: dict[str, object]) -> bool:
    changed = False
    for name in (
        "rescanIntervalS",
        "fsWatcherEnabled",
        "fsWatcherDelayS",
        "fsWatcherTimeoutS",
    ):
        value = xml_scalar(policy[name])
        if folder.get(name) != value:
            folder.set(name, value)
            changed = True
    for tag in ("scanProgressIntervalS", "maxConcurrentWrites", "disableFsync"):
        changed |= replace_values(folder, tag, [xml_scalar(policy[tag])])
    return changed


def harden(root: ET.Element, args: argparse.Namespace) -> bool:
    if root.tag != "configuration" or root.get("version") != CONFIG_VERSION:
        raise BootstrapError("config.xml is not the reviewed Syncthing 2.1.3 schema")

    devices = root.findall("device")
    peer_ids = [policy["deviceID"] for policy in args.peer_policies]
    if args.local_device_id in peer_ids or len(peer_ids) != len(set(peer_ids)):
        raise BootstrapError("the local and peer identities must be distinct")
    if sum(device.get("id") == args.local_device_id for device in devices) != 1:
        raise BootstrapError(
            "the bootstrapped local identity is absent from config.xml"
        )
    if any(
        sum(device.get("id") == peer_id for device in devices) > 1
        for peer_id in peer_ids
    ):
        raise BootstrapError("config.xml contains duplicate peer identities")

    changed = False
    policies_by_id = {policy["deviceID"]: policy for policy in args.peer_policies}
    for device in list(devices):
        device_id = device.get("id")
        if device_id == args.local_device_id or device_id in policies_by_id:
            continue
        root.remove(device)
        changed = True

    peer_attributes = {
        "compression": "metadata",
        "introducer": "false",
        "skipIntroductionRemovals": "false",
        "introducedBy": "",
    }
    for policy in args.peer_policies:
        peer_id = policy["deviceID"]
        device = next(
            (
                candidate
                for candidate in root.findall("device")
                if candidate.get("id") == peer_id
            ),
            None,
        )
        if device is None:
            device = ET.SubElement(root, "device", {"id": peer_id})
            changed = True
        changed |= replace_values(device, "address", policy["addresses"])
        changed |= replace_values(device, "allowedNetwork", policy["networks"])
        changed |= replace_values(device, "paused", ["false"])
        changed |= replace_values(
            device,
            "autoAcceptFolders",
            [str(policy["autoAcceptFolders"]).lower()],
        )
        changed |= replace_values(device, "untrusted", ["false"])
        for name, value in peer_attributes.items():
            if device.get(name) != value:
                device.set(name, value)
                changed = True

    expected_folder_devices = [args.local_device_id, *peer_ids]
    legacy_obsidian_path = str(args.documents.parent / "doc" / "obsidian")
    for folder in list(root.findall("folder")):
        folder_devices = [device.get("id") for device in folder.findall("device")]
        if (
            folder.get("id") == "obsidian"
            and folder.get("path") == legacy_obsidian_path
            and len(folder_devices) == len(expected_folder_devices)
            and set(folder_devices) == set(expected_folder_devices)
        ):
            # Retire only the former repository-owned share; its files remain untouched.
            root.remove(folder)
            changed = True

    managed_folders = {
        "documents": {"label": "Documents", "path": str(args.documents)},
        "desktop": {"label": "Desktop", "path": str(args.desktop)},
    }
    for folder_id, folder_policy in managed_folders.items():
        matches = [
            folder for folder in root.findall("folder") if folder.get("id") == folder_id
        ]
        if len(matches) > 1:
            raise BootstrapError("config.xml contains duplicate managed folders")
        if matches:
            folder = matches[0]
        else:
            folder = ET.SubElement(root, "folder", {"id": folder_id})
            changed = True
        folder_attributes = {
            "label": folder_policy["label"],
            "path": folder_policy["path"],
            "type": "sendreceive",
        }
        for name, value in folder_attributes.items():
            if folder.get(name) != value:
                folder.set(name, value)
                changed = True
        folder_devices = [device.get("id") for device in folder.findall("device")]
        if len(folder_devices) != len(expected_folder_devices) or set(
            folder_devices
        ) != set(expected_folder_devices):
            for device in list(folder.findall("device")):
                folder.remove(device)
            for device_id in expected_folder_devices:
                ET.SubElement(folder, "device", {"id": device_id})
            changed = True
        changed |= replace_values(folder, "paused", ["false"])

    # New autoaccepted folders clone the defaults below. Reapply the same
    # operational policy to retained folders so older shares cannot keep stale
    # watcher latency or concurrency settings across an activation.
    default_folder_policy = args.default_policy["folder"]
    for folder in root.findall("folder"):
        changed |= apply_folder_policy(folder, default_folder_policy)

    options_sections = root.findall("options")
    gui_sections = root.findall("gui")
    defaults_sections = root.findall("defaults")
    default_ignore_sections = (
        defaults_sections[0].findall("ignores") if defaults_sections else []
    )
    if (
        len(options_sections) != 1
        or len(gui_sections) != 1
        or len(defaults_sections) != 1
        or len(defaults_sections[0].findall("folder")) != 1
        or len(default_ignore_sections) > 1
    ):
        raise BootstrapError("config.xml has missing or duplicate policy sections")
    options = options_sections[0]
    gui = gui_sections[0]
    defaults = defaults_sections[0]
    default_folder = defaults.findall("folder")[0]
    if default_folder.get("path") != default_folder_policy["path"]:
        default_folder.set("path", str(default_folder_policy["path"]))
        changed = True
    changed |= apply_folder_policy(default_folder, default_folder_policy)
    if default_ignore_sections:
        default_ignores = default_ignore_sections[0]
    else:
        default_ignores = ET.SubElement(defaults, "ignores")
        changed = True
    changed |= replace_values(default_ignores, "line", args.default_policy["ignores"])

    singleton_options = {
        "listenAddress": args.listen_address,
        "globalAnnounceEnabled": "false",
        "localAnnounceEnabled": "false",
        "announceLANAddresses": "false",
        "relaysEnabled": "false",
        "natEnabled": "false",
        "reconnectionIntervalS": "5",
        "urAccepted": "-1",
        "crashReportingEnabled": "false",
        "autoUpgradeIntervalH": "0",
        "startBrowser": "false",
    }
    for tag, value in singleton_options.items():
        changed |= replace_values(options, tag, [value])
    peer_networks = list(
        dict.fromkeys(
            network for policy in args.peer_policies for network in policy["networks"]
        )
    )
    changed |= replace_values(options, "alwaysLocalNet", peer_networks)
    # Home Manager persists [] as absent XML nodes, while Syncthing 2.1.3
    # rehydrates those nodes as "default" in memory. Both encodings are safe
    # only because the false booleans above are authoritative; reject anything
    # else without creating reactivation drift between the two encodings.
    changed |= normalize_inactive_default(options, "globalAnnounceServer")
    changed |= normalize_inactive_default(options, "stunServer")

    changed |= replace_values(gui, "address", [str(args.gui_socket)])
    changed |= replace_values(gui, "unixSocketPermissions", ["0600"])
    changed |= replace_values(gui, "metricsWithoutAuth", ["false"])
    gui_attributes = {
        "enabled": "true",
        "tls": "false",
        "sendBasicAuthPrompt": "false",
    }
    for name, value in gui_attributes.items():
        if gui.get(name) != value:
            gui.set(name, value)
            changed = True

    return changed


def atomic_write(path: Path, root: ET.Element, original: os.stat_result) -> None:
    current = path.lstat()
    if (current.st_dev, current.st_ino) != (original.st_dev, original.st_ino):
        raise BootstrapError("config.xml changed before replacement")

    fd, temporary_name = tempfile.mkstemp(prefix=".config.xml.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        os.fchmod(fd, stat.S_IMODE(original.st_mode))
        with os.fdopen(fd, "wb", closefd=True) as output:
            ET.ElementTree(root).write(output, encoding="utf-8", xml_declaration=True)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def main() -> int:
    args = parse_args()
    try:
        payload, original = read_regular_file(args.config)
        root = ET.fromstring(payload)
        changed = harden(root, args)
        if args.check:
            return NEEDS_UPDATE if changed else 0
        if changed:
            atomic_write(args.config, root, original)
        return 0
    except (BootstrapError, ET.ParseError, OSError) as error:
        print(f"syncthing-bootstrap: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
