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

WorkerSpecs = tuple[tuple[str, str], ...]


def parse_worker_specs(raw: str) -> WorkerSpecs:
    """Parse and validate the Nix-owned worker roster."""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as error:
        raise AssertionError(f"invalid worker roster JSON: {raw}") from error
    if not isinstance(data, list) or not data:
        raise AssertionError(f"worker roster must be a non-empty list: {data}")

    specs: list[tuple[str, str]] = []
    names: set[str] = set()
    for item in data:
        if not isinstance(item, dict):
            raise AssertionError(f"invalid worker roster entry: {item}")
        lane = item.get("lane")
        name = item.get("name")
        if lane not in {":read", ":write", ":batch"} or not isinstance(name, str):
            raise AssertionError(f"invalid worker roster entry: {item}")
        if name in names:
            raise AssertionError(f"duplicate worker name: {name}")
        names.add(name)
        specs.append((lane, name))
    return tuple(specs)


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
    try:
        completed = subprocess.run(
            [str(launcher), f"--server-id={server_id}"],
            check=False,
            env=env,
            input="\n".join(frames) + "\n",
            text=True,
            capture_output=True,
            timeout=300,
        )
    except subprocess.TimeoutExpired as error:
        stdout = (
            error.stdout.decode(errors="replace")
            if isinstance(error.stdout, bytes)
            else error.stdout
        )
        stderr = (
            error.stderr.decode(errors="replace")
            if isinstance(error.stderr, bytes)
            else error.stderr
        )
        raise AssertionError(
            f"{host}/{server_id} timed out after {error.timeout}s\n"
            f"stdout:\n{stdout or ''}\nstderr:\n{stderr or ''}"
        ) from error
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
    if needle.lower() not in json.dumps(result, sort_keys=True).lower():
        raise AssertionError(f"tool result did not contain {needle!r}: {result}")


def worker_snapshot_expression(worker_specs: WorkerSpecs) -> str:
    """Return Elisp that validates and snapshots every worker lane."""
    worker_expression = r"""
(condition-case err
    (let ((name (format "%s" (daemonp))))
      (with-temp-file (expand-file-name "worker.pid" user-emacs-directory)
        (insert (number-to-string (emacs-pid))))
      (list name
            (emacs-pid)
            user-emacs-directory
            temporary-file-directory
            (getenv "TMPDIR")
            (getenv "TMP")
            (getenv "TEMP")
            (getenv "XDG_CACHE_HOME")
            (if (bound-and-true-p server-use-tcp) "tcp" "local")
            (if (bound-and-true-p server-use-tcp)
                server-auth-dir
              server-socket-dir)
            anvil-server-schema-cache-file
            ;; The wrapper closes the directory-backed lock descriptors.
            ;; Emacs may reuse these numbers for sockets during startup.
            (if (file-directory-p "/dev/fd/8") t :false)
            (if (file-directory-p "/dev/fd/9") t :false)))
  (error (list "snapshot-error" (error-message-string err))))
""".strip()
    specs = " ".join(f"({lane} {json.dumps(name)})" for lane, name in worker_specs)
    return f"""
(progn
  (require 'cl-lib)
  (unless anvil-worker--pool
    (anvil-worker--init-pool))
  (anvil-worker-spawn)
  (cl-labels
      ((all-workers-ready-p
        ()
        (let ((ready t))
          (anvil-worker--map-pool
           (lambda (worker)
             (unless (anvil-worker--worker-alive-p worker)
               (setq ready nil))))
          ready)))
    (let ((deadline (+ (float-time) 30)))
      (while (and (< (float-time) deadline) (not (all-workers-ready-p)))
        (sleep-for 0.1))
      (unless (all-workers-ready-p)
        (error "not every Anvil worker became ready")))
  (json-serialize
   (vconcat
    (mapcar
     (lambda (spec)
       (let ((snapshot
              (with-timeout
                  (10 (error "worker snapshot timed out: %s" (cadr spec)))
                (server-eval-at
                 (cadr spec) (read {json.dumps(worker_expression)})))))
         (unless (equal (car snapshot) (cadr spec))
           (error "worker snapshot mismatch: %S" snapshot))
         (vconcat snapshot)))
     '({specs}))))))
""".strip()


