# The dialog protocol

Run the ten phases below as a structured conversation. Where the harness
provides a question/answer interface (e.g. AskUserQuestion), use it for
forced choices; use prose for open exploration. Ask few questions per
message. Each phase names its questions, its artifact, and its exit test —
do not advance without the artifact. Record every answer in the worksheet
as it lands.

Before phase 1, settle three framing points with the user:

- **Prover and formality level**: Lean 4 (default), Rocq, or Agda — see
  `provers.md` for the trade-offs to present. Also whether a final
  foreign-language realization (Rust, C++, …) is planned, since that
  decides whether phase 10 exists. The method is usable informally and
  formally; it is materially better formally, and the formal end is where
  its author now works — but say plainly that an informal engagement gets
  the design discipline without the checker, so the reviewer carries every
  verdict. Invite skepticism explicitly: the method is not to be adopted
  on authority, and the user's objections are the most useful input the
  dialog can receive.
- **Greenfield or retrofit**: for an existing codebase, the opening move
  differs — first write down the denotation the code *already implicitly
  has, defects included* (expect it to be ugly; the ugliness is the
  evidence), then run the phases against it. Retrofit one type, not the
  system. The defect inventory licenses **two** verdicts, not one: fix
  these defects, or *start over* — "this is basically unfixable, thank you
  very much for showing me so clearly the mistakes that were made in the
  past." A retrofit that ends in a documented start-over recommendation
  succeeded; say so rather than forcing a repair. (Success measured in
  deletions applies only to the repair branch.)

## Phase 0 — teach the square (five minutes, once)

Skip when the user already knows the method. Otherwise do not open by
asserting the method; open by making the user fail to state a correctness
criterion:

1. **The correctness-criteria ladder.** Put a plausible implementation
   next to a deliberately wrong one and ask: "what makes your version
   correct and mine not?" Walk the answers down in order — does it parse?
   does it type-check (in *which* language — Haskell? Agda?)? does it pass
   tests? Each fails on its own terms: type checking rejects only "the
   most egregious boneheaded answers… things that are superficially
   obviously wrong", and "testing cannot get to truth; it can only detect
   errors, and worse, only the obvious errors." Only then introduce the
   homomorphism, as the invariant answer: "it's always the same question
   and it's always the same answer."
2. **Name the category error.** The machine holds bit patterns; the domain
   holds numbers, images, distributions — different kinds of things. The
   one-step domain operation becomes three steps (encode, implement,
   interpret), "and those four pieces form the analogy."
3. **Two pre-class examples.** `length : String → ℕ` is a monoid
   homomorphism (length of empty is zero; length of concatenation is the
   sum of lengths). The slide rule is `log`, a homomorphism from the
   multiplicative to the additive monoid — homomorphisms shipped as
   hardware for three centuries because addition was mechanizable and
   multiplication was not.
4. **Build the rectangle verbally.** Top edge: the mathematical function.
   Bottom edge: the implementation. Two vertical edges pointing *up*, from
   representation into meaning. Correct means the two paths agree for
   every input. Only then: "category theory calls that a commuting
   diagram — if you didn't know about categories, hopefully you'd come up
   with that one."
5. **Assign audiences to the edges.** "A user only thinks about the top
   one. The implementation only ever does the bottom one — it doesn't do
   the sides or the top. The correctness is what ties them together."
6. **Warn about the wild card.** The first operation comes out trivially
   because you chose both the carrier and the meaning function to make it
   so — "but I can only play that wild card once." The method starts
   paying at operation two.
