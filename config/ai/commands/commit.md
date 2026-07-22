Commit all work as a series of atomic, logically sequenced commits. Each commit should represent one coherent change that can be understood, reviewed, and reverted independently.

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
