# Nix-Managed Agent Configuration Design

Status: approved for implementation on 2026-07-22.
Date: 2026-07-22
Scope: Tasks 1–12 are authorized for implementation and ordinary publication. Task 13 host mutation, rollback-window closure, and promptdeploy retirement remain separately fail-closed.

## Executive decision

The canonical desired state for personal coding agents moves from promptdeploy into `/Users/johnw/src/nix`. Home Manager will realize that state locally on each machine. The design manages Claude Code, Codex, OpenCode, Droid, and Pi through a shared catalog, explicit profile selectors, five small client renderers, and exact leaf ownership.

`config/ai.nix`, imported by `config/johnw.nix`, is the integration point. It consumes immutable packages and external skill resources supplied by `ai-nix`; it does not run promptdeploy, copy a rendered promptdeploy tree, or create a general deployment framework. Promptdeploy remains frozen as the migration oracle until the rollout and rollback window are complete, then leaves the active workflow.

The result has no remote deployment path. Each host evaluates and realizes its own locked Home Manager closure. The one exception in the topology is not remote deployment: the Andoria family shares one NFS home, so all four hosts must first realize and retain the identical closure in their separate local Nix stores, after which Andoria-08 performs the single shared-profile activation.

## Goals

- Make Nix and Home Manager the source of truth for the five named agent clients.
- Express common agents, commands, skills, prompts, MCP servers, hooks, marketplaces, providers, models, and static settings once.
- Preserve the effective selections and audience distinctions currently encoded by promptdeploy tags, `only`, `except`, and target configuration.
- Preserve mutable client state such as authentication, sessions, trust databases, histories, caches, UI state, and package selections.
- Keep every secret unresolved until runtime and out of Git, evaluation, derivations, store paths, generated files, process arguments, and logs.
- Make an unchanged second Home Manager switch and unchanged macOS model synchronization a no-op.
- Support Hera, Clio, Vulcan, VPS, and the shared work home without SSH or rsync deployment.
- Provide a reversible, evidence-driven one-time migration from promptdeploy ownership.

## Non-goals

- This design does not create a reusable Home Manager options framework. It is a focused configuration for this fleet.
- It does not retain promptdeploy's manifests, hashes, adoption logic, force mode, reconciliation engine, settings patch engine, bundle receipts, deployment SSH, or rsync.
- It does not port the Poet or Jinja renderer; the two current `.poet` prompts become ordinary rendered Markdown assets.
- It does not manage GPTel or git-ai, which are outside the five named clients. Their existing artifacts and any legacy manifests remain untouched and become frozen unmanaged state; migration neither adopts nor deletes them.
- It does not make client authentication, sessions, caches, histories, trust state, or mutable package state declarative.
- It does not turn native client mutation commands into a second configuration source.
- It does not change runtime MCP transports such as `drafts-hera`; only deployment transport is removed.

## Current-state baseline

The design was derived from three independent inventories: repository and consumer topology, host/persona ownership, and promptdeploy selection/rendering semantics. The schema-v3 promptdeploy manifests inspected during design establish this legacy baseline:

- 26 agents.
- 59 personal commands and 58 Positron commands.
- Two Droid command-as-skill entries.
- 38 broadly shared skills, plus Claude-only Forge and Positron-only Retest.
- Two rendered prompts.
- Target-specific MCP sets, three Claude hook groups, one Codex hook group, and two Claude marketplaces.

These counts are migration evidence, not an API. The migration ledger records the exact names, selectors, and destination paths at the frozen promptdeploy revision so additions or omissions cannot hide behind matching totals.

The live fleet has several constraints that the design treats as authoritative:

- Hera and Clio keep separate Claude personal and Positron roots at `~/.config/claude/personal` and `~/.config/claude/positron`.
- Vulcan and VPS use the conventional Claude root `~/.claude`.
- Andoria-08, Andoria-t2, Delphi-3bd4, and gpu-server share one NFS home and one Home Manager profile, but each machine has its own local `/nix/store`.
- The shared Home Manager flake currently labels the configuration as Andoria-08. File selection must therefore use a `shared-work` home class rather than treating that configured label as the runtime hostname.
- External consumers import nix-config with `flake = false`, so inputs declared only in the root nix-config flake do not propagate to them.
- Existing Claude, Codex, and Droid base configuration files mix managed configuration with mutable client state and cannot be wholly replaced.

The recorded shared-home failure in [`docs/ANVIL-NELISP-HANDOFF.md`](../../ANVIL-NELISP-HANDOFF.md) is a hard rollout constraint: shared-home links appeared on other machines before the referenced closure existed in their local stores. The rollout ordering below prevents that failure class.

## Architecture

```text
config/ai/catalog.nix + models.nix + immutable assets
                         |
                   profile selection
                         |
         +---------------+---------------+
         |       |          |       |    |
       Claude   Codex    OpenCode  Droid Pi
       renderer renderer  renderer renderer renderer
         |       |          |       |    |
       exact Home Manager files and package wrappers
                         |
              local realization on each host
```

