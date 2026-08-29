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

Total persisted session bytes and entry count contribute no proportional term
to in-scope Pi-controlled live memory. For a fixed active context, fixed
declared budgets and concurrency, and fixed reviewed topology, opening,
resuming, and continuing a session therefore use the same bounded logical
resources whether the persisted history contains sixteen mebibytes or one
gibibyte.

The live-state envelope comprises named terms rather than one anonymous
allowance:

```text
in-scope Pi-controlled live state
  = fixed repository and runtime-host state
  + active context
  + largest admitted physical record
  + query pages
  + repository caches
  + terminal views and overscan
  + event and RPC queues
  + scanner and reducer scratch
  + export sinks and spools
  + exposed native and dependency handles and caches
  + concurrent operations
  + caller-retained results
  + bounded prepublication state
```

Total persisted bytes and total entry count are absent from that expression as
scale factors. A fixed-width aggregate fact such as the total-entry count is
permitted; a payload, object, offset, hash, flag, or other item retained once per
historical record is not. History size may determine scan duration, index size,
rebuild I/O, and total disk use, but not the amount of in-scope live memory.

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
- **In-scope live state** includes history-derived values reachable at any
  program point, including synchronous locals, parser and exposed native
  buffers, transient accumulators, suspended operations, and declared child
  processes. It is not limited to objects left at a quiescent barrier.
- **Warm retained state** is the state remaining after the package has opened a
  prepared fixture, completed the prescribed equal workload, quiesced, and
  undergone the collection protocol frozen in the qualification harness.
- **Cold rebuild** is the first open of a fixture whose rebuildable derived state
  is absent. Its peak, latency, I/O, and disk effects are reported separately.
- **Hydration** is conversion of bounded persisted records into live language
  objects.
- **Caller-retained state** is any result that remains reachable because the
  caller keeps it after a bounded operation returns.
- **Certified managed extension** is a managed extension whose default path uses
  only the strict bounded capability set and has passed the extension gate.
- **Product candidate** is one immutable Pi product revision, its complete
  package derivation, exact managed-extension set, configured budgets, and
  seeded product configuration tested with it.
- **Classic baseline** is an exact unmodified upstream coding-agent snapshot,
  pinned and then inspected before behavioral attribution, and measured without
  the managed gallery. When it retains the classic eager containers, it
  demonstrates that problem; it is not a bounded-product candidate.
- **Candidate process set** is the candidate root process and every declared
  helper, worker, sidecar, or descendant used at any point in the measured
  workload. The harness itself is outside this set. Candidate-process-set RSS
  is the sum of the raw RSS samples for every live member at the same retained
  barrier. Unexpected or missing members fail the measurement; the contract
  does not claim to contain malicious state offload by arbitrary third-party
  code.
- **Retained barrier** leaves the session open, quiescent, and ready for the
  next interaction. Closing, replacing, or restarting it before sampling does
  not qualify.

## Compatibility boundary

Pi exposes two deliberate modes during migration.

### Compatibility mode

Compatibility mode may retain an explicit legacy reader for callers that ask to
materialize complete history. Such an operation is labelled expensive, runs
only on demand, and transfers ownership of the returned memory to its caller.
It neither truncates history nor pretends that an array has become lazy.

The invocation of a legacy whole-history materializer, and the process for the
lifetime of its result, are outside the strict memory claim. Compatibility mode
is a migration facility, not a certified default.

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
measured. Any limit change creates a different product candidate and requires
requalification; changing an evidence rule requires a new protocol revision.

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
| Exposed native and dependency state | Runtime host and reviewed dependencies | History-derived handles, buffers, connections, and caches exposed to reviewed source retain declared caps. Opaque allocator and runtime internals are outside the source argument and are observed only by the finite RSS check. | Exposed resource counters plus raw RSS, `maxRSS`, heap, external, and `arrayBuffers` diagnostics with runtime identity. |
| Concurrent operations | Owning scheduler or caller | Each capability declares a concurrency ceiling; aggregate allowance is the ceiling multiplied by its per-operation bound. | Concurrency counters and saturated-bound tests. |
| Caller-retained results | Capability caller | Ownership transfers on return; certified callers retain no unbounded sequence of pages or streamed records. | Caller audits, poison tests, and managed-extension certification. |
| Managed-extension state and caches | Each certified extension | The extension declares item and byte admission limits and clears owned state on replacement and shutdown. | Per-extension counters, four-scale history workloads, and strict aggregate certification. |
| Prepublication and no-session state | Runtime host | Before durable repository ownership begins, an ephemeral repository or equivalent admission boundary applies the same record and active-context limits. | First-record, new-session, replacement-before-publish, and failure-cleanup tests. |
| Persisted history and rebuildable index | Session repository | Disk may grow with history; normal open retains only fixed repository metadata. | Fixture bytes, index bytes, warm endpoint regression, cold peak, rebuild time, and I/O. |

