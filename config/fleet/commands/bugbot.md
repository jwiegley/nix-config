There are bot comments on this PR (from BugBot, Graphite, Cursor, Devin, or similar automated tools) that need to be fixed and resolved. Follow this exact 5-phase protocol. Do not skip or reorder phases.

## Phase 1: INVENTORY

Before making any code changes, build a complete inventory of every unresolved bot comment.

1. Determine the current PR number (`gh pr view --json number -q .number`).
2. Use `gh api graphql` to fetch ALL review threads for this PR, including each thread's `id`, `isResolved`, `path`, `line`, and the `author.login`, `author.__typename`, and `body` of each comment in the thread.
3. Also fetch all top-level PR comments (issue comments) with their `id`, `author.login`, `author.__typename`, `body`, and `isMinimized` status.
4. Filter to only **unresolved** items from bot/automated authors. An author is a bot if `author.__typename` is `"Bot"` (this catches cursor, graphite-app, github-actions, etc. regardless of login naming). As a fallback for any API response missing `__typename`, also match logins containing "bot", "[bot]", or "app/". **Exclude all human authors** (`__typename: "User"`).
5. Categorize each item:
   - **Review thread**: inline code comment with a resolvable thread ID
   - **Top-level comment**: PR-level comment (can be replied to but not "resolved" in GitHub's sense)
6. Output the full numbered inventory as a checklist before proceeding. For each item include: number, author, category, file:line (if applicable), one-line summary of the issue raised.
7. If there are zero bot comments to address, report "No unresolved bot comments found" and stop.

## Phase 2: FIX

For each item in the inventory:

1. Read the bot's comment carefully and understand the exact issue it raises.
2. Read the relevant source code.
3. Make the code change that addresses the issue. If the comment is purely informational or a false positive requiring no code change, note that explicitly — you still must reply and resolve it in Phase 4.
4. Commit fixes with clear messages referencing what was addressed.

## Phase 3: PUSH

Push all commits to the remote branch:

```
git push
```

If the push fails due to remote changes, pull with rebase first (`git pull --rebase`), then push again.

## Phase 4: REPLY & RESOLVE

After pushing, process EVERY item from the Phase 1 inventory. Check off each item as you go.

**For each review thread:**

1. Reply to the thread explaining what you fixed (keep it brief — one or two sentences), or explain why no change was needed:
   ```
   gh api graphql -f query='
     mutation($threadId: ID!, $body: String!) {
       addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
         comment { id }
       }
     }' -f threadId='THREAD_NODE_ID' -f body='Fixed: <brief explanation>'
   ```
2. Then immediately resolve the thread:
   ```
   gh api graphql -f query='
     mutation($threadId: ID!) {
       resolveReviewThread(input: {threadId: $threadId}) {
         thread { isResolved }
       }
     }' -f threadId='THREAD_NODE_ID'
   ```
3. Confirm the response shows `isResolved: true`. If not, retry once.

**For each top-level comment:**

1. Reply to the comment explaining what you fixed (substitute the actual PR
   number from Phase 1 — `gh` expands `{owner}`/`{repo}` automatically, but
   not the PR number):
   ```
   gh api repos/{owner}/{repo}/issues/<pr-number>/comments -f body='Fixed: <brief explanation>'
   ```
2. Minimize the original bot comment as resolved:
   ```
   gh api graphql -f query='
     mutation($id: ID!) {
       minimizeComment(input: {subjectId: $id, classifier: RESOLVED}) {
         minimizedComment { isMinimized }
       }
     }' -f id='COMMENT_NODE_ID'
   ```

## Phase 5: VERIFY

1. Re-fetch all review threads for this PR using the same query from Phase 1.
2. For every item in your Phase 1 inventory, confirm:
   - Review threads: `isResolved` is now `true`
   - Top-level comments: `isMinimized` is now `true`
3. If ANY inventory items remain unresolved, list them and retry Phase 4 for just those items.
4. Only report completion when **every item from the original inventory** has been verified as resolved. Report the final tally: "N/N bot comments resolved."

**Important:** The verification must check only items from the original Phase 1 inventory. If new bot comments appeared during processing, ignore them — they will be caught in a subsequent run.
