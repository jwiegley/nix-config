#!/usr/bin/env python3
"""Exercise both registries of the dedicated Anvil Emacs daemon."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
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
    cwd: Path | None = None,
) -> list[dict[str, object]]:
    env = os.environ.copy()
    env["ANVIL_EMACS_HOST"] = host
    try:
        completed = subprocess.run(
            [str(launcher), f"--server-id={server_id}"],
            check=False,
            cwd=cwd,
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


def assert_overlong_socket_path_fails_fast(launcher: Path) -> None:
    """Reject an impossible AF_UNIX path before the readiness deadline."""
    host = "h" * 80
    env = os.environ.copy()
    env["ANVIL_EMACS_HOST"] = host
    env["ANVIL_AGENT_READY_SECONDS"] = "120"
    started = time.monotonic()
    try:
        completed = subprocess.run(
            [str(launcher), "--server-id=anvil"],
            check=False,
            env=env,
            input=b"",
            capture_output=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired as error:
        raise AssertionError(
            "overlong Anvil socket path reached the readiness wait"
        ) from error
    elapsed = time.monotonic() - started
    stderr = completed.stderr.decode(errors="replace")
    if completed.returncode != 77 or "platform Unix socket limit" not in stderr:
        raise AssertionError(
            "overlong Anvil socket path did not fail as configuration: "
            f"rc={completed.returncode} elapsed={elapsed:.3f}s stderr={stderr!r}"
        )
    runtime_host = Path(env["ANVIL_EMACS_RUNTIME_ROOT"]) / host
    state_host = Path(env["ANVIL_EMACS_STATE_ROOT"]) / host
    if runtime_host.exists() or state_host.exists():
        raise AssertionError("overlong Anvil socket path published host state")


def assert_overlong_explicit_socket_fails_fast(launcher: Path) -> None:
    """Reject an explicit impossible socket before readiness or publication."""
    host = "explicit-overlong"
    socket_path = "/" + ("s" * 200)
    env = os.environ.copy()
    env["ANVIL_EMACS_HOST"] = host
    started = time.monotonic()
    try:
        completed = subprocess.run(
            [str(launcher), f"--socket={socket_path}", "--server-id=anvil"],
            check=False,
            env=env,
            input=b"",
            capture_output=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired as error:
        raise AssertionError("overlong explicit socket reached readiness") from error
    elapsed = time.monotonic() - started
    stderr = completed.stderr.decode(errors="replace")
    if completed.returncode != 77 or "platform Unix socket limit" not in stderr:
        raise AssertionError(
            "overlong explicit socket did not fail as configuration: "
            f"rc={completed.returncode} elapsed={elapsed:.3f}s stderr={stderr!r}"
        )
    runtime_host = Path(env["ANVIL_EMACS_RUNTIME_ROOT"]) / host
    state_host = Path(env["ANVIL_EMACS_STATE_ROOT"]) / host
    if runtime_host.exists() or state_host.exists():
        raise AssertionError("overlong explicit socket published host state")


def assert_overlong_daemon_socket_paths_fail_fast(daemon: Path) -> None:
    """Reject impossible default and exact daemon paths without residue."""
    base_env = os.environ.copy()
    base_env["ANVIL_EMACS_LOCK_CONFLICT_STATUS"] = "75"
    cases: list[tuple[str, dict[str, str], tuple[Path, ...], str]] = []

    default_host = "d" * 80
    default_env = base_env.copy()
    default_env["ANVIL_EMACS_HOST"] = default_host
    default_env.pop("ANVIL_EMACS_RUNTIME_DIR", None)
    default_env.pop("ANVIL_EMACS_STATE_DIR", None)
    cases.append(
        (
            "default",
            default_env,
            (
                Path(default_env["ANVIL_EMACS_RUNTIME_ROOT"]) / default_host,
                Path(default_env["ANVIL_EMACS_STATE_ROOT"]) / default_host,
            ),
            "platform Unix socket limit",
        )
    )

    exact_runtime = Path(base_env["ANVIL_EMACS_RUNTIME_ROOT"]) / ("x" * 100)
    exact_state = Path(base_env["ANVIL_EMACS_STATE_ROOT"]) / "exact-overlong"
    exact_env = base_env.copy()
    exact_env["ANVIL_EMACS_HOST"] = "exact-overlong"
    exact_env["ANVIL_EMACS_RUNTIME_DIR"] = str(exact_runtime)
    exact_env["ANVIL_EMACS_STATE_DIR"] = str(exact_state)
    cases.append(
        (
            "exact",
            exact_env,
            (exact_runtime, exact_state),
            "platform Unix socket limit",
        )
    )

    coincident_host = "coincident-default"
    coincident_env = base_env.copy()
    coincident_env["ANVIL_EMACS_HOST"] = coincident_host
    coincident_env["ANVIL_EMACS_STATE_ROOT"] = coincident_env[
        "ANVIL_EMACS_RUNTIME_ROOT"
    ]
    coincident_env.pop("ANVIL_EMACS_RUNTIME_DIR", None)
    coincident_env.pop("ANVIL_EMACS_STATE_DIR", None)
    cases.append(
        (
            "coincident default",
            coincident_env,
            (Path(coincident_env["ANVIL_EMACS_RUNTIME_ROOT"]) / coincident_host,),
            "runtime and state directories must be distinct",
        )
    )

    coincident_exact = Path(base_env["ANVIL_EMACS_RUNTIME_ROOT"]) / "coincident-exact"
    coincident_exact_env = base_env.copy()
    coincident_exact_env["ANVIL_EMACS_HOST"] = "coincident-exact"
    coincident_exact_env["ANVIL_EMACS_RUNTIME_DIR"] = str(coincident_exact)
    coincident_exact_env["ANVIL_EMACS_STATE_DIR"] = str(coincident_exact)
    cases.append(
        (
            "coincident exact",
            coincident_exact_env,
            (coincident_exact,),
            "runtime and state directories must be distinct",
        )
    )

    for label, env, unpublished_paths, expected_error in cases:
        started = time.monotonic()
        try:
            completed = subprocess.run(
                [str(daemon)],
                check=False,
                env=env,
                input=b"",
                capture_output=True,
                timeout=5,
            )
        except subprocess.TimeoutExpired as error:
            raise AssertionError(
                f"overlong {label} daemon path reached startup"
            ) from error
        elapsed = time.monotonic() - started
        stderr = completed.stderr.decode(errors="replace")
        if completed.returncode != 77 or expected_error not in stderr:
            raise AssertionError(
                f"overlong {label} daemon path did not fail as configuration: "
                f"rc={completed.returncode} elapsed={elapsed:.3f}s stderr={stderr!r}"
            )
        if any(path.exists() for path in unpublished_paths):
            raise AssertionError(f"overlong {label} daemon path published state")


def run_final_framed_transcript(
    launcher: Path,
    host: str,
    server_id: str,
    line_frames: list[str],
    framed_frame: str,
    timeout_seconds: float = 300,
) -> list[dict[str, object]]:
    """Run line requests followed by one final Content-Length request."""
    env = os.environ.copy()
    env["ANVIL_EMACS_HOST"] = host
    framed_body = framed_frame.encode("utf-8")
    prefix = "".join(f"{frame}\n" for frame in line_frames).encode("utf-8")
    payload = (
        prefix
        + f"Content-Length: {len(framed_body)}\r\n\r\n".encode("ascii")
        + framed_body
    )
    try:
        completed = subprocess.run(
            [str(launcher), f"--server-id={server_id}"],
            check=False,
            env=env,
            input=payload,
            capture_output=True,
            timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired as error:
        raise AssertionError(
            f"{host}/{server_id} framed request timed out after {error.timeout}s"
        ) from error
    if completed.returncode != 0:
        raise AssertionError(
            f"{host}/{server_id} framed request exited {completed.returncode}\n"
            f"stdout:\n{completed.stdout.decode(errors='replace')}\n"
            f"stderr:\n{completed.stderr.decode(errors='replace')}"
        )

    responses: list[dict[str, object]] = []
    output = completed.stdout
    while output:
        if output.lower().startswith(b"content-length:"):
            header, separator, body_and_rest = output.partition(b"\r\n\r\n")
            if not separator:
                raise AssertionError(f"malformed framed response: {output[:200]!r}")
            length = int(header.split(b":", 1)[1].strip())
            body = body_and_rest[:length]
            if len(body) != length:
                raise AssertionError("truncated framed response")
            responses.append(json.loads(body))
            output = body_and_rest[length:]
        else:
            line, separator, output = output.partition(b"\n")
            if not separator:
                raise AssertionError(f"unterminated line response: {line[:200]!r}")
            if line.strip():
                responses.append(json.loads(line))
    return responses


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


def assert_tool_text(response: dict[str, object], expected: str) -> None:
    """Require an exact successful text result."""
    actual = tool_result_text(response)
    if actual != expected:
        raise AssertionError(
            f"tool result differed: expected {expected!r}, received {actual!r}"
        )


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


def parse_pid_response(response: dict[str, object], label: str) -> int:
    """Return one exact decimal PID from an emacs-eval response."""
    text = tool_result_text(response)
    match = re.fullmatch(r"\s*([0-9]+)\s*", text)
    if match is None:
        raise AssertionError(f"{label} returned no exact PID: {text!r}")
    return int(match.group(1))


def decode_shell_result(response: dict[str, object]) -> dict[str, object]:
    """Decode the structured payload returned by shell-run."""
    text = tool_result_text(response)
    try:
        payload = json.loads(text)
    except (TypeError, json.JSONDecodeError) as error:
        raise AssertionError(f"shell-run returned invalid JSON: {text!r}") from error
    if not isinstance(payload, dict):
        raise AssertionError(f"shell-run returned a non-object payload: {payload!r}")
    return payload


def assert_shell_result(
    response: dict[str, object], expected_stdout: str, expected_exit: int = 0
) -> None:
    """Require exact shell-run exit status and untruncated output."""
    payload = decode_shell_result(response)
    exit_status = payload.get("exit")
    truncated = payload.get("truncated")
    if (
        type(exit_status) is not int
        or exit_status != expected_exit
        or payload.get("compressed") != expected_stdout
        or payload.get("stderr") != ""
        or not (truncated is None or truncated is False)
    ):
        raise AssertionError(
            "shell-run result did not match exactly: "
            f"expected exit={expected_exit}, stdout={expected_stdout!r}; "
            f"received {payload!r}"
        )


def assert_shell_prefix(
    response: dict[str, object], expected_prefix: str, expected_exit: int = 0
) -> None:
    """Require exact shell metadata and a specific stdout prefix."""
    payload = decode_shell_result(response)
    exit_status = payload.get("exit")
    stdout = payload.get("compressed")
    truncated = payload.get("truncated")
    if (
        type(exit_status) is not int
        or exit_status != expected_exit
        or not isinstance(stdout, str)
        or not stdout.startswith(expected_prefix)
        or payload.get("stderr") != ""
        or not (truncated is None or truncated is False)
    ):
        raise AssertionError(
            "shell-run prefix contract failed: "
            f"expected exit={expected_exit}, prefix={expected_prefix!r}; "
            f"received {payload!r}"
        )


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


def strict_json_equal(actual: object, expected: object) -> bool:
    """Compare decoded JSON without Python's bool/int equivalence."""
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, list):
        return len(actual) == len(expected) and all(
            strict_json_equal(left, right)
            for left, right in zip(actual, expected, strict=True)
        )
    if isinstance(expected, dict):
        return actual.keys() == expected.keys() and all(
            strict_json_equal(actual[key], value) for key, value in expected.items()
        )
    return actual == expected