The architecture has three deliberately small layers:

1. A canonical catalog describes content, metadata, selectors, secret references, and model/provider relationships.
2. Five client renderers translate the selected catalog into native client formats and exact destination paths.
3. Home Manager declares only those leaf files, generated config documents, scripts, and packages that Nix owns.

`ai-nix` remains the package boundary. It supplies executable wrappers, the pinned single-purpose Droid HTTP-header bridge, packaged upstream resources, and immutable skill trees. It does not own fleet selection or Home Manager file placement. `/Users/johnw/src/nix` owns profiles, selection, rendering, and leaf declarations.

### Repository layout

```text
config/
  johnw.nix                  # imports ai.nix
  ai.nix                     # profiles, selectors, renderers, HM leaves
  ai/
    catalog.nix              # agents, commands, skills, prompts, MCP, hooks
    models.nix               # providers, models, per-profile defaults
    agents/                  # canonical body-only Markdown
    commands/                # canonical body-only Markdown
    skills/                  # local canonical skill trees
    prompts/                 # two pre-rendered Markdown prompts
```

`ai.nix` may use small local helper functions, but it does not expose a new public options namespace or a generic module library. The file is organized around this fleet's profiles and the five output contracts.

External skill sources are not added solely to the root `flake.nix`, because that would fail for flake-false consumers. Instead `/Users/johnw/src/ai-nix` pins and packages them and exposes a stable `agent-resources` output. `config/ai.nix` consumes `inputs.ai-nix.packages.${system}.agent-resources` or the equivalent overlay package already available to every consumer.

## Profiles and fleet matrix

A profile is a realized client/root context. It combines a client, audience, platform, home class, destination root, and renderer. Runtime hostname is not a catalog selector for the shared work home.

| Home | Managed profiles | Destination and audience | Writer |
|---|---|---|---|
| Hera | Claude personal, Claude Positron, Codex, OpenCode, Droid, Pi | Claude under `~/.config/claude/{personal,positron}`; other native roots; personal audience unless explicitly Positron | Hera |
| Clio | Claude personal, Claude Positron, Codex, OpenCode | Same dual Claude roots as Hera; personal audience unless explicitly Positron | Clio |
| Vulcan | Claude personal, OpenCode | Claude at `~/.claude`; personal audience | Vulcan |
| VPS | Claude personal | Claude at `~/.claude`; personal audience | VPS |
| Shared work home | Claude Positron, Codex shared union, OpenCode Positron | Claude at `~/.claude`; work/Positron selection; Codex preserves the current shared union | Andoria-08 only, after four-host realization |

The shared work home is consumed by Andoria-08, Andoria-t2, Delphi-3bd4, and gpu-server. Those machines are not four Home Manager writers. They are four local-store consumers of one NFS profile.

Droid and Pi are intentionally Hera-only. GPTel and git-ai remain outside this design.

## Catalog and selector semantics

Each catalog item has a stable name, content or immutable source, client-neutral metadata, optional client overrides, and selectors. Supported selector dimensions are:

- `clients`
- `audiences`
- `hosts`
- `platforms`
- `profiles`

Values within one dimension are ORed. Dimensions present on an item are ANDed. A missing dimension is unrestricted. `excludeProfiles` is the single supported negative escape hatch for the existing negative-selection case.

For example, an item selected for clients `claude` or `codex`, audience `personal`, and platform `darwin` matches either client only when both the audience and platform also match. It does not match Positron or Linux.

Promptdeploy filename tags and `only`/`except` fields are translated once into this schema. Deployment-only metadata is then removed from canonical content. A selector coverage ledger maps every legacy target, tag, allowlist, and denylist affecting the five managed clients to the resulting profile/item decision, and separately records GPTel/git-ai as untouched exclusions.

Catalog evaluation asserts:

- Every selector names a known client, audience, host class, platform, or profile.
- Every enabled profile has exactly one renderer.
- Every rendered target path is unique within a profile.
- Every skill name is unique across local and externally packaged resources.
- Every MCP server declares exactly one transport.
- Client overrides use supported fields only.
- Secret-bearing values use the typed environment-reference form only.
- When a default model is emitted, its provider and model remain selected for that profile.

No dependency graph is introduced. The current primary sources use no `requires` relationships, so dependency resolution would be speculative machinery.

### Canonical content forms

