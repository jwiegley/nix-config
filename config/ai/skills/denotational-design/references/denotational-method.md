# The denotational method, distilled

Source: Conal Elliott's corpus, 1988–2023 (TBAG, Fran, Pan, Vertigo,
Beautiful Differentiation, Type Class Morphisms, Push-Pull FRP, Simple
Essence of AD, Compiling to Categories, Generic Functional Parallel
Algorithms, Generalized Convolution, Calculating Compilers Categorically,
Timely Computation). This file is the working engine for phases 1–8.

## The kernel of the discipline

Denotational design is Scott–Strachey denotational semantics applied to
*data types* rather than languages: a library's types are a language, its
constructors are the syntax, and the model is `⟦·⟧`. For each type `T`,
name a mathematical object `⟦T⟧` and a compositional function
`⟦·⟧ :: T → ⟦T⟧` that fixes equality: `a ≡ b ⟺ ⟦a⟧ ≡ ⟦b⟧`.

Choose the denotation for **comprehension, not computability** — a
non-computable meaning is legitimate and often ideal, because it cannot be
confused with the artifact it constrains. Simplicity is epistemic, not
aesthetic: the specification is the one facet that cannot be objectively
verified, so its only quality control is that a person can hold it entirely
in mind. And a precise denotation makes simplicity *measurable*: two APIs
cannot be compared for abstraction level, but their semantic models can.

The central device is the **type class morphism**: for every abstraction
the type inhabits, `⟦·⟧` must distribute over that abstraction's
operations — *"the instance's meaning follows the meaning's instance."*
One morphism equation per operation does four jobs at once: it specifies
the operation completely, defines correctness for any implementation,
transfers the class's laws from model to type ("if not free, then already
paid for"), and closes the abstraction leak so users may treat a value as
being its meaning. Precondition: the type stays abstract — a leaked
constructor voids the free laws.

## The repertoires (make phases 1–2 mechanical)

**Denotation repertoire** — candidate meanings with a track record:

| Domain notion | Meaning |
|---|---|
| time-varying value | `Time → a` |
| event stream | non-decreasing `[(T̂, a)]` |
| image / field | `Point → a` (continuous, infinite) |
| region / predicate / set | `a → Bool` … generalize to `a → s` (semiring) |
| transform | `Point → Point` — a function, *not* a matrix |
| derivative | a linear map `a ⊸ b`, not a number/matrix/tape |
| language | `A* → Set` (turning recognition into parsing) |
| future value | `(T̂, a)` with `T̂` a monoid of partial times |
| stack computation | `SF (∀z. a×z → b×z)` |

**Non-arrow repertoire** — for things indexed by nothing (asking "a
function of what?" before "what object?" is the method's worst failure
mode): a monoid element chosen for bias/ordering; a semiring element whose
arithmetic is the domain's operations; a lattice element; a type paired
with an invariant (PRED: objects `(type, predicate)`, morphisms
`(function, preservation proof)`, predicates in `Set` so they need not be
decidable); a value paired with a rate of change; a representable
functor/memo trie (data standing for a function).

**Shape→classes rule** — match the *form* of `⟦T⟧`, not its subject:
`A → B` gives the reader Functor/Applicative/Monad plus everything `B`
inhabits pointwise; a set/predicate gives Monoid/Semiring/StarSemiring/
Semimodule; a monoid-indexed semiring-valued function is the monoid
semiring, whose multiplication *is* convolution *is* `liftA2` of the index
operation; a space of arrows gives the categorical tower (take the weakest
subset that suffices); a linear map gives a biproduct category
(compositional matrices with no matrix code); value-plus-rate gives
Functor + Monoidal (deliberately weaker than Applicative). Demand classes
one at a time — *which ones fail is diagnostic*.

## The solving loop (phase 7's engine)

The Simple Essence recipe, near verbatim: start from an expensive or
non-computable specification; build the desired result into the
*representation* of a new type; show conversion into that type is
compositional over well-understood abstractions; if compositionality fails,
read the failure for the augmented specification it indicates and iterate
(`D` → `(f, D f)` → fused `D⁺`); set up the algebra problem in the stylized
form "the operation being solved for is a homomorphism"; solve; the laws
then hold provided the type stays abstract.

Per equation, four moves:

1. **Write** the homomorphism equation for one operation.
2. **Simplify both sides independently**, annotating every rewrite with a
   named justification in braces.
3. **Strengthen by generalizing away from the specialized shape** — the
   move newcomers omit. The raw equation arrives with every morphism in the
   form `h f`; no definition may be read off a special case, so generalize
   to arbitrary arguments (from `SF (first g) ∘ SF (first f) =
   SF (first g ∘ first f)` to `SF g ∘ SF f = SF (g ∘ f)`).
4. **Observe solved form; adopt it as the definition.**

Expect many equations (`exl`, `dup`, `inl`, `swap`, `rassoc`, …) to arrive
already solved. Two shortcuts:

- **Invertible `⟦·⟧`**: synthesize mechanically — `∅ = ⟦∅⟧⁻¹`,
  `u ⊕ v = ⟦⟦u⟧ ⊕ ⟦v⟧⟧⁻¹` — morphism-hood by construction; later rewriting
  is optimization, not correctness work. Invertibility "removes all
  semantic choice."
