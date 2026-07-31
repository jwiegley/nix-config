# Current Work

Updated: 2026-07-31

This is the repository's current local work boundary. Completed plans and session
handoffs belong in Git history, not beside active instructions.

## Active order

1. Remove stale, duplicated, completed, and abandoned repository documentation;
   retain only current architecture, runbooks, and this work ledger.
2. Finish the all-lock and all-pin `make update` transaction and activate its exact
   candidate.
3. Finish and integrate `feature/mcp-searxng`.
4. Rebase or integrate owned completed worktrees, fast-forward their results into
   `main`, and remove the worktrees and local branches that are no longer needed.
5. Run one final verification and independent fess audit.

## Explicit boundaries

- The former cross-client deployment tool is retired and is not a task,
  dependency, comparison oracle, or deployment mechanism.
- GitHub issue, project, and wiki reconciliation is deferred until the user
  explicitly resumes it.
- When GitHub work resumes, every `gh` command must select the `jwiegley` account:

  ```bash
  GH_TOKEN="$(gh auth token --hostname github.com --user jwiegley)" gh <command>
  ```

- Do not edit Vulcan's separate NixOS configuration while working in this
  repository.
- Publication, activation, destructive cleanup, and history rewriting remain
  separately authorized actions.

## Current verified state

- Base revision: `dd736e225b4c3a84bbaf696bfb6e630c8d1eb732`.
- `main`, Gitea, and GitHub matched at that revision when this work began.
- Hera's active Nix-managed Pi configuration exposes
  `openai-codex/gpt-5.6-sol` with a 1.1M-token context.
- Documentation cleanup runs on `chore/dead-code-pass-1`.
- GitHub state has not been queried during this cleanup.

## Resume point

The cleanup reduces 28 documentation artifacts to seven current documents. The
remaining step for this unit is to regenerate the consumer inventory, run the
documentation and bounded repository checks, commit, and obtain an independent
fess verdict.

Stop-and-escalate counters:

- repeated failing verification signature: 0/3;
- unusable subagent output: 0/2;
- unresolved destructive or intent-sensitive action: none.