- Agents and commands are body-only Markdown. Their metadata lives in `catalog.nix`. Renderers prepend JSON object syntax, which is valid YAML, when a client requires YAML frontmatter.
- Skills remain complete directory trees. Selection metadata moves out of `SKILL.md` and into the catalog.
- The two `.poet` prompts are rendered once to ordinary Markdown and then treated as static source.
- JSON and TOML are generated with Nix formatters such as `pkgs.formats.json`, TOML generators, and `builtins.toJSON`; renderers do not concatenate ad hoc serialized fragments.
- Current settings patches are evaluated once into explicit Nix attribute composition and deletion. The RFC 7396 patch engine is not recreated.
- Statusline paths derive from `config.home.homeDirectory` and the selected profile root, never from a hard-coded user home.
- Disabled `anvil-tools` is a one-time migration tombstone and is not canonical catalog content.

## Ownership rule

Home Manager owns the smallest complete leaf that can be declarative. It never owns an entire mutable client root. A managed symlink or generated file has one writer: Nix. Files containing live client state remain ordinary mutable files.

| Client | Nix-owned state | Mutable state left to client/user | Launch contract |
|---|---|---|---|
| Claude | Selected agents, commands, skills, statusline script, `nix-managed-settings.json`, `nix-managed-mcp.json` | `settings.json`, profile `.claude.json`, auth, sessions, projects, caches | `ai-nix` wrapper injects both managed files |
| Codex | Selected agent TOML, exact user skill trees, `nix-managed.config.toml` with inline hooks | Base `config.toml`, global `hooks.json`, auth, sessions, history, SQLite, logs, system skills | Wrapper selects profile `nix-managed` on effective runtime surfaces |
| OpenCode | Complete `opencode.json`, selected agents, commands, skills | Data, state, cache, npm/package trees | Native loading; no wrapper |
| Droid | Selected droids, command-as-skill trees, skills, `mcp.json`, `nix-managed-settings.json` | Base `settings.json`, auth, trusted folders, UI state, sessions | Wrapper injects managed settings |
| Pi | Prompts, subagent definitions, `models.json`, extensions, standard global MCP catalog | `settings.json`, auth, sessions, model store, package selections, settings-only adapter override/cache/OAuth | Native discovery and pinned extensions |

Injecting wrappers are safe on installed-but-unmanaged profiles. With no managed artifacts present for the active root, the wrapper passes through without injection. With the complete expected artifact set present, it injects the managed flags. Partial presence fails with a clear repair message. This keeps the git-ai Claude persona, Codex on Vulcan, and Droid outside Hera usable without accidentally applying another profile.

All injecting wrappers use one escape hatch: `AI_NIX_BYPASS_MANAGED_CONFIG=1`. It omits only the new managed-config injection and permits recovery from partial artifacts. Existing wrapper behavior remains active, especially Codex's host-local SQLite/log relocation for the shared NFS home. In complete managed mode, a user-supplied conflicting flag is rejected; in pass-through or bypass mode it is forwarded normally. Integrations that truly require an upstream binary use an explicitly named private command. There is no silent precedence rule.

### Claude Code

Claude receives exact profile-local agent, command, and skill leaves, a generated statusline script, `nix-managed-settings.json`, and `nix-managed-mcp.json`. Hooks, marketplaces, plugins, and static managed settings live in the managed settings supplement. MCP servers live in the separate managed MCP document.

The `ai-nix` Claude wrapper computes the active root from `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` and supplies `--settings` and `--mcp-config`. It does not supply `--strict-mcp-config`, so project-local MCP configuration can still participate. Explicit conflicting `--settings` or `--mcp-config` arguments fail unless the bypass variable is set.

The ordinary `claude` command must resolve to this wrapper. The current direct `~/.local/bin/claude` link to the llm-agents binary is removed or replaced. The raw binary is exposed under an explicit private name such as `claude-real` only for integrations such as claude-mem, whose configured path is updated accordingly.

`settings.json` and the profile-local `.claude.json` remain mutable because they contain client/runtime state. During migration, only promptdeploy-owned keys and exact matching entries are removed from the actual profile-local files. Unmanaged MCP entries such as `org-wiki` and all unrelated state are preserved. Hera's global `~/.claude.json` is not mistaken for the profile-local target.

### Codex

Codex receives exact selected agent TOML files, exact user skill trees under `~/.agents/skills`, and `$CODEX_HOME/nix-managed.config.toml`, with the selected hook declarations embedded in that profile layer. Codex 0.144.6 effectively applies a config profile for interactive use, `exec`, `review`, `resume`, `archive`, `delete`, `unarchive`, `fork`, `sandbox`, and exactly `debug prompt-input`; the wrapper invokes those surfaces with `--profile nix-managed`, which layers that file over the mutable base configuration. Although `mcp` accepts the flag syntactically, this release discards the selected layer after migration validation and operates on mutable base configuration, so every `mcp` command delegates unchanged. Other configuration, diagnostic, completion, and server-management surfaces likewise delegate. A separate `$CODEX_HOME/hooks.json` is deliberately not managed because pinned Codex discovers that file from both base and profile layers in the same directory; embedding hooks in the selected TOML layer prevents delegated commands from inheriting personal hooks.

