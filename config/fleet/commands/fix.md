# Think, Research, Plan, Act, Review

Think deeply to analyze the following query, construct a well thought out plan of action based on the following context, and then carefully execute that plan step by step.

If you find that the bug or feature you’re attempting to fix has already been addressed in an earlier commit, just add a regression test to demonstrate the item has been dealt with.

Create a PR using my jwiegley user on GitHub. The author/committer for all new commits should be signed by johnw@newartisans.com.

This job will take a long time, so make a comprehensive and effective plan and then execute step by step until you have completed it and added new regression tests.

Now, please analyze and fix the GitHub issue: $ARGUMENTS.

NOTE: Do not work on a bug that already has a PR open that addresses it. In that case, just give the PR number and stop immediately.

# If present, change confirmation tests into regression tests

Sometime an issue will already have a “confirmation test” in the directory test/todo, with the name `<ISSUE-NUMBER>.test`. This test “confirms” the existence of the bug by stating the behavior as described in the issue report. What should happen if such a test exists is that the test gets moved to `test/regress` and then modified to test the correct expected behavior. You may need to use cpp-pro and your superpowers to thoroughly research and discover what this correct behavior should be. Modify the new regression test to express this behavior -- which will necessary fail at first -- with the aim of correcting the issue until the test passes, plus whatever other additional tests you may add to confirm that no other behaviors have been impacted by the fixes you made to the issue under question.

# Follow these steps

1. Use `GH_TOKEN="$(gh auth token --hostname github.com --user jwiegley)" gh issue view` to get the issue details
2. Understand the problem described in the issue
3. Search the codebase for relevant files
4. Implement the necessary changes to fix the issue
5. Write and run tests to verify the fix
6. Ensure code passes linting and type checking

Remember the following:
- Use `GH_TOKEN="$(gh auth token --hostname github.com --user jwiegley)" gh ...` for all GitHub-related tasks
- Search the codebase for relevant files
- Ensure code passes linting and type checking after doing any work
- Use cpp-pro, python-pro, emacs-lisp-pro, rust-pro or haskell-pro as needed for diagnosing and analyzing PRs, fixing code, and writing any new code.
- Use available live web search as needed for research and discovering resources.
- Use sequential-thinking when appropriate to break down tasks further.
- Use context7 whenever code examples might help.

When the fix is verified, follow the `commit` command's atomic decomposition, sequencing, message, staging, and per-commit verification rules.

# Monitor your work after submitting the PR

Use `GH_TOKEN="$(gh auth token --hostname github.com --user jwiegley)" gh ...` to monitor CI results and possible BugBot comments. If CI is failing, diagnose and resolve it, push the fixes, and continue monitoring with the same account-scoped form until everything passes.

Also, if there are any BugBot, Cursor or Devin comments on this PR, I want you to fix and address these comments from these bots, and then after you have pushed the fixes, I want you to reply to those comments and then mark them resolved.