No adjusted-RSS subtraction is an acceptance metric. Active payload, cache, and
exposed resource counters explain a result; they do not reduce the raw resident
set used for the warm RSS verdict.

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
backends under AgentHarness. Although the C1 inventory did not line-inspect that
snapshot, B1 subsequently pinned and inspected exact upstream commit
`2e4d23959485279aa2da1a45103de2ea22d46395` (`pi-coding-agent` 0.84.1) before
behavioral attribution. That source retains `fileEntries` and `byId`, loads the
complete file before indexing it, and retains appended entries in both
structures (`packages/coding-agent/src/core/session-manager.ts`, lines 862-965
and 1045 in the frozen source). The repository direction does not settle
whether SQLite is canonical or JSONL remains canonical behind a rebuildable
index. That choice remains an explicit maintainer architecture gate. This
contract governs either choice; it does not decide it by implication.

## Bounded-memory evidence

The programme uses three different kinds of evidence:

1. an architectural review closes the reviewable history-dataflow inventory for
   the exact Pi core, certified managed consumers, dependencies, and process
   topology;
2. deterministic tests verify the semantics and enforcement of every
   inventoried bound; and
3. a small packaged raw-RSS check catches material integration omissions in the
   exact measured build.

Finite fixtures, counter equality, and RSS do not by themselves prove an
asymptotic property. The architectural review is the basis for the claim about
in-scope Pi-controlled live state; the other two layers test that reviewed
design.

### Fixtures and semantic oracles

Prepare a logically nested deterministic family of linear-and-branched
histories at nominal sizes 16 MiB, 64 MiB, 256 MiB, and 1 GiB. Each step adds
pre-tail history while preserving one normalized active projection, terminal
branch topology, model and thinking state, labels, extension snapshot, and
post-open workload. Both persisted bytes and persisted entry count increase by
at least threefold at each step; this is not a claim that the files are literal
byte prefixes.

The fixture manifest records the generator and seed, exact source and prepared
store hashes, bytes, entries, active-tail gauges, and independently reviewed
semantic oracles. History-dependent operations such as complete tree, fork,
JSONL, and HTML export match the expected output for their own fixture. Only
the active projection, common-tail effects, identical post-open operations, and
the applicable live occupancy gauges agree across sizes. Lifecycle operations
reach the same bounded cleanup state rather than manufacture an equal content
digest.

A versioned operation-to-oracle table covers every operation and certified
consumer. Each row fixes the logical projection and ordering, volatile-field
normalization, comparison class (`per_fixture`, `history_invariant`, or
`typed_lifecycle`), execution phase (`deterministic` or `rss_normal`), expected
value source, owner, and live item, byte, concurrency, and spool limits.
Candidate output cannot define or update an expected value. Exact byte streams
are hashed incrementally; structured results use a frozen incremental encoding.
Pages are released as they are folded, and high-cardinality comparisons use
only their bounded external spool. The exact encoding belongs to the reviewed
A2/H1 manifest rather than this architecture contract.

Canonical fixtures and prepared stores are immutable. Each process receives a
fresh disposable copy. A selected non-JSONL backend uses one frozen streaming
importer; canonical and derived bytes remain separately reported.

Fixture generation, import, copy, hashing, projection, comparison, cold
collection, and bundle writing each have fixed live chunk, record, batch,
queue, and spool limits and cleanup counters. B1 owns the generator, importer,
and reference oracle; A2 owns strict-product projectors and comparators; H1 owns
copy, recording, and bundle publication. The intentionally eager classic B1
subject is the sole permitted O(n)-retained component; no evidence helper
inherits that exception.

