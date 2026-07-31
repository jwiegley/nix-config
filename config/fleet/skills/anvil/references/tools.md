# Anvil tool catalog

Backend-aware reference for the Anvil MCP surfaces, checked against the live
interactive server and the reproducible dedicated/NeLisp manifests on
2026-07-11. Promptdeploy registers only the primary server named `anvil`:
interactive Emacs exposes 13 primary tools, dedicated Emacs exposes 89 unified
primary tools (including 76 typed tools), and NeLisp exposes a 42-tool
standalone surface. The legacy split typed registration is retired. Client
prefixes vary; bare names are used here.

## Primary server `anvil`

### emacs-eval
Evaluate Emacs Lisp synchronously in the active Emacs backend and return the
printed result. For quick operations (< 30s): querying state, small edits,
reading data. Param: `expression` (string).

### emacs-eval-async
Evaluate Emacs Lisp asynchronously; returns a job ID immediately and Emacs
stays responsive. For long-running work: byte-compile, package installs,
network fetches. Param: `expression` (string).

### emacs-eval-result
Fetch an async job's status and result: running/done/error, age, queue wait,
runtime. Poll until done or error. Param: `job-id` (string).

### emacs-eval-jobs
List all async jobs and statuses; use to find stuck jobs. No params.

### nelisp-eval
Stateful pure-Elisp REPL (NeLisp evaluator, isolated from the live session's
globals but persistent across calls). Param: `expression` (string).

### nelisp-eval-reset
Reset the NeLisp REPL state. No params.

The Emacs-backed primary registry also includes `diagnostics`,
`imenu_list_symbols`, `project_info`, `treesit_info`,
`xref_find_apropos`, and `xref_find_references`. Dedicated mode additionally
mirrors every typed tool below into this registry.

## Emacs typed tools (unified in dedicated primary mode)


### Reading files

**file-outline** — Layer 1 of anvil progressive disclosure (see `disclosure-help`). Return a compact structural outline of a file without reading its body. Infers format from extension (.el / .org / .md) or accepts a format= override. Emits (:kind :name :line) entries for Elisp def-forms, org headlines, or Markdown headings. Use this FIRST to orient in large files before deciding whether to escalate to Layer 2 (`file-read-snippet`) or Layer 3 (`file-read`). Tool descriptions and disclosure-help cover the full contract.

*Params:* `path`, `format?`

**file-read** — Layer 3 of anvil progressive disclosure (see `disclosure-help`). Read file contents with optional line-based pagination. Accepts either a plain absolute path or a `file://PATH[#L<start>[-<end>]]` citation URI emitted by Layer 1 (`file-outline`) / Layer 2 (`file-read-snippet`) — the URI's line range becomes the default offset/limit. Returns the file content as a string. For large files, use `file-read-snippet` (Layer 2) or pass offset/limit to read specific sections.

*Params:* `path`, `offset?`, `limit?`

**file-read-delta** — Read a whole file through a session baseline cache optimized for re-reads. First read returns full content plus a SHA1 hash. A byte- identical re-read returns only mode/hash/size. A small edit returns a unified diff against the last full or delta-updated baseline, plus the new hash and the base hash. Callers apply the diff to their previously received full content; when uncertain, pass reset=true to force a fresh full baseline. Oversized files fall back to full mode and are not cached.

*Params:* `path`, `reset?`


### Editing files

**file-create** — Create a new file with given content in a single call. Replaces the `touch + file-append` two-step pattern. Errors if the file exists unless an overwrite flag is passed. Parent directory must exist; this tool will not create it. Safe for files over 1.2MB.

*Params:* `path`, `content`, `overwrite?`

**file-append** — Append text to the end of an existing file. A leading newline is added if the file does not end with one. Errors if the target file does not already exist. Safe for files over 1.2MB.

*Params:* `path`, `content`

**file-insert-at-line** — Insert text at a specific line number in a file (1-indexed). Line 1 inserts before the first line. Safe for files over 1.2MB.

