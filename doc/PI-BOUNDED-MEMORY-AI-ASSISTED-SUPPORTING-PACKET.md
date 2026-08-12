# AI-assisted supporting packet: Pi bounded retained-session memory

> **AI-assisted supporting packet.** Prepared locally for human review. It is
> evidence and question framing, not maintainer-authored text, programme status,
> authorization to publish, or an accepted upstream design.

The normative local contract and complete evidence ledger are in
[PI-BOUNDED-MEMORY-CONTRACT.md](PI-BOUNDED-MEMORY-CONTRACT.md). Mutable status,
dependencies, and next actions live only in `obr`.

## Claim and evidence boundary

The intended source-level claim is narrow: for fixed active context, budgets,
concurrency, and reviewed topology, source-reviewable Pi-controlled live history
state should not grow with total persisted bytes or entries. An explicit
whole-history compatibility call forfeits that bound. Opaque runtime and
allocator behavior remain outside the source argument, and finite RSS is an
integration observation rather than a proof of Big-O behavior.

## Causal trace and exact observed-main baseline

The exact B1 source subject has no downstream patches and an empty extension
manifest. Upstream `HEAD` and `main` were both observed at
`2e4d23959485279aa2da1a45103de2ea22d46395` on August 12, 2026; the frozen
package reports `pi-coding-agent` 0.84.1. This is a dated identity, not an
evergreen claim about upstream main.

The source crosswalk records the classic retention path in
`packages/coding-agent/src/core/session-manager.ts`:

| Behavior | Line |
| --- | ---: |
| `fileEntries` owns every parsed file entry | 862 |
| `byId` owns every non-header session entry | 863 |
| opening calls `loadEntriesFromFile` | 898 |
| `_buildIndex()` runs after the complete load | 921 |
| indexing iterates complete `fileEntries` | 963 |
| indexing inserts each entry into `byId` | 965 |
| append retains the new object in both containers | 1045 |
| context construction calls `getEntries()` | 1285 |
| `getEntries()` filters the complete array | 1302 |

These objects remain reachable even when compaction leaves a small active
projection. Garbage collection cannot reclaim them while the manager remains
live.

The immutable fixture family has logically nested 16 MiB, 64 MiB, 256 MiB, and
1 GiB histories with 526, 2,062, 8,206, and 32,782 non-header entries. The
diagnostic compared only the 16 MiB and 1 GiB endpoints using the same source
package, empty extension set, active tail, and normalized continuation.

| Endpoint | `fileEntries` before continuation | `byId` before continuation | Raw RSS | `maxRSS` |
| --- | ---: | ---: | ---: | ---: |
| 16 MiB | 527 | 526 | 103,481,344 bytes | 116,932,608 bytes |
| 1 GiB | 32,783 | 32,782 | 1,275,248,640 bytes | 1,361,608,704 bytes |

Evidence identities:

- source/package output:
  `/nix/store/98ldilyr7g34lg78nvn5470zxaqih3zy-pi-classic-core-source-0.84.1`;
- source NAR hash:
  `sha256-Z92ZxL2WdbRl7H1mHbN2sWfH/9ndpqLtBxEv5+A5fbg=`;
- package-output NAR hash:
  `sha256-jeZIFwg+NqhCn3spHAQJ9SfV24+UK5mMnZdbAi6Gfqs=`;
- fixture output:
  `/nix/store/zan7ir6jx415h85my3w07vla2mzvksyw-pi-classic-core-fixtures-v1`;
- fixture NAR hash:
  `sha256-dYiqyYnzpKCTbGiA0PxhgLFZiL4SOahV+lyCDvvT0YY=`;
- fixture `SHA256SUMS` SHA-256:
  `b5aed7c3c4b75d2699fa8e0c68fb6a8c063bcfed61c0e0969ed54feb2a7a19f8`;
- diagnostic output:
  `/nix/store/cp9sqkmswmxab9aa4hwdj4zz6d4hxvx0-pi-b1-classic-core-attempt-0001`;
- diagnostic NAR hash:
  `sha256-MRZ2TES55znZo53uNKXCS/kaMXja5DgxN960GLFIRA0=`;
- diagnostic `SHA256SUMS` SHA-256:
  `72a4c763417686ad0fd971f17d3009848e4f1b9e24aff1cb2dc635dd1526b9cd`;
- summary SHA-256:
  `b0bcac2601b5b949510a66fe534e99be97ea6c8c1f355c090d601373d5d1599d`.

This is complete descriptive B1 evidence for the frozen classic subject. It is
not M1 or M2 product qualification, not an adjusted-RSS verdict, and not a claim
that finite samples prove an asymptotic property.

## Existing v4 seam

The same exact source tree already contains the v4 session direction:

- `SessionStorage` defines durable lanes, entries, records, facts, and
  count-limited item queries;
