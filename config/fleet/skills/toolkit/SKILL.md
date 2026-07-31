---
name: toolkit
description: The standard tooling and working discipline for planning and executing
  a coding task -- GitHub CLI, codebase search, the language -pro agents, web research,
  sequential thinking, context7, and lint/type-check gating. The /medium and /heavy
  effort-tier commands build on it; load it when told to apply the standard toolkit.
---
# Toolkit

The standard tooling and working discipline for planning and executing a task. The `/medium` and `/heavy` commands invoke this at their effort tier; `forge` is the heaviest tier and has its own multi-phase workflow (see the `forge` skill).

## Standard tooling

- Use the GitHub CLI (`gh`) for all GitHub-related tasks.
- Search the codebase for the relevant files.
- Use `cpp-pro`, `python-pro`, `emacs-lisp-pro`, `rust-pro`, or `haskell-pro` as needed to diagnose and analyze PRs, fix code, and write new code.
- Use Web Search and Perplexity (via the `web-searcher` agent) for research and discovering resources.
- Use `sequential-thinking` when appropriate to break a task down further.
- Use `context7` whenever code examples might help.

## Working discipline

- Ensure code passes linting and type checking after any change.
- Think deeply to analyze the task, construct a well-thought-out plan of action from the context and research at hand, and then carefully execute that plan step by step.

## Effort tiers

- `medium` -- this standard toolkit and discipline.
- `heavy` -- this toolkit plus multi-model consensus via PAL and Positron's Notion context.
- `forge` -- the full multi-phase, multi-model collaborative workflow (the `forge` skill).