def direnv_buffer_expression() -> str:
    """Return Elisp that proves visited buffers retain isolated environments."""
    project_a = Path.home() / "direnv-a"
    project_b = Path.home() / "direnv-b"
    project_c = Path.home() / "direnv-c"
    project_unset = Path.home() / "direnv-unset"
    project_spoof = Path.home() / "direnv-spoof"
    project_failing = Path.home() / "direnv-failing"
    project_a_activation_count = Path.home() / "direnv-a-enter-count"
    file_a = project_a / "visited.txt"
    file_b = project_b / "visited.txt"
    file_c = project_c / "visited.txt"
    file_unset = project_unset / "visited.txt"
    file_spoof = project_spoof / "visited.txt"
    file_failing = project_failing / "visited.txt"
    return f"""
(progn
  (require 'cl-lib)
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
                (or (getenv "ANVIL_DIRENV_MARKER") :false)))
             (launch-audit
              (let ((project-a-bin
                     (directory-file-name
                      (expand-file-name "bin" {json.dumps(str(project_a))}))))
                (cl-labels
                    ((normalize-directory
                      (directory)
                      (and (stringp directory)
                           (directory-file-name
                            (file-truename directory))))
                     (snapshot
                      ()
                      (vector
                       (or (getenv "ANVIL_DIRENV_MARKER") :false)
                       (or (getenv "ANVIL_LAUNCH_SECRET") :false)
                       (or (getenv "ANVIL_LAUNCH_BASELINE") :false)
                       (or (executable-find "anvil-launch-contamination") :false)
                       (or (getenv "DIRENV_DIFF") :false)
                       (cl-count (normalize-directory project-a-bin)
                                 exec-path
                                 :key #'normalize-directory
                                 :test #'equal)
                       default-directory
                       anvil-headless--baseline-default-directory
                       (if (local-variable-p 'process-environment) t :false)
                       (if (local-variable-p 'exec-path) t :false))))
                  (vector
                   (snapshot)
                   (let ((process-environment
                          (default-value 'process-environment))
                         (exec-path (default-value 'exec-path)))
                     (snapshot))
                   (with-temp-buffer (snapshot))
                   (with-current-buffer buffer-a (snapshot))
                   (with-current-buffer buffer-b (snapshot)))))))
        (json-serialize
         (vector row-a row-b row-c row-unset row-spoof row-failing default-marker
                 (and (featurep 'direnv) t)
                 (and (featurep 'exec-path-from-shell) t)
                 (vector anvil-headless-smoke--mode-marker
                         anvil-headless-smoke--mode-executable)
                 (or (executable-find "anvil-login-shell") :false)
                 launch-audit
                 (string-to-number
                  (with-temp-buffer
                    (insert-file-contents
                     {json.dumps(str(project_a_activation_count))})
                    (buffer-string))))))
    (remove-hook 'text-mode-hook #'anvil-headless-smoke--mode-probe)
    (fmakunbound 'anvil-headless-smoke--mode-probe)))
""".strip()


