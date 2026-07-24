# Fractal Codex-through-LiteLLM Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a secret-safe LiteLLM route for Pi and Codex, expose Fractal’s operator skills to Pi, and complete one bounded Codex-backed Fractal pilot in a disposable repository.

**Architecture:** Agent Deck owns one Pi operator session; Fractal owns all autonomous worktrees, tmux sessions, and lifecycle state beneath it. A tested Codex wrapper resolves the LiteLLM password at process start and injects only non-secret provider overrides, while Pi uses its native request-time `!command` credential resolver. Fractal continues to use its built-in Codex backend and retains local cost estimates by stripping the model alias prefix during pricing lookup.

**Tech Stack:** Home Manager and Nix, Bash, Python standard library, Pi 0.81.1, Codex CLI 0.144.6, Fractal 1.0.0, LiteLLM Responses API, Git, tmux.

## Global Constraints

- The LiteLLM base URL is `https://litellm.vulcan.lan/v1`.
- The routed model identifier is `positron_openai/gpt-5.6-sol`.
- The LiteLLM credential comes from the first line of `pass litellm.vulcan.lan`.
- No resolved credential may enter stdout, stderr, argv, Git, the Nix store, generated configuration, logs, or diagnostics.
- The Pi model sets `contextWindow` to `1050000` and `maxTokens` to `128000` exactly.
- Agent Deck owns only the Pi operator session; Fractal alone owns child worktrees and tmux sessions.
- The first pilot uses no descendants, no radio sync, no remote push, at most two iterations, a USD 10 run cap, a USD 5 iteration cap, a 45-minute run timeout, and a 10-minute step timeout.
- A native Pi Fractal backend is outside this plan and remains gated on a second one-child pilot.
- Do not commit or push the Nix repository unless separately requested.

---

### Task 1: Add a secret-safe Codex LiteLLM wrapper

**Files:**
- Create: `bin/codex-litellm`
- Create: `bin/codex-litellm-test.py`
- Modify: `flake.nix:linting check`

**Interfaces:**
- Consumes: `pass`, a profile-provided real `codex` executable, and ordinary Codex CLI arguments.
- Produces: `bin/codex-litellm`, installed later as `~/.local/bin/codex`; the child receives `LITELLM_API_KEY` in its environment and LiteLLM provider defaults in non-secret `-c` arguments.

- [ ] **Step 1: Write the failing wrapper tests**

Create `bin/codex-litellm-test.py` with tests that install synthetic `pass` and `codex` executables into a temporary directory. The fake password command emits `synthetic-litellm-secret`; the fake Codex command records argv and the environment in mode-0600 files. Assert that:

```python
assert result.returncode == 0
assert captured_env == "synthetic-litellm-secret"
assert "synthetic-litellm-secret" not in captured_argv
assert "synthetic-litellm-secret" not in result.stdout
assert "synthetic-litellm-secret" not in result.stderr
assert 'model="positron_openai/gpt-5.6-sol"' in captured_argv
assert 'model_provider="litellm"' in captured_argv
assert 'model_providers.litellm.base_url="https://litellm.vulcan.lan/v1"' in captured_argv
assert 'model_providers.litellm.env_key="LITELLM_API_KEY"' in captured_argv
assert 'model_providers.litellm.wire_api="responses"' in captured_argv
assert 'shell_environment_policy.filters.LITELLM_API_KEY="exclude"' in captured_argv
assert 'shell_environment_policy.set.LITELLM_API_KEY=""' in captured_argv
assert captured_argv.index("exec") < captured_argv.index('model_provider="litellm"')
assert "-m" not in captured_argv
```

Add a second test whose fake password command emits no first line. Assert a non-zero exit, a redacted error, and that fake Codex was not invoked.

- [ ] **Step 2: Run the tests and verify the missing-wrapper failure**

Run:

```bash
python3 bin/codex-litellm-test.py
```

Expected: failure because `bin/codex-litellm` does not exist.

- [ ] **Step 3: Implement the minimum wrapper**

Create executable `bin/codex-litellm`:

```bash
#!/usr/bin/env bash
set -euo pipefail
set +x

user=${USER:-$(id -un)}
pass_bin=${CODEX_LITELLM_PASS_BIN:-/etc/profiles/per-user/${user}/bin/pass}
codex_bin=${CODEX_LITELLM_REAL_CODEX:-/etc/profiles/per-user/${user}/bin/codex}

if [[ ! -x $pass_bin ]]; then
    echo "codex: LiteLLM credential helper is unavailable" >&2
    exit 1
fi
if [[ ! -x $codex_bin ]]; then
    echo "codex: underlying Codex executable is unavailable" >&2
    exit 1
fi

credential=""
if ! credential=$("$pass_bin" litellm.vulcan.lan); then
    echo "codex: LiteLLM credential is unavailable or empty" >&2
    exit 1
fi
LITELLM_API_KEY=${credential%%$'\n'*}
unset credential
if [[ -z $LITELLM_API_KEY ]]; then
    echo "codex: LiteLLM credential is unavailable or empty" >&2
    exit 1
fi
export LITELLM_API_KEY

routed_model=positron_openai/gpt-5.6-sol
forward_args=()
while (($#)); do
    if [[ $1 == -- ]]; then
        forward_args+=("$@")
        break
    fi
    if [[ ($1 == -m || $1 == --model) && $# -ge 2 && $2 == "$routed_model" ]]; then
        shift 2
        continue
    fi
    if [[ $1 == "--model=$routed_model" ]]; then
        shift
        continue
    fi
    forward_args+=("$1")
    shift
done

litellm_args=(
    -c 'model="positron_openai/gpt-5.6-sol"'
    -c 'model_provider="litellm"'
    -c 'model_providers.litellm.name="LiteLLM (Vulcan)"'
    -c 'model_providers.litellm.base_url="https://litellm.vulcan.lan/v1"'
    -c 'model_providers.litellm.env_key="LITELLM_API_KEY"'
    -c 'model_providers.litellm.wire_api="responses"'
    -c 'shell_environment_policy.filters.LITELLM_API_KEY="exclude"'
    -c 'shell_environment_policy.set.LITELLM_API_KEY=""'
)

if [[ ${forward_args[0]:-} == exec ]]; then
    exec "$codex_bin" exec "${litellm_args[@]}" "${forward_args[@]:1}"
fi
exec "$codex_bin" "${litellm_args[@]}" "${forward_args[@]}"
```

The test-only environment overrides name executables, never credentials.

- [ ] **Step 4: Run focused wrapper verification**

Run:

```bash
python3 bin/codex-litellm-test.py
shellcheck --severity=warning bin/codex-litellm
shfmt -i 4 -d bin/codex-litellm
ruff check bin/codex-litellm-test.py
```

Expected: all commands pass with no output other than the test summary.

- [ ] **Step 5: Add the test to the flake linting check**

Extend `flake.nix` so the Ruff invocation includes `bin/codex-litellm-test.py`, then run:

```bash
nixfmt flake.nix
nix build .#checks.aarch64-darwin.linting --no-link
```

Expected: the check runs `python3 ${src}/bin/codex-litellm-test.py` and succeeds.

### Task 2: Declare Pi’s LiteLLM model and Fractal operator skills

**Files:**
- Create: `config/fractal.nix`
- Modify: `config/johnw.nix:imports`
- Modify: `flake.lock` (advance only `ai-nix` to the Fractal-packaging revision)

**Interfaces:**
- Consumes: `pkgs.pass`, `pkgs.coreutils`, `pkgs.plasma-fractal`, `pkgs.plasma-wiki`, and `bin/codex-litellm`.
- Produces: `~/.local/bin/codex`, `~/.agents/skills/{fractal,wiki}`, and `~/.pi/agent/models.json` through the Darwin `~/.pi -> ~/.config/pi` link.

- [ ] **Step 1: Write an evaluation assertion before the module exists**

Run an evaluation that expects the new Pi model source:

```bash
nix eval --json '.#darwinConfigurations.hera.config.home-manager.users.johnw.xdg.configFile."pi/agent/models.json".source'
```

Expected: evaluation fails because the file declaration does not exist.

- [ ] **Step 2: Create the focused Home Manager module**

Create `config/fractal.nix`. Gate the declarations to `hostname == "hera"`. Generate JSON with `pkgs.formats.json {}` and this provider shape:

