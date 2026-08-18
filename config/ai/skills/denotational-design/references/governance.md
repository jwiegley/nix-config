# Governance: the knowledge kernel, the spec tower, and planning

How a denotational design stays true once many hands — especially AI
hands — work on it. Battle-tested at program scale (a 724-item,
four-backend inference-compiler conformance program); every mechanism here
carries a scale-down form. Provenance note: this file is a program-scale
extension of the method, not Elliott's own practice — see SKILL.md — so
cite it as engineering, never as him.

## The knowledge kernel (K1–K6)

The human-review surface is a **closed enumeration** of six artifact
classes:

| Class | Artifact |
|---|---|
| K1 | the initial mathematical object |
| K2 | the operations on that object |
| K3 | the theorems over object and operations |
| K4 | the ordered sequence of representation objects, initial → final |
| K5 | the **definitions** of the operations on each representation |
| K6 | the **statements** of the commuting theorems between adjacent representations |

Three rules follow:

1. **Kernel changes are reviewed by humans.** Everything else is
   AI-explorable.
2. **Work whose meaning is pinned by K6 — proofs, instances, derivations,
   migrations, lints, fixtures — is validated by named checkers, never by
   review.** The proof assistant checks a proof better than any reader.
3. **Realizations of K5 operations — kernels, emitters, schedulers,
   optimizations — are accepted empirically**, on pre-committed,
   tighten-only criteria, because K5 and K6 fix exactly what those tests
   must test.