7. **Teaching hygiene.** Be honest that worked examples are survivors
   ("luckily it worked out — if it didn't work out I wouldn't have shown
   it to you"). Prove one law, once, to establish that all of them are
   that easy, then stop. De-jargon by etymology plus instances:
   "homomorphism… just means it preserves the shape"; "category is not
   scary, it's a Haskell class, in `Control.Category`" — teach *category
   practice*, not category theory. Expect the math-vs-code notation
   question and pre-empt it typographically (color or font, not only hats
   and brackets); the resemblance is unavoidable and will be asked about
   anyway.

## Phase 1 — The principal mathematical object

Take the user's API sketch — but take it as raw material, explicitly
un-meant. Ask for the type names and the operation signatures, and say out
loud that nobody yet knows what they mean: "we don't yet have to know what
those types mean; this is a process of clarifying our ideas." Refuse only
*how do we implement* — "How is an answer. What is a question. How do we
implement what?" Do not let the sketch harden: every type in it is a
candidate for denotation, unification, or deletion.

**State the scoring rubric before any candidate meaning is offered**: a
mathematical model must be **adequate** (it can express what the domain
and its users need), **simple** (you can reason with it practically and
reliably), and **precise** (so that you really have simplicity and
adequacy rather than only believing you do). Say explicitly what is *not*
a specification goal: minimality/restrictiveness — that is bought later,
in the operation vocabulary and the representation, never by narrowing the
semantic domain first.

**Facilitation** (Elliott's own seminar mechanics):

- Ask for bad answers by name — "I want lots of bad suggestions… every
  suggestion is illuminating, either for its strengths or its weaknesses
  or both." Do not show your own candidate first; if it slips out, say so.
- Collect every candidate without ranking, then price each with precision,
  because "many ideas are simple only because they're not precise. When
  made precise… their complexity becomes apparent."
- Paraphrase each objection back and get confirmation before answering it.
- Park objections that arrive out of order instead of resolving them — an
  objection about implementability cannot be answered before the operation
  set exists ("we're not even ready for that conversation"). Keep the
  parked list visible in the worksheet; some items never resolve, and that
  is a legitimate outcome.
- Expect domain experts to describe their *coping mechanisms*, not the
  essence — "it really is a very unusual expert who understands the
  essence of a question and can distinguish it from their coping
  mechanism." Keep asking different practitioners until one answer makes a
  mathematical pattern light up. This will feel arrogant; it is
  nevertheless the job.

**Openings, by the shape of the domain:**

- Noun-first (default): "In the domain's own words — no types, no code —
  what *is* the thing this system is about?" Then: "A `T` is a
  representation of *what mathematical object*?" Demand an object, not a
  layout. Ask "what object?" strictly before "a function of what?" —
  inventing a spurious index (a "key", a "time", a "context") for
  something indexed by nothing is the method's named worst failure mode.
  Legitimate non-arrow answers: a monoid element chosen for its
  bias/ordering, a semiring element, a lattice element, a type paired with
  an invariant, a value paired with a rate, a representable functor.
- Verb-first, when the domain is named by an operation (differentiate,
  solve, render, schedule): "What *is* this operation, mathematically?
  What does it take and return?" — then chase the codomain until it lands
  on an object whose mathematics already exists ("derivatives are linear
  maps"; the received answer — a number, a vector, a matrix — is usually a
  representation; name the thing it represents).
- The telescope split, for tools, renderers, viewers, query and reporting
  systems: "What is the user trying to *see*, and what is the instrument
  they look through?" Answer the first before the second and do not let
  the second contaminate the first — "I'm trying to invent a telescope for
  something. What is that something? That's the important thing."

**Subtraction and its probes:**

- "Enumerate every candidate notion of the thing. For each: what
  technology of production, storage, transport, or display does it smuggle
  in?" Subtract all of it — grids, sample rates, frames, bit depths,
  bounds, tapes, indices, mutable accumulators, matrices, finiteness,
  discreteness.
- **Index interrogation**: if a model indexed by a discrete type
  (naturals, positions, frames, ticks) makes some domain operation
  clumsy — interpolation, resampling, time-warping, blending — the
  clumsiness is the diagnostic: replace the index with a continuum and
  re-ask which operations became trivial. A lazy list/stream *is* a
  function from the naturals, so "make it functional" is not a fix.
- **Transformability probe**: do you want to *transform* the index domain
  (warp time, transform space, reparameterize)? If yes, it must be
  continuous — index transformation is exactly what a discrete index makes
  awkward.
- **Modularity criterion**, replacing bare "subtract discreteness": prefer
  the model that assumes least about how the consumer will sample.
  Laziness ships infinitely *many* values so you need not guess which
  prefix the caller wants; continuity is the next step — infinitely
  *dense*, "because I don't know where you're going to look." Elliott's
  empirical warning: finite and/or discrete models are *more* complicated
  than infinite continuous ones, and they do not have useful laws.
- **Pre-computer test**: did this problem exist before computers? "We
  shouldn't just use computers to solve computer problems." A notion that
  only makes sense because of the machine is a candidate for further
  subtraction.
- Generalize where generality is free (range first, then domain) and make
  the user list what came free — if nothing came free, the generalization
  was cosmetic. Stop stripping at adequacy — found in practice by
  *overshooting generality and retreating once*, not by aiming at it ("I
  don't know I went too far until I do go too far. Then I back up.").

**Teaching note for resistance**: when a user resists a subtraction —
usually discreteness — do not argue in the abstract. Find the same
subtraction they already accepted in a neighboring dimension and transfer
it: bitmap → outline fonts, raster → vector. Introduce continuity in
*space* first, then note the argument in *time* is identical and only the
resistance differs ("shields don't go up quite so quickly"). Naming the
asymmetry as conditioning, not as a difference in the argument, is what
unsticks the conversation. Full ammunition: `objections.md`.

**Artifact**: one line — the object's name, shape, and definition, in a
semantic domain whose mathematics already exists (functions, monoids,
semirings, linear maps, Set, CPOs — a menu, not a boundary: the criterion
is pre-existing mathematics, and "go learn it" is a passing answer), plus
the candidate board with each candidate's baggage, plus the list of
subtractions with the level at which each removed thing will reappear as a
*representation*.

**Exit tests**: (a) the definition fits on a line and may be
non-computable; (b) the **identity test** — the domain's most primitive
observation denotes `id` (e.g. `at time = id`); this test discriminates
for container-shaped candidates and passes vacuously when the primitive
observation *is* `⟦·⟧` (as with `⟦Image⟧ = Loc → Colour`) — there, rely on
the adequate/simple/precise triad plus the forcing criterion (do the
chosen meaning's operations become nearly forced by type-checking alone?);
(c) the user can say what a value *is* without mentioning any
representation; (d) the **closure test** — the object is built out of
things of its own kind, without bound ("what do you build functions out
of? Other functions… because then you have fewer things"); (e) **reach and
hard-to-vary** (Deutsch) — the model explains more than it was built for,
and no part of it can be changed freely while it still "works".

## Phase 2 — The fundamental operations

- **The model's vocabulary *is* the API, verbatim.** "You take the
  language that the math wants to talk about and you make that your API."
  The user's story and the implementer's obligation list are the same
  list; divergence between them is where abstraction leaks originate.
- Find the operations from how the *argument* values are built, not from
  what users say they want to do: you owe one rule per composition form
  (sequential, parallel, …) plus one base case covering all
  structure-preserving primitives ("every linear function is its own
  derivative"). That enumeration fixes the operation set, the law set,
  and the number of equations phase 7 will owe — all at once. Which
  operations are forced by a documented user need instead? Everything else
  waits for phase 4.
- Match the shape of `⟦T⟧` against the class repertoire
  (`denotational-method.md` §repertoires) and demand the standard classes
  one at a time — which ones fail is diagnostic. **Order the demands by
  kind**: monoid before functor, because "monoids are types, whereas
  functors are type constructors" — a type must be parameterized before
  Functor is a well-kinded question, and the parameterization is itself a
  design finding. Prefer the weakest class that suffices; factor
  hierarchies finely; uncurry to demand less of supporting structures.
- **Do not use algebraic structure as a gravity well.** Elliott, asked
  directly: "let's not worry about the monoidness… think about the
  denotations and try to keep them simple and precise, and then ask, given
  those denotations, are they monoids or not?" On a near miss, prefer
  improving the design so the laws hold over dropping the name — then ask
  "is it actually better, not worse? Did I improve things rather than make
  a sacrifice?" (He labels this his practice, not settled method.)
- **The residue test.** The classes should supply nearly the whole API
  ("implement these 17 or 20 methods, and exactly what they have to
  mean"). What they do *not* supply is the **value added**: one, at most
  two, domain-specific primitives (`scale` for linear maps; `time` for
  behaviors). A large residue means the classes have not been found yet —
  go back to the shape→classes rule.
- Named exemplar for fine factoring: `Arrow` is "a bit sketchy" — many
  otherwise-lawful candidates cannot instantiate it solely because of
  `arr`, which demands every host function embed. Prefer `Category` plus
  separate product/coproduct classes. This is "indict the class, not the
  model" in its most common concrete form.
- Before naming any new operation, ask whether it is an old one: delete
  every bespoke name a standard class supplies (`constant` ⇒ `pure`,
  `unionWith` ⇒ `liftA2`, a `lift_n` family ⇒ one missing abstraction).
  Expect the deletion to be *recognition after the denotation is
  written* — the shape of the written semantic equation is what makes the
  standard instance visible.
- Put semantic choices (bias, direction, which monoid) into visible wrapper
  types in the semantic domain (`First`, `Max`, `Sum`) — never into a
  hand-written instance or a comment.

**Artifact**: the operation set, each operation either a class method or
carrying a one-line justification for its bespoke existence; the class list
the type inhabits.

**Exit test**: no bespoke name remains where a standard class supplies one,
and each class choice names why the weaker alternative does not suffice,
why this is the weakest that does, **or** records the open question — "at
least a semiring; possibly just a monoid; I'm not sure exactly where the
line is" is an acceptable, recorded answer, noted in the non-theorems
list.

## Phase 3 — The fundamental theorems (on the object AND the operations)

- "What must always hold of this object under these operations?" State each
  as an equation with a **downstream force** clause: what it obliges lower
  levels to do.
- **Convert every law-desire into a denotation question.** When a
  participant proposes a law, do not ask for an implementation that
  satisfies it: "let's come up with a *correct* implementation — correct
  meaning consistent with the denotation — and then ask about the
  denotation: are you associative?" Hold the desire loosely — "I would
  allow myself to desire it to be true, but not so strongly [as] to blind
  me to whether it's true… I wouldn't want to say it's associativity or
  die."
- **Log law obligations as debt; never discharge them per instance.** The
  moment instances are written, record their laws as an explicit unpaid
  obligation ("that's a debt we have right now") and retire the whole
  batch at once when the morphism lands. A design that proves
  monoid/functor laws instance-by-instance has skipped the morphism —
  indeed, *needing* to prove an algebraic property at all "is a symptom
  that you are picking away at the surface": properties never yield
  meaning; meaning always yields properties.
- Anchor every law to a real defect it would make unrepresentable — a law
  with no defect lineage is decoration. For a retrofit, mine the bug
  tracker for the lineage.
- Write the explicit **non-theorems list**: the plausible-but-false
  properties (no exchangeability, no continuity, no compositionality of X
  over Y), so nobody assumes the convenient converse.
- Assign law IDs from single-letter families, one home file per family
  (`governance.md`); renames are decision-register entries.

**Artifact**: the law table (ID | statement | downstream force | defect
lineage) plus the non-theorems list.

**Exit test**: laws are lemmas-to-be from a denotation, not axioms about an
implementation — "using algebraic properties as specification rather than
as lemmas that follow from a denotational specification" is the diagnostic
for a skipped denotation (Kepler vs Newton: see the method file).

## Phase 4 — Derived operations and theorems

- Explore what the algebra gives for free: which literatures attach through
  the chosen classes; which meta-theorems collapse obligations (if the
  numeric/monoid operations are defined via `pure`/`fmap`/`liftA2`, then
  Functor + Applicative morphism-hood implies the rest).
- Ask also what the model made *impossible* rather than merely cheap: a
  dense index domain deletes interleaving nondeterminism outright
  ("there's no room to interleave anything, and for the same reason it's
  deterministic"). An eliminated concern is a stronger result than a
  managed one; record it here.
- **Post-solving generalization**: inspect the *solved* code for the
  minimal structure it actually consumed ("the only operations needed for
  the category instance is that linear maps is a category"), promote that
  to a parameter, and enumerate the unexpected instances it admits —
  incremental computation, interval analysis, SMT, hardware.
- **Interpretations compose; you are not choosing one.** Unwrapping a
  derived representation yields an ordinary value of the level above,
  which re-enters the pipeline — the differentiable-function
  interpretation followed by the graph interpretation draws the
  derivative.
- Run "recognize, then delete" again over everything invented in phase 2–3.
- Let the composition rule dictate interface shape (extra outputs, argument
  order), not convention.

**Artifact**: the derived-layer notes — what came free, what became
impossible, which obligations collapsed, which dilemmas dissolved (run both
and race; eliminate the construct that forced the choice).

## Phase 5 — Candidate representation objects (fan, then tower)

- First **enumerate** candidate representations — deliberately "radically
  different ways to implement the interface, every one of which respects
  the denotation" — then **pick**. The plurality is the payoff, not a
  survey step: a non-operational meaning is what lets one denotation carry
  an interpreter, a GPU code generator, and a radically transformed
  representation *at the same time*, each knowing exactly what it takes to
  be correct. Where the design descends through concerns, order the
  survivors into the level table; where it fans into peer backends, record
  them as peers under one denotation, each with its own realization card
  (phase 9).
- Levels need not descend monotonically in "operational-ness": they are
  instantiations of one construction at different parameter choices, plus
  general transformers (CPS, dual — see the method file) applied to
  previous levels. The carrier may return to the naive one, transformed
  (AD's fastest level is the *first* level, dualized); several
  instantiations stay alive at once, and the parameterization is what buys
  mode-independence. Give the level table a column for "which
  parameter/transformer distinguishes this level."
- **Justify each representation against the naive functional baseline.**
  The direct transcription of the meaning is usually correct and usually
  too slow; that is the baseline the chosen representation must beat, on
  the record. Choosing a representation because everyone else uses it is a
  named failure — "often people choose it wrongly, and that's really
  harmful."
- Build the **level table**: Level | Object | Carrier |
  Parameter/transformer | Exactness of its semantics. Decide the equality
  relation *per leg* (exact where math permits; bounded-and-measured where
  finite precision enters; bit-exact relative to a declared policy at the
  bottom) and defend the split as principled.
- Define each level boundary **negatively** as well as positively:
  "nothing above level k may mention floats, devices, or time"; "nothing
  below level j may introduce a user-visible knob." The negative clauses
  are what convert a violation into a diagnosable spec defect.

**Artifact**: the candidate fan with the pick recorded; the level table
plus the negative boundary clauses.

**Exit test**: every subtraction recorded in phase 1 reappears at exactly
one named level (or in exactly one named peer backend).

## Phase 6 — Denotations between representations

- Give each level k a *named* meaning function into level k−1
  (`at`, `occs`, `pred`, `force`, `value_at` — naming it is much of the
  work), compositional, and let it be uncomputable.
- State the meaning function as representation → meaning only. The
  *encoding* direction is then a specification, not a definition: a
  legitimate representation of `x` is **any** value whose meaning is `x` —
  say it in that deliberately backwards form ("come up with a bit pattern
  whose interpretation is the number you have in mind", not "convert the
  number to binary"), because it makes non-injective representations
  normal rather than a defect, and prevents an encoding function from
  becoming a second, competing specification.
- Write the one-line end-to-end statement first — `⟦running system⟧ ≡
  ⟦mathematical object⟧` at the named equalities — and treat everything
  below as bookkeeping that makes that one line checkable in pieces.
- Define semantic equality per level: `a ≡ b ⟺ ⟦a⟧ ≡ ⟦b⟧`, and keep each
  representation abstract. Equality is an operation with its own morphism
  obligation — see the method file.
- Check invertibility at each level: where `⟦·⟧` is invertible, all
  semantic choice disappears and instances can be synthesized mechanically.
- In a dependently typed host, consider **indexing the representation by
  its denotation** (`data Repr : Meaning → Type`) so nothing of the wrong
  meaning is constructible and the decision procedure's type *is* the
  correctness statement.
- Assign an audience to each edge of every square: the user reads the top,
  the implementation does the bottom, correctness ties them. A spec-tower
  file with two audiences is doing two jobs.

**Artifact**: per level, the named meaning function's signature and
definition; the composed end-to-end statement.

## Phase 7 — Typed operations per representation

- **Gate**: do not begin on operations until the level's meaning function
  is written. "If you can't answer how the representation means the things
  we're talking about, you shouldn't try anything else… it's only the
  meaning that guides them." The equation has one unknown only once `⟦·⟧`
  is fixed; without it there are three.
- For each level and each operation: write the homomorphism equation
  (mechanical — meaning distributes to the insides; see the method file),
  then **solve** it with the solving loop (`denotational-method.md`
  §solving). Expect many equations to arrive already solved.
- **The question to refuse.** When a collaborator asks "what should this
  operation *do* on this representation?", do not answer it. Say: that is
  not a question this framework answers. What is the denotation? What is
  the morphism equation? If your definition agrees with the equation it is
  right; if it disagrees it is wrong. Answering the operational question
  once teaches the collaborator that the framework is optional — and the
  host language will not deliver the verdict for you, so expect to repeat
  the refusal until a checker can.
- When the denotation is not inspectable (functions are black boxes), add a
  second reified layer with its own meaning function and re-run the
  identical calculation — the composition of homomorphisms is a
  homomorphism, so the composite is free.
- When an equation will not close, use the failure-diagnosis table — the
  repair is a design finding, never a weakened spec.

**Artifact**: per level, the operation definitions, each traceable to the
equation that forced it (keep the derivations — read backwards, they *are*
the proofs), plus the best rejected candidate per operation and any
recorded warts.

**Exit tests**: no operation was written first and checked second; every
argument on the right-hand side of every semantic equation is either
wrapped in `⟦·⟧` or recorded as a deliberately meaning-free primitive (an
un-denoted argument is an accepted primitive or an unnoticed hole — audit
each one).

## Phase 8 — Commuting theorems: statements and proofs

- State one commuting square per adjacent-level operation pair; the
  square's statement is kernel (human-reviewed); its *proof* is
  checker-validated (the proof assistant), never human-reviewed. For a
  translation with no counterpart operation upstairs (a compiler, a
  serializer) the shape is a **triangle** into one shared meaning world.
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
no junk states are representable **in any representation** (or the junk is
named). Scope that clause to representations: junk in the *semantic
domain* — meanings nothing expressible will ever denote — is usually a
deliberate purchase of simplicity and headroom, not a defect (see the
method file §headroom), and occasionally a prediction (Dirac's surplus
solutions were antimatter). An implementation change that cannot state its
denotation is not reviewable.

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
type-check?

Produce the **elimination list** — the standard machinery of the field
that the finished design never needed: "no graphs, no tapes, no
perturbation tags, no partial derivatives, certainly not mutation." It is
the exit-side counterpart of phase 1's subtraction list, and it is how the
result is stated to a skeptical practitioner.

Finally, record what resisted: types with no semantic morphism, unclosed
equations, structural evidence ceilings — published as open problems,
never papered over.

## How to disagree inside the dialog

The user's candidate meaning is never overridden by argument. The
criterion (from Elliott's Nonviolent Communication training): **before
proposing a replacement, reflect their model back until they confirm you
have its essence.** Paraphrase from the inside, never play back their
words ("a robot could do that"). Iterate; if the confirmation does not
land, back up rather than press on. Separate values from strategies —
"our beliefs are our strategies for how to fulfill our values" — because
opposed positions usually share the value (correctness, speed, shipping)
and differ only on strategy, and naming the shared value puts both people
on the same side of the puzzle. The failure mode to avoid: "in a debate,
the point is winning… which is another way to say, to leave the
conversation without having learned anything."