```nix
providers.litellm = {
  baseUrl = "https://litellm.vulcan.lan/v1";
  api = "openai-responses";
  apiKey = "!${pkgs.pass}/bin/pass litellm.vulcan.lan | ${pkgs.coreutils}/bin/head -n 1";
  authHeader = true;
  models = [
    {
      id = "positron_openai/gpt-5.6-sol";
      name = "GPT-5.6 Sol (LiteLLM Vulcan)";
      reasoning = true;
      thinkingLevelMap = {
        off = "none";
        minimal = null;
        xhigh = "xhigh";
        max = null;
      };
      input = [ "text" "image" ];
      contextWindow = 1050000;
      maxTokens = 128000;
      cost = {
        input = 5;
        output = 30;
        cacheRead = 0.5;
        cacheWrite = 6.25;
        tiers = [
          {
            inputTokensAbove = 272000;
            input = 10;
            output = 45;
            cacheRead = 1;
            cacheWrite = 12.5;
          }
        ];
      };
    }
  ];
};
```

Install `../bin/codex-litellm` as `.local/bin/codex`. Link the operator skill trees from the stable package exports:

```nix
"${pkgs.plasma-fractal}/share/skills/fractal"
"${pkgs.plasma-wiki}/share/skills/wiki"
```

Advance only the `ai-nix` lock input to revision `edae388`, whose change set adds the two Plasma packages and their smoke checks.

- [ ] **Step 3: Import the module**

Add `./fractal.nix` to the shared imports in `config/johnw.nix`.

- [ ] **Step 4: Format and evaluate exact generated values**

Run:

```bash
nixfmt config/fractal.nix config/johnw.nix
nix eval --raw '.#darwinConfigurations.hera.config.home-manager.users.johnw.xdg.configFile."pi/agent/models.json".source'
```

Read the resulting JSON with Python and assert:

```python
assert model["id"] == "positron_openai/gpt-5.6-sol"
assert model["contextWindow"] == 1050000
assert model["maxTokens"] == 128000
assert provider["baseUrl"] == "https://litellm.vulcan.lan/v1"
assert "apiKey" in provider and "pass" in provider["apiKey"]
```

Do not execute or print `provider["apiKey"]` beyond confirming that it is a command reference.

- [ ] **Step 5: Run repository checks and the system build**

Run:

```bash
nix flake check --no-warn-dirty
./build system
```

Expected: formatting, linting, Home Manager checks, and the Hera system build succeed.

### Task 3: Activate and smoke-test the LiteLLM routes

**Files:**
- Modify at deployment only: `~/.pi/agent/settings.json`
- Replace through Home Manager activation: `~/.pi/agent/models.json`

**Interfaces:**
- Consumes: the built Home Manager generation and the existing mutable Pi settings document.
- Produces: Pi default provider `litellm`, default model `positron_openai/gpt-5.6-sol`, and a working global Codex wrapper.

- [ ] **Step 1: Preserve the current Pi model file before first ownership transfer**

Move the existing regular `models.json` to a mode-0600 dated backup only after the system build passes. Do not copy any resolved credential; the existing file contains configuration only.

- [ ] **Step 2: Activate the Home Manager generation**

Run the repository’s normal switch command after the successful build. Confirm that `~/.local/bin/codex`, `~/.agents/skills/fractal`, `~/.agents/skills/wiki`, and `~/.pi/agent/models.json` resolve to Home Manager-managed store paths.

- [ ] **Step 3: Change only Pi’s mutable default selection**

Use a mode-preserving atomic JSON rewrite to set:

```json
{
  "defaultProvider": "litellm",
  "defaultModel": "positron_openai/gpt-5.6-sol"
}
```

Preserve every unrelated key in `settings.json`.

- [ ] **Step 4: Verify Pi metadata without a model request**

Run:

```bash
pi --list-models 'litellm/positron_openai/gpt-5.6-sol'
```

Expected: one model with context approximately `1.1M`, maximum output `128K`, thinking enabled, and images enabled.

- [ ] **Step 5: Run a bounded Pi request through LiteLLM**

Run Pi with no tools and minimal thinking, asking for the exact text `OK`. Assert that the response is exactly `OK`; do not print request headers or credential-resolution output.

- [ ] **Step 6: Run a bounded Codex request through the wrapper**

Run `codex exec --json` in a temporary Git repository with read-only sandboxing and a prompt requesting exactly `OK`. Parse the JSON stream and assert successful completion with model traffic visible in LiteLLM’s accounting. Do not inspect or print the credential environment.

### Task 4: Run the disposable Fractal pilot

**Files:**
- Create outside this repository: `~/src/fractal-pilot/`
- Fractal-created: `~/src/fractal-pilot/wiki/`, `.fractal/`, and `.worktrees/main.linecount/`

**Interfaces:**
- Consumes: the LiteLLM-routed Codex wrapper, Fractal CLI, wiki CLI, Git, and tmux.
- Produces: one completed and merged `linecount` node plus Fractal and LiteLLM cost records.

