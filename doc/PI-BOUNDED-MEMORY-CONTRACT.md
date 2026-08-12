# Pi bounded-session memory contract and evidence ledger

This document fixes the meaning, measurement protocol, and evidence boundary of
the Pi bounded-session-memory programme. It governs issue `nix-tcz.37.1` and
precedes candidate measurement: no result obtained before this revision is to
be presented as satisfying the geometric acceptance test defined below.

The contract concerns normal core execution and managed extensions certified to
use bounded capabilities. It does not assert that an arbitrary JavaScript
process, native library, caller, or third-party extension consumes constant
memory.

## Governing invariant

Persisted session history contributes no term to normal retained core memory.
For a fixed active context and fixed declared budgets, opening, resuming, and
continuing a session therefore retain the same logical resources whether the
persisted history contains sixteen mebibytes or one gibibyte.

The retained-state envelope comprises named terms rather than one anonymous
allowance:

```text
normal retained state
  = fixed repository and runtime state
  + active context
  + largest admitted physical record
  + query pages
  + repository caches
  + terminal views and overscan
  + event and RPC queues
  + scanner and reducer scratch
  + export sinks and spools
  + native-runtime state
  + concurrent operations
  + caller-retained results
  + bounded prepublication state
```

Persisted bytes and persisted entry count are absent from that expression. They
may determine scan duration, index size, rebuild I/O, and total disk use; they
may not determine the payloads or metadata retained by normal core execution.

This is a residency contract, not a latency or storage claim. Exact scans,
exports, migrations, and index rebuilds may perform work proportional to the
history length, provided that they proceed incrementally with bounded live
state, cancellation, and backpressure.

## Terms

The programme uses the following terms consistently:

- **Persisted history** is the complete durable session representation,
  including any canonical log and rebuildable index.
- **Normal core execution** comprises open or resume, active-context
  construction, append, compaction, point lookup, bounded navigation, ordinary
  terminal presentation, and lifecycle publication. An explicitly requested
  exact scan or export is not normal retained state.
- **Warm retained state** is the state remaining after the package has opened a
  prepared fixture, completed the prescribed equal workload, quiesced, and
  undergone the fixed collection protocol below.
- **Cold rebuild** is the first open of a fixture whose rebuildable derived state
  is absent. Its peak, latency, I/O, and disk effects are reported separately.
- **Hydration** is conversion of bounded persisted records into live language
  objects.
- **Caller-retained state** is any result that remains reachable because the
  caller keeps it after a bounded operation returns.
- **Certified managed extension** is a managed extension whose default path uses
  only the strict bounded capability set and has passed the extension gate.
- **Candidate** is one immutable Pi product revision, its complete package
  derivation, and the exact managed-extension set tested with it.

## Compatibility boundary

Pi exposes two deliberate modes during migration.

### Compatibility mode

Compatibility mode may retain an explicit legacy reader for callers that ask to
materialize complete history. Such an operation is labelled expensive, runs
only on demand, and transfers ownership of the returned memory to its caller.
It neither truncates history nor pretends that an array has become lazy.

A process that invokes a legacy whole-history materializer is outside the strict
retained-memory claim for the lifetime of that result. Compatibility mode is a
migration facility, not a certified default.

### Strict bounded mode

Strict bounded mode admits point reads, bounded item-and-byte pages, bounded
active or recent windows, and exact streaming visitors with cancellation and
backpressure. It rejects an implicit whole-history materialization before
allocation. Managed production defaults and every certified extension use this
mode before final acceptance.

Neither mode silently truncates an exact operation. Where an exact result cannot
fit a bounded page, the operation continues through a cursor or stream; where a
single physical record exceeds its declared limit, it fails with a typed error
before unrestricted allocation.

## Covered operations

The final product evidence covers the operations below. A passing point query
does not stand in for a streaming export, and a source-level review does not
stand in for the packaged runtime.

