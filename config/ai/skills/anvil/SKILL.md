---
name: anvil
description: Use the available Anvil MCP backend — interactive Emacs, dedicated headless
  Emacs, or NeLisp — for structured file, Org, Git, data, and Elisp work. Detect the
  advertised capabilities, prefer typed and token-efficient operations, and apply
  live-session safety only where the backend actually reaches the user's interactive
  Emacs.
---
# Anvil — the Emacs and NeLisp workbench

Anvil is deployed through one stable primary MCP registration, but its local
backend varies:

- **Interactive Emacs** — 13 primary eval/navigation tools. This backend
  reaches the user's development Emacs.
- **Dedicated Emacs** — a separate headless process with 76 direct typed tools;
  those tools are mirrored into the primary registry, yielding 89 unique
  primary tools. Its buffers, workers, sockets, and mutable state are isolated
  from the development Emacs.
- **NeLisp** — an Emacs-free 42-tool standalone registry for host, file, data,
  and shell operations. It has no `emacs-eval`, Org engine, or live buffers.

Clients register one MCP server named `anvil`. The former `anvil-tools`
sibling is a disabled promptdeploy migration tombstone and must not be used.
See `references/tools.md` for the backend manifests and tool guide; always use
advertised bare tool names rather than assuming every backend has every tool.

## Availability gate

Apply this skill when any Anvil tools are advertised; do not require an
Emacs-only tool before using NeLisp. Identify the backend from capabilities:

- `emacs-eval` present: Emacs-backed. Probe with `(emacs-version)`, then
  evaluate `(getenv "ANVIL_EMACS_STATE_DIR")`: a non-empty value identifies
  the dedicated daemon, as does an 89-tool unified primary surface. An unset
  value with a 13-tool primary surface identifies the interactive backend.
  If the distinction remains ambiguous, do not claim
  that modified-buffer checks cover the user's development Emacs.
- `emacs-eval` absent but `file-exists-p` or `anvil-host-info` present:
  NeLisp. Probe with a read-only file or host call that is actually advertised.
- Neither surface present: state that Anvil is unavailable on this host and
  use standard tools.
- A transport failure is temporary. Apply the bounded recovery policy below
  before falling back; do not convert one failed probe into a session-wide
  disable.

If `emacs-eval` works but an advertised typed tool reports "No active MCP
server", report the incomplete Emacs initialization rather than silently
working around it.

## Failure classification and bounded recovery

Classify the failure before choosing a fallback:

- An operation timeout is not a transport failure. In particular,
  `anvil-host: shell timeout after Ns` means only that the invoked command
  exceeded its own limit. Narrow that operation or use the authorized native
  fallback, then continue using Anvil for other supported operations.
- For a connection, transport, or readiness failure, perform exactly one
  bounded read-only liveness reprobe. Use `(emacs-version)` when
  `emacs-eval` is advertised; otherwise use an advertised read-only NeLisp
  host or file probe. Do not poll indefinitely.
- Retry the original request only if the failure explicitly reports
  `dispatched: false`, or if the original request is read-only. Never replay
  a mutating request when its dispatch or result is ambiguous; inspect its
  postcondition or ask before taking another write action.
- If the liveness reprobe also fails, use standard tools for the current
  operation and record that Anvil is temporarily unavailable. Do not disable
  Anvil for the rest of the session. Reprobe at the next mandatory Anvil
  checkpoint or after ten minutes, whichever comes first. Resume typed Anvil
  operations as soon as a probe succeeds.

## Core rules

1. **Use the most specific advertised tool.** Prefer schema-checked typed
   operations; use `emacs-eval` only when it exists and no typed tool covers
   the operation.
2. **Never read a whole file to answer a structural question.** Use the
   layered read surface when the backend advertises it.
3. **Batch edits when supported.** Use `file-batch` /
   `file-batch-across` on Emacs-backed surfaces; NeLisp has a smaller file
   API, so use its available operations directly.
4. **Respect the backend boundary.** Interactive Emacs is the user's live
   session. Dedicated Emacs is isolated. NeLisp has no Emacs state.

## Reading efficiently (progressive disclosure)

On an Emacs typed surface, work down the layers and stop as soon as the
question is answered. NeLisp exposes `file-read` but not every progressive
disclosure tool, so never invent a missing layer:

1. `file-outline` — structural outline without the body (headings, defuns,
   sections; format inferred). Answers "what is in this file / where is X".
2. `file-read` with `offset`/`limit` pagination — just the region
   that matters. For org files prefer `org-read-headline` / `org-read-by-id`
   (subtree only) over reading the file.
3. `file-read-delta` for files read earlier in the session — a byte-identical
   re-read returns just the unchanged-hash marker instead of full content.
   Use it when re-checking a file after edits elsewhere.

For git state, use the structured queries (`git-status`, `git-log`,
`git-diff-names`, `git-diff-stats`, `git-repo-root`, `git-worktree-list`)
instead of shelling out and parsing porcelain output.

## Editing efficiently

Use only operations advertised by the active backend. The richer batch,
regexp, import, and structured-edit guidance below applies to Emacs-backed
typed surfaces; NeLisp provides a smaller literal file/data API.

- Single literal change: `file-replace-string`. Regexp change:
  `file-replace-regexp` (Emacs regexp syntax — `\\(...\\)` groups, `\\1`
  in replacements — not PCRE).
