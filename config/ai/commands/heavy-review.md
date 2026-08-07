Run a coordinated, read-only review of `$ARGUMENTS`.

Interpret the scope as follows:

- empty or `repository`: the whole repository;
- `working-tree`: staged and unstaged changes against `HEAD`;
- `pr` or `pr N`: the current or numbered pull request;
- otherwise: a path, branch, commit, or commit range.

Freeze one scope snapshot before reviewing so every pass examines the same code. Do not edit files, stage changes, post comments, or invoke mutating dead-code phases.

Run seven independent passes:

1. **Deep review** — correctness, security, performance, structure, tests, and documentation.
2. **Alexey-discipline review** — challenge the premise first; verify correctness by construction, benchmark and prose claims, test meaning, and scope discipline.
3. **Abstraction review** (use the `abstraction-review` skill) — determine whether the change extends the existing abstractions or evades them: parallel mechanisms beside existing ones, identity dispatch, name-carried semantics, runtime rediscovery of static facts, guard workarounds, contract shoehorning, and mocks or tests that validate a workaround instead of the requirement.
4. **Validated multi-model review** (use the `validated-code-review` skill) — independent reviewers across multiple models, every claim verified by a *different* model, graded P0–P2, disputed calls settled by a consensus forum. When the scope is a branch or PR, give it the matching base ref; otherwise hand it the frozen snapshot diff as its review input. Under this command it returns its findings instead of writing the in-tree review file.
5. **Ponytail review** — identify over-engineering, duplicate machinery, unnecessary dependencies, and code that should be deleted or replaced by existing/native facilities.
6. **Dead-code audit** — report only evidence-backed unreachable, unused, stale, or superseded code and documentation; require two independent signals for dynamic references.
7. **Comment audit** — verify comments and docstrings against current code, commands, paths, versions, and behavior.

Orchestration — every pass always runs in its own subagent, all passes concurrently:

- In Claude Code, always orchestrate with an ultracode Workflow: a flat fan-out with one `agent()` call per pass, no barriers between passes, and consolidation in the orchestrating loop only after every pass returns. In other harnesses, launch each pass in its own subagent through the native subagent mechanism, all concurrent.
- Each pass subagent receives the frozen scope snapshot, loads any skill its pass names, works read-only, and returns findings as structured data: finding, file and line, evidence, severity, source pass.
- The validated pass drives its internal multi-model stages (PAL `clink`, `chat`, `consensus`) from inside its own subagent.
- The orchestrator reads no diffs and reviews no code itself; it only dispatches, collects, and consolidates.

Consolidate the results into one report:

- deduplicate overlapping findings while retaining every source pass;
- rank actionable findings as critical, high, medium, or low; map the validated pass's grades P0 → critical, P1 → high or medium by judgment, P2 → low;
- give an exact file and line/range plus evidence for each finding;
- separate verified defects from questions and non-actionable observations;
- include a clean-pass statement for each pass that found nothing;
- end with the smallest safe fix order and the verification command for each fix.

Do not report style preferences without a concrete maintenance, correctness, performance, or security consequence.
