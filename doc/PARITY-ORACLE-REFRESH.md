# Parity-oracle refresh policy

*Owning issue: [jwiegley/nix-config#31](https://github.com/jwiegley/nix-config/issues/31).
Prerequisite: [#19](https://github.com/jwiegley/nix-config/issues/19), the initial
capture, is closed.*

The fleet parity oracle is the single committed artifact
`test/baseline/parity-<rev>.json`, derived by `bin/parity-baseline`. Nearly every
parity gate in the Fleet Configuration Programme is phrased "byte-identical to
baseline". A baseline captured at one revision drifts into meaninglessness the
moment `main` advances: `a36d3f51` was 68 commits stale before anyone noticed,
and it also predated the overlay-factory refactor `a3cc3843`, so demanding
byte-identity against it could never have been satisfied. This document states
when the oracle advances, who advances it, how, and what stops a gate from
silently comparing against a stranded oracle.

The policy is enforced by a mechanism, not by memory. The human-facing half is
this document; the machine-facing half is `bin/oracle-currency-test.py`, run on
every commit by `bin/quality`'s `python-test` suite.


## The cost boundary, stated first

Deriving the oracle costs roughly five minutes and requires cross-system
`nix eval`. Advancing it is therefore a deliberate act, not something a gate does
on your behalf. The **currency guard is cheap**: it reads the committed artifact
and git metadata only, and never re-derives, never builds, never evaluates Nix.
It can tell you the oracle is stranded or internally inconsistent in
milliseconds; it cannot tell you the oracle's *numbers* are still correct, because
that is what the expensive derivation is for. Keep the two apart:

- **Determinism and multiset/drvPath equivalence** — `bin/parity-baseline --check`
  / `--compare`. Expensive. Run by a person, or by a refactor's own parity gate.
- **Currency, consistency, provenance, command-currency** —
  `bin/oracle-currency-test.py`. Cheap. Run on every commit.


## Trigger — when the oracle advances

The oracle advances when, and only when, **a parity-affecting change has landed on
`main` and that change's own parity gate has closed** — that is, its
`bin/parity-baseline --compare` against the current oracle showed one of:

1. **Parity-clean**: the selected-package multiset is identical on every target,
   and any `drvPath` movement is the expected consequence of an additive source
   change (for example, a new file under `bin/` moves every host toplevel that
   packages `nix-scripts`, while the multiset is untouched — measured, not
   assumed). `--compare` exits 0 for this case.

2. **Parity-explained**: the multiset moved, but the landed change's own parity
   gate examined and *accepted* every added and dropped package as intended.

The oracle does **not** advance:

- on every commit — that would make the oracle always agree with the present and
  destroy its value as a fixed comparison target;
- on an **unexplained** multiset drift — that is a parity failure the landing
  refactor must resolve or justify before anything is recorded. A refresh records
  an accepted result; it never launders an unexplained delta.

Deciding whether a given delta is acceptable is **out of scope** here — that is
each refactor's own parity gate's job. This policy only governs recording the
accepted outcome and keeping the oracle current.


## Owner — who advances it

The person landing the parity-affecting change owns the refresh, in the **same
signed commit series** that lands the change (or the immediately following one).
Advancing the oracle needs no special authorization: it is read-only Nix
evaluation plus one signed data-file commit, exactly as the initial capture was.
There is no scheduled bot and no auto-advance; a five-minute cross-system
derivation is a human's deliberate act.


## Mechanism — how it advances

```bash
# 1. Confirm the landed change is parity-clean-or-explained against the oracle.
bin/parity-baseline --compare test/baseline/parity-<old>.json

# 2. Advance. REFRESH_REASON is mandatory; REFRESH_DELTAS is required only when
#    the multiset legitimately moved (case 2 above).
REFRESH_REASON="overlay-factory refactor landed parity-clean (#NN)" \
  bin/parity-baseline --refresh test/baseline/parity-<old>.json

# for an explained multiset move:
REFRESH_REASON="lean-profile split (#NN); drops gopls on clio, accepted" \
REFRESH_DELTAS=$'lost darwin/clio: gopls' \
  bin/parity-baseline --refresh test/baseline/parity-<old>.json

# 3. Stage the new artifact and the removal of the old one, then commit (signed).
git add test/baseline/parity-<new>.json
git rm  test/baseline/parity-<old>.json
```

`--refresh` re-derives at HEAD with the command already recorded in the oracle,
refuses if the multiset moved without an explanation, and writes the new artifact
with a **provenance chain** appended. The superseded artifact is removed from the
working tree: Git is the archive, and exactly one oracle is ever tracked.


## Provenance — the auditable lineage

From the first refresh, the artifact carries a `history` array and its schema
advances from `fleet-parity-oracle/1` (the genesis capture) to
`fleet-parity-oracle/2`. Each entry records one advance:

```json
{
  "old_rev": "e0ed94fabbc054e36e08f2684123f248bffcf932",
  "new_rev": "1111111111111111111111111111111111111111",
  "reason":  "overlay-factory refactor landed parity-clean (#NN)",
  "intentional_deltas": []
}
```

The first entry is the genesis link (`old_rev: null`, `new_rev` = the #19 capture
rev), synthesized on the first refresh so the chain is auditable from birth rather
than from first advance. The chain links head-to-tail (`old_rev` of each entry is
the previous entry's `new_rev`) and its final `new_rev` is always the artifact's
own `baselineRev`. Landing #31 means the committed oracle reaches schema `/2` with
a non-empty history: this is exactly the issue's `jq -e '.history | length >= 1'`
pass condition.

Provenance is deliberately **inline** in the artifact rather than in a sibling
log, so a single file is the whole truth. The one consequence is that a literal
`--check` would see the `schema`/`history` fields as "drift"; Block 3 of the
accompanying `parity-baseline.additions` handles that by comparing the derived
core only, and is optional (see that file for the tradeoff).


## Enforcement — what happens when the policy is violated

`bin/oracle-currency-test.py` fails the build — `bin/quality python-test`, hence
lefthook and CI — when any of the following is true of the committed oracle. Each
is a mechanical check over the artifact and git metadata; none re-derives.

| Violation | Guard verdict |
|---|---|
| The oracle's `baselineRev` is **not an ancestor of HEAD** | FAIL — *stranded baseline*. A parity-affecting change landed and no one refreshed; the oracle no longer sits on this line of history and every "vs baseline" comparison is meaningless. |
| `baselineRev` does **not descend from `a3cc3843`** | FAIL — an oracle predating the overlay-factory refactor can never be satisfied by post-refactor work. |
| `baselineRev` is **not a real commit** here | FAIL — the oracle names a rev that does not exist in this repository. |
| The **filename** encodes a different rev than the recorded `baselineRev` | FAIL — the exact inconsistency the `--write` double `git rev-parse` bug produced; a baseline whose name and contents disagree is worse than none. |
| More than one, or zero, `test/baseline/parity-*.json` | FAIL — a superseded oracle belongs in git history, not a second tracked file. |
| Any target's `packageCount` ≠ `len(packages)` | FAIL — a count kept apart from its list has drifted from it. |
| The recorded derivation **command diverges** from `bin/parity-baseline` | FAIL — the oracle would be derived by a different command than a later gate uses (for example, after the `#47` `config/ai` → `config/fleet` rename). |
| The oracle's `schema` is **unknown** to the guard | FAIL — a silently accepted unknown schema is how a format drift goes unnoticed. |
| The `history` chain is malformed, mis-linked, or its tail ≠ `baselineRev` | FAIL — the lineage is not auditable. |
| A `/2`+ oracle carries **no history** | FAIL — provenance is mandatory once the oracle has advanced. |

Two checks are *forward-armed* rather than immediately hard, so the guard lands
and stays green before the refresh mechanism is wired, then tightens on its own:

- **Command currency** SKIPS (loudly, naming this document) until
  `bin/parity-baseline --commands` exists; once it does, command drift is a hard
  FAIL.
- **Provenance** is optional at the genesis schema `/1` and mandatory from `/2`.
  The first `--refresh` writes `/2`, and from then on a missing or malformed chain
  fails. The guard emits a visible SKIP while the oracle is still at `/1`, naming
  this document, so the pending transition is never silent.

The negative side of every row above is proven, not asserted:
`bin/oracle-currency-test.py` ships its own `OracleGuardSelfTests`, which mutate
synthetic oracles in throwaway git repositories and assert each check fires.


## Rollback

Repo-local. The policy is this document plus the guard test; revert the commit to
remove them. Advancing the oracle is an ordinary signed data-file commit with no
host state and no blast radius.
