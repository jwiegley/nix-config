#!/usr/bin/env python3
"""Behavioral contracts for generated host routing and its dispatchers."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
ROUTING = REPO / "bin/lib/host-routing.sh"
BUILD = REPO / "build"
UPDATE_REMOTE = REPO / "bin/update-remote"
BASH = shutil.which("bash") or "/bin/bash"


def write_executable(path, text):
    path.write_text(text, encoding="utf-8")
    path.chmod(0o755)


class HostRoutingTests(unittest.TestCase):
    def call_routing(self, function, value=None):
        command = f'source "$1"; {function}'
        arguments = [BASH, "-c", command, "routing", str(ROUTING)]
        if value is not None:
            command += ' "$2"'
            arguments = [BASH, "-c", command, "routing", str(ROUTING), value]
        return subprocess.run(arguments, capture_output=True, text=True, check=False)

    def test_normalization_handles_fqdn_and_is_idempotent(self):
        fqdn_cases = {
            "Hera.example.org": "hera",
            "git-ai.example.org": "shared-work",
            "andoria-t2.example.org": "shared-work",
            "srp-next-01.example.org": "vps",
        }
        for hostname, expected in fqdn_cases.items():
            with self.subTest(hostname=hostname):
                result = self.call_routing("normalize_nix_host", hostname)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)

        for host_class in ("clio", "hera", "shared-work", "vps", "vulcan"):
            with self.subTest(host_class=host_class):
                result = self.call_routing("normalize_nix_host", host_class)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), host_class)

    def test_unknown_and_pattern_only_shared_work_names_are_refused(self):
        for hostname in ("unknown", "andoria-99", "gpu-experimental"):
            with self.subTest(hostname=hostname):
                result = self.call_routing("normalize_nix_host", hostname)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_flake_outputs_and_rollout_are_projected(self):
        expected_outputs = {
            "clio": "clio",
            "hera": "hera",
            "shared-work": "jwiegley",
            "vps": "ovh-vps",
            "vulcan": "vulcan",
        }
        for host_class, expected in expected_outputs.items():
            with self.subTest(host_class=host_class):
                result = self.call_routing("nix_flake_output_for_host", host_class)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)

        expected_activations = {
            "clio": "darwin",
            "hera": "darwin",
            "shared-work": "home-standalone",
            "vps": "nixos-module",
            "vulcan": "nixos-module",
        }
        for host_class, expected in expected_activations.items():
            with self.subTest(host_class=host_class):
                result = self.call_routing("nix_activation_for_host", host_class)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)

        members = self.call_routing("nix_shared_work_members")
        rollout = self.call_routing("nix_active_shared_work_rollout_hosts")
        self.assertEqual(members.returncode, 0, members.stderr)
        self.assertEqual(rollout.returncode, 0, rollout.stderr)
        member_names = members.stdout.splitlines()
        rollout_names = rollout.stdout.splitlines()
        self.assertIn("git-ai", member_names)
        self.assertNotIn("git-ai", rollout_names)
        self.assertEqual(len(rollout_names), 4)
        self.assertLessEqual(set(rollout_names), set(member_names))

    def test_local_build_limits_are_projected_only_for_bounded_hosts(self):
        limits = self.call_routing("nix_local_build_limits_for_host", "vps")
        self.assertEqual(limits.returncode, 0, limits.stderr)
        self.assertEqual(limits.stdout.strip(), "1 1")

        for host in ("hera", "clio", "vulcan", "shared-work"):
            with self.subTest(host=host):
                result = self.call_routing("nix_local_build_limits_for_host", host)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_build_dispatches_the_projected_darwin_output(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            command_log = root / "nix.args"
            write_executable(
                fake_bin / "myhost", "#!/bin/sh\nprintf '%s\\n' Hera.example.org\n"
            )
            write_executable(
                fake_bin / "nix",
                '#!/bin/sh\nprintf \'%s\\n\' "$@" >"$COMMAND_LOG"\n',
            )
            env = os.environ.copy()
            env.update(
                {
                    "COMMAND_LOG": str(command_log),
                    "PATH": f"{fake_bin}{os.pathsep}{os.defpath}",
                }
            )
            result = subprocess.run(
                [BASH, str(BUILD), "system"],
                cwd=REPO,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(
                ".#darwinConfigurations.hera.system",
                command_log.read_text(encoding="utf-8").splitlines(),
            )

    def test_update_remote_switches_only_the_active_rollout(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            ssh_log = root / "ssh.hosts"
            write_executable(fake_bin / "tmux", "#!/bin/sh\nexit 0\n")
            write_executable(
                fake_bin / "ssh",
                '#!/bin/sh\nprintf \'%s\\n\' "$1" >>"$SSH_LOG"\n',
            )
            env = os.environ.copy()
            env.update(
                {
                    "PATH": f"{fake_bin}{os.pathsep}{os.defpath}",
                    "SSH_LOG": str(ssh_log),
                }
            )
            result = subprocess.run(
                [BASH, str(UPDATE_REMOTE)],
                cwd=REPO,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            members = set(
                self.call_routing("nix_shared_work_members").stdout.splitlines()
            )
            shared_work_visits = [
                host
                for host in ssh_log.read_text(encoding="utf-8").splitlines()
                if host in members
            ]
            self.assertEqual(
                shared_work_visits,
                [
                    "andoria-08",
                    "andoria-08",
                    "andoria-t2",
                    "delphi-3bd4",
                    "gpu-server",
                ],
            )


if __name__ == "__main__":
    unittest.main()