*Params:* `path`, `line`, `content`

**file-delete-lines** — Delete a range of lines (inclusive, 1-indexed) from a file. Safe for files over 1.2MB.

*Params:* `path`, `start-line`, `end-line`

**file-replace-string** — Replace literal text in a file. Operates on the raw file via temp-buffer + write-region (no mount-layer issues on Windows). Safe for files over 1.2MB. Errors if the old text is not found. Pass max-count "1" to assert exactly one match.

*Params:* `path`, `old-string`, `new-string`, `max-count?`

**file-replace-regexp** — Replace Emacs regexp matches in a file. Patterns use Emacs regexp syntax, including `\(...\)` capture groups; the replacement string may use \\1 \\2 for capture groups. Errors if no match found. Safe for files over 1.2MB.

*Params:* `path`, `pattern`, `replacement`, `max-count?`

**file-ensure-import** — Idempotently ensure an import (or any header) line exists in a file. If the line already appears verbatim, returns already-present without modifying the file. Otherwise inserts after the last line matching after-regex (default: "^import ", matching TS/JS/Python imports). Position can be overridden: "after-last-match" (default), "before-first-match", "top", or "bottom".

*Params:* `path`, `import-line`, `after-regex?`, `position?`

**file-batch** — Execute multiple file operations in a single call. Most token-efficient way to perform bulk edits: N operations in 1 round trip instead of N calls. The operations parameter is a JSON array string. Supported ops: replace, replace-regexp, insert-at-line, delete-lines, append, prepend. All operations run sequentially on the same buffer and the file is written once atomically at the end. Safe for files over 1.2MB.

*Params:* `path`, `operations`

**file-batch-across** — Apply anvil-file-batch to multiple files in a single MCP call. The argument is a JSON array where each element has a path and an operations array: [{"path":"/a.el","operations":[...]},...]. Failures in one file do not abort the rest; per-file results are returned. Use this for bulk docstring updates, import additions, or coordinated multi-file refactors.

*Params:* `file-ops-json`


### Structured data (JSON)

**json-object-add** — Add key-value pairs to a top-level JSON object while preserving existing formatting. Designed for i18n dictionaries and config files where hundreds of entries must be appended without re-emitting the whole file. Pairs are supplied as a JSON array, e.g. "[[\"a\",\"1\"],[\"b\",\"2\"]]". The function detects existing keys and handles duplicates via on-duplicate (skip/overwrite/error). Indentation is auto-detected from the file. Trailing-comma and closing-brace handling is automatic. Only string values are supported; for numeric/boolean values fall back to file-insert-at-line.

*Params:* `path`, `pairs-json`, `on-duplicate?`, `indent?`

**data-get-path** — Read the value at a dotted path inside a JSON file. Returns (:file :path :value) — VALUE is the parsed Lisp tree (plist for objects, vector for arrays, sentinel `:null` / `:false` for those JSON literals). Empty PATH returns the whole document. Read-only.

*Params:* `file`, `path`

**data-set-path** — Install a JSON value at a dotted path inside a JSON file. VALUE-JSON is a string the caller has serialised with `json-serialize` (or by hand) so the MCP boundary stays unambiguous about types. APPLY is preview-only by default — pass any truthy string (e.g. "t") to actually rewrite the file via UTF-8 + LF. Returns (:file :path :before-bytes :after-bytes :applied :preview).

*Params:* `file`, `path`, `value-json`, `apply?`

**data-delete-path** — Remove a dotted path from a JSON file. Same preview / apply contract as `data-set-path`. Returns plist with `:noop t` when the path was already absent.

*Params:* `file`, `path`, `apply?`

**data-list-keys** — Return the keys (or array indices) of the map / array at the named path. Object keys come back without their leading colon; array indices come back as numeric strings. Read-only.

*Params:* `file`, `path?`


### Code extraction/transforms