| Operation | Required bounded behavior |
| --- | --- |
| Open and resume | Read fixed metadata and the active projection without retaining the complete history. |
| Append and compaction | Publish durable state in order; evict payloads outside the retained active boundary without changing logical history. |
| Active context | Retain only the compaction-aware active projection and its declared payload budget. |
| Point lookup | Hydrate at most the addressed record and bounded cache effects. |
| Branch and tree navigation | Page metadata and bounded previews; hydrate selected records on demand. |
| Search and grouped statistics | Stream bounded hit pages and cap aggregation cardinality and bytes. |
| Fork, JSONL, and HTML export | Preserve exact output while streaming with cancellation and backpressure. |
| Terminal presentation | Bound loaded rows, previews, view state, and overscan independently of persisted history. |
| RPC and events | Bound frames, queued items, queued bytes, and concurrent producers. |
| Session replacement | Cancel or fence old owners so that replaced repositories and callbacks cannot retain or mutate successor state. |
| Managed extensions | Use certified point, window, page, or streaming capabilities according to their declared history class. |
| Cold import or rebuild | Stream source data; report peak, latency, I/O, and derived disk use separately from warm retention. |

## Live-work budget ledger

Every live term has one owner and one enforcement boundary. Numeric limits are
part of the immutable candidate manifest; they are fixed before a candidate is
measured and may only become smaller without beginning a new evidence revision.

| Term | Owner | Enforcement boundary | Required evidence |
| --- | --- | --- | --- |
| Fixed repository, connection, statement, descriptor, and lease state | Runtime host and repository implementation | Construction, replacement, and close own a fixed number of resources independent of history. | Resource counters before open, at retained idle, after replacement, and after close. |
| Active-context entries and bytes | Pi context and compaction layer | Context projection admits only the retained compaction tail and rejects an over-budget projection before publication. | Deterministic counters and active-context equivalence at every fixture size. |
| Physical record bytes | Session storage parser | Length is checked before payload allocation or JSON decoding. | Exact-limit and limit-plus-one fixtures, including multibyte input. |
| Page items and bytes | `SessionRepo`/`SessionTree` query API | Both limits apply before hydration; cursors advance without retaining earlier pages. | Poison-after-limit and geometric paging tests. |
| Hydration-cache bytes and entries | Repository cache | Byte-charged eviction occurs on insertion; replacement and close release ownership. | Cache counters, eviction tests, and replacement lifecycle tests. |
| Terminal rows, previews, and overscan | Terminal presentation layer | View and overscan caps apply before full record hydration. | Navigation tests and terminal-path memory measurements. |
| Event and RPC queue items and bytes | Event/RPC transport | Admission limits and backpressure apply before enqueue; cancellation releases queued payloads. | Queue counters, slow-consumer tests, and shutdown tests. |
| Scanner, reducer, and batch scratch | Bounded scan capability | Record, batch, reducer, and in-flight callback limits apply before handoff; no repository cursor or lease crosses extension-controlled suspension. | Oversized-record, slow-reducer, cancellation, and cursor-release tests. |
| Export, fork, renderer, and spool state | Export or fork implementation | Writer buffers and disk spools are admitted by byte and file limits and obey downstream backpressure. | Exact-output streaming, slow-sink, cancellation, temporary cleanup, and partial-publication tests. |
| Native-runtime state | Runtime and native dependencies | Runtime and backend builds and settings are immutable within an evidence unit; exposed connection and cache counts retain their declared caps, while unexplained history-dependent native drift is reported without subtraction and remains subject to the raw-RSS verdict. | Raw RSS, `maxRSS`, heap, external, and `arrayBuffers` metrics with runtime identity. |
| Concurrent operations | Owning scheduler or caller | Each capability declares a concurrency ceiling; aggregate allowance is the ceiling multiplied by its per-operation bound. | Concurrency counters and saturated-bound tests. |
| Caller-retained results | Capability caller | Ownership transfers on return; certified callers retain no unbounded sequence of pages or streamed records. | Caller audits, poison tests, and managed-extension certification. |
| Managed-extension state and caches | Each certified extension | The extension declares item and byte admission limits and clears owned state on replacement and shutdown. | Per-extension counters, geometric-history workloads, and strict aggregate certification. |
| Prepublication and no-session state | Runtime host | Before durable repository ownership begins, an ephemeral repository or equivalent admission boundary applies the same record and active-context limits. | First-record, new-session, replacement-before-publish, and failure-cleanup tests. |
| Persisted history and rebuildable index | Session repository | Disk may grow with history; normal open retains only fixed repository metadata. | Fixture bytes, index bytes, warm slope, cold peak, rebuild time, and I/O. |

