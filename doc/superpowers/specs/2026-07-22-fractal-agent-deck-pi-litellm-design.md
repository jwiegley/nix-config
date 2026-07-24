# Fractal, Agent Deck, Pi, and LiteLLM Integration Design

## Scope

This design introduces Fractal as a bounded autonomous execution plane beneath an Agent Deck-managed Pi operator. The first phase uses Codex workers routed through the private LiteLLM service. A native Fractal backend for Pi remains a subsequent, gated phase and is not part of the first implementation.

The installed versions assessed for this design are Agent Deck 1.10.10, Pi 0.81.1, Fractal 1.0.0, Codex CLI 0.144.6, and plasma-wiki 1.1.0.

## Ownership

Each layer has one owner and one purpose:

| Layer | Responsibility |
|---|---|
| Agent Deck | Own the interactive Pi operator session. |
| Pi | Configure, observe, steer, and conclude Fractal work. |
| Fractal | Own autonomous node lifecycle, worktrees, tmux sessions, budgets, radio, and its SQLite ledger. |
| Codex | Execute the work assigned to each first-phase Fractal node. |
| LiteLLM | Route model traffic and maintain the global cost record. |

Agent Deck does not register Fractal child nodes and does not create their worktrees. Fractal does not own the Pi operator session. This boundary avoids competing tmux, worktree, fork, and cleanup authorities.

## LiteLLM Route

All GPT-5.6 Sol traffic in this workflow uses the OpenAI-compatible Responses endpoint at:

```text
https://litellm.vulcan.lan/v1
```

The deployed model identifier is:

```text
positron_openai/gpt-5.6-sol
```

Authentication remains a runtime concern. The credential is read from the password-store entry `litellm.vulcan.lan`; no resolved value enters Git, a Nix derivation, the Nix store, a generated configuration file, a command argument, a log, or a diagnostic.

The endpoint has been verified to advertise the requested model, accept a Responses API request for it, and return usage metadata. The credential value was neither printed nor placed in process arguments during verification.

## Codex Route

A wrapper installed as `~/.local/bin/codex` reads the first line of the password-store entry into `LITELLM_API_KEY`, exports it only to the Codex process, and executes the profile-provided Codex binary. The wrapper supplies non-secret Codex configuration overrides for:

```toml
model = "positron_openai/gpt-5.6-sol"
model_provider = "litellm"

[model_providers.litellm]
name = "LiteLLM (Vulcan)"
base_url = "https://litellm.vulcan.lan/v1"
env_key = "LITELLM_API_KEY"
wire_api = "responses"
```

For `codex exec`, the wrapper inserts these overrides within the exec subcommand. Codex 0.144.6 otherwise lets a later exec-level `-c` option replace root-level overrides; Fractal supplies such an option for reasoning effort. The wrapper also consumes Fractal’s exact `-m positron_openai/gpt-5.6-sol` pair because Codex’s model flag resets the provider to `openai`; the equivalent `-c model=...` remains authoritative. Fractal continues to invoke the registered base command `codex`, so no Fractal backend shim is required.

This arrangement resolves a tmux boundary that environment injection alone cannot safely cross. Fractal creates worker sessions beneath an already-running tmux server, and passing a resolved token through `tmux new-session -e` would expose it transiently in argv. Reading the password inside the Codex wrapper avoids that exposure. The wrapper additionally excludes `LITELLM_API_KEY` from model-invoked shells and explicitly resets it to an empty string after Codex sources its shell snapshot; exclusion alone is insufficient because the snapshot can resurrect the parent value.

Fractal receives the configured model identifier `positron_openai/gpt-5.6-sol`. Its Codex pricing resolver first tries the full identifier and then strips the author prefix, thereby resolving the public `gpt-5.6-sol` rate entry. The Fractal ledger and boundary budgets therefore remain available in addition to LiteLLM’s global accounting.

## Pi Route

Pi receives a Nix-owned `~/.pi/agent/models.json` containing a `litellm` provider. Pi resolves the provider credential at request time through its native `!command` API-key form. The generated file contains only the command, never its output.

The model definition is:

```json
{
  "id": "positron_openai/gpt-5.6-sol",
  "reasoning": true,
  "thinkingLevelMap": {
    "off": "none",
    "minimal": null,
    "xhigh": "xhigh",
    "max": null
  },
  "input": ["text", "image"],
  "contextWindow": 1050000,
  "maxTokens": 128000
}
```