### Architectural bound and review closure

History independence is a claim about the exact reviewed Pi core and certified
managed consumers. Every normal history ingress crosses the strict bounded
`SessionRepo`/`SessionTree` capability before hydration. Compatibility readers
that explicitly materialize whole history remain outside the claim.

Freeze a capability-consumer and history-dataflow crosswalk for the exact source
tree, lockfile, gallery, and process topology. Its inventory covers every source
reviewable root or transient value that receives history-derived data or whose
cardinality or lifetime is driven by a history operation: fields, module
collections, synchronous locals, parser and exposed native buffers, closures,
listeners, caches, queues, timers, caller results, accumulators across any
callback or suspension boundary, and declared child-process state. Each entry
records its source location, owner, construction and release sites, item and
byte bound, enforcement point, and deterministic test. Unrelated fixed product
roots remain part of product identity and RSS but not this history-dataflow
argument.

For fixed active context, budgets, concurrency, and process topology, no
in-scope live term may grow with total persisted bytes or total entry count.
IDs, offsets, hashes, flags, and other per-entry metadata count as history state
just as payloads do; an unbounded history-keyed index may live only in durable
storage. An unclassified root or transient operation state fails acceptance,
even when ordinary counters and RSS stay green.

Independent review of that finite source slice supplies a non-formal
closed-world engineering argument and verifies the sum of its declared bounds;
it does not prove an absolute negative about opaque runtime or allocator
internals. A relevant source, consumer, dependency, topology, configuration, or
budget change invalidates the review. Opaque internals remain outside the
architectural claim and under the finite RSS integration observation only.

### Deterministic conformance

Counter classes are explicit. Matched retained-barrier occupancy and ownership
gauges agree across sizes; transient peak gauges remain within one common cap;
cleanup gauges return to zero or one fixed baseline; cumulative work such as
records visited, bytes streamed, and pages consumed matches its per-fixture
oracle and is never required to be equal across sizes.

Small boundary fixtures for limit, limit-plus-one, multi-page, branch,
cancellation, replacement, and cleanup are the merge-blocking upstream suite.
M1 and M2 additionally run the four full-scale fixtures, including exact-stream
backpressure, cold streaming import or rebuild, slow consumers, and resource
cleanup. A deterministic online staircase appends and compacts increasing
entry counts under one fixed active context and verifies that live gauges
plateau at their caps and return to their lifecycle baseline.

Strict mode must reject implicit whole-history materialization before hydration
or allocation. Review fixtures deliberately introduce representative forbidden
roots, including an unbounded per-entry metadata collection whose RSS effect is
below the packaged tolerance; such a change must invalidate the inventory even
if ordinary counters and RSS stay green. These mutations validate named review
and enforcement paths, not a generic ability to discover arbitrary hidden
allocations.

Gauge conformance is necessary evidence. It neither establishes inventory
completeness nor proves asymptotic behavior by itself.

Four-scale deterministic conformance completes in fresh processes before any
RSS endpoint starts. Those children may run exact scans, searches, forks,
exports, imports, and rebuilds only through their declared bounded readers,
projectors, spools, cancellation, and backpressure. They close all resources
and exit before RSS preflight.

An RSS-bearing child performs only the frozen normal open/resume/continue
workload. It verifies `rss_normal` rows produced by normal bounded execution,
the passing deterministic-bundle hash, and retained gauges marked
`history_invariant`. The retained barrier leaves that session open and ready for
the next interaction. Before sampling it performs no fixture or reference-oracle
construction, exact scan, complete-tree traversal, full-history search, fork,
export, import, rebuild, close, replacement, or restart.

### Evidence stages

- **B1 classic baseline** pins and inspects one exact unmodified upstream
  coding-agent snapshot with an empty extension manifest. Source evidence and
  one low/high diagnostic record the classic eager-retention cause and retained
  entry counts. B1 does not qualify the strict product or production harness.
