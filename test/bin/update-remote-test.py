#!/usr/bin/env python3
"""Behavioral tests for identified, synchronous remote rollout jobs."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
UPDATE_REMOTE = REPO / "bin/update-remote"

EXPECTED_COMMANDS = [
    ("clio", "cd ~/src/nix && ./bin/upgrade clio --host-only"),
    (
        "vulcan",
        "cd /etc/nixos && nix flake update --commit-lock-file && ./build switch",
    ),
    ("vps", "cd /etc/nixos && nix flake update --commit-lock-file && ./build switch"),
    (
        "andoria-08",
        "cd /home/jwiegley/.config/home-manager && nix flake update --commit-lock-file "
        "&& nix flake check --no-update-lock-file",
    ),
    ("andoria-08", "cd /home/jwiegley/.config/home-manager && switch"),
    ("andoria-t2", "cd /home/jwiegley/.config/home-manager && switch"),
    ("delphi-3bd4", "cd /home/jwiegley/.config/home-manager && switch"),
    ("gpu-server", "cd /home/jwiegley/.config/home-manager && switch"),
]
EXPECTED_JOBS = [
    "clio",
    "vulcan",
    "vps",
    "shared-work-update",
    "shared-work-andoria-08",
    "shared-work-andoria-t2",
    "shared-work-delphi-3bd4",
    "shared-work-gpu-server",
]


class UpdateRemoteTests(unittest.TestCase):
    def run_update_remote(
        self, fail_host="", fail_command="", fail_status=0, delay_command=""
    ):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            command_log = root / "commands.log"
            ssh = fake_bin / "ssh"
            ssh.write_text(
                """#!/bin/sh
printf 'start\t%s\t%s\n' "$1" "$2" >>"$COMMAND_LOG"
if [ "$2" = "${DELAY_COMMAND:-}" ]; then sleep 0.2; fi
if [ "$1" = "${FAIL_HOST:-}" ] && [ "$2" = "${FAIL_COMMAND:-}" ]; then
  exit "$FAIL_STATUS"
fi
printf 'complete\t%s\t%s\n' "$1" "$2" >>"$COMMAND_LOG"
""",
                encoding="utf-8",
            )
            ssh.chmod(0o755)
            result = subprocess.run(
                [str(UPDATE_REMOTE)],
                env={
                    **os.environ,
                    "COMMAND_LOG": str(command_log),
                    "DELAY_COMMAND": delay_command,
                    "FAIL_COMMAND": fail_command,
                    "FAIL_HOST": fail_host,
                    "FAIL_STATUS": str(fail_status),
                    "PATH": f"{fake_bin}{os.pathsep}{os.environ.get('PATH', os.defpath)}",
                },
                capture_output=True,
                text=True,
                check=False,
            )
            events = [
                tuple(line.split("\t", 2))
                for line in command_log.read_text(encoding="utf-8").splitlines()
            ]
            return result, events

    def test_jobs_have_stable_identity_checkout_paths_and_completion_order(self):
        result, events = self.run_update_remote(delay_command=EXPECTED_COMMANDS[0][1])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            events,
            [
                event
                for host, command in EXPECTED_COMMANDS
                for event in (
                    ("start", host, command),
                    ("complete", host, command),
                )
            ],
        )
        self.assertEqual(
            result.stdout.splitlines(),
            [
                line
                for job in EXPECTED_JOBS
                for line in (
                    f"update-remote: start {job}",
                    f"update-remote: complete {job}",
                )
            ],
        )

    def test_every_job_failure_propagates_and_stops_later_jobs(self):
        for index, ((host, command), job) in enumerate(
            zip(EXPECTED_COMMANDS, EXPECTED_JOBS, strict=True)
        ):
            status = 20 + index
            with self.subTest(job=job):
                result, events = self.run_update_remote(
                    fail_host=host, fail_command=command, fail_status=status
                )
                self.assertEqual(
                    result.returncode, status, result.stdout + result.stderr
                )
                expected = [
                    event
                    for host, prior_command in EXPECTED_COMMANDS[:index]
                    for event in (
                        ("start", host, prior_command),
                        ("complete", host, prior_command),
                    )
                ]
                expected.append(("start", EXPECTED_COMMANDS[index][0], command))
                self.assertEqual(events, expected)
                self.assertIn(
                    f"update-remote: failed {job} (status {status})", result.stderr
                )


if __name__ == "__main__":
    unittest.main()
