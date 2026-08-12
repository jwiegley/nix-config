# Pi bounded-session memory contract and evidence ledger

This document fixes the meaning, measurement protocol, and evidence boundary of
the Pi bounded-session-memory programme. It governs issue `nix-tcz.37.1` and
precedes candidate measurement: no result obtained before this revision is to
be presented as satisfying the bounded-memory evidence protocol defined below.

The contract concerns normal core execution and managed extensions certified to
use bounded capabilities. It does not assert that an arbitrary JavaScript
process, native library, caller, or third-party extension consumes constant
memory.

Pi Sessions is cancelled and remains audit-only. It is excluded from the
candidate, every managed-extension manifest, every measurement lane, and every
acceptance verdict in this programme.

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
- **Product candidate** is one immutable Pi product revision, its complete
  package derivation, and the exact managed-extension set tested with it.
- **Classic baseline** is an exact unmodified upstream coding-agent snapshot
  measured without the managed gallery. It demonstrates the eager-retention
  problem; it is not a bounded-product candidate.
- **Candidate process set** is the candidate root process and every declared
  helper, worker, sidecar, or descendant used by the measured workload. The
  harness itself is outside this set. Candidate-process-set RSS is the sum of
  the raw RSS samples for every live member at the same retained barrier.
  Unexpected or missing members fail the measurement; the contract does not
  claim to contain malicious state offload by arbitrary third-party code.

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
| Page items and bytes | `SessionRepo`/`SessionTree` query API | Both limits apply before hydration; cursors advance without retaining earlier pages. | Poison-after-limit and multi-scale bounded-paging tests. |
| Hydration-cache bytes and entries | Repository cache | Byte-charged eviction occurs on insertion; replacement and close release ownership. | Cache counters, eviction tests, and replacement lifecycle tests. |
| Terminal rows, previews, and overscan | Terminal presentation layer | View and overscan caps apply before full record hydration. | Navigation tests and terminal-path memory measurements. |
| Event and RPC queue items and bytes | Event/RPC transport | Admission limits and backpressure apply before enqueue; cancellation releases queued payloads. | Queue counters, slow-consumer tests, and shutdown tests. |
| Scanner, reducer, and batch scratch | Bounded scan capability | Record, batch, reducer, and in-flight callback limits apply before handoff; no repository cursor or lease crosses extension-controlled suspension. | Oversized-record, slow-reducer, cancellation, and cursor-release tests. |
| Export, fork, renderer, and spool state | Export or fork implementation | Writer buffers and disk spools are admitted by byte and file limits and obey downstream backpressure. | Exact-output streaming, slow-sink, cancellation, temporary cleanup, and partial-publication tests. |
| Native-runtime state | Runtime and native dependencies | Runtime and backend builds and settings are immutable within an evidence unit; exposed connection and cache counts retain their declared caps, while unexplained history-dependent native drift is reported without subtraction and remains subject to the raw-RSS verdict. | Raw RSS, `maxRSS`, heap, external, and `arrayBuffers` metrics with runtime identity. |
| Concurrent operations | Owning scheduler or caller | Each capability declares a concurrency ceiling; aggregate allowance is the ceiling multiplied by its per-operation bound. | Concurrency counters and saturated-bound tests. |
| Caller-retained results | Capability caller | Ownership transfers on return; certified callers retain no unbounded sequence of pages or streamed records. | Caller audits, poison tests, and managed-extension certification. |
| Managed-extension state and caches | Each certified extension | The extension declares item and byte admission limits and clears owned state on replacement and shutdown. | Per-extension counters, four-scale history workloads, and strict aggregate certification. |
| Prepublication and no-session state | Runtime host | Before durable repository ownership begins, an ephemeral repository or equivalent admission boundary applies the same record and active-context limits. | First-record, new-session, replacement-before-publish, and failure-cleanup tests. |
| Persisted history and rebuildable index | Session repository | Disk may grow with history; normal open retains only fixed repository metadata. | Fixture bytes, index bytes, warm endpoint regression, cold peak, rebuild time, and I/O. |

