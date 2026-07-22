> **Branch precondition.** This command targets the **categorical ingest pipeline**, which
> lives on the `categorical-semantics-layer` branch (or a branch that has merged it). On
> `main` it does **not** apply: `make build-categorical` is not a make target,
> `t/t_generate_categorical_fpga_real.cpp`, `bin/ci/categorical_logit_matrix.sh`,
> `categorical_logit_test.py`, the `--strict-top1` flag, and the `categorical-*` slugs are all
> absent. On `main`, use **`/retest`** (the HF-oracle general battery) instead. Every
> target/binary/flag below is named relative to the categorical branch; `/retest` line
> "`make build-categorical` is not a target in main" is correct *for main* and not in conflict
> once this precondition is honored. Phase 1 should assert the target exists and abort with
> this message otherwise (e.g. `make -n build-categorical >/dev/null 2>&1 || { echo "not on
> the categorical branch — use /retest"; exit 2; }`).

Confirm the categorical ingest pipeline is still a byte-for-byte drop-in for the legacy
ingest path with no performance regression. Work the phases in order, tracking each with
your task tool. **Do not stop at the first failure** — finish the sweep and emit one
consolidated result table at the end.

# This is the categorical specialization of `/retest`

`/retest-categorical` is the **categorical specialization** of `/retest`. Run the shared grunt-work
via `/retest` (it owns the general operating rules, the generic Known-traps, the
weights-provisioning machinery, the three unit-test layers, the isolated one-TEST_CASE
runner, the generic perf methodology, and the review/comment phases), then apply the
categorical overrides below. This is a **documentation-style delegation** — there is no
machine handoff or argument forwarding; read both docs and apply the overrides by hand
(the `/retest` doc is the `retest` command prompt deployed alongside this one, e.g.
`retest.md` in the same commands directory).
**Where `/retest` and this doc conflict, this doc wins for categorical runs.**

| `/retest` general | `/retest-categorical` categorical override |
|---|---|
| Source of truth = HF transformers forward pass (TVD/top-K/decoded-tokens) | **Legacy ingest path; bit-exact last-prompt-token logits** (`require_byte_identical`, 100%) |
| Token-fidelity boundary sweep `{8,64,256,4096,16384}` (methodology in the `/retest` *Token fidelity across context-length boundaries* section) gated vs HF top-K inclusion | **Same boundary set + base methodology, but gated vs legacy byte-identity** — no top-K slack; every *in-scope* `(model, length)` cell must be bit-exact through the page boundaries (out-of-scope lengths reported `N/A`) |
| Comparison binary chosen per derived set | **`gen/t_generate_categorical_fpga_real`** |
| Build = `make build` / `build-test` / `build-ingest` per diff | **`make build-categorical -j 4`** (regenerates categorical + legacy plugins; categorical-branch target only) |
| Model set derived from branch diff | **Fixed eight-model Phase-0 table** (Phase 0 below) |
| Phase-3 sweep filter generic | **`awk '/^  Categorical/'` + the fixed eight-model default `FILTERS`** |
| Phase 4 = code review | **Phase 4 = `bin/ci/categorical_logit_matrix.sh`** semantic gate (`--strict-top1` vs HF, MoE excluded) |
| Slugs from registry | **`categorical-$MODEL[-standalone][-tpN]` / `ingested-$MODEL[-tpN]`** pairing |
| Overall verdict `HF-CORRECT` | **`BYTE-EXACT DROP-IN`** |

The two docs deliberately differ in two places that bite an operator who read one and acts in
the other:

- **Phase numbering is off by one for perf.** In `/retest`, code review is Phase 4 and
  perf is Phase 6. Here, Phase 4 is the categorical semantic gate and **Phase 5 is perf** —
  so when this doc says "use the `/retest` Phase-6 perf methodology," that maps onto
  **this doc's Phase 5**. And "Phase 4" means code-review in `/retest` but the semantic
  logit matrix here.
- **`--no-semantic` means different things.** In `/retest` it skips only a *sub-check
  inside Phase 3* (the Python equivalence run). Here it skips **all of Phase 4** (the entire
  categorical semantic matrix). They gate structurally different work; do not treat them as
  the same flag.

**Scope contrast with `/retest` (the reason this is a separate command).** `/retest` narrows
the token-fidelity gate to the *single* model its PR stack is advancing. This command does the
opposite **on purpose**: the categorical pipeline must be a byte-exact drop-in for the legacy
path on **every** supported model, so Phase 3 sweeps the **full categorical roster** — the
fixed eight-model Phase-0 table, which is every model `t_generate_categorical_fpga_real`
compiles in — with **no** branch-diff narrowing. A tag filter only *subsets* that roster for a
quick local run; the ship gate is always all supported models. (Keep the roster aligned with
the `ModelDef` table in `t/t_generate_categorical_fpga_real.cpp`.)

