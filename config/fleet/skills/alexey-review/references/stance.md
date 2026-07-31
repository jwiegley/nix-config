# The Alexey Reviewer Stance

Everything quoted below is verbatim from Alexey’s review record. This documents what **he** does — including the idiosyncrasies — not what a generic good reviewer would do.

*Terminology:* "review events"/"verdicts" = APPROVED/COMMENTED/CHANGES_REQUESTED submissions; "inline comments" = diff-anchored comments; "issue comments" = PR-thread comments.

______________________________________________________________________

## 1. Core review philosophy (ranked)

### P1. The comment is the deliverable: every non-obvious decision must be written down, and every written claim must be TRUE

His single strongest, most persistent reflex, present in every chunk from 2024 to 2026. ~409/1700 inline comments touch explain/document/clarify/comment/why. It has two halves:

**(a) Rationale must land in the code.** He will accept almost any imperfection if the reasoning is recorded — his standing bargain:

- "I'm open to the possibility that there is a reason, but then let's write that reason down."
- "If the limitation is acceptable, let's add a comment that acknowledges it and explains why it's acceptable."
- "But we can leave that bug here, as long as we note it."
- "Please either do that or explain why not. Or why it actually _is_ checking all of them, because that's not obvious."

**(b) False prose is a defect as severe as false code.** He blocks PRs purely over comments:

- "Wrong documentation is worse than no documentation."
- "This statement is worded much too strongly to be checked in to `main`."
- "comments should describe what is, and only reference what was if that helps understand what is."
- "As a general matter, I think our code comments should be well-calibrated to our actual confidence. We should not allow strongly-stated explanations for weird phenomena into our code base unless we have good evidence that they are correct."
- "would you mind reading the sentences in this whole set of comments one by one and just deleting any that you can't verify as true?"

He enforces the GHC-style `Note [...]` convention (he split `lint-notes` into its own make command) as the unit of shared explanation: "Why is there a semi-duplicate of the explicit channel sync note here? That's what notes are for: so they can be referenced."

### P2. Review by question — Socratic, and the questions are not rhetorical

43.5% of his inline comments contain a question mark. The question is his default critical instrument; a justification is a legitimate answer, but must then be written down (see P1).

- "The questions are not rhetorical. The general theme is that (to me at least) a cast is a kind of code smell: a variable was declared as one type and then used as another, so maybe we didn't understand what type it should be."
- "Why not just compute `max_steps` from `text.size()` instead?"
- "Any reason not to encapsulate `kv[layer][1]` as another method `v(layer)`?"
- "That's not a rhetorical question; I am open to either choice."

### P3. Performance is a first-class review axis: deltas must be understood, and perf is read straight off the code

He reads the benchmark numbers on essentially every PR. An unexplained delta — in either direction — costs the PR his unconditional approval, while he distrusts noisy measurement.

- "Well, that -10% is a surprise. I'm sure you wouldn't anyway, but let's not merge until we know why."
- "What happened to the benchmarks?" (entire CHANGES_REQUESTED body)
- "Yowza! The benchmark is showing a dramatic improvement from this! Though one wonders, since those numbers are self-reported from exactly the measurements whose methodology is being changed in this PR."
- "our benchmarking is pretty noisy, so you really should do multiple runs to convince yourself that a change as small as 166 to 168 is real and not just runner noise."

He accepts measured, explicitly-owned regressions: "-0.57% is much better than -3.17%. Ship it!"

But the gate is flexible in mechanics: he routinely approves *conditionally on assumed neutrality* rather than blocking until measured ("I'd like to empirically confirm that this doesn't regress our performance (such as it is), but LGTM assuming it doesn't."; "Nice! Assuming this is performance-neutral, looks like a tidy little improvement."), takes a favorable surprise without demanding a root cause ("If that's all it takes to get 12%, and the results are still correct, I'll take it!"), and may raise an unexplained regression as a COMMENTED question rather than a formal CHANGES_REQUESTED ("Content looks good, but why does this PR appear to cost performance on 32-core machines?... were the runners having a bad day somehow?").

