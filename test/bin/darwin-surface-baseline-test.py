#!/usr/bin/env python3
"""Unit tests for deterministic Darwin baseline generation."""

from __future__ import annotations

import contextlib
import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
import signal
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest import mock


REPO = Path(__file__).resolve().parents[2]
TOOL = REPO / "test" / "bin" / "darwin-surface-baseline"
REVISION_A = "1" * 40
REVISION_B = "2" * 40
PROJECTION_PATHS = (
    "test/darwin/darwin-surface.nix",
    "test/darwin/surface-helpers.nix",
    "test/bin/darwin-surface-diff",
)


def load_tool():
    """Load the extensionless CLI without executing its main entry point."""
    loader = importlib.machinery.SourceFileLoader(
        "darwin_surface_baseline_under_test", str(TOOL)
    )
    spec = importlib.util.spec_from_loader(loader.name, loader)
    if spec is None:
        raise AssertionError(f"could not construct a module spec for {TOOL}")
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


GENERATOR = load_tool()


def host_surface(number: float = 1.25) -> dict[str, object]:
    """Return a small but structurally complete projector result."""
    return {
        "environment": {},
        "homebrew": {},
        "launchd": {},
        "nix": {},
        "services": {},
        "system": {"fractional": number},
        "users": {},
    }


def hosts(number: float = 1.25) -> dict[str, dict[str, object]]:
    """Return complete host data accepted by the generator schema."""
    return {host: host_surface(number) for host in GENERATOR.HOSTS}


def projection() -> dict[str, str]:
    """Return a structurally valid detached-tool identity."""
    return {
        relative: hashlib.sha256(relative.encode()).hexdigest()
        for relative in PROJECTION_PATHS
    }


class TemporaryBaselineTestCase(unittest.TestCase):
    """Provide an isolated baseline directory and current projector file."""

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory(
            prefix="darwin-surface-baseline-test-"
        )
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.baseline_directory = self.root / "baseline"
        self.baseline_directory.mkdir()

        baseline_patch = mock.patch.object(
            GENERATOR, "BASELINE_DIRECTORY", self.baseline_directory
        )
        baseline_patch.start()
        self.addCleanup(baseline_patch.stop)

    def write_baseline(
        self,
        revision: str = REVISION_A,
        *,
        schema: str | None = None,
    ) -> tuple[Path, dict[str, object]]:
        """Install one valid baseline, optionally corrupting its schema."""
        value = GENERATOR.artifact(revision, hosts(), projection())
        if schema is not None:
            value["schema"] = schema
        path = self.baseline_directory / f"darwin-surface-{revision[:12]}.json"
        path.write_text(GENERATOR.encode(value), encoding="utf-8")
        return path, value


