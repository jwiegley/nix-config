# The dialog protocol

Run the ten phases below as a structured conversation. Where the harness
provides a question/answer interface (e.g. AskUserQuestion), use it for
forced choices; use prose for open exploration. Ask few questions per
message. Each phase names its questions, its artifact, and its exit test —
do not advance without the artifact. Record every answer in the worksheet
as it lands.

Before phase 1, settle two framing points with the user:

- **Prover**: Lean 4 (default), Rocq, or Agda — see `provers.md` for the
  trade-offs to present. Also whether a final foreign-language realization
  (Rust, C++, …) is planned, since that decides whether phase 10 exists.
- **Greenfield or retrofit**: for an existing codebase, the opening move
  differs — first write down the denotation the code *already implicitly
  has, defects included* (expect it to be ugly; the ugliness is the
  evidence), then run the phases against it. Retrofit one type, not the
  system, and measure success in deletions.

## Phase 1 — The principal mathematical object

Refuse the user's first instinct, which is an API sketch. Ask instead:

- "In the domain's own words — no types, no code — what *is* the thing this
  system is about? Write the sentence." (What is, not what does.)
- "Enumerate every candidate notion of that thing. For each: what
  technology of production, storage, transport, or display does it smuggle
  in?" Then subtract all of it — grids, sample rates, frames, bit depths,
  bounds, tapes, indices, mutable accumulators, matrices, finiteness,
  discreteness.
- "A `T` is a representation of *what mathematical object*?" Demand an
  object, not a layout. Ask "what object?" strictly before "a function of
  what?" — inventing a spurious index (a "key", a "time", a "context") for
  something indexed by nothing is the method's named worst failure mode.
  Legitimate non-arrow answers: a monoid element chosen for its
  bias/ordering, a semiring element whose arithmetic is the domain's
  operations, a lattice element, a type paired with an invariant, a value
  paired with a rate, a representable functor.
