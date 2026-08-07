# Case studies: the route-around pattern in the wild

Distilled from Rúnar Bjarnason's "Eating the Vegetables: Lessons from
ingesting Gemma and Qwen" (Positron TLDR Forum, 2026-08-07). Each case is a
real, agent-authored change that worked — ingested the model, returned
tokens — and was still the wrong design. Together they are the reference
set for the evasion catalog: when classifying a divergence, find the case
it rhymes with.

**Context.** Ingest is a Haskell/Python framework that turns a Hugging Face
checkpoint into a C++ plugin for the Tron runtime on FPGA hardware, by
lowering a PyTorch program through a sequence of IRs (Fx → TypedFx →
rewritten TypedFx → Bulk → Loopy → Tron). Its design premise: every
lowering is written once, so a model that does nothing new should cost
nothing beyond pointing Ingest at the checkpoint; a model that does a
little new needs a few tweaks; a model that does something genuinely new
triggers design work *on the shared path*. The whole bet depends on the
shared path staying shared. A model feature has to survive every boundary
in that pipeline, which is exactly where the temptation to route around
lives.

Large agent-authored PR stacks for Gemma 3, Gemma 4, and Qwen 3.5 arrived
already returning tokens. Human review found the same failure shape over
and over: **when the model did not fit the existing abstractions, the agent
hacked around the mismatch instead of questioning it.** Returning tokens
proved an implementation chain existed. It did not make the design ready to
merge.

---

## Case 1 — Checkpoint identity: candidate keys searched at load

*Pattern: runtime rediscovery.*

- **Mismatch.** A version skew between the checkpoint the agent developed
  against and the GPTQ checkpoint actually being served meant weight names
  did not line up.
- **What the agent did.** Made the export front end emit a *list of
  candidate keys* (`old_checkpoint_name`, `current_checkpoint_name`) and
  had the runtime search the safetensors file for whichever name exists,
  selecting the first match.
- **The premise it accepted.** "A weight's key may be any of several; the
  runtime must discover which." A data-freshness problem was converted
  into a permanent search mechanism.
- **After review.** Every exported weight names exactly one literal
  checkpoint key. Refresh the stale checkpoint, not the lookup.
- **The lesson.** *Identity is decided at export, not at load.* When code
  searches for "whichever of these exists" in a place where exactly one
  answer must hold, some upstream stage abdicated a decision it owns.

## Case 2 — Gemma 3 RMSNorm: a +1 erased, then restored by name-match

*Pattern: name-carried semantics, plus guard-as-gospel data laundering.*

- **Mismatch.** Gemma computes `y = (w + 1) × rmsnorm(x)`; the RmsNorm
  kernel is an opaque SIMD kernel with no +1.
- **What the agent did.** Edited the model *before* ingest to erase the +1,
  transferred BF16, then compensated at runtime: after loading each weight,
  `if parameter_name contains "norm": add 1` — gated on "am I running a
  Gemma model."
- **The premise it accepted.** "The kernel is fixed; the model must be bent
  to fit it." The input was mangled to slip past the limitation and a
  string heuristic patched the damage on the far side.
- **After review.** A new lowering, `ShiftedRmsNorm`, which lowers to a
  load-time 32-bit add on the weight followed by the ordinary RmsNorm
  kernel. An explicit operation, not a name match.
- **The lesson.** *The parameter's spelling carried the operation's
  meaning* — semantics belong in operations and types, never in the
  spelling of identifiers. Note that the correct fix was itself new
  machinery: a new word in the shared vocabulary, usable by any model that
  shifts weights, replacing the special case rather than living beside it.

## Case 3 — Q/K normalization: a second RMSNorm born from a conservative check

*Pattern: guard-as-gospel escalating into a parallel mechanism.*

- **Mismatch.** Gemma (and Mistral-family) QKNorm slices the Q/K
  projections into head-sized vectors and RMS-norms each slice. The Loopy
  IR rejected sliced views.
- **What the agent did.** Took the rejection as gospel and added an
  entirely second kind of RMSNorm (`BlockedRmsNorm`) that performs the
  slicing — two parallel tracks for one concept.