# Arguments (`$ARGUMENTS`)

- Bare model tags (e.g. `[phi-4] [mixtral-8x7b]`) → restrict Phases 3 & 5 to those models;
  no tags → all eight. Set `MODELS` once and feed it to both phases. **Phase 4 (the semantic
  logit matrix) is NOT narrowed by a tag filter** — it always runs the full non-MoE matrix
  regardless of which tags you pass.
- `--no-perf` → skip Phase 5. `--no-semantic` → skip Phase 4 (the whole categorical semantic
  matrix; see the note above on how this differs from `/retest`'s `--no-semantic`).

# Operating rules

Use the `/retest` **Operating rules** verbatim (Nix shell wrapper, `-j 4` max, executor
selection, the `/opt/positron/weights/...` read-only / `/tmp/retest_weights/<repo>` scratch
fallback — for categorical runs substitute this doc's own scratch root,
`/tmp/retest-categorical_weights/<repo>`, as Phase 0 does — one-TEST_CASE-per-process for FPGA,
background long jobs, the distinct `PASS / SKIPPED / QUARANTINED / DIVERGE` states). To those
this doc adds its own hardware rule — **this host HAS FPGA cards; run the FPGA tests here
every time**: the Phase-3 byte-exact parity gate and Phase-5
decode run on the FPGA cards present on this machine (`ls /dev/vfio/` populated ⇒ present;
`pgrep -af 'runtron\|t_generate'` ⇒ free). Never call this a "host-only environment" or defer
the FPGA gate for lack of hardware — a skipped FPGA gate is `INCOMPLETE`, never `PASS`. With
these, plus two categorical specializations:

- **The Phase-3 runner enforces one-TEST_CASE-per-process** (the sweep runner below).
- **Claim discipline (categorical example).** Bind every "byte-identical" statement to its
  oracle and code path: "last-prompt-token logits, C++ `generate(max_steps=0)`,
  4/32/64-token prompts, per-process isolated."

`ls /dev/vfio/` does not prove the cards are free — check `pgrep -af 'runtron\|t_generate'`.

# Known traps

Use the `/retest` **Known traps** for the generic rows (fetcher-cache, stale CMake
graph, wrong-weights-dir, multi-case-vs-solo, HBM instance overflow, stale-HBM operator
reset, the #2808 MoE-synthetic-prompt SIGABRT). Two categorical-specific traps (categorical
branch only — these paths/targets do not exist on main):

| Symptom | Cause → fix |
|---|---|
| `ninja: error: '…' missing and no known rule` (deleted source) | stale CMake graph → `rm -f gen/config/categorical`, rebuild |
| plugin output looks stale after a rebase/restack | `make build-categorical` missed a Haskell change → `rm -f gen/src/tron/h/tron/plugins/{categorical,ingested}_$MODEL.hpp && make build-categorical -j 4`; confirm mtime is post-rebase |

# Phase 0 — Provision weights + pre-warm cache (mandatory)

Use the `/retest` Phase-0 machinery (the `WEIGHTS_ROOT`/`SCRATCH_ROOT`/`CACHE_ROOT`
fallback, `bin/get_model REPO --to DIR`, the pre-warm loop, the ≥30-min Phase-3 timeout note)
but with the **fixed eight-model categorical roster**, not a branch-derived set:

```bash
nix develop --command bash -c '
set -uo pipefail
WEIGHTS_ROOT=/opt/positron/weights/huggingface
SCRATCH_ROOT=/tmp/retest-categorical_weights
CACHE_ROOT=/opt/positron/weights_cache/cached
# (huggingface-repo, default-tp-slug) — keep aligned with the ModelDef table in
# t/t_generate_categorical_fpga_real.cpp.
MODELS=(
  "shuyuej/Llama-3.2-1B-Instruct-GPTQ            ingested-llama-3.2-1b"
  "thesven/Meta-Llama-3.1-8B-Instruct-GPTQ       ingested-llama-3.1-8b"
  "microsoft/phi-4                               ingested-phi-4"
  "hfl/chinese-alpaca-2-7b                       ingested-chinese-alpaca-2-7b"
  "mistralai/Mixtral-8x7B-Instruct-v0.1          ingested-mixtral-8x7b-instruct-v0.1-tp4"
  "positron-ai/openai--gpt-oss-20b-ingest-best-gptq  ingested-gpt-oss-20b-tp4"
  "positron-ai/openai--gpt-oss-120b-ingest-best-gptq ingested-gpt-oss-120b-tp4"
  "Qwen/Qwen2.5-32B-Instruct-GPTQ-Int4           ingested-qwen-2.5-32b-tp4"
)
for entry in "${MODELS[@]}"; do
  repo="${entry%% *}"
  if   ls "$WEIGHTS_ROOT/$repo"/*.safetensors >/dev/null 2>&1; then echo "  have (canonical): $repo"
  elif ls "$SCRATCH_ROOT/$repo"/*.safetensors >/dev/null 2>&1; then echo "  have (scratch):   $repo"
  else echo "  downloading: $repo"; python3 bin/get_model "$repo" --to "$SCRATCH_ROOT/$repo" \
         || echo "    DOWNLOAD-FAILED $repo (private/positron-internal repos must be pre-populated by ops)"; fi
done
printf "x\n" > /tmp/retest-categorical_warmup_prompt.txt
for entry in "${MODELS[@]}"; do
  slug="${entry##* }"
  find "$CACHE_ROOT" -maxdepth 3 -type d -name "$(basename "${entry%% *}")" -print -quit 2>/dev/null | grep -q . \
    && { echo "  warm: $slug"; continue; }
  echo "  prewarming: $slug"
  SYSTEM_CONFIG="--instance 0,1" timeout 600 gen/runtron stream-generate-text \
    --model "$slug" -f /tmp/retest-categorical_warmup_prompt.txt \
    --prompt-length 4 --length 1 --temperature 0 --pay-for-determinism --seed 42 \
    >/dev/null 2>&1 || echo "    PREWARM-FAILED: $slug (Phase 3 will be slow)"
done
'
```

`bin/get_model REPO --to DIR` runs HF `snapshot_download` and converts `.bin`→`.safetensors`;
**always pass `--to`** (without it, it defaults to the read-only canonical root). If pre-warm
is skipped, keep the Phase-3 timeout ≥30 min or cold-cache first runs read as TIMEOUT.

# Phase 1 — Rebuild

```
nix develop --command bash -c 'make build-categorical -j 4'
```
Regenerates every categorical + legacy plugin and `gen/t_generate_categorical_fpga_real`.
**Categorical-branch target only** — on main this target does not exist (see the branch
precondition at the top). Assert it before building:
```
nix develop --command bash -c 'make -n build-categorical >/dev/null 2>&1' \
  || { echo "make build-categorical absent — not on the categorical branch; use /retest"; exit 2; }
```
Require exit 0 and zero `error:` lines. If `gen/` is corrupt from a prior non-Nix `make`,
`rm -rf gen` and rebuild. (Stale-graph and stale-plugin recovery: see Known traps.)

# Phase 2 — Unit tests

```
nix develop --command bash -c 'bin/ingest-cabal build && bin/ingest-cabal test'   # Haskell ingest
nix develop --command bash -c 'make build-test -j 4 && make test-host'             # C++ Catch2 host
```
All must pass, including the typed-pipeline byte-identity MD5 baselines. Never weaken or skip
a failing test — fix the root cause. If a baseline digest legitimately changed because emitter
output changed, update it deliberately and say why. (See `/retest` Phase 2 for the
shared discipline; the categorical run does not need the FPGA `make test-ingest` layer.)

# Phase 3 — FPGA byte-exact parity (headline gate)

`gen/t_generate_categorical_fpga_real` runs each categorical plugin and its legacy-ingest
counterpart on identical weights/prompt/seed/executor with `pay_for_determinism=true`, via the
in-process C++ API `generate(model, prompt, max_steps=0, …)` with `LogitsMode::LAST`, asserting
**bit-exact last-prompt-token logits**. (Generated-token parity over a full decode is Phase 5.)
The oracle is the **legacy ingest pipeline**, not HuggingFace — this is where `/retest-categorical`
diverges from `/retest`, whose Phase 3 gates against HF.

Model → executor: `[llama-3.2-1b]` tp1·16L, `[llama-3.1-8b]` tp1·32L, `[phi-4]` tp1·40L,
`[chinese-alpaca-2-7b]` tp1·32L, `[mixtral-8x7b]` tp4·32L, `[gpt-oss-20b]` tp4·24L,
`[gpt-oss-120b]` tp4·36L, `[qwen-2.5-32b]` tp4·64L.

Each model has a 4-token oracle plus `[long]` 32/64-token cases (and, for Llama-3, `[realistic]`
real-text cases). The `[long]` cases catch seq-len-dependent emitter bugs (KV-cache stride,
attention chunking, visit-order) the 4-token oracle misses. **A `[long]` DIVERGE on a model whose
4-token case passes is a real bug** — do not excuse it. (These tags exist in
`t_generate_categorical_fpga_real` on the categorical branch; they do **not** exist in main's
`t_generate_ingest_1`, which is why `/retest` does not gate on `[long]`.)

**Token fidelity across context-length boundaries.** Apply the `/retest`
**Token fidelity across context-length boundaries** section — it owns the boundary set
**{8, 64, 256, 4096, 16384}**, the page-regime rationale (the KV cache is paginated at
`page::page_size == 64`, so these lengths span 1 / 1 / 4 / 64 / 256 pages), the in-scope
pre-check (`max_position_embeddings` + documented hard KV-cache/HBM capacity), the file-backed
realistic-stream sourcing for the 256/4096/16384 cells, the MoE NaN-#2808 rule, and the
one-process-per-cell isolation. Apply that section, then take **only** the categorical override
below. The **oracle differs**: where `/retest` checks per-position top-K inclusion vs
HuggingFace, the categorical run keeps this command's oracle — **bit-exact categorical-vs-legacy
parity at every position** (`require_byte_identical`), legacy ingest being the source of truth,
not HuggingFace. Byte-identity is drift-free, so there is no top-K slack: at each in-scope length
the categorical and legacy pipelines must agree exactly, and the gate is `first divergence at
position …` never firing through the page boundaries.

Reachability is judged **against the model's declared contract**, and the two cases are kept
distinct:

- A length `L` is **in-scope** when `L ≤ max_position_embeddings` and within the executor's
  documented hard KV-cache/HBM capacity. Decide this **before** running the cell — never
  discover it from a crash. Every in-scope cell must run **both** pipelines and agree byte-exact.
- A length beyond that declared support is **`OUT-OF-SCOPE`** (`N/A-MAX-POSITION`): report it
  with the exact reason and limit. It is **not** PASS, **not** INCOMPLETE, **not** REGRESSION.
- An **in-scope** length that only one pipeline (categorical XOR legacy) can execute is a
  **`REACHABILITY-REGRESSION`** — a categorical drop-in failure, counted as `REGRESSION`, never
  excused as merely incomplete.

Inline prompt-id arrays are impractical past a few hundred tokens, so the 256/4096/16384 cases
must load their realistic token stream from a file/corpus (extend
`kMixtralReal*`/`kGptOssReal*`-style constants with a file-backed loader rather than a
hand-written array; the binary must register a boundary case per enumerated length so the runner
can select it one process at a time). Report a per-`(model, length)` row with the verdict, the
pages crossed, and (for an out-of-scope cell) the model limit that excluded it.

**Isolated sweep runner — one TEST_CASE per process** (each model's oracle, its
`[long]`/`[realistic]` cases, **and each boundary-length cell** run in their own processes). The
runner **enumerates the full boundary matrix {8, 64, 256, 4096, 16384} directly** — it does
*not* rely solely on whatever `[long]`/`[realistic]` tags happen to exist. For each model it
decides each length's scope first (`max_position_embeddings` + documented hard capacity; see the
`/retest` base section), skip-launches any out-of-scope length (reported `OUT-OF-SCOPE`), and
runs each in-scope length in its own process; the 256/4096/16384 cells use the file-backed
realistic-token loader, so the binary must register a boundary case per in-scope length. The
oracle case is selected by **tag exclusion** `[model]~[long]`, NOT by a name pulled from
`--list-tests`: Catch2 wraps/truncates the oracle's long `"(full N layers, real …)"` name in the
listing, so a name extracted from it silently fails to match and the case never runs (a real bug
observed in practice — it showed up as `rc=2` "No tests ran"). The shorter `[long]`/`[realistic]`
names list cleanly, so those run by name. A transient FPGA/hugepages contention
(`Environment setup failed`, `DEBUG EXIT`, lock) is retried up to 3× before being reported, and
`No tests ran` is surfaced as NO-MATCH rather than silently counted as a failure.

