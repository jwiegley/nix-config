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
- **Candidate process set** is the candidate root process and every helper,
  worker, sidecar, or descendant it creates, including a process that attempts
  to detach. The harness itself is outside this set. Candidate-process-set RSS
  is the sum of the raw RSS samples for every live member at the same retained
  barrier.

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
exactly nine valid isolated repetitions per size. In every lane-and-size
stratum, indices `1` through `9` are primary and `10` through `12` are reserves;
these assignments are frozen before execution. Exactly nine observations enter
the estimator, never fewer or more. Exhausting the reserves makes the evidence
unit incomplete. A repetition reuses no process, repository object, derived
index, writable cache, or temporary state from another repetition.

An evidence unit is one immutable tuple in this fixed order: protocol revision,
campaign designation, candidate commit, candidate source-manifest SHA-256, package derivation,
package-output SHA-256, managed-extension-manifest SHA-256, fixture-manifest
SHA-256, runner-analyzer-control-manifest SHA-256, exact
host-and-environment-manifest SHA-256, host identity class, platform and OS
generation, runtime executable SHA-256 and version, and lane identifier. The
host-and-environment manifest identifies the exact host instance and frozen
non-secret measurement configuration; it neither contains nor hashes
credentials. The candidate source manifest and managed-extension manifest hash
canonical sorted path, type, mode, symlink target, and file-byte identities;
they exclude VCS metadata, commit names, and timestamps. The package-output
hash is the canonical NAR hash of output content rather than its store-path
name. Encode each UTF-8 field as a four-byte unsigned big-endian byte length
followed by its bytes, prefix the sequence with
`UTF8("nix-tcz.37.1.1-m1-unit-v2\0")`, and define
`evidence_unit_id` as the lowercase hexadecimal SHA-256 of that sequence. The
manifest records every source field and the resulting identifier, and freezes
them before candidate output is observed. Any field change creates a distinct
evidence unit rather than being pooled with the old one.

Each cell uses three fresh child processes. The cold child imports or rebuilds
and reports cold peak, latency, I/O, and disk. A preparation child creates and
closes a pristine derived store without contributing a memory observation. The
warm child reopens that prepared store, performs the fixed workload, and remains
open at the retained-state barrier while memory is measured.

Each child runs in a fresh runner-owned containment scope. The harness remains
outside the scope; the candidate root and every local process or service it
starts or gives fixture-derived state remain inside it. Detachment or
reparenting does not remove candidate ownership. The sole allowed transfer to
the outside harness is a runner-defined framed telemetry channel capped at 64
KiB per frame and 1 MiB total candidate-emitted bytes per child. Its frozen
schema admits scalar counters, fixed-length hashes and semantic digests,
identifiers, and bounded error metadata; it rejects history records, previews,
model text, arrays of entries, and arbitrary payloads. Escape from containment,
offload of candidate state through any other channel, telemetry overflow, or
unstable membership at the retained-state barrier is a candidate lifecycle
failure. At each retained sample, enumerate the complete stable scope and
record the PID, immutable start token, declared role, executable SHA-256, and
raw RSS of every member. The observation is their sum without subtracting
shared pages. Record PSS when a platform supplies it, but treat it as diagnostic
rather than the verdict.

Order all primary and reserve cells before execution by sorting the raw 32-byte
SHA-256 values of the following byte string in ascending byte order:

```text
UTF8("nix-tcz.37.1.1-m1-order-v1\0" + lane_id + "\0" + size_label + "\0" + decimal_repetition_index)
```

Freeze the resulting order before candidate output is observed. Execute all
primary cells in frozen-key order. After that phase, each lane-and-size stratum
has a deficit equal to nine minus its valid-primary count. Select the
lowest-numbered unused reserves needed to fill each deficit and execute those
cells in frozen-key order; repeat this rule after each reserve wave. No reserve
runs otherwise, the operator has no replacement choice, and no cell may be
added after reserve index `12`. The three children of one cell remain adjacent.
Runs occur serially on one identified idle host, on AC power, under one OS
generation, runtime binary, package derivation, and environment. Any material
change begins a new evidence unit.

### Campaign registration and cell validity

A confirmatory campaign comprises the three lane evidence units for one
immutable candidate. The only governing designations are `baseline-b1`,
`local-source-m1`, and `final-packaged-m2`; they are non-substitutable, and a
later designation never replaces an earlier verdict. Before any control child
starts, append and fsync the
signed control preregistration with all identity manifests, schedules,
validity predicates, and expected verdicts. After control qualification passes
and before the first governing confirmatory-measurement child starts, append
and fsync a signed campaign preregistration containing the campaign and
evidence-unit identifiers, all manifest hashes, the complete primary and
reserve cell order, the exhaustive validity predicates, the control
preregistration and result hashes, and the confirmatory designation. A campaign
starts when its first governing confirmatory-measurement child is invoked.
Every control attempt, started campaign, and cell, including aborted, invalid,
incomplete, and failing work, remains in the append-only evidence report.

