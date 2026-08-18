# The denotational method, distilled

Source: Conal Elliott's corpus, 1988–2023 (TBAG, Fran, Pan, Vertigo,
Beautiful Differentiation, Type Class Morphisms, Push-Pull FRP, Simple
Essence of AD, Compiling to Categories, Generic Functional Parallel
Algorithms, Generalized Convolution, Calculating Compilers Categorically,
Timely Computation), plus his recorded talks and seminars. This file is
the working engine for phases 1–8.

## The kernel of the discipline

Denotational design is Scott–Strachey denotational semantics applied to
*data types* rather than languages: a library's types are a language, its
constructors are the syntax, and the model is `⟦·⟧`. For each type `T`,
name a mathematical object `⟦T⟧` and a compositional function
`⟦·⟧ :: T → ⟦T⟧` that fixes equality: `a ≡ b ⟺ ⟦a⟧ ≡ ⟦b⟧`.

Choose the denotation for **comprehension, not computability** — a
non-computable meaning is legitimate and often ideal, because it cannot be
confused with the artifact it constrains, and it costs nothing: "we only
compute with representations; we only think with meanings." Simplicity is
epistemic, not aesthetic: the specification is the one facet that cannot
be objectively verified — "a theorem is a question, and there is no
question to check the question with" — so its only quality control is that
a person can hold it entirely in mind. A precise denotation also makes
simplicity *measurable*: two APIs cannot be compared for abstraction
level, but their semantic models can. Precision is not optional for the
simplicity claim: "many ideas are simple only because they're not precise;
when made precise, their complexity becomes apparent."

The central device is the **type class morphism**: for every abstraction
the type inhabits, `⟦·⟧` must distribute over that abstraction's
operations — *"the instance's meaning follows the meaning's instance."*
(Elliott's own gloss when that slogan does not land, which he says is
often: **"every type acts like its meaning."**) One morphism equation per
operation does four jobs at once: it specifies the operation completely,
defines correctness for any implementation, transfers the class's laws
from model to type ("if not free, then already paid for"), and closes the
abstraction leak so users may treat a value as being its meaning — the
model and the running system are different, "but the difference is
undetectable through this vocabulary." The teaching sentence: **a
homomorphism is a perfect analogy** — the same idea named differently
across mathematics (functor in categories; monoid/ring homomorphism in
algebra; linear transformation in linear algebra); recognizing the name in
the user's home field is often the fastest route in.

Present the principle the way Elliott found it, not as an axiom: it
arrived bottom-up, out of "code poetry" — rewriting FRP semantics "not so
it would mean something different, but so that it would feel more poetic,
more balanced" — and was noticed empirically: "I thought this was just
cute the first time I saw it. Then I saw it happen again and again. And
now I know that it must happen everywhere, or I have a bug in my design."
Consequence: aesthetic dissatisfaction with a written denotation is
*evidence*, worth acting on before any proof obligation exists.

**Equality is an operation in the vocabulary, and it carries its own
morphism obligation.** Fix it before claiming any free law — "you have to
say what you mean by equality… equality is also part of the language."
Withhold the *word* until the operation earns it: shipping a comparison
that distinguishes semantically equal representations is "giving you a gun
to shoot your foot with." The strong form of the free-laws claim: a law's
proof needs the operation's *correctness*, not its definition — "you can
prove that without even knowing the definition of matrix multiplication,
only knowing that it's correct." Conversely, finding yourself proving an
algebraic property at all "is a symptom that you are picking away at the
surface" — properties never yield meaning; meaning always yields
properties. Preconditions of the transfer, all three: homomorphic
specification, semantic equality, and abstractness — a leaked constructor
voids the free laws.

**Why exactness, not approximation.** The reason a model is exact,
continuous, and possibly non-computable is a composition law, not taste:
approximations do not compose, and exact things do — "compositionality
depends on perfection." Every approximation in a model — a sample rate, a
tolerance, a "probably correct" component — degrades under composition,
and composition is the method's entire leverage. The same principle
governs both ends of the tower: it is why discreteness belongs to
presentation rather than meaning, and why formal proofs (which compose
without degrading certainty) are the only components from which an
almost-correct system can be built.

