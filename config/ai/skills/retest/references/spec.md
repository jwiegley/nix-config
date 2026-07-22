# /retest -- model-support retest procedure (authoritative spec)

Confirm a model-support branch is correct against the **HuggingFace `transformers`
reference forward pass** (the source of truth), with no performance regression, a clean
review, and accurate comments. Work the phases in order, tracking each with your task
tool. **Do not stop at the first failure** — finish the sweep and emit one consolidated
result table at the end.

The headline gate is **Phase 3**: FPGA/host logits, top-K overlap, and decoded tokens
compared against the HF reference. Everything else is supporting evidence. There is only one
pipeline here, so the oracle is HuggingFace — not a legacy pipeline; this replaces the
legacy-byte-identity gate used by the categorical `/retest-categorical`.

# Arguments (`$ARGUMENTS`)

Defaults: every phase runs. Set `MODELS` once (see "Derive the target model set") and feed
it to Phases 0, 3, and 6.

- **Bare model names / runtime slugs** (e.g. `llama_3p1_8b`, `ingested-gpt-oss-20b`) → the
  model(s) under development. They normally **intersect** with the branch-derived set
  (restricting Phases 3 & 6); but when the stack touches only shared infra and the diff cannot
  infer a specific model, an explicit model/slug is **authoritative** and defines the set
  directly — the one case where an argument widens rather than narrows.
- **Tags** (e.g. `[test]`) → always a tag-intersection filter (`filter_models`); narrows the
  derived set, never widens it. Variants with no tags are excluded under tag filtering.
- **`--all`** → bypass branch-diff narrowing; fall back to the full support matrix at/above
  `--min-support working`, optionally tag-filtered. Precedence: `--all` > explicit
  model/tag filter > branch-diff set. **This is the only thing that widens past the model under
  development** — a shared-infra edit never auto-triggers it (see "Derive the target model
  set"). For the categorical pipeline's all-model byte-identity sweep, use `/retest-categorical`
  instead.
- **`--no-perf`** → skip Phase 6.
- **`--no-review`** → skip Phase 4.
- **`--no-comments`** → skip Phase 5.
- **`--no-semantic`** → within Phase 3, skip the Python equivalence sub-check
  (`logit_equivalence_test.py`), keeping the FPGA golden gate. **Narrower than
  `/retest-categorical`'s `--no-semantic`** (which skips an entire standalone Phase-4 semantic
  matrix); here it only skips Phase-3 check 1. Named the same as the `/retest-categorical` flag
  for muscle memory, but the semantics differ — do not assume parity.
- **Empty diff + no `--all`** → report "no model-affecting changes detected" and run only
  Phases 1–2 + 4–5 (build / unit / review / comments). With an empty `CHANGED` the Phase-1
  flavor table has nothing to key on, so **default to `make build-test -j 4`** (the test
  flavor) for Phases 1–2. Do **not** silently run a hardcoded model list.

# Derive the target model set from the branch (the core generality step)

**Invariant: NO hardcoded model list. The model set is computed every run from the diff.**

**Scope = the model this PR stack is advancing, not the full support matrix.** This command is
for a stack of PRs that adds or fixes support for **one** model (or one arch family). Advancing
a model always means also touching shared infrastructure — shared export files, base plugins,
IR passes — but those edits are **supporting**: they do **not** widen the Phase-3
token-fidelity gate to every sibling model. Resolve "the model under development" from the most
*specific* signals (a new/changed `config/models.yaml` variant; a changed arch-specific
`ingest/export/<arch>_export.py`; or a changed arch-specific `h/tron/plugins/<arch>.hpp`) and
gate only that. **Never auto-escalate to the whole family or full matrix because a shared file
changed** — full-matrix HF regression is opt-in via `--all`, and the categorical pipeline's
all-model byte-identity sweep is a separate command, `/retest-categorical`.

Run this before Phase 0, from the worktree root (absolute path; never rely on relative cwd):

```bash
cd <worktree-root>
BASE=$(git merge-base HEAD main)
CHANGED=$(git diff --name-only "$BASE"...HEAD)   # three-dot: every commit on this stack since
                                                 # main — the stack's full contribution
```

Map each changed path back to a `models.yaml` `name`/`slug` via these four signals.

**Signal A — `config/models.yaml` edits (highest fidelity).** A new variant or a changed
`default_weights`/`executors` is exactly what must be retested.

```bash
if echo "$CHANGED" | grep -q '^config/models.yaml$'; then
  git diff "$BASE"...HEAD -- config/models.yaml \
    | grep -E '^\+\s*(- name:|- slug:|slug:|name:)' \
    | sed -E 's/^\+\s*-?\s*(name|slug):\s*//'
fi
```

This catches *added* `name:`/`slug:` lines. It will **miss a `default_weights`- or
`executors`-only edit** on an existing variant (those changed lines carry no `name:`/`slug:`
key). When the diff touches `default_weights`/`executors` without a new slug, also read the
surrounding hunk stanza and resolve the edit back to the enclosing variant's slug — that
variant must be retested too.

Each `name` → runtime slugs (join below); each `slug` → its model's variants. Enumerate a
`name` → runtime slugs + executor + weights with `compute_runtime_slug`:

```bash
python3 - "$NAME" <<'PY'
import sys, yaml
sys.path.insert(0, "config")
from model_definitions import compute_runtime_slug
name = sys.argv[1]
reg = yaml.safe_load(open("config/models.yaml"))
for m in reg["models"]:
    if m["name"] != name: continue
    for v in (m.get("variants") or []):
        if v.get("disabled"): continue
        base = v.get("slug_base", v["slug"])
        for ex in v["executors"]:
            print(f"{compute_runtime_slug(base, ex)}\t{ex}\t{v['default_weights']}\t{v.get('tags', [])}")
PY
```