Exactly one confirmatory campaign may start for a fixed protocol revision,
governing designation, and candidate key. That key is the candidate commit,
candidate source-manifest SHA-256, package derivation, package-output SHA-256,
and managed-extension-manifest SHA-256 in canonical evidence-tuple encoding.
Host, fixture, seed, order, and attempt identifiers are intentionally not key
fields and cannot create another chance to pass. An interrupted campaign may
resume only at its next unstarted frozen cell; a started cell is never rerun
except through the deterministic reserve rule. Later unchanged-candidate runs
are diagnostic and cannot replace, pool with, or override the governing
verdict. Within one designation, a new governing campaign requires either a
recorded substantive product change that changes the source-manifest,
package-output, or managed-extension-manifest SHA-256, or a substantive
protocol correction committed before output is observed. A commit-only,
derivation-only, seed, order, revision-label, host, fixture, or attempt change
is insufficient. The separately frozen M1 and M2 designations both remain
required even if their substantive product hashes happen to match.

A scheduled repetition is a prelaunch non-observation only when no candidate
executable has been invoked and one of these machine-evaluable predicates is
true: an expected fixture, package, executable, or manifest hash mismatches;
the disposable copy cannot be created and fsynced; a required measurement API
fails its empty-process self-test; AC power is absent; thermal state is not
nominal; the platform reports memory pressure; swap page-in or page-out
counters changed during the preceding 60-second preflight; or free space is
less than the declared peak temporary-disk budget plus 20 GiB. The runner
commits the predicate inputs and result before launch and before the selector or
analyzer receives any RSS value. No human override is permitted.

An invalid prelaunch repetition remains in the raw evidence and is replaced
only by the deterministic reserve procedure. An unlisted harness defect makes
the campaign incomplete. Once candidate invocation begins, a crash, timeout,
missing field, containment failure, quiescence failure, budget or counter
breach, pressure event, cleanup failure, or other candidate behavior fails the
lane and never invalidates the repetition.

### Quiescence and collection

After open and the equal workload, wait for lifecycle publication, provider and
terminal streams, extension hooks, cursors, scans, exports, and all
candidate-owned queues to finish. The barrier has a 30-second deadline and
requires stable logical live counters, a stable candidate process set, and no
candidate task pending.

Record an unforced candidate-process-set sample first. Drain microtasks and two
event-loop turns in every GC-capable candidate runtime. Sort those runtimes by
declared role, executable SHA-256, and immutable start token, then perform
exactly three collection rounds. In each round, invoke exactly one full
collection in every sorted runtime through its frozen platform hook
(`global.gc()` for Node processes launched with `--expose-gc`), await its
acknowledgement, and yield one event-loop turn there. No GC-capable member may
be skipped. Wait one second without work or collection. Record nine raw RSS
samples at 250 ms intervals; each sample is the synchronized sum across the
stable candidate process set, and the repetition's warm retained RSS is their
median. Record both pre-collection and post-collection per-process and
aggregate metrics. The fixed collection protocol reduces allocator history as
a confounder; it is not a runtime mechanism, and no repeated collection occurs
during the measured workload.

### Raw record

Each repetition emits one append-only JSON record containing at least:

- campaign and evidence-unit identifiers, manifest hashes, candidate commit,
  package derivation, executable hashes, runtime version, OS generation, host
  identity class, lane, scale, repetition, primary or reserve status, frozen
  order, prelaunch predicate inputs and result, and timestamps;
- fixture hashes, JSONL bytes and entries, derived-index bytes, and disposable
  copy identity;
- active entries and bytes, admitted record maximum, page items and bytes,
  cache entries and bytes, view and overscan counts, queued items and bytes,
  scanner and reducer scratch, sink and spool bytes, concurrency,
  managed-extension state, and caller-retained result counts;
- raw `rss`, `maxRSS`, `heapTotal`, `heapUsed`, `external`, and `arrayBuffers`
  before and after collection, together with all nine per-process and summed
  candidate-process-set retained samples;
- containment identity, process births and exits, executable identities and
  roles, plus open cursors, statements, connections, descriptors, leases,
  listeners, timers, pending tasks, and child processes at each lifecycle
  boundary;
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

For equal live inputs, every retained-state item and byte counter is identical
at all four scales, including repository metadata, candidate-process-set
cardinality and role/executable multiset, and every hard logical resource count.
Fresh PIDs and start tokens need not match. Any other mismatch is a failure
before statistical RSS analysis.