class MainModeTests(TemporaryBaselineTestCase):
    def test_default_and_explicit_print_are_non_mutating(self) -> None:
        sentinel = self.baseline_directory / "sentinel"
        sentinel.write_bytes(b"unchanged\n")
        before = {
            path.name: path.read_bytes() for path in self.baseline_directory.iterdir()
        }
        expected_hosts = {
            "clio": host_surface(3.5),
            "hera": host_surface(4.5),
        }

        for print_flag in ([], ["--print"]):
            with self.subTest(print_flag=print_flag):
                stdout = io.StringIO()
                stderr = io.StringIO()
                with (
                    mock.patch.object(
                        GENERATOR, "resolve_revision", return_value=REVISION_A
                    ) as resolve,
                    mock.patch.object(
                        GENERATOR,
                        "derive_hosts",
                        return_value=(expected_hosts, projection()),
                    ) as derive,
                    mock.patch.object(GENERATOR, "write_artifact") as write,
                    contextlib.redirect_stdout(stdout),
                    contextlib.redirect_stderr(stderr),
                ):
                    status = GENERATOR.main(["--rev", "exact", *print_flag])

                self.assertEqual(status, 0, stderr.getvalue())
                resolve.assert_called_once_with("exact")
                derive.assert_called_once_with(REVISION_A)
                write.assert_not_called()
                value = json.loads(stdout.getvalue())
                self.assertEqual(value["schema"], "darwin-value-surface/3")
                self.assertEqual(value["baselineRev"], REVISION_A)
                self.assertEqual(value["projection"], projection())
                self.assertEqual(value["hosts"], expected_hosts)
                self.assertIsInstance(
                    value["hosts"]["clio"]["system"]["fractional"], float
                )
                after = {
                    path.name: path.read_bytes()
                    for path in self.baseline_directory.iterdir()
                }
                self.assertEqual(after, before)

    def test_operational_invalid_revision_is_nonzero(self) -> None:
        stderr = io.StringIO()
        malformed = subprocess.CompletedProcess(
            ["git", "rev-parse"], 0, "not-a-full-revision\n", ""
        )
        with (
            mock.patch.object(GENERATOR, "run", return_value=malformed),
            mock.patch.object(GENERATOR, "derive_hosts") as derive,
            contextlib.redirect_stderr(stderr),
        ):
            status = GENERATOR.main(["--rev", "missing", "--print"])

        self.assertEqual(status, 2)
        self.assertIn("invalid full revision", stderr.getvalue())
        derive.assert_not_called()

    def test_revision_resolution_rejects_git_failure(self) -> None:
        failed = subprocess.CompletedProcess(
            ["git", "rev-parse"], 128, "", "unknown revision"
        )
        with (
            mock.patch.object(GENERATOR.subprocess, "run", return_value=failed),
            self.assertRaisesRegex(GENERATOR.OperationalError, "unknown revision"),
        ):
            GENERATOR.resolve_revision("missing")

    def test_sigterm_request_has_conventional_nonzero_exit(self) -> None:
        stderr = io.StringIO()
        with (
            mock.patch.object(
                GENERATOR,
                "execute",
                side_effect=GENERATOR.TerminationRequested(signal.SIGTERM),
            ),
            contextlib.redirect_stderr(stderr),
        ):
            status = GENERATOR.main(["--print"])

        self.assertEqual(status, 128 + signal.SIGTERM)
        self.assertIn(f"terminated by signal {signal.SIGTERM}", stderr.getvalue())


class EvaluationTests(unittest.TestCase):
    def test_evaluate_host_uses_only_worktree_tools_and_preserves_float(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="darwin-surface-evaluate-test-"
        ) as temporary_directory:
            worktree = Path(temporary_directory) / "source"
            projector = worktree / "test" / "darwin" / "darwin-surface.nix"
            differ = worktree / "test" / "bin" / "darwin-surface-diff"
            helper = worktree / "test" / "darwin" / "surface-helpers.nix"
            projector.parent.mkdir(parents=True)
            differ.parent.mkdir(parents=True)
            projector.write_text("darwin: {}\n", encoding="utf-8")
            helper.write_text("{}\n", encoding="utf-8")
            differ.write_text(
                "def normalize_store(value): return value\n", encoding="utf-8"
            )
            projected = host_surface(7.125)
            completed = subprocess.CompletedProcess(
                args=["nix"], returncode=0, stdout=json.dumps(projected), stderr=""
            )

            with (
                mock.patch.object(GENERATOR, "run", return_value=completed) as run,
                mock.patch.object(
                    GENERATOR,
                    "store_normalizer",
                    return_value=lambda value: {
                        **value,
                        "system": {
                            **value["system"],
                            "fractional": value["system"]["fractional"] + 0.5,
                        },
                    },
                ) as normalizer,
            ):
                result = GENERATOR.evaluate_host(worktree, "clio")

        command = run.call_args.args[0]
        self.assertEqual(run.call_args.kwargs["cwd"], worktree)
        apply_expression = command[command.index("--apply") + 1]
        self.assertIn(str(projector), apply_expression)
        self.assertNotIn(str(REPO / "test" / "darwin"), apply_expression)
        normalizer.assert_called_once_with(differ)
        self.assertIsInstance(result["system"]["fractional"], float)
        self.assertEqual(result["system"]["fractional"], 7.625)

    def test_projection_identity_hashes_exact_detached_paths(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="darwin-surface-projection-test-"
        ) as temporary_directory:
            worktree = Path(temporary_directory) / "source"
            contents = {
                "test/darwin/darwin-surface.nix": b"darwin: { value = 1; }\n",
                "test/darwin/surface-helpers.nix": b"{ helper = true; }\n",
                "test/bin/darwin-surface-diff": b"def normalize_store(value): return value\n",
            }
            for relative, content in contents.items():
                path = worktree / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)

            identity = GENERATOR.projection_identity(worktree)

        self.assertEqual(set(identity), set(PROJECTION_PATHS))
        self.assertEqual(
            identity,
            {
                relative: hashlib.sha256(content).hexdigest()
                for relative, content in contents.items()
            },
        )
        for digest in identity.values():
            self.assertRegex(digest, r"^[0-9a-f]{64}$")

    def test_loading_differ_normalizer_is_silent_and_does_not_run_cli(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="darwin-surface-normalizer-test-"
        ) as temporary_directory:
            differ = Path(temporary_directory) / "darwin-surface-diff"
            differ.write_text(
                textwrap.dedent(
                    """\
                    def normalize_store(value):
                        return {"wrapped": value}

                    if __name__ == "__main__":
                        print("CLI RAN")
                        raise SystemExit(91)
                    """
                ),
                encoding="utf-8",
            )
            stdout = io.StringIO()
            stderr = io.StringIO()
            with (
                contextlib.redirect_stdout(stdout),
                contextlib.redirect_stderr(stderr),
            ):
                normalizer = GENERATOR.store_normalizer(differ)
                result = normalizer(2.5)

        self.assertEqual(result, {"wrapped": 2.5})
        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(stderr.getvalue(), "")


