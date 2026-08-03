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

Issue #107 is complete. Issue #103's implementation is complete and independently
audited, and its closeout is recorded here; the issue remains In Progress until
local integration. It deletes only mechanically inert commented-out
implementation; its focused comment audit, Darwin value surface, fast gate, and
final independent implementation review all pass. The next cleanup unit after
integration is issue #105.

The construction checkout is
`/private/tmp/wg-nix-cleanup/c2a-dead-comments`. The primary
`/Users/johnw/src/nix` checkout is on local
`main` and contains John's concurrent lock, dependency, and Pi work. Do not stage
or restore those user-owned paths.

Authoritative consumer proof now passes for Vulcan, VPS, and shared work. The VPS
was fast-forwarded to its existing signed upstream `config/fleet` migration and
passed a full no-link NixOS build without activation.

Hera activation of the current dependency candidate is separately authorized;
push, publication, other-host activation, session restart/termination, and
published-history rewrite are not.
