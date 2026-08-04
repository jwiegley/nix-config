# The Engineering Value of an Alexey-Calibre Review

What Alexey transmits through review is not a comment style — it is an engineering discipline. Every principle carries verbatim evidence.

______________________________________________________________________

## 1. Development practices enforced

### 1.1 A test must mechanize its expectations

If a human has to eyeball the output, or the assertion is loose enough to pass vacuously, it is not a test. In an ML compiler where correctness is numeric and subtle, a vacuous tolerance or console-log "test" produces false confidence that is worse than no test; exact mechanized deltas make regressions undeniable.

> "reflect on what you are looking for when you read the output of this test case, and write down a program that checks the same thing. Ideally we would cover every field recorded by the metrics capture mechanism." [GitHub, metrics-capture test, chunk-003]

> "This tolerance doesn't lead to a meaningful test. TVDs of 15%-30% seem anecdotally typical for logits from different (English) prompts, so we're really not catching much agreement here at all." [GitHub, PR 344]

> "Well, turns out this test doesn't actually test anything!" [GitHub, PR 1546]

### 1.2 A skip must be a fail — coverage may never be lost silently

Silent skips rot the safety net invisibly: the suite stays green while the thing it guarded goes untested. Any deleted, disabled, or shrunk test must be explicitly justified.

