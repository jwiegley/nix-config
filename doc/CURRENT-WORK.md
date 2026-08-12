# Current Work

Project 9 is complete. Its source, fleet deployment, Pi qualification, and
closeout evidence are recorded in GitHub Project 9 and issue `#98`. No Project
9 work remains active.

The optional Pi soak procedure remains available in
[`PI-EIGHT-HOUR-SOAK.md`](PI-EIGHT-HOUR-SOAK.md) for manual use when requested;
another soak is not a pending acceptance gate.

## Pi bounded-session memory programme

Issue `nix-tcz.37.1` is the active programme for making Pi's normal retained
session memory independent of persisted-history size. Its tasks cover the core
query and storage contract, the classic coding-agent cutover, lifecycle and
presentation paths, managed-extension migration, deterministic and geometric
acceptance gates, documentation, and the eventual removal of product-scale Nix
patches. `obr ready --label pi-bounded-memory` is the authoritative next-work
query, and `obr show nix-tcz.37.1` is the authoritative programme checkpoint.

`obr` is the sole continuation authority for this programme. Issue descriptions,
notes, statuses, and dependencies hold the invariant, evidence checkpoint,
authority boundaries, and exact next action; no parallel handoff document is
maintained. Maintainer outreach, pull requests, creation or publication of an
owner fork, the Nix cutover, activation, and push remain distinct issue gates.
The existing large downstream patch is evidence and a prototype, not the
architecture to upstream wholesale.

The preregistered residency contract, live-work budget ledger, historical
evidence boundary, and geometric measurement protocol are in
[`PI-BOUNDED-MEMORY-CONTRACT.md`](PI-BOUNDED-MEMORY-CONTRACT.md). Candidate
measurements may not begin until that contract is committed, its runner and
analyzer have been reviewed, and the bounded, injected-slope, strict-surface,
and synthetic analyzer controls have produced their frozen required verdicts.
The local-source geometric gate supplies pre-delivery evidence; a separate
unrecalibrated replay must pass against the exact delivered, Nix-pinned,
package-qualified store path before activation.

## 2026-08-09 whole-repository review: tracked closeout

A seven-pass heavy review (94 findings, consolidated to 41 clusters) was
addressed across eight adversarially verified batches, commits
`3278f5fc..842ce675`, followed by partner-observation cleanup and tracked
security follow-ups. Remaining implementation and authority work is recorded in
[`PLAN.org`](PLAN.org); this heading does not claim those issues are closed. The
signed commits and current tests are the durable evidence, and Git preserves the
consumed original observation queue. Five findings were adjudicated rather than
applied, with the rationale recorded below or beside the code they concern:

- the preflight allowlist stays leaf-granular (comment at its declaration
  in `config/ai/preflight.nix`);
- the Pi normalization policy keeps two validators with distinct roles
  (comments in `packages/pi-gallery/default.nix` and `bin/update-overlay`);
- signature acceptance remains independently enforced at its trust and
  packaging boundaries (comment in `test/bin/quality`);
- replacing the large update-overlay dispatcher remains a separately scoped
  parity spike, not a speculative cleanup refactor;
- Pi's mutable-state guard, runtime packages, and activation remain
  composer-owned lifecycle policy; a generic renderer channel waits for a
  second concrete client requirement rather than moving ownership speculatively.

### Open questions blocking the remaining items

Owner-decided review work is tracked in [`PLAN.org`](PLAN.org); only these
authority questions remain unresolved:

1. `nix-tcz.37` and `nix-tcz.30`: authorize an exact-tree import branch in
   `jwiegley/agent-deck` before replacing Agent Deck's product-scale patches.
   Its runtime-binding cleanup must land in that product repository, not
   another Nix patch. Pi's corresponding architecture and repository decision
   is now the explicit `nix-tcz.37.1.4` gate; local contract, fixture, and issue
   preparation work precedes it without publishing anything.
2. `nix-aln`: publication, paired consumer-lock adoption, and each managed
   host activation require separate authorization before the root-owned `obr`
   package can be accepted across the fleet.
3. `nix-5yr`: Clio currently serves neither advertised local model. Choose
   whether to repair its mutable inventory or withdraw/adjust the Clio route
   opt-ins to models actually served.
4. `nix-3u8`: choose whether the Vulcan-to-Andoria jump must use a dedicated
   timer identity or may intentionally reuse the general Vulcan identity. Key
   provisioning, authoritative consumer changes, activation, and runtime
   acceptance require separate authorization.
5. `nix-jlj`: choose whether to retain the unsupported Docker Desktop
   emulation used by MSSQL on Apple Silicon, migrate the service and data to
   supported x86-64 Linux, or retire it. Any service mutation, activation, or
   data migration requires separate authorization.