def assert_direnv_buffers(response: dict[str, object], request_directory: Path) -> Path:
    """Validate request context, daemon baseline, and per-buffer direnv isolation."""
    data = decode_eval_json(response)
    if not isinstance(data, list) or len(data) != 13:
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
        launch_audit,
        project_a_activation_count,
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
        if not strict_json_equal(row[4:6], [True, True]):
            raise AssertionError(f"environment is not buffer-local: {row}")
        if resolved_path(row[6], f"{project} active directory") != project.resolve():
            raise AssertionError(f"direnv active directory mismatch: {row}")

    if not isinstance(row_c, list) or len(row_c) != 10:
        raise AssertionError(f"malformed PATH-replacement row: {row_c}")
    expected_c = project_c / "bin" / "anvil-direnv-c"
    if (
        not strict_json_equal(row_c[0:2], ["project-c", "prefix{suffix"])
        or resolved_path(row_c[2], "project-c executable") != expected_c.resolve()
    ):
        raise AssertionError(f"PATH-replacing envrc was not applied: {row_c}")
    emacsclient = resolved_path(row_c[3], "project-c emacsclient")
    resolved_path(row_c[4], "project-c rg")
    if resolved_path(row_c[5], "project-c exec-path head") != emacsclient.parent:
        raise AssertionError(f"dedicated Emacs bin is not first in exec-path: {row_c}")
    if not strict_json_equal(row_c[6:8], [True, True]):
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
            or not strict_json_equal(row[3:5], [True, True])
            or resolved_path(row[5], f"{project} active directory") != project.resolve()
        ):
            raise AssertionError(f"guard state was not restored for {project}: {row}")

    if not isinstance(row_failing, list) or len(row_failing) != 7:
        raise AssertionError(f"malformed failing-direnv row: {row_failing}")
    if not strict_json_equal(row_failing[:4], [False, False, False, False]):
        raise AssertionError(f"failed envrc leaked environment state: {row_failing}")
    if not strict_json_equal(row_failing[4:6], [True, True]) or not isinstance(
        row_failing[6], str
    ):
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

    if not isinstance(launch_audit, list) or len(launch_audit) != 5:
        raise AssertionError(f"malformed launch contamination audit: {launch_audit}")
    root_launch, default_launch, plain_launch, project_a_launch, project_b_launch = (
        launch_audit
    )
    expected_request_directory = request_directory.resolve()
    expected_baseline_directory = (
        Path(os.environ["ANVIL_EMACS_STATE_ROOT"]) / "host-a"
    ).resolve()
    baseline_directory: Path | None = None
    for label, row in (
        ("root", root_launch),
        ("default", default_launch),
        ("no-env", plain_launch),
    ):
        if not isinstance(row, list) or len(row) != 10:
            raise AssertionError(f"malformed {label} launch audit: {row}")
        row_baseline = resolved_path(row[7], f"{label} baseline directory")
        if (
            not row_baseline.is_dir()
            or row_baseline != expected_baseline_directory
            or row_baseline == expected_request_directory
        ):
            raise AssertionError(f"{label} daemon baseline is not the state dir: {row}")
        if baseline_directory is None:
            baseline_directory = row_baseline
        elif row_baseline != baseline_directory:
            raise AssertionError(f"{label} daemon baseline drifted: {row}")
        if (
            not strict_json_equal(
                row[:6], [False, False, "clean-baseline", False, False, 0]
            )
            or resolved_path(row[6], f"{label} request directory")
            != expected_request_directory
            or not strict_json_equal(row[8:10], [False, False])
        ):
            raise AssertionError(
                f"{label} retained the daemon launch environment: {row}"
            )
    if baseline_directory is None:
        raise AssertionError("launch audit did not establish a daemon baseline")

    if (
        not isinstance(project_a_launch, list)
        or len(project_a_launch) != 10
        or not strict_json_equal(
            project_a_launch[:4],
            ["project-a", False, "clean-baseline", False],
        )
        or not isinstance(project_a_launch[4], str)
        or type(project_a_launch[5]) is not int
        or project_a_launch[5] != 1
        or resolved_path(project_a_launch[6], "project-a request directory")
        != project_a.resolve()
        or resolved_path(project_a_launch[7], "project-a baseline directory")
        != baseline_directory
        or not strict_json_equal(project_a_launch[8:10], [True, True])
    ):
        raise AssertionError(
            f"project-a environment was not isolated: {project_a_launch}"
        )
    if type(project_a_activation_count) is not int or project_a_activation_count != 1:
        raise AssertionError(
            f"project-a envrc did not run exactly once: {project_a_activation_count}"
        )
    if (
        not isinstance(project_b_launch, list)
        or len(project_b_launch) != 10
        or not strict_json_equal(
            project_b_launch[:4],
            ["project-b", False, "clean-baseline", False],
        )
        or not isinstance(project_b_launch[4], str)
        or type(project_b_launch[5]) is not int
        or project_b_launch[5] != 0
        or resolved_path(project_b_launch[6], "project-b request directory")
        != project_b.resolve()
        or resolved_path(project_b_launch[7], "project-b baseline directory")
        != baseline_directory
        or not strict_json_equal(project_b_launch[8:10], [True, True])
    ):
        raise AssertionError(
            f"project-b inherited the launch project: {project_b_launch}"
        )

    if not strict_json_equal([has_direnv, has_shell_import], [True, True]):
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

    return baseline_directory