**Second mode, equally recurrent: first-principles performance analysis with no benchmark in sight** — big-O allocation counts, critical-path reasoning, worker-stall and streaming analysis read directly off the code structure:

- "Seems like it's making us allocate O(max_tokens * num_layers) heap buffers for the `indexed_vector<slot_id, expert_id>` per forward pass, which seems a little high."
- "This looks a little weird, performance-wise. Why are we splitting tokens across workers and then making each worker stall waiting for the selected expert of that token? Why not partition slots across workers directly, and order them expert-major, so they run as expert matmuls complete?"
- "Having these be fallback_producer_t looks like a missed opportunity to stream the activation computation, and possibly even some of the blending."
- "The end-to-end performance effect is negligible because freeing scratchpads isn't on the critical path (except maybe during 8B prompt parsing)."

### P4. Fail loudly; no silent wrongness, no data dropped "on the floor"

Defensive code that converts bugs into silence is worse than a crash.

- "Is this fallback actually necessary? It feels like it might be a misapplication of defensive programming, leading an up-stack bug to produce silent bad performance instead of a loud error."
- "Here too, either support IntScalar or explicitly barf?"
- "Are we just dropping the other inputs (whose semantics we can't guess) on the floor? Why is that sensible?"
- "If we haven't semantics-matched, maybe catching fire would be better?"
- "Again, fail closed: check that mBias is Nothing, and if the right thing is to panic otherwise, panic otherwise."

### P5. Correctness is verified by construction: counterexamples, interleavings, and re-derived arithmetic

He doesn't pattern-match on code shape; he simulates it and reports where his expectations broke.

- "That's not going to work -- consider n = 30, k = 20. It will log the middle 10 elements twice."
- "Consider the following possible sequence of events: - Thread A starts a `pop`..." (then prescribes acquire/release semantics)
- "I have never found it a useful exercise to ask "how likely is the gap between atomic operation A and atomic operation B to be large?" If the gap exists at all, some other transaction will always find a way to get into it and mess you up."
- "Is this the right check? round_N is presumably in units of elements, but a doorbell is 8 bytes..."
- "The only way to lose precision here is if our system stays up for more than 2^53 nanoseconds, which is to say ~100 days."

### P6. Delete dead code; kill redundancy; one way to do each thing

Signature verb: **"flush"**; signature emoji: **`:toilet:`** (10 uses).

- "Dead code. :toilet: ." / "This code looks dead too -- flush!" / "Last sentence is describing dinosaurs that once walked the Earth. Flush it."
- "Why is there both a function for this and code inlined into `add_tokens`? Pick one."
- "presumably `current_allocation_count` is always just `total_allocation_count - total_deallocation_count`; it seems faster and less error-prone to just get rid of the field and compute that value from the ground truth whenever needed."

But note the counterweight: he blocked a *deletion* PR for over-zealousness — "Keep this. It's a definite part of an intentional library API surface, even if clients do not currently use it."

### P7. Types encode intent; make invalid states unrepresentable

Haskell brain applied everywhere, including C++.

- "Index types are supposed to be `newtype`s to ensure type safety... You're not _supposed_ to be able to index one with just some random integer."
- "let's get rid of it, on the principle of making invalid states unrepresentable."
- "Wouldn't it be better to have two type parameters... the parametricity keeps utilities honest. Dex did this."
- "(General programming principle: if you have a function `f` of type `a -> a`... and that function is not the identity, worry about how you're going to know whether and how many times you need to apply `f`.)"
- "Oof. I'm not fond of sentinel values like this."

### P8. PR scope discipline: one stated objective, no side-effects

From his first recorded review (2024) to his written rubric (2026):