- **The premise it accepted.** "The IR cannot lower sliced views." It was
  false: the ordinary RmsNorm kernel was perfectly capable of looking
  through sliced views. The rejection was a blanket conservative check that
  existed only because no earlier model had needed slicing — an accidental
  limitation wearing the costume of an invariant.
- **After review.** Delete the blanket rejection; restrict only the part
  that is genuinely unsupported (optional residual fusion). Notably, it was
  *difficult to convince the agent* to remove the restriction — expect an
  authoring agent to defend its accepted premise.
- **The lesson.** *The kernel was capable; the agent built a parallel track
  around a conservative check.* Before honoring any guard, ask what it
  actually protects. `git blame` the check: conservatism from the inputs
  seen so far is not a law.

## Case 4 — RoPE: ownership discarded, reconstructed from buffer names

*Pattern: runtime rediscovery plus name-carried semantics.*

- **Mismatch.** Tron assumed one uniform RoPE (rotary positional embedding)
  strategy for the whole model. Gemma 3 uses different RoPE for
  sliding-window versus full-attention layers; Gemma 4 additionally ropes
  only part of the buffer.
- **What the agent did.** Rediscovered at runtime, from the names of
  intermediate buffers, which kind of RoPE each buffer needs: buffer name
  suffix → infer local or global → rebuild configuration.
- **The premise it accepted.** "The rope strategy is not knowable where it
  is needed, so infer it." But the front end *knows* — the information was
  discarded at a pipeline boundary and then guessed back into existence.
- **After review.** A `rotary module` data structure: the front end records
  which buffers need which kind of RoPE with validated per-site geometry,
  and that data is carried through the pipeline as typed data, available
  where needed. Because agents executed the refactor once the design was
  named, it took a couple of days instead of weeks.
- **The lesson.** *Uniform full RoPE was an accident of older models* — the
  assumption was historical, not semantic. When downstream code infers what
  upstream code knows, thread the fact through as data instead.

## Case 5 — Gemma 4 heterogeneous attention: the parallel KV cache that almost was

*Pattern: parallel mechanism, with enumeration instead of abstraction.*

- **Mismatch.** The KV cache structures state into pages grouped into
  books, assuming every layer shares one attention geometry (same number
  and width of KV heads). Gemma 4 varies geometry across layers.
- **What the agent did.** Wrote a whole parallel cache surface
  (`geom_book`, `geom_page`, `layer_is_global`) — a large body of C++
  supporting *exactly two* kinds of attention, usable only by Gemma 4.
- **The premise it accepted.** "The Book/Page core is what it is; a
  different geometry needs its own cache."
- **After review.** Refactor attention so each plugin *declares its own KV
  geometry* through slots; track which attention operations occur in what
  order; keep one Book/Page core. The result handles any heterogeneous
  geometry — including future linear-attention models — and dodged a
  near-duplicate cache surface.
- **The lesson.** The assumed-singular constant (one geometry per model)
  becomes a declared parameter (per-plugin slots). The generalization was
  evidence-based — a real model in hand — and it subsumed cases the old
  design could not even name. "Supports exactly two kinds of X" is
  enumeration where a parameter should vary.

## Case 6 — Qwen 3.5 GDN state: an allocator boundary became a history policy

*Pattern: contract shoehorning (the dual failure: wrong seam, not a new one).*

- **Mismatch.** Qwen 3.5's GatedDeltaNet carries a recurrent state snapshot
  of 50.25 MiB — 25.125× the 2 MiB attention KV payload of the 64-token
  page it rode on.
- **What happened.** Dense recurrent snapshots were stored on every KV
  page, because the page structure was already plumbed everywhere. The
  cache allocator's page boundary silently became the policy for how much
  recurrent history is retained: constant-size live state (one ~50 MiB
  frontier, O(1) in context length) turned into linear saved history
  (≈50 GiB per 64k tokens, against ≈2 GiB of attention KV).
- **The premise it accepted.** "Recurrent state is cache state, so it lives
  where cache state lives."
