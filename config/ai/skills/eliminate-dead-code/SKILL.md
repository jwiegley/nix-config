---
name: eliminate-dead-code
description: Methodology for finding and removing dead code and stale documentation
  with evidence-based safety, using a mark / debate / act / verify workflow. Use when
  asked to remove dead code, unused symbols, unreachable branches, stale docs, unused
  imports, or dead feature flags -- gathering independent evidence before each removal
  and re-verifying build and tests after. The `/eliminate-dead-code` command turns
  it on.
---
# Dead Code Eliminator

Find code and documentation that are no longer reachable, referenced, or relevant, and remove them in small atomic commits without changing the project's current functional behavior. The `/eliminate-dead-code` command turns this on with an optional scope argument.

You cannot truly guarantee zero behavior change in an arbitrary codebase -- reflection, dynamic dispatch, framework conventions, and runtime wiring make that impossible from static analysis alone. What you can do, and what is required, is gather enough independent evidence that each removal is safe before making it, and verify after each removal that the project still builds and its tests still pass.

When in doubt, leave it. Flagging a candidate for human review is always better than a silently-broken production deploy.

## The four-phase workflow

Run in four phases. Do not interleave them.

1. **MARK** -- Discover, analyze, and bracket every dead-code region with in-source markers (plus a sidecar manifest for things that cannot be bracketed). No code is changed or removed; markers are left as uncommitted working-tree changes for review.
2. **DEBATE** -- For each marked region, decide its fate. Ambiguous or high-blast-radius regions get a three-advocate debate (keep-as-is / modify / remove); trivially-dead regions take a lighter safety-biased checklist. Every region ends with exactly one verdict: `keep`, `modify`, or `remove`.
3. **ACT** -- Walk the regions in dependency order and apply each verdict as an atomic commit, stripping the region's markers as you go.
4. **VERIFY** -- Run the full build/test/lint suite, confirm zero markers remain, and print a structured report.

Read `references/phases.md` for the full step-by-step detail of each phase (discovery, the exclusion allowlist, static-analysis tooling per language, cross-reference verification, the marker format and sidecar schema, the debate protocol, the act loop, and the verify checklist). Read `references/gates-and-report.md` for the report template, the approval gates, and the "never do" list.

## Scope

Interpret the argument:

- **Empty or `.`** -- full repository.
- **A path** (`src/foo`, `docs/`) -- restrict discovery, analysis, marking, and removals to that subtree (cross-reference checks still scan the entire repo).
- **`docs`** -- only stale documentation; do not remove code.
- **`imports`** -- only unused imports / unused dependencies.
- **`feature-flags`** -- only permanently-on/off flags and their dead branches.
- **`comments`** -- only commented-out code blocks.
- **A language name** (`python`, `rust`, `typescript`, ...) -- restrict to files of that language.
- **`cap=N`** (combinable, e.g. `src/foo cap=50`) -- override the default 20-commit blast-radius cap. `cap=0` means no cap (still stop on first failure).
- **`recent=Nd`** (e.g. `recent=14d`) -- override the 30-day recency window used by the approval gate.

If the argument is ambiguous, ask the user before proceeding.

## Operating principles (read first, every time)

1. **Conservative by default.** When uncertain, the verdict is `keep`, never `remove`. Uncertainty never resolves to removal -- not by majority vote, not by "the evidence mostly points that way."
2. **Pure deletions and surgical modifications only.** Do not refactor, rename, reformat, or "improve" adjacent code. A `modify` verdict applies only the concrete diff the debate produced -- nothing more. Do not fix unrelated bugs along the way; record them in the final report instead.
3. **Atomic commits.** One logical region per commit, with a clear message. Each commit must leave the build and tests passing.
4. **Two-evidence rule for dynamic languages.** In Python, Ruby, JavaScript, TypeScript (and any language supporting reflection or string-based dispatch), a passing test suite is not sufficient evidence of safety. Require at least two independent forms of evidence before a region is even marked as a removal candidate, and again before a `remove` verdict is finalized. The two sources must be independent modalities (e.g. static "no references" and an entry-point/registration check), not two variants of the same grep.
5. **Native tooling first.** Prefer compiler flags and lints already configured in the repo over third-party tools. Never auto-install a static-analysis tool -- if a recommended tool is not present, note it and move on.
6. **Avoid the yak-shaving trap.** If the project's build/test commands fail in your environment due to missing toolchains, abort and report -- do not spend the run trying to install things.
7. **Blast-radius cap.** Make at most 20 removal/modification commits per invocation by default. If more candidates carry a non-`keep` verdict, list them in the report and stop. The user can re-invoke for further passes.
8. **Never bypass safety.** No `--no-verify`, no `--force`, no skipping tests, no amending commits to hide failures.
9. **Markers never escape.** The `DCE-BEGIN`/`DCE-END` markers introduced in MARK are working-tree-only scaffolding. They are never committed, never pushed, and must be fully gone before VERIFY reports success. If the run is interrupted, discard the markers with `git restore --worktree -- .` because the working tree was clean at the start of the run.

## When you are unsure

Tell the user. A short message like:

> Phase 1 marked 14 candidates: 9 class `safe`, 3 `ambiguous` (route-handler files -- FastAPI auto-discovery), 2 `needs-approval` (single string-literal reference in a YAML config). I will run the lighter path on the 9, the full three-advocate debate on the 3 ambiguous ones, and ask before finalizing the 2 gated ones. OK?

is always preferable to silently making the wrong call.
