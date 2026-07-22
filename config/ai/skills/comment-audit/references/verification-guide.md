# Verification Guide

How to gather evidence, safely verify code found in comments, avoid
false positives, and format the report.

## Gathering evidence

- Always open the real code with Read before judging a comment. Read enough
  surrounding context to understand the claim, not just the commented line.
- Use Grep/Glob to confirm cross-references and to find every place a changed
  symbol is mentioned (critical for PR mode).
- Prefer the project's own tools as ground truth: type checkers, linters,
  compilers, and existing tests. Their output is stronger evidence than a
  reading of the source.
- Distinguish "could not reproduce / could not verify" from "proven false."
  The first is `NEEDS_REVIEW` or `UNVERIFIABLE`; only the second is `INCORRECT`.

## Verifying code found in comments (tiered)

Run the cheapest sufficient level. Record the level reached as part of the
evidence. Reaching a lower level than "executed" is normal and fine; it does
not by itself make a comment `INCORRECT`.

1. **PARSED** -- the snippet is syntactically valid for its language.
2. **TYPECHECKED** -- it passes the type checker against the project's symbols
   (the referenced functions/types exist with the shown signatures).
3. **COMPILED** -- it compiles in the project context.
4. **EXECUTED** -- it runs and produces the stated result.

### Prefer native doc-test harnesses

If the language/project has one, use it -- it handles imports and setup the way
the authors intended:

- Python docstrings with `>>>`: run `python -m doctest <file> -v` (or
  `pytest --doctest-modules`).
- Rust: `cargo test --doc` runs ```` ```rust ```` examples in doc comments.
- Other ecosystems: use their documented doctest mechanism if present.

### When running ad hoc, sandbox it

Only execute a snippet directly when no native harness applies and execution is
needed to settle the verdict. Then:

- Copy the snippet into a throwaway file under a temp directory
  (`mktemp -d`); never run it inside the project tree or modify project files.
- Do not run code with network calls, credentials/secrets, or obviously
  destructive operations (file deletion, `rm`, DB drops, shell-outs). If a
  snippet requires these to run, mark it `NEEDS_REVIEW` instead of executing.
- Keep execution short; abandon anything that hangs.
- Snippets routinely omit imports, fixtures, or setup. Missing scaffolding
  means "schematic example," not "broken code." Supply obvious imports if that
  is clearly the author's intent, otherwise downgrade the verification level
  rather than failing the comment.

## False-positive guardrails

The most damaging failure is declaring a correct comment wrong and then
"fixing" it. Guard against it:

- Require explicit counter-evidence for `INCORRECT`. If you cannot quote the
  code that contradicts the comment, the verdict is not `INCORRECT`.
- When a claim depends on business logic, intent, or external context not in
  the repo, use `NEEDS_REVIEW` -- do not guess.
- Be especially conservative with `rationale/constraint`,
  `security/performance/concurrency`, and `environment` claims; they are often
  only partially provable.
- Quote the exact claim and the exact evidence in the manifest's `evidence`
  field so the verdict is auditable by a human.
- Never auto-edit a `NEEDS_REVIEW`/`UNVERIFIABLE` comment or any sub-`high`
  confidence finding.

## Report format

Group findings by severity. Suggested severity mapping:

- **Critical**: `INCORRECT` or `MISLEADING` on `behavioral`,
  `security/performance/concurrency`, or `signature/type` claims -- a reader
  acting on the comment would be actively misled.
- **High**: `STALE`/`ORPHANED` on behavioral, reference, or code-in-comment
  claims; broken doctests.
- **Medium**: stale `temporal/version`, dead suppressions, resolved TODOs.
- **Low / FYI**: `UNVERIFIABLE`, `NEEDS_REVIEW` items needing a human, and minor
  wording nits.

For each finding, present:

```
<severity>  <path>:<line>  [<verdict>, confidence=<level>]
  claim:    "<the quoted comment text>"
  evidence: <what was checked and what was found>
  fix:      <applied | proposed diff | recommendation>  (or "none")
```

End the report with:

- Counts by verdict (from `inventory_comments.py stats`).
- A list of fixes applied automatically vs. left for human review.
- Any languages/files in `files_skipped` whose surface was therefore not
  covered, so the user knows the audit's true boundary.
