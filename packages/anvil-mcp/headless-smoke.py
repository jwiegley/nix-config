#!/usr/bin/env python3
"""Exercise both registries of the dedicated Anvil Emacs daemon."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys

MAIN_ONLY_TOOLS = {
    "diagnostics",
    "emacs-eval",
    "emacs-eval-async",
    "emacs-eval-jobs",
    "emacs-eval-result",
    "imenu_list_symbols",
    "nelisp-eval",
    "nelisp-eval-reset",
    "project_info",
    "treesit_info",
    "xref_find_apropos",
    "xref_find_references",
}

TYPED_TOOLS = {
    "anvil-worker-probe",
    "anvil-worker-reset-pool",
    "code-add-field-by-map",
    "code-extract-pattern",
    "context-compress",
    "context-retrieve",
    "context-stats",
    "cron-list",
    "cron-run",
    "cron-status",
    "data-delete-path",
    "data-get-path",
    "data-list-keys",
    "data-set-path",
    "elisp-byte-compile-file",
    "elisp-describe-function",
    "elisp-describe-variable",
    "elisp-ert-run",
    "elisp-get-function-definition",
    "elisp-read-source-file",
    "ert-run-distilled",
    "file-append",
    "file-batch",
    "file-batch-across",
    "file-create",
    "file-delete-lines",
    "file-ensure-import",
    "file-insert-at-line",
    "file-outline",
    "file-read",
    "file-read-delta",
    "file-replace-regexp",
    "file-replace-string",
    "git-branch-current",
    "git-diff-names",
    "git-diff-stats",
    "git-head-sha",
    "git-log",
    "git-repo-root",
    "git-status",
    "git-worktree-list",
    "json-object-add",
    "metrics-token-report",
    "notes-lexical-search",
    "org-add-todo",
    "org-agenda-view",
    "org-capture-string",
    "org-edit-body",
    "org-get-allowed-files",
    "org-get-tag-config",
    "org-get-todo-config",
    "org-habit-summary",
    "org-read-by-id",
    "org-read-file",
    "org-read-headline",
    "org-read-outline",
    "org-rename-headline",
    "org-update-todo-state",
    "semantic-embed-index",
    "semantic-reindex",
    "semantic-search",
    "semantic-status",
    "shell-filter",
    "shell-gain",
    "shell-run",
    "shell-tee-get",
    "shell-tee-grep",
    "sexp-macroexpand",
    "sexp-read-file",
    "sexp-rename-symbol",
    "sexp-replace-call",
    "sexp-replace-defun",
    "sexp-surrounding-form",
    "sexp-verify",
    "sexp-wrap-form",
    "sqlite-query",
}


def request(identifier: int | None, method: str, params: object | None = None) -> str:
    frame: dict[str, object] = {"jsonrpc": "2.0", "method": method}
    if identifier is not None:
        frame["id"] = identifier
    if params is not None:
        frame["params"] = params
    return json.dumps(frame, separators=(",", ":"))


def run_transcript(
    launcher: Path, host: str, server_id: str, frames: list[str]
) -> list[dict[str, object]]:
    env = os.environ.copy()
    env["ANVIL_EMACS_HOST"] = host
    completed = subprocess.run(
        [str(launcher), f"--server-id={server_id}"],
        check=False,
        env=env,
        input="\n".join(frames) + "\n",
        text=True,
        capture_output=True,
        timeout=60,
    )
    if completed.returncode != 0:
        raise AssertionError(
            f"{host}/{server_id} exited {completed.returncode}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    return [json.loads(line) for line in completed.stdout.splitlines() if line.strip()]


def response_by_id(
    responses: list[dict[str, object]], identifier: int
) -> dict[str, object]:
    matches = [response for response in responses if response.get("id") == identifier]
    if len(matches) != 1:
        raise AssertionError(
            f"expected one response for id {identifier}, found {len(matches)}"
        )
    response = matches[0]
    if "error" in response:
        raise AssertionError(f"request {identifier} failed: {response['error']}")
    return response


def tool_names(response: dict[str, object]) -> set[str]:
    result = response["result"]
    assert isinstance(result, dict)
    tools = result["tools"]
    assert isinstance(tools, list)
    names = [tool["name"] for tool in tools]
    if len(names) != len(set(names)):
        raise AssertionError(f"duplicate tools returned: {names}")
    return set(names)


def assert_tool_success(response: dict[str, object], needle: str) -> None:
    result = response["result"]
    if isinstance(result, dict) and result.get("isError") is True:
        raise AssertionError(f"tool call reported an error: {result}")
    if needle not in json.dumps(result, sort_keys=True).lower():
        raise AssertionError(f"tool result did not contain {needle!r}: {result}")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: headless-smoke.py /path/to/anvil-mcp")

    launcher = Path(sys.argv[1]).resolve()
    org_root = Path.home() / "org"
    org_file = org_root / "smoke.org"
    initialize = {
        "protocolVersion": "2025-03-26",
        "capabilities": {},
        "clientInfo": {"name": "nix-headless-smoke", "version": "1"},
    }

    main_responses = run_transcript(
        launcher,
        "host-a",
        "anvil",
        [
            request(1, "initialize", initialize),
            request(None, "notifications/initialized"),
            request(2, "tools/list"),
            request(
                3,
                "tools/call",
                {"name": "emacs-eval", "arguments": {"expression": "(+ 20 22)"}},
            ),
            request(
                4,
                "tools/call",
                {
                    "name": "file-read",
                    "arguments": {"path": str(launcher)},
                },
            ),
            request(
                5,
                "tools/call",
                {
                    "name": "org-read-file",
                    "arguments": {"file": str(org_file)},
                },
            ),
            request(
                6,
                "tools/call",
                {
                    "name": "semantic-reindex",
                    "arguments": {"root": str(org_root)},
                },
            ),
            request(
                7,
                "tools/call",
                {
                    "name": "semantic-search",
                    "arguments": {
                        "query": "headlesssemanticneedle",
                        "mode": "lexical",
                        "root": str(org_root),
                    },
                },
            ),
            request(
                8,
                "tools/call",
                {
                    "name": "emacs-eval",
                    "arguments": {
                        "expression": (
                            r"(let ((deadline (+ (float-time) 30))) "
                            r"(while (and (< (float-time) deadline) "
                            r"(not (anvil-worker-alive-p 0 :read))) "
                            r"(sleep-for 0.1)) "
                            r"(unless (anvil-worker-alive-p 0 :read) "
                            r'(error "read worker did not become ready")) '
                            r'(anvil-worker-call "(list (getenv \"TMPDIR\") '
                            r'(getenv \"XDG_CACHE_HOME\"))" '
                            r":kind :read :timeout 30))"
                        )
                    },
                },
            ),
        ],
    )
    main_names = tool_names(response_by_id(main_responses, 2))
    if main_names != MAIN_ONLY_TOOLS | TYPED_TOOLS:
        raise AssertionError(
            "unexpected unified main surface: "
            f"missing={sorted((MAIN_ONLY_TOOLS | TYPED_TOOLS) - main_names)}, "
            f"unexpected={sorted(main_names - (MAIN_ONLY_TOOLS | TYPED_TOOLS))}"
        )
    assert_tool_success(response_by_id(main_responses, 3), "42")
    assert_tool_success(response_by_id(main_responses, 4), "content")
    assert_tool_success(response_by_id(main_responses, 5), "headlessorgneedle")
    response_by_id(main_responses, 6)
    assert_tool_success(response_by_id(main_responses, 7), "headlesssemanticneedle")
    assert_tool_success(response_by_id(main_responses, 8), "workers/anvil-worker-read-")

    typed_responses = run_transcript(
        launcher,
        "host-b",
        "emacs-eval",
        [
            request(11, "initialize", initialize),
            request(None, "notifications/initialized"),
            request(12, "tools/list"),
            request(
                13,
                "tools/call",
                {
                    "name": "file-read",
                    "arguments": {"path": str(launcher)},
                },
            ),
        ],
    )
    typed_names = tool_names(response_by_id(typed_responses, 12))
    if typed_names != TYPED_TOOLS:
        raise AssertionError(
            "unexpected typed surface: "
            f"missing={sorted(TYPED_TOOLS - typed_names)}, "
            f"unexpected={sorted(typed_names - TYPED_TOOLS)}"
        )
    assert_tool_success(response_by_id(typed_responses, 13), "content")
    print(
        "PASS: two isolated daemons, "
        f"{len(main_names)} unified tools, {len(typed_names)} typed tools"
    )


if __name__ == "__main__":
    main()