- `SessionRepo` creates, opens, lists, deletes, and forks sessions;
- `Session` implements `SessionTree` over a `SessionStorage`;
- `InMemorySessionRepo` and `JsonlSessionRepo` implement repository backends;
- the separate `@earendil-works/pi-session-backend-sqlite-node` package
  implements `SqliteSessionRepository`;
- the shared conformance seam exercises entries, lanes, queries, facts,
  records, concurrency, repository lifecycle, and forks.

The current `EntryQuery` has an item limit and sequence cursor, but no byte
budget, and returns hydrated `Entry[]`. The JSONL implementation still loads
and retains complete v4 state, and the shared interfaces do not yet expose
close or disposal. Classic coding-agent continues to use its separate
synchronous `SessionManager`. The natural first contribution is to strengthen
and adopt the existing repository contract, not transplant the downstream
sidecar as another API.

The source does not decide which backend must be canonical for coding-agent, how
long legacy APIs remain, or whether direct `SessionTree` adoption or the durable
AgentHarness is the terminal product seam. Those remain maintainer decisions.

## Decisions requested

| Decision | Why it blocks a clean contribution | Maintainer direction requested |
| --- | --- | --- |
| Terminal adoption seam | Otherwise a coding-agent adapter may compete with the intended runtime cutover. | Adopt `SessionTree` directly, move to AgentHarness, or name another existing seam. |
| Durable backend | JSONL and SQLite repositories exist, but the source does not fix coding-agent's durable authority or product default. | Choose the canonical representation, supported alternatives, and default. |
| Legacy import | Atomicity, retry, rollback, and compatibility depend on it. | Choose explicit one-shot import, streaming first-open import, or a time-bounded compatibility reader. |
| Runtime support | The selected backend constrains the supported runtime set. | Name the required Node, Bun, platform, and filesystem matrix. |
| Compatibility runway | Whole-history synchronous APIs conflict with the strict bound. | Set their interval and whether strict mode rejects them before hydration. |
| Lifecycle and hook policy | Replacement, close, cancellation, writer leases, eager hook payloads, and RPCs need one bounded contract. | Name the owner and choose versioned bounded payloads or explicitly unbounded compatibility hooks. |
| No-session scope | Durable-session bounds do not cover an unlimited prepublication transcript. | Require a bounded ephemeral repository or define a hard admission boundary. |
| Guarantee wording | Overbroad language would claim more than reviewed source establishes. | Approve a Pi-owned live-state bound for fixed context and budgets, with opaque runtime and whole-history exclusions. |

## Candidate staged PR outline

This sequence is conditional on maintainer direction and grants no authority to
create a branch or pull request.

1. **Bound the repository capability.** Add byte-aware point, page,
   active-branch, and streaming contracts to `SessionTree`/`SessionStorage`,
   with typed oversized-record, stale-cursor, cancellation, and lifecycle
   failures before unrestricted hydration. Test every maintained backend against
   one conformance contract.
2. **Implement the selected durable authority and legacy import.** Stream legacy
   input with exclusive publication, retry semantics, permissions, and cleanup.
   Keep canonical and derived bytes separately identified when both exist.
3. **Adopt the repository in coding-agent.** Replace normal
   `fileEntries`/`byId` ownership while preserving exact history, compaction,
   branches, forks, resume, lifecycle, and the selected no-session behavior.
4. **Migrate presentation and consumers.** Move terminal navigation, discovery,
   search, RPC, export, and extensions to point, bounded-page, active-context, or
   streaming operations. Preserve explicit exact-history behavior without
   disguising it as bounded.
5. **Close compatibility and documentation.** Run deterministic conformance,
   document the guarantee and exclusions, and remove the eager implementation
   when its agreed runway ends.

Each stage should have a small boundary, focused semantic and failure tests, and
no dependency on a later PR to make its own lifecycle safe.

## Evidence offered and limitations

The downstream prototype is recorded by signed Nix commit
`e2c002e06cc4378b5a55cc1659e99caaab408dcb`. Its
`pi-bounded-session-history.patch` is 13,831 lines with SHA-256
`4bdb9524839764bf9639740be782e0719168d885332e5cf2b70da16c95f7494a`.
It uses a rebuildable SQLite sidecar and supplies a large failure-oriented test
corpus. It is causal evidence and a source of regression cases, not the intended
upstream architecture.

Older one-gibibyte prototype and eight-hour soak results remain historical,
attributed evidence. Their raw artifacts are not present in this repository,
and one earlier one-gibibyte report has an unresolved 98,302-byte discrepancy.
They must not be combined with the exact B1 result or used as current
qualification. The contract ledger retains their exact provenance and caveats.

This packet records no maintainer approval and grants no authority to publish an
issue or RFC, create a branch, fork, or pull request, or contact a maintainer.