- Generalize where generality is free (range first, then domain:
  `Bool → semiring`, `Colour → any range`, recognition → parsing) and make
  the user list what came free — if nothing came free, the generalization
  was cosmetic. Stop stripping at adequacy: the model must still answer
  every question the domain asks ("removing inessentials may have no
  ultimate stopping place short of oblivion").

**Artifact**: one line — the object's name, shape, and definition, in a
semantic domain whose mathematics already exists (functions, monoids,
semirings, linear maps, Set, CPOs), plus the list of subtractions with the
level at which each removed thing will reappear as a *representation*.

**Exit tests**: (a) the definition fits on a line and may be
non-computable; (b) the **identity test** — the domain's most primitive
observation denotes `id` (e.g. `at time = id`); if it does not, the object
is still an encoding, keep subtracting; (c) the user can say what a value
*is* without mentioning any representation.

## Phase 2 — The fundamental operations

- "Which operations are *forced* by the object's structure, and which by a
  documented user need?" Everything else waits for phase 4.
- Match the shape of `⟦T⟧` against the class repertoire
  (`denotational-method.md` §repertoires) and demand the standard classes
  one at a time — which ones fail is diagnostic. Prefer the weakest class
  that suffices; factor hierarchies finely; uncurry to demand less of
  supporting structures.
- Before naming any new operation, ask whether it is an old one: delete
  every bespoke name a standard class supplies (`constant` ⇒ `pure`,
  `unionWith` ⇒ `liftA2`, a `lift_n` family ⇒ one missing abstraction).
- Put semantic choices (bias, direction, which monoid) into visible wrapper
  types in the semantic domain (`First`, `Max`, `Sum`) — never into a
  hand-written instance or a comment.

**Artifact**: the operation set, each operation either a class method or
carrying a one-line justification for its bespoke existence; the class list
the type inhabits.

**Exit test**: no bespoke name remains where a standard class supplies one,
and each class choice names why the weaker alternative does not suffice or
why this is the weakest that does.

## Phase 3 — The fundamental theorems (on the object AND the operations)

- "What must always hold of this object under these operations?" State each
  as an equation with a **downstream force** clause: what it obliges lower
  levels to do.
- Anchor every law to a real defect it would make unrepresentable — a law
  with no defect lineage is decoration. For a retrofit, mine the bug
  tracker for the lineage.
- Write the explicit **non-theorems list**: the plausible-but-false
  properties (no exchangeability, no continuity, no compositionality of X
  over Y), so nobody assumes the convenient converse.
- Assign law IDs from single-letter families, one home file per family
  (`governance.md`); renames are decision-register entries. Avoid reusing a
  letter across families.

**Artifact**: the law table (ID | statement | downstream force | defect
lineage) plus the non-theorems list.

**Exit test**: laws are lemmas-to-be from a denotation, not axioms about an
implementation — "using algebraic properties as specification rather than
as lemmas that follow from a denotational specification" is the diagnostic
for a skipped denotation.

## Phase 4 — Derived operations and theorems

- Explore what the algebra gives for free: which literatures attach through
  the chosen classes; which meta-theorems collapse obligations (if the
  numeric/monoid operations are defined via `pure`/`fmap`/`liftA2`, then
  Functor + Applicative morphism-hood implies the rest).
- Run "recognize, then delete" again over everything invented in phase 2–3.
- Let the composition rule dictate interface shape (extra outputs, argument
  order), not convention.

**Artifact**: the derived-layer notes — what came free, which obligations
collapsed, which dilemmas dissolved (run both and race; eliminate the
construct that forced the choice).

## Phase 5 — Candidate representation objects (the tower)

- "What is the ordered sequence of representations, from the mathematical
  object down to the final realization?" One level per concern; each level
  strictly more operational than the one above.
- Build the **level table**: Level | Object | Carrier | Exactness of its
  semantics. Decide the equality relation *per leg* (exact where math
  permits; bounded-and-measured where finite precision enters; bit-exact
  relative to a declared policy at the bottom) and defend the split as
  principled.
- Define each level boundary **negatively** as well as positively:
  "nothing above level k may mention floats, devices, or time"; "nothing
  below level j may introduce a user-visible knob." The negative clauses
  are what convert a violation into a diagnosable spec defect. Cite, where
  possible, the existing violation each clause outlaws.

**Artifact**: the level table plus the negative boundary clauses.

**Exit test**: every subtraction recorded in phase 1 reappears at exactly
one named level.

## Phase 6 — Denotations between representations

- Give each level k a *named* meaning function into level k−1
  (`at`, `occs`, `pred`, `force`, `value_at` — naming it is much of the
  work), compositional, and let it be uncomputable.
- Write the one-line end-to-end statement first — `⟦running system⟧ ≡
  ⟦mathematical object⟧` at the named equalities — and treat everything
  below as bookkeeping that makes that one line checkable in pieces.
- Define semantic equality per level: `a ≡ b ⟺ ⟦a⟧ ≡ ⟦b⟧`, and keep each
  representation abstract.
- Check invertibility at each level: where `⟦·⟧` is invertible, all
  semantic choice disappears and instances can be synthesized mechanically.
- In a dependently typed host, consider **indexing the representation by
  its denotation** (`data Repr : Meaning → Type`) so nothing of the wrong
  meaning is constructible and the decision procedure's type *is* the
  correctness statement.

**Artifact**: per level, the named meaning function's signature and
definition; the composed end-to-end statement.

## Phase 7 — Typed operations per representation

- For each level and each operation: write the homomorphism equation, then
  **solve** it with the four-step loop (`denotational-method.md` §solving):
  simplify both sides independently with named justifications; strengthen
  by generalizing away from the specialized shape (the step newcomers
  omit); adopt the solved form as the definition. Expect many equations to
  arrive already solved.
- When the denotation is not inspectable (functions are black boxes), add a
  second reified layer with its own meaning function and re-run the
  identical calculation — the composition of homomorphisms is a
  homomorphism, so the composite is free.
- When an equation will not close, use the failure-diagnosis table — the
  repair is a design finding, never a weakened spec.

**Artifact**: per level, the operation definitions, each traceable to the
equation that forced it (keep the derivations — they are the proofs'
skeletons).

**Exit test**: no operation was written first and checked second.

## Phase 8 — Commuting theorems: statements and proofs

- State one commuting square per adjacent-level operation pair; the
  square's statement is kernel (human-reviewed); its *proof* is
  checker-validated (the proof assistant), never human-reviewed.
- Recognize the square as the standard comma-category construction:
  correctness composes, so sequential composition's correctness follows
  from functoriality, parallel composition's from monoidal functoriality,
  and primitives reduce to `refl`. Where the prover permits, discharge law
  families wholesale by a functor into an already-lawful category.
- Build the **obligation ledger**: Law | Home | Placement (Proof / Contract
  / Test) | Status. Exact legs trend to proofs, artifact legs to
  fail-closed contracts, runtime legs to proof-shaped tests; drift against
  a column is a placement defect. Run counterexample search before proof so
  false laws die cheaply.
- Fix the **axiom policy**: the short, public, versioned list of seams
  where the mathematics is allowed to end, with what empirically covers
  each gap. Refuse to claim theorems the substrate cannot support.

**Artifact**: the square statements in the prover; the obligation ledger;
the axiom policy.

**Exit test**: every needed observation factors through the denotations;
no junk states are representable (or the junk is named); an implementation
change that cannot state its denotation is not reviewable.

## Phase 9 — Empirical tests of realization quality

Realizations of the phase-7 definitions — fast kernels, emitters,
schedulers, optimizations — are deliberately outside the proof kernel.
Design their acceptance per `realization-and-bisimulation.md`:

- Commit an **acceptance card before the work**: reference oracle,
  criteria, thresholds, rungs, and what the change must leave semantically
  unchanged. Thresholds may only tighten; the reference oracle never moves;
  a performance-only card requires a semantic anchor so speed cannot go
  green while correctness goes red.
- Interpret every empirical gate as a **sampled square** (which levels,
  which operation, which sample), with the full comparison tuple pinned.
- Declare evidence ceilings; classify divergences into pre-frozen classes
  rather than widening tolerances.

**Artifact**: acceptance cards; the evidence-ceiling table; gate ladder.

## Phase 10 — Cross-language realization fidelity

When the final realization lives in another language (Rust, C++, …) while
the meaning and proofs live in the prover:

- Give the foreign realization **its own meaning function into the same
  mathematical object** — bisimilarity comes from the shared target, never
  from diffing implementations.
- Choose strategies from `realization-and-bisimulation.md`: golden-vector
  corpora exported from the prover, differential drivers, morphism
  equations as property-based tests, FFI-level probes, a
  stage-ladder localizer computing `first_failing_stage` and `next_owner`,
  and the single-oracle doctrine (exactly one fresh semantic oracle; other
  implementations are comparison evidence only).
- Do not transliterate the prover's notation — express the denotation and
  the morphism obligations in the host language's idiom.

**Artifact**: the bisimulation test plan with its oracle doctrine and
localization ladder.

## Closing every engagement

Run the four completion tests: every type's meaning stated in one line;
every operation's meaning forced by a written morphism equation with no
bespoke names remaining; nothing left to prove (laws hold by morphism, the
types are abstract, remaining proofs are lemmas from the denotation);
efficiency lives elsewhere as refinement of an unmoved denotation. Then
the negative test: does the design *morphism-check*, not merely
type-check? Finally, record what resisted: types with no semantic
morphism, unclosed equations, structural evidence ceilings — published as
open problems, never papered over.