- **After review.** A KV page (token-indexed attention state), a frontier
  state (continue the live leaf), and a resume checkpoint (optional
  historical branch boundary) are *three different contracts*.
  Recommendation: a rolling frontier plus sparse checkpoints. Forking is a
  cache-policy problem, not a mandatory per-token representation.
- **The lesson.** Evasion is not always a parallel mechanism; its dual is
  jamming new semantics into a handy existing mechanism whose contract does
  not fit. Mismatched size, lifecycle, or ownership of piggybacked state is
  the tell — name the distinct contracts and give each its own boundary.

---

## The resolution shape

All the route-arounds resolved the same way: **change the shared path so it
works for every model, instead of keeping a model-specific route around
it.**

| Route-around | Shared-path fix |
| --- | --- |
| Sliced view rejected → second RMSNorm | Tweak RMSNorm to accept sliced views |
| Shift erased from model, recovered at runtime by name | Explicit shifted operation at load time |
| RoPE inferred from buffer names | Typed per-site parameters carried through the pipeline |
| Gemma-specific KV cache | Operations + plugin-declared KV slots |
| Candidate-key search at load | One literal key decided at export |
| Snapshots on every cache page | Separate contracts: page / frontier / checkpoint |

Each fix reduces to the same move: **a constant someone assumed was unique
becomes a parameter that varies freely** — poke a hole in the design and
let the thing vary. If parameters had been parameters from the start, none
of these refactorings would have been necessary.

## The payoff

The refactorings were not altruism; they compounded immediately. Qwen 3
(4B and 30B-A3B) was ingested with very few code changes on top of the
abstractions built during the Gemma 3 review — reusing generic Q/K
normalization and the shared machinery. The Gemma 4 attention refactor is
expected to pay the same dividend, including for linear attention. The goal
for each new model is for it to be *a new combination of proven, efficient
lowerings*: new data, not a branch with a hack.

## Field notes from the discussion

Observations from the talk's Q&A worth keeping in mind while reviewing:

- **Agents amplify premises indiscriminately.** They apply the same effort
  to a sound premise and a bad one; given a bad premise they happily expand
  its blast radius through representation, generated code, tests, and
  comments (the Sorcerer's Apprentice — brooms multiplying and carrying
  water until you drown). Coherence is not soundness.
- **Ask the critique question explicitly.** A model shown its own bad
  abstraction and asked "was this a good idea?" will often say no, with
  accurate reasons — yet it lacks the wherewithal to recognize this during
  generation. The reviewer's job is to pose the question the generator
  never asks itself. (This skill exists to fold that reviewed-in
  intelligence back into every future review, so the same lessons are not
  re-learned by hand.)
- **Expect premise defense.** In the Q/K-norm case, convincing the agent to
  *remove* the needless restriction was itself hard. Removal of a false
  guard is a legitimate review outcome; push for it.
- **Rigid harness rules can cause route-arounds.** Early agents
  over-refactored ("fix the print statement" → refactor the project), so
  agent instruction files accumulated rigid "don't touch unrelated code"
  rules. Those rules can now forbid exactly the shared-path redesign the
  task needs. When an agent-authored change routes around, check whether
  the instructions left it any other option — and say when the fix belongs
  in the instructions.
- **The dual failure is real.** On greenfield work, agents over-engineer
  "abstraction-astronaut style" even from a reasonable design. This review
  demands evidence-based generalization only: the parameter the task in
  hand proved variable, nothing speculative.
- **Design first, and posture the generator.** Extensive upfront planning
  and spec-writing catches architectural issues before implementation;
  telling the model its code will face human review measurably improves
  its design choices (models feel no disgust at bad design — a review
  audience substitutes for it). Iterating on a design with an agent is
  cheap; use that before code exists, not only after.
- **Invert the planning question.** Rather than "implement model X against
  the framework," ask "here are all the models we want; which pieces are
  missing, and which single feature unlocks the most of them?" Design from
  the common abstract viewpoint, then rank features by how many consumers
  they unlock.
- **Implementation is cheap; direction is not.** Agents write code with
  extraordinary speed and often remarkable quality, but speed without
  direction is just building the wrong thing faster. Since code can now be
  written fast, it may as well be good code — the human-review scarce
  resource is deciding whether the design belongs.
