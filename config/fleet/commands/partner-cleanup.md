# Partner Observation Consumer

Run as the main-agent half of a two-agent workflow. Drain actionable findings
from `doc/observations/`, have a sub-agent address them one by one, and make a
single cleanup commit only after every current observation has been handled.

This command is agent-neutral: use it from Claude Code, Codex, or another
coding agent. Prefer the local sub-agent or Task facility. If no sub-agent
facility is available, perform the same workflow in the current agent and say
that no sub-agent tool was available.

## Scope

Interpret `$ARGUMENTS` as the observations directory. If empty, use
`doc/observations/`.

Only process regular, non-hidden `*.md` files directly inside the observations
directory. Ignore temp files, dotfiles, and nested directories.

## Preconditions

1. Resolve the repository root with `git rev-parse --show-toplevel` and operate
   from that directory.
2. Capture the first observation batch by sorting filenames lexicographically.
   The timestamp naming scheme makes this chronological.
3. Check the working tree before making source edits.
   - If there are no observation files, report that there is nothing to do and
     exit.
   - If the only changes are untracked observation files, proceed.
   - If there are unrelated source changes, do not overwrite or stage them.
     Either work around them safely or stop and report the conflict.

## Cleanup Loop

Repeat until the observations directory has no regular, non-hidden `*.md`
files:

1. Capture the current batch by sorting filenames lexicographically.
2. Spawn a focused sub-agent for that batch.
3. Review the sub-agent's work.
4. Rescan the directory. If new observation files appeared while cleanup was in
   progress, process them before committing.

## Sub-Agent Assignment

Give each sub-agent this assignment:

```text
You are addressing partner review observations in this repository.

Process these observation files in order:
<absolute or repo-relative list>

For each observation:
1. Read the observation completely.
2. Verify that the finding is still applicable.
3. If it is valid, implement the smallest correct fix and add or update focused
   tests when the risk warrants it.
4. If it is obsolete or false positive, document the evidence in your handoff
   instead of changing code.
5. Remove the observation file only after the item has been addressed or proven
   inapplicable.
6. Do not commit. Leave all changes staged or unstaged for the main agent to
   review.

Return a concise handoff listing each observation file, the resolution, changed
files, and verification performed.
```

If the environment supports multiple sub-agents and the observations are
independent, parallel sub-agents may be used. Do not parallelize observations
that touch the same files or behavior.

## Main-Agent Review

After each sub-agent returns:

1. Inspect the diff and confirm that every captured observation file was either
   removed or explicitly justified as inapplicable in the handoff.
2. Re-read any observation whose fix looks uncertain. Do not accept a superficial
   deletion.
3. Run the verification commands named by the sub-agent. Add reasonable local
   tests if the handoff omitted necessary verification.
4. Ensure no captured observation files remain. If any remain, continue the
   cleanup loop before committing.
5. Rescan for newly arrived observation files and continue the cleanup loop
   before committing.

## Commit Rules

Make exactly one commit for the completed batch, unless there are no code,
test, or documentation changes because every observation was proven
inapplicable.

Commit only the cleanup changes and the removal of any tracked observation
files. Do not add untracked observation files to the repository. If observation
files were untracked and removed after being handled, they will not appear in
the commit.

Use a message like:

```text
Address partner review observations

Resolve observations from <first timestamp> through <last timestamp>.
```

After committing, check `doc/observations/` again. If new observation files are
already present because the reviewing partner reacted to the cleanup commit,
report that another cleanup cycle is available; do not keep looping forever
unless the user explicitly asked for continuous cleanup.

## Completion Report

Report:

- Observation files processed.
- Summary of fixes or inapplicable findings.
- Verification commands and results.
- Commit SHA, or why no commit was made.
