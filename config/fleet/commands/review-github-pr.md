Please analyze and review the GitHub PR: $ARGUMENTS.

See also -- review ladder: `quick-review` is a fast single-pass rung;
`code-review` is a comprehensive named-agent health checkup; `deep-review` is
the heavy multi-agent, multi-language pass; `sec-audit` narrows the focus to
security; `review-github-pr` (this one) reviews a GitHub PR in a worktree and
never posts back.

## CRITICAL: DO NOT POST TO GITHUB

**NEVER, UNDER ANY CIRCUMSTANCES, post reviews, comments, or any content directly to the GitHub PR.**

- Do NOT use `gh pr review`
- Do NOT use `gh pr comment`
- Do NOT use any GitHub CLI command that writes to the PR
- Do NOT submit feedback to GitHub in any form

**ALL review output must be presented as a Markdown report to the user FIRST.**

The user will review your analysis and decide what (if anything) to post to GitHub themselves.

---

## Review Process

Follow these steps:

1. Use `git worktree` to create a worktree and branch for the PR inside a `work` sub-directory. For example, if the PR number is 1024, then create a branch named `pr-1024` and a working tree that has checked out that branch in `work/pr-1024`. However, only do this if you are not already in a working tree under the `work` directory.
2. Use `gh pr view` to get the PR details (read-only)
3. Use `gh pr diff` to get the PR diff (read-only)
4. Understand the problem described in the PR
5. Search the codebase for relevant files
6. Review any comments that have already been made to the PR (read-only)
7. Run all tests to verify the PR
8. Ensure code passes linting and type checking
9. **Present your complete review as a Markdown report directly in your response to the user**
10. Also save the report as a Markdown file in the working tree for reference

## Output Format

Your review report should include:
- Summary of the PR
- Strengths identified
- Concerns and suggestions
- Code review notes for specific files/lines
- CI status
- Final recommendation (approve/request changes/comment)

## After Presenting the Report

If any review comments are particularly important, you may **suggest** submitting them as comments - but ONLY after the user has reviewed the report and explicitly confirms they want you to post.

---

## Tools and Resources

- Use the GitHub CLI (`gh`) for all GitHub-related tasks (READ-ONLY operations only until user approves posting)
- Use cpp-pro, python-pro, emacs-lisp-pro, rust-pro or haskell-pro as needed for diagnosing and analyzing PRs, fixing code, and writing any new code.
- If this worktree is anywhere under the "positron" or "pos" directories, then use pal to confer with gemini-3.1-pro-preview and gpt-5.5-pro to reach consensus on your deep analysis and review.
- Use Web Search and Perplexity as needed for research and discovering resources.
- Use sequential-thinking when appropriate to break down tasks further.
- Use context7 whenever code examples might help.
