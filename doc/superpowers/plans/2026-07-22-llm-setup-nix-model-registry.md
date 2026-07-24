# LLM Setup to Nix Model Registry Implementation Plan

> **For agentic workers:** Use test-driven development and an isolated worktree. Fleet
> activation and Promptdeploy retirement remain separately authorized.

**Goal:** Make `llm-setup.el` the sole authority for model definitions and
selections, publish a deterministic nonsecret registry into the Nix configuration
repository, and have Nix render every agent configuration from that registry during
rebuilds.

**Architecture:** `llm-setup-reset` projects the in-memory registry into tracked
`config/ai/model-registry.json`. Nix validates that projection, derives source order
and composite keys, attaches only client compatibility and security policy from
`model-policy.nix`, and feeds the result to the existing renderers. Git and the
existing nix-config pins broadcast changes. Reset never commits, pushes, invokes
Nix, uses SSH, rebuilds, or mutates an agent configuration directly.

## Locked schema v2 contract

The generated document has exactly this shape:

```json
{
  "schemaVersion": 2,
  "selections": {
    "default": {
      "provider": "litellm",
      "model": "hera/omlx/Qwen3.6-27B-oQ4e-mtp"
    },
    "claudeDefault": {
      "provider": "positron-anthropic",
      "model": "claude-fable-5"
    },
    "claudeHaiku": {
      "provider": "positron-anthropic",
      "model": "claude-sonnet-4-6"
    },
    "claudeSubagent": {
      "provider": "positron-anthropic",
      "model": "claude-fable-5"
    }
  },
  "providers": [
    {
      "id": "litellm",
      "displayName": "LiteLLM",
      "baseUrl": "https://litellm.vulcan.lan/v1/",
      "apiKey": { "env": "LITELLM_API_KEY" }
    }
  ],
  "models": [
    {
      "provider": "litellm",
      "id": "hera/omlx/Qwen3.6-27B-oQ4e-mtp",
      "displayName": "Qwen 3.6 27B OQ4E MTP (MLX)",
      "maxOutputTokens": 65536,
      "contextLimit": 262144,
      "outputLimit": 65536
    }
  ]
}
```

- Top-level keys are exactly `schemaVersion`, `selections`, `providers`, and
  `models`; the schema version is exactly `2`.
- Selection keys are exactly `default`, `claudeDefault`, `claudeHaiku`, and
  `claudeSubagent`; every value has exactly `provider` and `model`.
- Provider keys are `id`, `displayName`, `baseUrl`, `apiKey`, and optional
  `hosts`.
- Model keys are `provider`, `id`, `displayName`, `maxOutputTokens`, and
  optional `contextLimit`, `outputLimit`, and `hosts`.
- `apiKey` is exactly one of `{"env":"UPPER_CASE_NAME"}` or an allowlisted
  `{"nonSecret":"..."}`.
- Arrays preserve declaration order. Nix derives `sourceOrder` and composite keys.
- Optional values are omitted, never serialized as `null`.
- Provider IDs and model pairs are unique; every route and selection resolves.
- The document contains no timestamps, Git revisions, client selectors, profile
  IDs, executable paths, live credential values, or arbitrary Custom state.

`llm-setup.el` owns provider and model identity, display names, endpoints, typed
credential references, effective limits, host availability, and all four selections.
Nix owns client selectors, excluded profiles, Droid/OpenCode/Pi adapters, OpenCode
profile fan-out, synchronization URL adaptation, renderers, MCPs, skills, commands,
prompts, paths, and activation.

## Frozen migration parity

The frozen Nix expression at `2c40781` contains 8 providers and 111 routes. The v2
projection contains the same provider facts and 119 routes.

The only added routes are:

- `positron-openai/gpt-5.6-luna`
- `positron-openai/gpt-5.6-sol`
- `positron-openai/gpt-5.6-terra`
- `litellm/positron_openai/gpt-5.6-luna`
- `litellm/positron_openai/gpt-5.6-sol`
- `litellm/positron_openai/gpt-5.6-terra`
- `litellm/openrouter/moonshotai/kimi-k3`
- `litellm/openrouter/qwen/qwen3.7-max`

Every common provider and model field is equal. Common route relative order is equal
after accounting for the already-audited GLM-5.2 movement from frozen index 28 to
generated index 35. The committed smoke gate records hashes of the frozen provider
facts and normalized common model facts so this exception cannot silently widen.

## Safety and scope

- Never edit Promptdeploy or read `.env`, password stores, SOPS data, auth state,
  or expanded live client configurations.
- Export credential reference names only. Evaluate and build with credential
  variables unset.
- Generate atomically and compare bytes before replacement. An identical reset leaves
  inode, modification time, and Git state unchanged.
- Do not add automatic commit, push, network, Nix, SSH, activation, or rebuild
  behavior.
- Fleet activation and Promptdeploy retirement remain the separately authorized
  rollout boundary.

## Tasks

### Task 1: deterministic projection

- [x] Add structured nonsecret provider facts and all four model selections.
- [x] Project schema v2 as deterministic canonical JSON.
- [x] Preserve the 8-provider/119-route authority anchors and exclude embedding and
  reranker instances.
- [x] Prove no credential lookup or file write occurs in the pure projection.

### Task 2: idempotent atomic writer

- [x] Write through a same-directory temporary file and atomic rename.
- [x] Skip byte-identical writes and preserve inode and modification time.
- [x] Support an explicit destination for tests and isolated worktrees.

### Task 3: strict Nix loader and policy

- [x] Generate the initial artifact by calling the exporter with an explicit
  destination.
- [x] Reject unknown keys or versions, duplicates, dangling references, malformed
  credentials, unsafe URLs, invalid hosts, non-positive limits, and secret-bearing
  fields.
- [x] Derive source order and composite keys, then attach only allowlisted Nix policy.
- [x] Move selectors, Droid/OpenCode adapters, OpenCode profile fan-out, and sync
  adaptation into `model-policy.nix`.
- [x] Feed Claude default, Haiku, and subagent values from selections; feed OpenCode
  defaults and synchronization from `selections.default`.
- [x] Preserve the public `{ providers; models; profileDefaults; syncInputs; }`
  interface, with internal `selections` exposed only where renderers need it.
- [x] Prove the frozen parity contract and build with credentials unset.

### Task 4: reset publishes only the Nix artifact

- [x] Call the JSON writer exactly once from `llm-setup-reset`.
- [x] Remove Promptdeploy and `models.yaml` generation from reset.
- [x] Keep service-specific LiteLLM and llama-swap generation behavior separate.

### Task 5: verification and publication

- [x] Run the exporter twice and prove the second produces no byte or Git change.
- [x] Run Nix formatting, focused registry validation, Home Manager smoke, and
  supported-platform evaluations.
- [x] Commit the llm-setup and Nix changes separately and publish their existing
  branches.
- [x] Record exact revisions in the parent handoff.
- [x] Do not activate hosts or retire Promptdeploy without separate rollout authority.