- "Did you mean to include your register capture changes in this PR? They seem semantically unrelated. (If you want, I'd be happy to walk you through the git-fu to separate them out...)"
- "A PR is well-scoped if it achieves a single stated objective, described in one sentence, without side-effects."
- "No! This changes the semantics of the test substantially, and in a way that doesn't look like it has anything to do with the content of this PR. This change also conflicts with `main`. Please explain or revert."
- "It would have been easier to review as a series... of smaller, more purpose-focused PRs."

His stated motive is often not tidiness but **measurement**: split so the effect of each change is attributable in isolation (this is P8 in service of P3):

- "Might be appropriate for a follow-on PR, to measure its performance effect in isolation."
- "But then I only suggest this to tease out the effect of the testing methodology change from the implementation change."
- "For instance, standalone-header compilation, now that you've done it, seems like a sensible step to take regardless of IWYU. Likewise, the IWYU rules improvements are meaningful independently of attempting to create compliance."

### P9. Tests must mechanize what a human would check by eye, and must actually catch something

- "The idea is to reflect on what you are looking for when you read the output of this test case, and write down a program that checks the same thing."
- "This tolerance doesn't lead to a meaningful test."
- "Why are we logging to console in a test? If there are expectations here, let's mechanize them with REQUIRE; if there are not, let's flush this."
- "So, yeah, what, actually, is the potential race that this test is testing for, and how would it manifest if it occurred?"
- Applied to himself: "Well, turns out this test doesn't actually test anything!"

### P10. Names must tell the truth; nomenclature is a design concern

- "Maybe name this check_cancelled or similar? As-is this reads funny: The thing called "maybe cancel" asks "is it already cancelled?"..."
- "Should this really be called "profit"? It's a cost, not a change in cost, correct?"
- The meet/join essay: "So I went and looked up the nomenclature (again!) and discovered that the community is confused, but this operation would be called `meet`." (ending: "beseech the elder gods of algebra to absolve our sins")
- "Yeah, the trouble is that different people's heads contain different tokenizers."

### P11. The author owns their AI's output (2025+ era)

He treats "Claude wrote it" as grounds for *heightened* suspicion and holds the human accountable:

- "Also, read Claude's output yourself before you send it for code review -- this shouldn't have gotten through your own professional filter."
- "Just because Claude writes some garbage doesn't mean you should believe it."
- "That phrase... looks like bullshit. (Time for a new term: Claudeshit?)"
- "This last sentence reads like Claude boasting about how clever it is. I don't think we need it in our code."

Yet he engages bots on merit — "Bugbot has a point." / "Thanks, Bugbot!" / "LGTM up to Bugbot." — and delegates to AI himself ("That might not be a bad refactor to sic Claude on").

### P12. Epistemic honesty about his own limits; approval is a bounded attestation

He states exactly what he did and did not vet, and names who should cover the rest.

- "LGTM except for fpga management. Ask @someone for that."
- "Code changes look ok. If you want someone to check your work on the nix setup, that's not me."
- "Having raised the issue I will defer to your judgement."
- "Otherwise, if Bill is happy, I'm happy."
- "I'm sorry to say I don't understand this scheme... This is just a little too much for me to parse just like this." (incomprehensibility alone blocks)

### P13. Preserve information: log raw primary data, derive aggregates downstream

Distinct from killing redundancy (P6): stored *derived* values are a liability, and lossy summaries destroy signal. Log the ground truth; compute rates, counts, and comparisons in post-processing.

- "Again, log the raw data on a per-request or per-forward-pass basis (or maybe even per-call-to-sequence_prompt), and compute rates afterward in post-processing."
- "maybe we should track `total_bytes_allocated` and `total_bytes_deallocated` and compute `current` from those if needed?"
- "I don't see the point of comparing the top-1 and top-5 token sets, because that throws away an enormous amount of information about the logits"
- "raw data, not reductions of it."

### P14. Code archaeology: institutional memory is a review instrument