def request_context_expression() -> str:
    """Return a clean root snapshot that distinguishes baseline from client cwd."""
    return r"""
(progn
  (require 'json)
  (json-serialize
   (vector
    default-directory
    anvil-headless--baseline-default-directory
    (or (getenv "ANVIL_LAUNCH_SECRET") :false)
    (or (getenv "ANVIL_LAUNCH_BASELINE") :false)
    (or (executable-find "anvil-launch-contamination") :false)
    (or (getenv "DIRENV_DIFF") :false)
    (if (local-variable-p 'process-environment) t :false)
    (if (local-variable-p 'exec-path) t :false))))
""".strip()


def assert_request_context(
    response: dict[str, object],
    request_directory: Path,
    baseline_directory: Path,
) -> None:
    """Prove client cwd is request-local without contaminating the daemon baseline."""
    snapshot = decode_eval_json(response)
    if (
        not isinstance(snapshot, list)
        or len(snapshot) != 8
        or resolved_path(snapshot[0], "request directory")
        != request_directory.resolve()
        or resolved_path(snapshot[1], "daemon baseline directory")
        != baseline_directory.resolve()
        or not strict_json_equal(
            snapshot[2:8],
            [False, "clean-baseline", False, False, False, False],
        )
    ):
        raise AssertionError(f"request context leaked or lost isolation: {snapshot}")


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
    assert_shell_result(response, expected)


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
            (vector
             (or (getenv "ANVIL_LAUNCH_SECRET") :false)
             (or (getenv "ANVIL_LAUNCH_BASELINE") :false)
             (or (executable-find "anvil-launch-contamination") :false)
             (or (getenv "DIRENV_DIFF") :false)
             default-directory
             (if (local-variable-p 'process-environment) t :false)
             (if (local-variable-p 'exec-path) t :false))
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
        if not isinstance(snapshot, list) or len(snapshot) != 21:
            raise AssertionError(f"malformed {name} snapshot: {snapshot}")
        if snapshot[0] != name:
            raise AssertionError(f"worker dispatch mismatch: {snapshot[0]} != {name}")
        if type(snapshot[1]) is not int or snapshot[1] <= 0:
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
        if not strict_json_equal(snapshot[11:13], [False, False]):
            raise AssertionError(
                f"{name} retained daemon lock-file descriptors: {snapshot[11:13]}"
            )
        if not strict_json_equal(snapshot[13:15], [True, True]):
            raise AssertionError(
                f"{name} did not load direnv environment support: {snapshot[13:15]}"
            )
        launch_state = snapshot[15]
        expected_root_directory = (
            Path(os.environ["ANVIL_EMACS_STATE_ROOT"]) / host
        ).resolve()
        if (
            not isinstance(launch_state, list)
            or len(launch_state) != 7
            or not strict_json_equal(
                launch_state[:4], [False, "clean-baseline", False, False]
            )
            or resolved_path(launch_state[4], f"{name} baseline directory")
            != expected_root_directory
            or not strict_json_equal(launch_state[5:7], [False, False])
        ):
            raise AssertionError(
                f"{name} inherited the daemon launch direnv: {launch_state}"
            )
        expected_project_command = (
            Path.home() / "direnv-spoof" / "bin" / "anvil-direnv-spoof"
        )
        if (
            snapshot[16] != "project-spoof"
            or resolved_path(snapshot[17], f"{name} project executable")
            != expected_project_command.resolve()
        ):
            raise AssertionError(f"{name} did not inherit the project env: {snapshot}")
        if (
            not isinstance(snapshot[18], str)
            or Path(snapshot[18]).name != "emacsclient"
        ):
            raise AssertionError(f"{name} lost emacsclient from PATH: {snapshot}")
        expected_login_command = Path.home() / "login-bin" / "anvil-login-shell"
        if (
            resolved_path(snapshot[19], f"{name} login-shell executable")
            != expected_login_command.resolve()
        ):
            raise AssertionError(f"{name} did not inherit the login PATH: {snapshot}")
        expected_root_socket = (
            Path(os.environ["ANVIL_EMACS_RUNTIME_ROOT"]) / host / "emacs" / "server"
        )
        if (
            resolved_path(snapshot[20], f"{name} root socket")
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
    if not strict_json_equal(snapshot[:2], [False, False]):
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
        or type(snapshot[6]) is not int
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
    if not strict_json_equal(snapshot, expected):
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


def assert_direnv_nonlocal_exit_restores_baseline(
    launcher: Path,
    initialize: dict[str, object],
) -> None:
    """Reject project state after every fallible allow-status boundary."""
    expression = r"""
(progn
  (require 'cl-lib)
  (require 'json)
  (let (rows)
    (dolist (phase '(initial final active))
      (dolist (mode '(quit throw))
        (with-temp-buffer
          (setq default-directory temporary-file-directory)
          (setq-local process-environment
                      (copy-sequence
                       anvil-headless--baseline-process-environment))
          (setq-local exec-path
                      (copy-sequence anvil-headless--baseline-exec-path))
          (setq-local direnv--active-directory nil)
          ;; Start with stale project state so an exit before export is also
          ;; required to restore the immutable baseline.
          (setenv "ANVIL_DIRENV_MARKER" "stale-project")
          (setq-local exec-path '("/stale-project"))
          (setq-local direnv--active-directory
                      (if (eq phase 'active)
                          "/active-project/"
                        "/stale-project/"))
          (let ((status-calls 0)
                (directory "/active-project/")
                outcome)
            (cl-letf
                (((symbol-function 'direnv-update-directory-environment)
                  (lambda (_directory)
                    (setenv "ANVIL_DIRENV_MARKER" "fresh-project")
                    (setq-local exec-path '("/fresh-project"))
                    (setq-local direnv--active-directory
                                "/fresh-project/")))
                 ((symbol-function 'direnv--directory)
                  (lambda () directory))
                 ((symbol-function 'anvil-headless--direnv-allowed-p)
                  (lambda (&rest _args)
                    (setq status-calls (1+ status-calls))
                    (let ((exit-now
                           (or (memq phase '(initial active))
                               (and (eq phase 'final)
                                    (= status-calls 2)))))
                      (if (not exit-now)
                          t
                        (if (eq mode 'quit)
                            (signal 'quit nil)
                          (throw 'anvil-direnv-smoke-exit
                                 "throw-original")))))))
              (setq outcome
                    (if (eq mode 'quit)
                        (condition-case nil
                            (progn
                              (if (eq phase 'active)
                                  (anvil-headless--direnv-update-current-buffer)
                                (anvil-headless--apply-direnv-if-allowed
                                 directory t))
                              "returned")
                          (quit "quit-original"))
                      (catch 'anvil-direnv-smoke-exit
                        (if (eq phase 'active)
                            (anvil-headless--direnv-update-current-buffer)
                          (anvil-headless--apply-direnv-if-allowed
                           directory t))
                        "returned"))))
            (push
             (vector
              (format "%s-%s" phase mode)
              outcome
              status-calls
              (or (getenv "ANVIL_DIRENV_MARKER") :false)
              (or direnv--active-directory :false)
              (equal exec-path anvil-headless--baseline-exec-path)
              (equal process-environment
                     anvil-headless--baseline-process-environment))
             rows)))))
    (dolist (phase '(missing remote discovery-quit discovery-throw))
      (with-temp-buffer
        (setq default-directory temporary-file-directory)
        (setq-local process-environment
                    (copy-sequence
                     anvil-headless--baseline-process-environment))
        (setq-local exec-path '("/stale-discovery"))
        (setq-local direnv--active-directory "/stale-discovery/")
        (setenv "ANVIL_DIRENV_MARKER" "stale-discovery")
        (let (outcome)
          (cl-letf
              (((symbol-function 'direnv--directory)
                (lambda ()
                  (pcase phase
                    ('missing nil)
                    ('remote "/ssh:example:/project/")
                    ('discovery-quit (signal 'quit nil))
                    ('discovery-throw
                     (throw 'anvil-direnv-smoke-exit
                            "throw-original"))))))
            (setq outcome
                  (pcase phase
                    ('discovery-quit
                     (condition-case nil
                         (progn
                           (anvil-headless--direnv-update-current-buffer)
                           "returned")
                       (quit "quit-original")))
                    ('discovery-throw
                     (catch 'anvil-direnv-smoke-exit
                       (anvil-headless--direnv-update-current-buffer)
                       "returned"))
                    (_
                     (anvil-headless--direnv-update-current-buffer)
                     "returned"))))
          (push
           (vector
            (symbol-name phase)
            outcome
            0
            (or (getenv "ANVIL_DIRENV_MARKER") :false)
            (or direnv--active-directory :false)
            (equal exec-path anvil-headless--baseline-exec-path)
            (equal process-environment
                   anvil-headless--baseline-process-environment))
           rows))))
    (json-serialize (vconcat (nreverse rows)))))
""".strip()
    result = decode_eval_json(
        call_tool(
            launcher,
            initialize,
            "emacs-eval",
            {"expression": expression},
            timeout_seconds=10,
        )
    )
    expected = [
        ["initial-quit", "quit-original", 1, False, False, True, True],
        ["initial-throw", "throw-original", 1, False, False, True, True],
        ["final-quit", "quit-original", 2, False, False, True, True],
        ["final-throw", "throw-original", 2, False, False, True, True],
        ["active-quit", "quit-original", 1, False, False, True, True],
        ["active-throw", "throw-original", 1, False, False, True, True],
        ["missing", "returned", 0, False, False, True, True],
        ["remote", "returned", 0, False, False, True, True],
        ["discovery-quit", "quit-original", 0, False, False, True, True],
        ["discovery-throw", "throw-original", 0, False, False, True, True],
    ]
    if not strict_json_equal(result, expected):
        raise AssertionError(
            f"direnv nonlocal exit retained project state: {result} != {expected}"
        )


def assert_slow_direnv_keeps_root_responsive(
    launcher: Path,
    initialize: dict[str, object],
) -> None:
    """Exercise the direct helper and real shell route while each is blocked."""
    project = (Path.home() / "direnv-slow").resolve()
    arm = Path.home() / "direnv-slow-arm"
    started = Path.home() / "direnv-slow-started"
    callback_seen = Path.home() / "direnv-slow-callback"
    release = Path.home() / "direnv-slow-release"

    def reset_gate() -> None:
        for marker in (arm, started, callback_seen, release):
            marker.unlink(missing_ok=True)

    def wait_for(marker: Path, future: object, label: str) -> None:
        deadline = time.monotonic() + 10
        while not marker.exists() and time.monotonic() < deadline:
            if future.done():  # type: ignore[attr-defined]
                future.result()  # type: ignore[attr-defined]
                raise AssertionError(f"{label} returned before {marker.name}")
            time.sleep(0.01)
        if not marker.exists():
            raise AssertionError(f"{label} never created {marker.name}")

    fast_expression = """
(progn
  (require 'json)
  (let ((canary (concat "direnv-secret-" "canary"))
        exposed)
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (save-restriction
          (widen)
          (when (string-match-p (regexp-quote canary) (buffer-string))
            (setq exposed t)))))
    (json-serialize
     (vector
      (emacs-pid)
      default-directory
      (or (getenv "ANVIL_DIRENV_MARKER") :false)
      (or (getenv "ANVIL_DIRENV_SECRET") :false)
      (or (getenv "DIRENV_DIFF") :false)
      (car exec-path)
      (if exposed t :false)))))
""".strip()

    direct_expression = f"""
(progn
  (require 'json)
  (let (timer callback)
    (unwind-protect
        (with-temp-buffer
          (setq default-directory {json.dumps(str(project) + os.sep)})
          (setq-local process-environment
                      (copy-sequence
                       anvil-headless--baseline-process-environment))
          (setq-local exec-path
                      (copy-sequence anvil-headless--baseline-exec-path))
          (setq-local direnv--active-directory nil)
          (setq timer
                (run-at-time
                 0.01 0.01
                 (lambda ()
                   ;; The initial direnv status call may yield too.  Record
                   ;; responsiveness only after the fixture's slow export has
                   ;; entered its release gate.
                   (when (file-exists-p {json.dumps(str(started))})
                     (setq callback
                           (vector
                            default-directory
                            (or (getenv "ANVIL_DIRENV_MARKER") :false)
                            (or (getenv "ANVIL_DIRENV_SECRET") :false)
                            (or (getenv "DIRENV_DIFF") :false)
                            (car exec-path)
                            t))
                     (write-region
                      "" nil {json.dumps(str(callback_seen))} nil 'silent)
                     (when (timerp timer)
                       (cancel-timer timer))))))
          (anvil-headless--apply-direnv-if-allowed default-directory t)
          (json-serialize
           (vector
            (emacs-pid)
            (or (getenv "ANVIL_DIRENV_MARKER") :false)
            (or (getenv "ANVIL_DIRENV_SECRET") :false)
            default-directory
            (or callback :false))))
      (when (timerp timer)
        (cancel-timer timer)))))
""".strip()

    reset_gate()
    arm.touch()
    try:
        with ThreadPoolExecutor(max_workers=1) as executor:
            slow = executor.submit(
                call_tool,
                launcher,
                initialize,
                "emacs-eval",
                {"expression": direct_expression},
                30,
            )
            try:
                wait_for(started, slow, "direct direnv helper")
                wait_for(callback_seen, slow, "direct direnv callback")
                fast = decode_eval_json(
                    call_tool(
                        launcher,
                        initialize,
                        "emacs-eval",
                        {"expression": fast_expression},
                        timeout_seconds=10,
                    )
                )
                if slow.done():
                    raise AssertionError(
                        "direct direnv helper returned before its release gate"
                    )
            finally:
                release.touch()
            direct = decode_eval_json(slow.result(timeout=15))
            post_direct = decode_eval_json(
                call_tool(
                    launcher,
                    initialize,
                    "emacs-eval",
                    {"expression": fast_expression},
                    timeout_seconds=10,
                )
            )
    finally:
        reset_gate()

    if (
        not isinstance(fast, list)
        or len(fast) != 7
        or not isinstance(post_direct, list)
        or len(post_direct) != 7
        or not isinstance(direct, list)
        or len(direct) != 5
    ):
        raise AssertionError(
            "invalid direct direnv snapshots: "
            f"fast={fast}, post={post_direct}, direct={direct}"
        )
    root_pid, root_directory, *root_state = fast
    direct_pid, marker, secret, project_directory, callback = direct
    if direct_pid != root_pid:
        raise AssertionError(
            f"direct helper changed root Emacs: {direct_pid} != {root_pid}"
        )
    if marker != "project-slow" or secret != "direnv-secret-canary":
        raise AssertionError(f"direct helper missed project env: {direct}")
    if Path(project_directory).resolve() != project:
        raise AssertionError(f"direct helper used wrong directory: {direct}")
    if (
        not strict_json_equal(root_state[0:3], [False, False, False])
        or root_state[4] is not False
    ):
        raise AssertionError(f"project state or output leaked into root: {fast}")
    if (
        post_direct[0] != root_pid
        or not strict_json_equal(post_direct[2:5], [False, False, False])
        or post_direct[6] is not False
    ):
        raise AssertionError(
            f"project state or decoded output leaked after release: {post_direct}"
        )
    if not isinstance(callback, list) or len(callback) != 6:
        raise AssertionError(f"responsive callback did not run: {callback}")
    expected_callback = [
        root_directory,
        root_state[0],
        root_state[1],
        root_state[2],
        root_state[3],
        True,
    ]
    if not strict_json_equal(callback, expected_callback):
        raise AssertionError(
            f"responsive callback inherited project state: {callback} "
            f"!= {expected_callback}"
        )

    reset_gate()
    arm.touch()
    try:
        with ThreadPoolExecutor(max_workers=1) as executor:
            slow_shell = executor.submit(
                call_tool,
                launcher,
                initialize,
                "shell-run",
                {
                    "cmd": (
                        "printf '%s:%s' "
                        '"$ANVIL_DIRENV_MARKER" "$ANVIL_HEADLESS_PARENT_PID"'
                    ),
                    "filter": "",
                    "cwd": str(project),
                },
                30,
            )
            try:
                wait_for(started, slow_shell, "shell-run direnv helper")
                shell_fast = decode_eval_json(
                    call_tool(
                        launcher,
                        initialize,
                        "emacs-eval",
                        {"expression": fast_expression},
                        timeout_seconds=10,
                    )
                )
                if slow_shell.done():
                    raise AssertionError(
                        "shell-run returned before its direnv release gate"
                    )
            finally:
                release.touch()
            shell_response = slow_shell.result(timeout=15)
            shell_after = decode_eval_json(
                call_tool(
                    launcher,
                    initialize,
                    "emacs-eval",
                    {"expression": fast_expression},
                    timeout_seconds=10,
                )
            )
    finally:
        reset_gate()

    if (
        not isinstance(shell_fast, list)
        or len(shell_fast) != 7
        or shell_fast[0] != root_pid
        or not strict_json_equal(shell_fast[2:5], [False, False, False])
        or shell_fast[6] is not False
    ):
        raise AssertionError(
            f"shell overlap leaked project state or output: {shell_fast}"
        )
    if (
        not isinstance(shell_after, list)
        or len(shell_after) != 7
        or shell_after[0] != root_pid
        or not strict_json_equal(shell_after[2:5], [False, False, False])
        or shell_after[6] is not False
    ):
        raise AssertionError(f"shell direnv output leaked after release: {shell_after}")
    assert_shell_result(shell_response, f"project-slow:{root_pid}")


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
    match = re.fullmatch(r"Job started: (job-[0-9]+-[0-9]+)\s*", text)
    if match is None:
        raise AssertionError(f"async submission returned no exact job ID: {text}")
    return match.group(1)


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
        if last.startswith("status: done\n") or last.startswith("status: error\n"):
            return last
        time.sleep(0.1)
    raise AssertionError(f"async job {job_id} did not settle: {last}")


def decode_done_async_json(result: str) -> object:
    """Decode one JSON value from a terminal asynchronous result."""
    if not result.startswith("status: done\n"):
        raise AssertionError(f"async job did not finish successfully: {result}")
    matches = re.findall(r"(?m)^result: (.*)$", result)
    if len(matches) != 1:
        raise AssertionError(f"async job returned no unique result: {result}")
    try:
        serialized = json.loads(matches[0])
        return json.loads(serialized)
    except (TypeError, json.JSONDecodeError) as error:
        raise AssertionError(f"async job returned invalid JSON: {result}") from error


def assert_offload_launch_baseline(
    launcher: Path,
    initialize: dict[str, object],
) -> None:
    """Prove a fresh isolated child starts outside the launch project."""
    expected_login = (Path.home() / "login-bin" / "anvil-login-shell").resolve()
    expression = f"""
(progn
  (require 'json)
  (let ((login (executable-find "anvil-login-shell")))
    (when (or (getenv "ANVIL_LAUNCH_SECRET")
              (not (equal (getenv "ANVIL_LAUNCH_BASELINE") "clean-baseline"))
              (executable-find "anvil-launch-contamination")
              (getenv "DIRENV_DIFF")
              (local-variable-p 'process-environment)
              (local-variable-p 'exec-path)
              (not (and login
                        (equal (file-truename login)
                               {json.dumps(str(expected_login))}))))
      (error "offload launch environment is contaminated"))
    (json-serialize
     (vector "clean-offload" default-directory login))))
""".strip()
    job_id = submit_async(launcher, initialize, expression, 10)
    result = decode_done_async_json(poll_async(launcher, initialize, job_id, 15))
    expected_directory = (
        Path(os.environ["ANVIL_EMACS_STATE_ROOT"]) / "host-a"
    ).resolve()
    if (
        not isinstance(result, list)
        or len(result) != 3
        or result[0] != "clean-offload"
        or resolved_path(result[1], "offload default directory") != expected_directory
        or resolved_path(result[2], "offload login executable") != expected_login
    ):
        raise AssertionError(f"offload inherited the launch project: {result}")


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

    root_pid = parse_pid_response(
        call_tool(
            launcher,
            initialize,
            "emacs-eval",
            {"expression": "(emacs-pid)"},
            timeout_seconds=5,
        ),
        "root Emacs",
    )
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
    if not terminal.startswith("status: error\n") or "timeout" not in terminal.lower():
        raise AssertionError(f"looping async job did not time out: {terminal}")

    death_deadline = time.monotonic() + 5
    while process_alive(child_pid) and time.monotonic() < death_deadline:
        time.sleep(0.05)
    if process_alive(child_pid):
        raise AssertionError(f"timed-out async child {child_pid} survived")

    root_after = parse_pid_response(
        call_tool(
            launcher,
            initialize,
            "emacs-eval",
            {"expression": "(emacs-pid)"},
            timeout_seconds=5,
        ),
        "root Emacs after async timeout",
    )
    if root_after != root_pid:
        raise AssertionError(
            f"root daemon changed after async timeout: {root_pid} -> {root_after}"
        )

    project_file = Path.home() / "direnv-a" / "visited.txt"
    environment_expression = f"""
(progn
  (require 'json)
  (with-current-buffer
      (find-file-noselect {json.dumps(str(project_file))})
    (json-serialize
     (vector
      (or (getenv "ANVIL_DIRENV_MARKER") :false)
      (or (executable-find "anvil-direnv-a") :false)))))
""".strip()
    environment_timeout = 10
    environment_job = submit_async(
        launcher,
        initialize,
        environment_expression,
        environment_timeout,
    )
    environment_result = decode_done_async_json(
        poll_async(
            launcher,
            initialize,
            environment_job,
            environment_timeout + 5,
        )
    )
    expected_executable = (project_file.parent / "bin" / "anvil-direnv-a").resolve()
    if (
        not isinstance(environment_result, list)
        or len(environment_result) != 2
        or environment_result[0] != "project-a"
        or resolved_path(environment_result[1], "async project executable")
        != expected_executable
    ):
        raise AssertionError(
            f"isolated async child lost the project environment: {environment_result}"
        )


def main() -> None:
    if (
        len(sys.argv) != 6
        or not sys.argv[4].isdigit()
        or int(sys.argv[4]) <= 0
        or not sys.argv[5].isdigit()
        or int(sys.argv[5]) <= 0
    ):
        raise SystemExit(
            "usage: headless-smoke.py /path/to/anvil-mcp "
            "/path/to/anvil-mcp-inner WORKER_SPECS_JSON "
            "CLIENT_TOOL_SECONDS HOST_SHELL_SECONDS"
        )

    launcher = Path(sys.argv[1]).resolve()
    per_agent_launcher = Path(os.environ["ANVIL_PER_AGENT_LAUNCHER"]).resolve()
    headless_daemon = Path(os.environ["ANVIL_HEADLESS_DAEMON"]).resolve()
    assert_overlong_explicit_socket_fails_fast(launcher)
    assert_overlong_socket_path_fails_fast(launcher)
    assert_overlong_socket_path_fails_fast(per_agent_launcher)
    assert_overlong_daemon_socket_paths_fail_fast(headless_daemon)
    inner_launcher = Path(sys.argv[2]).resolve()
    worker_specs = parse_worker_specs(sys.argv[3])
    client_tool_seconds = float(sys.argv[4])
    host_shell_seconds = int(sys.argv[5])
    org_root = Path.home() / "org"
    org_file = org_root / "smoke.org"
    initialize = {
        "protocolVersion": "2025-03-26",
        "capabilities": {},
        "clientInfo": {"name": "nix-headless-smoke", "version": "1"},
    }
    snapshot_expression = worker_snapshot_expression(worker_specs)
    buffer_environment_expression = direnv_buffer_expression()
    request_context = request_context_expression()
    spawn_environment_expression = spawn_baseline_expression()
    watchdog_expression = watchdog_lease_expression()
    launch_directory = Path.home() / "direnv-launch"
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
                25,
                "tools/call",
                {
                    "name": "file-read",
                    "arguments": {"path": str(inner_launcher)},
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
                            "printf '%s:%s:%s:%s:%s:%s' "
                            '"${ANVIL_DIRENV_MARKER-unset}" '
                            '"${ANVIL_LAUNCH_SECRET-unset}" '
                            '"${ANVIL_LAUNCH_BASELINE-unset}" '
                            '"$(command -v anvil-launch-contamination || printf missing)" '
                            '"$(command -v anvil-direnv-a || printf missing)" '
                            '"$(command -v anvil-login-shell || printf missing)"'
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
                        "cmd": "cat >/dev/null && printf stdin-eof",
                        "filter": "",
                        "cwd": str(project_plain),
                        "timeout_sec": 5,
                    },
                },
            ),
            request(
                24,
                "tools/call",
                {
                    "name": "nelisp-eval",
                    "arguments": {"expression": "(+ 20 22)"},
                },
            ),
            request(
                27,
                "tools/call",
                {
                    "name": "shell-run",
                    "arguments": {
                        "cmd": (
                            "printf '%s:%s:%s:%s' \"$(pwd -P)\" "
                            '"$ANVIL_LAUNCH_SECRET" "$ANVIL_LAUNCH_BASELINE" '
                            '"$(anvil-launch-contamination)"'
                        ),
                        "filter": "",
                    },
                },
            ),
        ],
        cwd=launch_directory,
    )
    main_names = tool_names(response_by_id(main_responses, 2))
    expected_tools = EVAL_IDE_TOOLS | TYPED_TOOLS
    if main_names != expected_tools:
        raise AssertionError(
            "unexpected unified main surface: "
            f"missing={sorted(expected_tools - main_names)}, "
            f"unexpected={sorted(main_names - expected_tools)}"
        )
    assert_tool_text(response_by_id(main_responses, 3), "42")
    assert_tool_success(response_by_id(main_responses, 4), "anvil-clean-environment.py")
    assert_tool_success(response_by_id(main_responses, 25), "server_id=anvil")
    assert_tool_success(response_by_id(main_responses, 5), "headlessorgneedle")
    assert_tool_success(response_by_id(main_responses, 6), ":files")
    assert_tool_success(response_by_id(main_responses, 7), "headlesssemanticneedle")
    assert_worker_snapshot(response_by_id(main_responses, 8), "host-a", worker_specs)
    baseline_directory = assert_direnv_buffers(
        response_by_id(main_responses, 9), launch_directory
    )
    assert_shell_result(
        response_by_id(main_responses, 10), "project-a:project-a-command"
    )
    assert_shell_result(
        response_by_id(main_responses, 11), "project-b:project-b-command"
    )
    expected_login_shell = (Path.home() / "login-bin" / "anvil-login-shell").resolve()
    assert_shell_result(
        response_by_id(main_responses, 12),
        f"unset:unset:clean-baseline:missing:missing:{expected_login_shell}",
    )
    assert_tool_success(
        response_by_id(main_responses, 13), ".anvil-headless-emacs.lock"
    )
    assert_tool_success(
        response_by_id(main_responses, 14), ".anvil-headless-emacs.lock"
    )
    assert_shell_result(response_by_id(main_responses, 15), "lock-fds-closed")
    assert_shell_prefix(
        response_by_id(main_responses, 16),
        "project-c:prefix{suffix:project-c-command:ripgrep",
    )
    assert_shell_result(
        response_by_id(main_responses, 17),
        "unset:unset:unset:unset:unset:blocked-command",
    )
    assert_spawn_baseline(response_by_id(main_responses, 18), "host-a")
    assert_watchdog_lease(response_by_id(main_responses, 19), watchdog_lease)
    assert_tool_failure(response_by_id(main_responses, 20), "direnv environment failed")
    assert_tool_text(response_by_id(main_responses, 21), str(host_shell_seconds))
    assert_shell_result(response_by_id(main_responses, 22), "pathless-rg:1")
    assert_shell_result(response_by_id(main_responses, 23), "stdin-eof")
    assert_tool_text(response_by_id(main_responses, 24), "42")
    assert_shell_result(
        response_by_id(main_responses, 27),
        f"{launch_directory.resolve()}:direnv-launch-secret-canary:"
        "launch-overwrite:launch-contamination-command",
    )
    if failing_shell_marker.exists():
        raise AssertionError("shell-run executed after an allowed envrc failed")
    for identifier in (10, 11, 16, 17):
        assert_tool_omits(response_by_id(main_responses, identifier), "direnv:")

    context_frames = [
        request(1, "initialize", initialize),
        request(None, "notifications/initialized"),
        request(
            2,
            "tools/call",
            {
                "name": "emacs-eval",
                "arguments": {"expression": request_context},
            },
        ),
    ]
    other_context = run_transcript(
        launcher,
        "host-a",
        "anvil",
        context_frames,
        client_tool_seconds,
        cwd=project_plain,
    )
    assert_request_context(
        response_by_id(other_context, 2), project_plain, baseline_directory
    )
    restored_context = run_transcript(
        launcher,
        "host-a",
        "anvil",
        context_frames,
        client_tool_seconds,
        cwd=launch_directory,
    )
    assert_request_context(
        response_by_id(restored_context, 2), launch_directory, baseline_directory
    )

    large_expression = '(length "雪' + ("x" * (512 * 1024)) + '")'
    large_responses = run_final_framed_transcript(
        launcher,
        "host-a",
        "anvil",
        [
            request(25, "initialize", initialize),
            request(None, "notifications/initialized"),
        ],
        request(
            26,
            "tools/call",
            {
                "name": "emacs-eval",
                "arguments": {"expression": large_expression},
            },
        ),
    )
    assert_tool_text(response_by_id(large_responses, 26), "524289")

    assert_offload_launch_baseline(launcher, initialize)
    assert_async_isolation(
        launcher,
        initialize,
        watchdog_lease,
    )
    assert_direnv_nonlocal_exit_restores_baseline(launcher, initialize)
    assert_slow_direnv_keeps_root_responsive(launcher, initialize)

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