No adjusted-RSS subtraction is an acceptance metric. Active payload, cache, and
native counters explain a result; they do not reduce the raw resident set used
for the warm RSS verdict.

## Causal trace of the classic implementation

The classic `SessionManager` in the catalog-pinned v0.83 source reads JSONL into
`fileEntries`, an array containing every parsed entry, and builds `byId`, a
`Map` whose values retain those session objects. Compaction changes the
model-facing context but does not remove the corresponding objects from either
container. Whole-history helpers and extensions then derive further strings,
arrays, indexes, or caches from the same live graph.

Consequently, persisted entry count and payload bytes determine the number and
size of objects reachable from a live manager. Invoking garbage collection
cannot reclaim them. The downstream prototype breaks that particular causal
chain by retaining byte offsets and bounded metadata in a rebuildable SQLite
sidecar, hydrating records on demand, and clearing `fileEntries` and `byId` once
the indexed store owns the session. That implementation is valuable regression
evidence, but it is a downstream parallel store rather than the intended
upstream architecture.

Local research associated with the dated upstream-main observation records
asynchronous v4 `SessionStorage`/`SessionRepo` work, including JSONL and SQLite
backends under AgentHarness. This C1 inventory did not line-inspect that
upstream snapshot, so B1 must freshly pin and inspect upstream main before it
attributes the same classic causal path there. The repository direction does
not settle whether SQLite is canonical or JSONL remains canonical behind a
rebuildable index. That choice remains an explicit maintainer architecture
gate. This contract governs either choice; it does not decide it by implication.

## Bounded-memory evidence

The primary proof is deterministic: strict paths expose only bounded point,
page, active-context, and streaming capabilities; every retained term has an
owner and a hard item, byte, concurrency, or lifecycle boundary; and those
counters are identical for equal live inputs at every fixture size. Raw RSS is
a coarse end-to-end regression check for omitted JavaScript, native, or helper
process retention. It is not a statistical proof of asymptotic complexity.

The fixture, workload, counter, process-accounting, sampling, and verdict rules
below are fixed before a product result. A later material change creates a new
protocol revision; old and new results remain separately attributable.

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
and prepared-store hashes, bytes, entries, active-tail counters, and expected
semantic digests. Measurement never mutates a canonical fixture or prepared
warm store; each process receives a disposable same-filesystem copy. If the
selected canonical backend is not JSONL, a frozen importer converts this
logical source fixture. Canonical store and derived-index bytes are reported
separately.

### Evidence stages and product topology

The stages have different purposes:

- **B1 classic baseline** measures one unmodified exact upstream classic-core
  snapshot with an empty extension manifest. It establishes the eager
  `fileEntries`/`byId` causal baseline and is expected to retain
  history-sized state. It neither exercises nor qualifies the later strict
  gallery or Nix wrapper. It uses the same six endpoint blocks for comparable
  descriptive data, but its threshold result is not product qualification.
- **M1 local-source qualification** runs the deterministic gate and RSS
  regression against the locally built strict product before delivery.
- **M2 final-package qualification** replays them without recalibration against
  the exact delivered, Nix-pinned, activation-eligible package and store path.

M1 and M2 use one governing RSS topology: the actual packaged Pi wrapper, the
complete certified managed gallery, a faux provider, and the fixed normal
open/resume/continue workload. The wrapper workload already contains the core,
terminal, and gallery integration; descriptive layers are not duplicate lanes.
Add another lane only when a shipped configuration creates a materially
different live process topology or retained product state that the governing
workload cannot exercise.

