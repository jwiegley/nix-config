# Test Coverage Model

**Status:** A6 / issue #80 research and design authority, 2026-07-29.

## Decision

Nix currently has no statement, expression, branch, line, or file coverage facility
for evaluated `.nix` code. This repository will not invent a percentage and call it
one. “Coverage” here is a versioned set of separately named measurements:

1. Nix **file evaluation started** reach;
2. explicit flake output/system forcing;
3. host/consumer evaluation coverage;
4. `johnw.*` option-value coverage;
5. Python dynamic line/branch coverage plus tracked-file inventory;
6. shell behavioral-test ownership inventory; and
7. proven-negative coverage for every gate.

No aggregate score may erase a failed or unmeasured component. A missing measurement
is `unknown`, never zero and never pass.

## Prior Art

Research used official documentation and source current on 2026-07-29. The local
`opensrc` cache tool was unavailable; `npx --no-install opensrc` confirmed it was not
installed, and no dependency was fetched.

| Candidate | Primary source | Verdict | What it actually provides |
|---|---|---|---|
| Nix language coverage | [open upstream #16107](https://github.com/NixOS/nix/issues/16107) | build | Proposal only; no implementation or linked PR. |
| `evaluating file` diagnostic | [Nix `evalFile`](https://github.com/NixOS/nix/blob/6eb73313e44ce05ff2a24ab212c6583d676df924/src/libexpr/eval.cc#L1108-L1180), [`scopedImport`](https://github.com/NixOS/nix/blob/6eb73313e44ce05ff2a24ab212c6583d676df924/src/libexpr/primops.cc#L268-L322) | compose | File evaluation-start lower bound for modern `nix eval` paths. |
| Function-call trace/profiler | [`--trace-function-calls`](https://nix.dev/manual/nix/2.35/command-ref/conf-file.html#conf-trace-function-calls), [eval profiler](https://nix.dev/manual/nix/2.35/advanced-topics/eval-profiler.html) | reject as coverage | Call activity/timing; no branch/expression denominator. |
| `NIX_SHOW_STATS` / `NIX_COUNT_CALLS` | [manual](https://nix.dev/manual/nix/2.35/command-ref/env-common.html), [source](https://github.com/NixOS/nix/blob/6eb73313e44ce05ff2a24ab212c6583d676df924/src/libexpr/eval.cc#L3046-L3177) | compose for diagnostics | Evaluator aggregates and positive lambda hits; uncalled lambdas absent. `nrExprs` counts constructed AST nodes, not executed expressions. |
| nix-unit | [official examples](https://nix-community.github.io/nix-unit/examples/simple.html), [runner](https://github.com/nix-community/nix-unit/blob/b3d16367c54621fd073aa8c1dd510042f771f624/src/nix-unit.cc#L254-L388) | compose selectively | Independent value/error unit results. Its `addCoverage` checks public-name registration, not source execution. |
| `lib.debug.runTests` | [Nixpkgs manual](https://nixos.org/manual/nixpkgs/stable/#function-library-lib.debug.runTests), [implementation](https://github.com/NixOS/nixpkgs/blob/master/lib/debug.nix#L438-L538) | extend | Lowest-cost pure value assertions; require explicit nonempty/throw guards. |
| Namaka | [official README](https://github.com/nix-community/namaka/blob/34b69a66a2cfa09f433324431dcdc182740e6665/README.md#L14-L113) | compose selectively | Snapshot equality/review, not execution coverage. Existing Darwin baseline has repo-specific provenance/security needs. |
| Determinate flake schemas | [protocol](https://manual.determinate.systems/protocols/flake-schemas), [forcing implementation](https://github.com/DeterminateSystems/nix-src/blob/469a08e76a130e51b7a9f5df1fcc48b7d4d4cd42/src/nix/flake.cc#L355-L484) | extend | Machine-readable output inventory and `--build-all --no-build`; unknown/custom outputs and declared-system completeness still need a manifest. |
| nix-eval-jobs | [official README](https://github.com/NixOS/nix-eval-jobs/blob/a0cd02231c58974a6b5aaa3712069b071047162e/README.md#L40-L84), [response schema](https://github.com/NixOS/nix-eval-jobs/blob/a0cd02231c58974a6b5aaa3712069b071047162e/src/response.cc#L24-L46) | compose in expensive tier | Parallel derivation-path/error inventory only. Primitive leaves disappear; emitted error records do not reliably make the process nonzero. |
| coverage.py | [official docs](https://coverage.readthedocs.io/en/7.15.2/), [subprocess rules](https://coverage.readthedocs.io/en/latest/subprocess.html) | adopt | Dynamic Python line/branch hits. Locked Nixpkgs already provides 7.13.2 on Darwin and Linux. |
| kcov / bashcov / coverage-sh | [kcov](https://github.com/SimonKagstrom/kcov), [bashcov](https://github.com/infertux/bashcov), [coverage-sh](https://pypi.org/project/coverage-sh/) | reject for mandatory tier | Linux-only locked kcov; Ruby/SimpleCov cost for bashcov; coverage-sh is pre-alpha and Python-subprocess-only. |
| Local traceability skills | `trace-requirement`, `gate-trace`, `inspect-quality` | reject as complete solution | Reusable artifact/regression patterns, but require absent Task-Master story state and do not observe Nix execution. |

## Nix: what can and cannot be measured

### Statement-level coverage is not achievable with stock Nix

Nix has expressions, not conventional statements. `--trace-function-calls` wraps
function dispatch; the sampling profiler also observes function stacks. Neither sees
literals, operators, branches, arbitrary expression forcing, or uncalled locations.
`NIX_COUNT_CALLS` has no denominator. A true metric would require evaluator changes
that record forced AST/thunk source spans. The closest expression profiler proposal,
[Tracy PR #9967](https://github.com/NixOS/nix/pull/9967), closed unmerged after high
overhead and semantic problems.

### File reach is a lower-bound surrogate

The installed Determinate Nix (`3.21.7`, Nix `2.34.8`) was live-probed with:

```sh
nix eval --no-eval-cache -v --log-format internal-json <probe>
```

It emits the upstream `evaluating file '<path>'` event for repository files. A collector
may deduplicate repository-local paths against `git ls-files '*.nix'`, but must label
the numerator **file evaluation started**.

Binding blind spots:

- the event occurs before parse/evaluation succeeds;
- lazy contents can remain unforced;
- direct `parseExprFromFile`, string/stdin expressions and some legacy roots bypass it;
- `readFile`, `readDir`, `hashFile`, `pathExists`, and copied paths are not events;
- `scopedImport` can log a directory rather than resolved `default.nix`;
- the wording is diagnostic, not a documented API, so parser drift must fail closed;
- evaluation cache hits suppress evidence, hence `--no-eval-cache` is mandatory.

Known root files are seeded explicitly. Reached and unreached path lists are committed;
the ratio is a navigation aid, not semantic completeness.

### Output reach requires an applicability manifest

This fleet uses Determinate schemas. `--all-systems` removes schema system filtering;
it does not prove that a missing system was declared. Unknown outputs only warn.
`--no-build` skips realisation; `--build-all --no-build` forces every schema-described
derivation path without building it.

The expensive tier composes:

```sh
nix flake show --all-systems --json path:.
nix flake check --all-systems --build-all --no-build --keep-going path:.
```

with a committed output-kind/system applicability manifest. The collector rejects
unknown outputs, missing systems, omitted expected attr paths, and error records.
Custom outputs must gain schemas or explicit bounded probes. The Nix implementation and
flake-schema revision are part of the artifact identity because upstream Nix 2.34 has
materially different `flake check` semantics.

## Metric definitions

| Component | Denominator | Numerator / evidence | Pass rule | Blind spot |
|---|---|---|---|---|
| `nixFileReach` | Every tracked `.nix` file, derived live | Union of successful-probe evaluation-start paths plus explicit roots | Must not regress without a reviewed baseline refresh; paths remain visible | Not line/expression success; `readFile` invisible |
| `outputReach` | Explicit output/system applicability records | Schema inventory + forced leaf/probe result | Every expected record observed; no unknown/error | Only declared bounded leaves |
| `hostReach` | Hera, Clio, two standalone HM configs, shared-work, VPS, Vulcan | Current eval/build gate named per target | Every maintained target has a tier and latest result; skip is failure unless documented unavailable | Eval is not activation/runtime proof |
| `optionValueReach` | Every evaluated `johnw.*` option path | Per-target serialized value matrix | Every option forced on at least one fixture; inert/default-only options reported separately | Value forcing does not prove a consumer reads it |
| `pythonDynamic` | Coverage.py executable statements/branches for files in a tier | Runtime line/branch hits | Report exact tier, paths, tool version; regression-gated separately | Subprocess/custom interpreter and unimportable script caveats |
| `pythonInventory` | `bin/quality --files python` | Paths assigned to fast/slow/manual tier | Every tracked path assigned exactly once | Assignment is not execution |
| `shellBehavior` | `bin/quality --files shell` | Explicit script → behavioral test/check/tier ownership | Every production script classified tested or gap; test drivers classified separately | No portable line-hit backend |
| `negativeGate` | Every registered gate/check | Committed perturbation + expected failing diagnostic | No gate may be `proven` without a replayable negative | A mutation can cover only the named failure mode |

## Derived baseline — never copy these as policy literals

As of 2026-07-29 the authorities derive:

- 104 tracked Nix files;
- 43 tracked/shebang Python files and 9 fast `bin/*-test.py` suites;
- 35 tracked Bash scripts;
- 14 evaluated `johnw.*` option paths (the old “4 options” note is stale);
- root checks: 27 on `aarch64-darwin`, 28 each on `aarch64-linux` and
  `x86_64-linux`;
- update inventory: 199 total, 176 managed, 23 pending.

These are snapshot observations. Gates compare freshly derived before/after sets or a
versioned artifact; they do not require those bare numbers forever. In particular:

- #39’s `pending 18 → 12` is stale; the current lock-bearing npm family and pending set
  must be derived at implementation time (the 2026-07-29 measurement is 23 pending,
  with nine lock-bearing npm records, so the then-current delta would be 23 → 14).
- #43’s “inventory total stays 188” is replaced by **total is unchanged across the
  change**. The current total happens to be 199.
- `bin/quality` prose saying 11 Anvil MCP test files is stale; 12 are tracked today.

## Tiers and cost contract

| Tier | Content | Placement | Budget semantics |
|---|---|---|---|
| pre-commit | formatting/lint, fast unit tests, portable bounded eval | local hook | One measured wall-clock budget; failure or timeout is red. Current hook has exceeded six minutes, so A6 must split slow tests before declaring this tier fast. |
| pre-push | file/output/host/option collection, Darwin surface, consumers, signatures, system/agent checks | local hook | Minutes are acceptable; every named target reports ran/pass, never silent skip. |
| CI / on demand | coverage.py branch report, full output/schema sweep, unsafe/live/soak suites, optional nix-eval-jobs projection | remote-safe CI or authorized self-hosted runner | Tool/runner identity recorded; LAN-only root inputs must not be presented as GitHub CI evidence. |

Budgets are measured on the repository state and stored as evidence, not guessed. A
timing regression is a concern even when correctness remains green. Pre-commit cannot
claim budget compliance until its observed slow `gates-test.py`/GPG paths are assigned
to an appropriate tier without losing their invocation.

## Artifact and regression policy

The committed coverage artifact records:

- schema and source revision;
- Nix/flake-schema/coverage.py versions;
- complete denominators and observed path/attr sets, not counts alone;
- target/tier status including `ran`, `passed`, `skipped`, duration and evidence kind;
- blind spots and unknown measurements;
- provenance commands.

The gate re-derives structural inventories cheaply on every pre-commit. Expensive
measurements are refreshed deliberately and must not regress without an explicit,
reviewable artifact update. A missing target, parser-schema change, duplicated tier
assignment, skipped assertion, or unexplained decrease is failure.

## Implementation order

1. Commit this research/design record.
2. Build a read-only collector plus schema-versioned artifact and negative tests.
3. Add `bin/quality coverage` as the only suite authority; hooks/CI delegate to it.
4. Measure and enforce tier timing, then split slow tests without deleting coverage.
5. Correct #39/#43 bodies to derived-before/after wording.
6. Run full verification, independent clean-context fess, and tracker closeout.

No host activation, package update, or credential provisioning is part of A6.