A model with **no `variants:` block** (`variants` is `None`) prints nothing — it is tracked
but not runnable. Several generated archs are in this state on main (e.g. `deepseek_v3`,
`gemma_3_27b`, `qwen_3_30b_moe`, `seed_oss_36b`, `glm_4p7`, `minimax_m2`). See "Empty /
unrunnable derived set" below — do **not** treat a variant-less arch as covered.

The slug in YAML is **not** the `--model` string. The runtime slug is per-executor:

| executor | runtime slug |
|---|---|
| `tp1` / `perm_tp1` | `<base>` (no suffix) |
| `tp2` / `tp4` / `perm_tp2` / `perm_tp4` | `<base>-tp2` / `<base>-tp4` |
| `host` | `<base>-host` |
| `host_bf16` / `host_fp16` | `<base>-host-bf16` / `<base>-host-fp16` |

**Signal B — `ingest/export/*_export.py` (architecture export modules).** Each module
patches a specific transformers class (its `register_patch(...)` `cls=` argument) and affects
all `ingest.source: generated` models of that architecture. **Derive the class from the
module, do not trust a frozen table** — a brand-new export module will not be in any
hardcoded list:

```bash
# For each changed ingest/export/*_export.py, recover the patched class:
echo "$CHANGED" | grep '^ingest/export/.*_export\.py$' | while read -r f; do
  grep -oE 'cls=[A-Za-z0-9_]+' "$f" | sort -u   # the transformers class it patches
done
```

