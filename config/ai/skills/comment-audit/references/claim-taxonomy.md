# Claim Taxonomy and Verdicts

Classify every comment along two axes, then verify according to its claim
type(s). A single comment may carry several claim types -- label all that apply
and verify each.

## Axis 1: Comment form

Form affects where to look and how the comment is meant to be read.

- **line** -- one or more consecutive single-line comments (`//`, `#`, `;`,
  `--`). Often describes the line or block directly below or beside it.
- **block** -- a delimited block (`/* ... */`, `{- ... -}`, `<!-- ... -->`).
  Often a file/section header or a longer rationale.
- **docstring** -- Python triple-quoted docstrings and equivalent API docs.
  Frequently contains example snippets (doctests) and signature/type claims.
- **trailing** -- a comment after code on the same line (the extractor marks
  these as non-standalone; they annotate the specific statement they follow).

## Axis 2: Claim type (and how to verify)

For each, the goal is to find concrete evidence in the *current* code.

1. **behavioral** -- asserts runtime behavior ("returns the count", "handles
   the empty list", "retries 3 times", "is idempotent").
   Verify: read the implementation it describes. Trace the relevant branch.
   Confirm the asserted behavior is actually produced by the current code.

2. **signature/type** -- asserts argument names, types, shapes, return type,
   nullability (common in docstrings, JSDoc, type-hint prose).
   Verify: compare against the actual function signature / type annotations.
   A renamed or removed parameter makes the claim `STALE`/`INCORRECT`.

3. **code-in-comment** -- an example, usage snippet, or doctest meant to work.
   Verify: per `verification-guide.md` (tiered: parse -> typecheck -> compile
   -> execute, preferring a native doc-test harness). "Not runnable as-is" is
   NOT automatically `INCORRECT`; many examples are intentionally schematic.

4. **cross-reference** -- names another file, function, class, module, symbol,
   or `@see`/`@link`.
   Verify: confirm the target exists now (grep/Glob). Missing target =
   `ORPHANED`. Existing but renamed = `STALE`.

5. **external-reference** -- a URL, RFC, spec section, ticket ID, standard.
   Verify: confirm the reference is well-formed and, where a tool is available,
   reachable. A dead link or a ticket that no longer matches the described
   behavior is `STALE`/`ORPHANED`. Do not fetch URLs that look unsafe.

6. **rationale/constraint** -- explains *why* ("because the API requires X",
   "must stay sorted for the binary search below", "workaround for bug Y").
   Verify: check whether the stated constraint still holds in the code. If the
   binary search was replaced by a hash lookup, the "must stay sorted" rationale
   is `STALE`. If the rationale depends on external/business context not in the
   repo, it is `UNVERIFIABLE` or `NEEDS_REVIEW` -- never `INCORRECT` on a guess.

7. **temporal/version** -- "as of v2.3", "deprecated in 3.8", "new in Python
   3.11", "remove after Q3".
   Verify: check the version actually in use (lockfiles, manifests, language
   version). A deprecation that already happened, or a "remove after" date that
   has passed, is `STALE`.

8. **environment/compatibility** -- "Linux-only", "requires env var X",
   "needs GPU", "POSIX only".
   Verify: check config, CI matrices, and code paths for the claimed
   requirement. Often `NEEDS_REVIEW` if the environment can't be inspected.

9. **machine-meaningful** -- suppressions and directives (`# type: ignore`,
   `# noqa`, `eslint-disable`, `# pragma`, `//nolint`, `# pylint: disable`).
   Verify: is the suppression still needed? Run the relevant linter/checker
   without it when feasible. A suppression for a warning that no longer fires is
   `STALE` (dead suppression). Note: removing these changes behavior -- treat as
   a finding, fix only with care.

10. **security/performance/concurrency** -- "constant-time compare", "O(n log
    n)", "thread-safe", "not reentrant", "input is already sanitized".
    Verify: these are high-stakes and often only partially provable from code.
    Require strong evidence; default to `NEEDS_REVIEW` when the claim cannot be
    established with confidence. Do not downgrade a security-relevant claim to
    `VALID` without solid proof.

11. **TODO/FIXME/HACK** -- a marker pointing at future or deferred work.
    Verify: has the work already been done (marker is stale)? Is the referenced
    problem still present? A `TODO` whose task is complete is `STALE`.

## Verdict vocabulary

Assign exactly one verdict per comment. Definitions are deliberately
conservative.

- **VALID** -- every claim checked is true against the current code, with
  concrete supporting evidence.
- **STALE** -- was accurate once but the code/version/reference has since moved;
  the comment now describes a past state.
- **INCORRECT** -- contradicted by the current code, with explicit
  counter-evidence. Requires proof, not absence of confirmation.
- **MISLEADING** -- technically true but likely to deceive a reader (omits a
  critical caveat, describes the happy path only, ambiguous wording).
- **ORPHANED** -- references something (file, symbol, ticket, URL) that no
  longer exists or resolves.
- **UNVERIFIABLE** -- pure intent, opinion, or context that cannot be checked
  from the repository (e.g. "this is the elegant approach").
- **NEEDS_REVIEW** -- the comment *could* be wrong, but proving it requires
  domain knowledge, external context, or judgment not available here. The
  safe default whenever counter-evidence is incomplete. Prefer this over a
  speculative `INCORRECT`.

## Confidence

Record `high` only when the verdict rests on direct, unambiguous evidence read
from the current code. Use `medium` when the evidence is indirect, `low` when
inferred. Auto-fixes are permitted only at `high` confidence (see SKILL.md).
