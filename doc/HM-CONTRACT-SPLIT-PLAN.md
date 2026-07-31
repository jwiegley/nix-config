# Home Manager contract split — design and mapping (jwiegley/nix-config#65)

**Status: designed and validated, NOT executed.**

Execution is blocked on a live concurrent edit, not on any technical question.
At the time this was written `test/ai/home-manager-contract.nix` had 32 lines of
uncommitted work in the main worktree (`positronPyTorchSkills`,
`personalOnlyProfileIds`, `positronProfileIds`), and this plan **deletes that
file**. Applying it would have destroyed or badly conflicted that work.

The plan is robust to those additions once they land: Pi and audience additions
arrive in the exported prelude lists, which the split preserves verbatim. Re-read
the anchors against the settled file before executing.

---

# SPEC — Split `test/ai/home-manager-contract.nix` into four cached checks (#65)

All line numbers below refer to `/Users/johnw/src/nix-impl/test/ai/home-manager-contract.nix`
(4902 lines), the version this work integrates against.

## 1. The partition is four, and four is correct

The monolith forces one list, `contractChecks` (built at `:3769-4189`), via
`assert builtins.deepSeq contractChecks true;` (`:4191`), then runs one
`runCommand` script (`:4193-4902`). Reading the whole file, the assertions fall
into exactly four **eval-closure** groups — the number the issue names, and the
number the code actually supports:

1. **catalog / renderers** — pure catalog + renderer evaluation. Forces
   `catalog`, `modelData`, and all five renderers (`renderedClaude/Codex/
   OpenCode/Droid/Pi`). No Home Manager configuration is evaluated.
2. **Home integration & ownership** — the *only* group that evaluates Home
   Manager host configurations (`task9Evaluations`, `task9JohnwEvaluations`,
   `task9AgentDeckEvaluation` — full `activationPackage`/`home.path` closures).
   This is by far the most expensive evaluation in the file.
3. **model synchronization** — the `config/fleet/model-sync.nix` factory and its
   generated shell script (`task10*`). Pure factory + script eval.
4. **package selection** — `config/fleet`/`config/packages.nix` input gating
   (`task11*`). Pure eval, no runtime harness.

Why not three or five: groups 1/3/4 are each cheap pure evaluations that touch
disjoint config surfaces (renderers vs. `model-sync.nix` vs. `packages.nix`);
merging any two of them would re-couple unrelated config edits. Group 2 is the
single expensive closure and must stand alone — that isolation is the whole
point. So four is the natural minimum that isolates the expensive closure while
keeping the three cheap surfaces independent.

### The one cross-group coupling that had to be cut

