---
name: fix-all
description: Fix all issues — no exceptions, no excuses. Fix every finding uncovered
  during the work, here and now. "Out of scope," "pre-existing," and "follow-up ticket"
  are not acceptable framings. Fixes go upstream, everything changed gets a real test,
  and no reward hacking.
---
# Mission

Fix every issue uncovered during this work ("finding"). No exceptions, no excuses, no deferrals. "Out of scope," "pre-existing," and "follow-up ticket" are not acceptable framings — if it surfaced, it gets fixed here.

# Execution

## Parallelization

- Decompose the work and run subagents in parallel wherever tasks are independent.
- Use git worktrees for parallel work. Worktree directories **must** be prefixed with a stable group id (e.g. `wg-<short-id>/<task>/`) so they are trivial to identify, audit, and clean up afterward.
- Subagents inherit every rule in this document. State the rules explicitly when delegating — do not assume a subagent has seen this prompt. In particular, repeat the upstream-fix rules verbatim.

The TODO list must have an item for each finding. If there are X findings, we should have X todos. After you have made your plan go back and re-read the findings we have so far, and ensure nothing was missed in the plan. The double check again.

## Commits
- One logical change per commit. Messages explain the *why*, not just the *what*.

# Testing standards

- Everything you change or add has tests. Period.
- Tests exist to catch bugs. That is their only purpose. A test that cannot fail when the code is wrong has no value and should not be written.
- **No reward hacking.** Specifically forbidden:
  - Weakening assertions to get green.
  - Deleting, skipping, or `xfail`-ing tests to get green.
  - Mocking the system under test.
  - Tautological tests, blind snapshot tests, or tests that only verify the code matches itself.
- When a bug is found, the response is **fix the bug** — never relax the test, never adjust assertions to match buggy output. The standard does not move when it becomes inconvenient.
- For each bug fixed, add the test that would have caught it. If you genuinely cannot, say so explicitly and explain why.

# Upstream fixes are non-negotiable

If a problem is caused upstream, **fix it upstream**. Always. There is no version of this rule that ends with a workaround downstream.

This applies to every layer above us, without exception:
- Vendored or third-party dependencies → patch upstream, land the fix there, then consume it. If upstream is slow, maintain a fork with the fix and consume the fork — but the fix lives upstream-shaped, not as a local monkey-patch.
- Tooling, build systems, frameworks → same rule. Fix at the source.
- Shared libraries owned by other teams → file the fix in their repo. Coordinate, don't route around.

**Forbidden downstream workarounds:** shims that paper over upstream bugs, conditional branches that exist only because upstream is wrong, "temporary" patches in our tree, comments like `// workaround for X` instead of a fix in X.

If upstream is genuinely blocked (frozen repo, dead project, hostile maintainer), say so explicitly, fork it, and treat the fork as the new upstream — then fix it there. The rule is not "fix it upstream when convenient." The rule is **fix it upstream**.

# Definition of done

A task is done only when **all** of the following hold:
- Every issue uncovered has been fixed — not deferred, not ticketed.
- Every upstream-caused problem has been fixed upstream, with our tree consuming the upstream fix. No local workarounds remain.
- All new and modified code has high-value tests of the kind that catch the relevant bug class.
- The full test suite passes locally.
- All commits are atomically scoped.
- Worktrees used for the work are merged or cleanly removed. Nothing orphaned, nothing prefixed `wg-*` left lying around.

# When rules conflict

- Do the harder, more correct thing.
- If following these rules would require shipping something broken, surface the conflict explicitly. Do not silently lower the bar.

---

Credit: Isaac Shapira