For each lane, compute the median warm retained RSS at each size from its
exactly nine governing observations. Compute the Theil–Sen slope from all
cross-size pairs among those governing observations, using exact immutable
source-fixture bytes as `x` and raw warm retained RSS as `y`; equal-size pairs
are excluded. Express the result as mebibytes of RSS per gibibyte of
source-fixture history.

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

No outlier is discarded. The exhaustive prelaunch predicates above are the
only route to a reserve; every started or invalid cell remains in the raw
evidence. Candidate-owned quiescence, cleanup, budget, containment, counter, or
lifecycle failures are failures rather than invalid repetitions. Cold rebuild
peak, latency, I/O, disk, and exact-operation latency receive separate
descriptive envelopes and cannot excuse a warm-retention failure.

### Harness controls

Before any governing confirmatory-measurement child starts, complete exactly
one preregistered control qualification. Bind it to the same protocol, base
candidate source and package identities, fixtures, managed-extension manifest,
host-and-environment manifest, and runner-analyzer-control manifest as the
confirmatory campaign; changing any of those fields requires a new control
qualification. Control children are not governing candidate measurements. The
bounded and injected-slope controls each run the complete three-lane, four-size
matrix with exactly nine valid repetitions and three reserves per stratum,
using the candidate ordering, validity, containment, quiescence, sampling, and
analysis rules. Every bounded-control lane must pass both RSS criteria. Every
injected-slope lane retains and page-touches an additional 8 MiB per GiB of
immutable source-fixture bytes through the ninth retained sample and must fail
the slope criterion.

The strict-surface mutation runs exactly one valid isolated `64x` cell per lane,
with three preregistered reserves. It restores one classic whole-history
materialization and passes only when every lane trips the eager-materialization
sentinel before RSS analysis; its RSS result is diagnostic only. All control
attempts and records are preregistered and retained. An incomplete control or
unexpected verdict blocks the governing confirmatory campaign and requires a
substantive recorded correction and new contract revision; it may not simply be
retried.

The analyzer also uses exact synthetic observations below, exactly at, and
above the slope threshold, plus a non-monotone median case. Control records,
expected verdicts, and analyzer hashes are part of the preregistration;
candidate output cannot set or revise them. If the bounded or injected-slope
control does not produce its required verdict, the host protocol, span, or
repetition design must be revised in a new contract revision before any
governing confirmatory campaign starts. The frozen synthetic suite executes
exactly once.

## Evidence ledger

This ledger distinguishes source identity, historical prototype evidence, and
future evidence governed by this contract.

