# fess audit -- scope and context snapshot

How to run the per-commit `fess` self-audit inside the wiggum loop.

## When

After each commit that advances the work. Do NOT separately re-audit commits whose only purpose is to fix problems a prior `fess` run found, nor `partner-cleanup`'s own cleanup commits (it self-verifies through its own subagent) -- auditing fixes of fixes loops without making progress. Do not let the perfect become the enemy of the good. Before declaring the work done, run one final audit over the last work commit even if the most recent commits were themselves fixes.

## Scope: how many commits to audit

Read the commit description, then choose an audit range of 1 to 10 recent commits:

- 1 commit for isolated, self-contained work.
- Expand the range when the description points to follow-up work, stacked changes, refactors, shared infrastructure, earlier groundwork, or claims whose truth depends on previous commits.

Record the selected commit SHAs and one line on why that range was chosen.

## Context snapshot to hand the fess subagent

Each subagent starts with none of your context, and the audit must judge the commits against the full context that produced them. Include:

- the original user request (exact wording where practical);
- the current plan and handoff state;
- relevant design decisions and trade-offs;
- notable commands run and their verification results;
- the commit SHA or SHAs under audit and the files each changed;
- the specific claims you have made about the work.

Preserve exact wording for requirements and claims when practical. If the context is too large, include a dense summary plus the exact excerpts needed so intent is not lost.

## Acting on findings

Verify each finding before acting -- convert uncertainty into a verification step rather than assuming the finding is right or wrong. Fold real fixes into your main development work and commit them normally. Remember not to re-audit those fix commits.
