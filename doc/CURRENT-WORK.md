# Current Work

Updated: 2026-08-03

Cleanup epic [#98](https://github.com/jwiegley/nix-config/issues/98) is active.
The accepted Definition of Done is [`CLEANUP-PLAN.md`](CLEANUP-PLAN.md), and
[`CLEANUP-WIGGUM-HANDOFF.md`](CLEANUP-WIGGUM-HANDOFF.md) is the sole mutable
resume authority.

Phase 1 is complete locally and its final independent range audit passed. It
retains a small fail-closed `fast`/`full` quality driver while deleting structural
coverage, root output-denominator bookkeeping, the committed consumer inventory,
duplicate root/portable gates, and their regeneration cycle.

Issue #107's dead catalog metadata deletion is complete and independently audited.
The next unit is Phase 2's mechanical dead-comment deletion, issue #103, after
#107 is fast-forwarded and its worktree is removed.

The construction checkout is
`/private/tmp/wg-nix-cleanup/c4-catalog-dead-metadata`. The primary
`/Users/johnw/src/nix` checkout is on local
`main` and contains John's concurrent lock, dependency, and Pi work. Do not stage
or restore those user-owned paths.

Authoritative consumer proof now passes for Vulcan, VPS, and shared work. The VPS
was fast-forwarded to its existing signed upstream `config/fleet` migration and
passed a full no-link NixOS build without activation.

Push, publication, activation, session restart/termination, and published-history
rewrite remain separately authorized actions.