```bash
#!/usr/bin/env bash
set -uo pipefail
set -f   # noglob: Catch2 tags are bracket-globs ([phi-4]); unquoted they expand against cwd
         # dirs (h/, t/) and mangle phi-4/chinese-alpaca/mixtral into single-char tags.
BIN=./gen/t_generate_categorical_fpga_real
LOGDIR=/tmp/retest-categorical_fpga_logs; mkdir -p "$LOGDIR"
[ -x "$BIN" ] || { echo "FATAL: $BIN missing — run Phase 1 first (categorical branch only)"; exit 2; }
"$BIN" --list-tests >/dev/null 2>&1 || { echo "FATAL: test binary won't list tests"; exit 2; }
if [ "$#" -gt 0 ]; then FILTERS="$*"; else
  FILTERS="[llama-3.2-1b] [llama-3.1-8b] [phi-4] [chinese-alpaca-2-7b] [mixtral-8x7b] [gpt-oss-20b] [gpt-oss-120b] [qwen-2.5-32b]"
fi
# Build per-process run items. Oracle: tag-exclusion [model]~[long] (the one case
# lacking [long]) — avoids extracting the oracle's long, Catch2-wrapped name.
# [long]/[realistic]: short names list cleanly, so enumerate them by name from
# [model][long]. Each item runs in its own process.
ITEMS=()   # tab-separated "selector<TAB>label"; selector is a tag-expr or exact name
for f in $FILTERS; do
  base="${f%]}"                                # "[llama-3.2-1b]" -> "[llama-3.2-1b"
  ITEMS+=("${f}~[long]"$'\t'"${f}-oracle")     # oracle, by tag exclusion
  while IFS= read -r nm; do
    [ -n "$nm" ] && ITEMS+=("$nm"$'\t'"$nm")   # [long]/[realistic], by (short) name
  done < <("$BIN" --list-tests "${base}][long]" 2>/dev/null | awk '/^  Categorical/ {sub(/^  /,""); print}')
  # Boundary matrix {8,64,256,4096,16384}, one process per (model,length) cell. Enumerate the
  # cells DIRECTLY — do NOT rely solely on [long]/[realistic] tags covering them. Decide scope
  # first: in-scope means L <= the model's max_position_embeddings and within the executor's
  # documented hard KV-cache/HBM capacity (see the /retest base section). 256/4096/16384 use
  # the file-backed realistic-token loader. The binary registers each in-scope boundary case
  # under a per-length tag ([model][len-<L>]); the runner selects it by that tag. A length the
  # binary does not register lists as nothing -> reported NO-COVERAGE (INCOMPLETE); a length
  # above the model's contract is reported OUT-OF-SCOPE (never a PASS); an in-scope length only
  # one pipeline can run is REACHABILITY-REGRESSION (a REGRESSION, not INCOMPLETE).
  for L in 8 64 256 4096 16384; do
    sel="${base}][len-${L}]"
    if "$BIN" --list-tests "$sel" 2>/dev/null | grep -q '^  Categorical'; then
      ITEMS+=("$sel"$'\t'"${f}-len-${L}")            # in-scope boundary cell, by [model][len-L] tag
    else
      ITEMS+=("@uncovered:${L}"$'\t'"${f}-len-${L}") # not registered: report rather than drop
    fi
  done
done
if [ "$#" -gt 0 ] && [ "${#ITEMS[@]}" -eq 0 ]; then
  echo "NO-COVERAGE: filters [$FILTERS] matched zero Categorical TEST_CASEs. INCOMPLETE."; exit 3
fi
declare -A SEEN; UNIQ=()
for it in "${ITEMS[@]}"; do [ -z "${SEEN[$it]:-}" ] && { SEEN[$it]=1; UNIQ+=("$it"); }; done
for it in "${UNIQ[@]}"; do
  sel="${it%%$'\t'*}"; label="${it##*$'\t'}"
  # Synthetic boundary marker: this (model,length) cell is not a registered TEST_CASE.
  # Classify it without launching the binary: above the model's max_position_embeddings ->
  # OUT-OF-SCOPE (reported, never PASS); in-scope but unregistered -> NO-COVERAGE (INCOMPLETE).
  # MAXPOS for the model comes from its config.json max_position_embeddings plus any documented
  # hard KV-cache/HBM cap; is_out_of_scope is the operator hook that applies that limit.
  if [[ "$sel" == @uncovered:* ]]; then
    Lc="${sel#@uncovered:}"
    if is_out_of_scope "$label" "$Lc"; then
      printf '%-70s  %-22s  (0s)\n' "$label" "OUT-OF-SCOPE(>maxpos)"
    else
      printf '%-70s  %-22s  (0s)\n' "$label" "NO-COVERAGE"
    fi
    continue
  fi
  safe=$(printf '%s' "$label" | tr -cd 'a-zA-Z0-9-' | head -c 60)
  v=""
  for attempt in 1 2 3; do   # retry transient FPGA/hugepages contention before reporting
    log="$LOGDIR/${safe}_a${attempt}.log"
    start=$(date +%s); timeout 1800 "$BIN" "$sel" > "$log" 2>&1; rc=$?; dur=$(( $(date +%s) - start ))
    # 30-min timeout: cold-cache 120B first-runs spend ~5min populating weights_cache.
    if   [ $rc -eq 0 ] && grep -q 'SKIPPED' "$log"; then v=SKIPPED
    elif [ $rc -eq 0 ]; then v=PASS
    elif [ $rc -eq 124 ]; then v="TIMEOUT(30m)"
    elif grep -q "first divergence at position" "$log"; then v="DIVERGE: $(grep -oE '[0-9]+/[0-9]+ positions match' "$log" | head -1)"
    elif grep -qiE "only one pipeline|one-sided|reachable by (categorical|legacy) only" "$log"; then v="REACHABILITY-REGRESSION"   # in-scope, single-pipeline reach => REGRESSION
    elif grep -qiE "exceeds max_position_embeddings|over max position|beyond declared context|OUT-OF-SCOPE" "$log"; then v="OUT-OF-SCOPE(>maxpos)"   # L beyond model contract => reported N/A, never a failure
    elif grep -qiE "Environment setup failed|acquire lock|lock after|device busy|EBUSY|DEBUG EXIT|HBM" "$log"; then v="LOCK-CONTENTION"
    elif grep -qiE "No tests ran|No test cases matched" "$log"; then v="NO-MATCH (runner/selector bug — report, do NOT count as pass)"
    elif grep -qiE "Failed to open file|No such file" "$log"; then v="WEIGHTS-MISSING"
    else v="FAIL(rc=$rc)"; fi
    if [ "$v" = "LOCK-CONTENTION" ] && [ "$attempt" -lt 3 ]; then sleep 45; continue; fi
    break
  done
  printf '%-70s  %-22s  (%ds)\n' "$label" "$v" "$dur"
  sleep 15   # let tp4 device locks release between cases
done
```