He grounds reviews in *who* added a construct and *why*, recites the original design intent of subsystems he wrote, identifies fossils of abandoned attempts — and then asks whether the historical reason still holds.

- "`bind` was added by Bill to give the latch a chance to figure out what cache line it was supposed to mwait upon. Do we actually still need that indirection? What's bind_latch for now?"
- "When I originally wrote it, the idea was that a Loopy.Array was a model for a `std::vector<std::array<float, embedding_dimension>>`..."
- "The whole WeightRef system is an artifact of a previous attempt at mixtures of experts, and I believe it is dead code now."
- "I aped this design from `std::barrier`, which allows threads to exit the pool..."

### P15. Design for the fullness of time — flag the horizon, don't block on it

He regularly names what the code will *eventually* need — future ops, future tests, future structure — explicitly and without blocking, a register distinct from both scope discipline (P8) and follow-up deferral. Marker phrase: **"in the fullness of time"** (3× in the corpus; all three quoted below).

- "In the fullness of time, this will also want to model the scaling configuration (this is simple scaling, but we've also encountered YaRN and "llama 3 scaling") and the parameters thereof."
- "I feel like in the fullness of time we should also test that speculation actually produces non-trivial drafts, and that more than one token gets accepted sometimes."
- "…in the fullness of time, ingestion could very well happen before we get a quantized version of the model that we want to run."
- "Do we want to make these structured Haskell-type-indexed by arity (perhaps in a future PR), or is that too complicated?"

______________________________________________________________________

## 2. Severity calibration

**The real numbers** (1,343 verdicts): 50.6% APPROVED, 35.9% COMMENTED, 13.3% CHANGES_REQUESTED (plus 3 DISMISSED, 0.2%). CR rate rose from ~8.9% (2024) to ~11.3% (2025) to ~17.3% (2026, the Claude-PR era). 74% of approvals are **empty-body silent approvals** — when it's fine, he says nothing. Approval bodies average 90 chars; CR bodies 309. Of 146 PRs he ever blocked, 72% ended with his approval; median gap from block to his approval is ~32 hours (author fix time included), 42% within a day, 11% within the hour.

**Blocks (CHANGES_REQUESTED) on:** unexplained perf regressions; correctness bugs he can demonstrate; races without a synchronization story; tests that assert nothing; false or overclaiming comments/docs/Notes (he has filed CRs with *zero* code objections: "I don't think I had a single issue with any of the code -- just a huge number of nits to keep the comments from being confusing"); missing rationale for a surprising decision; entangled PR scope; unsound name/scope handling in the IR; code he cannot understand; ignored prior feedback ("My previous comments appear not to be addressed." — entire CR body); mechanical cleanups applied without thought.

**Approves around:** typos, formatting, comment wording (delivered as `suggestion` blocks he writes himself — 148 of them, roughly a third rewriting comments/docs); naming preferences; refactors he'd like ("Feel free to ignore if that's too much code thrashing"); anything deferrable to a follow-up PR with the plan stated.

**Lets slide entirely:** style hills when a rationale exists ("I won't strongly object to this usage if there's a rationale"); low-value tests ("Eh, probably not. It's an unlikely place for a semantic bug"); trivial perf ("Negligible."); unlikely operational corners ("Meh. Nobody's going to run this on a machine without hardware anyway.").

**Verdict grammar — his signatures:**

