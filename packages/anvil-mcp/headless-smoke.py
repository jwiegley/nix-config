#!/usr/bin/env python3
"""Exercise both registries of the dedicated Anvil Emacs daemon."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import time

EVAL_IDE_TOOLS = {
    "diagnostics",
    "emacs-eval",
    "emacs-eval-async",
    "emacs-eval-cancel",
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
    launcher: Path,
    host: str,
    server_id: str,
    frames: list[str],
    timeout_seconds: float = 300,
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
            timeout=timeout_seconds,
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


def assert_tool_failure(response: dict[str, object], needle: str) -> None:
    """Require one MCP tool failure containing a non-sensitive diagnostic."""
    result = response.get("result")
    if not isinstance(result, dict) or result.get("isError") is not True:
        raise AssertionError(f"tool call unexpectedly succeeded: {result}")
    if needle.lower() not in json.dumps(result, sort_keys=True).lower():
        raise AssertionError(f"tool failure did not contain {needle!r}: {result}")


def tool_result_text(response: dict[str, object]) -> str:
    """Return the single text block from a successful MCP tool result."""
    result = response["result"]
    if not isinstance(result, dict) or result.get("isError") is True:
        raise AssertionError(f"tool call failed: {result}")
    content = result.get("content")
    if not isinstance(content, list) or len(content) != 1:
        raise AssertionError(f"unexpected tool content: {result}")
    block = content[0]
    if not isinstance(block, dict) or not isinstance(block.get("text"), str):
        raise AssertionError(f"tool result has no text block: {result}")
    return block["text"]


def assert_tool_omits(response: dict[str, object], needle: str) -> None:
    """Assert a successful tool result contains no wrapper chatter."""
    result = response["result"]
    if needle.lower() in json.dumps(result, sort_keys=True).lower():
        raise AssertionError(f"tool result unexpectedly contained {needle!r}: {result}")


def decode_eval_json(response: dict[str, object]) -> object:
    """Decode JSON returned through the printed emacs-eval string."""
    result = response["result"]
    if not isinstance(result, dict) or result.get("isError") is True:
        raise AssertionError(f"emacs-eval failed: {result}")
    content = result.get("content")
    if not isinstance(content, list) or len(content) != 1:
        raise AssertionError(f"unexpected emacs-eval content: {result}")
    text = content[0].get("text")
    if not isinstance(text, str):
        raise AssertionError(f"emacs-eval text is missing: {result}")
    try:
        return json.loads(json.loads(text))
    except (TypeError, json.JSONDecodeError) as error:
        raise AssertionError(f"invalid emacs-eval JSON: {text}") from error


def resolved_path(value: object, label: str) -> Path:
    """Return a normalized path or fail with a focused assertion."""
    if not isinstance(value, str):
        raise AssertionError(f"{label} is not a path: {value!r}")
    return Path(value).resolve()


def direnv_buffer_expression() -> str:
    """Return Elisp that proves visited buffers retain isolated environments."""
    project_a = Path.home() / "direnv-a"
    project_b = Path.home() / "direnv-b"
    project_c = Path.home() / "direnv-c"
    project_unset = Path.home() / "direnv-unset"
    project_spoof = Path.home() / "direnv-spoof"
    project_failing = Path.home() / "direnv-failing"
    file_a = project_a / "visited.txt"
    file_b = project_b / "visited.txt"
    file_c = project_c / "visited.txt"
    file_unset = project_unset / "visited.txt"
    file_spoof = project_spoof / "visited.txt"
    file_failing = project_failing / "visited.txt"
    return f"""