def assert_worker_snapshot(
    response: dict[str, object], host: str, worker_specs: WorkerSpecs
) -> None:
    result = response["result"]
    if not isinstance(result, dict) or result.get("isError") is True:
        raise AssertionError(f"worker snapshot failed: {result}")
    content = result.get("content")
    if not isinstance(content, list) or len(content) != 1:
        raise AssertionError(f"unexpected worker snapshot content: {result}")
    text = content[0].get("text")
    if not isinstance(text, str):
        raise AssertionError(f"worker snapshot text is missing: {result}")
    try:
        snapshots = json.loads(json.loads(text))
    except (TypeError, json.JSONDecodeError) as error:
        raise AssertionError(f"invalid worker snapshot JSON: {text}") from error
    if not isinstance(snapshots, list) or len(snapshots) != len(worker_specs):
        raise AssertionError(f"unexpected worker snapshots: {snapshots}")

    state_root = Path(os.environ["ANVIL_EMACS_STATE_ROOT"]) / host / "workers"
    runtime_root = Path(os.environ["ANVIL_EMACS_RUNTIME_ROOT"]) / host / "workers"
    socket_root = Path(os.environ["ANVIL_EMACS_RUNTIME_ROOT"]) / host / "emacs"
    for snapshot, (_, name) in zip(snapshots, worker_specs, strict=True):
        if not isinstance(snapshot, list) or len(snapshot) != 13:
            raise AssertionError(f"malformed {name} snapshot: {snapshot}")
        if snapshot[0] != name:
            raise AssertionError(f"worker dispatch mismatch: {snapshot[0]} != {name}")
        if not isinstance(snapshot[1], int) or snapshot[1] <= 0:
            raise AssertionError(f"invalid {name} PID: {snapshot[1]}")
        state_dir = state_root / name
        temp_dir = runtime_root / name / "tmp"
        expected_paths = [
            state_dir,
            temp_dir,
            temp_dir,
            temp_dir,
            temp_dir,
            state_dir / "cache",
        ]
        actual_paths = snapshot[2:8]
        if not all(isinstance(path, str) for path in actual_paths):
            raise AssertionError(f"{name} returned non-path state: {snapshot}")
        if [Path(path) for path in actual_paths] != expected_paths:
            raise AssertionError(
                f"{name} escaped host-local isolation:\n"
                f"actual={actual_paths}\nexpected={expected_paths}"
            )
        transport = snapshot[8]
        server_dir = snapshot[9]
        if transport == "local":
            expected_server_dir = socket_root
        elif transport == "tcp":
            expected_server_dir = state_dir / "server"
        else:
            raise AssertionError(f"unknown {name} server transport: {transport}")
        if not isinstance(server_dir, str) or Path(server_dir) != expected_server_dir:
            raise AssertionError(
                f"{name} server path escaped isolation: "
                f"{server_dir} != {expected_server_dir}"
            )
        expected_schema = temp_dir / "anvil-schema-cache.el"
        if not isinstance(snapshot[10], str) or Path(snapshot[10]) != expected_schema:
            raise AssertionError(
                f"{name} schema cache escaped isolation: "
                f"{snapshot[10]} != {expected_schema}"
            )
        if snapshot[11:] != [False, False]:
            raise AssertionError(
                f"{name} inherited daemon lock descriptors: {snapshot[11:]}"
            )


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(
            "usage: headless-smoke.py /path/to/anvil-mcp WORKER_SPECS_JSON"
        )

    launcher = Path(sys.argv[1]).resolve()
    worker_specs = parse_worker_specs(sys.argv[2])
    org_root = Path.home() / "org"
    org_file = org_root / "smoke.org"
    initialize = {
        "protocolVersion": "2025-03-26",
        "capabilities": {},
        "clientInfo": {"name": "nix-headless-smoke", "version": "1"},
    }
    snapshot_expression = worker_snapshot_expression(worker_specs)

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
                    "arguments": {"expression": snapshot_expression},
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
    assert_tool_success(response_by_id(main_responses, 4), "server_id=anvil")
    assert_tool_success(response_by_id(main_responses, 5), "headlessorgneedle")
    response_by_id(main_responses, 6)
    assert_tool_success(response_by_id(main_responses, 7), "headlesssemanticneedle")
    assert_worker_snapshot(response_by_id(main_responses, 8), "host-a", worker_specs)

    secondary_responses = run_transcript(
        launcher,
        "host-b",
        "anvil",
        [
            request(21, "initialize", initialize),
            request(None, "notifications/initialized"),
            request(
                22,
                "tools/call",
                {
                    "name": "emacs-eval",
                    "arguments": {"expression": snapshot_expression},
                },
            ),
        ],
    )
    assert_worker_snapshot(
        response_by_id(secondary_responses, 22), "host-b", worker_specs
    )

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
    assert_tool_success(response_by_id(typed_responses, 13), "server_id=anvil")
    print(
        "PASS: two isolated daemons, "
        f"{len(main_names)} unified tools, {len(typed_names)} typed tools"
    )


if __name__ == "__main__":
    main()