class ExistingBaselineValidationTests(TemporaryBaselineTestCase):
    def test_rejects_zero_candidates(self) -> None:
        with self.assertRaisesRegex(GENERATOR.OperationalError, "exactly one existing"):
            GENERATOR.validate_existing_baseline()

    def test_rejects_multiple_candidates(self) -> None:
        self.write_baseline(REVISION_A)
        self.write_baseline(REVISION_B)
        with self.assertRaisesRegex(GENERATOR.OperationalError, "exactly one existing"):
            GENERATOR.validate_existing_baseline()

    def test_rejects_bad_schema(self) -> None:
        self.write_baseline(schema="darwin-value-surface/999")
        with self.assertRaisesRegex(GENERATOR.OperationalError, "has schema"):
            GENERATOR.validate_existing_baseline()

    def test_write_rejects_missing_baseline_before_derivation(self) -> None:
        stderr = io.StringIO()

        @contextlib.contextmanager
        def write_lock():
            yield

        with (
            mock.patch.object(GENERATOR, "resolve_revision", return_value=REVISION_A),
            mock.patch.object(
                GENERATOR, "baseline_write_lock", return_value=write_lock()
            ),
            mock.patch.object(GENERATOR, "recover_interrupted_write"),
            mock.patch.object(GENERATOR, "derive_hosts") as derive,
            mock.patch.object(GENERATOR, "write_artifact") as write,
            contextlib.redirect_stderr(stderr),
        ):
            status = GENERATOR.main(["--write"])

        self.assertEqual(status, 2)
        self.assertIn("exactly one existing", stderr.getvalue())
        derive.assert_not_called()
        write.assert_not_called()

    def test_projection_validation_rejects_key_and_digest_drift(self) -> None:
        mutations = (
            {**projection(), "extra": "a" * 64},
            {key: value for key, value in projection().items() if key != PROJECTION_PATHS[0]},
            {**projection(), PROJECTION_PATHS[0]: "A" * 64},
            {**projection(), PROJECTION_PATHS[0]: "a" * 63},
            {**projection(), PROJECTION_PATHS[0]: 7},
        )
        for value in mutations:
            with self.subTest(value=value), self.assertRaises(
                GENERATOR.OperationalError
            ):
                GENERATOR.validate_projection(value)


class SensitiveDataTests(unittest.TestCase):
    def test_rejects_sensitive_shapes_but_allows_null_password_toggle(self) -> None:
        for value in (
            {"apiToken": "redacted"},
            {"arguments": ["--credential=value"]},
            {"askForPassword": True},
        ):
            with (
                self.subTest(value=value),
                self.assertRaisesRegex(GENERATOR.OperationalError, "persist"),
            ):
                GENERATOR.reject_sensitive_data(value)

        GENERATOR.reject_sensitive_data(
            {"askForPassword": None, "askForPasswordDelay": None}
        )


