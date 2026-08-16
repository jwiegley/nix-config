#!/usr/bin/env python3
"""Behavioral dispatch tests for switch and Linux upgrade paths."""

import os
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
SWITCH = REPO / "bin/switch"
ROUTING = REPO / "bin/lib/host-routing.sh"
UPGRADE = REPO / "bin/upgrade"
BASH = shutil.which("bash") or "/bin/bash"


def write_executable(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(0o755)


def shared_work_hosts() -> list[str]:
    result = subprocess.run(
        [
            BASH,
            "-c",
            'source "$1"; nix_shared_work_members',
            "routing",
            str(ROUTING),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.splitlines()


class SwitchTests(unittest.TestCase):
    def run_switch(
        self,
        host: str,
        driver_status: int | None = 0,
        *,
        system_checkout: bool = True,
        home_checkout: bool = True,
        u_status: int = 0,
    ):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            script_dir = root / "bin"
            (script_dir / "lib").mkdir(parents=True)
            system_config = root / "etc/nixos"
            if system_checkout:
                system_config.mkdir(parents=True)
            home_manager = root / "home/.config/home-manager"
            if home_checkout:
                home_manager.mkdir(parents=True)
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            driver_log = root / "driver.log"
            nix_log = root / "nix.args"
            u_log = root / "u.args"
            forbidden_log = root / "forbidden.log"
            generation = root / "generation"
            generation.mkdir()
            activation_marker = root / "activated"

            source = SWITCH.read_text(encoding="utf-8")
            old = "system_config_dir=/etc/nixos"
            self.assertEqual(source.count(old), 1)
            source = source.replace(
                old, f"system_config_dir={shlex.quote(str(system_config))}"
            )
            write_executable(script_dir / "switch", source)
            (script_dir / "lib/host-routing.sh").write_text(
                ROUTING.read_text(encoding="utf-8"), encoding="utf-8"
            )

            if system_checkout and driver_status is not None:
                write_executable(
                    system_config / "build",
                    """#!/bin/sh
printf '%s\t%s\t%s\n' "$PWD" "$#" "$*" >"$DRIVER_LOG"
if [ "$DRIVER_STATUS" -ne 0 ]; then printf 'build driver refused lock\n' >&2; fi
exit "$DRIVER_STATUS"
""",
                )
            write_executable(fake_bin / "hostname", f"#!/bin/sh\nprintf '{host}\\n'\n")
            write_executable(fake_bin / "uname", "#!/bin/sh\nprintf 'Linux\n'\n")
            for name in ("nixos-rebuild", "sudo"):
                write_executable(
                    fake_bin / name,
                    f"#!/bin/sh\nprintf '{name}\\n' >>\"$FORBIDDEN_LOG\"\nexit 99\n",
                )
            write_executable(
                fake_bin / "u",
                '#!/bin/sh\nprintf \'%s\\n\' "$*" >"$U_LOG"\nexit "$U_STATUS"\n',
            )
            write_executable(
                fake_bin / "nix",
                '#!/bin/sh\nprintf \'%s\\n\' "$@" >"$NIX_LOG"\nprintf \'%s\\n\' "$GENERATION"\n',
            )
            write_executable(
                generation / "activate",
                '#!/bin/sh\nprintf activated >"$ACTIVATION_MARKER"\n',
            )

            result = subprocess.run(
                [str(script_dir / "switch")],
                env={
                    **os.environ,
                    "DRIVER_LOG": str(driver_log),
                    "DRIVER_STATUS": str(driver_status or 0),
                    "NIX_LOG": str(nix_log),
                    "U_LOG": str(u_log),
                    "U_STATUS": str(u_status),
                    "ACTIVATION_MARKER": str(activation_marker),
                    "FORBIDDEN_LOG": str(forbidden_log),
                    "GENERATION": str(generation),
                    "HOME": str(root / "home"),
                    "PATH": f"{fake_bin}{os.pathsep}{os.environ.get('PATH', os.defpath)}",
                },
                capture_output=True,
                text=True,
                check=False,
            )
            return (
                result,
                driver_log.read_text(encoding="utf-8") if driver_log.exists() else "",
                nix_log.read_text(encoding="utf-8") if nix_log.exists() else "",
                u_log.read_text(encoding="utf-8") if u_log.exists() else "",
                activation_marker.exists(),
                forbidden_log.exists(),
            )

    def test_vulcan_and_vps_delegate_to_host_build_driver(self):
        for host, expected in (
            ("vulcan", "\t1\tswitch\n"),
            ("vps", "\t5\tswitch --max-jobs 1 --cores 1\n"),
        ):
            with self.subTest(host=host):
                result, driver_log, nix_log, u_log, activated, forbidden = (
                    self.run_switch(host)
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue(driver_log.endswith(expected), driver_log)
                self.assertEqual(nix_log, "")
                self.assertEqual(u_log, "")
                self.assertFalse(activated)
                self.assertFalse(forbidden)

    def test_build_driver_lock_refusal_is_propagated(self):
        result, _driver_log, nix_log, u_log, activated, forbidden = self.run_switch(
            "vulcan", 75
        )
        self.assertEqual(result.returncode, 75, result.stdout + result.stderr)
        self.assertIn("build driver refused lock", result.stderr)
        self.assertEqual(nix_log, "")
        self.assertEqual(u_log, "")
        self.assertFalse(activated)
        self.assertFalse(forbidden)

    def test_missing_build_driver_fails_before_raw_rebuild(self):
        result, driver_log, nix_log, u_log, activated, forbidden = self.run_switch(
            "vps", None
        )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("build driver is missing or not executable", result.stderr)
        self.assertEqual(driver_log, "")
        self.assertEqual(nix_log, "")
        self.assertEqual(u_log, "")
        self.assertFalse(activated)
        self.assertFalse(forbidden)

    def test_shared_work_ignores_competing_nixos_checkout(self):
        for host in shared_work_hosts():
            with self.subTest(host=host):
                result, driver_log, nix_log, u_log, activated, forbidden = (
                    self.run_switch(host)
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(driver_log, "")
                self.assertEqual(u_log, "")
                self.assertTrue(activated)
                self.assertFalse(forbidden)
                self.assertEqual(
                    nix_log.splitlines(),
                    [
                        "build",
                        "--no-link",
                        "--print-out-paths",
                        '.#homeConfigurations."jwiegley".activationPackage',
                    ],
                )

    def test_darwin_delegation_propagates_failure(self):
        for host in ("hera", "clio"):
            with self.subTest(host=host):
                result, driver_log, nix_log, u_log, activated, forbidden = (
                    self.run_switch(host, u_status=76)
                )
                self.assertEqual(result.returncode, 76, result.stdout + result.stderr)
                self.assertEqual(driver_log, "")
                self.assertEqual(nix_log, "")
                self.assertEqual(u_log, "switch\n")
                self.assertFalse(activated)
                self.assertFalse(forbidden)

    def test_missing_checkout_fallback_propagates_failure(self):
        for host, expected in (
            ("andoria-08", "shared-work switch\n"),
            ("vulcan", "vulcan switch\n"),
        ):
            with self.subTest(host=host):
                result, driver_log, nix_log, u_log, activated, forbidden = (
                    self.run_switch(
                        host,
                        system_checkout=False,
                        home_checkout=False,
                        u_status=77,
                    )
                )
                self.assertEqual(result.returncode, 77, result.stdout + result.stderr)
                self.assertEqual(driver_log, "")
                self.assertEqual(nix_log, "")
                self.assertEqual(u_log, expected)
                self.assertFalse(activated)
                self.assertFalse(forbidden)

    def test_linux_upgrade_routes_through_switch_and_propagates_failure(self):
        for host in ("vulcan", "vps"):
            with self.subTest(host=host), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                fake_bin = root / "bin"
                fake_bin.mkdir()
                command_log = root / "commands.log"
                write_executable(fake_bin / "uname", "#!/bin/sh\nprintf 'Linux\n'\n")
                write_executable(
                    fake_bin / "switch",
                    """#!/bin/sh
printf 'switch %s\n' "$*" >"$COMMAND_LOG"
exit 76
""",
                )
                result = subprocess.run(
                    [str(UPGRADE), host, "--host-only"],
                    env={
                        **os.environ,
                        "COMMAND_LOG": str(command_log),
                        "HOME": str(root / "home"),
                        "PATH": f"{fake_bin}{os.pathsep}{os.environ.get('PATH', os.defpath)}",
                    },
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 76, result.stdout + result.stderr)
                self.assertEqual(command_log.read_text(encoding="utf-8"), "switch \n")


if __name__ == "__main__":
    unittest.main()