No adjusted-RSS subtraction is an acceptance metric. Active payload, cache, and
native counters explain a result; they do not reduce the raw resident set used
for the geometric verdict.

## Causal trace of the classic implementation

The v0.83 classic `SessionManager` reads the JSONL into `fileEntries`, an array
containing every parsed entry, and builds `byId`, a `Map` whose values retain
those session objects. Compaction changes the model-facing context but does not
remove the corresponding objects from either container. Whole-history helpers
and extensions then derive further strings, arrays, indexes, or caches from the
same live graph.

Consequently, persisted entry count and payload bytes determine the number and
size of objects reachable from a live manager. Invoking garbage collection
cannot reclaim them. The downstream prototype breaks that particular causal
chain by retaining byte offsets and bounded metadata in a rebuildable SQLite
sidecar, hydrating records on demand, and clearing `fileEntries` and `byId` once
the indexed store owns the session. That implementation is valuable regression
evidence, but it is a downstream parallel store rather than the intended
upstream architecture.

The line-level upstream source inspected locally is the catalog-pinned v0.83
base at `845d6ff1f6643aba440341cce877ce1c43ebbc39`. It contains asynchronous
`SessionStorage` and `SessionRepo` vocabulary, JSONL and SQLite repository
implementations, and a durable AgentHarness plan for `SessionTree`; it does not
contain an implemented `SessionTree` interface, and classic coding-agent still
uses `SessionManager`. The two repository implementations do not settle whether
SQLite is canonical or JSONL remains canonical behind a rebuildable index. That
choice remains an explicit maintainer architecture gate. This contract governs
either choice; it does not decide it by implication.

## Geometric measurement preregistration

The geometric gate measures whether raw warm retained RSS depends on persisted
history size. The fixture, execution, sampling, and estimator rules in this
section are fixed before candidate measurements. A later change creates a new
contract revision and invalidates comparison with results obtained under the
earlier procedure.

### Fixtures

Prepare four deterministic linear-and-branched fixture families at nominal
scales `1x`, `4x`, `16x`, and `64x`. Each scalable prefix record is exactly
32 KiB on disk, including its newline:

| Scale | Scalable prefix bytes | Prefix records |
| --- | ---: | ---: |
| `1x` | 16 MiB | 512 |
| `4x` | 64 MiB | 2,048 |
| `16x` | 256 MiB | 8,192 |
| `64x` | 1 GiB | 32,768 |

Generate padding from a documented SHA-256 counter stream and reject sparse or
compressed fixture storage. Record exact bytes and entries and use the actual
immutable source-fixture byte counts as the regression variable. Each larger
fixture extends the same deterministic historical prefix.
All four fixtures end at the same logical compaction boundary and contain an
identical deterministic active tail, branch shape, model state, thinking state,
labels, and extension snapshots. The post-open workload is byte-for-byte and
operation-for-operation identical at every scale.

The fixture manifest records generator revision, seed, record limit, exact file
and index hashes, bytes, entries, active-tail counters, and expected semantic
digests. Measurement never mutates the canonical fixture; each repetition uses
a disposable same-filesystem copy. If the selected canonical backend is not
JSONL, a frozen importer converts this logical source fixture before candidate
observation. Canonical store and derived-index bytes are reported separately;
the regression x-coordinate remains the immutable source-fixture bytes unless a
new contract revision is committed before any candidate measurement.

### Lanes and repetitions

Measure the actual packaged coding-agent path in three lanes: core terminal
startup and continuation; the complete strict managed-extension set; and the
packaged runtime entry point used by the managed Pi wrapper. Each lane uses
exactly nine valid isolated repetitions per size. Three reserve repetition
indices per size and lane are frozen before execution; exhausting them makes the
evidence unit incomplete. A repetition reuses no process, repository object,
derived index, writable cache, or temporary state from another repetition.

An evidence unit is one immutable tuple in this fixed order: protocol revision,
candidate commit, candidate source-manifest SHA-256, package derivation,
package-output SHA-256, host identity class, platform and OS generation,
runtime executable SHA-256 and version, and lane identifier. Encode each UTF-8
field as a four-byte unsigned big-endian byte length followed by its bytes,
prefix the sequence with `UTF8("nix-tcz.37.1.1-m1-unit-v1\0")`, and define
`evidence_unit_id` as the lowercase hexadecimal SHA-256 of that sequence. The
manifest records every source field and the resulting identifier, and freezes
them before candidate output is observed. Any field change creates a distinct
evidence unit rather than being pooled with the old one.