- **M1 local qualification** reviews the closed history-dataflow inventory, runs
  deterministic conformance, and applies the packaged RSS check to one realized
  local Nix package: the actual Pi wrapper, complete certified gallery, faux
  provider, and fixed normal workload.
- **M2 final-package qualification** compares the activation-eligible package
  with a passing M1 and names that M1 bundle. It may reuse M1 only when the
  complete ordinary result manifest matches: protocol revision, product commit
  and source tree, derivation, store path and output NAR, runtime, wrapper,
  gallery, history-dataflow inventory, seeded product configuration and budgets,
  fixture/prepared stores, oracle schema and expected manifest,
  deterministic suite, evidence-tool limits, deterministic/RSS phase rules,
  harness and state schema/seed, faux-provider and isolation identities, runtime
  adapter source and executable hashes, platform API/unit schema, process
  topology, host, OS, normalized command template, and normalized non-secret
  environment manifest. Otherwise M2 reruns the complete M1 gate on the final
  package without changing its rules or threshold.

The wrapper workload already exercises core, terminal, and gallery integration;
there are no duplicate core/gallery/wrapper RSS lanes. A materially different
shipped process topology requires its own inventory review and qualification.

### Packaged RSS integration check

Use the 16 MiB and 1 GiB endpoints in two adjacent order-balanced pairs: one
low-then-high and one high-then-low. Every endpoint uses a fresh process set,
fresh disposable prepared store, and fresh private mutable-state root. The
content-addressed harness manifest freezes quiescence, sample cadence, RSS
source, aggregation, copy policy, and the within-process summary before M1. The
summary is the median of every scheduled post-barrier sample; no scheduled
sample may be omitted or selectively replaced.
One RSS attempt is the complete four-endpoint `L,H,H,L` sequence. An invalid
attempt may be repeated only as a new immutable bundle beginning again at the
first endpoint; no endpoint or pair is replaced in place.

Let `L_i` and `H_i` be the raw candidate-process-set RSS summaries for pair
`i`. Both pairs must complete and satisfy:

```text
abs(H_i - L_i) <= 32 MiB
```

There are no adjusted subtractions, reserves, outlier deletion, or replacement
cells. Heap, external, array-buffer, `maxRSS`, and PSS values are diagnostics.
The 32 MiB threshold is a predeclared material-regression tolerance: it can
catch material uninstrumented, native, or helper retention over the tested
range, but cannot rule out a smaller proportional term or behavior outside the
exact build and environment. It is not the architectural proof.

Freeze the actual product process topology for the complete workload, not only
the retained barrier. A single-process product starts no candidate child at any
point. If a shipped topology needs helpers, the containment adapter owns and
records every declared transient and retained member from launch through
cleanup, including detachment or reparenting. Simultaneous retained samples sum
the stable expected member set. A missing, unexpected, reused, or unaccounted
member makes the attempt `invalid`; the adapter passes helper-aggregation and
membership-change controls. Do not build multiprocess containment for a
topology that does not use it.

Run one cold import or rebuild per fixture size and report peak, latency, I/O,
canonical and derived disk bytes, and temporary-disk use separately. Cold cost
cannot excuse a warm-retention failure.

### Harness identity and isolation

The H1 harness gives every endpoint a unique, previously unused, closed-world
mode-0700 mutable namespace covering home, Pi and XDG roots, temporary and
working directories, the disposable store, and extension, cache, database,
journal, lock, socket, service, and helper state. The candidate and descendants
inherit enforcement before product code runs. Outside it they may read only a
content-hashed immutable allowlist; candidate-owned mutable access or attachment
to an ambient service is denied or detected. Bounded violation evidence,
prelaunch and cleanup checks, and a poison test prove that ambient and prior-run
sentinels remain unread and unchanged. An observed breach by the candidate, a
candidate helper, or a candidate-owned provider is a `product-failure`; lost
enforcement or observation evidence, or an isolation failure in a harness-owned
provider, is `invalid`.

The faux provider starts anew for every endpoint with a fresh root, endpoint,
request log, response cursor, queues, and counters. If candidate-owned, it is in
the process set and RSS sum. If harness-owned, it is outside that set but has no
retained request payload, response queue, or cursor at the retained barrier.
The result records provider ownership and reset evidence.

