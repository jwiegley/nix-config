#!/usr/bin/env python3
"""Deterministic comment inventory for the comment-audit skill.

Extracts every comment (and Python docstring) from a project or from the files
changed in a PR/stack, and records each as an entry in a JSON manifest. The
manifest is the source of truth for an exhaustive, resumable audit: the agent
fills in a verdict for every entry, and the audit is only complete when no
entry remains in the `pending` state.

This script is pure standard-library Python (3.9+). It does NOT require
tree-sitter, semgrep, or any third-party parser. Comment extraction uses
Python's `tokenize`/`ast` for `.py` files and a state-machine tokenizer
(string-literal aware, line- and block-comment aware) for other languages.
Extension families that are not recognized are recorded under
`files_skipped` so that "exhaustive" always means "exhaustive over a declared
and visible policy" rather than a vague promise.

Commands:
  inventory   Build/refresh the manifest (default).
  pending     Print the next N pending entries (id, path, lines, form).
  show        Print the full text of one or more entries by id.
  update      Record a verdict/evidence for one entry (atomic write).
  stats       Print summary counts by status and verdict.

Run `inventory_comments.py <command> --help` for command-specific options.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import io
import json
import os
import subprocess
import sys
import tempfile
import tokenize
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime

MANIFEST_VERSION = 1
DEFAULT_MANIFEST = os.path.join(".comment-audit", "manifest.json")

VALID_VERDICTS = {
    "VALID",
    "STALE",
    "INCORRECT",
    "MISLEADING",
    "ORPHANED",
    "UNVERIFIABLE",
    "NEEDS_REVIEW",
}

# Directories that never contain first-party comments worth auditing.
DEFAULT_PRUNE_DIRS = {
    ".git",
    ".hg",
    ".svn",
    "node_modules",
    "vendor",
    "third_party",
    "dist",
    "build",
    "target",
    ".venv",
    "venv",
    "__pycache__",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".tox",
    ".next",
    ".cache",
    "coverage",
    ".idea",
    ".gradle",
}


# --- Language comment specifications -----------------------------------------


@dataclass(frozen=True)
class LangSpec:
    """How to find comments in one family of languages."""

    name: str
    line: tuple[str, ...] = ()
    block: tuple[tuple[str, str], ...] = ()
    strings: tuple[str, ...] = ()
    # Line-comment tokens that must be preceded by start-of-line or whitespace
    # to count (avoids matching '#' inside shell ${#x} or '--' inside ident).
    line_needs_ws: tuple[str, ...] = ()


_C_LIKE = LangSpec(
    name="c-like",
    line=("//",),
    block=(("/*", "*/"),),
    strings=('"', "'", "`"),
)
_C_NO_LINE = LangSpec(  # CSS and friends: block comments only
    name="css",
    block=(("/*", "*/"),),
    strings=('"', "'"),
)
_HASH = LangSpec(
    name="hash",
    line=("#",),
    strings=('"', "'"),
    line_needs_ws=("#",),
)
_DASH_SQL = LangSpec(
    name="sql",
    line=("--",),
    block=(("/*", "*/"),),
    strings=("'", '"'),
    line_needs_ws=("--",),
)
_LISP = LangSpec(name="lisp", line=(";",), strings=('"',))
_HASKELL = LangSpec(
    name="haskell",
    line=("--",),
    block=(("{-", "-}"),),
    strings=('"',),
    line_needs_ws=("--",),
)
_LUA = LangSpec(
    name="lua",
    line=("--",),
    block=(("--[[", "]]"),),
    strings=('"', "'"),
    line_needs_ws=("--",),
)
_HTML = LangSpec(name="html", block=(("<!--", "-->"),), strings=('"', "'"))

# Extension -> spec. Python (.py, .pyi) is handled separately via tokenize/ast.
EXT_SPECS: dict[str, LangSpec] = {
    # C family / braces
    ".c": _C_LIKE,
    ".h": _C_LIKE,
    ".cc": _C_LIKE,
    ".cpp": _C_LIKE,
    ".cxx": _C_LIKE,
    ".hpp": _C_LIKE,
    ".hh": _C_LIKE,
    ".m": _C_LIKE,
    ".mm": _C_LIKE,
    ".java": _C_LIKE,
    ".js": _C_LIKE,
    ".jsx": _C_LIKE,
    ".mjs": _C_LIKE,
    ".cjs": _C_LIKE,
    ".ts": _C_LIKE,
    ".tsx": _C_LIKE,
    ".go": _C_LIKE,
    ".rs": _C_LIKE,
    ".swift": _C_LIKE,
    ".kt": _C_LIKE,
    ".kts": _C_LIKE,
    ".scala": _C_LIKE,
    ".dart": _C_LIKE,
    ".php": _C_LIKE,
    ".cs": _C_LIKE,
    ".proto": _C_LIKE,
    # CSS-ish
    ".css": _C_NO_LINE,
    ".scss": _C_LIKE,  # scss supports // too
    ".less": _C_LIKE,
    # hash family
    ".py": _HASH,  # placeholder; real path uses tokenize/ast
    ".pyi": _HASH,
    ".rb": _HASH,
    ".sh": _HASH,
    ".bash": _HASH,
    ".zsh": _HASH,
    ".yaml": _HASH,
    ".yml": _HASH,
    ".toml": _HASH,
    ".cfg": _HASH,
    ".ini": _HASH,
    ".conf": _HASH,
    ".r": _HASH,
    ".pl": _HASH,
    ".pm": _HASH,
    ".tf": _HASH,
    ".dockerfile": _HASH,
    ".mk": _HASH,
    ".nix": _HASH,
    ".ex": _HASH,
    ".exs": _HASH,
    # sql
    ".sql": _DASH_SQL,
    # lisp family
    ".el": _LISP,
    ".lisp": _LISP,
    ".cl": _LISP,
    ".clj": _LISP,
    ".cljs": _LISP,
    ".scm": _LISP,
    ".rkt": _LISP,
    # haskell
    ".hs": _HASKELL,
    ".lhs": _HASKELL,
    # lua
    ".lua": _LUA,
    # markup
    ".html": _HTML,
    ".htm": _HTML,
    ".xml": _HTML,
    ".vue": _HTML,
    ".svelte": _HTML,
    ".md": _HTML,
    ".markdown": _HTML,
}

# Files matched by basename (no useful extension).
BASENAME_SPECS: dict[str, LangSpec] = {
    "Makefile": _HASH,
    "makefile": _HASH,
    "GNUmakefile": _HASH,
    "Dockerfile": _HASH,
    "Containerfile": _HASH,
    ".env": _HASH,
    ".env.example": _HASH,
}


@dataclass
class Comment:
    start_line: int
    end_line: int
    form: str  # line | block | docstring
    text: str
    standalone: bool = True  # True if only whitespace precedes it on its line


# --- Extraction --------------------------------------------------------------


def _consume_string(src: str, i: int, line: int, quote: str) -> tuple[int, int]:
    """Advance past a string literal starting at i. Returns (new_i, new_line)."""
    n = len(src)
    i += len(quote)
    while i < n:
        c = src[i]
        if c == "\\":
            if i + 1 < n and src[i + 1] == "\n":
                line += 1
            i += 2
            continue
        if c == "\n":
            line += 1
            i += 1
            continue
        if src.startswith(quote, i):
            i += len(quote)
            break
        i += 1
    return i, line


def scan_generic(src: str, spec: LangSpec) -> list[Comment]:
    comments: list[Comment] = []
    i = 0
    n = len(src)
    line = 1
    at_line_start = True  # True until a non-whitespace char on this line
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            at_line_start = True
            continue
        prev_ws = at_line_start or (i > 0 and src[i - 1] in " \t")

        # strings
        matched = False
        for q in spec.strings:
            if src.startswith(q, i):
                i, line = _consume_string(src, i, line, q)
                matched = True
                at_line_start = False
                break
        if matched:
            continue

        # block comments
        for op, cl in spec.block:
            if src.startswith(op, i):
                start_line = line
                j = src.find(cl, i + len(op))
                end = n if j == -1 else j + len(cl)
                text = src[i:end]
                line += text.count("\n")
                comments.append(
                    Comment(start_line, line, "block", text, standalone=at_line_start)
                )
                i = end
                matched = True
                at_line_start = False
                break
        if matched:
            continue

        # line comments
        for lt in spec.line:
            if src.startswith(lt, i):
                if lt in spec.line_needs_ws and not prev_ws:
                    continue
                j = src.find("\n", i)
                if j == -1:
                    j = n
                text = src[i:j]
                comments.append(
                    Comment(line, line, "line", text, standalone=at_line_start)
                )
                i = j
                matched = True
                at_line_start = False
                break
        if matched:
            continue

        if not c.isspace():
            at_line_start = False
        i += 1
    return comments


def scan_python(src: str) -> list[Comment]:
    comments: list[Comment] = []
    lines = src.splitlines()
    try:
        tokens = tokenize.generate_tokens(io.StringIO(src).readline)
        for tok in tokens:
            if tok.type == tokenize.COMMENT:
                row, col = tok.start
                prefix = lines[row - 1][:col] if 0 < row <= len(lines) else ""
                standalone = prefix.strip() == ""
                comments.append(
                    Comment(
                        tok.start[0],
                        tok.end[0],
                        "line",
                        tok.string,
                        standalone=standalone,
                    )
                )
    except (tokenize.TokenError, IndentationError, SyntaxError):
        # Fall back to a hash-based generic scan for malformed files.
        return scan_generic(src, _HASH)

    try:
        tree = ast.parse(src)
        for node in ast.walk(tree):
            if isinstance(
                node,
                (
                    ast.Module,
                    ast.FunctionDef,
                    ast.AsyncFunctionDef,
                    ast.ClassDef,
                ),
            ):
                body = getattr(node, "body", None)
                if not body:
                    continue
                first = body[0]
                if (
                    isinstance(first, ast.Expr)
                    and isinstance(first.value, ast.Constant)
                    and isinstance(first.value.value, str)
                ):
                    seg = ast.get_source_segment(src, first.value)
                    text = seg if seg is not None else repr(first.value.value)
                    start = first.value.lineno
                    end = getattr(first.value, "end_lineno", start)
                    comments.append(Comment(start, end, "docstring", text))
    except (SyntaxError, ValueError):
        pass
    return comments


def merge_consecutive_line_comments(comments: list[Comment]) -> list[Comment]:
    """Merge runs of single-line comments on consecutive lines into one unit."""
    comments = sorted(comments, key=lambda c: (c.start_line, c.end_line))
    merged: list[Comment] = []
    for c in comments:
        if (
            merged
            and c.form == "line"
            and c.standalone
            and merged[-1].form == "line"
            and merged[-1].standalone
            and c.start_line == merged[-1].end_line + 1
        ):
            prev = merged[-1]
            merged[-1] = Comment(
                prev.start_line,
                c.end_line,
                "line",
                prev.text + "\n" + c.text,
                standalone=True,
            )
        else:
            merged.append(c)
    return merged


def spec_for(path: str) -> LangSpec | None:
    base = os.path.basename(path)
    if base in BASENAME_SPECS:
        return BASENAME_SPECS[base]
    _, ext = os.path.splitext(path)
    return EXT_SPECS.get(ext.lower())


def extract_comments(path: str, src: str) -> list[Comment]:
    _, ext = os.path.splitext(path)
    if ext.lower() in (".py", ".pyi"):
        comments = scan_python(src)
    else:
        spec = spec_for(path)
        if spec is None:
            return []
        comments = scan_generic(src, spec)
    return merge_consecutive_line_comments(comments)


# --- Git helpers -------------------------------------------------------------


def _run_git(args: list[str], root: str) -> str | None:
    try:
        out = subprocess.run(
            ["git", *args],
            cwd=root,
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return None
    if out.returncode != 0:
        return None
    return out.stdout


def is_git_repo(root: str) -> bool:
    out = _run_git(["rev-parse", "--is-inside-work-tree"], root)
    return out is not None and out.strip() == "true"


def git_tracked_files(root: str) -> list[str] | None:
    out = _run_git(["ls-files"], root)
    if out is None:
        return None
    return [line for line in out.splitlines() if line]


def diff_changed_files(root: str, base: str) -> list[str]:
    out = _run_git(["diff", "--name-only", f"{base}...HEAD"], root)
    files = [line for line in out.splitlines() if line] if out else []
    # Include uncommitted working-tree changes too.
    out2 = _run_git(["diff", "--name-only"], root)
    if out2:
        files.extend(line for line in out2.splitlines() if line)
    return sorted(set(files))


def diff_changed_lines(root: str, base: str, path: str) -> set[int]:
    """New-side line numbers touched by the diff for a single file."""
    changed: set[int] = set()
    for spec in (f"{base}...HEAD", "HEAD"):
        out = _run_git(["diff", "-U0", spec, "--", path], root)
        if not out:
            continue
        for line in out.splitlines():
            if line.startswith("@@"):
                # @@ -a,b +c,d @@
                try:
                    plus = line.split("+", 1)[1].split(" ", 1)[0]
                    if "," in plus:
                        start_s, count_s = plus.split(",", 1)
                        start, count = int(start_s), int(count_s)
                    else:
                        start, count = int(plus), 1
                except (ValueError, IndexError):
                    continue
                for ln in range(start, start + max(count, 1)):
                    changed.add(ln)
    return changed


# --- File discovery ----------------------------------------------------------


def walk_files(root: str) -> Iterable[str]:
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in DEFAULT_PRUNE_DIRS]
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            yield os.path.relpath(full, root)


def is_probably_binary(data: bytes) -> bool:
    return b"\x00" in data[:8192]


def read_text(root: str, rel: str) -> str | None:
    full = os.path.join(root, rel)
    try:
        with open(full, "rb") as f:
            data = f.read()
    except (OSError, IsADirectoryError):
        return None
    if is_probably_binary(data):
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        try:
            return data.decode("latin-1")
        except UnicodeDecodeError:
            return None


# --- Manifest ----------------------------------------------------------------


def comment_id(path: str, start_line: int, text: str) -> str:
    h = hashlib.sha1()
    norm = " ".join(text.split())
    h.update(f"{path}:{start_line}:{norm}".encode())
    return h.hexdigest()[:12]


def atomic_write_json(path: str, obj: dict) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(obj, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def load_manifest(path: str) -> dict | None:
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return None


def build_inventory(args: argparse.Namespace) -> int:
    root = os.path.abspath(args.root)
    manifest_path = os.path.join(root, args.manifest)

    scope = "diff" if args.diff_base else "project"

    # Determine candidate files.
    if args.diff_base:
        candidates = diff_changed_files(root, args.diff_base)
    else:
        tracked = git_tracked_files(root) if is_git_repo(root) else None
        candidates = tracked if tracked is not None else list(walk_files(root))

    files_scanned: list[str] = []
    files_skipped: list[dict] = []
    new_comments: dict[str, dict] = {}

    for rel in candidates:
        if spec_for(rel) is None and os.path.splitext(rel)[1].lower() not in (
            ".py",
            ".pyi",
        ):
            files_skipped.append({"path": rel, "reason": "unrecognized-extension"})
            continue
        src = read_text(root, rel)
        if src is None:
            files_skipped.append({"path": rel, "reason": "binary-or-unreadable"})
            continue
        files_scanned.append(rel)
        changed_lines = (
            diff_changed_lines(root, args.diff_base, rel) if args.diff_base else None
        )
        for c in extract_comments(rel, src):
            cid = comment_id(rel, c.start_line, c.text)
            in_diff = changed_lines is not None and bool(
                set(range(c.start_line, c.end_line + 1)) & changed_lines
            )
            new_comments[cid] = {
                "id": cid,
                "path": rel,
                "start_line": c.start_line,
                "end_line": c.end_line,
                "form": c.form,
                "text": c.text,
                "in_diff": in_diff,
                "status": "pending",
                "verdict": None,
                "confidence": None,
                "claim_types": [],
                "evidence": None,
                "recommendation": None,
            }

    # Merge with prior manifest to preserve completed verdicts (resumability).
    prior = load_manifest(manifest_path)
    preserved = 0
    if prior and isinstance(prior.get("comments"), list):
        prior_by_id = {c["id"]: c for c in prior["comments"] if "id" in c}
        for cid, entry in new_comments.items():
            old = prior_by_id.get(cid)
            if old and old.get("status") == "audited":
                for key in (
                    "status",
                    "verdict",
                    "confidence",
                    "claim_types",
                    "evidence",
                    "recommendation",
                ):
                    if key in old:
                        entry[key] = old[key]
                preserved += 1

    comments = sorted(new_comments.values(), key=lambda c: (c["path"], c["start_line"]))
    manifest = {
        "manifest_version": MANIFEST_VERSION,
        "generated_at": datetime.now(UTC).isoformat(),
        "root": root,
        "scope": scope,
        "diff_base": args.diff_base,
        "pruned_dirs": sorted(DEFAULT_PRUNE_DIRS),
        "files_scanned": sorted(files_scanned),
        "files_skipped": sorted(files_skipped, key=lambda f: f["path"]),
        "comments": comments,
    }
    atomic_write_json(manifest_path, manifest)

    pending = sum(1 for c in comments if c["status"] == "pending")
    print(f"Manifest written: {manifest_path}")
    print(
        f"  scope:          {scope}"
        + (f" (base {args.diff_base})" if args.diff_base else "")
    )
    print(f"  files scanned:  {len(files_scanned)}")
    print(f"  files skipped:  {len(files_skipped)}")
    print(f"  comments found: {len(comments)}")
    print(f"  preserved:      {preserved} (verdicts carried over)")
    print(f"  pending:        {pending}")
    if args.diff_base:
        in_diff = sum(1 for c in comments if c["in_diff"])
        print(f"  in-diff:        {in_diff}")
    return 0


# --- Reporting / mutation commands -------------------------------------------


def cmd_pending(args: argparse.Namespace) -> int:
    root = os.path.abspath(args.root)
    manifest_path = os.path.join(root, args.manifest)
    manifest = load_manifest(manifest_path)
    if manifest is None:
        print(
            f"No manifest at {manifest_path}. Run `inventory` first.", file=sys.stderr
        )
        return 1
    pending = [c for c in manifest["comments"] if c["status"] == "pending"]
    if args.in_diff_only:
        pending = [c for c in pending if c.get("in_diff")]
    for c in pending[: args.limit]:
        print(
            f"{c['id']}  {c['path']}:{c['start_line']}-{c['end_line']}  [{c['form']}]"
        )
    print(
        f"\n{len(pending)} pending total; showing up to {args.limit}.", file=sys.stderr
    )
    return 0


def cmd_show(args: argparse.Namespace) -> int:
    root = os.path.abspath(args.root)
    manifest_path = os.path.join(root, args.manifest)
    manifest = load_manifest(manifest_path)
    if manifest is None:
        print(f"No manifest at {manifest_path}.", file=sys.stderr)
        return 1
    by_id = {c["id"]: c for c in manifest["comments"]}
    for cid in args.ids:
        c = by_id.get(cid)
        if c is None:
            print(f"== {cid}: NOT FOUND ==")
            continue
        print(
            f"== {cid}  {c['path']}:{c['start_line']}-{c['end_line']}  [{c['form']}] =="
        )
        print(c["text"])
        print(
            f"-- status={c['status']} verdict={c['verdict']}"
            f" confidence={c['confidence']}"
        )
        print()
    return 0


def cmd_update(args: argparse.Namespace) -> int:
    root = os.path.abspath(args.root)
    manifest_path = os.path.join(root, args.manifest)
    manifest = load_manifest(manifest_path)
    if manifest is None:
        print(f"No manifest at {manifest_path}.", file=sys.stderr)
        return 1
    if args.verdict not in VALID_VERDICTS:
        print(
            f"Invalid verdict {args.verdict!r}. Allowed: {sorted(VALID_VERDICTS)}",
            file=sys.stderr,
        )
        return 1
    found = False
    for c in manifest["comments"]:
        if c["id"] == args.id:
            c["status"] = "audited"
            c["verdict"] = args.verdict
            c["confidence"] = args.confidence
            c["claim_types"] = (
                [t.strip() for t in args.claim_types.split(",") if t.strip()]
                if args.claim_types
                else []
            )
            c["evidence"] = args.evidence
            c["recommendation"] = args.recommendation
            found = True
            break
    if not found:
        print(f"id {args.id} not found.", file=sys.stderr)
        return 1
    atomic_write_json(manifest_path, manifest)
    print(f"Updated {args.id}: {args.verdict} (confidence={args.confidence})")
    return 0


def cmd_stats(args: argparse.Namespace) -> int:
    root = os.path.abspath(args.root)
    manifest_path = os.path.join(root, args.manifest)
    manifest = load_manifest(manifest_path)
    if manifest is None:
        print(f"No manifest at {manifest_path}.", file=sys.stderr)
        return 1
    comments = manifest["comments"]
    total = len(comments)
    pending = sum(1 for c in comments if c["status"] == "pending")
    by_verdict: dict[str, int] = {}
    for c in comments:
        if c["status"] == "audited":
            by_verdict[c["verdict"]] = by_verdict.get(c["verdict"], 0) + 1
    print(f"total:   {total}")
    print(f"pending: {pending}")
    print(f"audited: {total - pending}")
    for v in sorted(by_verdict):
        print(f"  {v}: {by_verdict[v]}")
    if pending == 0 and total > 0:
        print("\nAUDIT COMPLETE: every comment has a verdict.")
    else:
        print(f"\nAUDIT INCOMPLETE: {pending} comment(s) still pending.")
    return 0


# --- CLI ---------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("--root", default=".", help="Project root (default: cwd).")
    p.add_argument(
        "--manifest",
        default=DEFAULT_MANIFEST,
        help=f"Manifest path relative to root (default: {DEFAULT_MANIFEST}).",
    )
    sub = p.add_subparsers(dest="command")

    inv = sub.add_parser("inventory", help="Build/refresh the manifest.")
    inv.add_argument(
        "--diff-base",
        default=None,
        help="Audit only PR/stack changes relative to this base ref "
        "(e.g. origin/main). Omit for a whole-project audit.",
    )
    inv.set_defaults(func=build_inventory)

    pend = sub.add_parser("pending", help="List pending entries.")
    pend.add_argument("--limit", type=int, default=20)
    pend.add_argument("--in-diff-only", action="store_true")
    pend.set_defaults(func=cmd_pending)

    show = sub.add_parser("show", help="Show full text of entries by id.")
    show.add_argument("ids", nargs="+")
    show.set_defaults(func=cmd_show)

    upd = sub.add_parser("update", help="Record a verdict for one entry.")
    upd.add_argument("--id", required=True)
    upd.add_argument("--verdict", required=True)
    upd.add_argument("--confidence", choices=["high", "medium", "low"], required=True)
    upd.add_argument("--claim-types", default="")
    upd.add_argument("--evidence", default=None)
    upd.add_argument("--recommendation", default=None)
    upd.set_defaults(func=cmd_update)

    st = sub.add_parser("stats", help="Print summary counts.")
    st.set_defaults(func=cmd_stats)

    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "command", None):
        # Default to inventory with no diff base.
        args.command = "inventory"
        args.diff_base = None
        args.func = build_inventory
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
