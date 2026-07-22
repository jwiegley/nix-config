Please analyze and fix the GitHub issue: $ARGUMENTS.

Follow these steps:

1. Use `git worktree` to create a worktree and branch for the issue inside a
   `work` sub-directory. for example, if the issue number is 1024, then create
   a branch named `fix-1024` and a working tree that has checked out that
   branch in `work/fix-1024`.
2. Use `gh issue view` to get the issue details
3. Understand the problem described in the issue
4. Search the codebase for relevant files
5. Implement the necessary changes to fix the issue
6. Write and run tests to verify the fix
7. Ensure code passes linting and type checking
8. Leave your work uncommitted in the working tree, so it can be reviewed.

Remember the following:

- Use the GitHub CLI (`gh`) for all GitHub-related tasks.
- Use cpp-pro or python-pro or emacs-lisp-pro or rust-pro as needed for
  diagnosing and analyzing issues, fixing code, and writing any new code.
- Use Web Search and Perplexity as need for research and discovering resources.
- Use sequential-thinking when appropriate to break down tasks further.
- Use context7 whenever code examples might help.