The base `config.toml` remains mutable because it contains project trust and runtime state as well as legacy expanded values. Authentication, sessions, history, SQLite, logs, caches, and bundled/system skills remain unmanaged. Existing `ai-nix` behavior that keeps shared `CODEX_HOME` while relocating only SQLite and logs remains compatible.

On a command surface receiving managed selection, an explicit user `--profile` conflicts and fails unless `AI_NIX_BYPASS_MANAGED_CONFIG=1` is set. The conflict scan ends at `--` and rejects only positions Codex itself parses as a config profile; child-command flags are preserved on both managed and delegated surfaces.

### OpenCode

OpenCode's complete `opencode.json` is declaratively owned. The generated document adopts existing static keys such as `$schema`, `disabled_providers`, and `instructions` in addition to selected MCP servers, providers, models, and any default that survives filtering. Agents, commands, and skills are exact managed leaves.

OpenCode uses native `{env:VAR}` references and needs no wrapper. Runtime data, state, cache, and npm/package trees remain mutable.

Commands that mutate the owned configuration, including `opencode mcp add`, are unsupported in the managed profile. Ordinary Home Manager symlinks cannot prevent a client from unlinking them, so pre-activation and verification checks detect a missing/replaced link or changed target and fail closed. They never silently overwrite the replacement; the intended change must be moved into Nix or the unmanaged collision resolved explicitly.

### Droid

Droid receives exact droid definitions, the two selected command-as-skill trees, selected skills, a complete managed `mcp.json`, and `nix-managed-settings.json`. Static custom-model configuration lives in the managed settings overlay. The installed Droid version does not automatically load `settings.local.json`, so the `ai-nix` wrapper passes `--settings` explicitly.

Complete ownership of `mcp.json` includes one deliberate adoption: the live unmanaged `pal` entry becomes an explicit Droid/Hera catalog entry rendered from the secret-safe source definition. Its live expanded bytes are never copied. Any other unmanaged Droid MCP entry found at migration is a collision and stops cutover rather than being silently deleted.

The base `settings.json` remains mutable because it contains trusted folders and UI state. An explicit user `--settings` conflicts and fails unless the bypass variable is set. `droid mcp` mutation is unsupported for the declaratively owned `mcp.json`.

### Pi

Pi is enabled only on Hera and uses Pi's native resource discovery rather than a promptdeploy runtime. Its exact owned paths and loading contracts are:

- The 26 personal-selected agents render as `~/.pi/agent/agents/<name>.md` for `pi-subagent`.
- The 59 personal-selected commands render as native `~/.pi/agent/prompts/<name>.md` templates.
- The two pre-rendered prompts use the same native prompt directory.
- Personal-selected shared skills remain under `~/.agents/skills/<name>/`; no skill tree is copied under `.pi`. This includes the six static Ponytail skills visible through Hera's Codex-owned shared root.
- Codex parity also places 59 `command-*` and two `prompt-*` skill projections in `~/.agents/skills`. Pi natively discovers those projections in addition to its prompt templates. This duplication of entry surfaces is explicit inventory, not a second file copy or a wrapper filter.
- `~/.pi/agent/models.json` contains only the `litellm` provider, with model-level Hera selectors applied. Pi never falls back to a direct provider; models without a LiteLLM route are excluded.
- Pi's mutable `settings.json` remains authoritative for its selected default; this design emits no Pi default provider/model.
- `~/.config/mcp/mcp.json` is the Nix-owned standard global catalog for Ref, context-hub, context7, `perplexity`, sequential-thinking, and Anvil. `~/.pi/agent/mcp.json` remains mutable only for adapter-level `settings`; global `mcpServers` and compatibility `imports` are forbidden because that higher-precedence file could shadow the Nix catalog. Migration and verification fail closed if either field appears. Adapter cache and OAuth state remain mutable.
- `~/.pi/agent/extensions/pi-mcp-adapter` and `~/.pi/agent/extensions/pi-subagent` are exact Home Manager links to pinned `ai-nix` package roots and load through Pi's normal extension discovery.

Pi intentionally excludes PAL, DEVONthink, Drafts, memory-vault, stock-trader, hooks, and marketplaces because their selectors restrict them to other clients. The `anvil-tools` tombstone is also excluded. Global `/mcp setup`, imports, and server-definition toggles are unsupported; adapter-only settings may remain mutable. Trusted project `.mcp.json` and `.pi/mcp.json` additions retain their native project-local precedence and do not redefine the user-global source of truth.

Pi has no legacy promptdeploy target. Its acceptance oracle is therefore the exact agent, template, shared-skill, Codex-projection, model, MCP, and extension inventory above, not a fabricated parity comparison. Prompt templates retain native `$ARGUMENTS` behavior. Models and MCP use their native environment-reference syntax.

## External resources and `ai-nix`

