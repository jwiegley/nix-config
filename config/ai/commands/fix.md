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

1. Use `gh issue view` to get the issue details
2. Understand the problem described in the issue
3. Search the codebase for relevant files
4. Implement the necessary changes to fix the issue
5. Write and run tests to verify the fix
6. Ensure code passes linting and type checking

Remember the following:
- Use the GitHub CLI (`gh`) for all GitHub-related tasks
- Search the codebase for relevant files
- Ensure code passes linting and type checking after doing any work
- Use cpp-pro, python-pro, emacs-lisp-pro, rust-pro or haskell-pro as needed for diagnosing and analyzing PRs, fixing code, and writing any new code.
- Use Web Search and Perplexity as needed for research and discovering resources.
- Use sequential-thinking when appropriate to break down tasks further.
- Use context7 whenever code examples might help.

Commit all work as a series of atomic, logically sequenced commits. Each commit should represent one coherent change that can be understood, reviewed, and reverted independently.

# Monitor your work after submitting the PR

Use `gh` to monitor for CI test results and possible BugBot comments. If CI tests are failing for this PR, use the appropriate programming language agent to diagnose and resolve this issue, then push your fixes to the PR and monitor the CI test results using `gh` until you observe that everything passes correctly. If any further problems should be observed, repeat this diagnose, resolve, push and monitor process until everything is working with this PR.

Also, if there are any BugBot, Cursor or Devin comments on this PR, I want you to fix and address these comments from these bots, and then after you have pushed the fixes, I want you to reply to those comments and then mark them resolved.

# Commit Decomposition Principles

**Scope each commit to a single logical change.** A commit should do exactly one thing: add a function, fix a bug, refactor a module, update documentation. If you find yourself writing "and" in a commit message, consider splitting the commit.

**Sequence commits to tell a story.** Arrange commits so each builds naturally on the previous. A reviewer reading the series should understand why each change was made and how the code evolved. Foundational changes come before dependent ones.

**Keep each commit in a working state.** Every commit should compile, pass tests, and not introduce obvious regressions. This enables bisection for debugging and allows reviewers to check out any point in history.

# Categorizing Changes

Before committing, analyze the working tree and group changes into categories:

1. **Infrastructure/setup changes** — new dependencies, configuration, tooling
2. **Refactoring** — restructuring existing code without changing behavior
3. **New functionality** — features, APIs, modules
4. **Bug fixes** — corrections to existing behavior
5. **Tests** — new or modified test coverage
6. **Documentation** — comments, READMEs, inline docs

Commit these categories in order when dependencies exist between them. Refactoring that enables a new feature should precede the feature commit.

# Commit Message Format

```
<summary>

<body>

<footer>
```

**Summary line:** Imperative mood, no period, under 50 characters. Describe what applying the commit does, not what you did.

**Body:** Explain the motivation and contrast with previous behavior. Wrap at 72 characters. Focus on *why*, not *what* (the diff shows what).

**Footer:** Reference issues, breaking changes, or co-authors.

# Staging Strategy

Use selective staging to craft precise commits:

- `git add -p` for hunks within files
- `git add <specific-files>` to group related files
- Review staged changes with `git diff --staged` before committing

When a single file contains changes belonging to multiple logical commits, stage hunks separately rather than committing the entire file.

# Quality Checklist

Before finalizing each commit:

- [ ] Does this commit do exactly one thing?
- [ ] Could someone understand this change without seeing other commits?
- [ ] Is the commit message searchable? Will someone find this when grepping history?
- [ ] Does the code compile and pass tests at this point?
- [ ] Would reverting this commit cleanly undo one logical change?

# Example Decomposition

Given work that adds a feature with tests and required refactoring:

```
1. Extract token validation into dedicated module
2. Add unit tests for token validation
3. Implement refresh token rotation
4. Add integration tests for token refresh flow
5. Document refresh token behavior in API guide
```

Each commit is independently reviewable, the sequence shows logical progression, and future developers can find relevant changes through targeted searches.

# Handling Mixed Changes

If the working tree contains entangled changes:

1. **Identify the distinct changes** — list what logical modifications exist
2. **Determine dependencies** — which changes require others to be present
3. **Create a commit plan** — order commits to satisfy dependencies
4. **Stage incrementally** — use partial staging to isolate each change
5. **Verify at each step** — ensure the repository works after each commit

When changes are too entangled to separate cleanly, prefer a slightly larger commit with a clear message over a commit that leaves the repository in a broken state.