> "if a model has tests but the test runner can't read the weights, that should be a fail, not a skip." [Slack, #software]

> "I worry about the potential for silent loss of coverage here. Can we afford to just make this fail, and include a comment with instructions (from your PR description) on how to fix it?" [GitHub, PR 195]

> "This test case was intentionally re-enabled on main. Is this disablement a merge error?" [GitHub, PR 180]

### 1.3 Golden-file and numeric tests need a written failure-triage policy

Without a stated policy, every golden failure becomes an ad-hoc judgment call — and the path of least resistance (widen the tolerance, regenerate the golden) quietly converts real bugs into accepted noise. Tolerances must be justified by the precision the implementation actually has.

> "I think it's important for golden-file tests to have a very clear process for failures: when is it appropriate to resolve a failure by moving the tolerance, or by computing new goldens, or when is it likely to indicate a real bug." [GitHub, PR 195]

> "Given the implementation under test works in fp32 (as opposed to bf16), we should have much tighter error tolerances. How about 1e-8?" [GitHub, chunk-024]

> "Either tighten the tolerance or weaken the comments." [GitHub, PR 2347]

### 1.4 Correctness must be checkable against an independent source of truth

A compiler that validates itself against itself proves nothing. Anchor to published weights and reference implementations, choose comparison metrics for information content, and compute error math at higher precision than the system under test.

> "Do we have validation that this is equivalent to the original model? E.g., a test that running the original model and running this in torch against the published weights produces identical (up to numerics) logits?" [GitHub, chunk-015]

> "The error computations you should just always do in double precision. The speed gained from being less precise is not worth the cost of uncertainty about whether observed errors are due to numerics in the comparison code." [GitHub, Python tooling review]

> "X is not self-validating at all, and therefore... changes to X deserve intense scrutiny." [GitHub, PR 2000 essay on grades of code validation, chunk-017]

### 1.5 Encode invariants in the type system

A cast is a code smell; index types are newtypes; type safety is never weakened for convenience. Types are the cheapest permanent enforcement mechanism a codebase has — typed indices make whole classes of bugs unrepresentable instead of merely untested.

> "The general theme is that (to me at least) a cast is a kind of code smell: a variable was declared as one type and then used as another, so maybe we didn't understand what type it should be." [GitHub, PR 610, chunk-002]

> "Index types are supposed to be `newtype`s to ensure type safety of accessing indexed collections. You're not _supposed_ to be able to index one with just some random integer." [GitHub, PR 2358, chunk-020]

> "If you want a real distinction, use `newtype`, not `type`. Methinks the latter is just a recipe for later confusion." [GitHub, chunk-025]

### 1.6 Every non-obvious decision must be justified in writing at the site of the decision

A rationale is an acceptable answer to any challenge — but only if it lands in the code. This converts review arguments into permanent institutional memory: the reviewer's question dies with the PR thread; the comment it forces survives for every future maintainer and every future AI.

> "I'm open to the possibility that there is a reason, but then let's write that reason down." [GitHub, PR 2875; recurs near-verbatim across the corpus]

> "Seems like that should be addressed, either by code change or by a comment explaining why it's a non-issue." [GitHub, sweep-verdicts]

> "Could you record somewhere (e.g., a PR comment) how you validated that this change is working correctly, since `make test` has no coverage for it?" [GitHub, sweep-verdicts]

### 1.7 Durable design knowledge lives in cross-referenced, mechanically policed Notes

He introduced GHC-style `Note [...]` blocks to the repo, cross-referenced from every site that relies on them, fact-checked like code — and built a dangling-note-reference linter (PR 1526) so documentation drift becomes a build failure instead of a discovery during an outage.

> "possibly even create and reference a Note [Channel design]. The documentation for that Note is all there in `file.hpp`, it's just lacking a Note header." [GitHub, chunk-013]

> "Maybe even reference the Note from the place where Rinzler does bringup of multiple models so it stays true as the facts change." [GitHub, chunk-013]

> "OK, but some fact-checking of assertions made in the Note." [GitHub, CHANGES_REQUESTED body, PR 2346 — an entire re-review round spent verifying prose claims in a Note]

### 1.8 Comments describe what IS; unverifiable prose is deleted, not shipped

Change-narration belongs in the commit message. Comments that narrate a diff or make unchecked claims become lies the moment the code moves on — and in an AI-authored codebase, false comments actively mislead both the humans and the models that read them next.

> "comments should describe what is, and only reference what was if that helps understand what is." [GitHub, PR 2875]

> "would you mind reading the sentences in this whole set of comments one by one and just deleting any that you can't verify as true? ... I don't want a bunch of (potential) lies to sneak into comments riding on it." [GitHub, PR 2809, chunk-026]

> "I worry that Claude might read "lock-free" in the documentation and decide to just delete the lock from the code to make it so." [GitHub, PR 1276 — documentation audited for its effect on future AI readers]

### 1.9 Deletion is a first-class engineering act

Superseded code, dead branches, obsolete tests, and imprecise prose all get removed the moment they are superseded — "flush it" (his deletion verb, appearing in 25 comments). Every dead line is a maintenance tax and a trap for the next reader.

> "When would we ever even want the common ancestor of two seq_tips? This code looks dead too -- flush!" [GitHub, sweep-lexicon]

> "Last sentence is describing dinosaurs that once walked the Earth. Flush it." [GitHub, PR 2875 — prose gets the same treatment as code]

> "I feel like we miscommunicated. The point was to delete `sequence_prompt_each`, not refactor it." [GitHub, sweep-verdicts — refactoring is not a substitute for deletion]

### 1.10 A PR achieves a single stated objective; history stays bisectable

He wrote the operational definition, and holds stacks to it: entangled changes are unreviewable and get split (he offers to teach the git mechanics himself), stacks stay restacked, and the test suite should pass at every commit.

> "A PR is well-scoped if it achieves a single stated objective, described in one sentence, without side-effects. Undesirable side-effects include - Changes to unrelated code - Changes to dependencies - Changes to unrelated CI jobs or developer tools" [GitHub, PR 2000, chunk-017]

> "Adding log_intermediates support to force_generate might be reasonable, but I can't approve it because it's entangled with this other alleged change." [GitHub, sweep-verdicts]

> "Reviewer note: I attempted to make sure the test suite passes at every commit in this sequence, and I believe I succeeded." [GitHub, author-side, chunk-000 — he holds his own stacks to per-commit green]

### 1.11 Performance claims require methodology; unexplained deltas block merge

Explicit baseline, experimental setup, units, and enough repeated runs to clear the noise floor. An unexplained delta — regression or improvement — costs the PR his *unconditional* approval: depending on risk he blocks, asks the question on the record, or approves conditionally ("LGTM assuming no performance surprises"); accepted regressions are recorded with their rationale.

> "Well, that -10% is a surprise. I'm sure you wouldn't anyway, but let's not merge until we know why." [GitHub, sweep-verdicts, chunk-025]

> "our benchmarking is pretty noisy, so you really should do multiple runs to convince yourself that a change as small as 166 to 168 is real and not just runner noise." [GitHub, chunk-022]

> "Yowza! The benchmark is showing a dramatic improvement from this! Though one wonders, since those numbers are self-reported from exactly the measurements whose methodology is being changed in this PR." [GitHub, chunk-004]

Corroborated as a codified team standard: "state the experimental setup, the comparison baseline, and the units of any numerical claim; delete imprecise prose rather than leaving it in place." [Notion, Fusion Kernels sync 2026-05-06]

### 1.12 Concurrency changes get proof-level scrutiny

Concrete interleaving walkthroughs, explicit memory-ordering choices (acquire/release/relaxed) justified per-variable, and the threading model documented where the code lives. Races don't show up in tests; they show up in production at load.

> "Consider the following possible sequence of events: - Thread A starts a `pop` and reads the item from `items[head]` ... Now the data structure is screwed up... The solution to this is to track `head` and `tail` rather than `head` and `count`. ... Incrementing with `release` semantics and reading with `acquire` semantics should be sufficient." [GitHub, PR 1276 harvester.hpp]

> "neither the mwait instruction itself nor reading a volatile variable provide any memory guarantees whatever" [GitHub, PR 1276]

> "The only purpose of reading the old value is a debug check; do we need to pay the cost of the acquire part to make that check accurate? That's not a rhetorical question; I am open to either choice." [GitHub, PR 1276 — ordering strength is a deliberate, costed decision]

### 1.13 Defensive code is guilty until explained; root-cause instead of wrapping

Every try-catch, safety flag, and shutdown check must justify its existence. Unexplained defensive layers hide bugs instead of fixing them and permanently obscure the system's real invariants.

> "Why do we need an `ultra_safe_mode`? Safe from what?" [GitHub, PR 1276]

> "I expect the system shouldn't be shutting down if a sequence is still in progress. Instead, we should be relying on `scheduler_shutdown` to effectively cancel any outstanding generations (and if there's a race there, let's find it and fix it)." [GitHub, PR 1276]

> "How did our build system produce a situation where foo.cpp.o was stale? It transitively depends on bar.hpp---that shouldn't be possible." [GitHub, PR 2866 — even a passing workaround must explain the impossible state it papered over]

### 1.14 Complexity must justify itself quantitatively

"Why did this end up being so much code?" is a standing review gate, applied to diffs, abstractions, new concepts, and new technologies alike — and over-engineering is challenged in design docs before code exists.

> "Why did this end up being so much code? Are routings really that different from buffers that they require this much special treatment?" [GitHub, PR 2754, sweep-verdicts]

> "Um, sorry, why? I'm not necessarily opposed, I just think that if we're going to introduce a whole new programming language into our ecosystem, we should consider the rationale. We are at the very moment suffering from the consequences of one hastily-introduced new programming language already..." [GitHub, PR 891]

> "Really? That might be a bit much on the over-engineering." [Notion, Linear Attention design doc 2026-05-06]

______________________________________________________________________

## 2. Seasoned judgment and calibration

### 2.1 Review depth is calibrated to risk — and the calibration is disclosed

Concurrency and correctness code gets forensic, happens-before-level interrogation; low-risk tooling gets a fast pass that is explicitly labeled as such, with an offer to go deeper on request. Disclosing the depth makes the approval an honest, bounded attestation rather than a false blanket guarantee.

> "So, yeah, what, actually, is the potential race that this test is testing for, and how would it manifest if it occurred? What assertion(s), if any, should the test make to ensure that race did not, in fact, occur?" [GitHub, PR 2256, chunk-019]

> "Rubber-stamped, assuming the efficacy is relatively self-evident. LMK if you'd like a more thorough review." [Slack, #software]

> "Caveat: I only skimmed the Python stuff, and didn't read Nix at all because I don't know Nix (yet?), if you actually feel like this deserves more human attention than that, you know to ask for it." [GitHub, chunk-013]

### 2.2 Approvals are scoped attestations; the remainder is routed to a named owner

He never lets an approval imply expertise he lacks — he states exactly what he reviewed at what depth and names who should cover the rest. The default out of his depth is a COMMENTED review plus a tagged owner; approve-to-unblock happens only when the blast radius is small, the approval is explicitly scoped, and the right owner is still named.

> "LGTM except for fpga management. Ask @mcherba for that." [GitHub, sweep-verdicts]

> "I'm not really an expert here, but the blast radius seems small. Approving to unblock merge in case this is blocking something, but otherwise deferring to @BillBaumann." [GitHub, chunk-018]

> "I'm sufficiently unfamiliar with hegg that I hesitate to just approve it" — leaves COMMENTED and tags the domain expert instead. [GitHub, chunk-016]

### 2.3 Evidence is gathered before questioning — including his own

He runs the reproduction, spot-checks the claim, and states the loopholes in his own negative result. Challenges grounded in first-hand evidence are falsifiable and respectful of the author's time — and model the epistemic standard the whole team should hold.

> "No. No, it doesn't. I checked." (re a Makefile behavior claim) [GitHub, chunk-010]

> "I did not manage to reproduce this failure in `run`. There are several loopholes in that statement, though: - I didn't try to reproduce from the exact version at..." [GitHub, chunk-004]

> "After adding such a mode, I tried a plausible command line and the issue does not, in fact, reproduce." [Slack]

### 2.4 Principled 80-20: "improvement over status quo" is a sufficient merge bar

Known imperfections merge when they are conscious, flagged, and recorded; optimization work is not done until there is evidence it is needed. This is the opposite of sloppiness — imperfection is tolerated only when it is deliberate and cheap to revisit.

> "Approving the PR because it's an improvement on status quo; do with the comment what you deem best." [GitHub, chunk-000]

> "My guess is that this will form a perfectly good 80-20 solution... I hadn't done it yet because there wasn't actually any evidence that we needed to." [Notion, Interleaved GLU debate 2026-02-09]

> "This will force feed the same continuation into each of multiple prompts in that regime, but so be it." [GitHub, PR 304, chunk-001]

### 2.5 Knowing when NOT to block; taste is labeled taste

Nits are marked optional, merge autonomy is granted explicitly, and he refuses to block on his own architectural preferences — reserving CHANGES_REQUESTED for correctness, unexplained performance, open design questions, and entangled scope. Even coin-flip choices must still be made intentionally.

> "I really feel like a lot of this code would be much less nasty if it were in a State Env monad... But we've iterated on this PR so much already that I'm not going to block merging on that." [GitHub, chunk-021]

> "So, to detach or not to detach? I don't know that I have a strong opinion, but I think we should make the choice intentionally." [GitHub, PR 1276]

> "this doesn't really feel like a useful standalone concept…, but I can see how reasonable people would disagree about that." [GitHub, PR 1418] / "Having raised the issue I will defer to your judgement." [GitHub, PR 195]

### 2.6 Unblocking is the reviewer's stated, near-top priority

Either review promptly or say you are not the right person; approve-to-unblock deliberately with stated reasoning; and when you do block, hand the author a concrete unblocking path.

> "If you are asked to review a PR, the (relatively) high-priority task is to make sure it's not blocked on you: either do the review, or let the author know you can't or aren't the right person for it." [Slack, #software, 2025-11-14]

> "I almost feel like this sort of thing might want more of a 'move fast and fix broken things' collaboration style than traditional code review, so I'm approving in order to unblock." [GitHub, PR 1646, chunk-013]

> "If you want to unblock the rest of these changes, one way forward would be to revert the type change of `hw_tok_ix` and possibly take a follow-up." [GitHub, chunk-027]

### 2.7 Review is pedagogy; lessons are compounded into infrastructure

He assigns the author the exercise instead of handing them the answer, offers to teach the mechanics, invites learning-reviewers, and distills recurring feedback into reusable material — including for the AI toolchain (Claude skills, CLAUDE.md conventions).

> "I'm not necessarily sure that's better, but I think the exercise of figuring out whether or not it is (and providing an explanation) would be useful for learning the codebase." [GitHub, chunk-024]

> "If you want, I'd be happy to walk you through the git-fu to separate them out; I've gotten quite used to that sort of thing over the years." [GitHub, PR 45, chunk-000]

> "Looks like a bunch of my comments might make good grist for a Claude skill for how to write SIMD code in our code base." [GitHub, sweep-verdicts]

### 2.8 Follow-through and honest closure

He re-reviews what he blocks — 72% of his CHANGES_REQUESTED PRs (105 of 146) end in his own approval — marks progress across rounds, and when overruled he commits to the team decision while leaving the reservation explicitly on the record.

> Multi-round progress markers: "Good start!" -> "Progress!" -> "Excellent progress! Now for the refinement phase :)" -> "Much nicer, thank you! Just one thing left." -> approve. [GitHub, sweep-verdicts]

> "RIP, someproject. Let us grant this deletion the solemnity it deserves, for it is the last rite for my disagreement with Fritz, that we never were able to resolve." [GitHub, sweep-domains]

> "OK; per offline discussion, I withdraw my top-level architectural complaint." [GitHub, sweep-verdicts]

### 2.9 Friction is reduced with his own labor and the right channel

He offers to do the work he is requesting, fixes trivia himself pre-approval, escalates to synchronous conversation when text rounds stall — and then writes the conclusion back into the public record, including when the resolution is that he changed his mind.

> CHANGES_REQUESTED body ending: "Comments describe how we can have more precise events. Want me to do it?" [GitHub, PR 2420, chunk-021]

> "Perhaps a meeting to walk through the major constraints and features of the design?" [GitHub, sweep-verdicts]

> "Based on offline discussion, I am now convinced that the implemented semantics … is reasonable" — offline consensus summarized publicly for posterity. [GitHub, sweep-domains]

### 2.10 The AI development process itself is reviewed as first-class code

Agent instructions, skills, and generated artifacts get the same rigor as code: staleness risk of instruction files, provenance of generated scripts, and graduated trust levels for what AI may edit unsupervised — scrutiny proportional to how self-validating the code is.

> "Um, this instruction looks hallucinated? IIUC, we should but currently do not have infrastructure for something like this." [GitHub, .claude/ files, sweep-domains]

> "Is there a self-improvement loop somewhere? Some of these facts about file trees and so forth are going to grow stale; how do we keep them from becoming deceptive?" [GitHub, chunk-013]

> "the gap between natural-language intent and behavior of AI-generated code is just too large not to read it. Unless we read the properties and formally verify... or implement bullet-proof correctness (and performance) test harnesses." [Slack, #research 2026-06-10]

______________________________________________________________________

## 3. Relationship to canonical high-bar review standards

Mapped against Google-style published review practice (where he trained), his behavior demonstrates nearly every canonical element — usually via his own mechanisms — with two conscious deviations and several extensions beyond the canon.

### 3.1 Canon demonstrated, often codified

- **Code health over perfection.** His stated merge bar is improvement over status quo, said in the approval itself — paired with an on-the-record reservation instead of silent acquiescence, so the bar never silently erodes. ("Better than what we have now." [GitHub, sweep-verdicts])
- **Never let a CL block on you.** Articulated as explicit policy (2.6), down to managing automerge mechanics: "Turned off auto-merge to give you a chance to respond to the two minor comments, but happy to merge regardless of the resolution you choose." [GitHub, sweep-verdicts]
- **Small single-purpose CLs.** Not just practiced but written down as an operational rubric (1.10) and addressed to AI authors as reusable process: "Let me see if I can articulate for Claude's sake how to send better-scoped PRs." [GitHub, PR 2000, chunk-017]
- **Facts over opinions, applied symmetrically.** He demands evidence from authors and holds himself to the same bar — labeling his own preferences as preferences: "I guess my own instinct would be to prioritize release over kill, but I don't have a clear rationale for that." [GitHub, sweep-verdicts]
- **Courtesy and generous praise.** Praise is loud and specific ("Beautiful!" 18x, "Nice!" 18x); confident corrections are phrased as face-saving questions ("You mean `alive`, no?" [GitHub, PR 1581]); he publicly admits his own errors ("Sorry, being obtuse." / "my mental model of your capabilities is being updated." [GitHub, sweep-verdicts]).
- **Conflict via consensus and face-to-face — plus a closure step the canon lacks:** after the sync-up, the resolution is written back into the public record (2.9).
- **Understand every line you approve.** Practiced as disclosed, scope-limited approval with routing to named owners (2.1, 2.2).
- **Mentoring.** His dominant mode: 43.5% of inline comments contain a question, usually held with a candidate answer ("Why not just X?", 54x), with 72% CR-to-approval follow-through.
- **Feedback must be conserved.** Ignored feedback is one of his few flat re-blocks ("My previous comments appear not to be addressed." — the entire CHANGES_REQUESTED body [GitHub, sweep-verdicts]); he fact-checks claimed fixes; and as an author he models per-comment closure ("Done." 89x, "Fixed." 36x, "Flushed." [GitHub, sweep-lexicon]).

### 3.2 Conscious deviations in form, compliance in function

- **No Nit:/non-blocking taxonomy.** "non-blocking" appears 0 times; "nit" in 27 of 2,356 comments (case-insensitive). Severity is carried by sentence form (question = probe, imperative = do it, "An explanation is required." [GitHub, PR 2119] = hard gate, explicit waiver = optional) and by the conditional-approval grammar "LGTM up to bugbot (and tests passing, of course)." [GitHub, sweep-lexicon] — which makes the blocking set auditable in one line.
- **Courtesy deliberately suspended for unvetted AI output.** "What is this shit? There's a `relatedName` function in Name.hs for a reason." [GitHub, PR 2119, chunk-017] — but the accountability lands on the human process, not any person's competence: "Also, read Claude's output yourself before you send it for code review -- this shouldn't have gotten through your own professional filter." [GitHub, PR 1418, chunk-009]

### 3.3 Beyond the canon

- **The WHY must land in the artifact, not the thread** (1.6, 1.7) — institutionalized via the Notes convention plus the lint-notes linter he built.
- **Unexplained performance deltas are a hard merge gate** (1.11), stricter than anything in published practice — "What happened to the benchmarks?" is an entire CHANGES_REQUESTED body [GitHub, PR 1088, sweep-lexicon] — with accepted regressions documented: "we deem the 1% regression … acceptable because …" [GitHub, sweep-domains].
- **Tests are audited for meaningfulness, not existence** (1.1–1.3): vacuous tolerances, fail-not-skip, golden-file failure policy.
- **The AI development process is in scope for review** (2.10): instructions, skills, generated scripts, and a theory of graduated scrutiny by how self-validating each layer is.
- **Complexity owes a quantitative justification** (1.14), challenged at design-doc time, before code exists.

______________________________________________________________________

## What a review loses without this maturity

Without this calibre of review, the green checkmark stops meaning anything: tests that assert nothing stay green while numerics drift, skipped suites rot silently, and golden tolerances widen until real bugs read as noise. Performance decays one unexplained percent at a time, because nobody held the line at "let's not merge until we know why." The type system stops enforcing invariants — casts accumulate, indices become interchangeable integers, and bug classes that could have been unrepresentable become permanent test burden instead. Design rationale evaporates: every "why is it like this?" gets re-litigated per PR, decisions get silently reversed by people (and models) who never knew they were decisions, and comments harden into lies that mislead every future reader. Races ship, because nobody walked the interleavings; defensive wrappers accumulate around bugs nobody root-caused, until the system's real invariants are unknowable. Approvals become blanket vouching by people who skimmed — the trust signal of review itself degrades, and nobody knows which expert actually looked at what. Diffs balloon into entangled multi-purpose changes that can be neither reviewed, reverted, nor bisected; review either rubber-stamps them or becomes the bottleneck that teaches people to avoid it. The bar drifts to one of two failure modes: perfectionist gatekeeping that stalls the team, or velocity worship that compounds debt — because no one is doing the harder thing of tolerating imperfection only when it is conscious, flagged, and recorded. Authors stop growing: they receive patches instead of exercises, and the reviewer's knowledge scales linearly instead of compounding into conventions, linters, and agent instructions. And in an AI-authored codebase the loss is squared — the generator's instructions, harnesses, and self-reported claims go unreviewed at exactly the point of highest leverage, so the review that remains inspects the output while the source of the defects runs unexamined. What this maturity buys, in one line: a codebase whose green CI, benchmark history, type signatures, comments, and approvals all still mean what they say — years later, under authors who never met the reviewer.