class ArtifactReplacementTests(TemporaryBaselineTestCase):
    def test_write_execution_holds_lock_across_recovery_and_replacement(self) -> None:
        existing, _ = self.write_baseline(REVISION_A)
        events = []

        @contextlib.contextmanager
        def write_lock():
            events.append("lock-enter")
            yield
            events.append("lock-exit")

        def record(name, value=None):
            events.append(name)
            return value

        args = GENERATOR.parser().parse_args(["--rev", "exact", "--write"])
        with (
            mock.patch.object(GENERATOR, "REPOSITORY", self.root),
            mock.patch.object(GENERATOR, "resolve_revision", return_value=REVISION_A),
            mock.patch.object(
                GENERATOR, "baseline_write_lock", return_value=write_lock()
            ),
            mock.patch.object(
                GENERATOR,
                "recover_interrupted_write",
                side_effect=lambda: record("recover"),
            ),
            mock.patch.object(
                GENERATOR,
                "validate_existing_baseline",
                side_effect=lambda: record("validate", existing),
            ),
            mock.patch.object(
                GENERATOR,
                "derive_hosts",
                side_effect=lambda _revision: record("derive", (hosts(), projection())),
            ),
            mock.patch.object(
                GENERATOR,
                "write_artifact",
                side_effect=lambda _existing, _value: record("write", existing),
            ),
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            GENERATOR.execute(args)

        self.assertEqual(
            events,
            ["lock-enter", "recover", "validate", "derive", "write", "lock-exit"],
        )

    def test_same_revision_atomically_replaces_same_name(self) -> None:
        existing, before = self.write_baseline(REVISION_A)
        replacement = GENERATOR.artifact(REVISION_A, hosts(9.75), projection())

        with mock.patch.object(GENERATOR.os, "replace", wraps=os.replace) as replace:
            destination = GENERATOR.write_artifact(existing, replacement)

        self.assertEqual(destination, existing)
        self.assertEqual(json.loads(existing.read_text(encoding="utf-8")), replacement)
        self.assertNotEqual(before, replacement)
        self.assertEqual(
            list(self.baseline_directory.glob("darwin-surface-*.json")), [existing]
        )
        self.assertEqual(list(self.baseline_directory.iterdir()), [existing])
        replace.assert_called_once()
        temporary_path, installed_path = replace.call_args.args
        self.assertEqual(installed_path, existing)
        self.assertEqual(temporary_path.parent, existing.parent)
        self.assertTrue(temporary_path.name.startswith(f".{existing.name}."))

    def test_same_revision_replace_failure_preserves_original_bytes(self) -> None:
        existing, _ = self.write_baseline(REVISION_A)
        original = existing.read_bytes()
        replacement = GENERATOR.artifact(REVISION_A, hosts(8.25), projection())

        with (
            mock.patch.object(
                GENERATOR.os, "replace", side_effect=OSError("injected replace failure")
            ),
            self.assertRaisesRegex(GENERATOR.OperationalError, "atomically write"),
        ):
            GENERATOR.write_artifact(existing, replacement)

        self.assertEqual(existing.read_bytes(), original)
        self.assertEqual(list(self.baseline_directory.iterdir()), [existing])

    def test_recovery_restores_hidden_backup_when_no_candidate_exists(self) -> None:
        value = GENERATOR.artifact(REVISION_A, hosts(), projection())
        backup = GENERATOR.baseline_backup_path()
        backup.write_text(GENERATOR.encode(value), encoding="utf-8")
        restored = self.baseline_directory / f"darwin-surface-{REVISION_A[:12]}.json"

        with contextlib.redirect_stderr(io.StringIO()):
            GENERATOR.recover_interrupted_write()

        self.assertFalse(backup.exists())
        self.assertEqual(json.loads(restored.read_text()), value)
        self.assertEqual(list(self.baseline_directory.iterdir()), [restored])

    def test_revision_change_leaves_exactly_one_candidate(self) -> None:
        existing, _ = self.write_baseline(REVISION_A)
        replacement = GENERATOR.artifact(REVISION_B, hosts(4.5), projection())
        expected_destination = (
            self.baseline_directory / f"darwin-surface-{REVISION_B[:12]}.json"
        )
        backup = GENERATOR.baseline_backup_path()
        observed_install_state = []
        real_atomic_write = GENERATOR.atomic_write

        def inspect_transition(path: Path, contents: str) -> None:
            observed_install_state.append(
                (existing.exists(), backup.exists(), expected_destination.exists())
            )
            real_atomic_write(path, contents)

        with mock.patch.object(
            GENERATOR, "atomic_write", side_effect=inspect_transition
        ):
            destination = GENERATOR.write_artifact(existing, replacement)

        self.assertEqual(observed_install_state, [(False, True, False)])
        self.assertFalse(existing.exists())
        self.assertEqual(destination.name, f"darwin-surface-{REVISION_B[:12]}.json")
        self.assertEqual(json.loads(destination.read_text()), replacement)
        self.assertEqual(
            list(self.baseline_directory.glob("darwin-surface-*.json")),
            [destination],
        )
        self.assertEqual(list(self.baseline_directory.iterdir()), [destination])

    def test_revision_change_rolls_back_after_partial_write_failure(self) -> None:
        existing, original = self.write_baseline(REVISION_A)
        original_bytes = existing.read_bytes()
        replacement = GENERATOR.artifact(REVISION_B, hosts(6.5), projection())
        destination = self.baseline_directory / f"darwin-surface-{REVISION_B[:12]}.json"

        real_atomic_write = GENERATOR.atomic_write

        def fail_after_install(path: Path, contents: str) -> None:
            real_atomic_write(path, contents)
            raise GENERATOR.OperationalError("injected write failure")

        with (
            mock.patch.object(
                GENERATOR, "atomic_write", side_effect=fail_after_install
            ),
            self.assertRaisesRegex(
                GENERATOR.OperationalError, "injected write failure"
            ),
        ):
            GENERATOR.write_artifact(existing, replacement)

        self.assertTrue(existing.is_file())
        self.assertEqual(existing.read_bytes(), original_bytes)
        self.assertEqual(json.loads(existing.read_text()), original)
        self.assertFalse(destination.exists())
        self.assertEqual(
            list(self.baseline_directory.glob("darwin-surface-*.json")), [existing]
        )
        self.assertEqual(list(self.baseline_directory.iterdir()), [existing])


class WorktreeCleanupTests(unittest.TestCase):
    def test_worktree_add_failure_still_attempts_narrow_cleanup(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="darwin-surface-cleanup-test-"
        ) as temporary_directory:
            worktree = Path(temporary_directory) / "source"
            with (
                mock.patch.object(
                    GENERATOR,
                    "run",
                    side_effect=GENERATOR.OperationalError("add failed"),
                ),
                mock.patch.object(
                    GENERATOR, "remove_worktree", return_value=None
                ) as remove,
                self.assertRaisesRegex(GENERATOR.OperationalError, "add failed"),
            ):
                GENERATOR.derive_hosts_in_temporary_directory(
                    REVISION_A, temporary_directory
                )

        remove.assert_called_once_with(worktree)

    def test_cleanup_is_called_after_success(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="darwin-surface-cleanup-test-"
        ) as temporary_directory:
            worktree = Path(temporary_directory) / "source"
            completed = subprocess.CompletedProcess([], 0, "", "")
            with (
                mock.patch.object(GENERATOR, "run", return_value=completed) as run,
                mock.patch.object(
                    GENERATOR,
                    "evaluate_host",
                    side_effect=[host_surface(1.0), host_surface(2.0)],
                ),
                mock.patch.object(
                    GENERATOR, "projection_identity", return_value=projection()
                ),
                mock.patch.object(
                    GENERATOR, "remove_worktree", return_value=None
                ) as remove,
                contextlib.redirect_stderr(io.StringIO()),
            ):
                result = GENERATOR.derive_hosts_in_temporary_directory(
                    REVISION_A, temporary_directory
                )

        derived_hosts, derived_projection = result
        self.assertEqual(set(derived_hosts), set(GENERATOR.HOSTS))
        self.assertEqual(derived_projection, projection())
        remove.assert_called_once_with(worktree)
        run.assert_called_once_with(
            [
                "git",
                "worktree",
                "add",
                "--detach",
                "--quiet",
                str(worktree),
                REVISION_A,
            ],
            cwd=GENERATOR.REPOSITORY,
            description=f"could not create detached worktree at {REVISION_A}",
        )

    def test_primary_and_cleanup_failures_are_paired(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="darwin-surface-cleanup-test-"
        ) as temporary_directory:
            worktree = Path(temporary_directory) / "source"
            completed = subprocess.CompletedProcess([], 0, "", "")
            cleanup_error = GENERATOR.OperationalError("cleanup broke")
            with (
                mock.patch.object(GENERATOR, "run", return_value=completed),
                mock.patch.object(
                    GENERATOR,
                    "evaluate_host",
                    side_effect=GENERATOR.OperationalError("evaluation broke"),
                ),
                mock.patch.object(
                    GENERATOR, "projection_identity", return_value=projection()
                ),
                mock.patch.object(
                    GENERATOR, "remove_worktree", return_value=cleanup_error
                ) as remove,
                self.assertRaises(GENERATOR.OperationalError) as raised,
                contextlib.redirect_stderr(io.StringIO()),
            ):
                GENERATOR.derive_hosts_in_temporary_directory(
                    REVISION_A, temporary_directory
                )

        self.assertIn("evaluation broke", str(raised.exception))
        self.assertIn("cleanup broke", str(raised.exception))
        remove.assert_called_once_with(worktree)

    def test_sigterm_exception_still_unregisters_worktree(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="darwin-surface-cleanup-test-"
        ) as temporary_directory:
            worktree = Path(temporary_directory) / "source"
            completed = subprocess.CompletedProcess([], 0, "", "")
            with (
                mock.patch.object(GENERATOR, "run", return_value=completed),
                mock.patch.object(
                    GENERATOR, "projection_identity", return_value=projection()
                ),
                mock.patch.object(
                    GENERATOR,
                    "evaluate_host",
                    side_effect=GENERATOR.TerminationRequested(signal.SIGTERM),
                ),
                mock.patch.object(
                    GENERATOR, "remove_worktree", return_value=None
                ) as remove,
                contextlib.redirect_stderr(io.StringIO()),
                self.assertRaises(GENERATOR.TerminationRequested),
            ):
                GENERATOR.derive_hosts_in_temporary_directory(
                    REVISION_A, temporary_directory
                )

        remove.assert_called_once_with(worktree)


class EnvironmentIsolationTests(unittest.TestCase):
    def test_git_environment_is_scrubbed_for_required_subprocesses(self) -> None:
        completed = subprocess.CompletedProcess(["git"], 0, "ok\n", "")
        hostile = {
            "GIT_DIR": "/tmp/hostile-git-dir",
            "GIT_WORK_TREE": "/tmp/hostile-work-tree",
            "GIT_COMMON_DIR": "/tmp/hostile-common-dir",
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "core.worktree",
            "GIT_CONFIG_VALUE_0": "/tmp/hostile-config-work-tree",
            "DARWIN_SURFACE_TEST_MARKER": "preserved",
        }
        with (
            mock.patch.dict(os.environ, hostile, clear=False),
            mock.patch.object(
                GENERATOR.subprocess, "run", return_value=completed
            ) as subprocess_run,
        ):
            GENERATOR.run(
                ["git", "rev-parse", "HEAD"],
                cwd=REPO,
                description="test git environment",
            )

        environment = subprocess_run.call_args.kwargs["env"]
        for name in hostile:
            if name.startswith("GIT_"):
                self.assertNotIn(name, environment)
        self.assertEqual(environment["DARWIN_SURFACE_TEST_MARKER"], "preserved")

    def test_git_environment_is_scrubbed_for_worktree_cleanup(self) -> None:
        hostile = {
            name: f"hostile-{name.lower()}"
            for name in GENERATOR.GIT_REPOSITORY_VARIABLES
        }
        hostile.update(
            {
                "GIT_CONFIG_KEY_0": "core.worktree",
                "GIT_CONFIG_VALUE_0": "/tmp/hostile-config-work-tree",
                "GIT_SSH_COMMAND": "transport-command-is-retained",
            }
        )
        failed = subprocess.CompletedProcess(["git"], 1, "", "first removal failed")
        completed = subprocess.CompletedProcess(["git"], 0, "", "")
        with (
            mock.patch.dict(os.environ, hostile, clear=False),
            mock.patch.object(
                GENERATOR.subprocess, "run", side_effect=[failed, completed]
            ) as subprocess_run,
        ):
            result = GENERATOR.remove_worktree(Path("/tmp/source"))

        self.assertIsInstance(result, GENERATOR.OperationalError)
        self.assertIn("removed only with --force", str(result))
        self.assertEqual(subprocess_run.call_count, 2)
        self.assertIn("--force", subprocess_run.call_args_list[1].args[0])
        for call in subprocess_run.call_args_list:
            environment = call.kwargs["env"]
            for name in hostile:
                if name.startswith("GIT_CONFIG_") or name in (
                    GENERATOR.GIT_REPOSITORY_VARIABLES
                ):
                    self.assertNotIn(name, environment)
            self.assertEqual(
                environment["GIT_SSH_COMMAND"], "transport-command-is-retained"
            )


if __name__ == "__main__":
    unittest.main()
