# Current Work

Updated: 2026-07-31

This is the repository's current local work boundary. Completed plans and session
handoffs belong in Git history, not beside active instructions.

## Active order

1. Finish the all-lock and all-pin `make update` transaction and activate its exact
   candidate.
2. Run one final focused verification and independent fess audit.

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
- GitHub issue/project/wiki operations remain deferred; ordinary dual-remote
  publication is still part of the update transaction.

## Current verified state

- `main`, Gitea, and GitHub matched when this work began; the current local commits
  remain unpublished until the final update succeeds.
- Hera's active Nix-managed Pi configuration exposes
  `openai-codex/gpt-5.6-sol` with a 1.1M-token context.
- GitHub state has not been queried during this cleanup.

## Completed in this lane

- Reduced 28 documentation artifacts to seven current documents and removed 10,370
  stale lines.
- Replaced retired deployment terminology in generated Codex projections and the
  bundle-discovery command.
- Corrected `make update` to publish through the dual-remote `bin/publish` path.
- Required every stored GitHub inventory recipe to select the `jwiegley` account.
- Regenerated and verified the consumer inventory.
- Integrated the SearXNG MCP package and host-specific Clio/Hera/Vulcan routing;
  its launcher strips unrelated inherited credentials.
- Repaired Codex command/prompt projections so their manifests are regular files
  that Codex can discover.
- Reduced the mandatory pre-push gate to fast signature and structural-coverage
  checks; the broader checks remain under `make expensive`.
- Removed completed and obsolete worktrees. The unfinished issue 54 and issue 58
  branches remain as local refs without dedicated worktrees; the external Claude
  scratchpad was left untouched.

## Resume point

Run the complete `make update` transaction, verify the active generation and agent
surfaces, then perform the final audit. GitHub reconciliation remains deferred.

Stop-and-escalate counters:

- repeated failing verification signature: 0/3;
- unusable subagent output: 0/2;
- unresolved destructive or intent-sensitive action: none.
