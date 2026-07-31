Process every PR in the current Graphite stack to address all bot comments. Follow this protocol exactly.

## Step 1: Enumerate the Stack

1. Run `gt ls -s` to list all branches in the current stack.
2. For each branch, get the PR number: `gh pr view BRANCH --json number -q .number`
3. Record the ordered list of (branch, PR number) pairs from bottom (closest to main) to top.
4. If there is no stack or no open PRs, report that and stop.

## Step 2: Process Each PR Bottom-Up

Work through the stack from the **bottom** (base, closest to main/trunk) to the **top** (most recently created). Processing bottom-up prevents rebase conflicts when fixes cascade upward.

For each PR in order:

1. Check out the branch: `gt checkout BRANCH_NAME`
2. Spawn a sub-agent to run the `/bugbot` command for this PR with the following additional instruction:

   > **Exclusion rule: Do NOT address, reply to, or resolve comments from human co-workers. Specifically exclude Alexey, Ben, and any other clearly human reviewer. Only process comments from bots and automated tools.**

3. Wait for the sub-agent to complete. It should report a verified tally (e.g., "5/5 bot comments resolved").
4. If the sub-agent reports unresolved items, note the PR number and item details for the final report.
5. Before moving to the next PR, confirm the sub-agent's work is pushed to the remote.

## Step 3: Final Verification

After all PRs have been processed:

1. For each PR in the stack, use `gh api graphql` to fetch the count of unresolved review threads where the original comment's `author.__typename` is `"Bot"` (or login matches bot heuristics as a fallback).
2. Output a summary table:
   - PR number and branch name
   - Total bot comments found
   - Bot comments resolved
   - Any remaining unresolved (with thread ID and reason)
3. If all bot comments across all PRs are resolved, report success.
4. If any remain, list them explicitly so they can be addressed manually or in a follow-up run.
