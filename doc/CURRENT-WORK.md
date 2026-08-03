# Current Work

Updated: 2026-08-03

## Active programme

Cleanup epic [#98](https://github.com/jwiegley/nix-config/issues/98) is active.
The frozen Definition of Done is [`CLEANUP-PLAN.md`](CLEANUP-PLAN.md), and
[`CLEANUP-WIGGUM-HANDOFF.md`](CLEANUP-WIGGUM-HANDOFF.md) is the current resume
authority.

Active work unit: C0, [issue #99](https://github.com/jwiegley/nix-config/issues/99),
truthful current documentation. Native blocked-by links in Project 9 determine the
remaining order; do not skip them.

## Current verified state

- Local `main`, fetched Gitea `origin/main`, and fetched GitHub `github/main` form
  the baseline at `cf2056ec0a3681d9ef95ede54b4c5574ad33b008`. The current signed
  C0 work-unit branch is one documentation commit atop that unpublished baseline.
- The baseline fast mandatory gate passed in 57.7 seconds and the C0 candidate
  passed post-edit in 61.91 seconds. Every C0 commit/amend hook has remained below
  the 120-second limit; commit output is the authority for individual hook times.
- The full `make test` baseline passed on the same source.
- Portable assurance run `30788387383` passed on aarch64 Darwin, aarch64 Linux,
  and x86_64 Linux.
- Normal CI run `30715313370` remains red because the structural coverage artifact
  binds validity to the runner's Nix identity. C1a-C1c own the reviewed repair and
  retirement sequence; do not refresh the artifact merely to obtain green.
- Hera's active system profile is `system-984-link`.
- `clio.lan` is currently DNS-unresolvable. Treat every Clio-dependent retirement
  as incomplete until live evidence becomes available.
- At `2026-08-03T07:15:18Z`, the repository had 24 open issues, exactly cleanup
  #98-#121. Project 9 had 110 items: #98/#99 In Progress and #100-#121 Todo.

## Boundaries

- Push, publication, activation, history rewrite, consumer edits, and session
  restart/termination require separate explicit authorization.
- External Vulcan, VPS, and shared-work checkouts are read-only verification
  targets unless John separately authorizes an edit.
- Never display secret values; host probes report only booleans, path types,
  generation identifiers, and exact key-name presence/absence.
- Ordinary commits run the fast tier. Slow/expensive verification runs at the
  work-unit or unchanged-candidate boundary defined by the plan.
- One short-lived work-unit branch and at most one extra worktree may exist at a
  time. The coordinator alone mutates source and Git state.

## Resume point

C0 source work is complete in the current local signed commit. Inspect the latest
independent fess verdict: fix a real finding in the same unpublished unit, or, after
a clean verdict, locally fast-forward `main`, remove the C0 branch, and begin only
the newly unblocked units. Issue #99 remains open until publication is separately
authorized.

Stop counters are maintained in `CLEANUP-WIGGUM-HANDOFF.md`.