Each result bundle records ordinary content identities: protocol revision, Pi
commit and source-tree hash, Nix derivation, output store path and NAR hash,
managed-extension manifest hash, fixture and prepared-store hashes,
runner/analyzer hashes, runtime executable and version, OS generation, exact
host identity, command, and non-secret environment. Existing Git signatures,
Nix content identities, and SHA-256 hashes are sufficient; there is no second
custom evidence-identifier encoding.

### Deterministic gate

At all four fixture sizes, the fixed workload must produce the expected and
equal semantic digests for active context, append, compaction, branch, tree,
fork, export, and replacement. Every declared retained-state item and byte
counter, process role, descriptor, connection, statement, cursor, lease,
listener, timer, queue, cache, view, and caller-owned result count must also be
identical for equal live inputs.

Strict-mode tests reject implicit whole-history materialization before
allocation. Point and page limits, oversized records, streaming backpressure,
cancellation, replacement, close, and slow consumers are merge-blocking
deterministic tests rather than RSS experiments. Any deterministic mismatch
fails before RSS interpretation. This gate, not an RSS fit, establishes that
persisted bytes and entry count are absent from the declared retained-state
envelope.

### Warm RSS regression

The governing RSS sizes are the `1x` 16 MiB and `64x` 1 GiB endpoints.
Freeze six adjacent low/high blocks: three run low then high and three run high
then low in one fixed interleaved order. Every observation uses a fresh process
and a fresh disposable copy of the hashed prepared warm store. There are no
reserves, outlier removal, or replacement observations.

For each process, run the identical workload, reach the retained-state barrier,
verify semantic digests and hard counters, perform the fixed collection and
settling sequence, and record nine raw RSS samples at 250 ms intervals. The
within-process value is their median. For block `i`, let `L_i` and `H_i`
be the low and high process medians and `D_i = abs(H_i - L_i)`. The product RSS
gate passes only when every block is complete and:

```text
max(D_1, D_2, D_3, D_4, D_5, D_6) <= 32 MiB
```

The absolute allowance covers allocator and native-runtime noise; product code
may not spend it as a history-sized budget. Report every difference and raw
sample. Heap, external, array-buffer, `maxRSS`, and PSS are diagnostic and
never subtracted from raw RSS. Six blocks balance endpoint order and leave no
discretion to discard a noisy pair; the test deliberately makes no population
or universal confidence claim. The 32 MiB threshold is a material integration
guard. Exact deterministic counters, not this allowance, enforce the absence of
a history-sized retained term.

Run one cold import or rebuild per fixture size and report peak, latency, I/O,
canonical and derived disk bytes, and temporary-disk use separately. Do not
multiply cold preparation by every warm observation, and do not use cold costs
to excuse a warm-retention failure.

### Process accounting and sampling

Freeze the expected process topology for the workload. Prefer one runtime
process.
When the product genuinely requires helpers, the frozen platform adapter assigns
an inherited run-containment identity before launch and enumerates its members
independently of the current parent PID, including after detachment or
reparenting. If a platform adapter cannot retain and enumerate that membership,
the measured topology must remain single-process. Take a complete census
immediately before the retained samples, at every sample, and immediately after
the ninth sample. The member set and each member's PID, immutable start token,
declared role, and executable identity must be identical across all eleven
censuses. Sum the raw RSS of every member at each retained sample. An exit,
restart, detach/reparent omission, missing member, unexpected member, or
unstable identity fails the observation. The claim excludes malicious or
undeclared state offload by arbitrary third-party code.

The candidate may emit only bounded framed telemetry containing scalar
counters, fixed-length hashes, identifiers, and bounded error metadata. History
records, previews, model text, and arbitrary entry arrays are forbidden. The
harness remains outside the candidate process set.

