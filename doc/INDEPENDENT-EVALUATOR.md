# The Independent Evaluator

**Purpose:** define the one mechanism by which a unit of work in this programme
receives an independent, clean-context `fess` verdict before it is treated as
done, and the procedure by which that verdict is recorded, acted on, and — when
the evaluator is wrong — safely overruled.

**Status:** the mechanism this document describes is not new. It has been in use
across the programme since the design phase; this document formalizes it and
fixes the verdict-recording procedure so the practice is repeatable and its
verdicts live beside the gate evidence rather than in a session's memory.

**Standing authority:** `CLAUDE.md` ("follow Wiggum: … independent fess audit …"),
`doc/FLEET-IMPL-WIGGUM-PLAN.md` DoD-6 ("The final work commit passes an independent
`fess` audit"), and issue #15's review rule ("PAL consensus was explicitly waived;
independent fess and partner review remain required after each work unit").

---

## 1. Why this exists — the failure mode it defends against

This programme has one recurring, expensive defect class: **a gate that reports
success while covering nothing.** It is not caught by reading code — the code
looks correct — only by asking of each gate, *"does it fail when it should?"*
and running the case that must make it fail. Five instances have landed and been
removed so far:

1. A `shfmt` per-file loop that exited with the status of its **last** iteration,
   so a 45-line diff on `bin/update-agents` passed green (#46).
2. A bare `nix fmt` that invoked the formatter with **no paths, on empty stdin**,
   formatting nothing and reporting success (#30).
3. **Eleven flake outputs aliased to other outputs** while their names claimed to
   be distinct evidence — a check whose name promised evidence it did not produce
   (#48).
4. An accumulator that appended failures inside a **subshell**, so
   `test/bin/quality`'s own summary discarded them and under-reported ("1 suite failed"
   when two had) (#46).
5. A routing test that called `nix_flake_output_for_host` with **raw hostnames**
   instead of the **normalized label the real caller passes**, so it exercised a
   path no caller takes and missed a live `return 1` on every work machine (#37).

A sixth, adjacent lesson from the same period is quantitative rather than
structural: the parity oracle's *derived* counts contradicted the corpus's
*asserted* counts — hera is **414**, not 412; the portable systems are
**30/30/30**, not 43/37/38 (#19). An asserted number that no one re-derived was
simply wrong.

The independent evaluator exists to catch exactly these before a unit is called
done. Its checklist (§4) encodes both lessons as hard requirements: **a proven
negative case per gate**, and **re-derivation of every quantitative claim.**

---

## 2. What "independent" and "clean context" must mean

A verdict is only worth something if the evaluator could actually have said "no."
Two properties are load-bearing; neither is optional.

**Independent — the evaluator did not do the work.** The party producing the
verdict must not be the party whose claims are under audit, and must not be
grading its own output. The implementing agent auditing itself is a *self*-audit
(useful, but not what DoD-6 requires). Independence is a property of *who runs
the audit*, not of the rubric.

**Clean context — the evaluator did not inherit the maker's reasoning.** The
evaluator starts a fresh context and is handed only:

- the **requirements** the work was meant to satisfy (exact wording where
  practical),
- the **commits under audit** (SHAs and the files each changed), and
- the **claims** the maker made about the work ("tests pass," "handles X,"
  "parity preserved," the asserted counts).

It must **not** be handed the maker's chain of reasoning, its justifications, or
its private narrative about why the work is correct. That reasoning is precisely
what a clean audit must be able to contradict; importing it re-creates the
self-audit it was meant to replace. Hand it the *artifact and the claim*, never
the *rationalization*.

A corollary on framing: the `fess` rubric is written in the second person
("assume **you've** been dishonest"). When delegated, this is reoriented — the
evaluator audits **the maker's** claims, not its own. The `fess-auditor` agent
already performs this reorientation ("You are a delegated honesty auditor …
report the results back to the main session").

---

## 3. The mechanism

Establish **one** independent clean-context evaluator, chosen in this order of
preference. No credential is required to obtain a valid verdict; option (b) is
the mechanism, and it needs none.

**(b) — preferred: the local `fess` skill, run from a separate clean-context
subagent.** This is the standing mechanism and requires no external credentials.
It is available in this environment as:

- the `fess` command (rubric at `commands/fess.md`), invoked inside a subagent;
  and
- the `fess-auditor` agent, whose sole job is to run that rubric in a sub-agent
  and report an evidence-backed verdict to the caller.

Both are provisioned, not ad hoc: the Nix-managed agent oracle
(`doc/migrations/nix-managed-agent-oracle.md`) carries `agent:fess-auditor` and
`command:fess` as managed leaves with recorded hashes. Spawning the subagent with
the §2 context snapshot yields an independent, clean-context verdict.

**Fallback — PAL (multi-model), environment-only.** If a multi-model reviewer is
wanted, PAL may be used, but note two things. First, its provider credentials —
the variables enumerated in **issue #28's Scope and Verification sections** —
must be supplied as **environment-only** values: never in argv, logs, the Nix
store, generated files, or any tracked file, and provisioning them is a human
action. Second, PAL **consensus** is a *waived* gate in this programme (issue #15);
PAL is therefore only ever an alternative *reviewer*, never a re-imposed gating
requirement. Do not treat PAL's availability, or its credential state, as a
condition for closing any work: option (b) discharges the requirement on its own.

**Fallback — a designated human reviewer.** Always admissible; the same verdict
contents (§5) apply.

### Running option (b)

1. Choose the audit range. Read the commit descriptions and select **1 to 10**
   recent commits. One commit for isolated, self-contained work; expand the range
   when a description points to follow-up work, stacked changes, refactors, shared
   infrastructure, earlier groundwork, or claims whose truth depends on previous
   commits. Record the chosen SHAs and one line on why that range was chosen.
2. Assemble the §2 context snapshot: requirements (exact wording), the commit SHAs
   and their changed files, and the specific claims made — including every
   asserted number. Preserve exact wording for requirements and claims. If the
   context is large, hand a dense summary **plus** the exact excerpts, so intent
   is not lost. Do not include the maker's reasoning.
3. Spawn the subagent (`fess-auditor`, or a general subagent instructed to run the
   `fess` rubric) with that snapshot and the §4 additional mandate.
4. Receive the verdict and record it per §5 before acting on any finding.

### Live acceptance demonstration — 2026-07-29

Issue #28's clean-context mechanism was exercised end to end on real commit
`64064f0c` (Darwin surface baseline generator):

- a `fess-auditor` was spawned with `fork_turns=none` and therefore inherited no
  implementing-agent conversation;
- its only input was the exact requirements, commit/range and changed files, plus
  the maker's stated claims and numbers;
- it returned **request changes**, re-derived the claimed 104 Nix / 35 shell / 42
  Python files, eight suites, 22 gate tests and 14 Darwin tests, and found substantive
  provenance, credential-boundary, Git-environment, transaction and test gaps;
- each finding was verified rather than obeyed blindly, then fixed in signed code
  commit `494feeeb` plus exact schema-v2 baseline follow-up `7f9b00f4`;
- the final paired state passed every `test/bin/quality` suite with nine Python suites,
  live Darwin comparison and consumer evaluation 5 ran / 0 skipped.

No PAL path or credential was used or needed. This is the acceptance example for
option (b): a clean evaluator was able to say no, its quantitative claims were checked,
and its verdict changed the delivered artifact. Per §6, the finding-fix commits were
verified directly rather than recursively spawning audits of audits.

---

## 4. What the evaluator must check

The evaluator applies the full `fess` rubric (`commands/fess.md`): stubs and
fakes, vacuous tests, mock/fixture drift, silent failure and error swallowing,
suppressions, fallback smuggling, spec drift, scope creep, documentation drift,
the verification gap, and loose ends. Beyond that rubric, this programme requires
two checks that the general rubric does not spell out and that no amount of
reading can satisfy:

### 4a. A proven negative case per gate — mandatory

For **every** gate, check, or test the unit adds or relies on to claim success,
the verdict must record a **demonstrated negative case**: the specific
perturbation that makes the gate **fail**, run, with its output. Reading the gate
and concluding it "looks correct" does not satisfy this — all five defects in §1
passed inspection. Acceptable negative-case evidence looks like:

- re-arm the exact broken pattern the gate defends against and show the gate goes
  red (e.g. #22 re-created the `a3cc3843` positional-argument seam on scratch
  copies and showed the consumer eval fails and *localizes*);
- remove the fix and show the check fails naming the offender (e.g. #36 removed
  the `follows` edge, re-locked, and the purity walk failed naming the route);
- confirm a scope claim by proving the new scope is a **strict superset** of the
  old, so nothing silently left coverage (#46).

A gate for which no failing case was produced is treated as **unproven**, and the
unit is not done. State it plainly rather than inferring coverage. The evaluator
must also confirm the gate **exercises the real call path** — the routing test in
§1(5) passed because it called the function the way the *author* imagined, not the
way the *caller* invokes it. "Would this still pass if the code under test were a
stub of the right shape?" applies to gates as much as to tests.

### 4b. Re-derive every quantitative claim — mandatory

Commit messages and issue comments in this repository assert numbers: file
counts, reference counts, package multisets, node counts, test counts. The
evaluator must **re-derive each one from the source of truth**, not accept the
asserted value. Package/parity counts are re-derived against the parity oracle
(`test/bin/parity-baseline`, baseline under `test/baseline/`), not against prose; a
count in a commit message is a claim, the oracle is the evidence. This is the
check that found the 414-not-412 / 30-not-43 discrepancies (#19). A number the
evaluator could not re-derive is a **verification gap**, reported as such.

### 4c. Security — no credential named as required, no key literal added

The evaluator confirms the unit named **no** credential, key, or token as a
requirement, and added **no** key material to the tree. The concrete check is the
credential-literal grep given in **issue #28's Verification section**, run over
the files this unit added or changed: any new occurrence that is a **value
assignment** is a failure. (Pre-existing mentions of credential *variable names*
in documentation are not literals and are not failures; the test is whether a
*value* was introduced, or a credential was made a *requirement*.) When PAL is the
chosen reviewer, the evaluator additionally confirms its credentials are
environment-only and absent from argv, logs, the store, and generated files.

---

## 5. The verdict — where it lives and what it must contain

**Where it lives.** The verdict is recorded in **two** durable places, matching
how closed issues #46, #22, #24, and #36 already record their evidence:

1. **The tracking issue's status comment** — the `## Done — <sha>` (or `## Status
   — <sha>`) comment on the GitHub issue, alongside the gate evidence. This is the
   authoritative record and is where a reader looks to see that the unit was
   audited.
2. **The Wiggum handoff** — a one-line entry in the current handoff's "Closed this
   session" / "Landed" table, and any durable lesson under "Findings worth
   carrying forward." The handoff is the session-spanning index; the issue comment
   is the detail.

Partner-review observations (`doc/observations/`, drained per DoD-7) are a
**separate** channel and are not a substitute for the fess verdict; the two run
independently after a work unit.

**What a verdict must contain.** A verdict that omits any of these is incomplete:

- **Range and mechanism.** The audited SHA(s), the one-line reason for the range,
  and which mechanism produced the verdict (option b subagent / PAL / human).
- **Independence and clean-context attestation.** A statement that the evaluator
  did not do the work and received only requirements + commits + claims (§2).
- **Per-category findings** with exact `file:line` citations. `none` is written
  only for a category actually checked, never as a default.
- **Negative-case evidence per gate** (§4a): for each gate, the perturbation run
  and its failing output — or an explicit note that no failing case was produced,
  which blocks done.
- **Re-derived quantitative claims** (§4b): each asserted number, the value the
  evaluator re-derived, and agreement or the discrepancy.
- **Verification gaps**: every claim not proven from available evidence.
- **Security attestation** (§4c): the credential grep result over the unit's
  changes.
- **Disposition**: for each actionable finding, whether it was verified,
  fixed (with the fix SHA), or overruled with reason (§6).

A worked template is in the appendix.

---

## 6. Acting on a verdict — including when the evaluator is wrong

**An evaluator's finding is a claim, not a command.** Evaluators in this
programme have been right (the adversarial pass in #36 correctly flagged
`*_is_fully_fetchable` as overclaiming a fetch that never happens) and have been
wrong or merely opinionated (a reviewed spec's proposal to pin `obr` to a newer
revision was flagged and, on verification, the `follows` fix was taken instead in
#24; #35's adversarial pass returned `needs-correction` on points that then
required their own checking). Because both happen, the procedure is:

1. **Verify each finding before acting on it.** Convert uncertainty into a
   verification step — run the case, re-read the cited `file:line`, re-derive the
   number — rather than assuming the finding is either right or wrong. A finding
   that survives verification is real; a finding that does not is recorded as
   **overruled, with the evidence that refutes it.**
2. **A wrong finding must never force a change.** Do not weaken a correct gate,
   delete a valid test, or restructure working code to satisfy a finding that
   verification did not confirm. Silencing a *correct* gate to make a *wrong*
   finding go away is itself the §1 defect class, one level up. If acting on a
   finding would lower the bar, stop and record the overrule instead.
3. **Fold real fixes into the work and commit them normally**, as a separate fix
   commit with its own message. Do **not** separately re-audit a commit whose only
   purpose is to fix findings from a prior fess run, nor partner-cleanup's own
   cleanup commits — auditing fixes of fixes loops without progress.
4. **Run one final audit over the last work commit before declaring done**, even
   when the most recent commits were themselves fixes. This is the DoD-6 audit.
5. If a finding is genuinely ambiguous and verification cannot settle it without
   guessing intent, **escalate** rather than guess — this matches the programme's
   stop-and-escalate discipline.

---

## 7. When it runs

After **a logical unit of work is committed** and **before it is treated as
done** — that is, before its issue is closed (class A) or before its status
comment claims the work landed and verified (classes B–E). Concretely, in the
Wiggum cadence: one logical unit → signed commit → **independent fess audit
(this document)** → partner-observation cleanup → local-currency checkpoint →
durable handoff update. The final work commit of a unit always receives the audit
(DoD-6), even if it followed a run of fix commits.

---

## 8. Security constraints (binding)

- No key material, credential, or token is a **requirement** of this mechanism;
  option (b) needs none.
- No credential **value** may appear in the tree, in argv, in logs, in the Nix
  store, or in any generated file. The PAL fallback's credentials, if used, are
  environment-only and human-provisioned.
- The verification for the mechanism itself is the credential grep in **issue
  #28's Verification section**: over the changes that establish the evaluator, it
  must find no key literal. This document names no credential value and no
  credential variable, precisely so that grep stays clean over the file that
  installs it.
- Standing `CLAUDE.md` security rules apply unchanged: do not decrypt SOPS
  content, read runtime secret files, dump credential settings, or print
  API/auth payloads. The evaluator inspects structural metadata and
  field-targeted checks, never secret values.

---

## Appendix — verdict template

```
## fess verdict — <issue/unit>, commits <sha>[..<sha>]

Range: <sha(s)>; chosen because <one line>.
Mechanism: independent clean-context <fess-auditor subagent | PAL | human>.
Independence/clean-context: evaluator did not perform the work; received
  requirements + commits + claims only.

Findings (severity-ranked, file:line):
- <category>: <finding @ path:line>  — or `none (checked)`.
- …

Negative case per gate:
- <gate>: perturbation <what was re-armed/removed>; result <failing output>.
- …  (any gate with no failing case demonstrated blocks "done".)

Quantitative claims re-derived:
- <claim>: asserted <n>, re-derived <n> from <source of truth> — agree | DISCREPANCY <detail>.

Verification gaps: <claims not proven from evidence>.

Security: credential grep over this unit's changes — <no literal | detail>.

Disposition:
- <finding> → verified, fixed in <sha> | overruled: <refuting evidence>.
```

## Appendix — end-to-end precedent in this programme

The mechanism has already produced real verdicts on real commits without PAL:

- **A verdict that changed history.** `a88a77ba` ("feat(sources): execute compound
  catalog updates") was **found UNSAFE by fess audit** and reverted as `a98385b9`;
  its findings became Phase 1.1 requirements
  (`doc/FLEET-PROGRAMME-CROSS-STREAM.md` §X1).
- **A verdict that produced a fix commit.** An AI-nix reintegration fess audit
  found "an unjustified callable type suppression and incomplete safe-lock branch
  coverage"; commit `646cdc6` fixed both
  (`doc/AI-NIX-REINTEGRATION-WIGGUM-HANDOFF.md`).
- **A verdict that caught documentation drift.** A later fess audit "caught and
  corrected one inaccurate Kaleido test comment"
  (`doc/AIPERF-WIGGUM-HANDOFF.md`).
- **The design plan itself** was "audited by an independent `fess` pass" with PAL
  explicitly waived (`doc/FLEET-DESIGN-PLAN.md` §2).
- **Closed issue #22** carries "Independent fess pass" as a satisfied acceptance
  criterion.

None of these required PAL credentials.