| Evidence | Identity and result | Standing under this contract |
| --- | --- | --- |
| Programme baseline | Signed Nix `b3263de3d700ab0650fb9cceadd6586fd1126f1a`; Pi v0.83 source pin `845d6ff1f6643aba440341cce877ce1c43ebbc39`. | Establishes the local source and package baseline only. |
| Upstream inspection | Live GitHub metadata placed `earendil-works/pi` main at `534bcbffb7e1e7551d9ee3572dfeb278e203e493` on 2026-08-11. Line-level inspection used the locally retained, catalog-pinned v0.83 source `845d6ff1f6643aba440341cce877ce1c43ebbc39`. Local research notes point to upstream [issue `#7937`](https://github.com/earendil-works/pi/issues/7937) for unfinished v4 work; this inventory did not recover and freeze the issue body or comments. | Establishes the remote identity observed at that dated checkpoint separately from the exact inspected source. The issue pointer is coordination context, not source evidence or maintainer approval. This row does not establish an evergreen current identity, bind v0.83 line evidence to the observed main commit, or prove that a planned `SessionTree` interface exists. |
| Downstream prototype | Signed Nix commit `e2c002e06cc4378b5a55cc1659e99caaab408dcb`; `pi-bounded-session-history.patch` SHA-256 `4bdb9524839764bf9639740be782e0719168d885332e5cf2b70da16c95f7494a`, 13,831 lines. | Supplies a causal trace and regression corpus; it is not the intended upstream architecture. |
| One-gibibyte synthetic run | The public acceptance discussion on [GitHub issue `#128`](https://github.com/jwiegley/nix-config/issues/128#issuecomment-5229843110) names signed acceptance candidate `e44cb99c53ba1f2ae67e9714aff8bbad93243740` and reports `historyBytes=1,074,007,601`, 1,024 messages, 64 compactions, `maxRss=250,085,376`, and adjusted growth `40,501,246` bytes. Independently, signed Nix commit [`ce802467fecd488b8b835da6cc48f7f804797ce5`](https://github.com/jwiegley/nix-config/blob/ce802467fecd488b8b835da6cc48f7f804797ce5/doc/CLEANUP-WIGGUM-HANDOFF.md#L225-L249), `doc/CLEANUP-WIGGUM-HANDOFF.md` blob `20d9a687b9d619b09129f187bdd88481e28d7f77`, records prototype base `e2c002e0`, the same history size and compaction count, and adjusted growth `40,402,944` bytes. | Historical single-scale evidence with an unresolved 98,302-byte reporting conflict. Local Git does not establish whether the values describe different runs, a correction, or transcription drift. The absent raw bundle prevents independent run-to-commit reconstruction; neither adjusted value nor the unrepeated run satisfies the geometric gate. |
| Eight-hour synthetic run | The same signed [historical checkpoint](https://github.com/jwiegley/nix-config/blob/ce802467fecd488b8b835da6cc48f7f804797ce5/doc/CLEANUP-WIGGUM-HANDOFF.md#L278-L328) records exit 0; `durationMs=28,800,471`; 26,893 messages; 1,681 compactions; `historyBytes=888,276,251`; first/last adjusted-RSS medians `92,307,020` and `94,355,018`; adjusted growth `2,047,998` bytes; and private evidence-manifest SHA-256 `c30f01808c30701d3d66195c72ee7e821d934c4ca00f615cefd7ab0f75cc3aca`. | The computational duration and adjusted-growth criterion was reported as passed. The auxiliary retained-path/provenance checker remained incomplete because it compared macOS `/var` with the equivalent `/private/var` spelling. The private artifact is not reproduced by this repository, and adjusted RSS is not the geometric verdict defined here. |
| Manual soak procedure | Signed commit [`e44cb99c53ba1f2ae67e9714aff8bbad93243740`](https://github.com/jwiegley/nix-config/blob/e44cb99c53ba1f2ae67e9714aff8bbad93243740/doc/PI-EIGHT-HOUR-SOAK.md), `doc/PI-EIGHT-HOUR-SOAK.md` blob `23ce98c3d16a0481ac7ed9851adf22b22ca6fcec`, SHA-256 `54775179da5dee325330d4c47ac74e9d780c9d7fb2acec7c21b5fe6a9196d537`. | Preserves the final incomplete-checker disposition and reproducible optional procedure; another soak is not a pending acceptance gate. |
| Local-source geometric result | Not yet measured. | `.21` must use this revision's fixtures, raw record, repetitions, estimator, and thresholds before product delivery. |
| Final packaged geometric result | Not yet measured. | `.31` must replay the same frozen protocol without recalibration against the exact delivered, Nix-pinned, package-qualified store path before activation. |

The historical numerical results above derive from the linked public acceptance
discussion and the exact signed Git objects named in the ledger. They are
retained as attributed provenance, not silently collapsed into one run or
promoted to stronger evidence.
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
| Persisted history is absent from normal retained core state; peak, cold rebuild, latency, disk, caller ownership, and RSS remain distinct | Governing invariant, terms, and explicit non-guarantees | Local-source geometric result in `nix-tcz.37.1.21` and unrecalibrated final packaged replay in `.31`, with cold and disk envelopes reported separately |
| Compatibility and strict bounded behavior are explicit and do not silently truncate | Compatibility boundary | Capability conformance in `.14`, managed certification in `.19`, and final boundary in `.24` |
| Every covered operation has an item, byte, cancellation, ownership, or backpressure boundary | Covered operations and live-work budget ledger | Backend and runtime work in `.5` through `.13`, followed by deterministic gate `.20` |
| Classic eager retention has a source-supported causal trace | Classic causal trace and downstream-prototype ledger row | Current-main baseline `.2` and removal from normal execution in `.7` |
| Upstream and prototype identities and historical claims remain attributable | Evidence ledger | Immutable candidate/package identities in `.30`, delivery identity in `.27`, and Nix pin crosswalk in `.25` |
| The geometric procedure is fixed before candidate observation | Fixtures, repetitions, quiescence, raw record, estimator, controls, and thresholds | Runner and required control verdicts in `.2`; local-source measurement in `.21`; exact packaged replay in `.31` |
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
issues `nix-tcz.37.1.2`, `.20`, `.21`, and `.31`. Candidate results begin only
after its fixture, process-containment, campaign-ledger, control, and analysis
implementations have been reviewed against this text. Any change to fixture
scale, active workload, repetitions, campaign stopping, cell validity, reserve
selection, containment or process aggregation, quiescence, collection, raw
metrics, identity manifests, control schedules, estimator, seed policy, or
thresholds creates a new ledger revision; old and new results remain separate.

Final programme acceptance requires the complete semantic, lifecycle,
deterministic-budget, geometric-memory, managed-extension, and packaged-runtime
gates, together with removal of product-scale downstream Pi patches. This
document supplies the contract and ledger. It does not claim that those later
gates have run.