**code-extract-pattern** — Extract repeating structured records from a file using regexp patterns. For each match of `block-start` the tool finds the block's body via `block-end` (`next-block-start`, `brace-balance`, or a regexp), then runs each `fields` regexp inside the body and captures group 1 as the field's value. In `brace-balance` mode, `block-start` should match the header before the opening `{` and must not consume the brace itself. Read-only — the file is never modified. Returns plist with :matches (each :id :start-line :end-line :fields) :total :returned :skipped. Targets legacy code migration / data extraction where reading the entire file would be wasteful. Regexp values use Emacs regexp syntax, and `fields` must be a JSON array of {name, regexp, required?} objects. Brace-balance skips strings.

*Params:* `path`, `spec-json`

**code-add-field-by-map** — Add a field to TS/JS object literals by mapping from another field's value. For each occurrence of `LOOKUP-KEY: "VALUE"` inside a single-line `{...}` block at PATH, look up VALUE in MAP-JSON and insert `ADD-KEY: "MAPPED-VALUE"` before the closing `}`. Targets bulk i18n / schema-extension workflows where Read+Write of whole files would dominate token cost. Default is preview-only; pass apply="t" to write the file. on-existing controls behavior when ADD-KEY already exists (error|skip|overwrite, default error). scope-regex restricts edits to substrings matching the pattern. Returns plist with :added :skipped :overwritten :missing :total-matches :dry-run :preview.

*Params:* `path`, `lookup-key`, `add-key`, `map-json`, `on-existing?`, `on-missing?`, `scope-regex?`, `apply?`


### Emacs Lisp and ERT

`elisp-byte-compile-file`, `elisp-describe-function`,
`elisp-describe-variable`, `elisp-ert-run`,
`elisp-get-function-definition`, `elisp-read-source-file`, and
`ert-run-distilled` provide schema-checked source inspection, compilation,
and test execution.

### S-expression transforms

`sexp-macroexpand`, `sexp-read-file`, `sexp-rename-symbol`,
`sexp-replace-call`, `sexp-replace-defun`, `sexp-surrounding-form`,
`sexp-verify`, and `sexp-wrap-form` operate on parsed Elisp forms rather
than textual approximations.

### Semantic search and SQLite

`notes-lexical-search`, `semantic-embed-index`, `semantic-reindex`,
`semantic-search`, `semantic-status`, and `sqlite-query` use the
host-local SQLite state configured by the dedicated daemon.

### Org-mode

**org-get-allowed-files** — Get the list of Org files accessible through the anvil-org server. Returns the configured allowed files exactly as specified in anvil-org-allowed-files. Parameters: None Returns JSON object containing: files (array of strings): Absolute paths of allowed Org files Example response: { "files": [ "/path/to/org/tasks.org", "/path/to/org/projects.org", "/path/to/notes/daily.org" ] } Empty configuration returns: { "files": [] } Use cases: - Discovery: What Org files can I access through MCP? - URI Construction: I need to build an org-headline:// URI - what's the exact path? - Access Troubleshooting: Why is my file access failing? - Configuration Verification: Did my anvil-org-allowed-files setting work correctly?

*Params:* (none)

**org-read-file** — Read complete raw content of an Org file. Returns entire file as plain text with all formatting, properties, and structure preserved. File must be in anvil-org-allowed-files. Parameters: file - Absolute path to Org file (string, required) Returns: Plain text content of the entire Org file

*Params:* `file`

**org-read-outline** — Get hierarchical structure of Org file as JSON outline. Returns all headline titles and nesting relationships at full depth. File must be in anvil-org-allowed-files. Parameters: file - Absolute path to Org file (string, required) Returns: JSON object with hierarchical outline structure

*Params:* `file`, `max_depth?`, `max_chars?`

**org-read-headline** — Read specific Org headline by hierarchical path. Returns headline with TODO state, tags, properties, body text, and all nested subheadings. File must be in anvil-org-allowed-files. Parameters: file - Absolute path to Org file (string, required) headline_path - Non-empty slash-separated path to headline (string, required). Only slashes (/) in headline titles must be encoded as %2F Example: "Project/Planning" for nested headlines Example: "A%2FB Testing" for headline titled "A/B Testing" To read entire files, use org-read-file instead Returns: Plain text content of the headline and its subtree