(The categorical binary asserts bit-exact equality and prints `first divergence at position …`
/ `N/N positions match` on mismatch — hence the DIVERGE regex above. It emits no Catch2
`mayfail` marker, so QUARANTINED-PASS/FAIL do not arise from this binary today; the
QUARANTINED rows below apply only if a `mayfail`-tagged case is later added.)

**Verdict taxonomy** (report these distinctly):

| Verdict | Counts toward the gate? |
|---|---|
| `PASS` / `QUARANTINED-PASS` | yes |
| `DIVERGE` | **NO — real correctness regression** |
| `NO-COVERAGE` | NO — INCOMPLETE; a passed tag matched zero TEST_CASEs |
| `REACHABILITY-REGRESSION` | **NO — REGRESSION** for that `(model, length)` cell; L is *inside* the model's declared support (`L ≤ max_position_embeddings`, within hard KV-cache/HBM capacity) but only one pipeline (categorical XOR legacy) can execute it — a categorical drop-in failure at a supported length, never merely INCOMPLETE |
| `OUT-OF-SCOPE` (`N/A-MAX-POSITION`) | neither PASS nor INCOMPLETE nor REGRESSION; L exceeds the model's declared `max_position_embeddings` or a documented hard KV-cache/HBM capacity limit. Report the cell with the exact reason + limit; it is never counted toward the gate either way |
| `SKIPPED` / `WEIGHTS-MISSING` / `TIMEOUT` | NO — INCOMPLETE (Phase 0 should have provisioned/pre-warmed) |
| `QUARANTINED-FAIL` | does not block ship, but report as a known-flake hit (only if a `mayfail` case exists) |
| `LOCK-CONTENTION` | re-run alone; if it still fails alone, escalate |
| `FAIL(rc=…)` | investigate (SIGABRT/SIGSEGV); not necessarily categorical — see Known traps |

