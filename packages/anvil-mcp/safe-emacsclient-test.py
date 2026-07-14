#!/usr/bin/env python3
"""Adversarial tests for the dedicated same-root emacsclient guard."""

from __future__ import annotations

import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile

EXIT_DELEGATED = 23
EXIT_USAGE = 64
EXIT_RECURSION = 69
DELEGATED_MARKER = "anvil-safe-client-delegated"
SUBPROCESS_TIMEOUT_SECONDS = 10


def guarded_environment(
    root_socket: Path, overrides: dict[str, str] | None = None
) -> dict[str, str]:
    """Return a deterministic dedicated-root environment."""
    environment = os.environ.copy()
    environment["ANVIL_EMACS_SOCKET"] = str(root_socket)
    environment["XDG_RUNTIME_DIR"] = str(root_socket.parent.parent)
    environment.pop("EMACS_SOCKET_NAME", None)
    environment.pop("EMACS_SERVER_FILE", None)
    if overrides:
        environment.update(overrides)
    return environment


def run_guard(
    guard: Path,
    real_client: Path,
    arguments: list[str],
    root_socket: Path,
    cwd: Path,
    overrides: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run GUARD directly so delegation has an unambiguous marker status."""
    return subprocess.run(
        [sys.executable, "-I", "-S", str(guard), str(real_client), *arguments],
        cwd=cwd,
        env=guarded_environment(root_socket, overrides),
        capture_output=True,
        text=True,
        timeout=SUBPROCESS_TIMEOUT_SECONDS,
        check=False,
    )


def assert_refused(
    guard: Path,
    real_client: Path,
    label: str,
    arguments: list[str],
    root_socket: Path,
    cwd: Path,
    overrides: dict[str, str] | None = None,
) -> None:
    """Require ARGUMENTS to be rejected specifically as same-root recursion."""
    result = run_guard(guard, real_client, arguments, root_socket, cwd, overrides)
    if result.returncode != EXIT_RECURSION:
        raise AssertionError(
            f"{label} was not refused as recursion: rc={result.returncode}, "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )


def assert_delegated(
    guard: Path,
    real_client: Path,
    label: str,
    arguments: list[str],
    root_socket: Path,
    cwd: Path,
    overrides: dict[str, str] | None = None,
) -> None:
    """Require ARGUMENTS to reach the marker client, not merely avoid 69."""
    result = run_guard(guard, real_client, arguments, root_socket, cwd, overrides)
    if result.returncode != EXIT_DELEGATED or result.stdout != DELEGATED_MARKER:
        raise AssertionError(
            f"{label} was not delegated: rc={result.returncode}, "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )


def run_wrapper(
    wrapper: Path,
    arguments: list[str],
    root_socket: Path,
    cwd: Path,
) -> subprocess.CompletedProcess[str]:
    """Run the composed wrapper against packaged Emacsclient."""
    return subprocess.run(
        [str(wrapper), *arguments],
        cwd=cwd,
        env=guarded_environment(root_socket),
        capture_output=True,
        text=True,
        timeout=SUBPROCESS_TIMEOUT_SECONDS,
        check=False,
    )


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(
            "usage: safe-emacsclient-test.py GUARD.py /path/to/emacsclient"
        )
    guard = Path(sys.argv[1]).resolve()
    wrapper = Path(sys.argv[2]).resolve()

    with (
        # Darwin's sockaddr_un path is short (104 bytes), while its default
        # TMPDIR is long.  A short explicit root keeps this live-socket test
        # portable without weakening the production path checks.
        tempfile.TemporaryDirectory(prefix="anvil-", dir="/tmp") as raw_tmp,
        socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as root_listener,
        socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as other_listener,
    ):
        tmp = Path(raw_tmp)
        runtime = tmp / "runtime"
        socket_dir = runtime / "emacs"
        socket_dir.mkdir(parents=True)
        root_socket = socket_dir / "server"
        other_socket = socket_dir / "other"
        root_listener.bind(str(root_socket))
        root_listener.listen()
        root_listener.settimeout(1)
        other_listener.bind(str(other_socket))
        other_listener.listen()
        root_alias = tmp / "root-alias"
        root_alias.symlink_to(root_socket)
        root_hardlink = tmp / "root-hardlink"
        os.link(root_socket, root_hardlink)
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as alias_client:
            alias_client.connect(str(root_hardlink))
            accepted, _address = root_listener.accept()
            accepted.close()
        marker_client = tmp / "marker-client"
        marker_client.write_text(
            f"#!/bin/sh\nprintf %s {DELEGATED_MARKER!r}\nexit {EXIT_DELEGATED}\n"
        )
        marker_client.chmod(0o700)

        root = str(root_socket)
        other = str(other_socket)
        base = ["-a", "false"]
        refused: list[tuple[str, list[str], dict[str, str] | None]] = [
            ("implicit default", [*base, "-e", "t"], None),
            (
                "implicit default outside authoritative runtime",
                [*base, "-e", "t"],
                {"XDG_RUNTIME_DIR": str(tmp / "implicit-runtime")},
            ),
            ("split short", [*base, "-s", root, "-e", "t"], None),
            ("joined short", [*base, f"-s{root}", "-e", "t"], None),
            ("short cluster", [*base, f"-qs{root}", "-e", "t"], None),
            (
                "split double-dash long",
                [*base, "--socket-name", root, "-e", "t"],
                None,
            ),
            (
                "joined double-dash long",
                [*base, f"--socket-name={root}", "-e", "t"],
                None,
            ),
            (
                "double-dash abbreviation",
                [*base, f"--so={root}", "-e", "t"],
                None,
            ),
            (
                "single-dash long",
                [*base, f"-socket-name={root}", "-e", "t"],
                None,
            ),
            (
                "single-dash abbreviation",
                [*base, f"-so={root}", "-e", "t"],
                None,
            ),
            ("socket basename", [*base, "-s", "server", "-e", "t"], None),
            (
                "relative socket",
                [*base, "-s", "./emacs/server", "-e", "t"],
                None,
            ),
            (
                "symlink alias",
                [*base, "-s", str(root_alias), "-e", "t"],
                None,
            ),
            (
                "hardlink alias",
                [*base, "-s", str(root_hardlink), "-e", "t"],
                None,
            ),
            (
                "socket wins a later server file",
                [*base, "-s", root, "-f", other, "-e", "t"],
                None,
            ),
            (
                "socket wins an earlier server file",
                [*base, "-f", other, "-s", root, "-e", "t"],
                None,
            ),
            (
                "environment socket wins CLI server file",
                [*base, "-f", other, "-e", "t"],
                {"EMACS_SOCKET_NAME": root},
            ),
            (
                "environment socket wins environment server file",
                [*base, "-e", "t"],
                {"EMACS_SOCKET_NAME": root, "EMACS_SERVER_FILE": other},
            ),
        ]
        for label, arguments, overrides in refused:
            assert_refused(
                guard,
                marker_client,
                label,
                arguments,
                root_socket,
                runtime,
                overrides,
            )

        delegated: list[tuple[str, list[str], dict[str, str] | None]] = [
            ("different split socket", [*base, "-s", other, "-e", "t"], None),
            ("different joined socket", [*base, f"-s{other}", "-e", "t"], None),
            (
                "different single-dash long",
                [*base, f"-so={other}", "-e", "t"],
                None,
            ),
            (
                "last CLI socket overrides environment",
                [*base, "-s", other, "-e", "t"],
                {"EMACS_SOCKET_NAME": root},
            ),
            (
                "environment selects a peer socket",
                [*base, "-e", "t"],
                {"EMACS_SOCKET_NAME": other},
            ),
            (
                "CLI server file without socket",
                [*base, "-f", other, "-e", "t"],
                None,
            ),
            (
                "environment server file without socket",
                [*base, "-e", "t"],
                {"EMACS_SERVER_FILE": other},
            ),
            ("short help", ["-H"], None),
            ("double-dash help", ["--help"], None),
            ("single-dash help", ["-help"], None),
            ("single-letter help prefix", ["-h"], None),
            ("short version", ["-V"], None),
            ("double-dash version", ["--version"], None),
            ("single-dash version", ["-version"], None),
            ("single-letter version prefix", ["-v"], None),
            ("help exits before a later invalid option", ["-H", "--bogus"], None),
            (
                "single-letter parent prefix",
                ["-p", "123", "-s", other],
                None,
            ),
            ("single-letter reuse prefix", ["-r", "-s", other], None),
            ("double-dash nw to peer", ["--nw", "-s", other], None),
            (
                "single-dash no-window to peer",
                ["-no-window-system", "-s", other],
                None,
            ),
            (
                "separator stops socket parsing",
                [*base, "-s", other, "--", f"-s{root}"],
                None,
            ),
            (
                "display consumes root-looking value",
                [*base, "-d", f"-s{root}", "-s", other],
                None,
            ),
            (
                "frame option consumes root-looking value",
                [*base, f"-F-s{root}", "-s", other],
                None,
            ),
        ]
        for label, arguments, overrides in delegated:
            assert_delegated(
                guard,
                marker_client,
                label,
                arguments,
                root_socket,
                runtime,
                overrides,
            )

        invalid_before_help = run_guard(
            guard,
            marker_client,
            ["--bogus", "-H"],
            root_socket,
            runtime,
        )
        if invalid_before_help.returncode != EXIT_USAGE:
            raise AssertionError("invalid option before help was delegated")

        for arguments in (
            ["-H"],
            ["--version"],
            ["-help"],
            ["-h"],
            ["-v"],
            ["-H", "--bogus"],
        ):
            result = run_wrapper(wrapper, list(arguments), root_socket, runtime)
            if result.returncode != 0:
                raise AssertionError(
                    f"packaged Emacsclient rejected {arguments}: {result.stderr!r}"
                )
        composed_refusal = run_wrapper(
            wrapper,
            [*base, f"-so={root}", "-f", other, "-e", "t"],
            root_socket,
            runtime,
        )
        if composed_refusal.returncode != EXIT_RECURSION:
            raise AssertionError("composed wrapper missed socket precedence")

        orphaned_root_alias = tmp / "root-after-authoritative-unlink"
        os.link(root_socket, orphaned_root_alias)
        root_socket.unlink()
        assert_refused(
            guard,
            marker_client,
            "hardlink remains after authoritative root unlink",
            [*base, "-s", str(orphaned_root_alias), "-e", "t"],
            root_socket,
            runtime,
        )

    print("safe emacsclient test: long-only grammar and precedence verified")


if __name__ == "__main__":
    main()
