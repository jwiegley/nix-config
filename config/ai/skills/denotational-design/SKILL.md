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

## When to use, and when not

Use this skill when a vocabulary is being invented and the type will be
composed with itself — a library, DSL, compiler, runtime, protocol, or any
system whose core values combine into more of themselves. When only one
type in a design carries composition, that is the one type to denote.

Do NOT apply the full method to I/O glue, config parsing, log formatting,
migration scripts, test scaffolding, or build tooling — it produces
ceremony. The proportionate minimum for borderline cases: name the
mathematical object and write one line of `⟦·⟧`, then stop. The cost is a
sentence; the benefit is that the type now has an essence a reviewer can
disagree with.

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
5. **Candidate representation objects** — the tower from the mathematical
   object down to the final realization, one level per concern.
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

## How to work each phase

- **Method** (phases 1–8): the distilled Elliott discipline — the
  subtraction opening, the denotation repertoires, the shape→classes rule,
  the four-step solving loop, the failure-diagnosis table (a morphism
  equation that will not close is the method's most valuable output), and
  the completion tests — is in `references/denotational-method.md`. Consult
  it before and during every design conversation; the diagnostic table is
  the part to have open when an equation resists.
- **Prover** (phases 6–8): the design defaults to Lean 4, with Rocq and
  Agda as supported alternatives. Selection criteria, per-prover idioms for
  the method's artifacts (meaning functions, morphism statements,
  index-by-denotation, proof style), and extraction paths are in
  `references/provers.md`. Ask the user's preference in phase 1; do not
  re-litigate it later without cause.
- **Realizations** (phases 9–10): acceptance cards committed before the
  work, sampled-square evidence with pinned comparison tuples, evidence
  ceilings, and the bisimulation strategies for a foreign-language
  realization against its oracle are in
  `references/realization-and-bisimulation.md`.
- **Governance** (all phases, scaled to the project): the knowledge-kernel
  partition (what humans review vs what checkers admit vs what empirical
  gates accept), the spec-tower file scaffold, law IDs and the obligation
  ledger, judged decision records for architectural forks, and the
  scale-down table for small projects are in `references/governance.md`.

## The worksheet

Produce the design as a living document seeded from
`assets/design-worksheet.md` — copy it into the user's project (e.g.
`doc/design/denotational-design.md` or split per level as it grows) and
fill it in phase by phase. The worksheet's sections mirror the phases, so
an empty section is a visible unmet obligation rather than an absence
nobody notices.

## Ground rules (hold these in every phase)

- **Meaning constrains implementation; implementation never constrains
  meaning.** A performance or convenience pressure may change a
  representation; it may never change a denotation. Where a representation
  cannot support an operation, the failure is information and is recorded —
  never patched by weakening the level above.
- **Solve, do not verify.** The homomorphism equations are the entire
  specification; implementations are read off their solved forms.
- **The specification may be unrunnable.** Prefer the non-computable
  meaning that is clear over the executable one that is compromised; the
  spec is often a valid, slow implementation, and everything after it is
  semantics-preserving refinement.
- **Laws come "already paid for" only while the type stays abstract.**
  Every value must arise through the interface; a leaked constructor voids
  the free laws.
- **A failed morphism is a finding, not a defeat.** Diagnose it against the
  failure table and repair the model, choosing the repair that improves
  overall simplicity.
- **Evidence ceilings are declared, not inferred.** Every artifact states
  what its passing does not prove; a diagnostic never upgrades to semantic
  evidence by citation.
- **Gates only tighten.** Empirical criteria are committed before the work
  and may only tighten afterward; a gate is never weakened to land a step.
- **Honest costs, stated up front:** treating a type as its model cuts off
  operational-performance reasoning (a separate semantics-preserving fast
  path is eventually always needed); the method demands up-front clarity of
  thinking and some unlearning of presentation-oriented habits; and some
  types may resist the discipline entirely — publish the exception as an
  open problem rather than pretending the morphism holds.
