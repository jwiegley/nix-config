---
name: validated-code-review
description: Use when the user requests a thorough pre-PR code review of the current branch — e.g. "run a validated code review".  "validated" is a key word
---

MODELS: claude-fable-5, gpt-5.6-sol

# Multi-Model Code Review

## Overview

Orchestrate independent review agents across multiple models, verify every
claim with a *different* model, grade surviving claims P0–P2, and synthesize
one merge-blocker-focused review ready for human eyes.

This is strictly a code review: **never build, never run tests.** All agents
work read-only against the checkout and the diff.

## Inputs

- **Model list**: the `MODELS:` line above is the default. The user may
  override it with their own list. The list MUST contain at least 2 models
  (otherwise different-model verification is impossible — stop and ask).
- **Base ref** (optional): the ref the branch is diffed against. Defaults
  to `origin/main`. The user may override it to review one PR in a stack —
  pass the parent branch of the stacked PR (e.g. `origin/feature-part-1`).
  Prefer the remote-tracking ref (`origin/<branch>`); use a local branch
  only if the user explicitly names one.
- **Extra categories**: the user may add focused review categories beyond
  the four defaults below.

## Model dispatch

| Model | How to run it |
|-------|---------------|
| `claude-*` (e.g. claude-fable-5) | Subagent (the Agent tool in Claude Code; the harness's native subagent mechanism elsewhere) |
| Anything else (e.g. gpt-5.6-sol) | `mcp__pal__clink` (codex CLI); fall back to `mcp__pal__chat` with that model if clink is unavailable |

## Model assignment rules

1. **Focused reviews**: pick each reviewer's model uniformly at random from
   the model list (e.g. `shuf -n1 -e <models...>`).
2. **Broad reviews**: one broad review per model in the list — every model
   in the list gets its own broad pass.
3. **Verification**: every review (focused and broad) is verified by a model
   picked at random from the list *excluding the model that wrote the
   review*. A review is never verified by its own model. Record both model
   names in the output file.

## Stage 0 — Setup

```bash
git fetch origin   # skip only if the user states it is already done
BASE_REF=${BASE_REF:-origin/main}   # user override for stacked PRs (see Inputs)
git rev-parse --verify --quiet "$BASE_REF^{commit}" || exit 1  # bad base ref: stop and ask
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = "HEAD" ] && BRANCH=detached
SHORT_HEAD=$(git rev-parse --short HEAD)
REVIEW_DIR=/tmp/code-review-${BRANCH//\//-}-${SHORT_HEAD}
mkdir -p "$REVIEW_DIR"
git diff "$BASE_REF"...HEAD > "$REVIEW_DIR/diff.patch"
git log --oneline "$BASE_REF"..HEAD > "$REVIEW_DIR/commits.txt"
```

- The branch is always compared to **`$BASE_REF`** (three-dot, merge-base
  diff) — `origin/main` unless the user overrode it. Never diff against a
  local `main`.
- Every intermediate artifact — subagent summaries, clink transcripts,
  verification files — lives under `$REVIEW_DIR`. Only the final review is
  copied into the source tree.

## Stage 1 — Independent reviews (all in parallel)

Launch every reviewer below concurrently. Each reviewer receives: the
checkout path, `$REVIEW_DIR/diff.patch`, the instruction to read full source
files for context, and the instruction to review only (no builds, no tests).
Each writes its own markdown summary of claims, every claim with
`file:line` and a short evidence quote.

**Focused reviewers** (one random model each; default categories, plus any
user-supplied extras):

| Category | Output file |
|----------|-------------|
| Code correctness | `$REVIEW_DIR/review-correctness.md` |
| Memory safety | `$REVIEW_DIR/review-memory-safety.md` |
| Comment quality / inconsistencies | `$REVIEW_DIR/review-comments.md` |
| Missing test coverage | `$REVIEW_DIR/review-test-coverage.md` |
| *(user extras)* | `$REVIEW_DIR/review-<category>.md` |

**Broad reviewers** (one per model in the list, no assigned focus area,
full diff):

- `$REVIEW_DIR/review-broad-<model>.md`

## Stage 2 — Different-model verification (all in parallel)

For each Stage 1 review file, spawn a fresh verifier on a random
*different* model (rule 3 above). The verifier:

1. Reads the review and compares **every claim to the actual code**.
2. Marks each claim `VALID` or `INVALID` (with the reason).
3. Assigns each VALID claim a severity:

| Severity | Meaning |
|----------|---------|
| **P0** | Merge blocker — must fix before posting the PR stack |
| **P1** | Real issue — should fix, not blocking |
| **P2** | Minor / nit / style |

Output: `$REVIEW_DIR/verified-<same-suffix>.md`, headed by
`Reviewer model: X / Verifier model: Y`.

## Stage 3 — Consolidation

Merge all `verified-*.md` files into
`$REVIEW_DIR/consolidated-review.md`:

- Drop INVALID claims; dedupe claims found by multiple reviewers (keep the
  highest severity, note all finders).
- Annotate every claim with: source review (category, or broad + model),
  reviewing model, verifying model, verification outcome, severity.
- Broad-review claims are the **cross-model stream** — label them as such
  so downstream stages can weigh them.

## Stage 4 — Consensus forum

Run `mcp__pal__consensus` with every model in the list. Provide:

- `$REVIEW_DIR/consolidated-review.md`
- Sufficient source context (the diff plus the relevant file regions)
- The annotations from Stage 3, so the forum sees which claims came from
  the cross-model stream and how each fared under opposite-model
  verification.

Ask the forum to confirm or reject each P0/P1 as a genuine merge blocker.

## Stage 5 — Synthesis and delivery

1. Using the forum output, eliminate spurious, irrelevant, or trivial
   claims. Keep only substantial issues: **P0 merge blockers** lead the
   document; confirmed P1s go in a short "Follow-ups (non-blocking)"
   appendix; and remaining vetted P2s at the end.
2. Each surviving claim gets: `file:line`, a one-paragraph description,
   evidence, and a suggested fix.
3. Write `$REVIEW_DIR/final-review.md`, then copy it into the source tree
   root as `<branch>-code-review.md`. Do **not** commit it — the user posts
   reviews themselves.
4. Report to the user: blocker count, the in-tree path, and `$REVIEW_DIR`
   for the raw stream.

## Constraints

- Read-only review: no `make build*`, no `make test*`, no binaries run.
- Diff base is `$BASE_REF` (three-dot) — `origin/main` by default, a
  user-supplied parent branch for stacked PRs — never local `main`.
- No review is verified by the model that wrote it.
- All intermediates in `$REVIEW_DIR`; only the final review enters the tree.

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Diffing against local `main` | Always `"$BASE_REF"...HEAD` after `git fetch origin` (default `origin/main`) |
| Reviewing a stacked PR against `origin/main` | The diff then includes the parent PRs' changes — set the base ref to the stack parent (e.g. `origin/feature-part-1`) |
| Verifier same model as reviewer | Re-draw from the list minus the reviewer's model |
| Treating unverified claims as findings | Only VALID claims with severity survive Stage 2 |
| Running tests "to confirm" a claim | This skill is review-only; cite code, not runs |