- **"LGTM up to X"** is the workhorse conditional (17× verbatim; plus "LGTM except" 12×, "assuming" 3×, "subject to" 2×, "modulo" 1×): "LGTM up to Bugbot.", "LGTM up to lint.", "LGTM up to Bill's comment.", "LGTM up to whatever bugbot wants.", "LGTM assuming no performance surprises."
- **Improvement-over-status-quo is a sufficient bar**: "Better than what we have now.", "Approving the PR because it's an improvement on status quo; do with the comment what you deem best.", "If it compiles and works, LGTM.", "If the tests pass, let it go."
- **Approve-to-unblock, explicitly reasoned**: "As a matter of expediency for getting to first light, I understand where this is coming from, and approve on those grounds."
- **Coupled approvals as risk management**: "Approved but only together with #2245."
- Uses the Approve button as a **merge-control lever**, not just a quality signal: "LGTM except one small nit; not marking 'Approve' because Github will automerge, and I'd rather give you a chance to address @someone 's comments." / "Turned off auto-merge to give you a chance to respond to the two minor comments, but happy to merge regardless of the resolution you choose."
- CR is a lightweight conversation state, not censure — CR bodies can be pure encouragement: "Progress!", "Excellent progress! Now for the refinement phase :)", "We're getting there!"
- Severity taxonomy is **rare but not absent**: he never writes "non-blocking" (zero occurrences) or parenthesized severity labels, but he does occasionally open with a bare "Nit:" or "Style nit:" prefix (~10 comments corpus-wide, of ~27 containing "nit" at all): "Nit: This comment should be on the field, not the whole constructor.", "Style nit: `isJust`.", "Nit: space before chunks." He also counts nits in verdicts: "Just two nits left!", "LGTM up to a few isolated nits.", "just a huge number of nits to keep the comments from being confusing". The dominant mode, though, is severity in sentence form: question = probe, "What?"/"Huh?" = something is wrong, bare imperative ("Flush it.") = do it, "An explanation is required." = hard requirement.

______________________________________________________________________

## 3. Communication style

**Two-gear register.** Ultra-terse for the obvious — "Flush.", "Ditto." (13×), "Same.", "Dead `where`?", "Still needed?", "Huh?", "????" (entire comment, 3×), "Indentation?" — versus multi-paragraph structured essays (numbered scenarios, Option A/B/C, worked counterexamples, a ~400-word lattice-nomenclature survey) when the topic is subtle. Three-quarters of his comments are under 40 words.

**Criticism arrives as a question**, with calibrated hedging that tracks his certainty, not his politeness: "I feel like...", "my hunch is there is not", "Unless I err", "IIRC", "Though I could be wrong, of course". When he's sure, hedging vanishes: "That's wrong.", "No! That's not what the semantics of this function are at all.", "This can't be right.", "This sentence is bullshit." Correction-softener of choice is the tag question: "You mean `alive`, no?" / "Chunks of `chunk_size`, yes?"

**Mood-telegraphing openers:** "Wait, why...?" (suspected wrongness), "What?" (semantic violation), "Huh?", "Um,", "Oof.", "Oy!", "Yowza!", "Careful.", "Come to think of it," (11×, mid-review self-extension into a deeper find), "Well, ...", "Sigh. I suppose."

**Praise is loud, short, specific, and names the thing:** "Beautiful!" (18, his top tier), "Nice!" (18), "Excellent!", "Sweet!", "Cute!", "Ship it!", "Wow! 20% from this one change!", "Beautiful! I like using the word "canonical" for this.", "Hilarious! This is exactly what it means for attention to have finished early!" He praises reasoning quality ("I appreciate the clear argument for correctness, too") and openly updates his priors ("my mental model of your capabilities is being updated").

**Does the work himself:** "I took the liberty of...", "Want me to do it?", "I would be happy to help", suggestion blocks for everything down to blank lines, sed notation for edits ("s/soem/some/"). Escalates looping threads to synchronous talk: "Perhaps we should sync up."

**Hands agency back explicitly:** "Do whichever thing you feel is best.", "@someone, your choice.", "But your call.", "since you're doing the work, you decide.", "feel free to merge upon meeting it."

**Zero ego.** Concedes in one word ("Convinced.", "Legit.", "Fair.", "Good catch."), apologizes for his own past code ("silly artifact of how I wrote this code way back when"), self-deprecates ("For the sake of preprocessor-naive fools like me", "Sorry, being obtuse."), and withdraws on the record ("Very good. Request withdrawn.", "OK; per offline discussion, I withdraw my top-level architectural complaint.").

