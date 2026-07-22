# Partner Reviewing Agent

Run as the reviewing half of a two-agent workflow. Watch the current repository
for new commits. For each newly observed commit, run a deep PR-style review of
that commit and publish every actionable finding as its own Markdown file under
`doc/observations/`.

This command is agent-neutral: use it from Claude Code, Codex, or another
coding agent. Use the local `deep-review` command or skill if available. If no
deep-review capability is available, perform the same multi-pass review
manually.

## Arguments

Interpret `$ARGUMENTS` as follows:

- Empty: start from the current `HEAD` as the baseline and review commits that
  appear after the command starts.
- A single git ref: use that ref as the baseline, then watch for commits after
  it.
- A commit range such as `A..B`: review every commit in the range once, then
  continue watching from `B`.
- A positive integer: use it as the poll interval in seconds, with the baseline
  defaulting to current `HEAD`.
- A ref plus a positive integer: use the ref as baseline and the integer as the
  poll interval.

Default poll interval: 15 seconds.

## Setup

1. Resolve the repository root with `git rev-parse --show-toplevel` and operate
   from that directory.
2. Create `doc/observations/` if it does not exist.
3. Store private watcher state under `.git/partner-reviewer/`, not in the work
   tree.
4. If there is no prior watcher state and no explicit baseline was provided,
   write the current `HEAD` as the last-reviewed commit and wait for future
   commits.
5. Never stage or commit observation files. The reviewing agent only produces
   coordination files.

## Commit Watch Loop

Repeat until the user stops the command:

1. Read the last-reviewed commit from `.git/partner-reviewer/last-reviewed`.
2. Resolve the current `HEAD`.
3. If `HEAD` equals the last-reviewed commit, sleep for the poll interval and
   continue.
4. If the baseline commit is no longer an ancestor of `HEAD` because of a
   rebase, record the old baseline in `.git/partner-reviewer/rebased-baselines`,
   set the new baseline to `HEAD`, and continue watching. Do not flood the
   repository by reviewing rewritten history unless the user explicitly passed a
   range.
5. List commits in first-parent chronological order with:
   `git rev-list --first-parent --reverse <last-reviewed>..HEAD`
6. Review each listed commit independently. After each successful review, update
   `.git/partner-reviewer/last-reviewed` to that commit.

## Review Procedure

For each commit SHA:

1. Inspect the commit metadata and file list:
   `git show --stat --oneline --decorate <sha>`
   `git diff-tree --no-commit-id --name-only -r <sha>`
2. Invoke the `deep-review` command or skill against exactly that commit,
   treating it like a PR -- for example, run `deep-review` with `<sha>^!` as its
   argument.
3. If the local deep-review tool does not accept `<sha>^!`, review the output of
   `git show --find-renames --find-copies --stat --patch <sha>` directly.
4. Focus on actionable defects: correctness bugs, security problems,
   regressions, missing required tests, broken public contracts, unsafe
   migrations, serious performance issues, and documentation errors that could
   mislead future changes.
5. Exclude coordination-only changes under `doc/observations/` unless they
   affect executable behavior or the workflow itself.
6. Drop vague preferences, style nits, low-confidence concerns, and duplicate
   findings. Prefer zero observations over noisy observations.

## Ideas and Suggestions

Beyond defects, surface genuinely useful new ideas, creative insights, and
suggestions on approach or direction sparked by the commit under review:
better designs, missing capabilities, follow-on optimizations, simpler
formulations, or where the work could go next.

This is strictly opt-in on quality. Include an idea only when it is concrete,
grounded in the code you just read, and clearly valuable. If you have no ideas,
or the ideas are weak, leave them out — silence is better than noise. Never pad
a review with speculative directions to look thorough.

Be playful and think laterally. Instead of refining the obvious solution
head-on, move sideways: reframe the problem, attack it from an oblique angle,
and let unexpected associations suggest approaches a straight-line analysis
would never reach. The best ideas often come from refusing the obvious frame,
so for each commit that sparks something, run this ideation pass:

1. **Identify the hidden assumptions** the commit takes for granted (about the
   data, the hardware, the workflow, the order of operations, what "must" be
   true).
2. **Invert one assumption** and follow where that leads.
3. **Generate three "wild" ideas** that violate conventional thinking while
   remaining physically and ethically possible.
4. **Borrow one technique from an unrelated discipline** (biology, logistics,
   music, finance, game design, etc.) and apply it here.
5. **Explain why each seemingly crazy idea might actually work** — the concrete
   mechanism that makes it plausible, not just the vibe.

Keep the playfulness in service of usefulness: a wild idea still has to be
concrete and grounded enough to act on. Discard the ones that are only clever.

Publish each idea worth keeping as its own observation file using the same
contract below, with `Category: Idea` and a severity reflecting its value
(usually `Low`). State the idea, why it helps, a concrete first step, and how to
validate it. Tie it to the commit that inspired it. Ideas are distinct from
defects: do not let them displace or dilute the actionable-defect findings.

## Observation File Contract

Create one Markdown file per actionable finding. Each file must be complete
before it appears in `doc/observations/`.

Use this shape:

```markdown
# Observation: <short imperative title>

- **Source commit**: `<full-sha>`
- **Observed at**: `<ISO-8601 UTC timestamp with milliseconds>`
- **Severity**: Critical | High | Medium | Low
- **Category**: Bug | Security | Performance | Test Coverage | Documentation | Maintainability | Idea
- **File**: `path/to/file.ext:line`
- **Confidence**: <0-100>

## Problem

<Concrete description of what is wrong.>

## Impact

<Why this matters.>

## Suggested Fix

<Specific remediation. Include code when useful.>

## Verification

<Tests, commands, or manual checks that should prove the fix.>
```

For `Category: Idea` files, keep the same headers but read them as: **Problem**
= the idea and the gap it addresses, **Impact** = why it is worth doing,
**Suggested Fix** = a concrete first step, **Verification** = how to validate it
pays off.

Use the full ISO timestamp as the filename:

```text
doc/observations/YYYY-MM-DDTHH:MM:SS.mmmZ.md
```

Generate timestamps in UTC. If a filename already exists for the current
millisecond, wait until the next millisecond and generate a new timestamp. Do
not add counters, titles, or SHA fragments to the filename.

## Atomic Write Requirement

Never stream a partial observation directly into its final pathname.

For each observation:

1. Build the complete Markdown content first.
2. Write it to a temporary hidden file in `doc/observations/` on the same
   filesystem, for example `.2026-06-19T23:59:59.123Z.md.tmp.<pid>`.
3. Flush and close the file.
4. Atomically rename it into place with the final timestamp filename.
5. If the final path already exists, discard the temp file, wait for a fresh
   millisecond timestamp, and try again.

## Reporting

After each reviewed commit, report:

- The commit reviewed.
- The number of actionable observations written.
- The number of idea observations written, if any.
- The observation filenames written, if any.

Keep running after reporting unless the user stops the loop.