- **Obligation-collapsing meta-theorems**: if the numeric/monoid operations
  are defined via `pure`/`fmap`/`liftA2` and `⟦·⟧` is a Functor and
  Applicative morphism, the numeric/monoid morphisms are corollaries; and a
  morphism proof using nothing instance-specific applies to every type
  whose equality is defined by that kind of morphism. Where a functor into
  an already-lawful category exists, law families discharge wholesale.

When the denotation is **not inspectable** (functions are black boxes): add
a second reified/free layer with *its own* meaning function, re-run the
identical calculation, and compose — the composition of homomorphisms is a
homomorphism, so the outer correctness is free.

When the meaning must decompose along an index: factor by the index type's
constructors (`f = at_ε f ◁ D f` for functions from lists), recognize the
pieces as standard structure (`coreturn`/`cojoin` of the exponent comonad),
and let a data type mirroring the decomposition make the implementation a
transcription of the reconstruction theorem.

## The failure-diagnosis table (the method's highest-value section)

A morphism equation that will not close is a finding that names which
representation, class, or semantic domain is wrong — never grounds to
weaken the specification. Prefer the repair that improves overall
simplicity.

| Symptom | Diagnosis → repair |
|---|---|
| Surplus `fmap`/`liftA2` layer | the model is an unfactored functor composition — factor it (`Map k = TMap k ∘ First`, `Behavior = Reactive ∘ Fun Time`) |
| A bias/ordering silently lost; a default instance corrupts the design | the *element type* is wrong — keep the representation, change the type (`k → Maybe v` ⇒ `k → First v`) |
| The equation needs an argument that is not available | the specification is not compositional — augment it and iterate (bundle, then fuse) |
| The candidate meaning is not a morphism at all | it is not the meaning function — change the semantic domain (restrict it, e.g. to hyper-strict functions, which may also buy invertibility) |
| A whole class cannot be instantiated | wrong representation for the job — change it, or drop the class and say so publicly |
| A class method is undefinable for a reasonable model | indict the *class*, not the model — factor or generalize the class hierarchy |
| The denotation is not inspectable | add the reified layer with its own meaning function |
| The representation cannot support one operation | record the limitation against the representation, honestly |
| One key type resists entirely | publish it as an open problem (Push-Pull FRP's `Event` has no semantic morphism — and says so) |
| A forced either/or dilemma | suspect the framing — run both in parallel and race, or eliminate the construct that forced the choice |

## The anti-pattern table (retrofit diagnosis)

| Anti-pattern | The tell | Antidote |
|---|---|---|
| Representation becomes the concept | "transforms *are* matrices"; arrays + index arithmetic; graphs/tapes as the algorithm | ask what the concept is as space-to-space function; factor types, not numbers |
| Discreteness in the model | sample rates, frames, ticks in the meaning | discreteness belongs to presentation; ask "is time a value here, or implicit in an ordering?" |
| Laws asserted as the spec | algebraic properties with no denotation behind them | derive laws as lemmas from a meaning function |
| Invariant by comment | "callers must ensure…", assertions, docs | make the constrained type an object; preservation becomes a morphism component |
| Effects inside the model | an operation performs I/O in the denotation | effects are values (action-carrying events); one driver at the edge performs them |
| Meaning deferred to an external system | "whatever X/the GPU/the framework does" | fix the model first, then embed with a direct mapping |
| Pattern standing in for an abstraction | MVC-style choreography | one compositional type; multiple views come free |
| Construction-history-dependent equality | `combine` prefers "whichever was built first" | not a meaning function; the leak criterion failed in reverse |

## Optimization discipline (phase 7→9 boundary)

The specification is normally a valid, slow implementation; everything
after it is semantics-preserving refinement. Four legitimate moves: change
the representation and re-derive against the unchanged denotation;
decompose/recompose the meaning by functor composition; compile the meaning
away (inline until only scalars remain — abstraction layers cost the
optimizer nothing); state correctness as *refinement* rather than equality
(the optimized program may be more defined). Two prohibitions: an
efficiency fix may never move the meaning ("performance problems are
representation problems"), and never optimize before understanding —
premature optimization conceals structure (it hid the Sklansky/
Ladner–Fischer duality for fifty years). Derive the operational story
*last*: instruction sets, push/pop brackets, evaluation order, tapes are
theorems to read off the solved instance, never premises. Bonus: the same
combinator recipe that assembles algorithms assembles their work/depth
recurrences.

## Language independence

The method predates type classes (TBAG did it in 1994 C++: the morphism law
stated as a library property, the representation "completely hidden").
The invariant part in any language: name the object; name and write `⟦·⟧`;
keep the representation private; name operations after the standard-class
methods anyway; let the model be uncomputable. Substitutes: property-based
tests for morphism checking (generate values; apply the operation then
`⟦·⟧`; apply the model operation to mapped arguments; assert agreement —
then *delete* direct law tests as redundant corollaries); explicit names
for newtype wrappers; a review rule that any external mention of the
representation is a defect. Never transliterate Haskell/Lean notation into
a host lacking the constructs — "idiomatic C++ whose design was chosen
denotationally," not elegant Haskell awkwardly spelled. Check morphisms at
partial values too: a morphism holding on total values may fail on ⊥.

## Completion tests

1. Every type has a stated meaning that fits on a line.
2. Every operation's meaning is forced by a written morphism equation; no
   bespoke name remains where a standard class supplies one.
3. Nothing is left to prove: laws hold by morphism, the type is abstract,
   remaining proofs are lemmas from the denotation.
4. Efficiency lives elsewhere, as refinement of an unmoved denotation.

Negative test: does it **morphism-check**, not merely type-check?
