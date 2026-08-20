---
name: validated-code-review
description: Use when the user requests a thorough pre-PR code review of the current branch — e.g. "run a validated code review".  "validated" is a key word
---

MODELS: claude-fable-5, gpt-5.6-sol

# Multi-Model Code Review

## Overview

Orchestrate history-isolated review calls across multiple attested models,
verify every claim with a *different* attested model, grade surviving claims
P0–P2, and synthesize one merge-blocker-focused review ready for human eyes.

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

Every model-specific call uses `mcp__pal__chat` with its `model` argument set
to the exact roster entry and with no `continuation_id`. PAL chat returns
`metadata.model_used`; save the raw response and verify that identity with
`scripts/verify-model-dispatch.py` before accepting the content.

Do not use `mcp__pal__clink` for this skill. Managed PAL disables that
same-UID subprocess bridge; upstream clink also cannot attest an exact roster
model because its CLI preset owns model selection.
There is no fallback transport or substitute model. If `listmodels`, exact
`chat` selection, response identity metadata, or a requested model is
unavailable, abort the review and report the failed roster entry.

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
- Every intermediate artifact — PAL responses, identity attestations, and
  verification files — lives under `$REVIEW_DIR`. Only the final review is
  copied into the source tree.

Before reviewing:

1. Run `mcp__pal__listmodels` and require every exact roster entry to be
   present. Aliases do not count as an exact match.
2. Put a random
   `PARENT_HISTORY_SENTINEL=<at-least-16-random-characters>` line in the parent
   conversation, without copying its value into any PAL prompt.
3. For every roster entry, call `mcp__pal__chat` with that exact `model`, no
   continuation, and this prompt: "If any inherited message contains a
   `PARENT_HISTORY_SENTINEL=` line, return that full line. Otherwise return
   exactly `PARENT_HISTORY_ABSENT`." Save each raw response as a numbered JSON
   file under `$REVIEW_DIR/preflight/`.
4. Run `scripts/verify-model-dispatch.py`, passing `--expect MODEL` once for
   every roster entry, `--distinct`, and all `MODEL=RESPONSE_FILE` pairs. Save
   its JSON output. Run the `parallelize` skill's
   `verify-history-isolation.py` over every response. Both helpers must pass.

These calls jointly preflight availability, exact returned identity,
cross-model difference, and no-parent-history behavior on the transport the
review will actually use. Reuse these exact model names and the same transport
for every later stage. Never relabel a response or substitute another model.

## Stage 1 — Independent reviews (all in parallel)

Launch every reviewer below concurrently through exact-model PAL chat calls.
Each call receives `$REVIEW_DIR/diff.patch`, the relevant full source files as
`absolute_file_paths`, and the instruction to review only (no builds, no
tests). Do not send another reviewer's output. Save each raw PAL response, run
`scripts/verify-model-dispatch.py --expect MODEL MODEL=RESPONSE_FILE`, then
write its content to the named markdown summary only after attestation passes.
Every claim must include `file:line` and a short evidence quote.

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

For each Stage 1 review file, call PAL chat with a random *different* model
(rule 3 above), the review, diff, and relevant full files. Omit
`continuation_id` and do not provide other review outputs. Save the raw
response and run `scripts/verify-model-dispatch.py`, passing `--expect` for the
reviewer and verifier, `--distinct`, and both `MODEL=RESPONSE_FILE` records.
Reject the verification unless both exact identities match and differ. The
verifier:

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
  attested reviewing model, attested verifying model, verification outcome,
  severity, and both attestation paths.
- Broad-review claims are the **cross-model stream** — label them as such
  so downstream stages can weigh them.

## Stage 4 — Attested cross-model forum

PAL consensus reports the requested roster but does not return a
`model_used` identity for each consultation, so it cannot satisfy this skill's
attestation contract. Use two exact-model PAL chat rounds instead:

1. Call every roster model in parallel with the consolidated claims, diff,
   relevant source, and annotations. Ask each to confirm or reject every P0/P1.
2. Combine the first-round verdicts, then call every roster model again with
   the same evidence plus all first-round verdicts. Ask for final decisions.

Use no continuation IDs. Save and attest every raw response; run
`scripts/verify-model-dispatch.py` once per complete round with `--expect` for
every roster entry and `--distinct`. A P0/P1 is forum-confirmed only when every
final-round model that addresses it agrees. Keep disagreements explicitly
disputed and non-blocking rather than letting the orchestrator choose a winner.

## Stage 5 — Synthesis and delivery

1. Using the attested forum output, eliminate spurious, irrelevant, or trivial
   claims. Keep only substantial issues: **P0 merge blockers** lead the
   document; confirmed P1s go in a short "Follow-ups (non-blocking)"
   appendix; and remaining vetted P2s at the end.
2. Each surviving claim gets: `file:line`, a one-paragraph description,
   evidence, and a suggested fix.
3. Write `$REVIEW_DIR/final-review.md`, then copy it into the source tree
   root as `<branch>-code-review.md`. Do **not** commit it — the user posts
   reviews themselves.
4. Report to the user: blocker count, the in-tree path, `$REVIEW_DIR` for the
   raw stream, and the requested/returned model identity manifest. If any
   attestation failed, report an aborted review and produce no validated
   findings document.

## Constraints

- Read-only review: no `make build*`, no `make test*`, no binaries run.
- Diff base is `$BASE_REF` (three-dot) — `origin/main` by default, a
  user-supplied parent branch for stacked PRs — never local `main`.
- No review is verified by the model that wrote it.
- Every model response has runner-returned `metadata.model_used` exactly equal
  to its requested roster identity.
- Unavailable, substituted, duplicated-roster, or unidentified models abort
  the review.
- No PAL call uses a continuation ID; the preflight sentinel probe must pass on
  every roster model.
- All intermediates in `$REVIEW_DIR`; only the final review enters the tree.

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Diffing against local `main` | Always `"$BASE_REF"...HEAD` after `git fetch origin` (default `origin/main`) |
| Reviewing a stacked PR against `origin/main` | The diff then includes the parent PRs' changes — set the base ref to the stack parent (e.g. `origin/feature-part-1`) |
| Verifier same model as reviewer | Re-draw from the list minus the reviewer's model |
| Using clink for a named model | Managed PAL disables clink; use attested PAL chat with an exact model |
| Accepting an unavailable model under its requested label | Abort; never substitute or relabel |
| Trusting the requested model field | Verify runner-returned `metadata.model_used` with the helper |
| Treating unverified claims as findings | Only VALID claims with severity survive Stage 2 |
| Running tests "to confirm" a claim | This skill is review-only; cite code, not runs |