**Landin's denotative test, and equality before laws.** Deprecate
"functional" as a design predicate; use Landin's *denotative*, which is
testable: nested expression structure; every expression denotes something;
the denotation depends *only* on the denotations of the sub-expressions.
The third property "gives us a test for whether the notation is genuinely
functional or merely masquerading" — and reframes unproductive arguments
("is Scala functional?" is a non-question; "is Scala denotative?" has an
answer, and "if we're happy with [the resulting semantics], celebrate; if
not, let's steer"). Operationalize it as a prohibition on observables:
**no information gets out other than through the semantic function** —
test by naming candidate illegal observables and confirming each is
unrecoverable (wall-clock, the representation, the size of the expression
that built the value, construction history). Sharpest diagnostic: **you
cannot ask whether laws hold until equality is defined.** "Every time I
hear somebody say *the IO monad*, it bugs me… monad has laws; equality is
not defined on IO. It's not even wrong, because it's not denotative."

**Say where taste is allowed.** Choices at the rendering/presentation
level are frequently arbitrary and should be declared arbitrary ("there
are a variety of ways one might visualize a curry function… this is the
one I picked"). Choices in the denotation are never presented as taste. A
design document that blurs the two invites re-litigation of settled
semantics and false consensus about drawings.

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
| language | `A* → Set` (turning recognition into parsing — "languages have explanations for when strings are in them, formalizable as proofs") |
| polynomial / power series | a function `a → a` (not linear, so matrices do not apply) |
| formula (SAT/SMT) | a predicate `env → Bool` — the solver's job is to satisfy it, not to traverse a graph |
| state machine | `Stream a → Stream b`, restricted to the *causal* ones (the restriction lives in the semantic domain, as a restriction of the function space) |
| compiler / translation | a commuting **triangle**: source and object each denote into one *shared* meaning world ("they have to be the same world or you can't talk about correctness") |
| future value | `(T̂, a)` with `T̂` a monoid of partial times |
| stack computation | `SF (∀z. a×z → b×z)` |

When there is no counterpart operation upstairs — a translation, a
compiler, a serializer — the shape is a triangle, not a square.

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
subset that suffices — "a category is just a monoid with types", and
Elliott's own usage is "very, very simple category theory"); a linear map
gives a biproduct category (compositional matrices with no matrix code);
value-plus-rate gives Functor + Monoidal (deliberately weaker than
Applicative). Demand classes one at a time — *which ones fail is
diagnostic* — and diagnose a failure by the semantic domain when possible
(continuous images have no Foldable: "there's too much"; whether a
Traversable exists "would be some kind of integral thing — I'm not sure"
is a legitimate recorded open question).

**Naming rule**: name the representation's operation after the model
operation it denotes. A conventional name that does not match is evidence
the denotation was never taken seriously: "matrix addition is analogous to
linear-map addition — good job. Matrix *multiplication* is analogous to
linear-map *composition* — oops, bad naming job."

**Conformance is derived, not stipulated**: shape constraints on a
representation are homomorphic images of the model's typing — "the height
of one equals the width of the other translates homomorphically into: the
output type of one equals the input type of the other"; identity matrices
are square because identity maps a type to itself.

**Recognizing a semiring**: when a domain has two combining operations
that behave like × and + — each associative with an identity, one
distributing over the other, with annihilation — the entire linear-algebra
apparatus attaches (dot products, matrix multiplication, closure) with no
matrices in the code. Worked instance: hardware timing analysis is linear
algebra over (max, +) — parallel composition takes max, sequential adds —
so the combinator recipe that assembles a circuit assembles its timing
recurrence. Before assuming a recognized algebra is novel, search the
literature: max-plus was already the field of tropical semirings.

**What else could it mean? (retargeting).** Once a vocabulary has one
denotation, ask which *other* models it admits — a design tool, not
trivia. For a typed functional core, Lambek (1980) settled it: the models
are exactly the Cartesian closed categories — "exactly the reasonable
meanings you can assign to functional programs." Retargeting is
interpreting the same core in an unusual CCC: hardware, derivatives,
timing, work/depth, intervals, SMT. Corollary for choosing among candidate
vocabularies: prefer the one *symmetric with respect to composition* —
asymmetric vocabularies quietly restrict what you can compute (Beautiful
Differentiation's vocabulary supported forward-mode AD only; a
composition-symmetric one yielded forward, reverse, and mixed modes from
one derivation).

## Choosing among candidate meanings

The repertoire lists candidates; these are the tests between them:

1. **Pre-existing mathematics** — statable concisely in math that exists
   for other reasons (the Gell-Mann test; "go learn it" passes, "invented
   for this design" fails).
2. **Which theorems become one-liners** — prefer the domain where the
   properties you need are cheap: matrices denote linear maps; matmul
   denotes composition; composition is associative; therefore matmul is
   associative — four lines, versus index-slinging.
3. **Would you care about this object if computers did not exist?** A
   notion that only makes sense because of the machine wants more
   subtraction.
4. **Headroom**: a good model is *strictly more permissive* than the
   operation vocabulary it justifies — asked whether blurring was
   expressible: "the semantic model allows it, the API doesn't yet. So
   that's nice: we haven't prevented it, we haven't enabled it yet." Slack
   in the meaning is a purchase, not a defect: "I might make the
   denotations less precise — room for a lot more than I can express — in
   order to make them simpler." When someone objects that the domain
   admits pathologies (non-measurable sets, arbitrary functions), do not
   narrow the domain; push restriction *down*, to the operations the API
   offers and to the representation ("we'll have to figure out if every
   operation preserves that property" — that is the commuting square).
   Restricting the semantic domain is a last resort, taken only when the
   candidate is not a morphism at all.
5. **Among interconvertible models, prefer the shape that exposes shared
   structure.** `Set Loc` vs `Loc → Bool` are isomorphic, and the set
   reads more naturally alone — but written as `Loc → Bool`, Region's and
   Image's meaning functions "look fairly similar", which is what produced
   `Region = Image Bool`. A model that reads better standing alone may be
   the worse model in a design with several types; test candidates against
   the *set* of types, not one at a time.
6. **Read an anomaly as a missing entity before a broken theory.** A model
   admitting values the domain seems not to have may be a prediction:
   Dirac's equation "had twice as many solutions as there should have
   been" — the surplus was antimatter. The Uranus discrepancy was Neptune,
   not a defect in Newton. Change the semantic domain only when refinement
   has genuinely outrun it.
7. **Adequacy admits, efficiency vetoes, simplicity decides** (see the
   ground rules).

The laws-as-lemmas contrast, canonical form: Kepler's laws are beautiful,
exact, and explain nothing — "it wasn't an explanation because he didn't
say why." Newton's short formula is a denotation: Kepler's laws are
deducible from it, *and* it reaches further, to falling bodies. A law
table with no meaning behind it is Kepler; the meaning from which the laws
follow as lemmas — and which explains things you did not put in — is
Newton.

## The solving loop (phase 7's engine)

**Gate.** Do not begin until the representation's meaning function is
written down. "If you can't answer how the representation means the things
we're talking about, you shouldn't try anything else." The equation has
one unknown only once `⟦·⟧` is fixed.

**Every morphism equation is an algebra problem with exactly one
unknown** — the representation's operation, usually function-valued; the
meaning functions and the model's operation are given. Two consequences:
the solution set may have several members, and **every member is
correct** ("anything that is not a solution is wrong; everything that is,
is right") — efficiency work is the choice among solutions, never a
departure from the set. Where convenient, state the specification as a map
*into* the representation being derived (`D̂ : Meaning → Repr`, `cont`,
`dual`): written that way each equation (`D̂ id = id`,
`D̂ (g ∘ f) = D̂ g ∘ D̂ f`) leaves the unknown alone on one side. The
equation set is small, fixed, and mutually independent (for a Cartesian
category: `id`, `∘`, `exl`, `exr`, `△` — five equations), and it recurs
*unchanged* at every level, which is what makes adding a level cheap.
Choose the composition vocabulary so the domain's classical theorems
become the morphism equations: the chain rule, the fork rule, "every
linear function is its own derivative" are looked up, not proved, and the
solved forms are read off them.

**Writing the equation is mechanical.** Meaning distributes to the
insides: a nullary method has no inside, so `⟦·⟧` goes away
(`⟦id⟧ = id`, `⟦exl⟧ = exl`); a binary method has two insides, so the
meaning goes there (`⟦g ∘ f⟧ = ⟦g⟧ ∘ ⟦f⟧`). Elliott on doing it: "I didn't
have to think, I was just a robot typing there — that's just what
homomorphisms look like." If writing the equation required a decision,
that decision belongs in the semantic domain.

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
2. **Simplify**, annotating every rewrite with a named justification in
   braces. The workaday shape is one-sided and goal-directed: start from
   the semantic side, inline `⟦·⟧`'s defining clauses, simplify with the
   *semantic domain's own* laws, then **pattern-match the result against a
   defining clause of `⟦·⟧` and read the argument off** ("oh, that looks
   like `⟦scale s⟧`… so this is `⟦scale (s·s′)⟧`" — "this isn't just
   lucky; I was working in this direction").
3. **Strengthen toward solvable shape** — the move newcomers omit, and it
   depends on the carrier. For a **function carrier**, generalize away
   from the specialized form: no definition may be read off a special
   case, so pass from `SF (first g) ∘ SF (first f) = SF (first g ∘ first
   f)` to `SF g ∘ SF f = SF (g ∘ f)`. For a **free/reified carrier** (a
   GADT with one constructor per operation) the move is the converse:
   case-analyse the arguments over the constructors ("there's only one
   constructor so far, so G has to be `Scale s`") and re-run per
   constructor pair; adding a constructor obliges revisiting each
   derivation.
4. **Observe solved form; adopt it as the definition.**

The derivation is also the proof: "the reasoning was top-down; the proof
you can verify bottom-up — just read the slide from the bottom up."

Expect many equations (`exl`, `dup`, `inl`, `swap`, `rassoc`, …) to arrive
already solved. Four shortcuts:

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
- **Look it up afterwards**: when several candidate semantic definitions
  type-check, let the object's *defining property* decide — two results of
  type C must be **added**, not chosen between; a missing injection
  component must be **zero**, both "because we're really working with
  linearity" — then go read the mathematics and expect to find the derived
  definition already named (fork/join on linear maps are **direct sums**;
  "I did not make up these definitions… when I design a library, I want to
  invent as little as possible"). Failing to find it named is weak
  evidence the semantic domain is off-repertoire. Caution: the semantic
  domain's product/coproduct need not be the host language's — "for linear
  maps the coproducts are not sums; they're actually products."
- **Generalize temporarily to force uniqueness**: more polymorphic types
  admit fewer inhabitants. When an operation's definition is
  under-determined by its type, generalize the *signature* until only one
  implementation type-checks, read the definition off, then specialize
  back if the generality is unwanted — "I already know what the right
  answer would be thanks to it." (Distinct from move 3, which generalizes
  the equation.) While there, **enumerate the type-correct candidates
  explicitly**, including degenerate ones and any candidate that is
  semantically right but not computable; name the best rejected candidate
  in the record. Exemplar: the right meaning of `transform` is
  `⟦im⟧ ∘ ⟦h⟧⁻¹`, "except that I don't know how to do it" — the shipped
  meaning requires the caller to pre-invert, and the verdict is recorded:
  "I'm not entirely proud of it", with the declined principled alternative
  (a class of invertible functions closed under the operations) in the
  record too.

When the denotation is **not inspectable** (functions are black boxes): add
a second reified/free layer with *its own* meaning function, re-run the
identical calculation, and compose — the composition of homomorphisms is a
homomorphism, so the outer correctness is free.

When the meaning must decompose along an index: factor by the index type's
constructors (`f = at_ε f ◁ D f` for functions from lists), recognize the
pieces as standard structure (`coreturn`/`cojoin` of the exponent comonad),
and let a data type mirroring the decomposition make the implementation a
transcription of the reconstruction theorem.

## Category transformers (the tower's actual building material)

Levels are often not bespoke designs but general, domain-independent
constructions applied to the *previous* level and re-solved against the
same fixed equation set. Two with a track record:

- **CPS/Cayley** — when cost depends on how an associative operation is
  associated: "matrix multiplication has to be associative because it
  implements function composition, but it really matters a lot which way
  you associate." Forward-mode AD associates right, reverse-mode left; CPS
  forces left. Embed the transform as a category, re-solve the five
  equations.
- **Dual/transpose** — via `(v ⊸ s) ≅ v` when the codomain of interest is
  the scalar field (objective functions are scalar-valued; that domain
  fact is part of the record). Solving gives: composition flips,
  projections↔injections, fork↔join, scaling unchanged — matrix
  transposition, *derived*. "This is the heart of backprop."

Both are independent of the subject matter — "it has nothing to do with
differentiation or linear maps, just like the CPS transform was." The
heuristic: when association order or a cost dimension is the lever,
introduce a general transformer that forces it, then re-solve.

## Growing a design after the first derivation

Extending the vocabulary obliges extending the specification
*consistently*, in a fixed order: (1) add the operations to the interface;
(2) extend the model's instances so the new operations have meanings;
(3) extend the representation by **promoting each new operation to a
constructor**; (4) extend `⟦·⟧` with one clause per new constructor;
(5) re-derive the previously solved operations, now case analyses over
constructor pairs. Worked instance: `scale` + `▵` (vertical stacking) +
`▿` (horizontal juxtaposition) generate all of matrix algebra, and the
type constraints in the signatures *are* the dimension-matching rules —
"juxtapose horizontally, the heights have to match; that's why C is in
both places." Two-dimensional layout is a theorem about the operations,
not a premise (Elliott, *Reimagining matrices*).

## The failure-diagnosis table (the method's highest-value section)

A morphism equation that will not close is a finding that names which
representation, class, or semantic domain is wrong — never grounds to
weaken the specification. Read an anomaly as a missing entity before a
broken theory; prefer the repair that improves overall simplicity.

| Symptom | Diagnosis → repair |
|---|---|
| Surplus `fmap`/`liftA2` layer | the model is an unfactored functor composition — factor it (`Map k = TMap k ∘ First`, `Behavior = Reactive ∘ Fun Time`) |
| A bias/ordering silently lost; a default instance corrupts the design | the *element type* is wrong — keep the representation, change the type (`k → Maybe v` ⇒ `k → First v`) |
| The equation needs an argument that is not available | the specification is not compositional — the recognizable form is a law that mentions a value the caller cannot reconstruct (the chain rule needs `f` itself, not just `D f`); augment the *spec* and iterate (bundle, then fuse) |
| The model admits values the domain seems not to have | *first* ask whether the domain has values you have not noticed (Dirac's surplus solutions were antimatter); also consider deliberate headroom (§choosing). Only after both readings fail is it junk to exclude or name |
| The morphism holds on total values but fails at ⊥ (e.g. `and False ⊥ = False` but `and ⊥ False = ⊥`) | the host's commitment to *sequential evaluation*, not your model — keep the symmetric law and require an unbiased/parallel realization, or move to a total language where ⊥ does not arise. Never weaken the law to match the evaluation order |
| An operation in the model is partial (division, head, indexing) | you got the domain wrong — totalize: add the precondition's proof as an argument (`a / b` plus a proof `b ≠ 0`), implicit where instance resolution discharges it. "A partial function is a function for which you got the domain wrong" — a general recipe, not a trick |
| Two teams share a representation and disagree what it means (matrix×vector vs vector×matrix, square so nothing catches it) | the representation was serving as the interface — publish denotations, not representations; the composed theorems then refuse to close until the interpretations are reconciled |
| An argument on the right-hand side of a semantic equation is not wrapped in `⟦·⟧` | you have silently declared that type meaningless ("it just kind of is what it is"). Either that is true and recorded as a primitive, or the type deserves its own meaning function — audit every equation for un-denoted arguments |
| The candidate meaning is not a morphism at all | it is not the meaning function — change the semantic domain (restrict it, e.g. to hyper-strict functions, which may also buy invertibility) — a last resort; try the rows above first |
| A whole class cannot be instantiated | wrong representation for the job — change it, or drop the class and say so publicly |
| A class method is undefinable for a reasonable model | indict the *class*, not the model — factor or generalize the class hierarchy (the `arr` exemplar) |
| The denotation is not inspectable | add the reified layer with its own meaning function |
| The representation cannot support one operation | record the limitation against the representation, honestly |
| One key type resists entirely | publish it as an open problem (Push-Pull FRP's `Event` has no semantic morphism — and says so) |
| A forced either/or dilemma | suspect the framing — run both in parallel and race, or eliminate the construct that forced the choice |

## The anti-pattern table (retrofit diagnosis)

| Anti-pattern | The tell | Antidote |
|---|---|---|
| Representation becomes the concept | the *user* must build a representation of the thing (graph, tape, matrix) although the host language can express the thing itself; "transforms *are* matrices"; the concept is taught as a number/vector/matrix | ask what the concept is as a space-to-space function; name the object the received notion represents and let the representations become tower levels. A *generated* graph or matrix, as one interpretation among several, is not the anti-pattern — it is the payoff |
| Boundary shapes dictate the vocabulary | "my inputs are JPEGs, therefore this library manipulates finite discrete bitmaps"; "video in, video out, therefore behaviors are frame sequences" | the conclusion does not follow *and* it is disastrous; devices belong at the edges as representations. A defect of the telescope is not a property of the sky — "if you see your eyes, you have cataracts." Second-order tell: the author cannot see it as a choice |
| Discreteness in the model | sample rates, frames, ticks in the meaning | discreteness belongs to presentation. Ammunition against the standard rebuttals — round-trip failures, interpolation's arbitrariness, the physics frame-rate argument, "users can't articulate the laws they miss" — is in `objections.md` |
| Laws asserted as the spec | algebraic properties with no denotation behind them | this is *axiomatic semantics* (introduce names, then state properties), the third and oldest semantic tradition, done competently in the wrong slot — which is why it feels rigorous. Derive laws as lemmas from a meaning function |
| Class instance claimed with no stated equality | "it's a Monad" with no answer to what `≡` means on the type | the claim is not even wrong — define semantic equality first or withdraw the claim ("IO is the only one we don't know is a monad, because we don't even know what the question is"). And the compiler checks none of it: methods without laws are "not a category — sadly, the type system has no way to tell you" |
| Meaning given as a machine | the semantic domain is a store, a state, a transition system, an abstract/virtual machine | the meaning must be independent "not just of any particular machine, but of the idea of a machine." A store is a representation, however idealized |
| The math and the program are two artifacts | the paper/docstring carries equations, the code is a hand translation, nothing connects them | "programming is just a subset of math that is executable by physics" — make the equations the executable spec, the fast version a refinement of it |
| States that must not be observed | a commit/flush/present/double-buffer step after which state becomes meaningful | the pre-commit states denote nothing: "all you have is this partially done thing whose nature has very little to do with the correct answer and very much to do with the arbitrary order of operations you happened to follow" |
| A large API that builds a graph/expression for something else to interpret | "an ad hoc language with no surface syntax, whose construction you program from another language… what are graphs? Poor man's language" (TensorFlow) | count the genuinely new ideas; the user-visible footprint should be that many names — "it should be called `derivative`." Get the capability by compiling the host language, not by rebuilding the host as data |
| Invariant by comment | "callers must ensure…", assertions, docs | make the constrained type an object; preservation becomes a morphism component (the totalization recipe is the pointwise form) |
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
optimizer nothing, and a whole tower level can vanish: "there are actually
no matrix operations at all in the backprop algorithm — they're in the
derivation, but they get optimized away entirely"); state correctness as
*refinement* rather than equality (the optimized program may be more
defined). Two prohibitions: an efficiency fix may never move the meaning
("performance problems are representation problems"), and never optimize
before understanding — premature optimization conceals structure (it hid
the Sklansky/Ladner–Fischer duality for fifty years). Derive the
operational story *last*: instruction sets, push/pop brackets, evaluation
order, tapes are theorems to read off the solved instance, never premises.
Bonus: the same combinator recipe that assembles algorithms assembles
their work/depth recurrences.

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
partial values too: a morphism holding on total values may fail on ⊥ (see
the failure table's ⊥ row for the diagnosis).

## Completion tests

1. Every type has a stated meaning that fits on a line.
2. Every operation's meaning is forced by a written morphism equation; no
   bespoke name remains where a standard class supplies one.
3. Nothing is left to prove: laws hold by morphism, the type is abstract,
   remaining proofs are lemmas from the denotation.
4. Efficiency lives elsewhere, as refinement of an unmoved denotation.

Negative test: does it **morphism-check**, not merely type-check?