The harness manifest content-addresses the runner, analyzer, oracle and
deterministic suite, evidence-tool limits, seeded product configuration, copy
and state schemas, allowlist, isolation and faux-provider behavior, sampling
and summary, runtime collection, process containment, and host-condition adapter.
The reviewed platform manifest
fixes the exact API, unit, conversion, cadence, and threshold for RSS,
process-start identity, monotonic time, CPU, swap, power, thermal state, memory
pressure, suspend, and disk space; there is no fallback substitution. Those
mechanics belong to H1, not this architecture contract.

The harness manifest defines one versioned normalization for command and
non-secret environment identity. It maps only freshly allocated endpoint paths,
socket addresses, ports, provider roots, and endpoint identifiers to declared
role tokens; executable and argument identity, variable names, non-volatile
values, presence or omission, and ordering semantics remain exact. The result
records both the normalized identity and every concrete per-endpoint value as
evidence.

Host monitoring brackets the complete low/high pair from preflight through
postflight and cleanup. A missing trace, identity drift, adapter error, or
proven ambient host event makes the attempt `invalid`. Resource exhaustion or
pressure caused by the candidate remains a `product-failure`; it cannot be
reclassified merely because the host monitor observed it.

Table-driven analyzer tests cover both signs at and just beyond 32 MiB, units,
pair order, missing/duplicate cells, and invalid/product-failure outcomes. H1
also tests namespace poison, an injected ambient host event, a candidate-caused
resource event, missing postflight, and any topology relevant to the shipped
product. A2 owns strict-capability poison tests.

### Evidence custody and reruns

Each immutable result bundle records ordinary content identities: protocol;
product commit/source tree, Nix derivation, store path, and NAR; gallery,
history-dataflow inventory, seeded product configuration, and budgets;
fixture/prepared stores, oracle schema,
expected manifest, and deterministic suite; evidence-tool limits; harness,
state schema/seed, allowlist, isolation adapter, and provider; runtime adapters,
their source and executable hashes, Darwin API/unit schema, process topology,
host/OS, normalized command and non-secret environment identities, concrete
per-endpoint command and environment evidence, raw records, analyzer output, and
artifact hashes. Existing Git signatures, Nix identities, and SHA-256 hashes
are sufficient; there is no
second custom campaign identifier or transparency log.

After subject and harness identity freeze, every qualification workload
invocation, including a pilot, control, deterministic child, cold diagnostic,
or RSS attempt, creates an immutable bundle with a `pass`, `product-failure`, or
`invalid` outcome and the evidence available at that lifecycle point. One RSS
attempt is all four endpoints. An invalid RSS attempt may be rerun only in a new
named bundle beginning at endpoint one after correction. An invalid pilot,
control, deterministic child, or cold diagnostic may be rerun only in a new
named bundle that repeats its complete prescribed invocation from the first
step. Every earlier bundle remains.

A product failure remains blocking until a changed, reviewed product passes.
It may be reclassified as `invalid` only when retained raw evidence establishes
one specific harness or protocol defect and the corrected identity is recorded;
an unexplained disposition or a later unchanged-product pass cannot erase it.
Only `pass` qualifies M1 or M2. Obr records bundle references, hashes, outcomes,
dispositions, and next actions rather than raw per-process events.

This is reproducible engineering evidence under retained signed project
history, not adversarial non-equivocation. Local Git and files cannot prove that
an operator did not delete another local bundle or invoke the candidate out of
band, and the programme makes no such claim.

## Evidence ledger

This ledger distinguishes source identity, historical prototype evidence, and
future evidence governed by this contract.

