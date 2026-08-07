Run a coordinated, read-only review of `$ARGUMENTS`.

Interpret the scope as follows:

- empty or `repository`: the whole repository;
- `working-tree`: staged and unstaged changes against `HEAD`;
- `pr` or `pr N`: the current or numbered pull request;
- otherwise: a path, branch, commit, or commit range.

Freeze one scope snapshot before reviewing so every pass examines the same code. Do not edit files, stage changes, post comments, or invoke mutating dead-code phases.

Run six independent passes:

1. **Deep review** — correctness, security, performance, structure, tests, and documentation.
2. **Alexey-discipline review** — challenge the premise first; verify correctness by construction, benchmark and prose claims, test meaning, and scope discipline.
3. **Abstraction review** (use the `abstraction-review` skill) — determine whether the change extends the existing abstractions or evades them: parallel mechanisms beside existing ones, identity dispatch, name-carried semantics, runtime rediscovery of static facts, guard workarounds, contract shoehorning, and mocks or tests that validate a workaround instead of the requirement.
4. **Ponytail review** — identify over-engineering, duplicate machinery, unnecessary dependencies, and code that should be deleted or replaced by existing/native facilities.
5. **Dead-code audit** — report only evidence-backed unreachable, unused, stale, or superseded code and documentation; require two independent signals for dynamic references.
6. **Comment audit** — verify comments and docstrings against current code, commands, paths, versions, and behavior.

Consolidate the results into one report:

- deduplicate overlapping findings while retaining every source pass;
- rank actionable findings as critical, high, medium, or low;
- give an exact file and line/range plus evidence for each finding;
- separate verified defects from questions and non-actionable observations;
- include a clean-pass statement for each pass that found nothing;
- end with the smallest safe fix order and the verification command for each fix.

Do not report style preferences without a concrete maintenance, correctness, performance, or security consequence.
