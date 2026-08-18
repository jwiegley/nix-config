# Worked example: the image library

A reconstruction of Elliott's live image-synthesis seminar — the one place
the phases are shown *interacting*: a generalization in phase 4
retroactively justifies a phase-1 model choice; a phase-2 class question
forces a phase-1 parameterization; a phase-7 type enumeration exposes a
phase-1 over-restriction. Use it as the exhibit for any phase during a
dialog, and as the template for how much record-keeping a small design
needs. ("This part is not so much a talk as a seminar… this is exactly
what I do.")

## The brief and the un-meant sketch (phase 1 opening)

Goal: a library for building images. The API sketch is taken deliberately
and taken as raw material — type names (`Image`, `Region`, `Transform`,
`Color`) and operation signatures (`over`, `crop`, `transform`,
`monochrome`, `fromBitmap`/`toBitmap`), with meanings explicitly withheld:
"we don't yet have to know what those types mean." Only *how do we
implement* is refused.

## The candidate board (phase 1)

Criteria stated first — adequate, simple, precise; minimality deliberately
excluded. Bad suggestions solicited by name. The board, with what each
candidate smuggles in:

| Candidate | Baggage |
|---|---|
| matrix/array of pixels | resolution, bounds, discreteness — the JPEG fallacy |
| a way of collecting and saving light | capture technology |
| an OO interface of operations | operations, not an object; defers meaning |
| a collection of shapes (PDF/PostScript) | a particular drawing model |
| a scene graph with lights and cameras | the renderer's data structure |
| a short text conjuring a picture ("the poet's answer") | honored, priced, declined |
| **a function from a space to optical properties** | the survivor |

Chosen: `⟦Image⟧ = Loc → Colour`, with `Loc = ℝ²` — continuous and
infinite (round-trip and transformability arguments in `objections.md`).
`⟦Region⟧ = Loc → Bool`. He changed his mind to `Set Loc` on stage when
challenged ("a region's a set of points, that's it") and changed it back:
written as `Loc → Bool`, the two meaning functions "look fairly similar" —
which is what later makes `Region = Image Bool` visible. Among
interconvertible models, prefer the shape that exposes shared structure.

## Semantic equations by rote (phases 6–7)

Written by type-checking, not insight: "I'm not using imagination here.
I'm kind of running on rote… using my mental type checker to help me
generate code."

```
⟦over top bot⟧    = λp → ⟦top⟧ p ⊕ ⟦bot⟧ p
⟦crop reg im⟧     = λp → if ⟦reg⟧ p then ⟦im⟧ p else empty
⟦monochrome c⟧    = λp → c
⟦transform h im⟧  = ⟦im⟧ ∘ ⟦h⟧          -- see the wart below
```

The `λp` comes from the *meaning being a function* — "if the semantic
model were an array of pixels, you'd see `array i j`." The shape of the
meaning dictates the shape of every semantic equation. Un-inlining
(`⟦over top bot⟧ = overS ⟦top⟧ ⟦bot⟧` for a named `overS`) is an
unnecessary but clarifying step that makes the compositionality — and
later the morphism — explicit.

An audience member catches that `c` in `monochrome` and `h` in `transform`
are not wrapped in `⟦·⟧`. Accepted in full: "it means it doesn't have any
interesting meaning structure… colors deserve better treatment than that.
It makes me uncomfortable about the choice I made. It's great." — the
un-denoted-argument audit, live.

## The `transform` enumeration and the recorded wart (phase 7)

Candidates that type-check: `⟦im⟧` (ignores `h` — "none of us would be
satisfied"); `⟦im⟧ ∘ ⟦h⟧` (adopted); `⟦im⟧ ∘ ⟦h⟧⁻¹` — "that turns out to
actually be the right thing, **except that I don't know how to do it**."
Covariance is why it goes backwards: locations are in the *domain* of the
denotation, and "whenever that happens, things are going to go backwards"
(taught via *Honey, I Shrunk the Kids*: shrinking the kids made their
perceived world larger). The shipped compromise: the caller pre-inverts,
with hand-inverted specializations — "I'm not entirely proud of it" — and
the declined principled alternative (a class of invertible functions
closed under the operations, "a fine doable route") is on the record.

## The generalization cascade (phase 4, feeding back into 1 and 2)

`Image` → `Image a` (parameterize the *range*), one move with cascading
payoff:

- `Region = Image Bool` — one type deleted;
- `transformImage`/`transformRegion` unify into
  `transform : Transform → Image a → Image a` — "we not only unified two
  operations, we allowed infinitely many others";
- `crop` → `cond : Image Bool → Image a → Image a → Image a`
  = `lift3 ifThenElse` — "cropping is a special case of conditional";
- `monochrome` → `lift0`, `over` → `lift2 overC`, and `lift1` = `fmap`.

Evidence the generalization was real, not cosmetic: "images of images is
very interesting. Images of functions is very, very interesting. Images of
angles — you can rotate an image by a spatially varying angle. Very
bizarre and wonderful." The surviving over-restriction is also recorded:
`Transform = Loc → Loc` forces domain = range ("I can't change the shape —
I might have donut images… it's unnecessarily restrictive"); the better
choice parameterizes domain as well as range, "at which point they're just
functions."

The headroom check: can this API blur? No. Can the *model*? Yes (an
integral). "So that's nice — we haven't prevented it, we haven't enabled
it yet."

## The class sweep and the morphisms (phases 2–3, 8)

Order: monoid first ("monoids are types; functors are type
constructors" — Functor is only well-kinded after the parameterization,
which was itself a finding). Then Functor, Applicative, Monad, Comonad —
each recognized by grepping the written denotations against the Prelude's
`(->) a` instances: "I've seen that somewhere… oh my god, function is a
monoid when its range is a monoid." Law obligations are logged as debt
("pretend we did this work") and retired in one batch when the morphisms
land — "there's nothing about imagery except the homomorphism property
that makes these laws go through."

Foldable/Traversable fail, diagnosed by the semantic domain: "we don't
have foldables because it's continuous — there's too much. Maybe
traversables — some kind of integral thing. I'm not really sure." Recorded
open, not resolved. The comonad is *discovered*, not designed — "inevitably
implied by the denotation": at every point, the whole image shifted so
that point is the origin — "the most convenient possible coordinate
system" — giving continuous cellular automata and convolution ("go
crazy — sample it once, a hundred times, over a region").

Equality: pressed for the Applicative laws, he refuses to check them until
the audience produces extensional equality, then observes it *is*
denotational equality — "two images are equal iff their meanings are
equal." Equality before laws.

## The recorded warts (closing)

1. The un-denoted `Colour` argument — accepted primitive or unnoticed
   hole; flagged, uncomfortable, kept.
2. `Transform = Loc → Loc` forcing domain = range — "unnecessarily
   restrictive"; the parameterized alternative named.
3. The pre-inverted `transform` — "I'm not entirely proud of it"; declined
   alternative named.
4. `crop`'s `empty` was silently colour-specific — "there may be other
   things you want to crop."

Plus the parked questions that were never resolved (measurability of
regions; whether `lift1`/`lift2` admit too much) — legitimate outcomes,
kept visible. The elimination list: no pixels, no resolution, no bounds,
no scene graph, no rasterization anywhere above the display edge.