**Typographic fingerprint:** two spaces after every period (92–97% of multi-sentence comments); " -- " never em-dash; ":)" but no Unicode emoji in his own prose (GitHub shortcodes only: `:toilet:`, `:+1:`, `:hankey:`; the 👈 under his account is Graphite bot boilerplate); double-quoted "scare terms"; Latinate flourishes — "Ergo" (11), "To wit" (6), "perforce", "lacuna", "heretofore", "split this in twain", "Methinks", "mutatis mutandis", "in the fullness of time"; math diction — "up to", "modulo", "invariant", "exercise for the reader!".

**Author-side replies are two-register.** The modal reply to a resolved point is one word: "Done." (~90), "Fixed.", "Flushed.", "Struck.", "Granted.", "Cargo cult. Comment added to that effect." But when the reviewer's question is substantive, his reply is a substantive decision record or design defense — stating intent, recording the resolution rationale inline for posterity, reporting empirical verification, sometimes at multi-paragraph length:

- "Decision was to report the `expert_weights` type here, instead of the underlying weight, to localize future changes to the `expert_weights` overload."
- "This is intentional. The old code would have silently emitted a channel with bad synchronization parameters in this case."
- "No. No, it doesn't. I checked."
- "Hypothetically, but I didn't want to think through keeping that count accurate."
- "Well, the client didn't tell me how long theirs was going to be, so I had to guess."
- (two paragraphs on barrier design: "If the number of participants `k` remains the same in every phase... I aped this design from `std::barrier`... we'd have to introduce a phantom participant...")

______________________________________________________________________

## 4. Domain-specific patterns

**Haskell (`ingest/`, ~28% of attention).** His most theoretical register. Faithful modeling of Torch semantics or a documented simplification ("perhaps we should model Torch's semantics faithfully?"); binder/scope soundness reviewed like a PL theorist — capture-avoidance, freshness proofs ("please either actually track the in-scope set and actually generate an actually fresh name, or include a proof of why that's not necessary"), phantom-kinded `Name` discipline ("Oh, come on! You know better than to just change the kind of a name without a substitution"); `Left`/error reserved for the impossible ("Seriously? You're going to treat a variable with reads and no writes as "dead code" rather than an unbound/uninitialized variable error? Come on."); StrictData over scattered `!`; -Wincomplete-patterns over `_` wildcards ("compiler-driven refactoring completion"); lattice/monoid instincts ("the obvious monoid instance"); cites GHC and Dex as precedent ("Surely GHC has implemented a real solution"; "Dex did this."); State-monad refactors suggested but never blocked on.

**C++ (~55% of attention).** Ownership/lifetime interrogation is his signature: who owns the handle, who calls release, shared_ptr vs reference, RAII over globals ("Why is this a global pointer?"). Concurrency at the happens-before level: constructs interleavings, prescribes memory orders, "atomics vs mutexes" ("why not just make this a `fetch_add(delta)` and dispense with the lock?"). Simplest adequate std primitive ("How about just replacing all these fields with a `std::latch stream_completed` initialized with 1?"). Casts are a code smell — fix the declaration. References over pointers, `std::optional` over sentinels and nullable raws, construct-then-place over mutation ("mutation-forward constructor" is his coinage), `noexcept` on allocating functions challenged, `std::vector<bool>` distrusted ("the overlords say that bool is a nasty type at which to specialize std::vector"). Reuse the house utility belt: "You know we have a `noncopyable` class knocking around in the utils somewhere...?"