(progn
  (require 'json)
  (setq anvil-headless-smoke--mode-marker :false
        anvil-headless-smoke--mode-executable :false)
  (defun anvil-headless-smoke--mode-probe ()
    (when (string-suffix-p "/direnv-a/visited.txt"
                           (or buffer-file-name ""))
      (setq anvil-headless-smoke--mode-marker
            (or (getenv "ANVIL_DIRENV_MARKER") :false)
            anvil-headless-smoke--mode-executable
            (or (executable-find "anvil-direnv-a") :false))))
  (add-hook 'text-mode-hook #'anvil-headless-smoke--mode-probe)
  (unwind-protect
      (let* ((buffer-a (find-file-noselect {json.dumps(str(file_a))}))
             (buffer-b (find-file-noselect {json.dumps(str(file_b))}))
             (buffer-c (find-file-noselect {json.dumps(str(file_c))}))
             (row-a
              (with-current-buffer buffer-a
                (vector
                 (or (getenv "ANVIL_DIRENV_MARKER") :false)
                 (or (executable-find "anvil-direnv-a") :false)
                 (or (executable-find "anvil-direnv-b") :false)
                 (or (executable-find "emacsclient") :false)
                 (and (local-variable-p 'process-environment) t)
                 (and (local-variable-p 'exec-path) t)
                 direnv--active-directory)))
             (row-b
              (with-current-buffer buffer-b
                (vector
                 (or (getenv "ANVIL_DIRENV_MARKER") :false)
                 (or (executable-find "anvil-direnv-b") :false)
                 (or (executable-find "anvil-direnv-a") :false)
                 (or (executable-find "emacsclient") :false)
                 (and (local-variable-p 'process-environment) t)
                 (and (local-variable-p 'exec-path) t)
                 direnv--active-directory)))
             (row-c
              (with-current-buffer buffer-c
                (vector
                 (or (getenv "ANVIL_DIRENV_MARKER") :false)
                 (or (getenv "ANVIL_DIRENV_BRACE") :false)
                 (or (executable-find "anvil-direnv-c") :false)
                 (or (executable-find "emacsclient") :false)
                 (or (executable-find "rg") :false)
                 (car exec-path)
                 (and (local-variable-p 'process-environment) t)
                 (and (local-variable-p 'exec-path) t)
                 direnv--active-directory
                 (or (getenv "PATH") :false))))
             (row-unset
              (with-current-buffer
                  (find-file-noselect {json.dumps(str(file_unset))})
                (vector
                 (or (getenv "ANVIL_DIRENV_MARKER") :false)
                 (or (executable-find "anvil-direnv-unset") :false)
                 (or (getenv "ANVIL_EMACS_SOCKET") :false)
                 (and (local-variable-p 'process-environment) t)
                 (and (local-variable-p 'exec-path) t)
                 direnv--active-directory)))
             (row-spoof
              (with-current-buffer
                  (find-file-noselect {json.dumps(str(file_spoof))})
                (vector
                 (or (getenv "ANVIL_DIRENV_MARKER") :false)
                 (or (executable-find "anvil-direnv-spoof") :false)
                 (or (getenv "ANVIL_EMACS_SOCKET") :false)
                 (and (local-variable-p 'process-environment) t)
                 (and (local-variable-p 'exec-path) t)
                 direnv--active-directory)))
             (row-failing
              (with-current-buffer
                  (find-file-noselect {json.dumps(str(file_failing))})
                (vector
                 (or (getenv "ANVIL_DIRENV_MARKER") :false)
                 (or (executable-find "anvil-direnv-failing") :false)
                 (or direnv--active-directory :false)
                 (or (getenv "DIRENV_DIFF") :false)
                 (and (local-variable-p 'process-environment) t)
                 (and (local-variable-p 'exec-path) t)
                 (or (getenv "PATH") :false))))
             (default-marker
              (let ((process-environment
                     (default-value 'process-environment)))
                (or (getenv "ANVIL_DIRENV_MARKER") :false))))
        (json-serialize
         (vector row-a row-b row-c row-unset row-spoof row-failing default-marker
                 (and (featurep 'direnv) t)
                 (and (featurep 'exec-path-from-shell) t)
                 (vector anvil-headless-smoke--mode-marker
                         anvil-headless-smoke--mode-executable)
                 (or (executable-find "anvil-login-shell") :false))))
    (remove-hook 'text-mode-hook #'anvil-headless-smoke--mode-probe)
    (fmakunbound 'anvil-headless-smoke--mode-probe)))
""".strip()


def assert_direnv_buffers(response: dict[str, object]) -> None:
    """Validate per-buffer direnv isolation and required executable paths."""
    data = decode_eval_json(response)
    if not isinstance(data, list) or len(data) != 11:
        raise AssertionError(f"unexpected direnv buffer result: {data}")
    (
        row_a,
        row_b,
        row_c,
        row_unset,
        row_spoof,
        row_failing,
        default_marker,
        has_direnv,
        has_shell_import,
        mode_probe,
        login_path,
    ) = data
    project_a = Path.home() / "direnv-a"
    project_b = Path.home() / "direnv-b"
    project_c = Path.home() / "direnv-c"
    project_unset = Path.home() / "direnv-unset"
    project_spoof = Path.home() / "direnv-spoof"
    project_failing = Path.home() / "direnv-failing"
    expected_rows = (
        (
            row_a,
            "project-a",
            project_a / "bin" / "anvil-direnv-a",
            project_a,
        ),
        (
            row_b,
            "project-b",
            project_b / "bin" / "anvil-direnv-b",
            project_b,
        ),
    )
    for row, marker, executable, project in expected_rows:
        if not isinstance(row, list) or len(row) != 7:
            raise AssertionError(f"malformed direnv row: {row}")
        if (
            row[0] != marker
            or resolved_path(row[1], f"{project} executable") != executable.resolve()
            or row[2] is not False
        ):
            raise AssertionError(f"wrong project environment for {project}: {row}")
        if not isinstance(row[3], str) or Path(row[3]).name != "emacsclient":
            raise AssertionError(f"emacsclient disappeared from PATH: {row}")
        if row[4:6] != [True, True]:
            raise AssertionError(f"environment is not buffer-local: {row}")
        if resolved_path(row[6], f"{project} active directory") != project.resolve():
            raise AssertionError(f"direnv active directory mismatch: {row}")

    if not isinstance(row_c, list) or len(row_c) != 10:
        raise AssertionError(f"malformed PATH-replacement row: {row_c}")
    expected_c = project_c / "bin" / "anvil-direnv-c"
    if (
        row_c[0:2] != ["project-c", "prefix{suffix"]
        or resolved_path(row_c[2], "project-c executable") != expected_c.resolve()
    ):
        raise AssertionError(f"PATH-replacing envrc was not applied: {row_c}")
    emacsclient = resolved_path(row_c[3], "project-c emacsclient")
    resolved_path(row_c[4], "project-c rg")
    if resolved_path(row_c[5], "project-c exec-path head") != emacsclient.parent:
        raise AssertionError(f"dedicated Emacs bin is not first in exec-path: {row_c}")
    if row_c[6:8] != [True, True]:
        raise AssertionError(f"project-c environment is not buffer-local: {row_c}")
    if resolved_path(row_c[8], "project-c active directory") != project_c.resolve():
        raise AssertionError(f"project-c active directory mismatch: {row_c}")
    if not isinstance(row_c[9], str):
        raise AssertionError(f"project-c PATH is missing: {row_c}")
    path_entries = [Path(entry).resolve() for entry in row_c[9].split(os.pathsep)]
    if path_entries.count(emacsclient.parent) != 1:
        raise AssertionError(f"dedicated Emacs bin is duplicated in PATH: {row_c[9]}")

    expected_root_socket = (
        Path(os.environ["ANVIL_EMACS_RUNTIME_ROOT"]) / "host-a" / "emacs" / "server"
    )
    guarded_rows = (
        (
            row_unset,
            "project-unset",
            project_unset / "bin" / "anvil-direnv-unset",
            project_unset,
        ),
        (
            row_spoof,
            "project-spoof",
            project_spoof / "bin" / "anvil-direnv-spoof",
            project_spoof,
        ),
    )
    for row, marker, executable, project in guarded_rows:
        if not isinstance(row, list) or len(row) != 6:
            raise AssertionError(f"malformed guarded direnv row: {row}")
        if (
            row[0] != marker
            or resolved_path(row[1], f"{project} executable") != executable.resolve()
            or resolved_path(row[2], f"{project} root socket")
            != expected_root_socket.resolve()
            or row[3:5] != [True, True]
            or resolved_path(row[5], f"{project} active directory") != project.resolve()
        ):
            raise AssertionError(f"guard state was not restored for {project}: {row}")

    if not isinstance(row_failing, list) or len(row_failing) != 7:
        raise AssertionError(f"malformed failing-direnv row: {row_failing}")
    if row_failing[:4] != [False, False, False, False]:
        raise AssertionError(f"failed envrc leaked environment state: {row_failing}")
    if row_failing[4:6] != [True, True] or not isinstance(row_failing[6], str):
        raise AssertionError(
            f"failed envrc lost its clean buffer baseline: {row_failing}"
        )
    failing_bin = (project_failing / "bin").resolve()
    if failing_bin in [
        Path(entry).resolve() for entry in row_failing[6].split(os.pathsep)
    ]:
        raise AssertionError(f"failed envrc leaked its PATH entry: {row_failing}")

    if default_marker is not False:
        raise AssertionError(f"project environment leaked globally: {data}")
    if [has_direnv, has_shell_import] != [True, True]:
        raise AssertionError(f"environment packages were not loaded: {data}")
    expected_mode_executable = project_a / "bin" / "anvil-direnv-a"
    if (
        not isinstance(mode_probe, list)
        or len(mode_probe) != 2
        or mode_probe[0] != "project-a"
        or resolved_path(mode_probe[1], "mode-hook executable")
        != expected_mode_executable.resolve()
    ):
        raise AssertionError(f"mode hook ran before direnv activation: {mode_probe}")
    expected_login_path = Path.home() / "login-bin" / "anvil-login-shell"
    if (
        resolved_path(login_path, "root login-shell executable")
        != expected_login_path.resolve()
    ):
        raise AssertionError(f"root did not import the login-shell PATH: {login_path}")


def recursion_guard_command(project_command: str) -> str:
    """Return a representative shell probe for restored socket guards."""
    return f"""
root_socket="$ANVIL_EMACS_RUNTIME_ROOT/host-a/emacs/server"
other_socket="$ANVIL_EMACS_RUNTIME_ROOT/host-b/emacs/server"
"$ANVIL_PER_AGENT_LAUNCHER" </dev/null >/dev/null 2>&1
nested_status=$?
emacsclient -a false -e t >/dev/null 2>&1
implicit_status=$?
emacsclient -a false -s "$root_socket" -e t >/dev/null 2>&1
root_status=$?
other_output=$(emacsclient -a false -s "$other_socket" -e t 2>/dev/null)
other_status=$?
printf '%s:%s:%s:nested=%s:implicit=%s:root=%s:other=%s:%s' \\
  "$ANVIL_DIRENV_MARKER" "$({project_command})" "$ANVIL_EMACS_SOCKET" \\
  "$nested_status" "$implicit_status" "$root_status" \\
  "$other_status" "$other_output"
""".strip()


def assert_recursion_guards(
    response: dict[str, object], marker: str, project_command: str
) -> None:
    """Validate representative guards without duplicating parser unit tests."""
    root_socket = (
        Path(os.environ["ANVIL_EMACS_RUNTIME_ROOT"]) / "host-a" / "emacs" / "server"
    )
    expected = (
        f"{marker}:{project_command}:{root_socket}:"
        "nested=64:implicit=69:root=69:other=0:t"
    )
    assert_tool_success(response, expected)


def worker_snapshot_expression(worker_specs: WorkerSpecs) -> str:
    """Return Elisp that validates and snapshots every worker lane."""
    worker_expression = r"""
(condition-case err
    (let* ((name (format "%s" (daemonp)))
           (runtime-lock
            (expand-file-name ".anvil-headless-emacs.lock"
                              (getenv "XDG_RUNTIME_DIR")))
           (state-lock
            (expand-file-name ".anvil-headless-emacs.lock"
                              (getenv "ANVIL_EMACS_STATE_DIR"))))
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
            ;; Emacs may reuse these descriptor numbers after the wrapper
            ;; closes them, so compare file identity rather than existence.
            (if (and (file-exists-p "/dev/fd/8")
                     (file-equal-p "/dev/fd/8" runtime-lock))
                t :false)
            (if (and (file-exists-p "/dev/fd/9")
                     (file-equal-p "/dev/fd/9" state-lock))
                t :false)
            (and (featurep 'direnv) t)
            (and (featurep 'exec-path-from-shell) t)
            (with-current-buffer
                (find-file-noselect
                 (expand-file-name "direnv-spoof/visited.txt" (getenv "HOME")))
              (or (getenv "ANVIL_DIRENV_MARKER") :false))
            (with-current-buffer
                (find-file-noselect
                 (expand-file-name "direnv-spoof/visited.txt" (getenv "HOME")))
              (or (executable-find "anvil-direnv-spoof") :false))
            (with-current-buffer
                (find-file-noselect
                 (expand-file-name "direnv-spoof/visited.txt" (getenv "HOME")))
              (or (executable-find "emacsclient") :false))
            (or (executable-find "anvil-login-shell") :false)
            (or (getenv "ANVIL_EMACS_SOCKET") :false)))
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
    snapshots = decode_eval_json(response)
    if not isinstance(snapshots, list) or len(snapshots) != len(worker_specs):
        raise AssertionError(f"unexpected worker snapshots: {snapshots}")

    state_root = Path(os.environ["ANVIL_EMACS_STATE_ROOT"]) / host / "workers"
    runtime_root = Path(os.environ["ANVIL_EMACS_RUNTIME_ROOT"]) / host / "workers"
    socket_root = Path(os.environ["ANVIL_EMACS_RUNTIME_ROOT"]) / host / "emacs"
    for snapshot, (_, name) in zip(snapshots, worker_specs, strict=True):
        if not isinstance(snapshot, list) or len(snapshot) != 20:
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
        if snapshot[11:13] != [False, False]:
            raise AssertionError(
                f"{name} retained daemon lock-file descriptors: {snapshot[11:13]}"
            )
        if snapshot[13:15] != [True, True]:
            raise AssertionError(
                f"{name} did not load direnv environment support: {snapshot[13:15]}"
            )
        expected_project_command = (
            Path.home() / "direnv-spoof" / "bin" / "anvil-direnv-spoof"
        )
        if (
            snapshot[15] != "project-spoof"
            or resolved_path(snapshot[16], f"{name} project executable")
            != expected_project_command.resolve()
        ):
            raise AssertionError(f"{name} did not inherit the project env: {snapshot}")
        if (
            not isinstance(snapshot[17], str)
            or Path(snapshot[17]).name != "emacsclient"
        ):
            raise AssertionError(f"{name} lost emacsclient from PATH: {snapshot}")
        expected_login_command = Path.home() / "login-bin" / "anvil-login-shell"
        if (
            resolved_path(snapshot[18], f"{name} login-shell executable")
            != expected_login_command.resolve()
        ):
            raise AssertionError(f"{name} did not inherit the login PATH: {snapshot}")
        expected_root_socket = (
            Path(os.environ["ANVIL_EMACS_RUNTIME_ROOT"]) / host / "emacs" / "server"
        )
        if (
            resolved_path(snapshot[19], f"{name} root socket")
            != expected_root_socket.resolve()
        ):
            raise AssertionError(f"{name} inherited a spoofed root socket: {snapshot}")


def spawn_baseline_expression() -> str:
    """Probe the installed worker-spawn wrapper under a contaminated environment."""
    return r"""
(progn
  (unless
      (advice-member-p
       #'anvil-headless--with-parent-pid-for-worker
       'anvil-worker--spawn-worker)
    (error "worker spawn baseline advice is not installed"))
  (let ((process-environment (copy-sequence process-environment))
        (exec-path (cons "/timer-contamination"
                         (copy-sequence exec-path)))
        (contaminated-directory
         (make-temp-file "anvil-deleted-project-" t)))
    (setenv "ANVIL_DIRENV_MARKER" "timer-contamination")
    (unwind-protect
        (let ((default-directory
               (file-name-as-directory contaminated-directory)))
          (delete-directory contaminated-directory)
          (json-serialize
           (anvil-headless--with-parent-pid-for-worker
            (lambda ()
              (vector
               (or (getenv "ANVIL_DIRENV_MARKER") :false)
               (if (member "/timer-contamination" exec-path) t :false)
               (or (getenv "ANVIL_HEADLESS_PARENT_PID") :false)
               (number-to-string (emacs-pid))
               default-directory
               user-emacs-directory
               (call-process "true" nil nil nil))))))
      (when (file-exists-p contaminated-directory)
        (delete-directory contaminated-directory t)))))
""".strip()


def assert_spawn_baseline(response: dict[str, object], host: str) -> None:
    """Validate the immutable environment and parent used by worker spawn."""
    snapshot = decode_eval_json(response)
    if not isinstance(snapshot, list) or len(snapshot) != 7:
        raise AssertionError(f"malformed worker spawn snapshot: {snapshot}")
    if snapshot[:2] != [False, False]:
        raise AssertionError(f"spawn wrapper retained the project env: {snapshot}")
    if (
        not isinstance(snapshot[2], str)
        or not snapshot[2].isdecimal()
        or snapshot[2] != snapshot[3]
    ):
        raise AssertionError(f"spawn wrapper used the wrong parent PID: {snapshot}")
    expected_directory = Path(os.environ["ANVIL_EMACS_STATE_ROOT"]) / host
    if (
        not isinstance(snapshot[4], str)
        or not isinstance(snapshot[5], str)
        or Path(snapshot[4]) != expected_directory
        or Path(snapshot[5]) != expected_directory
        or snapshot[6] != 0
    ):
        raise AssertionError(
            "spawn wrapper retained a deleted project directory: "
            f"{snapshot}, expected={expected_directory}"
        )


def watchdog_lease_expression() -> str:
    """Exercise the synchronous diagnostic lease around one request."""
    return r"""
(progn
  (unless
      (advice-member-p
       #'anvil-headless--watchdog-sync-dispatch
       'anvil-server-process-jsonrpc)
    (error "synchronous watchdog advice is not installed"))
  (json-serialize
   (vector
    anvil-headless--watchdog-sync-dispatch-depth
    (logand (file-modes anvil-headless--watchdog-lease-file) #o777)
    (if (boundp 'anvil-headless--watchdog-async-jobs) t :false))))
""".strip()


def assert_watchdog_lease(response: dict[str, object], lease: Path) -> None:
    """Validate sync diagnostic state and the absence of async exemption."""
    snapshot = decode_eval_json(response)
    expected = [1, 0o600, False]
    if snapshot != expected:
        raise AssertionError(
            f"watchdog diagnostic lease mismatch: {snapshot} != {expected}"
        )
    if stat.S_IMODE(lease.stat().st_mode) != 0o400:
        raise AssertionError("synchronous watchdog lease did not return to idle")


def call_tool(
    launcher: Path,
    initialize: dict[str, object],
    name: str,
    arguments: dict[str, object],
    timeout_seconds: float = 10,
) -> dict[str, object]:
    """Call one tool through a fresh bridge with a bounded outer deadline."""
    responses = run_transcript(
        launcher,
        "host-a",
        "anvil",
        [
            request(1, "initialize", initialize),
            request(None, "notifications/initialized"),
            request(
                2,
                "tools/call",
                {"name": name, "arguments": arguments},
            ),
        ],
        timeout_seconds,
    )
    return response_by_id(responses, 2)


def submit_async(
    launcher: Path,
    initialize: dict[str, object],
    expression: str,
    timeout_seconds: float,
) -> str:
    """Submit one isolated async expression and return its job ID."""
    response = call_tool(
        launcher,
        initialize,
        "emacs-eval-async",
        {"expression": expression, "timeout": timeout_seconds},
    )
    text = tool_result_text(response)
    match = re.search(r"\bjob-[0-9]+-[0-9]+\b", text)
    if match is None:
        raise AssertionError(f"async submission returned no job ID: {text}")
    return match.group(0)


def poll_async(
    launcher: Path,
    initialize: dict[str, object],
    job_id: str,
    timeout_seconds: float,
) -> str:
    """Poll JOB-ID through independent bridges until it becomes terminal."""
    deadline = time.monotonic() + timeout_seconds
    last = ""
    while time.monotonic() < deadline:
        remaining = max(1.0, deadline - time.monotonic())
        last = tool_result_text(
            call_tool(
                launcher,
                initialize,
                "emacs-eval-result",
                {"job-id": job_id},
                timeout_seconds=remaining,
            )
        )
        if "status: done" in last or "status: error" in last:
            return last
        time.sleep(0.1)
    raise AssertionError(f"async job {job_id} did not settle: {last}")


def process_alive(pid: int) -> bool:
    """Return whether PID still names a live process."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def assert_async_isolation(
    launcher: Path,
    initialize: dict[str, object],
    watchdog_lease: Path,
) -> None:
    """Prove a wedged async child cannot wedge or exempt the root daemon."""
    runtime = Path(os.environ["ANVIL_EMACS_RUNTIME_ROOT"]) / "host-a"
    child_pid_file = runtime / "async-child.pid"
    pulse_file = runtime / ".anvil-root-pulse"
    child_pid_file.unlink(missing_ok=True)
    pulse_before = pulse_file.read_text()

    looping_expression = (
        "(progn "
        f"(with-temp-file {json.dumps(str(child_pid_file))} "
        "(insert (number-to-string (emacs-pid)))) "
        "(while t))"
    )
    # The timeout includes the one-shot Emacs cold start and its containment
    # guard handshake.  Keep enough margin above the guard's own readiness
    # ceiling that the expression demonstrably begins before it is killed.
    async_timeout = 15
    job_id = submit_async(
        launcher,
        initialize,
        looping_expression,
        async_timeout,
    )

    marker_deadline = time.monotonic() + 10
    while not child_pid_file.exists() and time.monotonic() < marker_deadline:
        time.sleep(0.05)
    if not child_pid_file.exists():
        terminal = poll_async(
            launcher,
            initialize,
            job_id,
            async_timeout + 5,
        )
        raise AssertionError(
            "isolated async child never wrote its PID marker; "
            f"terminal job state: {terminal}"
        )
    child_pid = int(child_pid_file.read_text().strip())

    root_text = tool_result_text(
        call_tool(
            launcher,
            initialize,
            "emacs-eval",
            {"expression": "(emacs-pid)"},
            timeout_seconds=5,
        )
    )
    root_match = re.search(r"\b[0-9]+\b", root_text)
    if root_match is None:
        raise AssertionError(f"root Emacs returned no PID: {root_text}")
    root_pid = int(root_match.group(0))
    if root_pid == child_pid:
        raise AssertionError("async expression ran inside the root Emacs")

    pulse_deadline = time.monotonic() + 2
    while pulse_file.read_text() == pulse_before and time.monotonic() < pulse_deadline:
        time.sleep(0.05)
    if pulse_file.read_text() == pulse_before:
        raise AssertionError("root watchdog stopped pulsing during async evaluation")
    if stat.S_IMODE(watchdog_lease.stat().st_mode) != 0o400:
        raise AssertionError("async evaluation incorrectly exempted the root watchdog")

    terminal = poll_async(
        launcher,
        initialize,
        job_id,
        async_timeout + 5,
    )
    if "status: error" not in terminal or "timeout" not in terminal.lower():
        raise AssertionError(f"looping async job did not time out: {terminal}")

    death_deadline = time.monotonic() + 5
    while process_alive(child_pid) and time.monotonic() < death_deadline:
        time.sleep(0.05)
    if process_alive(child_pid):
        raise AssertionError(f"timed-out async child {child_pid} survived")

    root_after = tool_result_text(
        call_tool(
            launcher,
            initialize,
            "emacs-eval",
            {"expression": "(emacs-pid)"},
            timeout_seconds=5,
        )
    )
    if str(root_pid) not in root_after:
        raise AssertionError(f"root daemon changed after async timeout: {root_after}")

    project_file = Path.home() / "direnv-a" / "visited.txt"
    environment_expression = (
        f"(with-current-buffer (find-file-noselect {json.dumps(str(project_file))}) "
        '(list (getenv "ANVIL_DIRENV_MARKER") '
        '(executable-find "anvil-direnv-a")))'
    )
    environment_timeout = 10
    environment_job = submit_async(
        launcher,
        initialize,
        environment_expression,
        environment_timeout,
    )
    environment_result = poll_async(
        launcher,
        initialize,
        environment_job,
        environment_timeout + 5,
    )
    if (
        "status: done" not in environment_result
        or "project-a" not in environment_result
        or "anvil-direnv-a" not in environment_result
    ):
        raise AssertionError(
            f"isolated async child lost the project environment: {environment_result}"
        )


def main() -> None:
    if (
        len(sys.argv) != 5
        or not sys.argv[3].isdigit()
        or int(sys.argv[3]) <= 0
        or not sys.argv[4].isdigit()
        or int(sys.argv[4]) <= 0
    ):
        raise SystemExit(
            "usage: headless-smoke.py /path/to/anvil-mcp "
            "WORKER_SPECS_JSON CLIENT_TOOL_SECONDS HOST_SHELL_SECONDS"
        )

    launcher = Path(sys.argv[1]).resolve()
    worker_specs = parse_worker_specs(sys.argv[2])
    client_tool_seconds = float(sys.argv[3])
    host_shell_seconds = int(sys.argv[4])
    org_root = Path.home() / "org"
    org_file = org_root / "smoke.org"
    initialize = {
        "protocolVersion": "2025-03-26",
        "capabilities": {},
        "clientInfo": {"name": "nix-headless-smoke", "version": "1"},
    }
    snapshot_expression = worker_snapshot_expression(worker_specs)
    buffer_environment_expression = direnv_buffer_expression()
    spawn_environment_expression = spawn_baseline_expression()
    watchdog_expression = watchdog_lease_expression()
    project_a = Path.home() / "direnv-a"
    project_b = Path.home() / "direnv-b"
    project_plain = Path.home() / "direnv-plain"
    project_c = Path.home() / "direnv-c"
    project_unset = Path.home() / "direnv-unset"
    project_spoof = Path.home() / "direnv-spoof"
    project_blocked = Path.home() / "direnv-blocked"
    project_failing = Path.home() / "direnv-failing"
    failing_shell_marker = Path.home() / "direnv-failing-shell-ran"
    runtime_lock = (
        Path(os.environ["ANVIL_EMACS_RUNTIME_ROOT"])
        / "host-a"
        / ".anvil-headless-emacs.lock"
    )
    state_lock = (
        Path(os.environ["ANVIL_EMACS_STATE_ROOT"])
        / "host-a"
        / ".anvil-headless-emacs.lock"
    )
    watchdog_lease = (
        Path(os.environ["ANVIL_EMACS_RUNTIME_ROOT"])
        / "host-a"
        / ".anvil-root-async-lease"
    )
    lock_fd_command = (
        "if { [ -e /dev/fd/8 ] && "
        f"[ /dev/fd/8 -ef {shlex.quote(str(runtime_lock))} ]; "
        "} || { [ -e /dev/fd/9 ] && "
        f"[ /dev/fd/9 -ef {shlex.quote(str(state_lock))} ]; "
        "}; then printf lock-fds-retained; else printf lock-fds-closed; fi"
    )

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
            request(
                9,
                "tools/call",
                {
                    "name": "emacs-eval",
                    "arguments": {"expression": buffer_environment_expression},
                },
            ),
            request(
                10,
                "tools/call",
                {
                    "name": "shell-run",
                    "arguments": {
                        "cmd": (
                            "printf '%s:%s' \"$ANVIL_DIRENV_MARKER\" "
                            '"$(anvil-direnv-a)"'
                        ),
                        "filter": "",
                        "cwd": str(project_a),
                    },
                },
            ),
            request(
                11,
                "tools/call",
                {
                    "name": "shell-run",
                    "arguments": {
                        "cmd": (
                            "printf '%s:%s' \"$ANVIL_DIRENV_MARKER\" "
                            '"$(anvil-direnv-b)"'
                        ),
                        "filter": "",
                        "cwd": str(project_b),
                    },
                },
            ),
            request(
                12,
                "tools/call",
                {
                    "name": "shell-run",
                    "arguments": {
                        "cmd": (
                            "printf '%s:%s' "
                            '"${ANVIL_DIRENV_MARKER-unset}" '
                            '"$(command -v anvil-direnv-a || printf missing)"'
                        ),
                        "filter": "",
                        "cwd": str(project_plain),
                    },
                },
            ),
            request(
                13,
                "tools/call",
                {
                    "name": "file-read",
                    "arguments": {"path": str(runtime_lock)},
                },
            ),
            request(
                14,
                "tools/call",
                {
                    "name": "file-read",
                    "arguments": {"path": str(state_lock)},
                },
            ),
            request(
                15,
                "tools/call",
                {
                    "name": "shell-run",
                    "arguments": {
                        "cmd": lock_fd_command,
                        "filter": "",
                        "cwd": str(project_plain),
                    },
                },
            ),
            request(
                16,
                "tools/call",
                {
                    "name": "shell-run",
                    "arguments": {
                        "cmd": (
                            "printf '%s:%s:%s:' \"$ANVIL_DIRENV_MARKER\" "
                            '"$ANVIL_DIRENV_BRACE" "$(anvil-direnv-c)"; rg --version'
                        ),
                        "filter": "",
                        "cwd": str(project_c),
                    },
                },
            ),
            request(
                17,
                "tools/call",
                {
                    "name": "shell-run",
                    "arguments": {
                        "cmd": (
                            "printf '%s:%s:%s:%s:%s:blocked-command' "
                            '"${ANVIL_DIRENV_MARKER-unset}" '
                            '"${DIRENV_DIFF-unset}" '
                            '"${DIRENV_DIR-unset}" '
                            '"${DIRENV_FILE-unset}" '
                            '"${DIRENV_WATCHES-unset}"'
                        ),
                        "filter": "",
                        "cwd": str(project_blocked),
                    },
                },
            ),
            request(
                18,
                "tools/call",
                {
                    "name": "emacs-eval",
                    "arguments": {"expression": spawn_environment_expression},
                },
            ),
            request(
                19,
                "tools/call",
                {
                    "name": "emacs-eval",
                    "arguments": {"expression": watchdog_expression},
                },
            ),
            request(
                20,
                "tools/call",
                {
                    "name": "shell-run",
                    "arguments": {
                        "cmd": f"printf ran > {shlex.quote(str(failing_shell_marker))}",
                        "filter": "",
                        "cwd": str(project_failing),
                    },
                },
            ),
            request(
                21,
                "tools/call",
                {
                    "name": "emacs-eval",
                    "arguments": {"expression": "anvil-host--default-timeout"},
                },
            ),
            request(
                22,
                "tools/call",
                {
                    "name": "shell-run",
                    "arguments": {
                        "cmd": (
                            "rg -n 'anvil-eof-probe-no-match' >/dev/null; "
                            "status=$?; printf 'pathless-rg:%s' \"$status\""
                        ),
                        "filter": "",
                        "cwd": str(project_plain),
                        "timeout_sec": 5,
                    },
                },
            ),
            request(
                23,
                "tools/call",
                {
                    "name": "shell-run",
                    "arguments": {
                        "cmd": "cat >/dev/null; printf stdin-eof",
                        "filter": "",
                        "cwd": str(project_plain),
                        "timeout_sec": 5,
                    },
                },
            ),
        ],
    )
    main_names = tool_names(response_by_id(main_responses, 2))
    expected_tools = EVAL_IDE_TOOLS | TYPED_TOOLS
    if main_names != expected_tools:
        raise AssertionError(
            "unexpected unified main surface: "
            f"missing={sorted(expected_tools - main_names)}, "
            f"unexpected={sorted(main_names - expected_tools)}"
        )
    assert_tool_success(response_by_id(main_responses, 3), "42")
    assert_tool_success(response_by_id(main_responses, 4), "server_id=anvil")
    assert_tool_success(response_by_id(main_responses, 5), "headlessorgneedle")
    assert_tool_success(response_by_id(main_responses, 6), ":files")
    assert_tool_success(response_by_id(main_responses, 7), "headlesssemanticneedle")
    assert_worker_snapshot(response_by_id(main_responses, 8), "host-a", worker_specs)
    assert_direnv_buffers(response_by_id(main_responses, 9))
    assert_tool_success(
        response_by_id(main_responses, 10), "project-a:project-a-command"
    )
    assert_tool_success(
        response_by_id(main_responses, 11), "project-b:project-b-command"
    )
    assert_tool_success(response_by_id(main_responses, 12), "unset:missing")
    assert_tool_success(
        response_by_id(main_responses, 13), ".anvil-headless-emacs.lock"
    )
    assert_tool_success(
        response_by_id(main_responses, 14), ".anvil-headless-emacs.lock"
    )
    assert_tool_success(response_by_id(main_responses, 15), "lock-fds-closed")
    assert_tool_success(
        response_by_id(main_responses, 16),
        "project-c:prefix{suffix:project-c-command:ripgrep",
    )
    assert_tool_success(
        response_by_id(main_responses, 17),
        "unset:unset:unset:unset:unset:blocked-command",
    )
    assert_spawn_baseline(response_by_id(main_responses, 18), "host-a")
    assert_watchdog_lease(response_by_id(main_responses, 19), watchdog_lease)
    assert_tool_failure(response_by_id(main_responses, 20), "direnv environment failed")
    assert_tool_success(response_by_id(main_responses, 21), str(host_shell_seconds))
    assert_tool_success(response_by_id(main_responses, 22), "pathless-rg:1")
    assert_tool_success(response_by_id(main_responses, 23), "stdin-eof")
    if failing_shell_marker.exists():
        raise AssertionError("shell-run executed after an allowed envrc failed")
    for identifier in (10, 11, 16, 17):
        assert_tool_omits(response_by_id(main_responses, identifier), "direnv:")

    assert_async_isolation(
        launcher,
        initialize,
        watchdog_lease,
    )

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

    guard_probes = (
        (
            "project-unset",
            "project-unset-command",
            "anvil-direnv-unset",
            project_unset,
        ),
        (
            "project-spoof",
            "project-spoof-command",
            "anvil-direnv-spoof",
            project_spoof,
        ),
    )
    for marker, expected_command, project_command, project in guard_probes:
        try:
            guard_response = call_tool(
                launcher,
                initialize,
                "shell-run",
                {
                    "cmd": recursion_guard_command(project_command),
                    "filter": "",
                    "cwd": str(project),
                },
                client_tool_seconds,
            )
        except AssertionError as error:
            raise AssertionError(f"{marker} recursion guard probe failed") from error
        assert_recursion_guards(guard_response, marker, expected_command)
        assert_tool_omits(guard_response, "direnv:")

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
            "unexpected direct typed surface: "
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