Then map that class to `models.yaml` via its `ingest.hf_id` / architecture. The known
mappings on main (for orientation — re-derive, don't rely on this staying complete):

| Export module | patched class (`cls=`) | Affected `models.yaml` names |
|---|---|---|
| `mixtral_export.py` | `MixtralSparseMoeBlock` | `ingested_mixtral_8x7b` (and hand-authored `mixtral_8x7b`) |
| `gpt_oss_export.py` | `GptOssExperts` | `ingested_gpt_oss_20b`, `ingested_gpt_oss_120b` |
| `glm4_moe_export.py` | `Glm4MoeMoE` | `glm_4p7` (and GLM-family routing) |
| shared (`torch_export.py` / `model_patch.py` / `load_model.py` / `moe_ops.py`) | generic path | **all** generated models |

A changed **arch-specific** `*_export.py` (e.g. `qwen3_next_export.py`) — even one not in the
table above — names the architecture under development: scope to that arch's `models.yaml`
model(s). A changed **shared** export file (`torch_export.py` / `model_patch.py` /
`load_model.py` / `moe_ops.py`) is the generic path under *every* generated model, but editing
it is the normal cost of landing one model's support — it is **supporting infra, not a fan-out
trigger**. Do **not** select all generated models from a shared-file edit; keep the gate on the
model(s) the specific signals named. Only an explicit `--all` enumerates the full generated set:

```bash
# Under an explicit --all only — enumerate every generated arch for a full-matrix sweep:
python3 config/model_definitions.py --registry config/models.yaml --list-ingest
```

`--list-ingest` prints one line per generated arch:
`HF_ID required|optional default_weights NAME target_executor` (target_executor is
`plain`/`permuted`). It lists the arch even when the arch has no runnable variant — that
listing alone does **not** make the model gateable (see "Empty / unrunnable derived set").

**Signal C — `h/tron/plugins/*.hpp` (hand-authored plugins).** Strip the extension to get
the family base; select every `models.yaml` name sharing that architecture base, then its
runtime slugs:

```bash
echo "$CHANGED" | grep '^h/tron/plugins/' | sed 's#.*/##; s#\.hpp$##'
# e.g. "llama" -> all models.yaml names starting llama_ -> their runtime slugs
```

**Signal D — `gen/src/tron/h/tron/plugins/*` (build artifacts).** Normally `.gitignore`'d,
so this rarely appears in a diff. Treat Signal B (the export source that produces it) as the
real trigger. If a generated plugin is committed, strip the extension to recover the arch
`name` and look it up.

**The join.** For every collected `name`, expand to runtime slugs; for every `slug` from
Signal A, resolve its model's runtime slugs. De-dup. Set `MODELS`, recording each runtime
slug's `(slug, executor, default_weights, tags)` row (needed by Phases 0/3/6). If explicit
args were given, intersect (or, per the rule above, let an explicit model define the set when
the diff inferred none); if `--all`, replace with the full matrix. **Do not auto-escalate to
`--all`:** a shared-export edit or a base-plugin edit is the expected footprint of advancing one
model's support, so `MODELS` stays the model(s) the specific signals named — it does not
silently expand to the architecture family or the full matrix. A shared-path change *may* affect
sibling models; flag that in the final report, but verifying them is a deliberate `--all`, not
the default sweep.

**Empty / unrunnable derived set.** If the join produces zero runnable rows — empty diff with
no `--all`; every changed arch is `source: generated` but variant-less (no
`executors`/`default_weights`); or the stack touches **only shared infra** (shared export
files, IR passes) with no model-specific signal and no explicit model arg — do **not** report
success off Phases 1/2/4/5 alone. Classify the overall run **INCOMPLETE** with the explicit
reason ("model tracked but not runnable — no variant/executor/weights", "no model-affecting
changes", or "shared-infra change with no inferable model — name the model explicitly or pass
`--all`"), and say so in the final report.

# Operating rules (apply to every phase)

- **Nix shell.** Wrap every build/test/ingest command as `nix develop --command bash -c
  '$CMD'`; outside it the toolchain (GHC 9.12, clang-19, the uv-managed Python venvs) is
  missing.
- **`-j 4` max** build jobs.
- **Executors.** Dense models on `tp1` (1 card); MoE / 32B+ models on `tp4` (4 cards).
  Selection is per-variant from the derived set (the variant's `executors`), **not** a fixed
  enumeration. `ls /dev/vfio/` does not prove the cards are free — check
  `pgrep -af 'runtron\|t_generate'`.
- **Weights.** `/opt/positron/weights/huggingface/...` is read-only; missing weights go to
  `/tmp/retest_weights/<repo>` (Phase 0 provisions them). The test's weights-root constant
  auto-falls-back to the scratch path — **never edit the weights-root constant or a
  `ModelDef`/registry `default_weights`.**
- **One TEST_CASE per process** for all FPGA tests. Catch2 in single-process mode shares
  FPGA state (KV-cache pages, worker assignment, scratch HBM) across cases, so a later case
  can flip on residue even though each passes alone. Never run the binary unfiltered or with
  a multi-match filter (`"[long]"`) as the gate — that is interactive-debugging mode and
  yields non-reproducible verdicts.
- **Background** long builds/sweeps and let the harness notify you; don't poll.
- **Claim discipline.** Bind every correctness statement to its oracle and code path (e.g.
  "logits within the committed TVD/top-K tolerance of the content-addressed HF golden, C++
  `force_generate(model, tokens, {.max_layers=N, .max_minibatches=1})` →
  `check_golden_logits(...)` in `t_generate_ingest_1`, prompt+response logits, per-process
  isolated"). Report `PASS / SKIPPED / QUARANTINED / DIVERGE / NO-COVERAGE` as distinct
  states — never collapse them into "N/N PASS".

# Known traps (rule out before blaming an HF-correctness divergence)

A failure that *looks* like a divergence from the HF reference is usually one of these:

| Symptom | Cause → fix |
|---|---|
| `disk I/O error` / `database disk image is malformed` from `nix develop` | corrupt Nix fetcher cache → `rm -f ${XDG_CACHE_HOME:-$HOME/.cache}/nix/fetcher-cache-v4.sqlite`, retry |
| `ninja: error: '…' missing and no known rule` (deleted source) | stale CMake graph → `rm -f gen/config/<flavor>` (the relevant `dev`/`test`/`ingest` stamp), rebuild |
| plugin output looks stale after a rebase/restack | the build missed a Haskell change → force-regen the affected plugin under `gen/src/tron/h/tron/plugins/` and rebuild (`make build-ingest -j 4`); confirm mtime is post-rebase |
| `ModuleNotFoundError` / `No such file: tron-reference-logits` / `uv` import errors on the golden or equivalence path | the `ingest/export` uv venv is not provisioned (`tron-reference-logits` is a console script there, not a `bin/` file) → run `make ingest-deps` (skipped inside `nix develop`); this is **not** a DIVERGE |
| `unable to load tensor: …experts.0.gate_up_proj` | wrong weights dir (raw HF repo vs ingest-prepared) → copy the path verbatim from the existing TEST_CASE / registry `default_weights` |
| test FAILs in a multi-case run but PASSes solo | in-process state contamination, **not** a regression → always re-run the single case by exact name in a fresh process before believing a FAIL |
| `ERROR allocating HBM space … start_addr 0x48000000 … DEBUG EXIT` | instance-budget overflow (model exceeds its `1/n` share) → re-run with `SYSTEM_CONFIG="--instance 0,1"` (whole machine) |
| same HBM error persisting across fresh processes after a wait, large multi-GB `start_addr` | genuine stale FPGA HBM → needs operator reset; report and stop |
| SIGABRT `m_star != -inf` on an **MoE** model with a synthetic prompt | deterministic MoE bf16 overflow→NaN on degenerate input (issue #2808), laundered to -inf by x86 `max()`. **Never feed an MoE model synthetic incrementing-id prompts**; use a realistic tokenization. |

# Phase 0 — Provision weights + pre-warm cache (mandatory)

Provisions missing weights (some repos ship only PyTorch `.bin`) and pre-warms the FPGA
weight cache so the first Phase-3 run doesn't pay a multi-minute populate and TIMEOUT. The
`MODELS` table is **built from the derived set** (see "Derive the target model set") — each
entry is `(default_weights_repo, runtime_slug)` from the join, **not** a hardcoded roster. If
the derived set is empty/unrunnable, skip Phase 0 and mark the run INCOMPLETE.

Before the first golden or equivalence run, confirm the `ingest/export` uv venv resolves
(outside Nix): `nix develop --command bash -c 'tron-reference-logits --help >/dev/null'`, or
`make ingest-deps`. A missing venv is a setup gap, not a DIVERGE (see Known traps).

```bash
nix develop --command bash -c '
set -uo pipefail
WEIGHTS_ROOT=/opt/positron/weights/huggingface
SCRATCH_ROOT=/tmp/retest_weights
CACHE_ROOT=/opt/positron/weights_cache/cached
# (huggingface-repo, runtime-slug) — entries computed from the branch-derived model set.
MODELS=(
  "<default_weights_repo>            <runtime_slug>"
  # … one line per derived (default_weights, runtime_slug) pair …
)
for entry in "${MODELS[@]}"; do
  repo="${entry%% *}"
  if   ls "$WEIGHTS_ROOT/$repo"/*.safetensors >/dev/null 2>&1; then echo "  have (canonical): $repo"
  elif ls "$SCRATCH_ROOT/$repo"/*.safetensors >/dev/null 2>&1; then echo "  have (scratch):   $repo"
  else echo "  downloading: $repo"; python3 bin/get_model "$repo" --to "$SCRATCH_ROOT/$repo" \
         || echo "    DOWNLOAD-FAILED $repo (private/positron-internal repos must be pre-populated by ops)"; fi
done
printf "x\n" > /tmp/retest_warmup_prompt.txt
for entry in "${MODELS[@]}"; do
  slug="${entry##* }"
  find "$CACHE_ROOT" -maxdepth 3 -type d -name "$(basename "${entry%% *}")" -print -quit 2>/dev/null | grep -q . \
    && { echo "  warm: $slug"; continue; }
  echo "  prewarming: $slug"
  SYSTEM_CONFIG="--instance 0,1" timeout 600 gen/runtron stream-generate-text \
    --model "$slug" -f /tmp/retest_warmup_prompt.txt \
    --prompt-length 4 --length 1 --temperature 0 --pay-for-determinism --seed 42 \
    >/dev/null 2>&1 || echo "    PREWARM-FAILED: $slug (Phase 3 will be slow)"
done
'
```

`bin/get_model REPO --to DIR` runs HF `snapshot_download` and converts `.bin`→`.safetensors`;
**always pass `--to`** (without it, it defaults to the read-only canonical root). If pre-warm
is skipped, keep the Phase-3 timeout ≥30 min or cold-cache first runs read as TIMEOUT.

# Phase 1 — Rebuild

Pick the build flavor from `CHANGED`. **`make build-categorical` is not a target in main —
never use it.**

| `CHANGED` content | command |
|---|---|
| Empty / doc-only (no model-affecting changes) | `nix develop --command bash -c 'make build-test -j 4'` |
| Haskell-only (`ingest/**/*.hs`), no C++/plugin link needed | `nix develop --command bash -c 'bin/ingest-cabal build'` |
| C++/headers (`h/`, `src/`, `t/`) | `nix develop --command bash -c 'make build-test -j 4'` |
| Ingest + C++ integration (export modules, generated plugins, the torch.export→Haskell→plugin→link path, or any FPGA ingest test) | `nix develop --command bash -c 'make build-ingest -j 4'` |
| Default / ambiguous when models are in the derived set | `nix develop --command bash -c 'make build-ingest -j 4'` (superset: sets `BUILD_TEST_MODELS=ON` and `BUILD_INGEST_MODELS=ON`) |

Require exit 0 and zero `error:` lines. If `gen/` is corrupt from a prior non-Nix `make`,
`rm -rf gen` and rebuild. Switching build flavors triggers a full CMake reconfigure
(`gen/config/*` does `rm -rf gen/config`). (Stale-graph and stale-plugin recovery: see Known
traps.)

# Phase 2 — Unit tests (three layers)

```
nix develop --command bash -c 'bin/ingest-cabal build && bin/ingest-cabal test'   # Haskell ingest IR
nix develop --command bash -c 'make build-test -j 4 && make test-host'            # C++ Catch2 host
nix develop --command bash -c 'make test-ingest'                                  # ingest + C++ integration (FPGA)
```

`make test-ingest` = `build-ingest` then `ctest -R ingest` → runs `t_generate_ingest_1`
(FPGA-locked); it is the Catch2 binary that loads ingested plugins and gates logits against
HF goldens (**not** a pytest runner). **Run it whenever the Phase-1 build flavor was
`build-ingest`** (i.e. ingest C++ linked), independent of whether the derived model set is
non-empty — a shared-ingest C++ change with an empty model set still must exercise the
integration layer. Only skip it when FPGA is genuinely unavailable.

All must pass, including byte-identity MD5 baselines. Never weaken or skip a failing test —
fix the root cause. If a baseline legitimately changed because emitter output changed, update
it deliberately and say why.

# Phase 3 — FPGA/host correctness vs HuggingFace (headline gate)

The HuggingFace `transformers` reference forward pass is the source of truth. The FPGA gate is
the C++ `t_generate_ingest_1`: each golden TEST_CASE calls
`force_generate(model, tokens, {.max_layers=N, .max_minibatches=1})` (prompt + a few
generated steps) and then `check_golden_logits(...)` against a content-addressed HF golden —
this is the codepath your correctness claim must bind to (not `generate(max_steps=0)` /
`LogitsMode::LAST`, which exist but are the decode/runtron path, not the gate). Three checks,
all vs HF:

1. **Logit allclose / TVD.** Python path
   `nix develop --command bash -c 'python ingest/runtime/scripts/logit_equivalence_test.py
   --model $HF_ID --output-dir /tmp/logit_test'`. `logit_equivalence_test.py` is a thin mode
   wrapper; the flags and metrics live in `ingest/runtime/tron_ingest_tools/logit_test.py`
   (shared with the bulk variant). Defaults: `--atol 0.1`, `--rtol 0.01`,
   `--tvd-threshold 0.01` (flag is `--tvd-threshold`, not `tvd`); `--dtype float16`;
   `--device` defaults to **`cuda` if available else `cpu`** (pass `--device cpu` to force a
   CPU oracle). It forces HF eager attention (`config._attn_implementation="eager"`) but runs
   on the resolved device/dtype — i.e. **GPU+fp16 by default**, not CPU. `--dtype float64`
   auto-tightens atol/rtol/tvd-threshold to `1e-6` each (independently). The script reports
   both a strict allclose `passed` flag and a `functional_equivalence` (TVD) flag; the gate
   here is functional/TVD equivalence + exit 0. (The C++ FPGA golden path —
   `tron-reference-logits` — is the one that pins CPU; see check 3.) FPGA path:
   `check_golden_logits` TVD/outlier/top-K caps inside `t_generate_ingest_1`.
2. **Top-1 / head-of-distribution.** FPGA top-K overlap (`topk_params{k=5, min_overlap≥3}`,
   per the committed literals); Python `top1_agreement` / `top5_agreement` metrics (defined
   in `logit_test.py`). There is **no `--strict-top1` flag** — do not invent it; top-1 is the
   top-K-overlap guard (C++) and the agreement metrics (Python).
3. **Decoded-token parity.** For a model **with** a registered `t_generate_ingest_1`
   TEST_CASE, the canned-token comparison (`load_tokens_by_hash` → `force_generate` →
   `check_golden_logits`) is the gate. For a model **without** one, run the explicit
   runtron-vs-golden fallback below.

`--no-semantic` skips check 1's Python sub-run only; the FPGA golden gate still runs.

**Coverage precondition — most derived models have NO registered TEST_CASE.**
`t_generate_ingest_1` ships golden cases for only `llama-3.1-8b` (plain + permuted),
`gpt-oss-20b`, and `phi-4` (the Mixtral case is SKIP'd — see below). Any other derived model
(`qwen-2.5-32b`, `gpt-oss-120b`, `chinese-alpaca`, `glm-4p7`, `gemma`, …) has no case, so the
tag-filtered sweep resolves to zero names. **A zero-name sweep is NOT a PASS** — the sweep
runner below aborts loudly when `FILTERS` is non-empty but matches nothing, and such a model
is reported `NO-COVERAGE` (INCOMPLETE), unless you run the runtron-vs-golden fallback for it.
**Adding a new model is an authoring step**: write a `t_generate_ingest_1` TEST_CASE with a
content-addressed golden (recipe below) and choose its tolerance literals — there is no
generic per-model harness and a new model has no pre-committed tolerance.

**Runtron-vs-golden fallback (first-class gate for models lacking a TEST_CASE):**

```bash
nix develop --command bash -c '
set -uo pipefail
# 1. HF golden tokens (CPU oracle):
bin/extract_logits --model <weights> --max-layers <L> \
  --text-file <prompt.txt> --max-tokens <N> --save-tokens \
  --scratch-dir /scratch/test/data | tee /tmp/golden_tokens.txt
# 2. FPGA decode under the derived executor, greedy/deterministic:
SYSTEM_CONFIG="--instance 0,1" gen/runtron stream-generate-text \
  --model <runtime_slug> -f <prompt.txt> --prompt-length <P> --length <N> \
  --temperature 0 --pay-for-determinism --seed 42 --log-intermediates \
  > /tmp/fpga_decode.txt 2>&1
'
# 3. Pass/fail: the FPGA-decoded token IDs must match the golden token sequence
#    exactly (greedy/temp 0). Any mismatch position is a DIVERGE; a clean match
#    is PASS. (MoE models: realistic prompt only — see below.)
```

**Golden generation recipe** (content-addressed goldens under `/scratch/test/data/`):

```bash
nix develop --command bash -c 'bin/extract_logits --model <weights> [--gptq] \
  --max-layers <L> --text-file <prompt.txt> --max-tokens <N> --save-tokens \
  --scratch-dir /scratch/test/data'
```

`bin/extract_logits` subprocesses into the `ingest/export` uv venv console script
`tron-reference-logits` (`reference_logits:main`), which runs the HF forward **on CPU**
(`reference_logits.py:141`, `device = torch.device("cpu")`); it does **not** set eager
attention on that path. `--prepend-bos` defaults true; `--gptq` is accepted-and-ignored at
both the `extract_logits` shim and the frontend (quantization is auto-detected from
`config.quantization_config`) — do not expect it to change behavior.

**Per-model tolerances are NOT global** — they live in the test
(`t/t_generate_ingest_1.cpp`). Use the test's committed literals; do not invent new ones, and
note that a brand-new model has **no** committed tolerance (choosing one is a deliberate,
reviewed authoring step). Committed values on main (`t/t_generate_ingest_1.cpp`):
Llama-3.1-8B GPTQ `tvd 0.05`, `outlier_cap 0.3 / max 10%`, `topk{k=5, overlap 3}` (the
permuted case uses `outlier_cap 0.1 / max 6%`); GPT-OSS-20B `tvd 0.10`, extracted
`--no-prepend-bos`; Phi-4 `tvd 0.08`, `outlier_cap 0.32 / max 15%`, `topk{k=5, overlap 4}`.

**Executor map** is per-derived-variant (dense → tp1; MoE / large → tp4); **no fixed
enumeration**. `t_generate_ingest_1` currently registers only a single prompt per model
(there are **no `[long]`/`[realistic]` tags** in any `t/` binary — that distinction lived only
in the categorical `t_generate_categorical_fpga_real`, absent from main). **Token fidelity
across context-length boundaries** is the methodology below; apply it honestly scoped to what
the binary registers: run the boundary sweep where a binary actually registers the boundary
cells and **gate** divergences there (a `DIVERGE` on a longer case while the short case passes
is a real bug — do not excuse it); where a model has only a single short case, report each unrun
boundary length as an acknowledged seq-len coverage gap (`NO-COVERAGE`) rather than claiming
`[long]` or boundary coverage that was never run — in the generic path that gap is reported, not
a run-level INCOMPLETE (the sweep is a hard gate only where boundary cells are registered, and
mandatory in `/retest-categorical`). Decide each length's scope against the model's
`max_position_embeddings` before running it, and report out-of-scope lengths as `OUT-OF-SCOPE`
(`N/A`), never as PASS.

**Isolated sweep runner — one TEST_CASE per process by exact name** (`BIN` and the test-name
filter are parameterized for the chosen binary, e.g. `t_generate_ingest_1` or `t_generate`):

```bash
#!/usr/bin/env bash
set -uo pipefail
set -f   # noglob: Catch2 tags are bracket-globs ([phi-4]); unquoted they expand against cwd
         # dirs (h/, t/) and mangle multi-segment tags into single-char tags.
BIN=./gen/t_generate_ingest_1   # or ./gen/t_generate — parameterize for the derived set
LOGDIR=/tmp/retest_fpga_logs; mkdir -p "$LOGDIR"
[ -x "$BIN" ] || { echo "FATAL: $BIN missing — run Phase 1 first"; exit 2; }
"$BIN" --list-tests >/dev/null 2>&1 || { echo "FATAL: test binary won't list tests"; exit 2; }
FILTERS="$*"   # tag filters derived from MODELS; empty -> sweep all listed cases
NAMES=()
if [ -n "$FILTERS" ]; then
  for f in $FILTERS; do
    matched=$("$BIN" --list-tests "$f" 2>/dev/null | sed -n 's/^  //p')
    [ -n "$matched" ] && while IFS= read -r line; do NAMES+=("$line"); done <<< "$matched"
  done
  # A derived model with no registered TEST_CASE => zero names. This is NOT a clean
  # sweep; it is NO-COVERAGE. Fail loudly so it is reported, not silently passed.
  if [ "${#NAMES[@]}" -eq 0 ]; then
    echo "NO-COVERAGE: filters [$FILTERS] matched zero TEST_CASEs in $BIN."
    echo "  Author a TEST_CASE + golden, or use the runtron-vs-golden fallback. INCOMPLETE."
    exit 3
  fi
else
  while IFS= read -r line; do NAMES+=("$line"); done < <("$BIN" --list-tests 2>/dev/null | sed -n 's/^  //p')
fi
declare -A SEEN; UNIQ=()
for n in "${NAMES[@]}"; do [ -z "${SEEN[$n]:-}" ] && { SEEN[$n]=1; UNIQ+=("$n"); }; done
for name in "${UNIQ[@]}"; do
  safe=$(printf '%s' "$name" | tr -cd 'a-zA-Z0-9-' | head -c 60); log="$LOGDIR/${safe}.log"
  start=$(date +%s); timeout 1800 "$BIN" "$name" > "$log" 2>&1; rc=$?; dur=$(( $(date +%s) - start ))
  # 30-min timeout: cold-cache 120B first-runs spend ~5min populating weights_cache.
  # check_golden_logits failure strings (testutil.cpp): "Max TVD = … > … = tolerance"
  # (TVD/outlier) and "overlap at step … is …/…, below min …" (top-K). There is no
  # "first divergence" / "N/N positions match" wording in this binary.
  if   [ $rc -eq 0 ] && grep -q 'SKIPPED' "$log"; then v=SKIPPED
  elif [ $rc -eq 0 ]; then v=PASS
  elif [ $rc -eq 124 ]; then v="TIMEOUT(30m)"
  elif grep -qiE "acquire lock|lock after|device busy|EBUSY" "$log"; then v="LOCK-CONTENTION"
  elif grep -qiE "Max TVD|below min|outlier|top-?[0-9k] overlap" "$log"; then v="DIVERGE: $(grep -oiE 'Max TVD = [^,]*|overlap at step [0-9]+ is [0-9]+/[0-9]+' "$log" | head -1)"
  elif grep -qiE "Failed to open file|No such file|unable to load tensor" "$log"; then v="WEIGHTS-MISSING"
  else v="FAIL(rc=$rc)"; fi
  printf '%-70s  %-18s  (%ds)\n' "$name" "$v" "$dur"
  sleep 15   # let tp4 device locks release between cases
done
```

(Note: `t_generate_ingest_1` / `t_generate` emit no Catch2 `mayfail` marker, so there are no
QUARANTINED-PASS/FAIL outcomes from these binaries today; the QUARANTINED rows below apply
only if a `mayfail`-tagged case is later added.)

**Verdict taxonomy** (report these distinctly):

| Verdict | Counts toward the gate? |
|---|---|
| `PASS` / `QUARANTINED-PASS` | yes |
| `DIVERGE` | **NO — diverges from the HF reference beyond tolerance — real correctness regression** |
| `NO-COVERAGE` | NO — INCOMPLETE; derived model has no TEST_CASE/golden and no fallback run |
| `SKIPPED` / `WEIGHTS-MISSING` / `TIMEOUT` | NO — INCOMPLETE (Phase 0 should have provisioned/pre-warmed) |
| `QUARANTINED-FAIL` | does not block ship, but report as a known-flake hit (only if a `mayfail` case exists) |
| `LOCK-CONTENTION` | re-run alone; if it still fails alone, escalate |
| `FAIL(rc=…)` | investigate (SIGABRT/SIGSEGV); not necessarily a correctness bug — see Known traps |

**Gate:** every model in the derived set must `PASS`/`QUARANTINED-PASS` on its registered
case(s) vs HF. Any `DIVERGE` fails. Any
`NO-COVERAGE`/`SKIPPED`/`WEIGHTS-MISSING`/`TIMEOUT` makes the run INCOMPLETE.

**MoE models must use realistic prompts.** Synthetic incrementing-id prompts overflow an MoE
expert FFN to NaN at depth (issue #2808). Any MoE model in the derived set must get a realistic
tokenization; dense models may use synthetic prompts (no expert-FFN path to overflow). **The
in-tree Mixtral case is not a usable template**: it is `SKIP("TODO(#2808)")`, uses a synthetic
incrementing-id prompt (0..600), samples with `top_p=0.7` (not greedy), runs tp2, and is a
self-comparison (`logits1` vs `logits2`) — **not** an HF-golden gate. A new MoE case must use a
realistic tokenized prompt **and** an HF golden **and** `temperature 0`.

# Token fidelity across context-length boundaries

This is the generic, oracle-agnostic methodology `/retest-categorical` inherits and overrides.
It is a *methodology*, not a claim that any given binary already runs it — whether it gates
depends entirely on what TEST_CASEs a binary registers (see the reporting rule below).
`t_generate_ingest_1` on main registers only a single short prompt per model with no
`[long]`/`[realistic]` tags, so in the generic `/retest` path the boundary lengths below are an
**acknowledged seq-len coverage gap**: report each unrun length as uncovered (`NO-COVERAGE`),
never as a PASS — but on its own that gap does **not** make the run INCOMPLETE; the run's
verdict is driven by the registered case(s) per the Phase-3 gate. The sweep becomes a hard gate
only where a binary registers the boundary cells, and it is **mandatory in
`/retest-categorical`**, where every in-scope `(model, length)` cell must run.

**Boundary set: `{8, 64, 256, 4096, 16384}`.** The KV cache is paginated at
`page::page_size == 64`, so these lengths exercise **1 / 1 / 4 / 64 / 256** page regimes
(8 and 64 each fit in one page; 256 = 4 pages; 4096 = 64 pages; 16384 = 256 pages). The set is
chosen to cross the page boundaries where KV-cache stride, attention-chunking, and
visit-order bugs surface that a single short prompt cannot reach.

**Oracle for the generic `/retest` path = HuggingFace.** At each in-scope length, compare the
pipeline's logits against the HF `transformers` forward pass with the same metrics as the rest
of Phase 3: per-position **top-K inclusion** (`topk_params{k=5, min_overlap≥3}` on the C++
path; `top1_agreement`/`top5_agreement` on the Python path) plus the committed TVD/outlier
caps. There is **no `--strict-top1` flag** here (that is categorical-only) — top-1 is the
top-K-overlap guard plus the agreement metrics. Tolerances are the per-model literals committed
in `t/t_generate_ingest_1.cpp`; do **not** invent new ones, and a longer prompt does not relax
them (a brand-new model has no committed tolerance — choosing one is a reviewed authoring step).

**Decide in-scope BEFORE running a length.** A length `L` is in scope for a model only when
`L ≤` the model's declared `max_position_embeddings` (from its HF `config.json`) **and** within
any documented hard KV-cache/HBM capacity limit for the chosen executor. Resolve this *before*
launching the cell — never discover it from a crash. A length beyond the declared contract is
reported **`OUT-OF-SCOPE`** (`N/A-MAX-POSITION`) with the exact limit; it is neither PASS,
INCOMPLETE, nor DIVERGE, and is never counted toward the gate.

**Source realistic token streams for the long cases.** Inline prompt-id arrays are impractical
past a few hundred tokens, so the 256/4096/16384 cells must load their token stream from a
file/corpus (a file-backed loader, not a hand-written array). Use a real tokenized text so the
distribution is representative, and feed the same stream to the pipeline and the HF oracle so
the comparison is apples-to-apples. The 8- and 64-token cells may use short inline prompts.

**MoE models never use synthetic incrementing-id prompts.** A synthetic incrementing-id prompt
overflows an MoE expert FFN to NaN at depth (issue #2808, SIGABRT `m_star != -inf`). Any MoE
model in the sweep must use a realistic tokenization at every boundary length; dense models may
use a synthetic prompt (no expert-FFN path to overflow).

**Run each `(model, length)` cell in its own process.** One TEST_CASE per process, exactly as
the Phase-3 isolated sweep runner does — Catch2 single-process runs share FPGA state (KV-cache
pages, worker assignment, scratch HBM) across cases, so the boundary cells must not share a
process or they yield non-reproducible verdicts.

**Reporting and gate (per `(model, length)` cell).** Run the sweep wherever a binary actually
registers the boundary cells, and gate divergences there:

- **In-scope, ran, within tolerance vs HF** → `PASS`.
- **In-scope, exceeds tolerance vs HF** → `DIVERGE` (a real correctness regression; a `DIVERGE`
  on a longer case while the short case passes is a real bug, not flake).
- **In-scope, but the environment cannot run a registered cell** (weights missing, timeout,
  unresolved lock contention) → `WEIGHTS-MISSING` / `TIMEOUT` / `LOCK-CONTENTION` →
  **INCOMPLETE** (Phase 0 should have provisioned/pre-warmed).
- **In-scope, but the binary registers no case at this length** → `NO-COVERAGE`. Report it as an
  acknowledged seq-len coverage gap; never claim the boundary was exercised or PASS it. In the
  generic `/retest` path this is the default on main (only the single short prompt is registered)
  and does **not** by itself make the run INCOMPLETE; in `/retest-categorical` the boundary sweep
  is **mandatory**, so an in-scope `NO-COVERAGE` cell there **is** INCOMPLETE.
- **Out-of-scope** (`L` beyond the model's declared support) → `OUT-OF-SCOPE` (`N/A`), reported
  with the limit, never counted as PASS.

# Phase 4 — Code review — skip if `--no-review`

Compute touched languages from `CHANGED`, then invoke `/deep-review` scoped to the branch
diff and let it route by the languages the branch actually changed:

```
/deep-review <merge-base>..HEAD     # or the PR number / stack
```

Routing (do **not** spawn reviewers for untouched languages):

| Changed paths | reviewer |
|---|---|
| `ingest/**/*.hs`, `*.lhs` | haskell-reviewer |
| `src/`/`h/`/`t/` `*.cpp`/`*.hpp`/`*.h`/`*.cc` | cpp-reviewer |
| `ingest/**/*.py` | python-reviewer |
| `rust/**/*.rs` | rust-reviewer |
| `*.nix` | nix-reviewer |
| `bin/ci/*.sh` | bash-reviewer |

`deep-review` automatically adds `security-reviewer` + `perf-reviewer` and synthesizes one
severity-sorted report (dedup, drop confidence <80).

Any fix made during review must pass `make format` + `make lint` (lint enforces
version-pinning; run `make format-haskell` / `-python` / `-rust` / `-shell` as the touched
languages require). Note: `bin/lint-notes` does **not** scan `ingest/**/*.hs`, so dangling
`See Note [...]` refs in Haskell won't be caught by `make lint` — have
haskell-reviewer/comment-audit check those explicitly.

# Phase 5 — Comment-check — skip if `--no-comments`

Invoke `comment-audit` scoped to the diff:

```
Skill(comment-audit, "audit comments in this branch's changes vs main
  (use --diff-base $(git merge-base HEAD main)); report STALE/INCORRECT/ORPHANED
  findings; do not auto-edit NEEDS_REVIEW or medium/low-confidence findings")
```

It records which comments fall inside the diff (in-diff first) and also greps the repo for
changed symbols' remote comments (stale-elsewhere catch). Verdicts: `VALID` / `STALE` /
`INCORRECT` / `MISLEADING` / `ORPHANED` / `UNVERIFIABLE` / `NEEDS_REVIEW`; complete only when
`stats` reports zero pending.

# Phase 6 — Performance + decode-token parity — skip if `--no-perf`

Generate through the pipeline under test on the derived executor; report perf, and (under
`--temperature 0`) whether the decoded token sequence is stable.

**Phase 3 ≠ Phase 6 codepath.** Phase 3 is the in-process C++ gate
(`force_generate` → `check_golden_logits`) — prompt + a few forced steps. Phase 6 is the
external `runtron stream-generate-text --length N` — full decode loop, KV-cache, sampling. A
decode-only divergence with a clean Phase 3 is a decode-loop / runtron-host issue, **not** the
emitter.

**TOKID triage:** (1) Phase-3 PASS + Phase-6 TOKID DIFF on GPT-OSS tp4 → advisory (documented
multi-token-decode nondeterminism); run 3×, both/all runs must pass. (2) same on any other
model → not an emitter bug (Phase 3 already proved the prompt path correct vs HF); root-cause
the decode path separately. (3) a Phase-3 DIFF is the real bug; Phase 3 is the gate.

Fixed methodology (don't vary, or numbers aren't comparable):
- Slug + executor from the derived set; confirm in `config/models.yaml`.
- `SYSTEM_CONFIG="--instance 0,1"` for every launch (whole machine; `--instance 0,4` starves
  large-tp4 decode KV cache → DEBUG EXIT).
- 64-token prompt, 32-token greedy decode, `--temperature 0 --pay-for-determinism --seed 42`
  (confirm flags with `runtron --help`; don't invent flags).
- 3 trials, report the **median**. Cold cache: before each trial try
  `sudo -n bash -c 'sync; echo 3 > /proc/sys/vm/drop_caches'`; if passwordless sudo is
  unavailable, skip it, compare gen-time/tok-s only, and label wall **NON-COMPARABLE** (warm
  cache once produced a fake −18% wall "win" on 120B).
- Metrics per model: Δ gen-time (ms/tok), Δ tok/s, Δ wall vs the run's baseline / prior
  committed baseline, and whether the 32 token-IDs are stable. **Flag >5% median
  gen-time/tok regression.**
- **Token-ID extraction:** diff the `Logits of token N` lines from `--log-intermediates`
  pairwise, not ANSI green-text spans (fragile across runtron versions).

# Final report

One consolidated summary, using the verdict taxonomy verbatim (do not collapse SKIPPED /
QUARANTINED / NO-COVERAGE into PASS):
- **Derived model set:** the runtime slugs computed from the diff (or `--all` / explicit
  override). If empty/unrunnable, say so and mark INCOMPLETE.
- **Build / Unit tests:** build flavor used; Haskell N/N; C++ host pass/fail; `test-ingest`.
- **Phase 0:** per model — weights canonical/scratch/DOWNLOAD-FAILED; cache pre-warmed y/n.
- **Phase 3:** per `(model, prompt)` — verdict (incl. NO-COVERAGE) + executor + runtime +
  oracle + tolerance bound.
- **Phase 4:** review findings count by severity.
- **Phase 5:** comment verdicts.
- **Phase 6:** per model Δ gen-time/tok-s/wall + TOKID.
- **Overall verdict:**
  - **`HF-CORRECT`** — all measured rows PASS/QUARANTINED-PASS vs HF, no DIVERGE, no
    NO-COVERAGE, no >5% regression, review/comments clean (quote the oracle + codepath +
    prompt-set + tolerance bound).
  - **`INCOMPLETE`** — any NO-COVERAGE/SKIPPED/WEIGHTS-MISSING/TIMEOUT, or an empty/unrunnable
    derived set.
  - **`REGRESSION`** — any HF DIVERGE, any >5% slowdown, or any blocking review finding.

Root-cause anything that genuinely diverged or regressed at file:line level — don't paper over
it, and don't silence a real DIVERGE as "flaky" (quarantine with an issue link + removal
condition, or fix it).
