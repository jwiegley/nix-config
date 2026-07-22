Produce a situational report, or sitrep, for the current work. Treat the user's
request and any `$ARGUMENTS` as the scope of the report.

The sitrep is for a human reviewer who needs to understand what the currently
working AI agent is trying to accomplish, how much progress has been made, what
stands in the way, and how available compute or reviewer attention might best be
used next. Write from the current state of the project, not from memory alone.

First gather evidence:

- Read the latest user request, active plan, task list, checklist, issue, PR,
  specification, journal, or handoff document that defines the present goal.
- Inspect the working tree and recent history as appropriate: `git status`,
  relevant diffs, recent commits, changed files, test output, benchmark output,
  logs, generated artifacts, or runtime state.
- Look for recent measurements that indicate movement toward the goal. Depending
  on the project, these may include performance numbers, memory use, quality
  scores, test counts, coverage, lint/type-check results, build times, failure
  rates, data quality checks, queue depth, throughput, token/time budget usage,
  elapsed time, or completed/remaining task counts.
- If a measurement would be useful but has not been taken, say so plainly rather
  than inventing one.

Write the sitrep in a Markdown file in the `~/dl` directory -- create it if it
does not exist, and never write it into the project or current directory -- following
the strict naming scheme `YYYYMMDDTHHMM-SITREP-$PROJECT-$BRANCH.md` -- with the
`YYYYMMDDTHHMM` being replaced by a timestamp having that format (in local
time for the server), and `$PROJECT` being replaced by the name of the
repository or project, and `$BRANCH` being replaced by the name of the branch
with any ’/’ characters replaced by ’-’ -- with these sections:

## Aim

Restate the full objective the agent is presently trying to accomplish. Include
the source of the objective when it is known, such as a user request, issue, PR,
handoff, or plan. Do not shrink the aim to the work already completed.

## Accomplishments

Give a full accounting of what has been accomplished so far. Name the concrete
artifacts, files, commits, tests, documents, or runtime changes that prove the
work has moved. Distinguish completed work from work that is merely started or
inferred.

## Next Steps

List the next actions in the order they should be taken. Keep them specific
enough that another agent could resume from the report without rediscovery.

## Blockers And Stumbling Blocks

Call out anything preventing progress, slowing progress, or carrying meaningful
risk. Separate hard blockers from ordinary uncertainty, technical debt, flaky
signals, missing context, environmental failures, reviewer decisions, and
unverified assumptions.

## Measurements

Report the recent measurements that best show progress toward the goal. Include
the command, artifact, or observation that produced each measurement when that
matters. If no meaningful measurements are currently available, say what would
need to be measured next and why.

## Distance To Completion

Estimate how far away the goal is in both time and effort. Give the estimate as
a range when uncertainty is material. State the assumptions behind the estimate:
remaining task count, known unknowns, expected verification cost, external
dependencies, review time, or computational cost.

## Parallel Work

Identify upcoming work that could be done in parallel without disrupting the
current path. For each candidate, say why it is safe to parallelize, what inputs
it needs, what output it should produce, and what conflicts or coordination
risks to watch for. If nothing should be parallelized yet, say that and explain
which dependency must be resolved first.

## Recommendation

End with a short recommendation for the reviewer: continue with the current
agent, allocate another agent to a named parallel task, pause for a decision,
run a specific verification step, or change course. Base this recommendation on
the evidence above.

Keep the report direct and useful. Prefer concrete status over narrative color.
Do not hide weak evidence, missing measurements, or optimistic estimates behind
polished prose.
