#!/usr/bin/env python3
"""Fail-closed offline hardening for a bootstrapped Syncthing 2.1.2 config."""

from __future__ import annotations

import argparse
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--apply", action="store_true")
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--local-device-id", required=True)
    parser.add_argument("--peer-device-id", required=True)
    parser.add_argument("--peer-address", dest="peer_addresses", action="append", required=True)
    parser.add_argument("--listen-address", required=True)
    parser.add_argument("--peer-network", dest="peer_networks", action="append", required=True)
    parser.add_argument("--gui-socket", required=True)
    parser.add_argument("--vault", type=Path, required=True)
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


def harden(root: ET.Element, args: argparse.Namespace) -> bool:
    if root.tag != "configuration" or root.get("version") != CONFIG_VERSION:
        raise BootstrapError("config.xml is not the reviewed Syncthing 2.1.2 schema")

    devices = root.findall("device")
    if args.local_device_id == args.peer_device_id:
        raise BootstrapError("the local and peer identities must be distinct")
    if sum(device.get("id") == args.local_device_id for device in devices) != 1:
        raise BootstrapError("the bootstrapped local identity is absent from config.xml")
    if sum(device.get("id") == args.peer_device_id for device in devices) > 1:
        raise BootstrapError("config.xml contains duplicate peer identities")

    changed = False
    for device in list(devices):
        device_id = device.get("id")
        if device_id not in (args.local_device_id, args.peer_device_id):
            root.remove(device)
            changed = True
            continue
        if device_id != args.peer_device_id:
            continue
        changed |= replace_values(device, "address", args.peer_addresses)
        changed |= replace_values(device, "allowedNetwork", args.peer_networks)
        for tag in ("paused", "autoAcceptFolders", "untrusted"):
            changed |= replace_values(device, tag, ["false"])
        peer_attributes = {
            "compression": "metadata",
            "introducer": "false",
            "skipIntroductionRemovals": "false",
            "introducedBy": "",
        }
        for name, value in peer_attributes.items():
            if device.get(name) != value:
                device.set(name, value)
                changed = True

    peer_present = any(device.get("id") == args.peer_device_id for device in root.findall("device"))
    for folder in list(root.findall("folder")):
        folder_devices = [device.get("id") for device in folder.findall("device")]
        if (
            folder.get("id") != "obsidian"
            or folder.get("path") != str(args.vault)
            or len(folder_devices) != 2
            or set(folder_devices) != {args.local_device_id, args.peer_device_id}
            or not peer_present
        ):
            root.remove(folder)
            changed = True

    options = root.find("options")
    gui = root.find("gui")
    if options is None or gui is None:
        raise BootstrapError("config.xml is missing required policy sections")

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
    changed |= replace_values(options, "alwaysLocalNet", args.peer_networks)
    # Home Manager persists [] as absent XML nodes, while Syncthing 2.1.2
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