After the equal workload, wait at most 30 seconds for lifecycle publication,
provider and terminal streams, hooks, cursors, scans, exports, and owned queues
to finish. Poll every 100 ms and require eleven consecutive polls spanning at
least one second with identical logical counters and process identities, zero declared
in-flight operations, and empty owned queues. Record one unforced diagnostic
sample. Then every declared GC-capable runtime in the process set runs its exact
runtime-adapter sequence in frozen role order: one microtask checkpoint, two
event-loop-turn callbacks, and one exposed full collection. Wait one second
without candidate work before the nine retained samples. The runner manifest
records the runtime-specific callback and collection primitives, their role
order, and their source hashes. A missing primitive or adapter error is a
harness failure rather than an invitation to substitute another sequence. The
logical counters and process identities remain stable through the final census.
The collection sequence reduces allocator history as a confounder; it is not a
product mechanism.

Runs are serial on one identified host under one OS generation, runtime,
package, and environment. The frozen host adapter performs one 60-second
preflight before each block using a continuous monotonic clock and twelve
consecutive five-second buckets. It records every raw sample and requires at
most 10% aggregate CPU busy time in every bucket. AC power and nominal thermal
state hold at every bucket boundary; a subscribed warning or critical
memory-pressure event invalidates the window; swap-in and swap-out counters are
unchanged at every boundary; and available space remains at least the declared
temporary-disk budget plus 20 GiB. A suspend or monotonic discontinuity
invalidates the window. At the final boundary, immediately before launch, the
adapter rechecks fixture, prepared-store, executable, and writable-copy
identities and available space. An environmental predicate failure produces a
prelaunch-invalid record. An adapter/API error or an identity, copy, or record
integrity failure produces a prelaunch harness-failure record.

### Outcomes

Each of the six scheduled blocks has an immutable block identifier. Every
preflight invocation for that block has a monotonically increasing attempt
identifier and exactly one terminal preflight record:

- `block_prelaunch_ready`: every environmental, identity, copy, and adapter
  predicate passed. The two frozen endpoint observations begin immediately.
- `block_prelaunch_invalid`: an environmental predicate failed before any
  candidate executable ran. Retain the failed predicate and raw preflight
  samples. The same block remains at the schedule head; no later block may
  overtake it, and a later attempt increments the attempt identifier.
- `block_prelaunch_harness_failure`: the adapter could not evaluate or record a
  predicate exactly, or an identity/copy integrity check failed, before any
  candidate executable ran. The qualification is incomplete. Retain the error;
  review the harness or protocol before retrying that same head block. An
  in-place retry is permitted only when every recorded identity is unchanged;
  any correction that changes one begins a separately named result bundle.

Only `block_prelaunch_ready` may start a candidate. Once either endpoint starts,
that block attempt is governing: a candidate failure ends the qualification and
no replacement attempt is selected. Each started endpoint observation has one
terminal outcome:

- `completed_observation`: containment, quiescence, counters, semantic
  digests, sampling, and cleanup completed. Only this outcome supplies an RSS
  value.
- `started_candidate_failure`: the candidate started and then crashed, timed
  out, changed a hard counter or semantic digest, escaped its declared process
  topology, leaked a resource, or failed quiescence or cleanup. The
  qualification fails; no replacement is selected.
- `started_harness_failure`: the runner lost process membership, sampling, or
  record integrity and candidate responsibility cannot be established. The
  qualification is incomplete; fix and review the runner or protocol before a
  new result.

A reviewed runner correction after a `started_harness_failure` begins a
separately named result bundle rather than adding replacement cells to the
incomplete bundle. Within one bundle, more than one RSS-bearing record for the
same block and endpoint is a duplicate cell and invalidates the bundle.

A common envelope records all identities, fixture, block, block-attempt,
endpoint, order, timestamps, preflight inputs, and invocation state. Each
variant requires only the evidence that can exist at its lifecycle point;
absent measurements are not represented as zero, null, or fabricated digests.
A complete observation contains the full process census, raw samples, counters,
semantics, timing, disk, I/O, environment, and cleanup evidence.

### Harness controls

The runner and analyzer have four small controls:

1. Pure analyzer cases prove that differences of positive or negative 32 MiB
   pass by magnitude, either sign at 32 MiB plus one byte fails, and missing or
   duplicate cells, unit-conversion errors, deterministic-counter mismatch,
   candidate failure, and harness-incomplete records cannot pass. Additional
   cases with correct numeric samples but shuffled block identifiers,
   cross-block low/high pairing, reversed frozen order, or mislabeled endpoints
   must fail.
2. One low/high pair traverses every byte of the hashed low and high inputs
   through the same fixed-size bounded reader, verifies their expected hashes,
   retains only fixture-independent fixed state, and must pass.
3. One low/high pair places a page-touched 64 MiB allocation only in a declared
   helper process at the high endpoint, then detaches or reparents that helper.
   The helper must remain in every containment census, the absolute root-only
   low/high RSS difference must remain within the threshold, aggregate RSS must
   fail, and losing the helper fails the control.
4. The deterministic strict-API suite restores one eager whole-history path at
   each distinct strict load surface. The guard must return the exact typed
   whole-history-forbidden error before allocation, while delegate-call,
   hydration, and allocation counters remain zero. A poison delegate makes any
   bypass or unrelated early exception fail the control.

Controls 1 through 3 are B1-owned and qualify an exact runner, analyzer, host
adapter, and process-topology implementation. Control 4 is A2-owned and
qualifies the strict product surfaces before M1 or M2. Repeat a control group
only when one of its qualified identities changes. An unexpected verdict blocks
candidate measurement; there are no full candidate-by-lane control matrices.

### Evidence and reruns

A result bundle contains the ordinary identity manifest, raw records, analyzer
output, and artifact hashes. It is never overwritten. The owning obr issue
records the bundle reference and hash, verdict, evidence class, reason for any
later run, and exact next action; raw records and per-process events remain in
the immutable bundle rather than becoming obr comments.

This is reproducible engineering evidence under retained signed project
history, not adversarial non-equivocation. Local Git, signatures, exclusive
file creation, and `fsync` cannot prove that an operator did not delete
another local bundle, rewrite history, or invoke the candidate out of band. The
programme makes no such claim and requires no custom transparency log or remote
witness. A later result never erases an earlier named failure; a changed product
or corrected protocol receives a new bundle and remains separately
attributable.

B1 builds and qualifies the fixture generator, runner, analyzer, and controls 1
through 3, then records the classic-core causal baseline. A2 qualifies strict
control 4. M1 records the pre-delivery product result. M2 repeats the unchanged
deterministic and RSS gates against the exact final package eligible for
activation; an M2 failure blocks activation.

The M2 bundle names the passing M1 bundle. Its protocol revision, fixture and
prepared-store manifests, fixed workload, process-role schema, six-block
endpoint and order schedule, quiescence, sampling, outcome and analyzer rules,
managed-extension manifest, and threshold must equal the named M1 values. Its
signed crosswalk maps the M1 product source tree to the reviewed delivery
commits, Nix pin, derivation, output path, and NAR hash. Delivery provenance and
package derivation, output, and store identities are expected permissible
differences. A runner binary, analyzer binary, host-adapter, process-topology,
or strict-suite identity may also differ only when required for the final
platform, with the difference enumerated, the frozen semantics unchanged, and
its owning controls rerun before M2. A product source, managed extension,
fixture, workload, schedule, outcome rule, analyzer rule or verdict semantic,
or threshold change requires a new passing M1 under the new identity or
protocol; packaging-only differences are enumerated rather than treated as
equivalent by assertion.

For one product identity and protocol revision, a completed threshold or
deterministic failure and every `started_candidate_failure` are terminal; an
unchanged-product passing rerun cannot replace them. A
`started_harness_failure` permits a new bundle only after a reviewed runner or
protocol correction and the required control reruns. Activation requires one
passing M2 bundle for the exact final package and current protocol, explicit
disposition of every earlier bundle, and no earlier product failure under that
same product and protocol identity.