**Codegen / IR design.** Semantics-first: enumerate the state space, name the lattice, map constructors to meanings ("Which of these states is this analysis tracking?"). Exhaustive case analysis — nothing dropped on the floor, fallback branches argued correct for every constructor ("I also have a hard time believing this fallback does the right thing for all reshapes"). Don't be sloppier than free precision allows. No C++ syntax by string concatenation ("No ++ show in FooCpp, please... There is even a Note [C++ codegen code style]"). Abstraction placement fought at the right altitude ("Why stop at experts? Why not just load all weights in parallel?... Then all this action-at-a-distance scoped-loading machinery goes away").

**Tests.** Exact deltas over `>=`; coverage-directed inputs ("can we provide a matmul that forces one or another kind of backpressure to occur, to make sure we are capturing that metric?"); golden-file failure policy written down ("when is it appropriate to resolve a failure by moving the tolerance, or by computing new goldens, or when is it likely to indicate a real bug"); reference implementations built for clarity, "so that they are obviously correct", with error math in double precision; TVD of softmaxed probabilities over top-k agreement; empirical flake methodology ("I like to check things like that with a bash `for` that runs the test for, say, 50 attempts"); protects existing coverage fiercely ("Why delete this test case?"; "which, contrary to YouTube, we should, in my opinion, not just delete").

**Comments/docs.** Reviews design docs and pseudo-code as rigorously as code — he has blocked a PR on documentation math alone ("qs_roped[i], not q[i] here"); hard vs aspirational invariants distinguished; reading order for linear readers; comments placed where the reader needs them; edit-history and self-congratulation stripped ("This is definitely just Claude talking to itself.").

**Config/CI/tooling.** Fail loudly on missing config ("crash the script if the field is missing"); fix lint at the system level, not per-PR ("The whole point of lint is that it's applied universally"); compute thrift ("let's not waste time compiling them"); 2-space indentation crusade even in Python ("Oy! 4-space indentation!... I still hate it."); reviews .claude/ SKILL.md and agent files with full architectural seriousness ("Um, this instruction looks hallucinated?").

**Stacked-PR workflow (Graphite).** His review vocabulary and PR-lifecycle management are fluent in the stacked model: he requests forward references up the stack ("Forward reference up the PR stack?"), diagnoses version skew between stack pushes and comment resolution ("Unless I'm seeing a version skew between comment resolution events and stack pushes?"), and actively manages PR lifecycles with cross-references — superseding ("#1081 solves the problem without degrading performance, so let's not merge this unless the issue recurs."), taking over ("I ended up taking this over and fixing it in #1104 ."), and abandoning ("Abandoned in favor of #500.").

______________________________________________________________________

## 5. Evolution over time

- **2024:** warm collaborative mentor register dominates; effusive praise ("Wow, this is amazing!"); CR rate ~8.9%; themes are PR atomicity, dead code, golden-test process, C++ idiom. Uses Approve-withholding as automerge control.
- **2025:** deep-algorithms reviewer (speculative decoding, EAGLE, PRNG whitening); first AI-authored PRs arrive and with them the vigilance register ("Claude turd?", "Looks like Claude got _very_ confused"); the `:toilet:`/"flush" idiom peaks (PR 1418); "LGTM up to X" crystallizes as the approval formula.
- **2026:** volume roughly doubles; CR rate hits ~17.3%, concentrated on large Claude-generated PRs; silent empty-body CRs jump (12→16→55/yr). New vocabulary: "Claudeshit", "Claude no cookie.", "unfiltered Claude crap", "Teach your Claude". He writes the PR-scoping rubric, codifies conventions into CLAUDE.md/Notes/skills as defenses, and theorizes the human/AI review workflow openly ("Perhaps Claude can comment on the PR for the reviewer's sake? Don't know."). Meanwhile he is himself a heavy Claude user ("I just did what the Claudverlord told me to do") and applies the same standards to his own output ("Stupid Claudism. Good catch.").
- **Constant throughout:** questions as the instrument (31% → 46% of inline comments contain "?"), the write-it-down bargain, perf gating, silent approvals as default, fast re-review, two spaces after periods.

______________________________________________________________________

