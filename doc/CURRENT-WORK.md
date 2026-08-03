# Current Work

Updated: 2026-08-03

Cleanup epic [#98](https://github.com/jwiegley/nix-config/issues/98) is active.
The accepted Definition of Done is [`CLEANUP-PLAN.md`](CLEANUP-PLAN.md), and
[`CLEANUP-WIGGUM-HANDOFF.md`](CLEANUP-WIGGUM-HANDOFF.md) is the sole mutable
resume authority.

The active unit is Phase 1: retain a small fail-closed `fast`/`full` quality
driver while deleting structural coverage, root output-denominator bookkeeping,
the committed consumer inventory, and their exact-source regeneration cycle.

The construction checkout is
`/private/tmp/wg-nix-cleanup/c1a-rewrite`. The signed exploratory branch remains
preserved separately. The primary `/Users/johnw/src/nix` checkout is on local
`main` and contains John's concurrent lock, dependency, and Pi work. Do not stage
or restore those user-owned paths.

Authoritative consumer proof now passes for Vulcan, VPS, and shared work. The VPS
was fast-forwarded to its existing signed upstream `config/fleet` migration and
passed a full no-link NixOS build without activation.

Push, publication, activation, session restart/termination, and published-history
rewrite remain separately authorized actions.
