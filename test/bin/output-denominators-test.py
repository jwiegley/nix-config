#!/usr/bin/env python3
"""Unit tests for the manifest-versus-live output denominator gate."""

from __future__ import annotations

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO = Path(__file__).resolve().parents[2]
TOOL = REPO / "test" / "bin" / "output-denominators"
SYSTEMS = ("aarch64-darwin", "aarch64-linux", "x86_64-linux")


def load_tool():
    """Load the extensionless CLI without executing its main entry point."""
    loader = importlib.machinery.SourceFileLoader(
        "output_denominators_under_test", str(TOOL)
    )
    spec = importlib.util.spec_from_loader(loader.name, loader)
    if spec is None:
        raise AssertionError(f"could not construct a module spec for {TOOL}")
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


GATE = load_tool()


def manifest(checks=("alpha",), packages=("beta",), overlays=("default",)):
    """Build a manifest declaring one denominator per output kind."""
    return {
        "gateDenominator": {
            "topLevelChecks": [
                {"system": system, "id": identifier}
                for system in SYSTEMS
                for identifier in checks
            ]
        },
        "outputApplicability": {
            "outputKinds": [
                {
                    "kind": "packages",
                    "systems": list(SYSTEMS),
                    "commonAttrs": list(packages),
                    "systemAdditions": {},
                },
                {"kind": "overlays", "systems": [], "expectedAttrs": list(overlays)},
            ]
        },
    }


class DenominatorGateTests(unittest.TestCase):
    def run_gate(self, document, live):
        """Run main() against a manifest, with flake evaluation stubbed."""
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        (root / "test" / "coverage").mkdir(parents=True)
        (root / "test" / "coverage" / "manifest.json").write_text(
            json.dumps(document), encoding="utf-8"
        )
        previous = Path.cwd()
        os.chdir(root)
        self.addCleanup(os.chdir, previous)

        def evaluate(target, _apply_expression):
            return live[target]

        stderr = io.StringIO()
        stdout = io.StringIO()
        with mock.patch.object(GATE, "evaluate", evaluate):
            with contextlib.redirect_stderr(stderr):
                with contextlib.redirect_stdout(stdout):
                    status = GATE.main()
        return status, stdout.getvalue() + stderr.getvalue()

    def live(self, checks=("alpha",), packages=("beta",), overlays=("default",)):
        return {
            ".#checks": {system: list(checks) for system in SYSTEMS},
            ".#packages": {system: list(packages) for system in SYSTEMS},
            ".#overlays": list(overlays),
        }

    def test_matching_denominators_pass(self):
        status, output = self.run_gate(manifest(), self.live())
        self.assertEqual(status, 0)
        self.assertIn("match live flake output", output)

    def test_unregistered_check_fails(self):
        status, output = self.run_gate(
            manifest(), self.live(checks=("alpha", "surprise"))
        )
        self.assertEqual(status, 1)
        self.assertIn(".#checks.aarch64-darwin publishes unregistered surprise", output)

    def test_unregistered_package_fails_for_every_system(self):
        status, output = self.run_gate(manifest(), self.live(packages=("beta", "extra")))
        self.assertEqual(status, 1)
        for system in SYSTEMS:
            self.assertIn(f".#packages.{system} publishes unregistered extra", output)

    def test_unregistered_overlay_fails(self):
        status, output = self.run_gate(
            manifest(), self.live(overlays=("default", "tools"))
        )
        self.assertEqual(status, 1)
        self.assertIn(".#overlays publishes unregistered tools", output)

    def test_declared_but_absent_output_fails(self):
        status, output = self.run_gate(manifest(packages=("beta", "retired")), self.live())
        self.assertEqual(status, 1)
        self.assertIn("declares absent retired", output)

    def test_failure_names_the_repair_including_the_artifact(self):
        # The manifest and the artifact are paired by digest, so repairing one
        # without the other trades this failure for a digest mismatch that only
        # the expensive tier reports.
        _, output = self.run_gate(manifest(), self.live(checks=("alpha", "surprise")))
        self.assertIn("regenerate the artifact", output)
        self.assertIn("manifestDigest", output)

    def test_evaluation_failure_is_refused_without_echoing_values(self):
        completed = subprocess.CompletedProcess(
            ["nix"], 1, stdout="", stderr="secret evaluated value"
        )
        with mock.patch.object(GATE.subprocess, "run", return_value=completed):
            with self.assertRaises(SystemExit) as raised:
                GATE.evaluate(".#checks", "builtins.attrNames")
        self.assertIn("cannot evaluate .#checks", str(raised.exception))
        self.assertNotIn("secret evaluated value", str(raised.exception))

    def test_evaluation_timeout_is_refused(self):
        with mock.patch.object(
            GATE.subprocess,
            "run",
            side_effect=subprocess.TimeoutExpired(["nix"], GATE.EVAL_TIMEOUT_SECONDS),
        ):
            with self.assertRaises(SystemExit) as raised:
                GATE.evaluate(".#checks", "builtins.attrNames")
        self.assertIn("exceeded", str(raised.exception))

    def test_single_evaluation_covers_every_system(self):
        # One evaluation per output kind, not one per system: the per-system
        # cost is what would push this out of a routine tier.
        targets = []

        def evaluate(target, _apply_expression):
            targets.append(target)
            return self.live()[target]

        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        (root / "test" / "coverage").mkdir(parents=True)
        (root / "test" / "coverage" / "manifest.json").write_text(
            json.dumps(manifest()), encoding="utf-8"
        )
        previous = Path.cwd()
        os.chdir(root)
        self.addCleanup(os.chdir, previous)
        with mock.patch.object(GATE, "evaluate", evaluate):
            with contextlib.redirect_stdout(io.StringIO()):
                GATE.main()
        self.assertEqual(sorted(targets), [".#checks", ".#overlays", ".#packages"])


if __name__ == "__main__":
    unittest.main()
