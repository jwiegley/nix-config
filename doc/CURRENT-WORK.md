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

Issues #107, #103, #105, #106, #111, and #112 are complete and closed Done.
Issue #113 is verified complete with no new source change: Phase 1 already made
parity currency full-only while preserving its negative checks. It remains In
Progress until Project reconciliation. The next cleanup unit is issue #115.

The construction checkout is
`/private/tmp/wg-nix-cleanup/c8b-parity-currency`. The primary
`/Users/johnw/src/nix` checkout is on local `main` and contains the concurrent
dependency, model, Pi, and oMLX 0.5.5 repair work that produced active Hera
generation 986, expanded Pi/gallery work, untracked Pi provider work, and runtime
`.pi/goals` state. Do not stage or restore those paths during cleanup.

Authoritative consumer proof now passes for Vulcan, VPS, and shared work. The VPS
was fast-forwarded to its existing signed upstream `config/fleet` migration and
passed a full no-link NixOS build without activation.

The requested one-time Hera switch completed at generation 986. Push,
publication, another activation, session restart/termination, and
published-history rewrite are not authorized.