- New file: `file-create` (one call, errors if the file exists unless
  overwrite is set). Append: `file-append`. Positional: `file-insert-at-line`,
  `file-delete-lines` (1-indexed).
- **Multiple edits to one file: `file-batch`** — the whole edit plan in one
  call. **Multiple files: `file-batch-across`.** These are the
  token-efficient workhorses; default to them for any multi-step edit.
- Imports/headers: `file-ensure-import` (idempotent, no-op when present).
- JSON: `json-object-add` for bulk key additions preserving formatting;
  `data-get-path` / `data-set-path` / `data-delete-path` / `data-list-keys`
  for dotted-path access. The mutating data tools have a preview/apply
  contract — preview first, then apply, for anything destructive.
- All file tools operate on disk via temp buffers: no live-buffer side
  effects, no auto-revert disruption, safe on files over 1.2 MB. The
  flip side: they do NOT see unsaved buffer edits (see safety rules).

Verify edits from the return plist (e.g. `(:replaced 3 ...)`) — a count of
0 means the pattern missed; re-read the region rather than re-firing blind.

## Org-mode work

Org tools require an Emacs-backed backend. Dedicated Emacs configures
`~/org` as its agenda and semantic root and permits explicit Org paths;
NeLisp has no Org engine. On an interactive backend, files may be gated by
an allowlist — check `org-get-allowed-files` when a call errors on access.

- Discover: `org-read-outline` (hierarchy as JSON), then `org-read-headline`
  (subtree by path) or `org-read-by-id` (stable across refiles; prefer IDs
  once known).
- Mutate: `org-update-todo-state`, `org-add-todo`, `org-rename-headline`,
  `org-edit-body` (partial string replacement within a headline's body).
  These preserve structure, properties, and tags, and mint org IDs —
  always prefer them over textual edits to org files.
- Capture: `org-capture-string` drives the user's own capture templates.
- Query: `org-agenda-view` renders a real agenda buffer (same engine the
  user sees); `org-habit-summary` for habit state;
  `org-get-todo-config` / `org-get-tag-config` before constructing TODO
  states or tags by hand.

## Emacs-backed eval — the conditional escape hatch

This section applies only when `emacs-eval` is advertised. NeLisp tools
must be used directly and must not be preceded by an Emacs probe.

- `emacs-eval` for anything under ~30 s: query variables, call functions,
  inspect buffers, drive packages. Return values print as Elisp data —
  shape results with `format`/`prin1-to-string` or return plists for easy
  parsing.
- Anything potentially slow (byte-compile, package ops, network, large
  searches): `emacs-eval-async` → poll `emacs-eval-result` with the job ID;
  `emacs-eval-jobs` to list/debug. Do not run slow forms through the
  synchronous tool — it blocks the user's editor.
- `nelisp-eval` is a stateful pure-Elisp scratch REPL isolated from the
  session's globals (reset with `nelisp-eval-reset`) — use it for Elisp
  experiments that should not touch the user's state.
- Worker pool: `anvil-worker-probe` shows per-lane worker health;
  `anvil-worker-reset-pool` recovers a stuck pool. Probe before assuming
  async infrastructure is broken.
- `metrics-token-report` reports per-tool payload telemetry — use it when
  asked to audit or tune MCP token usage.

## Backend safety (overrides all of the above)

Modified-buffer checks protect user work only when the backend reaches the
interactive Emacs. A dedicated daemon or NeLisp cannot prove that another
Emacs process has no unsaved copy; state that boundary instead of presenting
its empty buffer list as evidence.

- An interactive session belongs to the user. Never kill buffers you did not
  create, never `save-buffers-kill-emacs`, and never toggle global modes or
  mutate user configuration unless that is the task.
- Before disk-editing a file through interactive Emacs, check
  `(let ((b (find-buffer-visiting FILE))) (and b (buffer-modified-p b)))`.
  If modified, do not edit the file on disk; operate on the live buffer or
  ask. On dedicated/NeLisp backends, do not claim this check covers a separate
  interactive editor.
- Keep synchronous eval short; route heavy work through async or workers.
- Prefer read-only forms when only reading: don't "query" with mutating
  functions.
- Preview before apply on the `data-*` mutating tools; state what changed
  after applying.
- Results containing user data (buffers, agendas, journals) may be
  personal — quote only what the task needs.

## When NOT to use anvil

- The host advertises no Anvil tools, or its transport remains unavailable
  after the bounded recovery probe. Treat the latter as temporary and reprobe
  on the schedule above.
- The requested operation requires Emacs-only capabilities but the active
  backend is NeLisp; explain the boundary and use an authorized fallback.
- Long-lived shell processes (servers, watchers) — no Anvil backend is a
  process supervisor.

## Anvil Checkpoints

These checkpoints remain mandatory. On dedicated Emacs or NeLisp, explicitly
record that their buffer view cannot cover a separate interactive Emacs.

1. Session start: probe Anvil, check modified Emacs buffers, and inspect git status.
2. Before every edit batch: check modified buffers and name files to be edited.
3. After every edit batch: inspect changed files and git diff through Anvil.
4. Before committing: recheck modified buffers, status, and diff.
5. After interruption/resume: repeat the session-start checkpoint.
6. Use shell/apply_patch only where required; state the reason for fallback.
