---
name: comment-audit
description: 'Exhaustively verify code comments against the current state of a project.
  Use when asked to audit, fact-check, or validate comments/docstrings -- to confirm
  that every claim a comment makes is true, that any code shown in a comment actually
  works, and that everything a comment references still exists. Supports auditing
  an entire project or only the changes in a PR or stack of PRs. Triggers: "check
  the comments", "are these comments still accurate", "audit comments in this PR",
  "verify the docstrings".'
---
# Comment Audit

Audit code comments with a fine-toothed comb. Move comment-by-comment until
every comment in scope has been checked against the live codebase and assigned
a verdict. The guarantee is exhaustiveness over a declared policy: every
comment the inventory finds gets a verdict, and every file that was skipped is
recorded with a reason.

## Core principles

- **Evidence before verdict.** Never call a comment wrong without concrete
  proof from the current code. When proof is missing or the judgment depends on
  domain knowledge not present in the repo, the verdict is `NEEDS_REVIEW`, not
  `INCORRECT`. A confident-but-wrong verdict that triggers a "fix" to a correct
  comment is the worst possible outcome -- bias toward caution.
- **The manifest is the source of truth.** Track progress on disk in
  `.comment-audit/manifest.json`, not in working memory. This makes the audit
  resumable and lets large projects be processed in batches without losing
  place.
- **Exhaustive means accounted-for.** A comment is either audited (has a
  verdict) or explicitly skipped (its file is in `files_skipped`). Nothing
  silently falls through.

## Workflow

Create one TodoWrite item per phase below and work them in order.

### 1. Determine scope

Ask (or infer from the request) which scope applies:

- **Whole project** -- audit every comment in the repository.
- **PR / stack** -- audit only the changes. Identify the base ref:
  - For a checked-out branch, use `gh pr view --json baseRefName` or the merge
    base: `git merge-base HEAD origin/main`.
  - For a stack, use the base of the bottom-most PR so the whole stack's
    changes are in range.

### 2. Build the inventory

Run the bundled extractor to enumerate every comment into the manifest. It is
pure-stdlib Python (no third-party parsers) and is string-literal aware, so it
will not mistake `"http://..."` or a shell `${#var}` for a comment.

The script lives next to this file at `scripts/inventory_comments.py`. Run it
by its **installed absolute path** (this skill's own directory -- the same
directory this SKILL.md was loaded from), since the working directory will be
the project under audit, not the skill directory. Below, `$SKILL` stands for
that directory.

Whole project:

```bash
python3 "$SKILL/scripts/inventory_comments.py" inventory
```

PR / stack (records which comments fall inside the diff):

```bash
python3 "$SKILL/scripts/inventory_comments.py" inventory --diff-base origin/main
```

Global options (`--root`, `--manifest`) come *before* the subcommand; use
`--root <project>` if not running from the project root. The command prints
counts: comments found, files skipped, and (in diff mode) how many comments are
in-diff. Inspect `files_skipped` in the manifest -- if a source language the
project actually uses was skipped as `unrecognized-extension`, note it in the
final report so the user knows that surface was not covered.

Re-running `inventory` is safe and idempotent: it preserves verdicts already
recorded for comments that still exist (resumability).

### 3. Audit each comment

Process the manifest in **batches of ~10-15 comments per file** so context stays
small. Loop:

1. List the next batch: `"$SKILL/scripts/inventory_comments.py" pending --limit 15`
   (add `--in-diff-only` in PR mode to prioritize changed comments first).
2. For each id, read its text (`"$SKILL/scripts/inventory_comments.py" show <id>`)
   and open the surrounding code with the Read tool to get real context.
3. Classify the comment and verify it using
   `references/claim-taxonomy.md` (claim types and the verification recipe for
   each) and `references/verification-guide.md` (how to gather evidence, how to
   safely run code found in comments, and the false-positive guardrails).
4. Record the verdict:

   ```bash
   python3 "$SKILL/scripts/inventory_comments.py" update --id <id> \
     --verdict <VERDICT> --confidence high|medium|low \
     --claim-types behavioral,reference \
     --evidence "what was checked and what was found" \
     --recommendation "suggested fix, or omit"
   ```

   Allowed verdicts: `VALID`, `STALE`, `INCORRECT`, `MISLEADING`, `ORPHANED`,
   `UNVERIFIABLE`, `NEEDS_REVIEW` (see the taxonomy for definitions).

After each batch, drop the batch's details from working context and pull the
next batch. The manifest holds the accumulated results.

### 4. PR/stack: catch remote stale comments

Diff-adjacency is not enough. When the diff changes a function, type, constant,
or config key, comments **elsewhere** in the repo that describe it may now be
stale. For each symbol whose signature or behavior changed in the diff, grep
the whole project for its name and audit any comment that references it, even if
that comment is outside the diff. Add any such comments to the audit before
declaring the PR scope complete.

### 5. Apply fixes

For each non-`VALID` finding the user asked to fix:

- **Auto-fix** comments with verdict `STALE`, `INCORRECT`, `MISLEADING`, or
  `ORPHANED` **only when confidence is `high`** and the correct content is
  unambiguous from the evidence. Edit the comment text in place; never change
  the surrounding code to match a comment without flagging it separately.
- **Never auto-edit** `NEEDS_REVIEW` or `UNVERIFIABLE` comments, or any
  `medium`/`low` confidence finding. Surface these for human decision.
- Deleting a comment is a valid fix for an `ORPHANED` reference or a resolved
  `TODO`, but prefer correcting over deleting unless the comment is purely
  obsolete.

### 6. Completion gate and report

The audit is complete **only when `"$SKILL/scripts/inventory_comments.py" stats`
reports zero pending**. Do not claim completion before then.

Produce a report (see the report format in `references/verification-guide.md`)
grouped by severity. For each finding include: `path:line`, the quoted claim,
the verdict and confidence, the concrete evidence, and the recommended or
applied fix. Summarize counts by verdict and list any skipped-file surfaces that
were not covered.

## Notes

- The `.comment-audit/` directory is a working artifact. Suggest the user add it
  to `.gitignore` if it should not be committed; do not add it yourself unless
  asked.
- If the project provides a native doc-test harness (Python `doctest`, Rust
  `--doc` tests, etc.), prefer it for verifying example snippets over ad-hoc
  execution. Details in `references/verification-guide.md`.
- Extractor limitations to stay skeptical about: the generic tokenizer does not
  model raw strings (e.g. Rust `r#"..."#`) or regex literals (e.g. JS `/.../`),
  so a `//` or `#` inside one of those can occasionally produce a spurious
  inventory entry. These are false *positives* (an extra entry to dismiss), not
  silent omissions. Python (`.py`) uses the real `tokenize`/`ast` and is exact.
  Files whose extension is unrecognized are listed in `files_skipped`; if such a
  language carries real comments, audit those files by reading them directly and
  report the gap.