*Params:* `file`, `headline_path`

**org-read-by-id** — Layer 3 of anvil progressive disclosure (see `disclosure-help`). Read Org headline by its unique ID property. More stable than path-based access since IDs don't change when headlines are renamed or moved. Accepts the raw UUID directly or the `org://UUID` citation URI returned by Layer 1 (`org-index-index`) / Layer 2 (`org-index-search`). The `org-id://UUID` form is the MCP resource URI, not the input format for this tool. File containing the ID must be in anvil-org-allowed-files. Parameters: uuid - UUID (or org://UUID citation URI) from headline's ID property (string, required) max_depth - Optional integer string capping the included heading depth relative to the target heading. "1" (default) returns the heading and its body only; "2" adds immediate children; "0" or negative returns the full subtree. Returns: Plain text content of the bounded subtree followed by a "------ Child headlines (N) ------" footer naming the immediate children, so the caller knows which subtrees to descend into next

*Params:* `uuid`, `max_depth?`

**org-edit-body** — Edit the body content of an Org headline using partial string replacement. Finds and replaces a substring within the headline's body text. Creates an Org ID property for the headline if one doesn't exist. Parameters: resource_uri - URI of the headline to edit (string, required) Formats: - org-headline://{absolute-path}#{url-encoded-path} - org-id://{uuid} old_body - Substring to find and replace (string, required) Must appear exactly once unless replace_all is true Use empty string "" only for adding to empty nodes new_body - Replacement text (string, required) Cannot introduce headlines at same or higher level Must maintain balanced #+BEGIN/#+END blocks replace_all - Replace all occurrences (boolean, optional, default false). When false, old_body must be unique in the body. Returns JSON object: success - Always true on success (boolean) uri - ID-based URI (org-id://{uuid}) for the edited headline Special behavior - Empty old_body: When old_body is "", the tool adds content to empty nodes: - Only works if node body is empty or whitespace-only - Error if node already has content - Useful for adding initial content to newly created headlines

*Params:* `resource_uri`, `old_body`, `new_body`, `replace_all?`

**org-add-todo** — Add a new TODO item to an Org file at a specified location. Creates the headline with TODO state, tags, and optional body content. Automatically creates an Org ID property for the new headline. Parameters: title - Headline text without TODO state or tags (string, required) Cannot be empty or whitespace-only Cannot contain newlines todo_state - TODO keyword from org-todo-keywords (string, required) tags - Tags for the headline (string, required) Single tag: "urgent" Multiple tags: JSON array literal, e.g. "[\"work\",\"urgent\"]" No tags: empty string "" Validated against org-tag-alist if configured Must follow Org tag rules (alphanumeric, _, @) Respects mutually exclusive tag groups body - Body content under the headline (string, optional) Cannot contain headlines at same or higher level as new item If #+BEGIN/#+END blocks are present, they must be balanced parent_uri - Parent location (string, required) For top-level: org-headline://{absolute-path} For child: org-headline://{path}#{parent-path} or org-id://{parent-uuid} after_uri - Sibling to insert after (string, optional) Must be org-id://{uuid} format If omitted, appends as last child of parent position - "first" inserts as parent's first child (string, optional) Mutually exclusive with after_uri Returns JSON object: success - Always true on success (boolean) uri - ID-based URI (org-id://{uuid}) for the new headline file - Filename (not full path) where item was added title - The headline title that was created Positioning behavior: - With parent_uri only: Appends as last child of parent - With parent_uri + after_uri: Inserts immediately after specified sibling - Top-level (parent_uri with no fragment): Adds at end of file.

*Params:* `title`, `todo_state`, `parent_uri`, `body?`, `after_uri?`, `tags?`, `position?`