- [ ] **Step 1: Create the baseline repository**

Create `~/src/fractal-pilot` only if that path is absent. Initialize branch `main`, write a one-line README identifying the disposable pilot, and make the initial Git commit.

- [ ] **Step 2: Create the Agent Deck Pi operator session**

Run:

```bash
agent-deck add -c pi -t "fractal-pilot-operator" ~/src/fractal-pilot
```

Do not pass a worktree option. Confirm that Agent Deck records only this operator session.

- [ ] **Step 3: Initialize Fractal and commit its baseline**

Run from the repository root:

```bash
fractal init --agent=codex
fractal commit "add Fractal pilot baseline" --init
```

- [ ] **Step 4: Initialize the bounded node**

Run:

```bash
fractal node init linecount \
  --title="Build text counting CLI" \
  --agent=codex \
  --model=positron_openai/gpt-5.6-sol \
  --effort=medium \
  --max-iters=2 \
  --max-depth=0 \
  --max-descendants=0 \
  --timeout=45m \
  --iter-timeout=30m \
  --step-timeout=10m \
  --max-cost=10 \
  --max-iter-cost=5 \
  --reserve-budget=10% \
  --no-sync \
  --local
```

- [ ] **Step 5: Author the node contract and checks**

Set `NODE.md` instructions to implement a dependency-free Python CLI that reports line, word, and character counts for one or more UTF-8 text files, handles missing and unreadable files with non-zero exit status, includes `unittest` coverage, and documents usage. Completion requires all tests to pass, the CLI and README to be committed, and `fractal node finish --reason="linecount pilot complete"` to be called.

Set `scripts/test.sh` to run `python3 -m unittest discover -s tests -v`. Set `scripts/lint.sh` to compile the CLI and tests with `python3 -m compileall -q`.

- [ ] **Step 6: Commit the node seed and launch**

From `.worktrees/main.linecount` run:

```bash
fractal commit "configure linecount pilot" --init
fractal node start
```

- [ ] **Step 7: Monitor without introducing a second owner**

Poll `fractal node status linecount`, `fractal node activity linecount`, and `fractal node cost spent linecount`. Use `fractal open` only as a separate cockpit; do not register the node in Agent Deck.

- [ ] **Step 8: Verify and merge**

After status becomes `completed`, run the tests in the node worktree, inspect its diff and commits, then run from the repository root:

```bash
fractal node merge linecount
```

Run the merged tests on `main`. Confirm that LiteLLM and Fractal both recorded the run and that no worktree is orphaned.

### Task 5: Record the gate result

**Files:**
- Modify: `doc/superpowers/specs/2026-07-22-fractal-agent-deck-pi-litellm-design.md`

**Interfaces:**
- Consumes: observed pilot results.
- Produces: a factual pilot-result appendix and a go/no-go statement for the separate one-child pilot.

- [ ] **Step 1: Append verified results**

Record versions, the node’s terminal status, test count, Fractal spend, whether LiteLLM recorded the request, merge result, and worktree state. Record no token, password, request header, or credential-derived material.

- [ ] **Step 2: Apply the native-Pi gate**

State `no-go yet` after only the first pilot. A native Pi backend remains blocked until a separately authorized one-child radio pilot succeeds and demonstrates a material need for Pi workers.

- [ ] **Step 3: Review final repository state**

Run:

```bash
git status --short --branch
git diff --check
git diff --stat
git diff
```

Confirm that only the planned Nix configuration, wrapper, tests, and documentation changed; confirm that no credential-like value is present.

## Execution Result

The plan completed on 2026-07-22 with one controlled deviation: a system-wide switch and the unrelated Anvil persistent-soak check were not run because another active session was changing Anvil. The Nix-produced user artifacts were activated reversibly, and the complete Home Manager activation package built successfully without switching the live system.

Pi and Codex both completed bounded requests through LiteLLM. Codex required three compatibility measures verified by regression tests and live smoke tests: insert provider overrides inside `codex exec`, consume Fractal's exact routed `-m` option, and reset the key to an empty value in tool shells after shell-snapshot restoration. The Fractal pilot completed in one successful iteration at USD 4.8325, passed six tests before and after merge, and produced `main` commit `e8f7a77` in `~/src/fractal-pilot`.

The native-Pi gate remains `no-go yet`; the one-child radio pilot remains a separate, separately authorized task.
