---
name: abstraction-review
description: |
  Architecture-alignment code review that detects when a change evades the
  codebase's existing abstractions instead of extending or correcting them:
  parallel implementations built beside existing ones, special-case dispatch
  on identity, semantics carried by naming conventions, runtime rediscovery
  of statically known facts, workarounds contorted around a guard, contracts
  shoehorned onto handy mechanisms, and mocks or tests that validate the
  workaround instead of the requirement. Judges architectural fit only, not
  correctness or implementation quality. Use when reviewing agent-authored or
  large-scale changes, or when asked whether a change routes around an
  abstraction, "eats the vegetables", or aligns with the existing
  architecture.
---

# Abstraction Review

A change can work perfectly and still be wrong. This review answers one
question: **when the task did not fit the existing abstractions, did the
change correct the abstraction, or evade it?** Correctness, performance,
style, and general over-engineering belong to other reviews; report findings
only about architectural fit.

## The failure mode

A requirement arrives that the shared path cannot express. The abstraction
says no. An implementer — most reliably an LLM agent, which is an excellent
implementer and a poor architect — takes that "no" as a law of physics and
routes around it: a private mechanism, a special case, a name-sniffing hack.
The code works, and working is the trap. Working code proves an
implementation chain *exists*; it says nothing about whether it is a good
path, and it does not make the design mergeable.

Every route-around embodies a **premise** — "the IR cannot lower sliced
views", "the keys may not match, so search at runtime". Agents apply the
same effort to a sound premise and a bad one, elaborating either into
representations, code, tests, and comments with equal coherence. Volume,
polish, and green tests measure the premise's *blast radius*, not its truth.

So the central question for every divergence from the shared path is:
**real invariant, or accidental limitation?** Most guards encode nothing
deeper than "no input has needed this yet."

## Extension versus evasion

The correct fix is often new machinery too — a new operation, a new typed
structure, a removed restriction. The discriminator is not whether the
change adds a mechanism but *where the mechanism lands*:

- **Extension** teaches the shared path a new word: it enters through the
  sanctioned extension point, is expressed as data, types, or parameters
  flowing through the existing pipeline, is available to every consumer, and
  it *replaces* the need for a special case. The next similar requirement
  gets cheaper.
- **Evasion** adds a private dialect: reachable only from the new case, with
  the shared path left ignorant of it and the special case living alongside
  the general mechanism. The next similar requirement needs its own branch.

The goal state: the next task should be **new data, not a branch with a
hack**. When in doubt, price the next task under each design.

## Evasion catalog

Seven patterns, with detection signatures. `references/case-studies.md`
holds a worked example of each; read it before the first review with this
skill and whenever a match is uncertain.

1. **Parallel mechanism.** A second implementation of a responsibility the
   codebase already owns, specialized to the new case. Signatures: a new
   module whose structure mirrors an existing module; a name that is an
   existing concept plus a qualifier (`BlockedFoo`, `FooV2`, `foo_for_x`);
   two call paths now reaching the same downstream resource; copy-adapted
   bodies; "supports exactly two kinds of X".
2. **Identity dispatch.** Shared code branching on *who* is calling rather
   than *what* is needed. Signatures: conditionals on model/product/version
   names in shared paths; a switch over identities that grows an arm per
   consumer; capability inferred from identity; enumeration where a
   parameter should vary.
3. **Name-carried semantics.** Behavior selected by string-matching
   identifiers, so a name's spelling carries an operation's meaning.
   Signatures: `contains("norm")`, prefix/suffix sniffing, regex over
   symbol or buffer names to choose code paths.
4. **Runtime rediscovery.** A fact the producer knows statically is
   discarded, then reconstructed downstream by search or heuristic.
   Identity is decided at the source, not re-derived at the destination.
   Signatures: candidate lists searched for "whichever exists" where
   exactly one answer must hold; try-cascades and fallback chains;
   "auto-detect" where the upstream stage could simply say.
5. **Guard-as-gospel.** A validation rejection, conservative check, or
   inherited TODO treated as fundamental, with the change contorted to
   satisfy it instead of asking whether it is warranted. Includes data
   laundering: pre-mangling input to slip past a check, then compensating
   on the other side. Signatures: comments of the form "X doesn't support
   Y, so we..."; transform/untransform pairs straddling a checker; more
   effort spent circumventing an assertion than it would take to question
   it.
6. **Contract shoehorning.** The dual failure: overloading an existing
   mechanism with semantics its contract does not cover, because it happens
   to be plumbed everywhere already. Signatures: piggybacked state with
   mismatched size, lifecycle, or ownership; an allocator or transport
   boundary silently becoming a policy decision; one structure serving two
   masters; distinct contracts (live state, history, checkpoint) conflated
   because they ride the same struct.
7. **Test-reality substitution.** Verification bent around the workaround:
   mocks replacing the internal abstraction that should have been extended
   rather than an external boundary; fixtures hard-coding the special case;
   assertions weakened or deleted to get green; tests pinning the
   workaround's mechanism instead of the requirement's semantics. Tests
   written by the author of a premise inherit the premise — treat them as
   amplifiers, not as evidence.

## Procedure

### 1. Establish the intended shape — before reading the diff

- Determine the task from the PR description, commits, or linked issue.
- Find the shared path: how does this codebase already absorb this *kind*
  of change? Read the relevant abstraction's interface and the last one or
  two similar changes (`git log` on the seam is the fastest teacher).
- Write the **null diff**: if the existing design fit the task perfectly,
  what would the change touch? Often: data, config, one new instance of an
  extension point, and little else.
