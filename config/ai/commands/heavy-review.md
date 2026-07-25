Run a coordinated, read-only review of `$ARGUMENTS`.

Interpret the scope as follows:

- empty or `repository`: the whole repository;
- `working-tree`: staged and unstaged changes against `HEAD`;
- `pr` or `pr N`: the current or numbered pull request;
- otherwise: a path, branch, commit, or commit range.

Freeze one scope snapshot before reviewing so every pass examines the same code. Do not edit files, stage changes, post comments, or invoke mutating dead-code phases.

Run five independent passes:

1. **Deep review** — correctness, security, performance, structure, tests, and documentation.
2. **Alexey-discipline review** — challenge the premise first; verify correctness by construction, benchmark and prose claims, test meaning, and scope discipline.
3. **Ponytail review** — identify over-engineering, duplicate machinery, unnecessary dependencies, and code that should be deleted or replaced by existing/native facilities.
4. **Dead-code audit** — report only evidence-backed unreachable, unused, stale, or superseded code and documentation; require two independent signals for dynamic references.
5. **Comment audit** — verify comments and docstrings against current code, commands, paths, versions, and behavior.

Consolidate the results into one report:

- deduplicate overlapping findings while retaining every source pass;
- rank actionable findings as critical, high, medium, or low;
- give an exact file and line/range plus evidence for each finding;
- separate verified defects from questions and non-actionable observations;
- include a clean-pass statement for each pass that found nothing;
- end with the smallest safe fix order and the verification command for each fix.

Do not report style preferences without a concrete maintenance, correctness, performance, or security consequence.
