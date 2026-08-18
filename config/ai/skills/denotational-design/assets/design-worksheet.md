# Denotational design — {PROJECT}

> Status: DRAFT · Prover: {Lean 4 | Rocq | Agda} · Foreign realization:
> {none | Rust | …} · Working tree pinned at: {rev}
> Line numbers are hints; paths and quoted text are the authority.

## 0. The end-to-end statement

> ⟦running system⟧ ≡ ⟦{mathematical object}⟧ at the equalities named in §5.
> Everything below is bookkeeping to make this one line checkable in
> pieces.

## 1. The principal mathematical object (K1)

**The domain sentence** (the domain's own words, no types — what *is*,
not what does):

> …

**Candidate notions and their subtractions** (each candidate names the
technology of production/storage/display it smuggles in; each subtraction
names the level where the removed thing reappears as a representation):

| Candidate | Baggage | Reappears at |
|---|---|---|
| | | |

**The object** (one line; may be non-computable):

```
{Name} := …
```

**Generalizations taken and what came free** / **generality declined and
why**:

- …

**Identity test**: the domain's most primitive observation denotes `id`
via: …

## 2. The fundamental operations (K2)

Classes the object inhabits (weakest sufficient, finely factored):

| Class | Why this and not weaker/stronger |
|---|---|
| | |

Operations (each a class method, or justified bespoke):

| Operation | Class method of… / justification |
|---|---|
| | |

Semantic choices carried by wrapper types (bias, direction, monoid): …

## 3. The fundamental theorems (K3)

| ID | Statement | Downstream force | Defect lineage |
|---|---|---|---|
| | | | |

**Non-theorems** (plausible but false; do not assume the converse):

- …

## 4. Derived operations and theorems

What the algebra gives free; obligations collapsed by meta-theorems;
dilemmas dissolved:

- …

## 5. The representation tower (K4)

| Level | Object | Carrier | ≡ on its leg | Verification style |
|---|---|---|---|---|
| L0 | {mathematical object} | — | exact | proof |
| L1 | | | | |

**Negative boundaries**:

- Nothing above L… may mention …
- Nothing below L… may introduce …

## 6. Denotations (per level)

| Level | Meaning function | Signature | Invertible? | Notes |
|---|---|---|---|---|
| L1→L0 | | | | |

Abstract-type discipline: representations export smart constructors + the
meaning function only.

## 7. Operations per representation (K5 — definitions are kernel)

Per level: the homomorphism equations and their solved forms (keep the
derivations; they are the proofs' skeletons).

### L1

| Operation | Equation | Solved definition | Derivation note |
|---|---|---|---|
| | | | |

**Unclosed equations and their diagnoses** (findings, not defeats):

- …

## 8. Commuting theorems (K6 — statements are kernel; proofs are checker class)

**Obligation ledger**:

| Law | Home | Placement (P/C/T) | Status |
|---|---|---|---|
| | | | |

**Axiom policy** (where the mathematics ends, and what covers each gap):

- …

## 9. Realization acceptance (empirical)

Per realization, an acceptance card **committed before the work**:

| Realization | Oracle | Criteria/thresholds (derivation cited) | Rungs | semantics_unchanged_by |
|---|---|---|---|---|
| | | | | |

**Evidence-ceiling table** (each evidence kind → maximum defensible claim):

| Evidence kind | Ceiling |
|---|---|
| | |

## 10. Cross-language fidelity

Oracle doctrine: the single fresh semantic oracle is …; everything else is
comparison evidence only.

Strategies in use (golden vectors / morphism property tests / differential
driver / stage ladder / schema lockstep / refl-by-construction / FFI
probes):

| Strategy | Artifact | Status |
|---|---|---|
| | | |

Stage ladder (one owner per stage; localization is diagnostic only):

| # | Stage | Owner |
|---|---|---|
| | | |

## Kernel census and governance

| Class | Artifacts (files) | Gate |
|---|---|---|
| K1–K3 | | owner review (digest row) |
| K4 | | owner review |
| K5 definitions | | owner review |
| K6 statements | | owner review |
| proofs, instances, derivations | | checker: {prover} |
| K5 realizations | | empirical: acceptance cards |

Review mechanism: {hashes file + CODEOWNERS | digest manifest + standalone
checker}. Measured kernel size: {lines}.

## Decision register

| # | Question | Options | Ruling (dated) / RECOMMENDED / DEFERRED | Reversal cost |
|---|---|---|---|---|
| | | | | |

## Open problems (published, not papered over)

- Types resisting the discipline; unclosed equations; structural evidence
  ceilings: …