Each cell uses three fresh child processes. The cold child imports or rebuilds
and reports cold peak, latency, I/O, and disk. A preparation child creates and
closes a pristine derived store without contributing a memory observation. The
warm child reopens that prepared store, performs the fixed workload, and remains
open at the retained-state barrier while memory is measured.

Order all primary and reserve cells before execution by sorting the raw 32-byte
SHA-256 values of the following byte string in ascending byte order:

```text
UTF8("nix-tcz.37.1.1-m1-order-v1\0" + lane_id + "\0" + size_label + "\0" + decimal_repetition_index)
```

Freeze the resulting order before candidate output is observed. The three
children of one cell remain adjacent. Runs occur serially on one identified idle
host, on AC power, under one OS generation, runtime binary, package derivation,
and environment. Any material change begins a new evidence unit.

### Quiescence and collection

After open and the equal workload, wait for lifecycle publication, provider and
terminal streams, extension hooks, cursors, scans, exports, and all
candidate-owned queues to finish. The barrier has a 30-second deadline and
requires stable logical live counters with no candidate task pending.

Record an unforced sample first. Drain microtasks and two event-loop turns, then
invoke exactly three full collections through `global.gc()` in a runtime
launched with `--expose-gc`, yielding one event-loop turn after each. Wait one
second without work or collection. Record nine raw RSS samples at 250 ms
intervals; the repetition's warm retained RSS is their median. Record both
pre-collection and post-collection metrics. The fixed collection protocol
reduces allocator history as a confounder; it is not a runtime mechanism, and
no repeated collection occurs during the measured workload.

### Raw record

Each repetition emits one append-only JSON record containing at least:

- candidate commit, source manifest, package derivation, executable hashes,
  runtime version, OS generation, host identity class, lane, scale, repetition,
  fixed order, and timestamps;
- fixture hashes, JSONL bytes and entries, derived-index bytes, and disposable
  copy identity;
- active entries and bytes, admitted record maximum, page items and bytes,
  cache entries and bytes, view and overscan counts, queued items and bytes,
  scanner and reducer scratch, sink and spool bytes, concurrency,
  managed-extension state, and caller-retained result counts;
- raw `rss`, `maxRSS`, `heapTotal`, `heapUsed`, `external`, and `arrayBuffers`
  before and after collection, together with all nine retained samples;
- open cursors, statements, connections, descriptors, leases, listeners,
  timers, pending tasks, and child processes at each lifecycle boundary;
- cold-open or rebuild peak, elapsed time, bytes read and written, canonical and
  derived disk bytes, peak temporary disk, and warm operation latencies;
- host memory pressure, compression and swap deltas, power and thermal state,
  free disk, and competing-load observations; and
- semantic digests and hard logical counters for context, branch, tree, append,
  fork, export, and the certified extension workload.

Raw records and the fixture manifest are immutable inputs to analysis. A report
contains their hashes and the analysis-program hash; summary tables never
replace them. The runner must establish and freeze the runtime/platform unit of
raw `maxRSS`, retain that raw value, and centralize conversion to bytes before
candidate collection begins.

### Estimator and verdict

For equal live inputs, every hard counter and logical resource count is
identical at all four scales. A mismatch is a failure before statistical RSS
analysis.

For each lane, compute the median warm retained RSS at each size. Compute the
Theil–Sen slope from all cross-size pairs among all repetitions, using exact
immutable source-fixture bytes as `x` and raw warm retained RSS as `y`;
equal-size pairs are excluded. Express the result as mebibytes of RSS per
gibibyte of source-fixture history.

With nine repetitions at each size, the point estimate is the arithmetic mean
of the 243rd and 244th sorted values among all 486 cross-size pairwise slopes.
Compute a one-sided 95% bootstrap upper confidence
bound by stratified resampling with replacement within each size, preserving
nine observations per size, recomputing the Theil–Sen slope exactly 100,000
times, and taking sorted element 95,000 (one-based) as the nearest-rank 95th
percentile. The analyzer uses versioned
SplitMix64 with the first eight big-endian bytes of
`SHA256("nix-tcz.37.1.1-m1-bootstrap-v1\0" + evidence_unit_id)` as its seed and
uses unbiased rejection sampling for indices.
The seed, implementation, and quantile summary are retained with the raw record.

