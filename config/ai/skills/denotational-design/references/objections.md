# Objections, and the answers Elliott gives

Every engagement surfaces some of these. Do not improvise the answers —
these are the ones Elliott actually gives in talks and Q&A, with his own
grading: some objections he refuses as wrong questions arising from
conditioning, some he treats as substantive and answers in full, and one
he concedes on the facts and contests on values. The grading is itself
method — deflecting a substantive objection, or litigating a refused one,
both lose the room.

## The discreteness cluster

**"The output is discrete/finite anyway."** The objection is about
fidelity; the answer is compositionality. "They don't realize that that
bug breaks compositionality — and compositionality is our superpower for
solving problems. It is one of the worst possible things to break."
Approximation is legitimate; approximating *before* composing is not —
"when you compose approximations you get something that is no longer
approximately correct; you get something that's grossly incorrect."
Approximate once, last.

**"An exact/continuous model is a luxury we can't afford."** Discrete
models are *both* less precise and less efficient: zooming in magnifies a
bitmap's errors ("a continuous image is perfect to begin with"), zooming
out still touches every sample. "Every discrete system is both
unnecessarily imprecise and unnecessarily inefficient." And the measured
cost of Elliott's maximally permissive image model was "really none that I
could notice" — the library ran interactively, in real time, with GUI
sliders, and was implemented several times, "vastly different from each
other."

**"But nature really is discrete."** Then you inherit nature's frame rate
too (~10⁻⁴³ s), and "nothing made out of nature can run at nature's own
rate" — so a discrete model is committed to being wrong by construction,
while the continuous model's step size of 0 is far closer to 10⁻⁴³ than
any implementable sampling (10⁻⁶…10⁻¹²). "The continuous model is much
more faithful to a quantum discrete reality than anything we could build
out of nature."

**Concrete round-trip ammunition** (for the skeptic who wants cases, not
principles): under an integral-coordinate model, rotate by θ then −θ is
not the identity; zoom out by a trillion and back in does not recover the
image; move an object out of a finite window and back and it is gone.
Interpolation does not rescue it, it relocates the damage: "it's
complicated to specify. And it's arbitrary — linear, cubic, quadratic,
Chebyshev? And no nice mathematical properties will hold." Conclusion:
"discreteness is harmful to simple composability. Finiteness is harmful to
simple composability."

**"Users don't care about laws."** "They might not walk in and say, hey, I
wanted my trigonometric identities to hold, and they don't. That's just
because they don't have the language for saying that. They'll still get
unexpected results — they just might not be able to articulate their
disappointment or confusion."

**Teaching order**: introduce continuity in *space* first (bitmap →
outline fonts, raster → vector — a subtraction programmers already
accepted), then note the argument in time is identical — "shields don't go
up quite so quickly and rigidly." Name the asymmetry as conditioning by
the von Neumann loop, not as a difference in the argument.

## The scope cluster

**"Let's keep a functional/denoted core and an imperative shell."** Any
paradigm boundary drawn by scale or layer is parochial: "there is no small
and large… every line you draw between big and small is incredibly
parochial. It's like every king saying the new unit of measurement is the
distance from my shoulder to my fingertip." (This skill's own carve-out
for I/O glue is an effort budget, not a counter-doctrine — see SKILL.md.)

**"Why not just write a reference interpreter / small-step rules?"**
Operational semantics compresses the quality range — "the beautiful stuff
becomes uglier, the uglier stuff becomes less ugly" — so you lose the only
instrument that tells a good design from a bad one. That range compression
is, in Elliott's telling, why denotational semantics was displaced: "it
continued to point out in great detail the ugliness of certain programming
ideas." An operational account is also a premature commitment to an
execution shape, usually sequential: "you have to undo that work to get
back to something more denotational, and then you can go forward. So it's
harder, not easier." And: "operational semantics may show you that indeed
it's computable, but I don't want something computable. I want a good
implementation."

**"Our domain really is machine-shaped / unstructured collections."** The
objection does not exempt the design; it relocates the mess. "I say: what
does it mean? What's a mathematical meaning that is precise, elegant, and
adequate? There may be some really important reason to use certain data
structures and match the machines I'm using — but none of that do I want
to appear in the API. All of that is representation. Those are all
important things *after* I've found the API."

