# fix-all

A relentless fix-everything skill. Where [`fess`](../fess) only audits and
reports, `fix-all` acts: it takes the findings uncovered during a piece of
work and fixes **every one of them**, here and now. "Out of scope,"
"pre-existing," and "follow-up ticket" are not acceptable framings — if it
surfaced, it gets fixed.

It encodes a strict bar for *how* the fixing happens:

- **Parallelize** independent work across subagents and git worktrees
  (prefixed `wg-<short-id>/` for trivial cleanup). Subagents are told the
  rules explicitly — they don't inherit this prompt by osmosis.
- **One finding per TODO**, double-checked against the full findings list so
  nothing slips.
- **Commits** are atomic and explain *why*.
- **Tests** for everything changed, of the kind that actually catch the bug.
  No reward hacking — no weakened assertions, skipped tests, or tautologies.
- **Upstream fixes are non-negotiable.** A problem caused upstream is fixed
  upstream (the source, the dependency), never papered over with a
  downstream shim.

## Install

```bash
ln -sfn ~/code/llm-toolbox/skills/fix-all ~/.claude/skills/fix-all
```

Then type `/fix-all` in any Claude Code session — typically right after a
review or a `/fess` audit has produced a list of findings you want driven to
zero.

## Pairs well with `fess`

Run [`fess`](../fess) to surface what was stubbed, faked, swallowed, or
glossed over; run `fix-all` to drive that list to done without deferrals.