## Evidence ledger

This ledger distinguishes source identity, historical prototype evidence, and
future evidence governed by this contract.

| Evidence | Identity and result | Standing under this contract |
| --- | --- | --- |
| Programme baseline | Signed Nix `b3263de3d700ab0650fb9cceadd6586fd1126f1a`; Pi v0.83 source pin `845d6ff1f6643aba440341cce877ce1c43ebbc39`. | Establishes the local source and package baseline only. |
| Upstream inspection | Live GitHub metadata placed `earendil-works/pi` main at `534bcbffb7e1e7551d9ee3572dfeb278e203e493` on 2026-08-11. Line-level inspection used the locally retained, catalog-pinned v0.83 source `845d6ff1f6643aba440341cce877ce1c43ebbc39`. Local research notes point to upstream [issue `#7937`](https://github.com/earendil-works/pi/issues/7937) for unfinished v4 work; this inventory did not recover and freeze the issue body or comments. | Establishes the remote identity observed at that dated checkpoint separately from the exact inspected source. The issue pointer is coordination context, not source evidence or maintainer approval. This row does not establish an evergreen current identity, bind v0.83 line evidence to the observed main commit, or prove that a planned `SessionTree` interface exists. |
| Downstream prototype | Signed Nix commit `e2c002e06cc4378b5a55cc1659e99caaab408dcb`; `pi-bounded-session-history.patch` SHA-256 `4bdb9524839764bf9639740be782e0719168d885332e5cf2b70da16c95f7494a`, 13,831 lines. | Supplies a causal trace and regression corpus; it is not the intended upstream architecture. |
| One-gibibyte synthetic run | The public acceptance discussion on [GitHub issue `#128`](https://github.com/jwiegley/nix-config/issues/128#issuecomment-5229843110) names signed acceptance candidate `e44cb99c53ba1f2ae67e9714aff8bbad93243740` and reports `historyBytes=1,074,007,601`, 1,024 messages, 64 compactions, `maxRss=250,085,376`, and adjusted growth `40,501,246` bytes. Independently, signed Nix commit [`ce802467fecd488b8b835da6cc48f7f804797ce5`](https://github.com/jwiegley/nix-config/blob/ce802467fecd488b8b835da6cc48f7f804797ce5/doc/CLEANUP-WIGGUM-HANDOFF.md#L225-L249), `doc/CLEANUP-WIGGUM-HANDOFF.md` blob `20d9a687b9d619b09129f187bdd88481e28d7f77`, records prototype base `e2c002e0`, the same history size and compaction count, and adjusted growth `40,402,944` bytes. | Historical single-scale evidence with an unresolved 98,302-byte reporting conflict. Local Git does not establish whether the values describe different runs, a correction, or transcription drift. The absent raw bundle prevents independent run-to-commit reconstruction; neither adjusted value nor the unrepeated run satisfies the paired endpoint product gate. |
| Eight-hour synthetic run | The same signed [historical checkpoint](https://github.com/jwiegley/nix-config/blob/ce802467fecd488b8b835da6cc48f7f804797ce5/doc/CLEANUP-WIGGUM-HANDOFF.md#L278-L328) records exit 0; `durationMs=28,800,471`; 26,893 messages; 1,681 compactions; `historyBytes=888,276,251`; first/last adjusted-RSS medians `92,307,020` and `94,355,018`; adjusted growth `2,047,998` bytes; and private evidence-manifest SHA-256 `c30f01808c30701d3d66195c72ee7e821d934c4ca00f615cefd7ab0f75cc3aca`. | The computational duration and adjusted-growth criterion was reported as passed. The auxiliary retained-path/provenance checker remained incomplete because it compared macOS `/var` with the equivalent `/private/var` spelling. The private artifact is not reproduced by this repository, and adjusted RSS is not the paired endpoint verdict defined here. |
| Manual soak procedure | Signed commit [`e44cb99c53ba1f2ae67e9714aff8bbad93243740`](https://github.com/jwiegley/nix-config/blob/e44cb99c53ba1f2ae67e9714aff8bbad93243740/doc/PI-EIGHT-HOUR-SOAK.md), `doc/PI-EIGHT-HOUR-SOAK.md` blob `23ce98c3d16a0481ac7ed9851adf22b22ca6fcec`, SHA-256 `54775179da5dee325330d4c47ac74e9d780c9d7fb2acec7c21b5fe6a9196d537`. | Preserves the final incomplete-checker disposition and reproducible optional procedure; another soak is not a pending acceptance gate. |
| Classic causal baseline | **NOT RUN.** | B1 `.2` owns the exact upstream classic-core measurement. It is expected to expose eager history retention and cannot satisfy M1 or M2. |
| Local-source product result | **NOT RUN.** | M1 `.21` must run the four-size deterministic gate and paired endpoint RSS regression against the local strict product before delivery. |
| Final packaged product result | **NOT RUN.** | M2 `.31` must replay the same gates without recalibration against the exact delivered, Nix-pinned, package-qualified store path before activation. |

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
| Persisted history is absent from normal retained core state; peak, cold rebuild, latency, disk, caller ownership, and RSS remain distinct | Governing invariant, terms, and explicit non-guarantees | Deterministic gate and local-source RSS result in `nix-tcz.37.1.21`, then the unrecalibrated final packaged replay in `.31`, with cold and disk envelopes reported separately |
| Compatibility and strict bounded behavior are explicit and do not silently truncate | Compatibility boundary | Capability conformance in `.14`, managed certification in `.19`, and final boundary in `.24` |
| Every covered operation has an item, byte, cancellation, ownership, or backpressure boundary | Covered operations and live-work budget ledger | Backend and runtime work in `.5` through `.13`, followed by deterministic gate `.20` |
| Classic eager retention has a source-supported causal trace | Classic causal trace and downstream-prototype ledger row | Freshly pinned exact-upstream classic baseline `.2` and removal from normal execution in `.7` |
| Upstream and prototype identities and historical claims remain attributable | Evidence ledger | Immutable candidate/package identities in `.30`, delivery identity in `.27`, and Nix pin crosswalk in `.25` |
| The bounded-memory procedure is fixed before product qualification | Fixtures, deterministic counters, paired endpoint schedule, process accounting, outcomes, controls, and threshold | Runner and controls 1 through 3 in `.2`; strict-surface control 4 in `.20`; local-source result in `.21`; exact packaged replay in `.31` |
| Results remain reproducible and failures are not silently overwritten | Ordinary Git, Nix, fixture, runner, host, raw-bundle, and artifact identities | Named result bundles and dispositions in `.2`, `.21`, and `.31`; explicit local-auditability limitation |
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
  certification;
- a finite RSS regression proves behavior on every host, allocator, workload,
  or unbounded history size;
- retained local Git and artifact history proves that an operator could not
  delete another local result or invoke the candidate out of band; or
- the downstream prototype, an optional soak, or one focused test proves the
  final packaged-runtime claim.

## Change control and completion evidence

The signed committed revision of this document is the protocol authority for
issues `nix-tcz.37.1.2`, `.20`, `.21`, and `.31`. Product results begin only
after the fixture, deterministic gate, process accounting, outcome schema,
controls, and analyzer have been reviewed against this text. A material change
to fixture endpoints, active workload, paired schedule, process aggregation,
quiescence, raw metrics, controls, or the 32 MiB threshold creates a new
protocol revision. Old and new results remain separate and named.

Final programme acceptance requires the complete semantic, lifecycle,
deterministic-budget, paired-RSS, managed-extension, and packaged-runtime
gates, together with removal of product-scale downstream Pi patches. This
document supplies the contract and ledger. It does not claim that those later
gates have run.
