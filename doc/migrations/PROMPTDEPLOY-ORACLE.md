# The promptdeploy reconciliation oracle

`doc/migrations/promptdeploy-reconciliation.json` is a committed expectation
artifact: 295 lines of recorded inventory that drive 115+ generated assertions in
`test/ai/home-manager-contract-common.nix`, consumed by
`test/ai/home-manager-catalog-renderers.nix`. It has the same standing as
`test/baseline/parity-<rev>.json`, and until now it had no equivalent of
`doc/PARITY-ORACLE-REFRESH.md` — the assertions were present but not
maintainable, because nothing said what they encode or when the encoding may
change.

Written in response to the review of `13e69093`, with the durable correction of
record in `9f26f24` and jwiegley/nix-config#83.


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
| `inventory` | The transcribed source inventory, by surface. Currently `agents: 26`, `commands: 66`, `skills: 23`, `prompts: 2`. Exact counts and non-empty keys are contract assertions, so a partial or empty transcription cannot erase its own generated checks. |
| `selectors` | The audience/client partitioning the source applied — `commandAudiences`, `commandExtraClients`, `skillAudiences`, `skillClients`. This is what lets the contract assert *who* each item was deployed to, not merely that it existed. |
| `models` | Model routing as the source had it: `authority`, `default`, `sourceOnlyDisposition`, `sourceOnlyStaleTuples`. The contract pins the frozen source default but does not require the live Nix default to remain equal; `llm-setup.el` owns current routing. `sourceOnlyStaleTuples` records source-only stale pins so they are not mistaken for Nix omissions. |
| `postFrozenDelta` | The exact 12-path delta from the original migration oracle `7a12b54` to reviewed source `8d09f9f`, each with an explicit disposition. It records what reconciliation added beyond the stale migration freeze; it is not a claim about changes after `8d09f9f`. |
| `nixOnly` | Surfaces Nix owns that promptdeploy never had. Expected asymmetry; listing them prevents a reader from reading their absence as a gap. |
| `unchangedSourceSurfaces` | Surfaces deliberately left as-is. Distinguishes "reconciled and equal" from "not yet examined". |
| `documentationDisposition` | Aggregate rationale for the conflicting prose that accompanied Promptdeploy model injection and why Nix does not inherit it. |


## When it is refreshed, and when it is frozen

**Frozen** for all ordinary work. A failing promptdeploy assertion means the Nix
selection changed; the fix is in the catalog, not in the oracle. Editing the
oracle to match a changed selection converts a real regression into a green
build, which is the same laundering `doc/PARITY-ORACLE-REFRESH.md` forbids for
the parity oracle.

**Regenerate only when** the promptdeploy source itself is re-read by a human and
`reviewedSource` advances with it. That is a deliberate act with a recorded
provenance change, exactly like a parity-oracle refresh. `postFrozenDelta` exists
to preserve the fully reviewed difference between the original migration freeze
and the current reviewed source.

**Closing #83 freezes the external refresh obligation; it does not delete the
regression checks.** Retire the manifest-backed assertions only when an explicitly
recorded replacement provides equivalent currency evidence. Retirement is a
separate decision, not cleanup implied by issue closure.


## Where the assertions are wired

`test/ai/home-manager-contract-common.nix` defines
`promptdeploySourceItemChecks`, `promptdeployCapabilitySelectionChecks`, and
`promptdeployReconciliationChecks`; `test/ai/home-manager-catalog-renderers.nix`
consumes them alongside the catalog/renderer contract. Verify non-vacuity before
trusting a green result:

```bash
python3 -c "import json; d=json.load(open('doc/migrations/promptdeploy-reconciliation.json')); print({k: len(v) for k, v in d['inventory'].items()})"
nix build --no-link .#checks.aarch64-darwin.ai-home-manager-catalog-renderers
```

Historically, an empty inventory key generated zero per-item checks. The contract
now asserts exact `26/66/23/2` counts, non-empty keys, and committed inline
empty/partial mutation checks before trusting the generated checks.


## Serves

jwiegley/nix-config#83 (Promptdeploy-to-Nix AI capability reconciliation).