| Evidence | Identity and result | Standing under this contract |
| --- | --- | --- |
| Programme baseline | Signed Nix `b3263de3d700ab0650fb9cceadd6586fd1126f1a`; Pi v0.83 source pin `845d6ff1f6643aba440341cce877ce1c43ebbc39`. | Establishes the local source and package baseline only. |
| Upstream inspection | Live GitHub metadata placed `earendil-works/pi` main at `534bcbffb7e1e7551d9ee3572dfeb278e203e493` on 2026-08-11. Line-level inspection used the locally retained, catalog-pinned v0.83 source `845d6ff1f6643aba440341cce877ce1c43ebbc39`. Local research notes point to upstream [issue `#7937`](https://github.com/earendil-works/pi/issues/7937) for unfinished v4 work; this inventory did not recover and freeze the issue body or comments. | Establishes the remote identity observed at that dated checkpoint separately from the exact inspected source. The issue pointer is coordination context, not source evidence or maintainer approval. This row does not establish an evergreen current identity, bind v0.83 line evidence to the observed main commit, or prove that a planned `SessionTree` interface exists. |
| B1 exact-upstream classic freeze | Signed Nix commits `3cba940ee521e9f3ae8c67d812c19a951982be9b` and `251e1d3bec72ba682aa20022360fbca98897b93d`; upstream commit `2e4d23959485279aa2da1a45103de2ea22d46395`; `pi-coding-agent` 0.84.1; package output `/nix/store/98ldilyr7g34lg78nvn5470zxaqih3zy-pi-classic-core-source-0.84.1`; output NAR SHA-256 `sha256-jeZIFwg+NqhCn3spHAQJ9SfV24+UK5mMnZdbAi6Gfqs=`. | Establishes the exact unmodified classic subject and its eager `fileEntries`/`byId` causal path for B1. It is source evidence only; no fixture or diagnostic result is implied. |
| B1 classic fixture and descriptive diagnostic | Deterministic fixture output `/nix/store/zan7ir6jx415h85my3w07vla2mzvksyw-pi-classic-core-fixtures-v1`, NAR SHA-256 `sha256-dYiqyYnzpKCTbGiA0PxhgLFZiL4SOahV+lyCDvvT0YY=`, and `SHA256SUMS` SHA-256 `b5aed7c3c4b75d2699fa8e0c68fb6a8c063bcfed61c0e0969ed54feb2a7a19f8`; its 16 MiB through 1 GiB fixtures contain 526, 2,062, 8,206, and 32,782 non-header entries. Immutable diagnostic `/nix/store/cp9sqkmswmxab9aa4hwdj4zz6d4hxvx0-pi-b1-classic-core-attempt-0001`, NAR SHA-256 `sha256-MRZ2TES55znZo53uNKXCS/kaMXja5DgxN960GLFIRA0=`, bundle `SHA256SUMS` SHA-256 `72a4c763417686ad0fd971f17d3009848e4f1b9e24aff1cb2dc635dd1526b9cd`, and summary SHA-256 `b0bcac2601b5b949510a66fe534e99be97ea6c8c1f355c090d601373d5d1599d`. The 16 MiB endpoint records raw RSS 103,481,344 bytes and `maxRSS` 116,932,608 bytes; the 1 GiB endpoint records 1,275,248,640 and 1,361,608,704 bytes. Retained `fileEntries` before continuation increase from 527 to 32,783 and `byId` from 526 to 32,782. | Complete B1 descriptive evidence. Both endpoint, postflight, common-identity, semantic, raw-unit, and empty-extension checks pass. The result establishes history-sized retention in the exact unmodified classic core; it does not qualify M1 or M2 and is not an adjusted-RSS verdict. |
| Maintained fork implementation | Signed Pi commit `4a2f3374c` on maintained fork lineage `c3d353aa3`; descended from signed Nix prototype `e2c002e06cc4378b5a55cc1659e99caaab408dcb` and retired patch SHA-256 `4bdb9524839764bf9639740be782e0719168d885332e5cf2b70da16c95f7494a`. | Supplies the maintained implementation and regression corpus. Its presence alone does not qualify M1 or M2. |
| One-gibibyte synthetic run | The public acceptance discussion on [GitHub issue `#128`](https://github.com/jwiegley/nix-config/issues/128#issuecomment-5229843110) names signed acceptance candidate `e44cb99c53ba1f2ae67e9714aff8bbad93243740` and reports `historyBytes=1,074,007,601`, 1,024 messages, 64 compactions, `maxRss=250,085,376`, and adjusted growth `40,501,246` bytes. Independently, signed Nix commit [`ce802467fecd488b8b835da6cc48f7f804797ce5`](https://github.com/jwiegley/nix-config/blob/ce802467fecd488b8b835da6cc48f7f804797ce5/doc/CLEANUP-WIGGUM-HANDOFF.md#L225-L249), `doc/CLEANUP-WIGGUM-HANDOFF.md` blob `20d9a687b9d619b09129f187bdd88481e28d7f77`, records prototype base `e2c002e0`, the same history size and compaction count, and adjusted growth `40,402,944` bytes. | Historical single-scale evidence with an unresolved 98,302-byte reporting conflict. Local Git does not establish whether the values describe different runs, a correction, or transcription drift. The absent raw bundle prevents independent run-to-commit reconstruction; neither adjusted value nor the unrepeated run satisfies the paired endpoint product gate. |
| Eight-hour synthetic run | The same signed [historical checkpoint](https://github.com/jwiegley/nix-config/blob/ce802467fecd488b8b835da6cc48f7f804797ce5/doc/CLEANUP-WIGGUM-HANDOFF.md#L278-L328) records exit 0; `durationMs=28,800,471`; 26,893 messages; 1,681 compactions; `historyBytes=888,276,251`; first/last adjusted-RSS medians `92,307,020` and `94,355,018`; adjusted growth `2,047,998` bytes; and private evidence-manifest SHA-256 `c30f01808c30701d3d66195c72ee7e821d934c4ca00f615cefd7ab0f75cc3aca`. | The computational duration and adjusted-growth criterion was reported as passed. The auxiliary retained-path/provenance checker remained incomplete because it compared macOS `/var` with the equivalent `/private/var` spelling. The private artifact is not reproduced by this repository, and adjusted RSS is not the paired endpoint verdict defined here. |
| Manual soak procedure | Signed commit [`e44cb99c53ba1f2ae67e9714aff8bbad93243740`](https://github.com/jwiegley/nix-config/blob/e44cb99c53ba1f2ae67e9714aff8bbad93243740/doc/PI-EIGHT-HOUR-SOAK.md), `doc/PI-EIGHT-HOUR-SOAK.md` blob `23ce98c3d16a0481ac7ed9851adf22b22ca6fcec`, SHA-256 `54775179da5dee325330d4c47ac74e9d780c9d7fb2acec7c21b5fe6a9196d537`. | Preserves the final incomplete-checker disposition and reproducible optional procedure; another soak is not a pending acceptance gate. |

The historical numerical results above derive from the linked public acceptance
discussion and the exact signed Git objects named in the ledger. They are
retained as attributed provenance, not silently collapsed into one run or
promoted to stronger evidence.
The raw one-gibibyte result stream and the sealed eight-hour artifact bundle are
not present in this repository and were not available for rehashing during this
inventory. Their numerical values therefore remain attributed historical
measurements rather than independently reproduced results.

Current stage status, result-bundle references, verdicts, dispositions, and next
actions live only in obr. This document retains the invariant, protocol, and
immutable historical evidence; it is not a second continuation ledger.

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
- the maintained fork implementation, an optional soak, or one focused test proves
  the final packaged-runtime claim.

## Change control and completion evidence

The signed committed revision of this document is the protocol authority for
issues `nix-tcz.37.1.2`, `.20`, `.21`, `.30`, and `.31`. Product qualification
begins only after the history-dataflow inventory, operation-to-oracle manifest,
deterministic tests, evidence-tool budgets, isolated harness, analyzer, and
platform manifest have been independently reviewed. A material change to the
invariant, fixture endpoints, oracle schema or expected values,
deterministic/RSS phase rule, evidence-tool limit, mutable-state or provider
semantics, adapter API or unit, host predicate/cadence, paired order, outcome
rule, or 32 MiB threshold creates a new protocol revision. Product, budget,
inventory, gallery, harness binary, platform, or host changes create a new
qualification identity and may require a new M1 or M2 under the rules above.
Old and new results remain separate and named.

Final programme acceptance requires the complete semantic, lifecycle,
deterministic-budget, paired-RSS, managed-extension, and packaged-runtime
gates, together with removal of product-scale downstream Pi patches. This
document supplies the contract and ledger. It does not claim that those later
gates have run.