**"The existing API is simpler."** "Often when people say simple, they
really mean familiar… a Python programmer may think Python programming is
simple, but if they made it mathematically precise, they would have to see
how complex it is." The test is what the meaning looks like written down
precisely, not how comfortable the vocabulary feels. For engineers,
familiarity is close to an anti-signal: "quite often what I'm calling
elegant is the opposite of familiar to programmers."

## The theory cluster

**"Full abstraction fails for these models."** Two independent responses.
Technical: the failure tracks a commitment to *sequentiality* — Haskell's
`and` is subtly asymmetric at ⊥ (`and False ⊥ = False`, `and ⊥ False =
⊥`); the missing piece is parallel-or/and, and "the problem is the
implementer is thinking: which do I evaluate first? There is no winning
answer. To a hardware person this is a non-issue — this issue is all about
language designers being afraid of parallelism. It's very easy to fix."
(It does not arise in a total language.) Framing refusal: "the very
pretext of the question assumes that operational semantics is the defining
thing that denotational semantics has to live up to… the goal is not for
denotational to match operational any more than the reverse."

**"What about strong normalization / progress and preservation?"** "That's
something you've been trained to want… you can get people addicted to it.
It's not a natural thing to want." Redirect: operational semantics is a
means, not an end, so it cannot be the goal; the goal is a machine
faithfully realizing a problem defined outside the technology.

**"Your meanings aren't computable, so they're vacuous."** "First, that's
not really true — the domains do include computability; that's why they're
continuous, CPOs. But aside from that, it doesn't matter": we compute with
representations and think with meanings, and the homomorphisms make the
difference undetectable through the vocabulary.

## The engineering cluster

**"You ignore the machine; this reduces to pure mathematics."** "Exactly
the opposite is true." The necessity chain: care about the implementation
→ then you care whether it is correct → then you need a specification →
if you want the correctness claim to be true, you need proof → for the
proof to be achievable and the theorem useful, you need elegance and
simplicity. "The more efficient you want, the more the proof becomes
necessary." Working mathematicians already run the two-artifact
discipline — Kaplansky on Halmos: "we think basis-free, we write
basis-free, but when the chips are down, we close the office door and
compute with matrices like fury" — and it works because the connecting
theorem is at the top of their heads.

**"Is proof worth the performance cost?"** First split the question: "is
it *proof* that's the problem, or is it *truth* that's the problem? Do you
want to eliminate proof because you don't want the work, or because you
don't want the inconvenience of dealing with the fact that your
implementation is wrong?" The reductio: give up correctness and "you can
get absolute ideal efficiency very easily — erase everything. It runs
infinitely fast and has no known bugs." Then the career-length
observation: "people optimize their software to the point where their grip
on its correctness is so shaky they don't dare optimize further —
optimization is self-defeating if done without proof." Proof is "not the
enemy of efficiency; it is the necessary ally of efficiency."

**"Formal methods are too slow for industry."** "Whether that claim is
true depends entirely on what your objectives are. If your objective is to
crank out more code that's probably wrong by a deadline, you should not
use formal methods — you don't need to be right, so you don't get the
value, and it'll take longer, because it's hard. But doing everything
right is hard. Everything." The compounding argument: "even if you say I'm
just after 95% probably correct — the only possible way to do that is to
be 100% correct… if every component is probably right, the whole thing is
probably wrong." (He flags this as falsifiable belief, not theorem.)

**"Nobody can learn Agda/Haskell; ecosystems win."** Conceded on the
facts: "pick a familiar paradigm and make a tiny tweak… you'll bring a lot
more people in." Contested on value: "But will you get anywhere of value?
If Galileo had come up with another small tweak to the theology of his
day, it would have been much more accessible… he would have taken
advantage of the popularity of muddled thinking." And the cost: "you're
contributing your life energy, which is non-renewable, to a dead end."
Expect the reception cost either way: "simplicity requires education to
appreciate… they're not jumping up and down to thank the inventor. They're
more like maybe annoyed."

## Conduct

Paraphrase every objection back and get confirmation before answering
("I'm going to try and paraphrase, and then you can tell me if I got it or
not"); park objections that arrive out of order rather than resolving them
("we're not even ready for that conversation"), keeping the parked list
visible; and when an objection cannot be answered on the spot, say so on
the record — "I'll chew on that… and then we'll talk and I'll find out I
misunderstood you." Admitting an open boundary beats bluffing: "I don't
know exactly what it needs. It could be simply a monoid. I'm not sure
exactly where the line is."