The lane passes only when both conditions hold:

1. the upper 95% bootstrap confidence bound is no greater than **1 MiB of raw
   warm RSS per GiB of persisted history**; and
2. the range across all four size medians is no greater than **max(32 MiB, 5%
   of the smallest median)**.

No outlier is discarded. A repetition invalidated by an objective environment
or harness failure remains in the raw evidence and may be replaced only by its
next preregistered reserve index. Candidate-owned quiescence, cleanup, budget,
or lifecycle failures are failures rather than invalid repetitions. Cold
rebuild peak, latency, I/O, disk, and exact-operation latency receive separate
descriptive envelopes and cannot excuse a warm-retention failure.

### Harness controls

Before a candidate is measured, the runner and analyzer must pass three
immutable controls. The bounded control executes the real runtime and terminal
barrier without reaching geometric history and must pass both RSS criteria. The
injected-slope control retains and page-touches an additional 8 MiB per GiB of
immutable source-fixture bytes through the ninth retained sample and must fail
the slope criterion. The strict-surface mutation restores one classic
whole-history materialization and must fail the eager-materialization sentinel
before RSS analysis; its RSS result is diagnostic only.

The analyzer also uses exact synthetic observations below, exactly at, and
above the slope threshold, plus a non-monotone median case. Control records,
expected verdicts, and analyzer hashes are part of the preregistration;
candidate output cannot set or revise them. If the bounded or injected-slope
control does not produce its required verdict, the host protocol, span, or
repetition design must be revised in a new contract revision before any
candidate is observed.

## Evidence ledger

This ledger distinguishes source identity, historical prototype evidence, and
future evidence governed by this contract.

| Evidence | Identity and result | Standing under this contract |
| --- | --- | --- |
| Programme baseline | Signed Nix `b3263de3d700ab0650fb9cceadd6586fd1126f1a`; Pi v0.83 source pin `845d6ff1f6643aba440341cce877ce1c43ebbc39`. | Establishes the local source and package baseline only. |
| Upstream inspection | Live GitHub metadata placed `earendil-works/pi` main at `534bcbffb7e1e7551d9ee3572dfeb278e203e493` on 2026-08-11. Line-level inspection used the locally retained, catalog-pinned v0.83 source `845d6ff1f6643aba440341cce877ce1c43ebbc39`. A surviving handoff records issue `#7937` as describing unfinished v4 integration. | Establishes the remote identity observed at that dated checkpoint separately from the exact inspected source. It does not establish an evergreen current identity or maintainer approval, bind v0.83 line evidence to the observed main commit, or prove that a planned `SessionTree` interface exists. |
| Downstream prototype | Signed Nix commit `e2c002e06cc4378b5a55cc1659e99caaab408dcb`; `pi-bounded-session-history.patch` SHA-256 `4bdb9524839764bf9639740be782e0719168d885332e5cf2b70da16c95f7494a`, 13,831 lines. | Supplies a causal trace and regression corpus; it is not the intended upstream architecture. |
| One-gibibyte synthetic run | The final acceptance comment on GitHub issue `#128` names signed acceptance candidate `e44cb99c53ba1f2ae67e9714aff8bbad93243740` and reports `historyBytes=1,074,007,601`, 1,024 messages, 64 compactions, `maxRss=250,085,376`, and adjusted growth `40,501,246` bytes. A separate surviving source-audit report associates a prototype run with base `e2c002e0` and reports the same history size but adjusted growth `40,402,944` bytes. | Historical single-scale evidence with an unresolved 98,302-byte reporting conflict. The absent raw bundle does not establish whether the values describe different runs, a corrected statistic, or a transcription difference, and it prevents an independent run-to-commit reconstruction. Neither adjusted value nor the unrepeated run satisfies the geometric gate. |
| Eight-hour synthetic run | GitHub issue `#128`: exit 0; `durationMs=28,800,471`; 26,893 messages; 1,681 compactions; `historyBytes=888,276,251`; first/last adjusted-RSS medians `92,307,020` and `94,355,018`; adjusted growth `2,047,998` bytes. Private evidence-manifest SHA-256 `c30f01808c30701d3d66195c72ee7e821d934c4ca00f615cefd7ab0f75cc3aca`. | The computational duration and adjusted-growth criterion was reported as passed. The auxiliary retained-path/provenance checker remained incomplete because it compared macOS `/var` with the equivalent `/private/var` spelling. The private artifact is not reproduced by this repository, and adjusted RSS is not the geometric verdict defined here. |
| Manual soak procedure | `doc/PI-EIGHT-HOUR-SOAK.md` SHA-256 `54775179da5dee325330d4c47ac74e9d780c9d7fb2acec7c21b5fe6a9196d537`. | Reproducible optional procedure; another soak is not a pending acceptance gate. |
| Geometric result | Not yet measured. | Must use this revision's fixtures, raw record, repetitions, estimator, and thresholds. |

