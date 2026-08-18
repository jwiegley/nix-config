---
name: denotational-design
description: This skill should be used when applying denotational design (Conal Elliott's method) to a project — designing a library, compiler, runtime, or system around a precise mathematical meaning. It guides a structured dialog to choose the principal mathematical object, its operations and theorems, a tower of representation objects with denotations between them, per-representation operation definitions solved from homomorphism (commuting) equations, machine-checked proofs in Lean/Rocq/Agda, empirical realization testing, and cross-language bisimulation (e.g., a Rust realization against its proof-assistant oracle). Triggers include "denotational design", "meaning function", "what does this type mean", "semantic domain", "type class morphism", "commuting theorems", "representation tower", "design this denotationally", or a request to give an existing codebase a formal semantic basis.
---

# Denotational Design

Guide a project from "what should this mean?" to a proven, tested, governed
implementation, using Conal Elliott's denotational design discipline: give
every key type a precise mathematical meaning, specify every operation by
the single requirement that the meaning function is a homomorphism, *solve*
those equations for the implementation rather than verifying guesses, refine
representations without ever moving the meaning, and accept realizations on
empirical evidence whose limits are declared.

The method in one line: **before asking how it runs, ask what it means;
then require that the meaning be preserved; let the implementation be
whatever the equations force it to be.**

The method at teaching scale, in Elliott's own words — "this plan holds
for library design in general": (1) define the abstract interface *and its
denotation* — "this is the most important thing; this is what it all
means"; (2) enumerate candidate representations — "radically different ways
to implement the interface, every one of which respects the denotation";
(3) pick one; (4) **calculate** the implementation from the specification.
The ten phases below are that four-step recipe expanded for a project with
a proof assistant, multiple levels, and many hands. On a small design, the
four steps are the whole method.

**The simplicity criterion is a test, not a taste.** A meaning is elegant
when it can be stated very concisely in mathematics that already exists
*for other reasons* (Gell-Mann's definition, which Elliott adopts —
"already learned" means collectively, so "now I'm finally motivated to
learn it" passes and bespoke machinery invented for this one design fails).
The pre-existence clause is what makes the claim falsifiable: otherwise one
can define a complicated object, name it, and point at the name. And when
someone calls a candidate "simpler", check whether they mean *familiar* —
"often when people say simple, they really mean familiar."

## When to use, and when not

**Design a vocabulary, not a language.** Elliott's scope is narrower than
"anything with a semantics": "I don't design languages… what I do is I
design programming interfaces and implementations." Landin's split governs:
a domain-independent host language plus an embedded domain vocabulary —
reinvent only the second. The positive admission test is *infinite
expressiveness*: a vocabulary whose values compose into unboundedly many
more values — a library, DSL-as-library, compiler, runtime, or protocol.
Applications get amnesty: "applications are quite rigid… you don't expect
to be systematic." When only one type in a design carries composition,
that is the one type to denote. When a capability genuinely cannot be a
plain library (automatic differentiation is non-computable at the host's
function semantics) or the target is exotic (hardware, mesh processors),
the remedy is compiling the host language (Compiling to Categories), never
a graph-building API — "the funkiness shouldn't be visible in my API;
that's an abstraction leak."

Do NOT apply the full method to I/O glue, config parsing, log formatting,
migration scripts, test scaffolding, or build tooling. The principled
reason: those fragments are not *denotative* — the meaning of an
expression does not depend only on the meanings of its components (Landin,
1966) — so there is no compositional meaning for `⟦·⟧` to be a homomorphism
over. The antidote is the usual one: make the effects into values,
interpret them with one driver at the edge, and denote the values. Own the
carve-out honestly: it is this skill's effort budget, not method doctrine —
Elliott rejects paradigm lines drawn by scale or layer ("functional core
and an imperative shell… stop and don't believe it") — so never cite it as
license for a denoted core with an undenoted shell. The proportionate
minimum for borderline cases: name the mathematical object and write one
line of `⟦·⟧`, then stop.

**Do not reach for the prover before the meaning.** Formalizing a design
that was conceived operationally — sequential, stateful, effect-ordered —
produces an artificially difficult proof that teaches nothing: success
shows only that a hard problem was solved. For such a codebase the
retrofit opening (write down the denotation it implicitly has, defects
included) is the work; proof comes after the meaning moves, not instead of
it.

## The process

Run the phases below **as a dialog**. Each phase has questions to put to
the user, an artifact to produce, and an exit test. Do not advance a phase
without its artifact. The full interview script, with per-phase questions
and exit criteria, is in `references/dialog-protocol.md` — read it first
and follow it. The phases:

1. **The principal mathematical object** — its shape and definition, found
   by subtraction, confirmed by the identity test.
2. **The fundamental operations** on that object — forced by structure or
   documented need, named by standard algebraic classes.
3. **The fundamental theorems** on that object and those operations —
   equations with downstream force, plus an explicit non-theorems list.
4. **Derived operations and theorems** — exploration; recognize before
   inventing, delete bespoke names that standard classes supply.
5. **Candidate representation objects** — first a fan of radically
   different candidates, then a pick; the tower from the mathematical
   object down to the final realization.
6. **Denotations between representations** — each level's meaning function
   into the level above, composing into the mathematical object's type.
7. **Typed operations per representation** — solved from the homomorphism
   equations, not written and checked.
8. **Commuting theorem statements and proofs** — the squares that establish
   each representation's semantics, machine-checked.
9. **Empirical realization testing** — quality, efficiency, performance,
   runtime behavior, accepted on pre-committed criteria.
10. **Cross-language realization fidelity** — bisimulation of (e.g.) a Rust
    implementation against its proof-assistant oracle.

Phases 1–4 fix the *meaning* (kernel classes K1–K3 plus derived layer);
phases 5–8 fix the *representations and their correctness* (K4–K6);
phases 9–10 fix the *realizations*, which are deliberately outside the
proof kernel and governed empirically.

**Provenance.** Phases 1–8 and the method references distill Elliott's
corpus and talks. Phases 9–10 and `references/governance.md` are a
program-scale extension from a different lineage: in Elliott's own talks
the proofs are hand calculations in an appendix and efficiency claims are
labelled impressions ("I don't have measurements to back that up"). On a
small project the derivation itself is the reviewable proof artifact, and
an unmeasured performance claim should be labelled as one rather than
dressed as a gate.

## How to work each phase

- **Method** (phases 1–8): the distilled Elliott discipline — the
  subtraction opening, the denotation repertoires, the shape→classes rule,
  the solving loop, the failure-diagnosis table (a morphism equation that
  will not close is the method's most valuable output), and the completion
  tests — is in `references/denotational-method.md`. Consult it before and
  during every design conversation; the diagnostic table is the part to
  have open when an equation resists.
- **Worked example**: `references/worked-example-images.md` reconstructs
  Elliott's image-library seminar end to end — candidate board, semantic
  equations, the generalization cascade, the class sweep, and the four
  recorded warts. Read it before running the dialog for the first time,
  and mine it for phase-appropriate exhibits during any engagement.
- **Objections**: every engagement will surface some of the standard
  objections (discreteness, full abstraction, "too slow for industry",
  "nobody can learn Agda", …). The answers Elliott actually gives — with
  his own grading of which objections are substantive — are in
  `references/objections.md`. Do not improvise these.
- **Prover** (phases 6–8): the design defaults to Lean 4, with Rocq and
  Agda as supported alternatives. Selection criteria, per-prover idioms for
  the method's artifacts, and extraction paths are in
  `references/provers.md`. Ask the user's preference in phase 1; do not
  re-litigate it later without cause.
- **Realizations** (phases 9–10): acceptance cards committed before the
  work, sampled-square evidence with pinned comparison tuples, evidence
  ceilings, and the bisimulation strategies for a foreign-language
  realization against its oracle are in
  `references/realization-and-bisimulation.md`.
- **Governance** (all phases, scaled to the project): the knowledge-kernel
  partition, the spec-tower file scaffold, law IDs and the obligation
  ledger, judged decision records, and the scale-down table are in
  `references/governance.md`.

## The worksheet

Produce the design as a living document seeded from
`assets/design-worksheet.md` — copy it into the user's project (e.g.
`doc/design/denotational-design.md` or split per level as it grows) and
fill it in phase by phase. The worksheet's sections mirror the phases, so
an empty section is a visible unmet obligation rather than an absence
nobody notices.

## Ground rules (hold these in every phase)

- **Meaning constrains implementation; implementation never constrains
  meaning.** Specification and realization are pulled in *opposite*
  directions — the spec toward precise simplicity, the realization toward
  the machine actually in front of you — and each should be pushed to its
  extreme: "if you conflate those two things you cannot win, or one can
  only win at the other's loss." The theorem is not a tax on the fast
  path; it is the permission slip for it. One honest exception, taken
  openly: where the semantically right meaning is not computable, Elliott
  has substituted the computable neighbour and *recorded the wart*, naming
  the declined alternative ("I'm not entirely proud of it"). Never take
  that move silently, and never for a whole object — only an operation's
  convenience is sacrificed, on the record.
- **Solve, do not verify.** Every homomorphism equation is an algebra
  problem with exactly one unknown — the representation's operation — and
  every solution is correct; implementations are read off solved forms,
  and efficiency work is the choice *among* solutions.
- **The specification may be unrunnable.** Prefer the non-computable
  meaning that is clear over the executable one that is compromised — at
  no operational cost, because "we only compute with representations; we
  only think with meanings."
- **Compose first, approximate last.** Approximation is legitimate and
  usually unavoidable; approximating *before* composing is not, because
  errors that are individually small compound past usefulness under
  composition. Resolution, sample rates, frame boundaries, step sizes, and
  fixed precision live at exactly one level — the bottom — applied once
  after everything has been combined. "Compositionality depends on
  perfection," and it is the method's entire leverage.
- **Adequacy admits, efficiency vetoes, simplicity decides.** A model that
  cannot answer the domain's questions is disqualified whatever its
  beauty; so is one whose realizations are unaffordably slow ("elegance
  isn't worth a 50× hit in efficiency — I completely agree"). Simplicity
  is the tiebreaker among candidates that already pass both, never an
  admission criterion.
- **Laws come "already paid for" under exactly three provisos** — the
  specification is in homomorphic form, equality is semantic
  (`a ≡ b ⟺ ⟦a⟧ ≡ ⟦b⟧`), and the type stays abstract. A type that does not
  define equality through its meaning has no meaning function, whatever
  the candidate is called; a leaked constructor voids the transfer.
- **A failed morphism is a finding, not a defeat.** Diagnose it against the
  failure table and repair the model, choosing the repair that improves
  overall simplicity.
- **The derived vocabulary is a compilation target, not a user
  interface.** The point-free/categorical form is where reinterpretation
  becomes possible, not where people write. Keep the friendly surface
  (lambdas, ordinary functions) and generate the target form mechanically.
  A *generated* graph, tape, or matrix is fine and often the payoff;
  requiring the **user** to construct one when the host language can
  express the thing directly is the defect.
- **The prover is an amplifier, not a constituent.** The minimum viable
  home for a specification is a comment and the documentation, optionally
  a property test; the minimum viable proof is the derivation read
  backwards, recorded beside the definition. Do not gate phase 1 on
  tooling; reach for Lean/Rocq/Agda when the design has many levels, many
  hands, or laws whose proofs are no longer one-liners.
- **Evidence ceilings are declared, not inferred.** Every artifact states
  what its passing does not prove; a diagnostic never upgrades to semantic
  evidence by citation.
- **Gates only tighten.** Empirical criteria are committed before the work
  and may only tighten afterward; a gate is never weakened to land a step.
- **Honest costs, stated up front:** the method demands up-front clarity
  and some unlearning of presentation-oriented habits; in a host language
  that cannot *state* correctness, a human becomes the checker, repeats
  the same verdict indefinitely, and burns out (the documented reason
  denotational design outgrew Haskell-plus-discipline); the method admits
  no sanctioned ugly fallback, so an equation that will not close is a
  redesign whose schedule risk the practitioner absorbs; and there is an
  institutional cost — from outside, the method reads as a refusal to
  compromise ("Conal needs to learn to compromise better" was a recurring
  performance review). What is *not* a cost: the meaning/representation
  split is what makes aggressive optimization safe — without proof,
  optimization stalls where the author's grip on correctness gets too
  shaky to continue ("proof is the necessary ally of efficiency"), and
  Elliott's maximally permissive image model cost "really none that I
  could notice" in a real-time interactive system. Some types may resist
  the discipline entirely — publish the exception as an open problem
  rather than pretending the morphism holds.
