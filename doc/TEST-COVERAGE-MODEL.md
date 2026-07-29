# Test Coverage Model

**Status:** A6 / issue #80 research and design authority, 2026-07-29.

## Decision

Stock Nix 2.34/2.35 exposes no statement-, expression-, branch-, or line-coverage
interface for evaluated `.nix` code, and no documented complete file-access trace.
This repository will not invent a percentage and call it one. “Coverage” here is a
versioned set of separately named measurements:

1. Nix **file evaluation started** reach;
2. explicit flake output/system forcing;
3. host/consumer evaluation coverage;
4. `johnw.*` option-value coverage;
5. Python dynamic line/branch coverage plus tracked-file inventory;
6. shell behavioral-test ownership inventory; and
7. proven-negative coverage for every gate.

These are seven measurement families, not seven scalar scores; the component table
below splits them where execution state or security boundaries differ.

No aggregate score may erase a failed or unmeasured component. Every denominator is
derived independently of the execution path it measures, so unreachable declarations
cannot disappear from both sides. A missing measurement is `unknown`, never zero and
never pass.

## Prior Art

Research used official documentation and source current on 2026-07-29. The local
`opensrc` cache tool was unavailable; `npx --no-install opensrc` confirmed it was not
installed, and no dependency was fetched.

| Candidate | Primary source | Verdict | What it actually provides |
|---|---|---|---|
| Nix language coverage | [open upstream #16107](https://github.com/NixOS/nix/issues/16107) | reject for A6 | Proposal only; implementing it requires an evaluator extension/fork. |
| `evaluating file` diagnostic | [Nix `evalFile`](https://github.com/NixOS/nix/blob/6eb73313e44ce05ff2a24ab212c6583d676df924/src/libexpr/eval.cc#L1108-L1180), [`scopedImport`](https://github.com/NixOS/nix/blob/6eb73313e44ce05ff2a24ab212c6583d676df924/src/libexpr/primops.cc#L268-L322) | compose | File evaluation-start lower bound for modern `nix eval` paths. |
| Function-call trace/profiler | [`--trace-function-calls`](https://nix.dev/manual/nix/2.35/command-ref/conf-file.html#conf-trace-function-calls), [eval profiler](https://nix.dev/manual/nix/2.35/advanced-topics/eval-profiler.html) | reject as coverage | Call activity/timing; no branch/expression denominator. |
| `NIX_SHOW_STATS` / `NIX_COUNT_CALLS` | [source](https://github.com/NixOS/nix/blob/6eb73313e44ce05ff2a24ab212c6583d676df924/src/libexpr/eval.cc#L3046-L3177), [`Expr` counter](https://github.com/NixOS/nix/blob/6eb73313e44ce05ff2a24ab212c6583d676df924/src/libexpr/include/nix/expr/nixexpr.hh#L106-L110) | compose for diagnostics | Evaluator aggregates and positive lambda hits; uncalled lambdas absent. `nrExprs` counts constructed `Expr` instances, not executed expressions. |
| nix-unit | [pinned examples](https://github.com/nix-community/nix-unit/blob/b3d16367c54621fd073aa8c1dd510042f771f624/doc/src/examples/simple.md), [runner](https://github.com/nix-community/nix-unit/blob/b3d16367c54621fd073aa8c1dd510042f771f624/src/nix-unit.cc#L254-L388), [`addCoverage`](https://github.com/nix-community/nix-unit/blob/b3d16367c54621fd073aa8c1dd510042f771f624/lib/coverage.nix#L48-L65) | compose selectively | Independent value/error unit results. Zero discovered tests can pass; `addCoverage` checks public-name registration, not source execution. |
| Nixtest | [v1.3.0 source](https://gitlab.com/TECHNOFAB/nixtest/-/tree/v1.3.0) | compose selectively | Go runner for Nix unit, snapshot, script and VM tests with JUnit output; semantic outcomes, not source-hit coverage. |
| nix-tests | [pinned README](https://github.com/danielefongo/nix-tests/blob/866429d23a6ebf6e03837434f18e4cace9c37bc5/README.md) | compose selectively | Rust runner and assertion library with parallel file execution; timing is file-level and no line/expression coverage is reported. |
| `lib.debug.runTests` | [locked implementation](https://github.com/NixOS/nixpkgs/blob/421eebfd0ec7bccd4abe826ce62d7e6e83129493/lib/debug.nix#L438-L538) | extend | Pure value assertions without a new input; require explicit nonempty/throw guards. |
| Namaka | [official README](https://github.com/nix-community/namaka/blob/34b69a66a2cfa09f433324431dcdc182740e6665/README.md#L14-L113) | compose selectively | Snapshot equality/review, not execution coverage. Existing Darwin baseline has repo-specific provenance/security needs. |
| Determinate flake schemas | [protocol](https://manual.determinate.systems/protocols/flake-schemas), [forcing implementation](https://github.com/DeterminateSystems/nix-src/blob/469a08e76a130e51b7a9f5df1fcc48b7d4d4cd42/src/nix/flake.cc#L355-L484) | extend | Machine-readable output inventory and `--build-all --no-build`; unknown/custom outputs and declared-system completeness still need a manifest. |
| nix-eval-jobs | [official README](https://github.com/NixOS/nix-eval-jobs/blob/a0cd02231c58974a6b5aaa3712069b071047162e/README.md#L40-L84), [worker](https://github.com/NixOS/nix-eval-jobs/blob/a0cd02231c58974a6b5aaa3712069b071047162e/src/worker.cc#L322-L397), [collector](https://github.com/NixOS/nix-eval-jobs/blob/a0cd02231c58974a6b5aaa3712069b071047162e/src/nix-eval-jobs.cc#L383-L429) | compose in expensive tier | Parallel derivation metadata plus caller `extraValue` and errors. Primitive leaves disappear; error records require explicit scanning. |
| coverage.py | [7.15.2 docs](https://coverage.readthedocs.io/en/7.15.2/), [7.15.2 subprocess rules](https://coverage.readthedocs.io/en/7.15.2/subprocess.html), [locked package](https://github.com/NixOS/nixpkgs/blob/421eebfd0ec7bccd4abe826ce62d7e6e83129493/pkgs/development/python-modules/coverage/default.nix) | adopt | Dynamic Python line/branch hits. The root’s locked Nixpkgs provides 7.15.2 on Darwin and Linux. |
| kcov / bashcov / coverage-sh | [kcov v43](https://github.com/SimonKagstrom/kcov/tree/v43), [locked Linux-only package](https://github.com/NixOS/nixpkgs/blob/421eebfd0ec7bccd4abe826ce62d7e6e83129493/pkgs/by-name/kc/kcov/package.nix#L73-L92), [bashcov v3.3.0](https://github.com/infertux/bashcov/tree/v3.3.0), [coverage-sh 0.5.0](https://pypi.org/project/coverage-sh/0.5.0/) | reject for mandatory tier | Upstream kcov supports macOS/Linux but the locked package is Linux-only; bashcov adds Ruby/SimpleCov; coverage-sh is pre-alpha and absent from the locked environment. |
| Local traceability skills | `trace-requirement`, `gate-trace`, `inspect-quality` | reject as complete solution | Reusable artifact/regression patterns, but require absent Task-Master story state and do not observe Nix execution. |

## Nix: what can and cannot be measured

### Stock Nix exposes no statement/branch coverage interface

Nix has expressions, not conventional statements. `--trace-function-calls` wraps
function dispatch; the sampling profiler also observes function stacks. Neither sees
literals, operators, branches, arbitrary expression forcing, or uncalled locations.
`NIX_COUNT_CALLS` has no denominator. A source-span metric would require evaluator
instrumentation beyond stock interfaces. [Tracy profiler PR #9967](https://github.com/NixOS/nix/pull/9967)
closed unmerged after roughly 8× example overhead, unwieldy traces, and misleading
attribution between function calls and lazy thunk forcing.

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

Known root files are not credited merely for being roots: each requires a successful
named probe whose event or explicit root contract is recorded. Reached and unreached
path lists are committed; the ratio is a navigation aid, not semantic completeness.

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
Schema-described derivation paths are forced; arbitrary lazy values are not. Each
custom probe therefore states its normal-form contract (`drvPath`, attr-name set,
JSON-safe value, or explicit `deepSeq`). Custom outputs must gain schemas or such a
bounded probe. The Nix implementation and flake-schema revision are part of the
artifact identity because Determinate schema forcing and upstream Nix 2.34's hardcoded
flake-check traversal are different mechanisms.

## Metric definitions

| Component | Denominator | Numerator / evidence | Pass rule | Blind spot |
|---|---|---|---|---|
| `nixFileReach` | Every tracked `.nix` file, derived live | Union of successful-probe evaluation-start paths plus explicit roots | Must not regress without a reviewed baseline refresh; paths remain visible | Not line/expression success; `readFile` invisible |
| `outputReach` | Explicit output/system applicability records | Schema inventory + forced leaf/probe result | Every expected record observed; no unknown/error | Only declared bounded leaves |
| `hostReach` | Registry-derived real machines, group rows, synthetic fixtures and unique evaluation roots, each with a stable kind/ID | Current eval/build gate named per evaluation root; aliases reference one result | Every denominator ID is assigned exactly one root or explicit unavailable state; skip never passes | Group proxies do not exercise member-host branches; eval is not activation/runtime proof |
| `optionValueReach` | Static option declarations plus evaluated option-tree paths (union, never evaluated-only) | Per-target forced status/type/fingerprint under a default-deny safe-field policy | Every declared path is present in the union and forced on at least one fixture; inert/default-only options reported separately | Value forcing does not prove a consumer reads it; raw values are not persisted |
| `pythonDynamic` | Coverage.py executable statements/branches for files in a tier | Runtime line/branch hits | Report exact tier, paths, tool version; regression-gated separately | Subprocess/custom interpreter and unimportable script caveats |
| `pythonInventory` | `bin/quality --files python` | Paths assigned to fast/slow/manual tier | Every tracked path assigned exactly once | Assignment is not execution |
| `shellBehavior` | `bin/quality --files shell` | Explicit script → behavioral test/check/tier ownership | Every production script classified tested or gap; test drivers classified separately | No shell line-hit backend is available in the locked cross-platform environment without a new dependency |
| `negativeGate` | Unique executable authorities: `quality:<suite>` plus system-qualified `checks.<system>.<attr>`; hook/CI entries are invocation surfaces, not duplicate gates | Committed perturbation + expected failing diagnostic | No gate may be `proven` without a replayable negative | A mutation can cover only the named failure mode |
| `testCaseReach` | Test cases discovered independently from runtime | Structured runtime outcome: passed/failed/skipped/not-run | Every selected case reports one outcome; skipped/not-run is not pass | A test case may contain multiple assertions |
| `assertionCallReach` | Statically enumerated Python assertion-call lines and explicitly named Nix assertion records | Coverage.py line hit or named Nix result | Reached/pass and unreached are distinct; languages without instrumentation report `unknown` | Line hits do not prove every expression inside a compound assertion |
| `darwinValueSurface` | Seven named surfaces × Hera/Clio under schema-v2 projection identity | Credential-safe normalized baseline comparison | Both host artifacts compare; schema/projector mismatch fails before value drift | Agent-level launchd hashes do not localize sensitive subtree fields |

Host denominators are explicit and non-overlapping:

- registry machine IDs: `hera`, `clio`, `vulcan`, `vps`, `andoria-08`, `andoria-t2`,
  `delphi-3bd4`, `gpu-server` (eight real machines);
- registry group row: `andoria` (one proxy for the four shared-home machines);
- synthetic fixture: `linux` / `johnw@aarch64-linux`;
- unique evaluation roots: Hera, Clio, the Linux fixture, shared-work (the same root as
  `jwiegley@x86_64-linux`, not a second target), VPS and Vulcan.

The group proxy is evidence for shared-home class behavior, not proof of each member's
hostname-gated behavior. Aliases point to one root result so counts cannot double.

## Derived baseline — never copy these as policy literals

As of 2026-07-29 the authorities derive:

- 104 tracked Nix files;
- 43 tracked/shebang Python files and 9 currently pre-commit-selected
  `bin/*-test.py` suites (selection does not imply speed);
- 35 tracked Bash scripts;
- 14 `johnw.*` option paths in the static/evaluated union (the old “4 options” note is
  stale; live value forcing remains a collector task);
- merged top-level `checks.<system>` outputs: 27 on `aarch64-darwin`, 28 each on
  `aarch64-linux` and `x86_64-linux` (not unique derivations or executed gates);
- update inventory: 199 total, 176 managed, 23 pending.

These are snapshot observations. Gates compare freshly derived before/after sets or a
versioned artifact; they do not require those bare numbers forever. In particular:

- #39’s `pending 18 → 12` is stale; the current lock-bearing npm family and pending set
  must be derived at implementation time (the 2026-07-29 measurement is 23 pending,
  with nine lock-bearing npm records, so the then-current delta would be 23 → 14).
- #43’s “inventory total stays 188” is replaced by **total is unchanged across the
  change**. The current total happens to be 199.
- `bin/quality` prose saying 11 Anvil MCP Python `*-test.py` files is stale; 12 are
  tracked today (three additional Elisp `*-test.el` files are a separate inventory).

## Tiers and cost contract

| Tier | Content | Placement | Budget semantics |
|---|---|---|---|
| pre-commit | formatting/lint, genuinely bounded unit tests, portable bounded eval | local hook | Initial wall-clock budget: **180 seconds** on Hera. Failure/timeout is red; current compliance is `unknown` until the timing artifact is recorded, and slow suites must move without losing invocation coverage. |
| pre-push | file/output/host/option collection, Darwin surface, consumers, signatures, system/agent checks | local hook | Initial wall-clock budget: **900 seconds** on Hera; every named target reports ran/pass, never silent skip. |
| CI / on demand | coverage.py branch report, full output/schema sweep, unsafe/live/soak suites, optional nix-eval-jobs projection | remote-safe CI or authorized self-hosted runner | Initial per-job budget: **1800 seconds**; tool/runner identity recorded; LAN-only root inputs must not be presented as GitHub CI evidence. |

The initial limits are policy ceilings, not claims about current performance. Durations
are measured on a named revision/host, stored in the artifact, and compared to the
limits. A timing regression is a concern even when correctness remains green.
Pre-commit cannot claim compliance until measurement completes and any slow
`gates-test.py`/GPG paths are assigned to an appropriate tier without losing their
invocation.

## Artifact and regression policy

The committed coverage artifact records:

- schema and source revision;
- Nix/flake-schema/coverage.py versions;
- complete denominators and observed path/attr sets, not counts alone;
- denominator provenance (`static-declaration`, registry, quality discovery, manifest)
  independently from runtime observation;
- target/tier/test-case status including `ran`, `passed`, `failed`, `skipped`,
  `not-run`, duration and evidence kind;
- assertion-call or named-assertion states where instrumentation exists; otherwise
  explicit `unknown`, never inheritance from process success;
- blind spots and unknown measurements;
- provenance commands.

Persistence is default-deny. Raw option values, environment variables, command
arguments, credentials, activation scripts and service configuration are forbidden.
The artifact stores path/status/type metadata, safe enumerations, or SHA-256 fingerprints
after the same normalization/security boundary used by the Darwin surface. Provenance
commands are argv arrays from an allowlisted command schema, not captured shell strings
or environments. A recursive sensitive-key/assignment scan runs before print/write.

The gate re-derives structural inventories cheaply on every pre-commit. Expensive
measurements are refreshed deliberately and must not regress without an explicit,
reviewable artifact update. A missing target, parser-schema change, duplicated tier
assignment, skipped assertion, or unexplained decrease is failure.

## Implementation order

Selected prior art is mapped explicitly:

- **build** the repo collector/artifact/regression layer;
- **compose** Nix file-entry diagnostics and Determinate schema forcing into the
  expensive tier;
- **adopt** coverage.py for Python line/branch data;
- **extend** existing `bin/quality`, parity/baseline and consumer-inventory patterns;
- **defer** nix-unit, Nixtest, nix-tests and Namaka until a concrete
  pure-unit/snapshot/script migration needs them;
- **defer** nix-eval-jobs until a bounded derivation projection and self-hosted runner
  justify its memory/toolchain cost;
- **reject** an evaluator fork, shell coverage dependency, or blanket deep forcing for
  A6.

1. Commit this research/design record.
2. Build a read-only collector plus schema-versioned artifact and negative tests.
3. Add `bin/quality coverage` as the only suite authority; hooks/CI delegate to it.
4. Measure and enforce tier timing, then split slow tests without deleting coverage.
5. Correct #39/#43 bodies to derived-before/after wording.
6. Run full verification, independent clean-context fess, and tracker closeout.

No host activation, package update, or credential provisioning is part of A6.
