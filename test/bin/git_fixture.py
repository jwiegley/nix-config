"""Hermetic Git subprocess helpers for integration tests."""

import os
import subprocess


_GIT_SELECTOR_VARIABLES = (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_PREFIX",
    "GIT_CONFIG",
    "GIT_CONFIG_GLOBAL",
    "GIT_CONFIG_SYSTEM",
    "GIT_CONFIG_COUNT",
    "GIT_INTERNAL_SUPER_PREFIX",
    "GIT_CEILING_DIRECTORIES",
)

_COMMIT_ENVIRONMENT = {
    "GIT_AUTHOR_NAME": "Test",
    "GIT_AUTHOR_EMAIL": "test@example.invalid",
    "GIT_COMMITTER_NAME": "Test",
    "GIT_COMMITTER_EMAIL": "test@example.invalid",
    "GIT_AUTHOR_DATE": "2026-01-01T00:00:00+0000",
    "GIT_COMMITTER_DATE": "2026-01-01T00:00:00+0000",
}


def clean_env(**extra):
    """Return the process environment without repository selectors."""
    env = dict(os.environ)
    for variable in _GIT_SELECTOR_VARIABLES:
        env.pop(variable, None)
    env.update(extra)
    return env


def git(*args, cwd, check=True, env=None):
    """Run Git with deterministic fixture identity."""
    command_env = clean_env(**_COMMIT_ENVIRONMENT)
    if env:
        command_env.update(env)
    result = subprocess.run(
        ["git", *args], cwd=cwd, capture_output=True, text=True, env=command_env
    )
    if check and result.returncode != 0:
        raise AssertionError(
            "git %s failed in %s:\n%s\n%s"
            % (" ".join(args), cwd, result.stdout, result.stderr)
        )
    return result