Five assertions inside `task10Checks` (`:3581-3605`: "Hera activation exists",
"Clio activation is absent", "Linux activations are absent", "runs after
linkGeneration", "generated activation carries exact DAG edge") reference
`task9Evaluations` — i.e. they need the *expensive* Home Manager closure. Left
in the model-sync check they would drag the entire activation eval into it,
defeating the split. They are genuinely **activation-wiring / topology**
assertions (they check the sync step is wired correctly into each host's
generation), so they are re-homed to the **integration** check, whose closure
already pays for those evaluations. The model-sync check keeps only the factory
+ generated-script assertions, which need no Home Manager eval.

## 2. Structure: four check files + one shared library

Physically the split is **four check files plus one shared library**:

- `test/ai/home-manager-contract-common.nix` — the monolith's entire `let`
  prelude (`:1-4189`) preserved **verbatim**, with the final
  `assert …; pkgs.runCommand …` (`:4190-4902`) replaced by an attrset that
  exports the named check sub-lists and the runtime fixtures.
- `test/ai/home-manager-catalog-renderers.nix`
- `test/ai/home-manager-integration.nix`
- `test/ai/home-manager-model-sync.nix`
- `test/ai/home-manager-package-selection.nix`

Each check file is small (41-434 lines): import the common library, assemble
its slice, `deepSeq`-assert it, and run its own `runCommand` with the runtime
block extracted verbatim from the monolith.

**Why a shared library rather than four self-contained files.** The prelude is
~3800 lines of tightly interdependent bindings (`catalog`, all renderers,
`task9*`, `task10*`, ~130 inline validation checks). Duplicating it four times
is unmaintainable; hand-tracing a minimal per-file prelude cannot be verified in
this environment (no eval/build available). Promoting the prelude once, intact,
to a library is the low-risk seam, and it does **not** defeat independent
caching: Nix evaluation is lazy, so `nix build .#checks.<sys>.<one-check>` forces
only the sub-lists and fixtures that check references — building the
catalog-renderers, model-sync, or package-selection check never forces the Home
Manager evaluations. The library is a support module, not a fifth check; it
mirrors how `config/fleet/renderers/` is already a directory of shared modules.

## 3. What happens to the monolith

`test/ai/home-manager-contract.nix` is **deleted**; its prelude survives, byte
for byte, as `home-manager-contract-common.nix`. There is no transition period
and no thin aggregator left behind — the four new checks fully cover it
(mapping table in NOTES.md), so nothing "retires" the old file later. The
registry loses `ai-home-manager-contract` and gains the four new entries in the
same edit (Section 5). This keeps current authority in one place: the prelude is
authored once; the four checks only *select* from it.

## 4. The exact transformation applied to build the common library

The common library was produced mechanically from the monolith so it can be
re-derived against the post-Pi-rebase file. Three localized edits to the prelude
plus one tail replacement:

1. **Split `task10Checks`** (`:3572-3630`) into two named lists so the
   activation-wiring subset can move to the integration check:
   - `task10FactoryChecksHead` = the factory-shape checks (`:3573-3580`)
   - `task10ActivationWiringChecks` = the five host-eval checks (`:3581-3605`)
   - `task10FactoryChecksTail` = the digest/redaction/source checks (`:3606-3629`)
   - then: `task10FactoryChecks = task10FactoryChecksHead ++ task10FactoryChecksTail;`
     and `task10Checks = task10FactoryChecks ++ task10ActivationWiringChecks;`
     (the original `task10Checks` name is preserved so nothing else breaks).
2. **Split `contractChecks`** (`:3769-4189`) so the inline validation list is
   nameable: rename the list literal `contractChecks = [ … ]` (`:3769`) to
   `contractInlineChecks = [ … ]`, then define
   `contractChecks = contractInlineChecks ++ profileChecks ++ reachabilityChecks
   ++ rendererChecks ++ task9Checks ++ task10Checks ++ task11PackageChecks
   ++ task11AiperfChecks;` (identical aggregate, retained for parity).
3. **Replace the tail** (`:4190-4902`, the `in`, the `assert`, and the entire
   `pkgs.runCommand`) with `in { inherit …; }` exporting:
   - concern 1: `contractInlineChecks profileChecks reachabilityChecks
     rendererChecks assetCheckPython rendererDocumentManifest piExtensionSources
     piPkgs`
   - concern 2: `task9Checks task10ActivationWiringChecks task9JohnwHera
     task9WrappedClaude task9HeraBridge task9Evaluations`
   - concern 3: `task10FactoryChecks task10Script task10ChangedScript
     task10Digest task10ChangedDigest modelData alternateModelData`
   - concern 4: `task11PackageChecks task11AiperfChecks`
   - parity/helpers: `contractChecks lib`

The six `runCommand` runtime segments were moved verbatim into the check files,
with only the leading `${binding}` interpolations rewritten to `${common.…}`
(`piExtensionSources`, `piPkgs`, `rendererDocumentManifest`, `task9*`,
`modelData`, `alternateModelData`, `task10*`). `${src}` and `${pkgs.*}` are
unchanged. See NOTES.md §mapping for which segment went where.

### Robustness to the concurrent Pi rebase

The Pi commits add ~300 lines to this same file, landing in the prelude
(`rendererChecks`, `piExtensionSources`, and the pi-extension existence lines at
`:4204-4212`). Because the common library exposes those by name, Pi additions to
`rendererChecks`/`piExtensionSources` flow into the catalog-renderers check
automatically. Only two hand-carried spots need a glance on re-integration: any
new lines the Pi work adds to the `runCommand` **body** (map them to a concern
by the same rules — pi-extension/renderer runtime → catalog-renderers), and any
new `task10`/`task9` list entries (they inherit the existing routing).

## 5. Ordered install plan (anchors)

1. `git mv test/ai/home-manager-contract.nix
   test/ai/home-manager-contract-common.nix`, then apply the three prelude edits
   + tail replacement from Section 4. (Or drop in the provided
   `home-manager-contract-common.nix`, which already is that transformation of
   the nix-impl content; then re-apply the Pi delta per Section 4.)
2. Add the four check files under `test/ai/` (provided).
3. `flake.nix`: delete the `ai-home-manager-contract = …` entry
   (nix-impl `:530-537`) and splice the four entries from `flake-block.nix` in
   its place (same `rootChecks` base attrset, same arg set).
4. `nix fmt` the five new/renamed files (nixfmt is the whitespace authority; the
   hand-written wrappers are close but not guaranteed canonical).
5. Verify (Section 6).

## 6. Verification

```
# parse-only (already passing in the authoring env):
nix-instantiate --parse test/ai/home-manager-contract-common.nix
nix-instantiate --parse test/ai/home-manager-catalog-renderers.nix
nix-instantiate --parse test/ai/home-manager-integration.nix
nix-instantiate --parse test/ai/home-manager-model-sync.nix
nix-instantiate --parse test/ai/home-manager-package-selection.nix

# full gate + per-check independent build:
nix flake check ./config/fleet --all-systems --no-build      # portable path per #47
nix build --no-link '.#checks.aarch64-darwin.ai-home-manager-catalog-renderers'
nix build --no-link '.#checks.aarch64-darwin.ai-home-manager-integration'
nix build --no-link '.#checks.aarch64-darwin.ai-home-manager-model-sync'
nix build --no-link '.#checks.aarch64-darwin.ai-home-manager-package-selection'
```

**Attribute-name note.** The issue's verification text uses unprefixed names
(`home-manager-catalog-renderers`, …). I kept the `ai-` family prefix in the
*registry attribute* (`ai-home-manager-*`) to match the retired
`ai-home-manager-contract` and its siblings (`ai-lock-coherence`,
`ai-managed-preflight`) — that is the "match how the existing check is declared"
directive. The built derivation names are the unprefixed `home-manager-*` the
issue expects. If the #46 registry owner prefers unprefixed attributes, change
only the four LHS keys in `flake-block.nix`; nothing else depends on them.

## 7. Rollback

Repo-local, no host activation. `git revert` the split commit restores the
monolith and the single registry entry. If only the registry is wrong, restore
the one `ai-home-manager-contract` entry and keep the files — nothing imports the
new checks except the flake registry.


---

# NOTES — coverage, negatives, caching, and literal oracles (#65)

Monolith line numbers refer to `/Users/johnw/src/nix-impl/test/ai/home-manager-contract.nix`.

## 1. What each split check proves

- **catalog-renderers** (`home-manager-catalog-renderers`): the catalog composes
  and validates (profile/selector/unmanaged ledgers, reachability), the model
  registry + policy accept/reject the right shapes, every MCP transport/header
  is exact, and each of the five renderers emits exactly the committed path set,
  companions, required-env, and secret-reference shape for every profile — plus
  the committed on-disk `config/fleet` asset layout (modes, symlink containment,
  skill frontmatter, forbidden artifacts, deployment-field ban) and the
  statusline unit test.
- **integration** (`home-manager-integration`): the Home Manager host
  configurations own the right leaves and *not* the mutable ones, the managed
  profile wins on `PATH`, the `claude`/`claude-real`/bridge/persona wrappers are
  the patched store paths (and `claude-real` is *not* patched), a legacy
  `~/src/scripts/claude` loses to the managed wrapper under a real login zsh, and
  the activation DAG orders preflight → collision-check → writeBoundary →
  linkGeneration → model-sync.
- **model-sync** (`home-manager-model-sync`): the `model-sync.nix` factory shape
  + DAG edge, and the generated script's exact `defaults`/`security` allowlist,
  DEVONthink/iTerm2 process guards, credential redaction, digest idempotence
  (fast path + corrupt-stamp recovery), and crash-safe atomic replacement /
  rollback at every updater-failure position.
- **package-selection** (`home-manager-package-selection`): cross-platform
  `userPackageInputNames` gating (Darwin-only vs. common inputs,
  infrastructure-input filtering) and the AIPerf source-dependency gate in both
  the user package list and the AI toolchain.

## 2. Negative test per check (the concrete change that makes it fail)

- **catalog-renderers**: in `config/fleet/agents/bash-reviewer.md`, change any field
  that feeds `expectedOpenCodeAgentMetadata` → the committed sha256 literal
  `27eaf3302a4ff6cd97d4a0f5a7027d57c121f362318c1b4d011b0fce691b3e1a`
  (monolith `:3779`) no longer matches and `deepSeq` throws. (Equivalent: add a
  file to a Claude profile's render → `"<profile> selected resource paths"` vs.
  the literal `expectedClaudePaths` list mismatches.)
- **integration**: make the `claude` wrapper the raw upstream package (drop the
  `classify_managed_artifacts` patch) in `config/ai.nix` → the runtime assertion
  `grep -Fq 'classify_managed_artifacts' "$profile_path/bin/claude"` (`:4220`)
  fails. (Equivalent: reorder the aiManagedPreflight activation after
  linkGeneration → `preflight_line < collision_line` (`:4279`) fails.)
- **model-sync**: add one more `defaults write` (e.g. a new iTerm2 key) in
  `config/fleet/model-sync.nix` → `task10_assert_exact_app_calls` reports
  `defaults allowlist mismatch` (python `:4716`) and the build exits 1.
  (Equivalent: echo the credential to stdout → `task10_assert_redacted`
  greps the `TASK10-CREDENTIAL-SENTINEL` and fails, `:4664`.)
- **package-selection**: expose a Darwin-only app (e.g. `org-jw`) on Linux in
  `config/packages.nix` → `"Task 11 x86_64-linux ignores package-shaped
  infrastructure inputs"` compares `userPackageInputNames` against the literal
  `task11CommonPackageInputs` and throws (`:3739`). (Equivalent: let AIPerf be
  selected without complete deps → `"AIPerf omits both missing source
  dependencies"` expects `false`, gets `true`, `:3694`.)

## 3. No assertion lost — mapping table

Every deepSeq'd sub-list and every `runCommand` runtime segment of the monolith,
routed to exactly one split check. Nothing is dropped or merely "redundant."

### Nix `deepSeq` check lists

| Monolith source | Assertion group | → Split check |
|---|---|---|
| `:3769-4181` `contractInlineChecks` | overlay isolation; OpenCode tool hash oracles; catalog validate/profile-ids/roots/settings/ledgers/unions; registry schema + selection projection; alternate-selection→catalog; **sync selection + sync-URL provenance** (`:3850-3853,4071-4077`); host-filter render; renamed-credential; all registry rejects; policy rejects; provider base-URL/credential contracts; MCP transport/URL/header contracts; adapter versions; secret routing + capability rows; typed-env / no-forbidden-env; all `validateWith*`/MCP rejects | **catalog-renderers** |
| `:595-609` `profileChecks` | per-profile MCP/hooks/marketplaces/settings/default coverage | **catalog-renderers** |
| `:624-643` `reachabilityChecks` | every item/provider/model reaches ≥1 profile; excluded-item oracle | **catalog-renderers** |
| `:2114-2337` `rendererChecks` | per-profile rendered paths/companions/required-env; forbidden mutable roots; skill sources; Droid & Pi MCP hash oracles; Pi extension leaves; Pi shape/guard probes; **Claude command-prompt collision** (`:2333`) | **catalog-renderers** |
| `:3194-3350` `task9Checks` (+ `task9FixtureChecks`, `task9PathChecks`, `task9IntegratedPathChecks`, `task9FeaturePackageChecks`) | ownership of home leaves, PATH precedence, git-ai degrade, package-into-home, HM-source normalization, agent-deck launchd PATH, invalid-class rejects | **integration** |
| `:3581-3605` `task10ActivationWiringChecks` (carved out of `task10Checks`) | Hera activation present / Clio+Linux absent; runs after linkGeneration; generated activation DAG edge | **integration** |
| `:3573-3580,3606-3629` `task10FactoryChecks` (rest of `task10Checks`) | factory shape/tool-seam/DAG edge; digest oracles + digest-changes; empty-input reject; source-omits-forbidden-ops; credential-key confinement; centralized read/write; iTerm metadata-query count | **model-sync** |
| `:3735-3767` `task11PackageChecks` | Linux vs. Darwin `userPackageInputNames` | **package-selection** |
| `:3693-3734` `task11AiperfChecks` | AIPerf source-dependency + toolchain gate | **package-selection** |

### `runCommand` runtime segments

| Monolith lines | Runtime segment | → Split check |
|---|---|---|
| `:4202` | `statusline-command-test.py` | **catalog-renderers** |
| `:4204-4212` | pi-extension source existence (`auto-compact-resume`, gallery, mcp-adapter, quiet) | **catalog-renderers** |
| `:4214-4282` | aarch64-darwin: wrapper exec bits, legacy-`claude` collision under login zsh, activation ordering | **integration** |
| `:4284-4424` | `rendererDocumentManifest` python (JSON/TOML/text/frontmatter vs. committed `expected`) | **catalog-renderers** |
| `:4426-4637` | `config/fleet` asset walk python (modes, symlink containment, skill frontmatter, forbidden artifacts, deployment fields) | **catalog-renderers** |
| `:4639-4901` | task10 model-sync shell harness (redaction, idempotence, rollback, process guard, atomic mv) | **model-sync** |

### Required behaviors (issue) mapped check-by-check

- **collision** → catalog-renderers (renderer target collisions: Claude
  command/prompt `:2333`, Pi probes `:2265-2285`) **and** integration (runtime
  PATH collision vs. legacy `~/src/scripts/claude` `:4240-4270`).
- **permission** → catalog-renderers (asset file modes + statusline executable,
  `:4488-4491,4600-4601`) **and** integration (`test -x` wrapper bits `:4216-4219`).
- **redaction** → model-sync (`task10_assert_redacted` sentinel + forbidden-op /
  credential-key-confinement source checks) **and** catalog-renderers
  (no-literal-secret rejects + typed-env / secret-routing checks).
- **rollback** → model-sync (second-updater / verification / rename failures
  preserve the old stamp, `:4855-4899`).
- **idempotence** → model-sync (digest fast path emits no tool calls; corrupt
  multi-line stamp recovers, `:4792-4803`).
- **topology** → integration (activation ordering `:4273-4281` +
  `task10ActivationWiringChecks`).

`contractChecks` (the full aggregate) is retained in the common library only for
parity/debugging; coverage is provided by its components above, not by forcing
the aggregate.

## 4. Shared setup — why the checks' inputs differ (the caching claim)

- **catalog-renderers** forces `catalog` + all five renderers + `pi-gallery`;
  runtime reads `${src}` (statusline test + `config/fleet` walk) and the
  renderer-document / pi-extension store paths. It does **not** force any Home
  Manager configuration.
- **integration** forces the Home Manager host evaluations — the
  `activationPackage`/`home.path` closures for every host fixture, plus the
  wrapped Claude and Droid bridge. Its runtime reads only those store paths (no
  `${src}`). This is the single expensive closure, now isolated.
- **model-sync** forces the `model-sync.nix` factory + the two generated shell
  scripts + digests; runtime reads only those store paths (no `${src}`). No Home
  Manager eval.
- **package-selection** forces `config/packages.nix` selection +
  `aiFlake.lib.aiPackagesFor`; the derivation has *no* source input at all
  (`runCommand … '' touch $out ''`), so its store output effectively never
  rebuilds — the contract is the eval-time `deepSeq` assertion.

**Guaranteed win:** `nix build .#checks.<sys>.<one>` for catalog-renderers,
model-sync, or package-selection never forces the Home Manager configuration
evaluation, which only the integration check pays. Editing a home config file
rebuilds *only* integration; editing `model-sync.nix` rebuilds model-sync (its
generated-script store hash) — it does not force renderers or Home Manager.

**Honest residual coupling:** catalog-renderers keeps the monolith's whole-tree
`${src}` dependency, because `statusline-command-test.py` resolves the repo root
from `__file__.parents[2]` (it needs the tree layout, not a lone file) and the
asset walk reads all of `config/fleet`. So editing an unrelated file still rebuilds
catalog-renderers — no worse than today, and the other three are strictly
better. A follow-up can narrow it with `lib.fileset.toSource` over
`{config/fleet, test/ai/statusline-command-test.py}` (config/fleet has **zero**
symlinks — verified — so no dangling risk), **but** `src = self.outPath` is a
*string*, not a path, so `lib.fileset` rejects it directly; the follow-up must
first obtain a path-typed root (e.g. thread the flake's path input through, or
`builtins.path` per subtree and recompose). I did not ship that narrowing
because it cannot be eval-verified here and a wrong root type breaks the check.

## 5. Literal oracles — status and what I could not convert

"Literal oracle" = assert against a committed constant, not a value re-derived
from the thing under test (the #48 false-evidence pattern).

**Already literal — preserved byte-for-byte** (the bulk of the file): the
OpenCode tool sha256 oracles (`:3779,3782`), Droid MCP oracle (`:2241`), Pi MCP
oracle (`:2299`), every `expected*Paths` path list, every required-env list, the
host-filter expected map (`:745-750`), the `rendererDocumentManifest`
`expected`/`expectedText`/`expectedMetadata`/`expectedBody` records, and the
task10 `defaults` allowlist baked into the python (`:4701-4712`). These carried
over unchanged; no drift risk.

**Still self-computed — carried over faithfully but NOT converted to literals**
(would need a `nix eval` to mint the constant, which is contended in this
environment; none is *lost* — each is asserted exactly as today):

| Monolith | Expected value is derived from… | Class |
|---|---|---|
| `:3803-3805` "shared Codex union" | `sortedNames catalog.items.commands` | drift-risk |
| `:3810-3824` personal/positron/shared skill sets | `selectedNames "hera-codex" "skills"` ++ literal deltas | drift-risk (base set) |
| `:627-641` reachability "reaches ≥1 profile" | `sortedNames catalog.items.<cat>` / `modelData.providers`/`models` | invariant (self-reference is intended; residual drift only if an item is dropped from both sides) |
| `:3833-3853,4071-4077` alternate/sync selection provenance | the mutated input registry (`alternateRegistry`/`rawModelRegistry`) | low-risk provenance (input→output projection) |
| `:2142-2146` etc. renderer skill-source pass-through | catalog `item.source` | intended pass-through check |

To finish the issue's "literal oracle" criterion for the two drift-risk rows,
mint the constant once and paste it as a committed list, e.g. evaluate the LHS
(`selectedNames "shared-work-codex" "commands"`, and the three skill sets)
against the common library via `nix eval --json` and replace the RHS expression
with the returned literal. That conversion is mechanical but must be done with
eval available; it is the only part of the issue I could not complete here, and
it changes zero behavior (same values, committed instead of recomputed).

## 6. Verification performed here

`nix-instantiate --parse` passes for the common library and all four check
files. Every `common.<name>` referenced by the four files is confirmed present
in the library's export set. Every runtime-block interpolation was rewritten and
re-audited (no un-rewritten monolith binding remains; only `${common.*}`,
`${src}`, `${pkgs.*}`). Full `nix eval`/`nix build` was not run (contended per
task constraints) — run Section 6 of SPEC.md before committing.
