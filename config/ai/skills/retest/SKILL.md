---
name: retest
description: Full model-support battery on any branch -- rebuild, unit tests, FPGA
  correctness vs the HuggingFace transformers source of truth, code review, comment-check,
  and a perf pass. Derives the target model set from the branch diff. Use when retesting
  a stack of PRs that adds or fixes support for one model or arch family on the FPGA
  pipeline.
---
# retest: Model-Support Retest Battery

## Overview

Confirm a model-support branch is correct against the **HuggingFace `transformers`
reference forward pass** (the source of truth), with no performance regression, a clean
review, and accurate comments. Work the phases in order, tracking each with your task tool.
**Do not stop at the first failure** -- finish the sweep and emit one consolidated result
table at the end.

The headline gate is **Phase 3**: FPGA/host logits, top-K overlap, and decoded tokens
compared against the HF reference. Everything else is supporting evidence. There is only one
pipeline here, so the oracle is HuggingFace -- not a legacy pipeline. For the categorical
byte-identity pipeline, use `/retest-categorical` instead (a separate command).

## Arguments (`$ARGUMENTS`)

`[model|slug|tag...] [--all] [--no-perf] [--no-review] [--no-comments] [--no-semantic]`

By default every phase runs. Set `MODELS` once from the branch diff and feed it to Phases 0,
3, and 6.

- **Bare model names / runtime slugs** (e.g. `llama_3p1_8b`) -- the model(s) under development.
  Normally intersect with the branch-derived set; but when the stack touches only shared infra
  and the diff cannot infer a model, an explicit model/slug is authoritative and defines the set.
- **Tags** (e.g. `[test]`) -- always a tag-intersection filter; narrows, never widens.
- **`--all`** -- bypass branch-diff narrowing; fall back to the full support matrix at/above
  `--min-support working`. The only thing that widens past the model under development.
- **`--no-perf`** -- skip Phase 6.
- **`--no-review`** -- skip Phase 4.
- **`--no-comments`** -- skip Phase 5.
- **`--no-semantic`** -- within Phase 3, skip only the Python equivalence sub-check
  (`logit_equivalence_test.py`), keeping the FPGA golden gate.
- **Empty diff + no `--all`** -- report "no model-affecting changes detected" and run only
  Phases 1-2 + 4-5, defaulting to `make build-test -j 4`.

**Invariant: NO hardcoded model list.** The model set is computed every run from the diff
(`git diff --name-only <BASE>...HEAD`), mapping changed paths back to `models.yaml`
`name`/`slug` via four signals: (A) `config/models.yaml` edits, (B) `ingest/export/*_export.py`
arch export modules, (C) `h/tron/plugins/*.hpp` hand-authored plugins, (D)
`gen/src/tron/h/tron/plugins/*` build artifacts. Shared-infra edits are supporting -- they do
not auto-widen the gate to sibling models; full-matrix is opt-in via `--all`. An empty or
unrunnable derived set is classified **INCOMPLETE**, never a success. See the spec for the
exact derivation scripts and the runtime-slug-per-executor table.

## Phases (run in order)

0. **Provision weights + pre-warm cache** (mandatory) -- provision missing weights to the
   scratch path; pre-warm the FPGA weight cache so the first Phase-3 run does not TIMEOUT.
1. **Rebuild** -- pick the build flavor from `CHANGED`; require exit 0 and zero `error:` lines.
   `make build-categorical` is not a target in main -- never use it.
2. **Unit tests (three layers)** -- Haskell ingest IR (`ingest-cabal test`), C++ Catch2 host
   (`make test-host`), and ingest + C++ integration (`make test-ingest`). All must pass,
   including byte-identity MD5 baselines. Never weaken or skip a failing test.
3. **FPGA/host correctness vs HuggingFace (headline gate)** -- three checks vs HF: logit
   allclose/TVD, top-1/head-of-distribution (top-K overlap), and decoded-token parity. Gate
   is the C++ `t_generate_ingest_1` (`force_generate` -> `check_golden_logits` against a
   content-addressed HF golden). Most derived models have NO registered TEST_CASE -- a
   zero-name sweep is `NO-COVERAGE` (INCOMPLETE), not a PASS; author a case + golden or run
   the runtron-vs-golden fallback. Per-model tolerances are the committed literals in
   `t/t_generate_ingest_1.cpp`. MoE models must use realistic prompts (synthetic
   incrementing-id prompts overflow to NaN, issue #2808).
4. **Code review** (skip if `--no-review`) -- invoke `/deep-review` scoped to the branch diff;
   it routes reviewers by touched language and adds security + perf reviewers.
5. **Comment-check** (skip if `--no-comments`) -- invoke `comment-audit` scoped to the diff;
   complete only when `stats` reports zero pending.
6. **Performance + decode-token parity** (skip if `--no-perf`) -- generate through the
   pipeline on the derived executor; 64-token prompt, 32-token greedy decode, 3 trials, report
   median. Flag >5% median gen-time/tok regression. Phase 3 (in-process gate) is a different
   codepath from Phase 6 (external `runtron stream-generate-text`).

The spec also documents **token fidelity across context-length boundaries** (boundary set
`{8, 64, 256, 4096, 16384}`), a methodology that gates only where a binary registers the
boundary cells (mandatory in `/retest-categorical`, an acknowledged coverage gap on the
generic path).

## Top operating rules (apply to every phase)

- **Nix shell.** Wrap every build/test/ingest command as
  `nix develop --command bash -c '<CMD>'`; outside it the toolchain is missing.
- **`-j 4` max** build jobs.
- **Executors.** Dense models on `tp1` (1 card); MoE / 32B+ models on `tp4` (4 cards),
  per-variant from the derived set. `ls /dev/vfio/` does not prove cards are free -- check
  `pgrep -af 'runtron\|t_generate'`.
- **Weights.** `/opt/positron/weights/huggingface/...` is read-only; missing weights go to
  `/tmp/retest_weights/<repo>`. Never edit the weights-root constant or a registry
  `default_weights`.
- **One TEST_CASE per process** for all FPGA tests -- Catch2 single-process mode shares FPGA
  state across cases. Never run the binary unfiltered or with a multi-match filter as the gate.
- **Background** long builds/sweeps and let the harness notify you; do not poll.
- **Claim discipline.** Bind every correctness statement to its oracle and code path. Report
  `PASS / SKIPPED / QUARANTINED / DIVERGE / NO-COVERAGE` as distinct states -- never collapse
  them into "N/N PASS".

The spec includes a **Known traps** table (rule these out before blaming an HF divergence):
corrupt Nix fetcher cache, stale CMake graph, stale plugin after rebase, unprovisioned uv
venv, wrong weights dir, in-process state contamination, HBM instance-budget overflow, and
MoE bf16 overflow on synthetic prompts.

## Overall verdict

- **`HF-CORRECT`** -- all measured rows PASS/QUARANTINED-PASS vs HF, no DIVERGE, no
  NO-COVERAGE, no >5% regression, review/comments clean.
- **`INCOMPLETE`** -- any NO-COVERAGE/SKIPPED/WEIGHTS-MISSING/TIMEOUT, or an empty/unrunnable
  derived set.
- **`REGRESSION`** -- any HF DIVERGE, any >5% slowdown, or any blocking review finding.

## Authoritative procedure

The complete, authoritative phase-by-phase procedure -- every command, script, and gate -- is
in `references/spec.md`; follow it exactly. Do not paraphrase or reorder it; the tolerances,
gate literals, embedded bash, and verdict taxonomy there are load-bearing.
