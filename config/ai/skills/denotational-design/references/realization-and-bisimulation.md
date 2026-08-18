# Realization testing and cross-language bisimulation

Phases 9–10. Realizations of the solved operation definitions — fast
kernels, emitters, schedulers, optimized data structures, foreign-language
implementations — are deliberately outside the proof kernel. The meaning
and the commuting statements fix *exactly what their tests must test*;
acceptance is empirical, on criteria committed in advance.

## Acceptance cards (commit before the work)

For every empirically accepted realization, commit an acceptance card
*before* the realization lands:

- the **reference oracle** (which meaning function / executable spec /
  external reference decides correctness) — never movable once declared;
- the **criteria and thresholds** (correctness bounds, efficiency budgets,
  runtime-behavior requirements), each with a recorded derivation —
  threshold constants without derivations become indefensible folklore;
- the **rungs**: an ordered ladder of evidence gates (e.g. small-input
  exactness → property sweep → full-scale comparison → sustained-load
  behavior), each fail-closed, none skippable by a later rung;
- a **semantics-unchanged-by list** so a performance change is refused when
  a cited semantic gate goes red — speed may never go green while
  correctness goes red.

Enforce monotone tightening with a merge-base diff check: `at_most` bounds
only fall, `at_least` only rise, exact values never move, criteria and
rungs are add-only. "You cannot re-baseline by editing the card." A gate is
never weakened to land a step; a step that cannot be certified without
breaking an always-green invariant is a redesign.

## Evidence discipline

- **Every empirical gate is a sampled square.** An artifact counts only if
  it names: the square it samples (which levels, which operation), the full
  **comparison tuple** (every input that fixes the point being compared —
  versions, configs, seeds, precisions, the capture code's own identity),
  the sample, the comparator with its tolerance *named*, and a durable
  verdict. "Absence of output is never silent success."
- **Tuple mismatch voids, never weakens.** Two artifacts are comparable iff
  their tuples denote the same point; the expensive part of adjudication is
  the identity proof. Goldens are tuple-pinned caches, not truth.
- **Claim ceilings are schema-fixed at capture time.** Map each evidence
  kind to its maximum defensible claim (unit fixture → per-operation
  evidence, never promotable to a system rung; self-comparison → regression
  only, never correctness; diagnostic localization → routing only). No
  field, producer, or citation can request promotion. Structural gaps in
  coverage are recorded as sampling limits "to be lifted by engineering,
  not by reclassification."
- **Divergence is classified, not absorbed.** Pre-freeze the outcome
  classes for a divergent comparison (e.g. matches-oracle /
  matches-reference-only / matches-neither / …); a divergent row lands in
  exactly one class as per-row evidence. Classification is never a
  threshold change.
- **Every detector ships both fixtures.** A true-positive (it fires on the
  planted defect) and a false-positive control (it stays quiet on the
  legitimate case) — a detector with only the first drifts into blocking
  and gets weakened by whoever it first blocks. Fail-closed paths prove
  their failure with a fixture; vacuity is itself a failure.
- Measure performance at the **representation level only**, under a fixed
  meaning (representation swaps have yielded 2,000–230,000×; that is the
  legitimate lever).

## Cross-language bisimulation (e.g. Rust against a Lean oracle)

The governing move: give the foreign realization **its own meaning function
into the same mathematical object**, and test each realization against that
shared target. Bisimilarity comes from the shared meaning — never from
diffing two implementations, and never from structural resemblance.

**The oracle doctrine.** Exactly one implementation is the *fresh semantic
oracle* (normally the prover-side executable spec, or a pinned external
reference the meaning quarantines Elliott-style). Every other
implementation — including yesterday's build of the system under test — is
comparison or regression evidence only. Self-bisimulation (system vs its
own earlier output) detects change, never correctness. Never let the system
under test author the expectation it is tested against.

**Strategy menu** (compose as the project's scale demands):

1. **Golden vectors from the prover.** Export input/output corpora from the
   executable spec with the comparison tuple embedded (spec version, seed,
   precision policy) plus content digests. The foreign side replays and
   compares. Regenerate — never hand-edit — and treat capture-code identity
   as part of the tuple, so freshness is a re-run obligation.
2. **Morphism equations as property tests.** Each commuting equation
   becomes a generator-plus-assert test on the foreign side: apply the
   operation, apply the (foreign) meaning function, compare against the
   model operation on mapped arguments. Then delete direct law tests as
   redundant corollaries. Include partial/edge values — a morphism can hold
   on total values and fail at boundaries (NaN, overflow, ⊥-analogues).
3. **Differential drivers.** One harness runs both sides on the same
   generated program/input stream and compares at every declared
   observation point, not only at the end. Where the levels are staged
   (compiler-like), compare per stage.
4. **Stage-ladder localization.** When an end-to-end comparison diverges,
   run the tower as an ordered stage ladder — oracle leg first, then each
   intermediate representation, then the executor — computing
   `first_failing_stage` and `next_owner` (one owner per stage, one owner
   map, kept in the instrument itself). Localization is *diagnostic only*:
   naming a first failing stage classifies nothing, adjudicates nothing,
   and never upgrades into semantic evidence by citation — guard the
   citation. A ladder invocation that produces no artifact is a failure,
   never a silent pass.
5. **Schema-level lockstep.** Where the two languages share serialized
   artifacts, mirror the accept *and reject* fixtures on both sides: an
   artifact accepted by one validator and rejected by the other is a
   failing test, not a discovery; bind schema versions with a lockstep
   test.
6. **Refl-by-construction (the strongest form).** Where feasible, make the
   published comparison matrix a theorem in the prover (each row a `refl`),
   built compositionally — then the foreign side needs only to match the
   theorem's exported table.
7. **FFI probes.** Where the foreign realization links against the prover's
   compiled spec, drive both through one FFI harness on shared memory
   layouts, with layout asserts on both sides pinned to a single declared
   contract.

**Idiom rule.** Do not transliterate the prover's abstractions into the
host. Retain the denotation and the morphism obligations (both
language-independent) and express them idiomatically — traits and property
tests in Rust, not an emulated Applicative through three layers of
generics. The representation stays private; a review rule that any external
mention of the representation is a defect substitutes for the module
system's enforcement where needed.

## Efficiency discipline, restated for realizations

Hold the meaning fixed and rebuild the representation, on the record, with
reasons. Reject any speed-up that would move a denotation ("a speed-up that
changes any square's meaning is not an optimization but a semantics
change") — a legitimate behavioral option enters as a distinct policy
object at a named level, never as an environment flag or a runtime
fallback branch. Sanctioned fallback is a different plan selected *above*
the runtime, not a branch below it. Validator and executor must decide the
same predicate — accepting what the executor rejects is a defect class of
its own.