`ai-nix` pins and packages every external resource needed by flake-false consumers:

- Superpowers.
- Ponytail.
- git-surgeon from the llm-agents source.
- translate-tool glossary and related resources.
- `pi-mcp-adapter`.
- `pi-subagent`.
- Patched `mcp-remote` for Droid's static-header-only bridge.

It exposes skill/extension resources as immutable trees beneath an `agent-resources` package/output and supplies the needed wrappers and pinned bridge. `config/ai.nix` chooses and links resources from that package. There is no copied deployment bundle, promptdeploy receipt, or dependence on transitive root flake inputs.

Packaging does not imply selection. `catalog.nix` explicitly selects Superpowers and git-surgeon for every enabled skill-capable client profile, selects translate-tool resources according to their current skill selectors, and applies Ponytail's static-skill contract below. Pi consumes selected shared skills through `~/.agents/skills`; the other clients receive their native skill leaves.

A skill name has one canonical source. When a pinned external tree supersedes a same-named local copy, the catalog references the external tree and removes the duplicate local entry; there is no precedence rule or last-writer behavior. Resource assembly rejects duplicate selected skill names before Home Manager constructs any destination. Upstream source pins live in `ai-nix`, where all consumers already obtain their package set.

### Ponytail static skills

Ponytail is packaged as fixed, pinned Nix resources rather than as a retained promptdeploy bundle. Its six complete skill trees are selected for Claude, Codex, Droid, and OpenCode. On Hera, Pi sees the same six Codex-owned trees through `~/.agents/skills`; it receives no duplicate copy under `.pi`.

Dormant Ponytail lifecycle hooks, ambient modes, status lines, runtime publication, and the OpenCode plugin are not selected or registered. Existing unrelated agent-deck hooks and plugins are preserved. Existing GPTel Ponytail prompt projections are outside migration and remain untouched. No bundle catalog, receipt, adoption engine, or runtime downloader survives.

### Native contract references