The economics behind rules 1–2 are a cost/value asymmetry, not just
review-surface accounting: proof complexity is paid once, by the author,
and the machine checks it; theorem complexity is paid by every user on
every use, forever, and no machine can check it ("I care how hard it is to
build a proof because that's the cost of it, and I care how simple the
theorem is because that's the value of it"). Spend freely on proof
difficulty, ruthlessly on statement simplicity. Corollary lint: **the
specification must not be the code** — a theorem whose statement is the
implementation carries no value ("that specification should not be the
code itself. Otherwise, it's not useful").

Load-bearing subtleties: K5 *definitions* are kernel, K5 *realizations*
are not; K6 carries statements only (proofs are checker class); K6 is
defined relative to K4 adjacency — new theorem statements without a new
representation object are *not* K6 and get their own named gate rather
than silently growing the kernel. The design metric: **a change is better,
all else equal, when it shrinks the human-review surface toward exactly
K1–K6** — and shrinkage must be *measured*, not estimated (one project's
"250-line" kernel estimate measured at 1,500–3,000 lines).

**Mechanize the review rule.** A digest manifest (one sha256 row per
kernel file) owned by a small standalone checker — never bolted onto an
existing pinned trust anchor — plus a CODEOWNERS rule: a changed kernel
file fails CI until the owner reviews the file-level diff and re-mints the
digest row in the same commit. Proofs stay outside the manifest (a proof
edit must not re-mint an owner-review signal). Mark files
FOUNDATIONAL/DERIVED so the review rule is readable off the header.
Grant bulk acceptance explicitly where a file is mechanical plumbing.

**AI-artifact admission.** One table: artifact class | certificate it
carries | checker of record | lane. An artifact without a certificate
enters no lane and cannot merge. Checkers are blind to provenance —
"record everything, consult nothing." An artifact may never author the
expectation it is tested against. "The agent is never asked to argue that
an artifact is correct; it is handed the commuting equation and asked to
produce the object that closes it."

## The spec tower (file scaffold)

Decadal-numbered files, insertion room built in:

- `000` — index, method, tower diagram, the kernel table, reading paths;
- `010` — the mathematical object and its first refinement (K1–K3 home);
- `020` — the level table, the denotations, the square discipline (K4/K6);
- `030…0N0` — one file per representation level, descending (K5 homes);
- then: the empirical-evidence doctrine, the verification-placement
  ledger, a **reconciliation file** (for retrofits: tower object → what
  realizes it today; everything classified absorbed / superseded (with
  lineage — "the folklore was correct practice awaiting its invariant") /
  orphaned; declared regenerable), and a **decision register**.

Conventions that keep it honest: YAML frontmatter with status and
FOUNDATIONAL/DERIVED; each level file ends with "Implementation notes
[DERIVED]: Exists / To build / issue anchors" so the spec cannot quietly
describe a system that does not exist; every code claim pinned to a named
working tree with the disclaimer "line numbers are hints; paths and quoted
text are the authority." **Generate the figures**: diagrams in the tower
should be produced by an interpretation of the same code they document —
"the way I generated the pictures was I compiled the Haskell code I showed
you into those pictures" — so a figure cannot drift from the artifact; a
hand-drawn diagram of a system with a graph interpretation available is an
unpinned claim.

**Three tables carry the method**: the level table (Level | Object |
Carrier | Exactness); the square table (Leg | what `≡` means here |
verification style | status today — equality chosen per leg and defended);
the obligation ledger (Law | Home | Placement: Proof/Contract/Test |
Status — drift against a column is a placement defect).

**Law IDs as currency**: single-letter families, one home file each,
stable names (renames are register entries; never reuse a letter across
families); every law anchored to a real defect it makes unrepresentable;
a non-theorems list; code citing law IDs at enforcement points
(`-- [spec: T2]`) with a CI lint closing the loop both directions — "a law
that code cannot cite will drift." Define levels *negatively* too
("nothing above L4 may mention floats, devices, or time") so violations
are diagnosable defects with owners.

**Authority partition** with explicit "does not own" columns: the spec
owns meaning; the design owns how (module layout, checkers, migration
shape, gate placement); the plan owns scheduling. No silent spec
amendment; when code and spec disagree about meaning, "the disagreement is
a defect in one of them and must be resolved explicitly — never silently
in favor of the code." Supersede, never rewrite: decisions change only by
appending a dated ruling.

**Vocabulary drift.** A design's *names* get adopted far more readily than
its *meaning* — Elliott on his most-cited work: "almost 100% of what
people call functional reactive programming… fundamentally missed the idea
and reinvented the bugs that I invented FRP to solve." When a downstream
component, team, or paper claims to apply this design, check that the
denotation survived, not that the vocabulary did; an adopter who kept the
type names and dropped the meaning function has silently amended the spec.

**The messy-domain objection** arrives as a claim about the domain rather
than the method ("our data really is unstructured collections tuned to the
machine"). It does not exempt a design; it relocates the mess. Elliott's
answer, scripted: "I say: what does it mean? What's a mathematical meaning
that is precise, elegant, and adequate? There may be some really important
reason to use certain data structures and match the machines — but none of
that do I want to appear in the API. All of that is representation. Those
are important things *after* I've found the API."

## Design documents (one per level/concern)

Fixed eight-heading template, so a missing discharge is a missing heading:
**Objective** (a `Law | what this section supplies` table plus explicit
non-supplies routed to tracker ids) / **Current state** (verified
file:line evidence; correct inherited premises in place) / **The design**
/ **Migration** (numbered increments M0…Mn, each with an invariant gate,
an artifact-churn column, a declared fallback; byte-moving events named as
owner decisions) / **Validation of AI-generated work** (artifact→checker
table) / **Kernel boundary** (K-classes touched; owner-read artifacts with
*measured* sizes; checker-validated surface; empirical criteria) /
**Rejected alternatives** (including the section's own prior revision) /
**Open questions for the owner** (numbered; each names what it blocks).

**Judged decision records** for architectural forks: N independently
authored candidate documents (authors do not read each other); ≥2 judges
under explicitly named opposed lenses (soundness: strongest machine-checked
guarantee per new trusted component; delivery: adoptability, rollback,
gate survival); every claim re-verified at one pinned revision; per-judge
numeric scores; each judge names "the failure the author missed"; binding
= combined score with the losing lens's grafts carried; when two judges'
opposed bases name the same object, that object is the binding. The record
is falsifiable — audit its score distribution for degeneracy; a corrected
record forces re-derivation, not patched citations.

## Planning integration

Turn the design into tracked work with these properties:

- **Goal verbatim.** The owner's exit criterion is frozen in its own file
  and quoted, never paraphrased.
- **Definition of done in two non-tradeable halves** — per-target exit
  gates AND always-green invariants recomputed at the publication tip —
  published by exactly **one sink item** whose negative fixture is "all
  columns green, one invariant unverified, must fail."
- **A `kernel_gate` class on every item** (owner / checker / empirical /
  none) with a regenerated census — the review surface as a number.
- **An evidence-ceiling sentence on every item**: what its completion does
  not prove.
- **An anti-gaming trap list written before decomposing**: the concrete
  false-completion moves available in this project's shape (counting items
  instead of evidence; stale-tuple citation; diagnostic upgraded by
  citation; the system naming its own tolerance; a detector with only
  true-positive fixtures; a blocked resource reported green; a shrunk
  denominator).
- **Gates enforced by edges, never prose.** Compute the set of items that
  do *not* transitively block a declared gate; justify each survivor by
  name or add the edge. Never assert a corpus property ahead of the checker
  that establishes it — "the sweep, not the paragraph, makes it a fact."
- **Owner dockets** for a serial human reviewer: batch questions by
  downstream-unlocked mass; each ruling = quoted question → verdict →
  accepted consequences → files changed → edges released, with the footer
  that an answer is not evidence the answer is right. Where work must start
  ahead of ratification: a **build-ahead register** — authorized categories
  (pure checkers, registries, censuses, scaffolding), forbidden ones
  (kernel-statement commits, pinned-artifact moves, evidence captures),
  predicted exposure, every start listed, expiry at ratification, closed
  out with actual re-cut count vs prediction.
- **Depth is not duration**; the wave map is not a staffing plan.

## Scale-down table

| Mechanism | Program scale | Small-project form |
|---|---|---|
| Kernel census | six-class table + tree partition lint | one page listing the K1–K6 artifacts by file |
| Review gate | digest manifest + standalone checker + CODEOWNERS | a hashes file + CODEOWNERS |
| Artifact admission | class/certificate/checker/lane table | four rows |
| Decision record | N candidates × ≥2 judges | two candidates, two lenses |
| Ladder | nine stages, instrument-computed routing | three stages, three owners |
| Plan | JSONL corpus, materializer, integrity sweeps, audits | ~20 items in one file with the gate class + ceiling per item |

What never scales down: the closed kernel enumeration; per-change kernel
boundary declarations; acceptance criteria committed before the work and
tighten-only; checkers blind to provenance; declared evidence ceilings;
one sink for "done"; and the rule that no gate is weakened to land a step.

## Selling it, and surviving it

The governance above governs the work; getting permission to do it is a
separate problem Elliott talks about at length.

- The question to put to a stakeholder who objects to the cost of proof:
  "is it *proof* that's the problem, or is it *truth* that's the problem?"
  — with the reductio in reserve (give up correctness and you get ideal
  efficiency instantly: erase everything; it runs infinitely fast and has
  no known bugs).
- Proof is the ally of performance, via the optimization-ceiling argument:
  without it, optimization stalls where the author's grip on correctness
  gets too shaky to continue.
- The risk-ratio caveat, in his voice: there is a real cost, "and you do
  this kind of risk ratio, and some things we just don't bother, some
  things we do."
- The reception warning: simplicity requires education to appreciate, so
  expect the simplified design to be received with irritation rather than
  gratitude — and expect the institutional feedback "learn to compromise
  better."
- Counsel for the gap between knowing a plan is wrong and having a better
  one: speak in the gap anyway — "a lot of people are not willing to speak
  when they're in that gap" — even if all you can propose is a pause to
  think.