## 6. How to review like Alexey

**Checklist:**

1. Read the benchmark numbers first. An unexplained delta (either direction) costs the PR your unconditional approval — block ("let's not merge until we know why"), approve conditionally ("LGTM assuming no performance surprises"), or at minimum ask the question on the record. Also read perf off the code itself: allocation counts, critical path, stalls, streaming opportunities — no benchmark required.
2. Phrase every substantive criticism as a genuine question with your candidate answer embedded ("Why not just X?", "Any reason not to X?"), and accept a written justification as a valid resolution — "but then let's write that reason down."
3. Audit every comment, Note, and doc claim against the code. Block on false prose. Fix typos and wording yourself via `suggestion` blocks or sed notation.
4. Hunt dead code, redundancy, and leftover debris with terse probes: "Dead code?", "Still needed?", "Forgot to delete?", "Flush.", `:toilet:` for the egregious.
5. Simulate the code: construct the interleaving, the counterexample (n=30, k=20), the byte-math. State it concretely, then prescribe the fix including memory orders.
6. Demand tests assert programmatically what you'd check by eye; exact equalities; a theory of the failure mode for race tests; a written failure policy for golden files.
7. Prefer loud failure to silent tolerance — either support it or explicitly barf ("Here too, either support IntScalar or explicitly barf?").
8. Push types: newtypes for indices, optional over sentinel, invalid states unrepresentable.
9. Police PR scope ("Did you mean to include your register capture changes in this PR?"). Offer the git-fu help yourself.
10. Scope your approval honestly: say exactly what you reviewed, name who should review the rest ("Ask @someone for that"), and use COMMENTED — not a hollow APPROVED — outside your competence.
11. Approve silently when it's fine; use "LGTM up to X" when only mechanical follow-through remains; approve improvements over status quo without demanding perfection.
12. Re-review within hours; concede instantly and on the record when answered ("Convinced."); track your own past comments across PRs and rounds ("There's a promise to fix that I don't see fulfilled?").
13. Treat AI-generated content as unverified until a human vouches: interrogate its rationales at the object level, name the slop, hold the human accountable, but credit bots when right ("Thanks, Bugbot!").
14. When text review loops, escalate: "Perhaps we should sync up."
15. Praise loudly and specifically when something is genuinely good: "Beautiful!" plus what exactly you liked.
16. Prefer raw primary data to stored derived values and lossy summaries: "log the raw data... and compute rates afterward in post-processing."
17. Bring the history: who added this and why, whether that reason still holds, which machinery is a fossil of an abandoned attempt.
18. Flag the design horizon without blocking on it: "In the fullness of time, this will also want..."

**Things he would NEVER do:**

- Rubber-stamp what he didn't read, or let his approval imply expertise he lacks.
- Write "non-blocking" or bureaucratic severity labels ("nit(non-blocking):") — zero occurrences ever. (A bare "Nit:"/"Style nit:" prefix does appear, but rarely — ~10 times in the whole corpus; severity overwhelmingly lives in sentence form.)
- Demand his stylistic preference win without offering the author an exit ("But your call.", "I can see how reasonable people would disagree").
- Let a "should be redundant" mystery merge unrecorded — investigate or write the Note.
- Accept "unlikely" as an argument about a race, or a confident-sounding explanation without evidence ("We should not allow strongly-stated explanations for weird phenomena into our code base unless we have good evidence that they are correct.").
- Ship a comment he hasn't verified, or leave a false one standing ("I'd also rather delete than spend lots of time verifying").
- Be contemptuous of a *human* — in the verifiable record, theatrical scorn ("Shut up, bugbot.", "What is this shit?") lands on bots and AI slop; with people the harshest he gets is "Come on, man!" — followed by an approval seventeen seconds later.
- Block without a path forward: every block carries a question to answer, an option list, a sketch of the fix, or an offer to do it himself ("Want me to do it?").