**org-update-todo-state** — Update the TODO state of an Org headline. Changes the task state while preserving the headline title, tags, and other properties. Creates an Org ID property for the headline if one doesn't exist. Parameters: uri - URI of the headline to update (string, required) Formats: - org-headline://{absolute-path}#{url-encoded-path} - org-id://{uuid} current_state - Expected current TODO state (string, required) Use empty string "" if headline has no TODO state Must match actual state or tool will error new_state - New TODO state to set (string, required) Must be valid keyword from org-todo-keywords Returns JSON object: success - Always true on success (boolean) previous_state - The previous TODO state (string, empty for none) new_state - The new TODO state that was set (string) uri - ID-based URI (org-id://{uuid}) for the updated headline

*Params:* `uri`, `current_state`, `new_state`

**org-rename-headline** — Rename an Org headline's title while preserving its TODO state, tags, properties, and body content. Creates an Org ID property for the headline if one doesn't exist. Parameters: uri - URI of the headline to rename (string, required) Formats: - org-headline://{absolute-path}#{url-encoded-path} - org-id://{uuid} current_title - Expected current title without TODO/tags (string, required) Must match actual title or tool will error Used to prevent race conditions new_title - New title without TODO state or tags (string, required) Cannot be empty or whitespace-only Cannot contain newlines Returns JSON object: success - Always true on success (boolean) previous_title - The previous headline title (string) new_title - The new title that was set (string) uri - ID-based URI (org-id://{uuid}) for the renamed headline

*Params:* `uri`, `current_title`, `new_title`

**org-capture-string** — Invoke an org-capture template noninteractively. CONTENT is passed as org-capture-initial, so the target template must include %i if the caller wants CONTENT inserted. Static file targets are validated against anvil-org-allowed-files before capture runs. Parameters: keys - org-capture template key string, e.g. "t" or "jm" content - Initial text available to the template as %i allow_unvalidated_target - Optional true/false string. Dynamic function targets cannot be pre-validated; pass true only for trusted templates. Returns JSON object: success - true on success keys - Template key used target_file - Expanded target file when statically known, else empty

*Params:* `keys`, `content`, `allow_unvalidated_target?`

**org-agenda-view** — Render an Org agenda view using Emacs' own org-agenda engine and return the plain-text agenda buffer. Use this when the agent needs the same scheduled/deadline/TODO view a human would see in Emacs, without reimplementing agenda logic. Parameters: keys - Optional org-agenda dispatcher key (string). Examples: "a" daily/weekly agenda, "t" global TODO list, or a custom command key from org-agenda-custom-commands. Empty means direct org-agenda-list. start_day - Optional YYYY-MM-DD start date for agenda-list views span - Optional positive integer string for number of days files_json - Optional JSON array of Org file paths to bind as org-agenda-files. Omit to use anvil-org-allowed-files when access restrictions are enabled, otherwise the user's org-agenda-files. Returns: Plain text agenda output with text properties stripped.

*Params:* `keys?`, `start_day?`, `span?`, `files_json?`

**org-habit-summary** — Summarize Org habits using org-habit itself. Scans STYLE=habit headlines and returns scheduled/deadline dates, repeat intervals, done dates, current status, urgency, recent completion ratio, and a repeat-aware streak count. Parameters: files_json - Optional JSON array of Org file paths to scan. Omit to use anvil-org-allowed-files when restrictions are enabled, otherwise org-agenda-files. today - Optional YYYY-MM-DD reference date. Defaults to today. Returns JSON object: today - Reference date count - Number of habit rows habits - Array of habit objects. Invalid habit entries include an error field instead of aborting the whole scan.

*Params:* `files_json?`, `today?`

**org-get-todo-config** — Get the TODO keyword configuration from the current Emacs Org-mode settings. Returns information about task state sequences and their semantics. Parameters: None Returns JSON object with two arrays: sequences - Array of TODO keyword sequences, each containing: - type: Sequence type (e.g., "sequence", "type") - keywords: Array of keywords including "|" separator between active and done states semantics - Array of keyword semantics, each containing: - state: The TODO keyword (e.g., "TODO", "DONE") - isFinal: Whether this is a final (done) state (boolean) - sequenceType: The sequence type this keyword belongs to The "|" separator in sequences marks the boundary between active states (before) and done states (after). If no "|" is present, the last keyword is treated as the done state. Use this tool to understand the available task states in the Org configuration before creating or updating TODO items.