The model’s base and long-context pricing metadata mirrors the GPT-5.6 Sol rates used by Pi so that Pi’s own usage display remains meaningful. Pi’s mutable `settings.json` is not placed under Nix ownership; the deployment changes its selected default once, preserving all unrelated mutable state.

## Fractal Skills

Home Manager links the bundled operator-level `fractal` and `wiki` skill trees into `~/.agents/skills/`, a location Pi discovers natively. Fractal’s operator skill has `disable-model-invocation: true`; it is entered explicitly through `/skill:fractal` and does not activate merely because it is installed.

Autonomous nodes continue to use Fractal’s distinct node-seed skills. Those skills are created by `fractal node init` and are not replaced by the operator-level links.

## First Pilot

The first pilot runs in a disposable repository and uses one Codex node. The task is a dependency-free Python command-line program that reports line, word, and character counts, with `unittest` coverage and a concise README.

The run configuration is fixed as follows:

| Setting | Value |
|---|---|
| Agent | `codex` |
| Model | `positron_openai/gpt-5.6-sol` |
| Effort | `medium` |
| Run budget | USD 10 |
| Iteration budget | USD 5 |
| Maximum iterations | 2 |
| Run timeout | 45 minutes |
| Step timeout | 10 minutes |
| Maximum descendants | 0 |
| Radio sync | disabled |
| Remote pushes | disabled |

Codex has no hard in-flight monetary limit. Fractal checks monetary caps between launches; the step, iteration, and run timeouts are the stronger containment boundaries.

The pilot passes when Pi discovers the operator skill; Agent Deck owns only the root Pi session; Fractal starts and records the Codex node; LiteLLM records the routed traffic; Fractal records priced spend; the requested implementation and tests complete; and `fractal node merge` lands the result without an orphaned worktree.

## Pilot Result

The single-node pilot passed on 2026-07-22. The `main.linecount` node completed in one successful iteration, called `fractal node finish --reason="linecount pilot complete"`, and recorded USD 4.8325 of spend. Its six `unittest` cases pass on both the node branch and merged `main`; `fractal node merge linecount` produced commit `e8f7a77` containing only the CLI, tests, and README changes. The completed node remains registered with a live, non-orphaned worktree. Agent Deck reports `fractal-pilot-operator` as the sole child session and leaves Fractal’s worker tmux session outside its registry.

The pilot also established three Nix-specific compatibility findings:

- Fractal’s seed copy preserves the Nix store’s read-only file modes. The disposable node required a recursive user-write correction before `NODE.md`, scripts, and agent configuration could be edited.
- Fractal’s Codex skill link points `CODEX_HOME/skills` directly at the tracked node skills. Codex 0.144.6 writes `.system` there, so the pilot replaced that directory link with an ignored real directory containing individual links to the four node skills.
- The Wiki Obsidian plugin template likewise retained read-only modes; a recursive user-write correction permitted the optional plugin refresh.

These findings belong in the Fractal Nix package or upstream Fractal and deserve dedicated regression checks. They do not alter the layered ownership model.

The native-Pi decision remains `no-go yet`: the required one-child radio pilot has not been authorized or run.

## Native Pi Worker Gate

A native Pi backend is considered only after the single-node pilot and a separate one-child radio pilot both pass. Development proceeds only when Pi-specific models, tools, or behavior provide a material worker benefit beyond the existing Codex backend.

The future backend belongs at Fractal’s provider seam, first through the per-tree `agents.py` hook and ultimately as an upstream `fractal.impl.pi` module. It will use Pi’s JSON mode, node-local session storage, explicit node skills, fresh/resume/fork session operations, and Pi-reported per-turn costs. Agent Deck remains unchanged.

## Failure and Recovery

A missing password-store entry causes the Codex wrapper or Pi provider to fail with a redacted error before a model request. A LiteLLM routing failure remains a provider error and does not fall back to direct OpenAI traffic.

If the Fractal node exits abnormally, inspect `fractal node activity` and the node’s `codex.err`. Continuation does not use `--clean` unless loss of uncommitted node state is deliberate. Merge occurs only after tests and branch state have been inspected.

## Verification

Verification comprises five layers:

1. A wrapper test proves that a synthetic credential reaches Codex only through the environment and never through argv or output.
2. Nix formatting, linting, dead-code checks, and the host system build pass.
3. Pi lists and invokes the LiteLLM-backed model with the exact context and output limits.
4. A bounded Codex smoke invocation reaches LiteLLM through the wrapper.
5. The disposable Fractal pilot meets every acceptance condition above.