The historical numerical results above derive from the final acceptance comment
on [GitHub issue #128](https://github.com/jwiegley/nix-config/issues/128) and
from the separately identified surviving source-audit and soak reports described
in the ledger. They are retained as attributed provenance, not silently
collapsed into one run or promoted to stronger evidence.
The raw one-gibibyte result stream and the sealed eight-hour artifact bundle are
not present in this repository and were not available for rehashing during this
inventory. Their numerical values therefore remain attributed historical
measurements rather than independently reproduced results.

## Requirement-to-evidence map

This map prevents a later focused result from being presented as programme
acceptance. “Frozen here” means that this document supplies the normative
contract; it does not mean that the implementation evidence has run.

| Obligation | Authority frozen here | Evidence that closes it |
| --- | --- | --- |
| Persisted history is absent from normal retained core state; peak, cold rebuild, latency, disk, caller ownership, and RSS remain distinct | Governing invariant, terms, and explicit non-guarantees | Geometric result in `nix-tcz.37.1.21`, with cold and disk envelopes reported separately |
| Compatibility and strict bounded behavior are explicit and do not silently truncate | Compatibility boundary | Capability conformance in `.14`, managed certification in `.19`, and final boundary in `.24` |
| Every covered operation has an item, byte, cancellation, ownership, or backpressure boundary | Covered operations and live-work budget ledger | Backend and runtime work in `.5` through `.13`, followed by deterministic gate `.20` |
| Classic eager retention has a source-supported causal trace | Classic causal trace and downstream-prototype ledger row | Current-main baseline `.2` and removal from normal execution in `.7` |
| Upstream and prototype identities and historical claims remain attributable | Evidence ledger | Immutable candidate/package identities in `.30`, delivery identity in `.27`, and Nix pin crosswalk in `.25` |
| The geometric procedure is fixed before candidate observation | Fixtures, repetitions, quiescence, raw record, estimator, controls, and thresholds | Runner/control review in `.2`; candidate measurements only in `.21` |
| Managed extensions cannot inherit the claim merely by loading | Certified-extension definition and same-process non-guarantee | Consumer dispositions in `.15` through `.19` and strict aggregate certification in `.19` |
| Final documentation distinguishes passed, failed, historical, and not-run evidence | This map and evidence ledger | Final contract and migration guide in `.23` |

## Explicit non-guarantees

The programme makes no claim that:

- total process RSS is constant across operating systems, runtime builds,
  allocators, native libraries, models, or concurrency levels;
- cold rebuild peak, migration time, exact-scan duration, or disk consumption is
  independent of persisted history;
- a single physical record can be arbitrarily large;
- a caller may retain an unbounded number of otherwise bounded pages or results;
- a compatibility caller that materializes complete history remains within the
  strict envelope;
- an arbitrary same-process third-party extension is bounded without capability
  certification; or
- the downstream prototype, an optional soak, or one focused test proves the
  final packaged-runtime claim.

## Change control and completion evidence

The committed revision of this document is the preregistration authority for
issues `nix-tcz.37.1.2`, `.20`, and `.21`. Candidate results begin only after its
fixture and analysis implementations have been reviewed against this text. Any
change to fixture scale, active workload, repetitions, quiescence, collection,
raw metrics, estimator, seed policy, or thresholds creates a new ledger
revision; old and new results remain separate.

Final programme acceptance requires the complete semantic, lifecycle,
deterministic-budget, geometric-memory, managed-extension, and packaged-runtime
gates, together with removal of product-scale downstream Pi patches. This
document supplies the contract and ledger. It does not claim that those later
gates have run.