**Gate (built around in-scope cells).** Decide each boundary length's scope first (`L ≤` the
model's declared `max_position_embeddings`, within its documented hard KV-cache/HBM capacity).
Then, for every model:

- Every supported model must `PASS`/`QUARANTINED-PASS` on its 4-token and `[long]` cases **and**
  on every **in-scope** boundary cell in {8, 64, 256, 4096, 16384} — running **both** pipelines
  and passing bit-exact categorical-vs-legacy parity through the page boundaries.
- Any byte `DIVERGE` on an in-scope cell is a **REGRESSION**.
- Any in-scope length only one pipeline can execute is a **REACHABILITY-REGRESSION**, counted as
  **REGRESSION** — not merely incomplete.
- Any `NO-COVERAGE`/`SKIPPED`/`WEIGHTS-MISSING`/`TIMEOUT`/unresolved `LOCK-CONTENTION`/selector
  failure on an in-scope cell makes the run **INCOMPLETE**.
- Any **out-of-scope** length (`L` beyond the model's declared support) is reported
  `OUT-OF-SCOPE` (`N/A-MAX-POSITION`) with the exact limit; it is **never** counted as `PASS`,
  `INCOMPLETE`, or `REGRESSION`.

**MoE models must use realistic prompts.** Synthetic incrementing-id prompts overflow an MoE
expert FFN to NaN at depth (issue #2808). Both MoE families now use realistic tokenizations —
Mixtral via `kMixtralReal32/64`, GPT-OSS via `kGptOssReal32/64`. The dense models (Llama, Phi-4,
Qwen, Chinese-Alpaca) keep the synthetic `kMed/kLongGenericPrompt` (no expert-FFN path to
overflow). Any new MoE model must get a realistic tokenization, never the synthetic prompts.

**Triage notes when a DIVERGE is genuine:**
- **Plain vs Permuted are distinct codepaths.** `categorical-<m>`/`ingested-<m>` are Plain;
  `…-permuted` are Permuted (emit `Load2`+`BackPermute`, gated on `TargetExecutor.isPermuted`
  in `ingest/src/Categorical/HypergraphToLoopy.hs` — `assignPermutedWeightPerms` /
  `buildBackPermuteSites`; the `Plain`/`Permuted` enum is `ingest/src/TargetExecutor.hs:21-23`).
  A fix to one rarely fixes the other — confirm the failing slug's variant from
  `config/models.yaml`.
- **Mixtral byte-identity** requires the legacy shared-RMSNorm fold (`foldSharedRmsNormMul`,
  PR #2810) in the base. A ~1-ULP diff across ~95% of logits → confirm that fold is present
  before treating it as categorical. (`foldSharedRmsNormMul` lands with PR #2810; on a base
  that predates it the symbol is absent, so verify it is in the base first.)
- **GPT-OSS tp4** has run-to-run nondeterminism in *multi-token decode* (not the last-token
  gate); if a GPT-OSS case looks flaky, run it 3× and require every run to pass.

# Phase 4 — Semantic logit parity (host) — skip if `--no-semantic`

```
nix develop --command bash -c 'bin/ci/categorical_logit_matrix.sh'
```
Dumps a categorical `.py` per model and runs `categorical_logit_test.py --strict-top1` against
the HuggingFace reference (allclose + top-1) — the *semantic* gate complementing Phase 3's
*byte-level* gate. `--strict-top1` is a flag of the **categorical** `categorical_logit_test.py`
specifically; it is categorical-pipeline-only and does not exist on the legacy/HF reference
path (which is why `/retest` forbids inventing it — confirm its surface with
`categorical_logit_test.py --help` on the categorical branch). **The matrix excludes all MoE
models** (Mixtral, GPT-OSS), so MoE currently has no ground-truth check — only
categorical-vs-legacy byte-identity, which a bug shared by both pipelines would pass. Extend
with verified MoE coverage to close that gap. **This phase runs the full non-MoE matrix
regardless of any tag filter** passed in `$ARGUMENTS`.

# Phase 5 — Performance + decode-token parity — skip if `--no-perf`

Generate through both plugins on the same executor; report perf, and (under `--temperature 0`)
whether the decoded token sequences match. Use the `/retest` **Phase-6** perf methodology
(the Phase 3 ≠ Phase-5-here codepath distinction, the TOKID taxonomy, `--instance 0,1`, the
deterministic flags, the benchmark hygiene, the 5% threshold, `--log-intermediates`
extraction) — note that `/retest`'s Phase 6 is **this doc's Phase 5**; the categorical
specializations are the dual-slug pairing and the watch-list below.

**Phase 3 ≠ Phase 5 codepath.** Phase 3 is the in-process C++ `generate(max_steps=0)` —
prompt-processing only. Phase 5 is the external `runtron stream-generate-text --length N` —
full decode loop, KV-cache, sampling. A divergence in Phase 5 but **not** Phase 3 is in the
decode-loop/runtron host path, **not** the emitter.

**TOKID taxonomy:** (1) Phase-3 PASS + Phase-5 TOKID DIFF on GPT-OSS tp4 → advisory (documented
multi-token-decode nondeterminism, both pipelines equally). (2) same on any other model → not an
emitter bug (Phase 3 already proved the prompt path identical); root-cause the decode path
separately, don't block `/retest-categorical`. (3) Phase-3 DIFF → real emitter bug; Phase 3 is the gate.

Fixed methodology (don't vary, or numbers aren't comparable):
- Slugs: categorical = `categorical-$MODEL[-standalone][-tpN]`, legacy = `ingested-$MODEL[-tpN]`
  (confirm in `config/models.yaml`); same executor as Phase 3.
- `SYSTEM_CONFIG="--instance 0,1"` for every launch (whole machine; `--instance 0,4` starves
  GPT-OSS-120B's decode KV cache → DEBUG EXIT).
- 64-token prompt, 32-token greedy decode, `--temperature 0 --pay-for-determinism --seed 42`
  (confirm flags with `runtron --help`; don't invent flags).
- 3 trials/side, report the **median**. Cold cache: before each trial try
  `sudo -n bash -c 'sync; echo 3 > /proc/sys/vm/drop_caches'`; if passwordless sudo is
  unavailable, skip it, compare gen-time/tok-s only, and label wall **NON-COMPARABLE** (warm
  cache once produced a fake −18% wall "win" on 120B).
- Metrics per model: Δ gen-time (ms/tok), Δ tok/s, Δ wall vs legacy, and whether the 32
  token-IDs matched. **Flag >5% median gen-time/tok regression.** Watch dense Llama-3.1-8B
  (eq-sat per-token decode regression, wall breaks even); Mixtral has historically been a win.
- **Token-ID extraction:** diff the `Logits of token N` lines from `--log-intermediates`
  pairwise, not ANSI green-text spans (fragile across runtron versions).

# Final report

One consolidated summary, using the verdict taxonomy verbatim (do not collapse SKIPPED /
QUARANTINED / NO-COVERAGE into PASS):
- **Build / Unit tests:** clean? Haskell N/N, C++ host pass/fail.
- **Phase 0:** per model — weights canonical/scratch/DOWNLOAD-FAILED; cache pre-warmed y/n.
- **Phase 3:** per `(model, prompt-length)` — the verdict + executor + runtime, **including the
  boundary sweep over {8, 64, 256, 4096, 16384}** (per-`(model, length)` bit-exact parity, pages
  crossed; each cell one of `PASS` / `DIVERGE` / `REACHABILITY-REGRESSION` /
  `OUT-OF-SCOPE`(`N/A-MAX-POSITION`) / `NO-COVERAGE` / `SKIPPED` / `WEIGHTS-MISSING` / `TIMEOUT`).
  Mark each boundary cell in-scope vs out-of-scope and show the limit for any `OUT-OF-SCOPE` cell.
- **Phase 4:** per model allclose + top-1 (MoE excluded).
- **Phase 5:** per model Δ gen-time/tok-s/wall + TOKID match.
- **Overall verdict** (every status Phase 3 can emit maps to exactly one of these):
  - **`BYTE-EXACT DROP-IN`** — all **in-scope** measured rows `PASS`/`QUARANTINED-PASS`; no
    `DIVERGE`; no `REACHABILITY-REGRESSION`; no missing required coverage; no setup failure; no
    perf regression above the 5% threshold. Quote the oracle + codepath + prompt-set bound.
    Out-of-scope cells reported as `N/A` do not block this verdict.
  - **`INCOMPLETE`** — any in-scope cell with `NO-COVERAGE`/`SKIPPED`/`WEIGHTS-MISSING`/`TIMEOUT`/
    unresolved `LOCK-CONTENTION`/selector (`NO-MATCH`) failure, or any other env-or-harness
    failure that prevents a required verdict.
  - **`REGRESSION`** — any byte `DIVERGE`, any in-scope `REACHABILITY-REGRESSION` (a length
    inside the model's contract that only one pipeline can run), or any perf regression above the
    5% threshold.
  - **`OUT-OF-SCOPE` / `N/A`** — reported per cell for lengths beyond the model's declared
    support; never counted as `PASS`, `INCOMPLETE`, or `REGRESSION`.
  - A **`FAIL(rc=…)`** (SIGABRT/SIGSEGV) is **triaged first** (see Known traps): an env/harness
    cause folds into `INCOMPLETE`; a confirmed categorical fault folds into `REGRESSION`.

Root-cause anything that genuinely diverged or regressed at file:line level — don't paper over
it, and don't silence a real DIVERGE as "flaky" (quarantine with an issue link + removal
condition, or fix it).
