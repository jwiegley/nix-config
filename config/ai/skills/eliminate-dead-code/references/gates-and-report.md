# Report, approval gates, and prohibitions

This reference holds the final report template, the approval-gate list consulted during Phase 2 synthesis, and the "never do" list.

---

## Report structure

Produce a single Markdown report (print it; do not write to disk unless the user requests). Structure:

```
# Dead-Code Elimination Report

**Branch**: chore/dead-code-pass-<n>
**Starting commit**: <sha>
**Ending commit**: <sha>
**Baseline commands**: <commands run before/after>
**Result**: green / red
**Markers remaining**: 0 (verified)

## Verdicts
- Removed: <N>   Modified: <M>   Kept: <K>   Escalated to user: <E>

## Removed / Modified (committed)
- `<sha>` -- <verdict> -- <symbol> -- <files touched, lines delta> -- <deciding evidence>
- ...

## Kept (and why)
- `<location>` -- `<symbol>` -- concrete reference or uncertainty that won the debate.

## Deferred (needs-approval, awaiting or denied by user)
- `<location>` -- `<symbol>` -- what evidence was found, what was missing, gate triggered.

## Stale-doc changes
- <file>:<lines> -- <summary>

## Toolchain notes
- Tools attempted, tools missing, tools that produced output.

## Cap status
- Hit blast-radius cap? Yes/No. Remaining non-keep verdicts: <count>.
- To continue, re-invoke `/eliminate-dead-code <scope>`.

## Risks and uncertainties
- Anything you noticed but did not act on, plus a recommendation.

## Unrelated issues observed
- (Per the operating principle of not fixing unrelated issues mid-run.)
```

Then print the proposed next step:

- If `Result: green` and cap not hit: "Branch ready for review -- open a PR with `gh pr create` when you have reviewed the diff."
- If `Result: green` and cap hit: "Re-invoke for another pass."
- If `Result: red`: do not propose merging; describe the offending commit and the diagnostic step to take.

---

## Approval gates (always pause before finalizing a `remove`/`modify` verdict)

Stop and **ask the user** during Phase 2 synthesis before finalizing a non-`keep` verdict for any of the following, regardless of static-analysis or debate confidence:

- Removing or modifying any **public API surface** (library exports, CLI commands, web routes, RPC handlers, GraphQL types, OpenAPI endpoints).
- Removing any symbol matching a pattern in the **Exclusion Allowlist** (Phase 1.1).
- Removing any **database migration**.
- Removing files inside **generated** or **vendored** directories.
- Removing **test fixtures**, **golden files**, or **i18n keys**.
- Removing anything mentioned in **deploy / ops / runbook** files.
- Removing anything **touched within the recency window** (default 30 days, configurable via `recent=Nd` in the argument, per `git log --since`).
- Removing **conditional-compilation branches** (`#ifdef`, `cfg!`, feature gates) -- the inactive branch may target a platform you cannot build.
- Removing **dead feature-flag definitions** when the flag's default may still be read from a remote config service.
- Removing **deprecated APIs** that may still have external consumers, even if internal callers are gone.

For each gated case, present:

- the candidate,
- the evidence collected and the three-advocate arguments,
- the specific reason it triggered the gate,
- and your recommendation (remove / modify / keep),

then wait for the user's decision before writing the verdict.

---

## What to never do

- Never **commit or push** `DCE-BEGIN`/`DCE-END` markers or the `.dce-pass-*/` sidecar directory. They are working-tree-only scaffolding.
- Never insert a marker where a comment is not syntactically legal -- sidecar it instead.
- Never modify `.git/`, `.github/` workflows, CI configs, or hooks unless the user explicitly asked for that scope.
- Never delete a file from a directory containing `# Code generated`, `@generated`, or that is listed in `.gitattributes` with `linguist-generated`.
- Never use `git push --force`, `git reset --hard` on a non-throwaway branch, or `git rebase` to hide commits.
- Never bypass `pre-commit`/`lefthook` with `--no-verify`.
- Never auto-install a static-analysis tool; if it is not present, skip it.
- Never remove "old-looking" code based purely on age -- many projects have stable, rarely-touched, still-load-bearing modules.
- Never trust a single evidence source in a dynamic language. The two-evidence rule is mandatory at both marking (Phase 1.4) and verdict synthesis (Phase 2.C).
- Never let a balanced-looking debate justify removal. Uncertainty resolves to `keep`.
- Never claim "no behavior change" -- instead report **the evidence collected** and let the user judge.
