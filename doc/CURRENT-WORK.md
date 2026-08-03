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

Issues #107, #103, and #105 are complete and closed Done. Both portable formatter
app names and their write/check behavior are preserved. Issue #106's credential
launcher consolidation is now In Progress.

The construction checkout is
`/private/tmp/wg-nix-cleanup/c3b-credential-launcher`. The primary
`/Users/johnw/src/nix` checkout is on local `main` and contains the concurrent
dependency, model, Pi, and oMLX 0.5.5 repair work that produced active Hera
generation 986, plus runtime `.pi/goals` state. Do not stage or restore those
paths during cleanup.

Authoritative consumer proof now passes for Vulcan, VPS, and shared work. The VPS
was fast-forwarded to its existing signed upstream `config/fleet` migration and
passed a full no-link NixOS build without activation.

Push, publication, further activation, session restart/termination, and
published-history rewrite are not authorized.