*Params:* (none)

**org-get-tag-config** — Get tag-related configuration from the current Emacs Org-mode settings. Returns literal Elisp variable values as strings for tag configuration introspection. Parameters: None Returns JSON object with literal Elisp expressions (as strings) for: org-use-tag-inheritance - Controls tag inheritance behavior org-tags-exclude-from-inheritance - Tags that don't inherit org-tag-alist - List of allowed tags with optional key bindings and groups org-tag-persistent-alist - Additional persistent tags (or nil) The org-tag-alist format includes: - Simple tags: ("tagname" . key-char) - Group markers: :startgroup, :endgroup for mutually exclusive tags - Grouptags: :startgrouptag, :grouptags, :endgrouptag for tag hierarchies Use this tool to understand: - Which tags are allowed - Tag inheritance rules - Mutually exclusive tag groups - Tag hierarchy relationships This helps validate tag usage and understand tag semantics before adding or modifying tags on TODO items.

*Params:* (none)


### Git (read-only queries)

**git-repo-root** — Return the git top-level directory for PATH, or nil when PATH is not inside a repository. PATH must be a directory.

*Params:* `path`

**git-head-sha** — Return the HEAD commit SHA for the repo containing PATH. Pass short=1 for the abbreviated form.

*Params:* `path`, `short?`

**git-branch-current** — Return the current branch name, or nil when HEAD is detached.

*Params:* `path`

**git-status** — Return porcelain status + branch/upstream/ahead/behind counts as one plist. Buckets: staged / modified / untracked / unmerged.

*Params:* `path`

**git-log** — Return recent commits as (hash, date, author, subject) plists. limit defaults to 20.

*Params:* `path`, `limit?`

**git-diff-names** — Return the paths differing between FROM and TO (defaults unstaged-vs-HEAD).

*Params:* `path`, `from?`, `to?`

**git-diff-stats** — Return structured diff counts (files, insertions, deletions) for REV or unstaged-vs-HEAD.

*Params:* `path`, `rev?`

**git-worktree-list** — Return attached git worktrees as plists (path, head, branch, bare, detached).

*Params:* `path`


### Workers & telemetry

**anvil-worker-probe** — Per-lane worker status: name, alive/busy, PID, metrics summary

*Params:* (none)

**anvil-worker-reset-pool** — Kill all workers and respawn fresh daemons (recovers stuck pool)

*Params:* (none)

**metrics-token-report** — Report per-tool MCP payload telemetry for this session. Returns session totals plus the top-N tools sorted by response volume (default), request volume, or call count. Request counts use the dispatcher's in-memory arguments object measured via `%S`; response counts use the exact transport string when the dispatcher already has it. Optional `reset` is report-then-reset.

*Params:* `top_n?`, `sort?`, `reset?`


## Dedicated-only typed extensions

The dedicated configuration adds 11 tools to the 65-tool interactive typed
surface: `context-compress`, `context-retrieve`, `context-stats`,
`cron-list`, `cron-run`, `cron-status`, `shell-filter`, `shell-gain`,
`shell-run`, `shell-tee-get`, and `shell-tee-grep`. They are available
both through the direct typed registry and the unified primary registry.

## NeLisp standalone surface

NeLisp has no live Emacs process and therefore no `emacs-eval` or Org engine;
its evaluator is internal and is not exposed as a general Elisp-eval tool. Its
exact 42-tool manifest covers host inspection, file/directory operations, JSON
path operations, and shell execution. Probe the advertised
tool list and use those tools directly; do not require an Emacs-only probe
before using the standalone backend.

*Param names suffixed `?` are optional. Full JSON schemas ship with the
active server; when a call is rejected, re-check the client tool definition
rather than guessing.*
