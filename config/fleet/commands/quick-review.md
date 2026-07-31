# Quick Code Review

Perform a fast, single-pass code review without spawning sub-agents. This is
for rapid feedback during development, not for pre-merge thoroughness.

See also -- review ladder: `quick-review` is the fastest single-pass rung;
`code-review` is a comprehensive named-agent health checkup; `deep-review` is
the heavy multi-agent, multi-language pass; `sec-audit` narrows the focus to
security; `review-github-pr` reviews a GitHub PR in a worktree and never posts
back. Pick the lightest rung that fits.

## Scope

Determine what to review from `$ARGUMENTS`:
- Git ref / range → `git diff $ARGUMENTS`
- File paths → review those files
- Empty → uncommitted changes, or last commit if clean

## Review

Read each changed file and its diff. For each file, check for:

1. **Obvious bugs**: null/nil dereference, off-by-one, logic inversions, typos
2. **Security red flags**: hardcoded secrets, unsanitized input, `eval`/`exec`
3. **Error handling gaps**: unchecked returns, swallowed exceptions, missing cleanup
4. **Clear style violations**: inconsistent naming, dead code, TODO/FIXME/HACK markers

## Output

For each finding:
```
**[SEVERITY]** `file:line` — Brief description. Suggested fix.
```

Keep it concise. If the code looks fine, say "No issues found" with a brief
summary of what you reviewed.
