# The promptdeploy reconciliation oracle

`doc/migrations/promptdeploy-reconciliation.json` is a committed expectation
artifact: 295 lines of recorded inventory that drive 115+ generated assertions in
`test/ai/home-manager-contract.nix`. It has the same standing as
`test/baseline/parity-<rev>.json`, and until now it had no equivalent of
`doc/PARITY-ORACLE-REFRESH.md` — the assertions were present but not
maintainable, because nothing said what they encode or when the encoding may
change.

Written in response to a partner observation on `13e69093`
(`doc/observations/2026-07-28T23:11:20.640Z.md`).


## What it reconciles

Promptdeploy was the pre-Nix owner of agent prompt/skill deployment. Moving that
ownership into Nix means two inventories must be shown to agree: what promptdeploy
deployed, and what the Nix catalog now selects. The JSON records the *source* side
of that comparison so the contract can assert the *Nix* side against it without
re-reading promptdeploy at evaluation time — which it could not do anyway, since
promptdeploy is not a flake input of this repository.

The oracle is therefore a **frozen transcription of an external system's state at
a point in time**, not a derived quantity. That distinction drives every rule
below: a derived artifact is refreshed by re-deriving, but this one can only be
refreshed by a human re-reading the source.


## Top-level keys

All nine keys, because a key table that silently omits keys is the same class of
defect as the commit message that prompted this document:

| Key | Meaning |
|---|---|
| `schemaVersion` | Currently `1`. Bump when the *shape* changes, so a reader can tell a shape change from a content refresh. |
| `reviewedSource` | The promptdeploy `{repository, commit, tree, commitDate, worktreeState}` a human actually read to produce this file. The provenance anchor: without it the inventory is an unattributable assertion. Recording `tree` as well as `commit` means a dirty worktree cannot masquerade as a clean revision. |
| `inventory` | The transcribed source inventory, by surface. Currently `agents: 26`, `commands: 66`, `skills: 23`, `prompts: 2`. Non-empty per key is what makes the generated checks non-vacuous. |
| `selectors` | The audience/client partitioning the source applied — `commandAudiences`, `commandExtraClients`, `skillAudiences`, `skillClients`. This is what lets the contract assert *who* each item was deployed to, not merely that it existed. |
| `models` | Model routing as the source had it: `authority`, `default`, `sourceOnlyDisposition`, `sourceOnlyStaleTuples`. `sourceOnlyStaleTuples` records model pins that exist only in the source and are known stale — recorded so they are not mistaken for Nix-side omissions. |
| `postFrozenDelta` | Changes observed in promptdeploy *after* `reviewedSource` was frozen, recorded rather than silently folded in, so the freeze stays honest. |
| `nixOnly` | Surfaces Nix owns that promptdeploy never had. Expected asymmetry; listing them prevents a reader from reading their absence as a gap. |
| `unchangedSourceSurfaces` | Surfaces deliberately left as-is. Distinguishes "reconciled and equal" from "not yet examined". |
| `documentationDisposition` | Per-item decision about the prose that accompanied each promptdeploy surface: migrated, superseded, or dropped. |


## When it is refreshed, and when it is frozen

**Frozen** for all ordinary work. A failing promptdeploy assertion means the Nix
selection changed; the fix is in the catalog, not in the oracle. Editing the
oracle to match a changed selection converts a real regression into a green
build, which is the same laundering `doc/PARITY-ORACLE-REFRESH.md` forbids for
the parity oracle.

**Regenerate only when** the promptdeploy source itself is re-read by a human and
`reviewedSource` advances with it. That is a deliberate act with a recorded
provenance change, exactly like a parity-oracle refresh. `postFrozenDelta` exists
so that a known-but-not-yet-transcribed source change can be recorded without
forcing a full re-read.

**Retire** when promptdeploy ownership is fully transferred and #83 closes: at
that point the reconciliation has served its purpose and the assertions become
history rather than a live gate. Retirement is a decision to record on #83, not a
cleanup to perform silently.


## Where the assertions are wired

`test/ai/home-manager-contract.nix` — `promptdeploySourceItemChecks` and
`promptdeployCapabilitySelectionChecks` feed `promptdeployReconciliationChecks`,
which is consumed alongside the rest of the contract. Verify non-vacuity before
trusting a green result:

```bash
python3 -c "import json; d=json.load(open('doc/migrations/promptdeploy-reconciliation.json')); print({k: len(v) for k, v in d['inventory'].items()})"
nix build --no-link .#checks.aarch64-darwin.ai-home-manager-contract
```

An empty inventory key generates zero checks and still passes — the count above is
the guard against that, and it is the reason this file says "non-empty per key"
rather than "the checks pass".


## Serves

jwiegley/nix-config#83 (Promptdeploy-to-Nix AI capability reconciliation).