- The gap between the actual diff's shape and the null diff is the review
  agenda. A "add support for X" change that lands thousands of lines of new
  mechanism is presumptively interesting.

### 2. Inventory the divergences

- List every new mechanism the diff introduces: files, types, subsystems,
  conditionals added to shared code, runtime probes, config keys, mocks,
  fixtures.
- For each, find the existing owner of that responsibility: grep for
  siblings, follow the downstream resource both paths touch.
- Sweep for confession markers — the diff usually confesses. Search added
  lines, comments, and any plan documents for: `workaround`, `for now`,
  `instead of`, `doesn't support`, `special case`, `special-cas`, `hack`,
  `fallback`, `temporary`, `until`, `legacy`, `compat`, `parallel`,
  `bypass`, `TODO`. An authoring agent states its accepted premise
  verbatim surprisingly often.

### 3. Interrogate each divergence

State the premise the divergence embodies in one sentence. Then attack it:

1. **Verify the premise against the code, not the prose.** Read the guard
   that said no; `git blame` it; check whether the claimed impossibility is
   real. The "incapable" kernel may already handle the case; the
   restriction may be a blanket conservatism nobody has needed to loosen.
   Models critique a bad premise accurately when asked directly, yet almost
   never question it mid-generation — so ask, explicitly, every time.
2. **Ask the six review questions.** Does this limitation need to exist?
   Can this be made more general? Which abstraction should own this fact?
   Is an existing concept being duplicated? Is this distinction semantic,
   or an accident of history? Will this bite us later?
3. **Name the constant that should be a parameter.** Nearly every case
   reduces to "we assumed there was only one X" — one strategy, one
   geometry, one key. State the assumed-singular thing this task proved
   plural. That is the hole to poke, and the minimal generalization is the
   fix sketch.
4. **Classify:** `EXTENSION` (through the seam — credit it),
   `EVASION` (around the seam), `SHOEHORN` (wrong seam), `JUSTIFIED-LOCAL`
   (genuinely local concern), or `PREMISE-UNVERIFIED` (needs an owner's
   answer — report the specific question, do not guess).

### 4. Check the amplifiers

Tests, comments, and docs elaborate a premise as faithfully as code does:

- Do tests assert the requirement's semantics — ideally against a reference
  implementation or spec — or do they pin the workaround's mechanism? Would
  they still pass if the workaround were replaced by the proper design?
  They should.
- Do mocks stand in for an external boundary (fine) or for the internal
  abstraction the change declined to extend (finding)?
- Do added comments or docs canonize a false premise as fact ("X cannot do
  Y")? Prose spreads an evasion to every future reader, human or agent.

### 5. Report

Order findings by severity: **critical** (parallel subsystem for an owned
responsibility; contract shoehorning that redefines a core mechanism's
semantics; test-reality substitution masking either), **high** (identity
dispatch or name-carried semantics on the shared path; runtime rediscovery;
guard-as-gospel with cross-module reach), **medium** (contained single-site
special case; enumeration growth; unverified premises), **low** (divergence
in leaf code worth a pointer to the right seam; a verified-real invariant
left undocumented).

Per finding:

```
[severity] [pattern] title — file:line
  Premise: "<one sentence>" — verdict: false | accidental | real | unverified
  Assumed singular: <the constant> → should vary as <parameter/data>
  Fix sketch: <the shared-path change, one or two sentences>
  Next-task cost: <what the next similar requirement costs with vs. without the fix>
```

Overall verdict: `ALIGNED`, `ALIGNED WITH FINDINGS`, or `EVADES`. Include a
short **Extensions done right** section crediting genuine vocabulary
extensions — calibration cuts both ways — and a **Premises needing an
owner's answer** list for everything left unverified.

## Defenses that do not count

- **"It works / tests pass."** Existence proof, not path proof.
- **"The abstraction didn't support it."** That is the finding, not the
  defense.
- **"The redesign is too expensive."** Stale reasoning: implementation is
  cheap now. Once the design is named, agents execute this scale of
  refactor in days, not weeks — the scarce input is the design decision,
  which the review just supplied.
- **"It has tests and documentation."** Coherent elaboration measures blast
  radius, not soundness.
- **"This case really is different."** Possibly — but that claim must
  survive step 3's premise verification, not substitute for it.

## Calibration — do not become the dual failure

Demanding maximal generality everywhere is the same disease with opposite
sign (abstraction astronautics). Rules:

- **Require observed evidence.** The requirement in hand *is* the evidence
  that an assumption broke. Generalize exactly the parameter the present
  task proved variable; never demand speculative flexibility for
  hypothetical futures.
- **Minimal hole-poking.** The right fix is usually one concept: one new
  operation, one typed structure carried through the pipeline, one declared
  parameter — not a framework rewrite.
- Fitting the existing abstraction as-is, even slightly awkwardly, is
  success — not a finding.
- Greenfield code with no established abstraction cannot evade one; leaf
  code, one-off scripts, and prototypes are not the shared path. Judge only
  code that claims a lasting place in the architecture.
- A premise that verifies as **real** makes the divergence potentially the
  best available design; then require only that the invariant be documented
  where the next implementer will look.
- If the authoring agent was *instructed* never to touch shared code, the
  finding is about the instructions, not the agent — flag the harness or
  prompt rule that forced the route-around.

## Self-check mode

The same catalog works as a pre-handoff self-review when authoring. After
implementing, run steps 2–4 against the diff and ask of each divergence:
"was this the right design, or a workaround I can now name?" Models answer
that question honestly when it is posed — the failure is that it goes
unasked. Write every diff as if the owner of the shared path will read it,
because with this skill in the loop, one will.
