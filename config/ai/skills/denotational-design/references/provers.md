# Prover selection and idioms

The method's proof artifacts — the mathematical object, meaning functions,
morphism statements, commuting squares, and their proofs — live in a
dependently typed proof assistant. Default to **Lean 4**; support **Rocq**
(formerly Coq) and **Agda** as first-class alternatives. Settle the choice
in phase 1 and record it; the design documents then use that prover's
notation throughout.

## Choosing

Present these trade-offs; the user's ecosystem usually decides.

| Criterion | Lean 4 | Rocq | Agda |
|---|---|---|---|
| Standard mathematics library | Mathlib — the largest; semirings, categories, CPOs, linear maps arrive ready | MathComp / stdlib — mature, ssreflect discipline | agda-stdlib + categories libraries — leaner; more is hand-rolled |
| Proof automation | `simp`, `omega`, `decide`, strong metaprogramming | ssreflect, `lia`, Ltac/Ltac2, hint databases | minimal — proofs are mostly terms; copatterns make coinductive models pleasant |
| Programming-language quality (the executable spec is also a program) | excellent — Lean is a real PL; `#eval`, monads, do-notation, FFI | good via extraction (OCaml/Haskell); native execution weaker | good — compiles via GHC backend; Haskell-adjacent idiom |
| Extraction / realization path | compile to C via Lean's backend; FFI to C/Rust; or treat Lean as the oracle and bisimulate | certified extraction to OCaml/Haskell is the classic strength | GHC backend; or oracle-and-bisimulate |
| Coinduction (streams, behaviors, tries) | `Stream'`/coinductive via `Quot`-based encodings; workable | mature coinduction, guardedness | the nicest: copatterns and sized types make trie/stream models direct |
| Type-class / instance discipline | type classes with controlled resolution | canonical structures or type classes | instance arguments; explicit records common |

Rules of thumb: heavy real analysis or category theory in the model →
Lean (Mathlib). Certified extraction as the *shipping* path → Rocq.
Coinductive semantic domains front and center, or a taste for
proofs-as-programs minimalism → Agda. When the project already hosts one
prover, do not introduce a second for this design — "port a statement when
a consumer needs it, never as a bulk campaign."

## The method's artifacts, per prover

**The mathematical object and meaning functions.** Define the object as a
plain type/structure (`Model V := List V → Dist V`), each representation as
its own type, and each meaning function as a named definition
(`def denote : Repr → Meaning`). Let meaning functions be noncomputable
when the mathematics wants it (`noncomputable def` in Lean; `Prop`-level
functions in Rocq; postulated-or-`Set`-valued in Agda). Keep
representations abstract: do not export constructors; export smart
constructors plus the meaning function.

**Morphism statements (the specification).** One theorem per class method,
stated over the meaning function:

- Lean: `theorem denote_comp : denote (g.comp f) = (denote g).comp (denote f)`
  — group them in one file per level; the statements are K6 kernel, the
  proofs are not.
- Rocq: same shape; consider a `Morphism` record collecting the equations
  per class so a level's obligation set is one term.
- Agda: equations as record fields; copatterns let the implementation be
  read off the reconstruction theorem directly.

**Index-by-denotation (the strongest form).** Where practical, index the
representation by its meaning so wrong meanings are unconstructible and no
separate soundness proof exists: `data Lang : ◇.Lang → Set` (Agda);
inductive families / `Σ`-types with a meaning index (Lean, Rocq). The
decision procedure's type then *is* the correctness statement
(`⟦_⟧? : Lang P → Decidable P`). Reach for this when a level's junk states
keep generating side conditions.

**Discharging law families wholesale.** Split operations from laws;
discharge laws by a functor into an already-lawful category, defining
morphism equivalence in the new category as equivalence modulo that
functor. In Lean this is a `Category` instance plus a lawful functor; the
per-operation proofs then reduce to `rfl`/`simp` — "we never need to
perform these proofs when we specify category instances via a functor."

**Counterexample search before proof.** So false laws die cheaply:
`slim_check`/`plausible` (Lean), QuickChick (Rocq), or evaluation over
generated fixtures (Agda) — run the evaluator on both sides of every
morphism equation before asking for the proof.

**Proof placement.** Proofs are the AI-explorable class: checker-validated
(the kernel of the prover), never human-reviewed, and deliberately outside
any owner-review digest manifest — a proof edit must not re-mint an
owner-review signal. What humans review is the statements.

## The executable-spec bridge

Keep one executable (if slow) reference implementation *inside* the prover
per level — the denotation compiled directly, or the solved definitions run
naively. This is the oracle phase 10's bisimulation targets, and the
generator of golden vectors. Mark it clearly as specification-grade: its
performance is irrelevant by design.

## Axiom policy

Whatever the prover, publish the short, versioned list of seams where the
mathematics ends (classical axioms admitted, floating-point left to
empirical gates, external kernels quarantined behind a version-pinned
citation). Adding to the list is a decision-register event. Refuse global
theorems the substrate cannot support and say what empirically covers the
gap — "by design and not by concession."