The Pi path and loading contracts follow its official [skills](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/skills.md), [settings](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/settings.md), and [models](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/models.md) documentation. The extension-specific paths follow [pi-mcp-adapter](https://github.com/nicobailon/pi-mcp-adapter) and [pi-subagent](https://github.com/mjakl/pi-subagent). Ref authentication uses its [documented header form](https://docs.ref.tools/context/install).

## Secrets and runtime references

A secret value in the catalog has one representation:

```nix
{ env = "NAME"; }
```

Evaluation never reads `.env`, password stores, SOPS data, or live client configuration. The renderer translates the typed reference to native syntax:

| Client | Native runtime form |
|---|---|
| Claude | `${VAR}` |
| OpenCode | `{env:VAR}` |
| Codex | native environment-key fields, `env_http_headers`, or bearer-token environment fields |
| Droid | `${VAR_NAME}` for custom models; stdio children inherit the environment |
| Pi | `$VAR` or `${VAR}` |

### Launch environment contract

Nix declares required variable names but never supplies their values. Claude, Codex, and Droid wrappers preserve the parent environment; OpenCode and Pi inherit it directly. No wrapper reads `.env`, a password store, SOPS material, or a live config file.

Terminal launches receive variables from the user's existing session bootstrap. Agent-deck launches receive them from the agent-deck process environment, and that process must be restarted when its secret environment changes. Any GUI launch uses a user-controlled launch environment outside the Nix store. A missing required variable produces a bounded, redacted client/server error; it never falls back to a literal in generated configuration.

Acceptance exercises terminal, agent-deck, and applicable GUI launch surfaces with synthetic values, verifies every required value arrives unchanged and wrappers introduce no additional secret material, and checks that neither values nor derived tokens appear in argv, generated files, store closures, or logs.

Ref uses `https://api.ref.tools/mcp` with the supported `x-ref-api-key` header rather than a query-string token. Context7 likewise uses an environment-backed header. This avoids Codex's lack of URL environment expansion and keeps credentials out of URLs.

The pinned Pi adapter expands header environment references natively. Droid does not, so `ai-nix` supplies one patched `mcp-remote` static-header-only bridge. That bridge process is the sole approved stdio child allowed to inherit the named credential. It skips OAuth discovery, configuration and browser paths, rejects missing variables, 401 responses, redirects, and debug mode, deletes the consumed variable from its own environment after in-process expansion, spawns no further subprocess, and emits only bounded redacted errors. The resolved credential may exist only in that process's inherited environment until deletion, its header map, and the outbound TLS request; it never enters argv, a URL, any further child environment, generated files, derivation arguments, cache paths, persistence, or diagnostics.

Nix store paths are world-readable. Assertions reject literal secret-shaped values where a typed reference is required, and verification scans rendered outputs and their closures for forbidden resolved values. A synthetic sentinel test supplements these structural checks but is not the only proof.

Live expanded Claude, Droid, or OpenCode files are never copied into fixtures or compared byte-for-byte as parity input. Secret-bearing migration backups are host-local and protected or encrypted; they never enter Git, the Nix store, the shared NFS home, or ordinary logs.

## Models, defaults, hooks, and settings

Provider and model selection is profile-aware. A renderer emits a default only if both its provider and model survive filtering. OpenCode on Vulcan may intentionally have no Nix-managed default because the litellm provider is excluded; this is valid and must not be repaired by reintroducing the provider.

Claude hook groups, marketplaces, plugins, and settings are rendered into its managed settings supplement. Codex's current hook declarations are wholly agent-deck sourced and become an exact inline section of `nix-managed.config.toml` once parity is proven; the global `hooks.json` remains unmanaged. OpenCode's complete config includes both adopted static keys and rendered dynamic sections. Droid's managed overlay contains only declarative static values.

No general JSON merge-patch engine survives. Nix expressions directly compose the final attribute sets, including intentional deletions.

## Hera macOS model synchronization

Hera retains DEVONthink and iTerm2 model synchronization as a separate Darwin/Hera-only activation concern. It is not part of the core catalog renderer and it is never invoked remotely. The legacy Clio-side synchronization path is intentionally retired; Clio does not own these application model catalogs in the approved topology.

The activation computes a digest of the rendered model input and records the last successfully synchronized digest in mutable XDG state. When the digest is unchanged, activation performs no application work. When it changes, synchronization runs once and updates the stamp only after success.

If either application is running and the update is unsafe, activation defers or fails with a clear instruction; it never forces application termination or rewrites live state. A failed or deferred run does not advance the digest stamp.

## One-time migration

Migration is a reviewed runbook or disposable script, not a persistent deployment subsystem. It has two phases.

### Phase A: freeze and prove

1. Freeze a content-addressed snapshot of the exact nonsecret promptdeploy inputs used as the oracle. Record the Git revision plus hashes for every tracked, dirty, and relevant untracked configuration/content source; alternatively commit that exact content first. Explicitly exclude `.env`, credential files, live client state, and every other secret source, recording only required environment-variable names. A revision alone is insufficient, and the current authoritative modified `models.yaml` must be included.
2. Record the corresponding legacy manifest hashes.
3. Quiesce the affected client processes. For the shared work home, quiesce every possible writer on all four hosts.
4. Render the frozen snapshot with `--target-root` as a secret-free legacy oracle; this preview preserves environment references rather than expanding them.
5. Build the proposed Home Manager render trees without switching.
6. Compare selected item names and asset tree hashes. Require exact relative paths only for unchanged asset leaves; relocated configuration uses an explicit old-path/key to new-artifact/key semantic mapping for Claude supplements, the Codex profile, Droid settings, and other intentional moves.
7. Validate Pi directly against its explicit inventory.
8. Produce a selector coverage ledger mapping every legacy target/tag/`only`/`except` decision affecting the five managed clients and explicitly listing untouched GPTel/git-ai exclusions.

The ledger records every reviewed semantic transformation: configuration relocation, Ref query-token to header authentication, client-native environment reference syntax, any credential-resolving bridge, serialization/order normalization, removed manifests/provenance, and normalized home prefixes. No other difference is ignored.

Two oracles remain separate. The frozen preview proves desired-state semantic parity. Live cutover drift uses legacy manifest ownership plus an in-memory redacted structural digest: secret-classified values are normalized before comparison, only path/key ownership and nonsecret structure are compared, and only digests and decisions may be persisted or logged. A secret-bearing live file is never byte-compared to reference-preserving preview output.

Secret literal equality is intentionally not an ownership oracle: the frozen desired state contains a runtime reference, not the resolved credential. A secret-bearing entry may be removed only when the legacy manifest and exact parent/key mapping independently establish promptdeploy ownership and every nonsecret field matches. Missing ownership evidence or any nonsecret drift stops cutover; the credential bytes are neither resolved nor compared.

### Phase B: adopt and activate

Every destination is classified before mutation:

- Absent: proceed.
- Manifest-owned and accepted by the frozen live-drift oracle: back up and remove.
- Byte-identical unmanaged, nonsecret asset content: back up and adopt.
- Secret-bearing or mixed configuration: require the redacted structural/key-ownership comparison and an explicit adopted-key mapping.
- Unmanaged, unadopted, or drifted content: stop. There is no force path.

Backups preserve file type, modes, ownership where relevant, and symlink metadata. The backup root is atomically created in a host-local `0700` directory after refusing symlinks and verifying its owner. Secret-bearing backups are encrypted or remain in that protected host-local root.

The mutation journal contains only paths, file types, modes, hashes, backup references, and expected pre/post states. It never contains before/after fragments or credential-bearing bytes. The migration removes only exact legacy leaves and exact promptdeploy-owned fragments, including profile-local Claude entries, Codex base blocks, proven legacy hook declarations from the global `$CODEX_HOME/hooks.json`, and Droid `customModels`; it preserves unrelated global hook entries and all other content, stopping on drift or ambiguous ownership. After cleanup, a delegated Codex config-loading surface must prove the managed hook sentinel absent before the selected profile is enabled.

Activation is a two-phase cutover, not an atomicity claim. The old Home Manager generation, complete backup inventory, legacy manifests, and mutation journal are retained. On failure or rollback, the runbook reactivates the old generation and restores every removed/adopted whole leaf, legacy manifest, and mixed mutable file, then verifies path type, mode, and hash. Restore refuses to overwrite a path that no longer matches the journaled post-cutover state; such a path requires an explicit merge. Home Manager rollback alone is insufficient.

After a successful switch, the same generation is switched a second time. It must produce the same managed bytes, symlink targets, activation path, and store references without creating another backup or mutation journal entry.

## Shared NFS-home rollout rule

The shared work profile follows a stricter order because its home is shared while stores are not:

1. Pin one exact committed consumer revision and lock file.
2. Record the currently active old Home Manager generation. Realize, verify, and register a persistent host-local root for its complete closure on Andoria-08, Andoria-t2, Delphi-3bd4, and gpu-server.
3. Build the identical new shared Home Manager activation closure on all four machines.
4. Register a separate persistent host-local profile or GC root for the new closure under each machine's local Nix state, never beneath the shared home.
5. On every host, verify both old and new activation paths and all recursively referenced store paths exist locally; verify the new activation path is identical across hosts.
6. Only after all four verifications pass, activate the shared profile once from Andoria-08.
7. From each of the other three machines, verify managed links, parsable config, client launch, and the selected inventory without running another Home Manager activation.

Both closure roots remain on every host through the rollback window. No shared-home symlink is changed before all four stores are ready. Host-local runtime services continue to derive the actual short hostname when they start.

## Fleet rollout

Rollout proceeds only after migration parity and build validation:

1. Hera is the canary. Exercise every five-client contract, repeat the switch, and perform an explicit rollback/restore test.
2. Clio validates the dual-Claude, Codex, and OpenCode Darwin subset.
3. Vulcan validates personal Linux Claude/OpenCode selection and the omitted OpenCode default.
4. VPS validates the personal Claude-only subset.
5. The shared work home rolls out last using the four-host realization rule above.

Every host realizes state locally. There is no deployment SSH or rsync. The `drafts-hera` SSH MCP remains because it is an application runtime transport, not a deployment mechanism.

## Verification and acceptance

Implementation is acceptable only when current evidence proves all of the following:

### Evaluation and rendering

- Home Manager evaluation and activation packages build for Darwin, personal Linux ARM64, personal Linux x86_64 where applicable, and shared Linux x86_64.
- Every generated JSON and TOML document parses with an independent parser.
- Selector assertions and the selector coverage ledger cover every legacy target, filename tag, `only`, and `except` rule affecting the five managed clients, while explicitly recording untouched GPTel/git-ai exclusions.
- Exact catalog and destination inventories match expectations, with no duplicate paths or skill names.
- Every enabled profile has exactly one renderer.
- If a default model is emitted, the selected provider and model exist; a deliberately omitted default passes.

### Parity and content

- The frozen promptdeploy snapshot and Nix render trees agree for Claude, Codex, OpenCode, and Droid under the declared path/key mapping and reviewed semantic transformations.
- Pi's exact agent, prompt-template, shared-skill, Codex command/prompt projection, MCP, model, and extension inventory matches the explicit Pi contract.
- Ponytail's six selected skill trees match the pinned source; dormant hook/runtime/plugin payloads are absent and existing unrelated hooks/plugins remain unchanged.
- Commands and agents render valid client frontmatter and preserve bodies.
- Skill trees match their immutable sources and contain no deployment selectors.
- The `anvil-tools` tombstone removes the stale entry and creates no managed catalog item.

### Secret safety

- Evaluation succeeds with no secret sources available.
- Typed secret assertions reject literals in secret-bearing fields.
- Rendered output and closure scans contain references only, not resolved credentials.
- Ref and Context7 use header-based environment indirection.
- Bridge tests prove no credential appears in argv, URLs, files, derivation arguments, traces, or redacted errors.
- Migration comparison and backup handling do not expose live expanded values.

### Client contracts

- Each profile launches and sees the expected agents, commands, skills, MCP servers, hooks, marketplaces, providers, and models.
- Claude uses profile-local managed supplements while preserving mutable settings and project MCP behavior.
- Codex layers `nix-managed.config.toml` over intact trust and runtime state.
- OpenCode loads the complete owned document, including adopted static keys.
- Droid loads the managed settings overlay through its wrapper while preserving base UI/trust state.
- Pi discovers shared skills, prompt templates, subagents, models, the standard global MCP catalog, the settings-only mutable adapter override, and both pinned extensions natively; global override `mcpServers`/`imports` are rejected.
- Required secret references work from terminal, agent-deck, and applicable GUI launches without materializing values in Nix-owned state.
- Wrapper zero-artifact pass-through, complete-artifact injection, partial-artifact failure, conflicting-flag failure, and bypass behavior are tested for every injected client.
- Verification detects missing, replaced, or retargeted declarative links. Activation fails closed on such collisions instead of silently restoring or discarding client mutations.

### Activation, rollback, and topology

- Hera's second unchanged switch is a no-op at the managed-content boundary.
- An unchanged DEVONthink/iTerm2 model digest causes no synchronization; a changed digest updates exactly once after success.
- Migration preflight stops on unmanaged or drifted collisions.
- A forced activation failure restores the old Home Manager generation, every backed-up whole leaf and legacy manifest, and all journaled mixed files, then verifies their metadata and hashes.
- Each shared-home host realizes and retains both the old and identical new activation closures locally before Andoria-08 writes the shared profile.
- Every shared-home host passes post-activation local reference and client smoke checks, and both roots remain valid through rollback.

## Rollback and retirement

During rollout, rollback means reactivating the recorded previous Home Manager generation and restoring every backed-up whole leaf, legacy manifest, and journaled mixed file whose migration change is still present. The restore verifies metadata and hashes and refuses to overwrite later user changes. Backups and journals remain until every home has passed acceptance and the rollback window is explicitly closed.

After Hera, Clio, Vulcan, VPS, and the shared work home pass, promptdeploy is removed from the active workflow. For the five managed clients, Python deployment, manifests, ownership hashes, adoption/force/reconciliation behavior, settings merge machinery, bundle receipts, deployment SSH, and rsync do not survive in the Nix design. Excluded GPTel/git-ai artifacts and any archival manifests remain untouched but are no longer an active promptdeploy workflow. Runtime MCP transports such as `drafts-hera` remain.

The promptdeploy repository remains available, unchanged, as the migration oracle through the rollback window. It may then be archived. Client-owned auth, sessions, history, caches, trust state, UI state, and package selections remain mutable after retirement.

## Rejected alternatives

### Keep promptdeploy as a content-only flake input

This retains revision coupling and two competing sources of truth. It also reintroduces flake-input propagation problems for external consumers.

### Run promptdeploy's Python renderer during Nix builds

This preserves the machinery being retired and makes Python behavior part of evaluation/build reproducibility.

### Put everything in one `ai.nix`

A single giant file obscures immutable content and selector review. The chosen split keeps one integration module with small data and asset files, without inventing a framework.

### Rebuild promptdeploy's migration engine in Nix

Persistent adoption, force, reconciliation, and transaction machinery are unnecessary after cutover. A disposable, reviewed migration runbook is smaller and safer.

## Design invariants

- `/Users/johnw/src/nix` is the only desired-state source for fleet selection and file placement.
- `ai-nix` is the only packaging source for external resources required by all consumers.
- One managed path has one declarative writer.
- Mutable client state is never captured merely to simplify parity.
- No resolved secret enters a world-readable, persisted, logged, argv, or unapproved process channel; the sole bridge exception is its inherited environment, in-process header map, and outbound TLS request.
- No NFS-shared profile points at an unrealized local-store path.
- No runtime hostname decision for the shared work home trusts the configured Andoria-08 label.
- No deployment operation uses SSH or rsync.
- Implementation proceeds only under the recorded approval; Task 13 still requires its separate durable host-mutation and retirement authority.

## Design review record

Adversarial review materially changed the design before approval. It identified and corrected:

- The separate-store/shared-NFS activation hazard.
- The non-transitivity of flake inputs for flake-false consumers.
- Missing VPS and shared-host consumers.
- Over-broad ownership of mutable Claude, Codex, and Droid files.
- Droid's need for an explicit settings wrapper.
- Ref's query-string secret exposure.
- The direct Claude binary link that would bypass the wrapper.
- The absence of a direct Pi inventory.
- Migration overengineering and unsafe shared-home backup assumptions.
- The distinction between deployment SSH and legitimate runtime SSH.
- The need to keep digest-gated DEVONthink/iTerm2 synchronization.
- Complete rollback of whole leaves and confidential journal metadata.
- Dirty-source snapshotting and separate preview/live-drift oracles.
- Codex projections visible through Pi's shared skill root.
- Ponytail's static-skill boundary and exclusion of dormant runtime/plugin payloads.
- Explicit adoption of Droid's live `pal` entry.

This document incorporates those corrections and is the approved design. The user subsequently approved the active implementation objective on 2026-07-22, authorizing the reviewed implementation and ordinary branch publication through Task 12. The implementation plan remains the operational authority for sequencing and verification; Task 13 still requires its separate durable host-mutation and retirement record.
