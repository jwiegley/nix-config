---
title: Pi Coding Agent Extensions
aliases:
  - Pi Extension Inventory
  - Pi Packages in Use
tags:
  - pi
  - ai-agents
  - developer-tools
created: 2026-07-27
updated: 2026-09-01
pi-version: 0.84.4
---

# Pi Coding Agent Extensions

This note records the Nix-managed Pi estate: 27 gallery packages projected on every managed host, four separately deployed extensions, one generated loader, the rendered fleet profiles, and the immediate runtime companions. The Gallery registers 25 of those packages on Darwin and 23 on Linux; [Pi Lens][pi-lens] and [Pi Mem][pi-mem] are retained but are not registered on any managed profile. Versions below are the versions selected by the current Nix source.

The inventory includes generated ownership, model routing, MCP registration, and keybindings. Pi core facilities, built-in tool implementations, ordinary skill bodies, mutable user state, MCP tool-by-tool APIs, and transitive npm dependencies remain outside its scope. The `agent-resources` package also carries [`pi-openai-server-compaction`][pi-openai-server-compaction] for compatibility testing, but no managed Pi profile renders or loads it, so it is not part of this configured inventory.

## At a glance

This table lists extensions that are active on at least one managed Pi profile. The retained but inactive Gallery packages are listed separately below.

| Extension | Version | Principal purpose | Primary interface |
| --- | ---: | --- | --- |
| [Nix Gallery loader][nix-gallery-loader] | local | Compose the managed package gallery | automatic |
| [Fleet Theme][fleet-theme] | local | Discover and select the managed TUI theme | automatic |
| [`@realvendex/pi-loop`][pi-loop] | 1.0.2 | Repeat prompts under explicit stop conditions | `/loop` |
| [`pi-mcp-adapter`][pi-mcp-adapter] | 2.31.0 | Lazy, context-efficient MCP access | `mcp`, `/mcp` |
| [`@zenspc/pi-quiet`][pi-quiet] | 0.4.1 | Dense tool-result presentation | `/quiet` |
| [`pi-hashline-edit-pro`][pi-hashline-edit-pro] | 0.17.5 | Hash-anchored reads and replacements | `read`, `replace` |
| [`agent-cat-workflow`][agent-cat-workflow] | 0.1.0 | Discover, supervise, control, and resume typed agent-cat workflows | `/wf`, `agent_cat_workflow` |
| [`pi-smart-fetch`][pi-smart-fetch] | 0.3.17 | Browser-fingerprinted readable web fetching | `web_fetch`, `batch_web_fetch` |
| [`pi-smart-web-search`][pi-smart-web-search] | 0.4.0 | Ranked batch web discovery | `web_search` |
| [`@dietrichgebert/ponytail`][ponytail] | 4.9.0 | Minimal implementation discipline | `/ponytail` |
| [`pi-agent-browser-native`][pi-agent-browser-native] | 0.5.0 | Native Pi interface to `agent-browser` | `agent_browser` |
| [`pi-btw`][pi-btw] | 0.4.1 | Side conversations without disturbing the main turn | `/btw` |
| [`pi-copy-message`][pi-copy-message] | 2.1.0 | Search and copy raw session messages | `/copy-message`, `/copy-user` |
| [`pi-multi-pass`][pi-multi-pass] | 1.3.0 | Multiple OAuth accounts and failover pools | `/subs`, `/pool`, `/mp-preset` |
| [`pi-droid-sdk`][pi-droid-sdk] | 0.1.0 | Factory Droid models through the official Droid SDK and CLI | `/model`, `factory/*` |
| [`pi-provider-llama-swap`][pi-provider-llama-swap] | `57583beb` | Discover chat models from local llama-swap | `/model`, `llama-swap/*` |
| [`pi-provider-omlx`][pi-provider-omlx] | `57583beb` | Discover authenticated oMLX services selected for each host | `/model`, `omlx-hera/*`, `omlx-clio/*` |
| [`pi-rewind`][pi-rewind] | 0.5.0 | Conversation and file checkpoints | `/rewind` |
| [`pi-flag`][pi-flag] | 0.1.0 | Mark user or assistant messages significant for later model turns | `/flag` |
| [`pi-idle-check`][pi-idle-check] | 0.1.0 | Offer context-aware send, compact, or new-session choices after idle time | automatic |
| [`pi-trace-extension`][pi-trace] | 0.1.15 | Local execution traces and HTML reports | `/trace` |
| [`pi-markdown-preview`][pi-markdown-preview] | 0.15.0 | Terminal, browser, PDF, and artifact previews | `/preview`, `preview_export` |
| [`pi-caveman`][pi-caveman] | 1.0.8 | Compressed response style | `/caveman` |
| [`pi-rtk-optimizer`][pi-rtk-optimizer] | 0.9.0 | RTK command rewriting and output compaction | `/rtk` |
| [`pi-cymbal`][pi-cymbal] | 0.5.3 | Indexed, symbol-oriented code navigation | `cymbal_*` |
| [`pi-gpt-fast-mode`][pi-gpt-fast-mode] | 0.1.2 | Select OpenAI service tiers and hand preference to subagents | `/fast`, `--fast` |
| [`pi-subagents`][pi-subagents] | 0.58.0 | Focused child-agent delegation and orchestration | `subagent`, `/run` |
| [`@quintinshaw/pi-dynamic-workflows`][pi-dynamic-workflows] | 3.9.0 | JavaScript orchestration over parallel Pi subagents | `workflow`, `/workflows` |
| [`pi-goal-x`][pi-goal-x] | 0.30.5 | Durable goals and Sisyphus continuation | `/goal`, `get_goal` |
| [`pi-cache-optimizer`][pi-cache-optimizer] | 2.8.6 | Improve provider prompt-cache reuse and report cache statistics | `/cache-optimizer` |

### Packaged but inactive

These packages remain pinned, built, and present in the immutable Gallery projection, but their extension code is not imported or registered by any managed Pi profile.

| Retained package | Version | Remaining use |
| --- | ---: | --- |
| [`pi-lens`][pi-lens] | 4.0.1 | One packaged skill root exposing four [Lens][pi-lens] skills remains advertised, and Nix still renders the hidden [Lens][pi-lens] widget setting; [Lens][pi-lens] tools and commands are unavailable |
| [`@askjo/pi-mem`][pi-mem] | 1.2.0 | Projection only; no [Pi Mem][pi-mem] imports, tools, commands, or managed state activation |

The [Factory Droid SDK provider][pi-droid-sdk] is available and registered on every host. Darwin registers the [llama-swap provider][pi-provider-llama-swap] and both workstation endpoints from the [oMLX provider][pi-provider-omlx]. Vulcan registers only the remote `omlx-hera` endpoint; other Linux profiles retain the packages without registering local-provider endpoints. Local llama-swap remains loopback-only. Hera receives fixed `omlx-hera` overrides; Clio retains bounded bilateral discovery; and Vulcan uses bounded authenticated discovery from Hera. OpenRouter remains a native provider on every managed Pi profile and becomes available when that host has mutable OpenRouter authentication.

## Managed fleet configuration

The Hera, Clio, shared-work, VPS, and Vulcan Pi profiles are rendered by `~/src/nix/config/ai/renderers/pi.nix` into the active XDG profile at `~/.config/pi/agent`. Nix owns individual generated entries rather than mutable parent directories, preserving authentication, histories, settings, caches, and extension state while keeping the declarative surface collision-checked. Home Manager also owns the compatibility link `~/.pi -> ~/.config/pi`; activation refuses to replace a real legacy `~/.pi` tree or a wrong link. On Darwin only, activation performs one lock-scoped migration when the mutable global `enabledModels` list contains the retired `omlx/` provider identity, a known-stale exact oMLX reference, or the formerly managed `factory/*` wildcard. Legacy oMLX entries contribute matching local-first `omlx-hera/` and `omlx-clio/` identities except known-stale pairs; stale entries and the broad Factory wildcard are removed; and generated/current-provider collisions are deduplicated. Other entries, including duplicates, retain their order. Missing, empty, or unaffected scopes remain byte-for-byte untouched.

### Owned surface

| Surface | Current projection |
| --- | --- |
| Generated ownership | Individual leaves below `~/.config/pi/agent`, plus `~/.pi-lens/config.json` and the `~/.pi` compatibility link; Pi shares `~/.config/mcp/mcp.json` with Prime Agent |
| Extension entries | [Fleet Theme][fleet-theme], [Nix Gallery loader][nix-gallery-loader], [Pi Loop][pi-loop], [Pi MCP Adapter][pi-mcp-adapter], and [Quiet Display][pi-quiet] on every managed host; the Gallery loads [Agent-cat Workflows][agent-cat-workflow], [Significance Flags][pi-flag], [Idle Check][pi-idle-check], [GPT Fast Mode][pi-gpt-fast-mode], and the [Factory Droid SDK provider][pi-droid-sdk] everywhere; Darwin additionally loads loopback llama-swap and bilateral oMLX discovery, while Vulcan loads only remote `omlx-hera` discovery |
| Agent resources | 25 Nix-managed agent definitions |
| Prompt resources | 63 files: 61 command prompts and the `emacs` and `spanish` prompts |
| Skill resources | Shared catalog skills selected for Pi, plus five gallery package skill paths and one gallery prompt path advertised at runtime |
| Generated policy | `keybindings.json`, `models.json`, the GPT Fast Mode config, the managed theme, the hidden [Lens][pi-lens] widget setting, and the global MCP registry |
| Deliberately absent | No Pi-specific Nix settings file, hooks, marketplaces, or whole-directory ownership |

Shared skills remain in the common discovery estate rather than being copied into a private Pi skill tree. Their ownership is independent of Codex, so Pi-only hosts receive them too. Package skills supplied by [Lens][pi-lens], [BTW][pi-btw], [Subagents][pi-subagents], and [Dynamic Workflows][pi-dynamic-workflows] enter through the gallery loader.

### Model and routing policy

The generated model files deliberately emit no default model. Model selection remains mutable at session scope. Hera configures fixed `llama-swap` and `omlx-hera` overrides plus the Hermes route. Clio retains Hermes and bounded runtime discovery for `llama-swap`, `omlx-hera`, and `omlx-clio`, but emits no fixed local-provider override. Linux generates only the native remote-provider context overrides even though the complete extension package projection is present.

| Item | Current value |
| --- | --- |
| Hera provider surface | Gallery providers `factory`, `llama-swap`, `omlx-hera`, and `omlx-clio`; fixed `llama-swap` and `omlx-hera` model overrides; the `hermes` OpenAI-compatible provider; and native `openai-codex` and `openrouter` overrides |
| Clio provider surface | Gallery providers `factory`, `llama-swap`, `omlx-hera`, and `omlx-clio`, whose bounded discovery exposes only returned chat models; the `hermes` OpenAI-compatible provider; and native `openai-codex` and `openrouter` overrides. No fixed local model route is generated |
| Linux provider surface | Gallery provider `factory` plus native `openai-codex` and `openrouter` overrides; the llama-swap and oMLX discovery adapters are packaged but not registered automatically |
| Hermes route | `hermes/hermes-agent` at `https://hermes.vulcan.lan/v1`; opt-in, with its bearer credential resolved from the Home Manager-configured password store and GnuPG home only when a request uses the provider; stale inherited `GPG_TTY` state is discarded before lookup, isolating credential resolution from Agent Deck/tmux terminal state; Pi session-affinity headers are enabled for stable upstream routing |
| Native overrides | Managed native-provider model IDs, context windows, and output limits come from `config/ai/models.nix` |
| GPT Fast Mode | Session-only and disabled by default; `priority` tier with status indicator; supports the GPT-5.4/5.5 keys plus the unsuffixed and `luna`/`terra`/`sol` GPT-5.6 keys for both `openai` and `openai-codex` |
| Hera managed oMLX models | `omlx-hera/Qwen3.8-27B-oQ4e-mtp` and `omlx-hera/DeepSeek-V4-Flash-0731-MXFP4-MLX` are pinned to 262,144 context and 81,920 output tokens. Qwen remains text-only and non-reasoning; its override carries the local Qwen chat-template compatibility flags |
| Hera DeepSeek thinking | `omlx-hera/DeepSeek-V4-Flash-0731-MXFP4-MLX` exposes only `off` and `max`; `max` uses Pi's `deepseek` format and sends `thinking.type="enabled"` plus top-level `reasoning_effort="max"`. oMLX's model-level Enable Thinking setting must also be active |
| Voice-agent routing aliases | The managed registry defaults to `gpt sol` on `hera`; maps `nix`, `ares`, and `agent-cat` to their Hera checkouts; maps `tron` to `~/tron/main` through the configured `andoria-08` Agent Deck remote; and retains `~/src/<project>` discovery on Hera |
| Discovery | `llama-swap` queries its loopback `/models` endpoint; `omlx-hera` and `omlx-clio` query their respective authenticated TLS endpoints. Registration and `/model` refreshes use a 2.5-second per-request bound, and a failed refresh retains the last good list. Explicit type, modality, and capability metadata determines model behavior, while missing or unknown metadata falls back to text-only, non-reasoning chat with 262,144 context and 65,536 output. Hera's fixed Qwen and DeepSeek overrides replace that output fallback with 81,920 |
| Request and credential policy | Both Darwin profiles declare a 7,200-second request and stream-idle transport budget for all three local discovery providers in `models.json`; the ordinary global timeout remains 300 seconds. For each provider-specific runtime environment variable, Pi prefers an explicit value, then the matching login-Keychain item, then the services' non-secret compatibility sentinel. The Factory provider uses the launching process's `FACTORY_API_KEY` or Pi's mutable `factory` login, without rendering any credential into Nix-owned files |

The generated `models.json` owns compatibility, context, and output-limit overrides; on Hera it owns fixed `llama-swap` and `omlx-hera` overrides, while both Darwin profiles own the Hermes route. The exact managed Qwen override pins its text-only, non-reasoning shape and local chat-template compatibility without duplicating the discovered provider. The DeepSeek override marks the sparse discovery record as reasoning-capable and maps Pi's `max` level to the top-level DeepSeek request fields accepted by oMLX; the voice-agent `deepseek` alias selects that level. Image input is not advertised until an exact model-and-service probe establishes it. Hermes uses a runtime command reference, and each [oMLX provider][pi-provider-omlx] first uses its own explicit or Keychain-backed runtime environment value. When neither exists, the Pi wrapper supplies the non-secret workstation sentinel accepted by the local services; no secret credential is copied into the Nix store. The Darwin-registered provider extensions own runtime model discovery. No generated model is Pi's default.

### MCP registry

Nix generates the shared, catalog-selected registry at `~/.config/mcp/mcp.json`; [Pi MCP Adapter][pi-mcp-adapter] exposes it lazily and renders compact footer status.

| Profiles | Servers |
| --- | --- |
| Hera and Clio | `devonthink`, `drafts`, `pal`, `searxng`, `sequential-thinking`, `stock-trader` |
| shared-work and VPS | `pal`, `sequential-thinking` |
| Vulcan | `pal`, `searxng`, `sequential-thinking` |

Credential-bearing values are environment references rather than literal secrets. The mutable `~/.config/pi/agent/mcp.json` may retain adapter state, but Nix preflight forbids `mcpServers` and `imports` there so that it cannot shadow the generated registry.

PAL may initialize and expose its provider-independent discovery tools without credentials. Its model-backed tools require at least one referenced provider variable to be present in the launching client's environment; the generated registry carries variable names, never their values. Nix limits PAL's stderr logging to warnings and errors and disables its upstream persistent file logging. The packaged server does not expose upstream `clink`: a same-UID nested CLI could inspect PAL's multi-provider ancestor environment and mutable client hooks, so filtering only the child environment would not provide a credential boundary.

### Keybindings

The generated keymap retains the ordinary keys and adds Emacs-style editing:

- cursor movement: Up or `Ctrl-P`, Down or `Ctrl-N`, Left or `Ctrl-B`, and Right or `Ctrl-F`;
- word movement: `Alt-Left` or `Alt-B`, and `Alt-Right` or `Alt-F`;
- deletion: Delete or `Ctrl-D`, and Backspace or `Ctrl-H`;
- newline: `Shift-Enter` or `Ctrl-J`; and
- model selection: `Ctrl-L`, with forward and backward model cycling disabled.

## Deployment and integration layer

### [Nix Gallery loader][nix-gallery-loader]

**Version:** local · **Links:** Nix authority: `~/src/nix/packages/pi-gallery/` · deployed leaf: `~/.config/pi/agent/extensions/nix-gallery/index.ts`

The [Nix Gallery loader][nix-gallery-loader] projects the complete managed package set on every host. It imports and registers extensions in deterministic order, except that Linux does not automatically import the [llama-swap provider][pi-provider-llama-swap] or [oMLX provider][pi-provider-omlx], and [Pi Lens][pi-lens] and [Pi Mem][pi-mem] are temporarily excluded on every platform. All 26 immutable package paths, including [Lens][pi-lens], [Pi Mem][pi-mem], and the separately loaded [Pi Loop][pi-loop], remain available. Before registration the loader suppresses [Ponytail][ponytail]'s footer status, disables [Lens][pi-lens] runtime installers, and enforces model-only [Pi Droid SDK][pi-droid-sdk] operation by setting autonomy off and disabling the Pi tool bridge. It is infrastructure rather than a public Pi package.

**Basic usage.** No direct command is required. Run `/reload` after activating a new Nix generation, or start a fresh Pi process, to load the current gallery. The loader itself owns no mutable state.

### [Fleet Theme][fleet-theme]

**Version:** local · **Links:** extension: `~/src/nix/config/ai/extensions/fleet-theme/index.ts` · theme: `~/src/nix/config/ai/themes/dark-tool-backgrounds.json`

[Fleet Theme][fleet-theme] advertises the immutable `dark-tool-backgrounds` theme during resource discovery and selects it when an interactive TUI session begins. The palette gives pending, successful, and failed tool calls distinct dark backgrounds while leaving headless sessions unchanged.

**Basic usage.** The extension is automatic and has no command. Run `/reload` or begin a fresh Pi process after activation; the theme is selected at the next interactive session start.

### [Pi Loop][pi-loop]

**Version:** 1.0.2 · **Links:** [Pi Packages](https://pi.dev/packages/@realvendex/pi-loop) · [Home](https://github.com/ZachDreamZ/pi-loop#readme) · [GitHub](https://github.com/ZachDreamZ/pi-loop)

[Pi Loop][pi-loop] repeats a prompt under bounded iteration, timeout, convergence, text, regular-expression, command, and error stop conditions. It supports prompt templating, lifecycle hooks, run logs, named presets, a live TUI panel, and completion notifications. Nix deploys its entry directly from an immutable support package rather than loading it through the managed gallery.

**Basic usage.** Run `/loop "prompt" --max 5` for confirmed rounds, or add `--yes` only when unattended execution and automatic approval of confirmations are intended. Use `/loop stop` to cancel after the current iteration, `/loop preview` to inspect a resolved run without starting it, and `/loop list`, `/loop logs`, or `/loop show` for retained state under `~/.pi/loops/`.

### [Pi MCP Adapter][pi-mcp-adapter]

**Version:** 2.31.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-mcp-adapter) · [Home](https://github.com/nicobailon/pi-mcp-adapter#readme) · [GitHub](https://github.com/nicobailon/pi-mcp-adapter)

[Pi MCP Adapter][pi-mcp-adapter] exposes Model Context Protocol servers through one compact proxy tool instead of placing every remote tool schema in the model context. Servers are lazy by default; metadata, instructions, resources, and prompts are cached; large results are guarded; selected tools may be promoted directly; and MCP Apps and remote OAuth retain explicit interactive surfaces.

**Basic usage.** Open `/mcp` for status and direct-tool control, `/mcp setup` for guided configuration, and `/mcp-auth` for OAuth. From an agent turn, use `mcp({ search: "term" })`, inspect a candidate with `mcp({ describe: "tool" })`, read server guidance with `mcp({ instructions: "server" })`, and call it with `mcp({ tool: "tool", args: { ... } })`. `/mcp enable` and `/mcp disable` write only project-local overrides and require `/reload`; reconnects and direct-tool changes refresh the current session.

### [Quiet Display][pi-quiet]

**Version:** 0.4.1 · **Links:** [Pi Packages](https://pi.dev/packages/@zenspc/pi-quiet) · [Home](https://github.com/zenspc/pi-extensions/tree/master/packages/pi-quiet#readme) · [GitHub](https://github.com/zenspc/pi-extensions)

[Quiet Display][pi-quiet] changes presentation, not execution. It renders built-in and foreign tool activity as dense verb-first rows, folds adjacent successful operations of the same kind, suppresses live stdout while a tool is running, and preserves Pi's stock expanded display for inspection and failures.

**Basic usage.** [Quiet][pi-quiet] mode is enabled by default. Use `/quiet`, `/quiet on`, `/quiet off`, or `/quiet status`. The sticky preference is stored in `~/.config/pi/agent/extensions/quiet.json`.

## Editing, context, and session control

### [Hashline Edit Pro][pi-hashline-edit-pro]

**Version:** 0.17.5 · **Links:** [Pi Packages](https://pi.dev/packages/pi-hashline-edit-pro) · [Home](https://github.com/YuGiMob/pi-hashline-edit-pro#readme) · [GitHub](https://github.com/YuGiMob/pi-hashline-edit-pro)

[Hashline Edit Pro][pi-hashline-edit-pro] replaces ambiguous text matching with stable, short anchors attached to every line returned by `read`. The corresponding `replace` tool addresses an inclusive anchor range, which makes edits explicit and guards against changing stale or unexpectedly modified text.

**Basic usage.** Read the relevant file, retain the three-character hashes, then call `replace` with `hash_range_inclusive` and literal replacement lines. `/toggle-replace-mode` changes between bulk and flat replacement forms; `/toggle-auto-read` controls automatic anchor refresh after writes and replacements.

### [Ponytail][ponytail]

**Version:** 4.9.0 (`4.9.0+2ed6c52` in the Nix projection) · **Links:** [Pi Packages](https://pi.dev/packages/@dietrichgebert/ponytail) · [Home](https://github.com/DietrichGebert/ponytail) · [GitHub](https://github.com/DietrichGebert/ponytail)

[Ponytail][ponytail] imposes a minimal implementation discipline: question speculative work, reuse the existing codebase, prefer the standard library and native platform, and stop at the first simple solution that satisfies the actual requirement. Its purpose is to reduce avoidable code rather than compress prose alone.

**Basic usage.** Use `/ponytail off|lite|full|ultra`, `/ponytail status`, or `/ponytail default <mode>`. The companion commands `/ponytail-review`, `/ponytail-audit`, `/ponytail-debt`, `/ponytail-gain`, and `/ponytail-help` invoke the corresponding skills.

### [Rewind][pi-rewind]

**Version:** 0.5.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-rewind) · [Home](https://arpagon.github.io/pi-rewind) · [GitHub](https://github.com/arpagon/pi-rewind)

[Pi Rewind][pi-rewind] records per-tool checkpoints so conversation state, file changes, or both may be returned to an earlier point. Restoration is bounded to the recorded session history and retains a redo stack, making exploratory work recoverable without a broad Git reset.

**Basic usage.** Run `/rewind` and choose the checkpoint and restoration scope. In interactive sessions, `Esc Esc` opens the quick files-only rewind.

### [Significance Flags][pi-flag]

**Version:** 0.1.0, pinned at `520be58` · **Links:** [Home](https://github.com/jwiegley/pi-flag#readme) · [GitHub](https://github.com/jwiegley/pi-flag)

[Pi Flag][pi-flag] lets you mark complete user prompts or visible assistant responses as significant. It restores the session-scoped selections from Pi's journal and losslessly projects them as a deterministic focus block on later user-input model runs. It retains no separate mutable state, and selecting an image-bearing prompt is rejected because it cannot be reproduced losslessly in a text system prompt.

**Basic usage.** Run `/flag`, select a user or assistant message, and confirm. The first selection requires acknowledgement that the full flagged text will be resent on subsequent user-input runs in the session; start a fresh Pi process or run `/reload` after activation.

### [Idle Check][pi-idle-check]

**Version:** 0.1.0, pinned at `407fcd9` · **Links:** [Home](https://github.com/jwiegley/pi-idle-check#readme) · [GitHub](https://github.com/jwiegley/pi-idle-check)

[Idle Check][pi-idle-check] intercepts only interactive TUI input after a session with prior assistant activity has been continuously idle for strictly more than 180,000 milliseconds and known context use reaches its configured threshold (5% by default). Idle begins at `agent_settled`; active model, tool, retry, compaction, steering, follow-up, RPC, print, JSON, and extension-injected input never opens its selector. Pre-threshold terminal activity restarts the interval, while activity after the threshold latches the decision. Resume seeding uses at most 64 parent-entry point reads; if that bounded tail contains no completed assistant response, it fails closed.

The selector reports exact whole-second idle duration, then accepts **Enter — send**, **`c` — compact + send**, **`C` — new session + send**, or **Escape/Ctrl-C — cancel**. New session starts blank and replays the exact prompt with normal skill and prompt-template expansion. Compaction withholds the exact text and images until Pi's manual compaction succeeds, then replays once. Cancellation and failures send nothing and restore text without overwriting a newer draft. The extension owns only an internal handoff command; it stores no mutable configuration, session record, or direct network client.

**Basic usage.** No command is required. After activation, start a fresh Pi process or run `/reload`; the next qualifying interactive prompt opens the selector automatically.

### [Pi Mem][pi-mem]

**Version:** 1.2.0 · **Links:** [Pi Packages](https://pi.dev/packages/@askjo/pi-mem) · [Home](https://github.com/jo-inc/pi-mem#readme) · [GitHub](https://github.com/jo-inc/pi-mem)

When registered, [Pi Mem][pi-mem] maintains explicit, user-directed memory as plain Markdown. `MEMORY.md` holds durable facts and decisions, dated files hold daily notes, `notes/` holds named topics, and `SCRATCHPAD.md` holds a checklist. Writes and mutating scratchpad actions require an explicit user request. While active, it injects selected memory, recent daily logs, and recent catchup indexes into each agent turn, so the chosen model provider receives that content along with the rest of the prompt. [Pi Mem][pi-mem] does not supply session-derived compaction or a recall tool.

The managed package keeps its dashboard summary local instead of making upstream's automatic secondary model request. It reads recent Pi session titles and costs for the local dashboard, but does not send that inventory to a separate summarizer. Its mutable root is logically `~/.pi/agent/memory` and therefore resolves through the managed compatibility link to `~/.config/pi/agent/memory`; `PI_MEMORY_DIR` may select another root. Configured state directories are created or tightened to mode 0700, and files [Pi Mem][pi-mem] creates or replaces use mode 0600. File updates reject symbolic-link leaves, replace whole files atomically, and serialize read-modify-write operations across Pi processes. Stale file locks are reclaimed only when a same-host owner is proven to have exited; foreign-host, live-owner, malformed, and in-progress-recovery locks remain in place, and writes fail closed. Nix does not own or delete this state. The managed package deliberately removes upstream Git autocommit: `PI_AUTOCOMMIT` and the legacy `.pi-mem.json` `autocommit` field are inert. Memory history therefore requires an explicit private Git workflow outside [Pi Mem][pi-mem], operated manually or by a separate external tool.

[Pi Mem][pi-mem] is currently retained as a managed package in the Gallery projection but is not imported or registered by the generated Gallery. This reversible state removes its synchronous startup scan without deleting its mutable memory.

**Basic usage.** [Pi Mem][pi-mem] tools are unavailable while automatic registration is disabled. Restoring [Pi Mem][pi-mem] to the generated Gallery restores `memory_write`, `memory_read`, `memory_search`, and `scratchpad`; start a fresh Pi process or run `/reload` after activation to register them.

### [Trace][pi-trace]

**Version:** 0.1.15 · **Links:** [Pi Packages](https://pi.dev/packages/pi-trace-extension) · [Home](https://github.com/npxcnency-ux/pi-trace-extension) · [GitHub](https://github.com/npxcnency-ux/pi-trace-extension)

[Pi Trace][pi-trace] records the execution structure of each session—model requests, steps, tool calls, timings, usage, and outcomes—as local JSONL, then renders a self-contained HTML report. The Nix package sanitizes persisted values under secret-like key names, including common authorization, API-key, AWS-secret, and cookie fields; bounds nesting; truncates long strings; flushes pending events before rendering; supplies an immutable Python renderer; and handles unavailable browser launchers without crashing Pi. [Trace][pi-trace] directories are created with mode 0700 and their JSONL and HTML files with mode 0600.

**Basic usage.** Tracing starts automatically. Run `/trace` for the current session or `/trace all` for the cross-session dashboard. Files live below `~/.pi/agent/traces/`. They still contain prompts, tool inputs and results, file paths, and model data; treat them as sensitive. The extension has no retention or rotation policy.

### [Cache Optimizer][pi-cache-optimizer]

**Version:** 2.8.6 · **Links:** [Pi Packages](https://pi.dev/packages/pi-cache-optimizer) · [Home](https://github.com/jiangge/pi-cache-optimizer) · [GitHub](https://github.com/jiangge/pi-cache-optimizer)

[Pi Cache Optimizer][pi-cache-optimizer] keeps stable prompt content near the front, compresses volatile skill listings, supplies conservative OpenAI-compatible cache keys, diagnoses proxy compatibility, and reports local cache statistics. It is registered last so its prompt hook observes the gallery's final prompt shape.

**Basic usage.** Use `/cache-optimizer doctor`, `/cache-optimizer stats`, `/cache-optimizer compat`, or the interactive `/cache-optimizer` menu. `/cache-optimizer enable|disable` affects the current process; `/cache-optimizer config footer-mode ...` and `/cache-optimizer reset` manage mutable extension state. `/cache-optimizer fix` is deliberately disabled because `models.json` is Nix-managed—change `config/ai` and activate a new generation instead.

### [Caveman][pi-caveman]

**Version:** 1.0.8 · **Links:** [Pi Packages](https://pi.dev/packages/pi-caveman) · [Home](https://github.com/jonjonrankin/pi-caveman) · [GitHub](https://github.com/jonjonrankin/pi-caveman)

[Pi Caveman][pi-caveman] appends a response-style instruction that reduces output prose while retaining technical content. It is a communication control rather than an implementation policy; this distinguishes it from [Ponytail][ponytail], which governs the amount and shape of code produced.

**Basic usage.** Use `/caveman` to toggle the default full mode, or select `/caveman lite|full|ultra|wenyan-lite|wenyan|wenyan-ultra|micro`. `/caveman config` controls the default level and status indicator; `/caveman off` disables it.

## Research, code intelligence, and browsers

### [Smart Fetch][pi-smart-fetch]

**Version:** 0.3.17 · **Links:** [Pi Packages](https://pi.dev/packages/pi-smart-fetch) · [Home](https://github.com/Thinkscape/agent-smart-fetch#readme) · [GitHub](https://github.com/Thinkscape/agent-smart-fetch)

[Pi Smart Fetch][pi-smart-fetch] retrieves readable web content with browser-like TLS and HTTP fingerprints, Defuddle extraction, bounded batch concurrency, metadata, redirects, and streamed binary downloads. It does not execute page JavaScript or bypass interactive login challenges.

**Basic usage.** Use `web_fetch` for one URL and `batch_web_fetch` for several. Choose `markdown` for readable content or `html`, `text`, `json`, or `raw` when downstream processing requires another representation.

### [Smart Web Search][pi-smart-web-search]

**Version:** 0.4.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-smart-web-search) · [Home](https://github.com/joematthews/pi-smart-web-search#readme) · [GitHub](https://github.com/joematthews/pi-smart-web-search)

[Pi Smart Web Search][pi-smart-web-search] owns the `web_search` tool. It accepts up to six focused queries, returns ranked links and snippets, and directs the agent to [Smart Fetch][pi-smart-fetch] for full pages.

**Basic usage.** Call `web_search` with a `searches` array, then read selected results with `web_fetch` or `batch_web_fetch`. Nix does not override `smartWebSearch.resultsPerQuery`, so its managed value is the package default of five; mutable settings may select one to ten.

### [Lens][pi-lens]

**Version:** 4.0.1 · **Links:** [Pi Packages](https://pi.dev/packages/pi-lens) · [Home](https://github.com/apmantza/pi-lens#readme) · [GitHub](https://github.com/apmantza/pi-lens)

[Pi Lens][pi-lens] combines language-server diagnostics, formatters, linters, structural scanners, complexity checks, symbol indexing, and edit-read guards. Its indexed tools provide a narrow discovery funnel—search for likely modules, inspect an outline, then read the exact symbol—before resorting to broad file reads.

[Pi Lens][pi-lens] is currently retained as a managed package and projected resource but is not imported or registered by the generated Gallery. Its packaged skill root continues to expose four [Lens][pi-lens] skills through the Gallery, and Nix still renders the hidden [Lens][pi-lens] widget setting. This reversible state isolates the extension's eager startup cost without removing those resources.

**Basic usage.** [Lens][pi-lens] tools and commands are unavailable while automatic registration is disabled. Restoring [Lens][pi-lens] to the generated Gallery restores `symbol_search`, `module_report`, `read_symbol`, `lsp_diagnostics`, `lens_diagnostics`, `/lens-health`, `/lens-tools`, `/lens-tdi`, and `/lens-map`. Runtime tool installation remains disabled by the Nix policy.

### [Agent Browser Native][pi-agent-browser-native]

**Version:** 0.5.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-agent-browser-native) · [Home](https://github.com/fitchmultz/pi-agent-browser-native#readme) · [GitHub](https://github.com/fitchmultz/pi-agent-browser-native) · [agent-browser](https://github.com/vercel-labs/agent-browser)

[Pi Agent Browser Native][pi-agent-browser-native] presents `agent-browser` as the `agent_browser` Pi tool. It supports live browsing, semantic locators, multi-step jobs, screenshots, extraction, QA presets, authenticated browser profiles, and Electron application control while retaining explicit stopping points before consequential submissions.

**Basic usage.** Follow the stable sequence `open` → interactive snapshot → action by current reference → new snapshot. Use the `job` input for bounded multi-step work, `qa` for page assertions and diagnostics, and `electron` only for desktop applications. The managed runtime companion is `agent-browser` 0.34.0.

### [RTK Optimizer][pi-rtk-optimizer]

**Version:** 0.9.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-rtk-optimizer) · [Home](https://github.com/MasuRii/pi-rtk-optimizer#readme) · [GitHub](https://github.com/MasuRii/pi-rtk-optimizer) · [RTK home](https://www.rtk-ai.app) · [RTK GitHub](https://github.com/rtk-ai/rtk)

[Pi RTK Optimizer][pi-rtk-optimizer] delegates shell-command rewrites to RTK—Rust Token Killer—and compacts selected tool output before it enters the model context. Test, build, Git, lint, and search output receive specialized treatment; lossy source-read compaction remains disabled by default so anchored edits retain exact source lines.

**Basic usage.** Use `/rtk` for the settings panel, `/rtk verify` to confirm the executable, `/rtk show` for current policy, and `/rtk stats` for session savings. The Nix profile supplies RTK 0.44.0 as `rtk` on `PATH`.

### [Cymbal][pi-cymbal]

**Version:** 0.5.3 · **Links:** [Pi Packages](https://pi.dev/packages/pi-cymbal) · [Home](https://github.com/raphapr/pi-cymbal#readme) · [GitHub](https://github.com/raphapr/pi-cymbal) · [Cymbal home](https://chain.sh/cymbal/) · [Cymbal GitHub](https://github.com/1broseidon/cymbal)

[Pi Cymbal][pi-cymbal] exposes Cymbal's local tree-sitter and SQLite index as agent-native code navigation. Its tools cover repository maps, structural summaries, symbol and text search, outlines, exact source retrieval, references, impact, imports, implementations, changed symbols, symbol diffs, guided investigations, call traces, and context bundles.

**Basic usage.** Begin unfamiliar work with `cymbal_map` or `cymbal_structure`, then narrow through `cymbal_search`, `cymbal_outline`, and `cymbal_show`. Use `cymbal_refs`, `cymbal_impact`, `cymbal_changed`, or `cymbal_diff` before a refactor. `/cymbal` shows or changes session guidance settings. The Nix profile supplies Cymbal 0.14.0.

## Rendering and previews

### [Markdown Preview][pi-markdown-preview]

**Version:** 0.15.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-markdown-preview) · [Home](https://github.com/omaclaren/pi-markdown-preview#readme) · [GitHub](https://github.com/omaclaren/pi-markdown-preview)

[Pi Markdown Preview][pi-markdown-preview] renders assistant responses and local Markdown, LaTeX, source, and diff files in the terminal or browser, and exports PDF, HTML, or PNG artifacts. It supports syntax highlighting, mathematical notation, Mermaid diagrams, local images, response selection, and Pi-theme-aware styling.

**Basic usage.** Run `/preview` for the latest response, `/preview <path>` for a file, `/preview-browser` for HTML, and `/preview-pdf` for PDF output. The `preview_export` tool writes artifacts without requiring an interactive preview. Nix supplies the Puppeteer closure; browser rendering uses an installed Chromium-based browser or `PUPPETEER_EXECUTABLE_PATH`. Pandoc and XeLaTeX support document and PDF rendering.

## Models and conversational control

### [GPT Fast Mode][pi-gpt-fast-mode]

**Version:** 0.1.2, pinned at `2ac61e0` · **Links:** [Pi Packages](https://pi.dev/packages/pi-gpt-fast-mode) · [Home](https://github.com/devwithpug/pi-gpt-fast-mode#readme) · [GitHub](https://github.com/devwithpug/pi-gpt-fast-mode)

[GPT Fast Mode][pi-gpt-fast-mode] requests OpenAI's `priority`, `flex`, `default`, or `auto` service tier through Pi's `before_provider_request` hook. Nix manages only `~/.config/pi/agent/extensions/pi-gpt-fast-mode/config.json`: persistence and desired state are disabled, the initial tier is `priority`, the indicator uses footer status, and the exact twelve-model allowlist covers GPT-5.4/5.5 plus the unsuffixed and `luna`/`terra`/`sol` GPT-5.6 keys for both `openai` and `openai-codex`. Unsupported models suppress `service_tier` without clearing the desired preference. `PI_GPT_FAST_MODE` hands that preference to child Pi processes, which apply it only when their own model is supported. No credential or mutable session state enters the Nix store.

**Basic usage.** Run `/fast` to toggle the selected tier, `/fast priority|flex|default|auto` to select and enable one, `/fast off` to disable, or `/fast status` to inspect desired versus active state. `pi --fast` requests priority at startup. Service-tier availability, latency, and billing remain controlled by OpenAI and the account; installation and local verification do not send a paid request.

### [Goal X][pi-goal-x]

**Version:** 0.30.5 · **Links:** [Pi Packages](https://pi.dev/packages/pi-goal-x) · [Home](https://github.com/tmonk/pi-goal-x#readme) · [GitHub](https://github.com/tmonk/pi-goal-x)

[Pi Goal X][pi-goal-x] persists explicit objectives, lifecycle and task state, usage, ordered Sisyphus continuation, and a bounded append-only event ledger. Goals can pause, resume, be audited before completion, retain compact task and recent-ledger guidance across context compaction, retry transient network interruptions, and consult an optional blocker Oracle without restating the objective in the footer.

**Basic usage.** Use `/goal` or `/sisyphus` to discuss and confirm a new objective; `/goal-direct` and `/sisyphus-direct` bypass discussion when the objective is already final. `/goal-list` lists open goals, `/goal-status` displays the focused goal, and `get_goal` exposes it to the agent. Use `/goal-clear` for user-owned abandonment and `/goal-cancel` to discard an unconfirmed draft; the remaining commands and phase-specific tools govern selection, pause, resume, recovery, and completion. Start a fresh Pi session after activation.

### [Subagents][pi-subagents]

**Version:** 0.58.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-subagents) · [Home](https://github.com/nicobailon/pi-subagents#readme) · [GitHub](https://github.com/nicobailon/pi-subagents)

[Pi Subagents][pi-subagents] delegates focused work to child Pi sessions without replacing the parent as orchestrator. It supports single foreground and asynchronous runs, scripted sequential and parallel composition, fresh or forked context, fleet status, steering, and supervisor communication.

Seven builtin definitions—delegate, gpt-pro, oracle, researcher, reviewer, scout, and worker—ship with the extension; `advisor` remains an alias for `oracle`. The `gpt-pro` definition requires a separately registered Surf `surf-oracle` external-job provider, which the managed fleet does not configure, so it is discoverable but cannot run from Nix configuration alone. The Nix-managed baseline adds twenty-five user definitions without collisions, accounting for thirty-two definitions before mutable package, user, or project definitions are considered. Live discovery may therefore report a larger total without changing Nix ownership.

**Basic usage.** Ask naturally for `reviewer`, `oracle`, `scout`, or `worker`, or use `/run` for a single child. Use packaged prompt shortcuts such as `/parallel-review` and `/review-loop`, or call `subagent` with `workflowScript` for coordinated multi-agent work. Use `/subagents-doctor` to check setup and `/subagents-fleet` for active work. The watchdog remains opt-in.

### [Dynamic Workflows][pi-dynamic-workflows]

**Version:** 3.9.0 · **Links:** [Pi Packages](https://pi.dev/packages/@quintinshaw/pi-dynamic-workflows) · [Home](https://github.com/QuintinShaw/pi-dynamic-workflows#readme) · [GitHub](https://github.com/QuintinShaw/pi-dynamic-workflows)

[Pi Dynamic Workflows][pi-dynamic-workflows] builds JavaScript orchestration over [Pi Subagents][pi-subagents]. A workflow may compose `agent()`, `parallel()`, and `pipeline()` calls, run in the background, retain resumable run state, isolate work in Git worktrees, or invoke the built-in deep-research, adversarial-review, code-review, multi-perspective, and codebase-audit patterns.

**Basic usage.** Use the `workflow` tool only after explicit opt-in: a direct request to run or fan out a workflow, the bounded word `workflow` or `workflows`, or `/workflows run <prompt>`. The keyword authorizes orchestration but does not force it. Open `/workflows` to inspect and control runs, or use `workflow_control` for programmatic list, status, pause, resume, and stop actions.

### [BTW][pi-btw]

**Version:** 0.4.1 · **Links:** [Pi Packages](https://pi.dev/packages/pi-btw) · [Home](https://github.com/dbachelder/pi-btw#readme) · [GitHub](https://github.com/dbachelder/pi-btw)

[Pi BTW][pi-btw] creates a focused side conversation while the main session remains intact. A thread may inherit the main context or begin as a contextless tangent; its result may remain private, be saved as a visible note, or be injected into the main conversation in full or summarized form.

**Basic usage.** Use `/btw <question>`, `/btw:new`, or `/btw:tangent`; use `/btw:inject` or `/btw:summarize` to return useful findings to the principal session. `/btw:model` and `/btw:thinking` control thread-specific inference settings. While the [BTW][pi-btw] overlay is focused, the first Escape closes it without pausing an active [Goal X][pi-goal-x] goal; a subsequent Escape retains [Goal X][pi-goal-x]'s normal pause behavior.

### [Copy Message][pi-copy-message]

**Version:** 2.1.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-copy-message) · [Home](https://github.com/fitchmultz/pi-copy-message#readme) · [GitHub](https://github.com/fitchmultz/pi-copy-message)

[Pi Copy Message][pi-copy-message] opens a searchable, keyboard-driven picker over raw session messages, avoiding terminal wrapping and rendered TUI artifacts. It can filter by role or text, include metadata, and copy user, assistant, tool, or bash messages. The Nix package delegates copying to Pi's portable clipboard layer, including its terminal fallback for remote sessions.

**Basic usage.** Use `/copy-message` for the interactive picker, `/copy-message latest` for the newest message visible under the default filters (falling back to the newest copyable message), or `/copy-user` for the most recent user message containing text. Add `--with-meta` to prefix the copied text with its role and displayed local time.

### [llama-swap Provider][pi-provider-llama-swap]

**Version:** `57583beb` · **Links:** Nix adapter: `~/src/nix/packages/pi-gallery/providers/pi-provider-llama-swap.ts` · [upstream source](https://github.com/gaurav-321/pi-local-llm)

The fleet-packaged [llama-swap provider][pi-provider-llama-swap] is a reviewed Nix derivative of [`pi-local-llm`][pi-local-llm]. Darwin registers it automatically; Linux retains the package without doing so. At registration and on an explicit `/model` refresh it queries the loopback llama-swap service, filters non-chat and non-text models, derives modality and reasoning support from model metadata, and registers the surviving models through Pi's OpenAI Completions interface. A failed initial discovery emits a warning; a later refresh failure is reported by Pi while retaining the last good model list.

**Basic usage.** On Darwin, keep the Nix-managed `org.nixos.llama-swap` launch agent available, then open `/model` to refresh and select a discovered `llama-swap/*` model. Managed Linux profiles provide no maintained local-provider loading path. A custom deployment must supply its own trusted service and loader that passes a validated typed endpoint projection to the adapter; loading the adapter directly without that projection is intentionally inert.

### [oMLX Provider][pi-provider-omlx]

**Version:** `57583beb` · **Links:** Nix adapter: `~/src/nix/packages/pi-gallery/providers/pi-provider-omlx.ts` · [upstream source](https://github.com/gaurav-321/pi-local-llm)

The fleet-packaged [oMLX provider][pi-provider-omlx] uses the same bounded discovery adapter against two authenticated TLS services. Darwin registers the stable `omlx-hera` and `omlx-clio` provider identities on both workstations. Pi prefers a provider-specific explicit environment value, then its matching login-Keychain item, and finally the non-secret `dummy-key` workstation sentinel already accepted by both local services. Generated configuration contains only environment-variable references; secret values remain outside Nix evaluation and the store. Hera adds the fixed context override for the reasoning model declared in `config/ai/models.nix`; Clio exposes only models returned by either service, with sparse records remaining conservatively non-reasoning and text-only. Linux retains the package without automatic registration.

**Basic usage.** On either workstation, keep both managed TLS proxies reachable, then open `/model` to refresh and select a discovered `omlx-hera/*` or `omlx-clio/*` model. Clio's discovered sparse records retain conservative defaults. Managed Linux profiles provide no maintained local-provider loading path. A custom deployment must supply its own trusted service and loader that passes validated typed endpoint and credential-reference records to the adapter; loading the adapter directly without those records is intentionally inert.

### [Multi-Pass][pi-multi-pass]

**Version:** 1.3.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-multi-pass) · [Home](https://github.com/hjanuschka/pi-multi-pass#readme) · [GitHub](https://github.com/hjanuschka/pi-multi-pass)

[Pi Multi-Pass][pi-multi-pass] registers additional OAuth subscription accounts for the managed Pi runtime's native Anthropic, OpenAI Codex, and GitHub Copilot providers. It reuses each native provider's login, refresh, request-auth, model-filtering, and cancellation behavior; stale Gemini CLI and Antigravity entries are ignored because managed Pi no longer provides those runtimes. Pools rotate accounts on rate limits or errors; project config may restrict accounts, override pools, and define named routing presets.

**Basic usage.** Use `/subs` to add, authenticate, inspect, or remove accounts; `/pool` to create and manage failover pools and chains; and `/mp-preset` for named model routes. Mutable account and pool state remains outside Nix ownership.

### [Factory Droid SDK Provider][pi-droid-sdk]

**Version:** 0.1.0, pinned at `ecc7e9e` · **Links:** [Pi extension](https://github.com/bentossell/pi-droid-sdk) · [Factory TypeScript SDK](https://docs.factory.ai/sdk/typescript) · [Factory models](https://docs.factory.ai/models)

[Pi Droid SDK][pi-droid-sdk] registers Factory models through the public `@factory/droid-sdk` package and the official `droid` CLI. It presents those models under `factory/*` and maps Pi thinking levels to the model's advertised Droid reasoning levels. The managed Gallery enforces model-only operation with autonomy off and the Pi tool bridge disabled. Startup and session replacement load the bundled roster without reading Factory credentials, spawning Droid, or contacting Factory. Explicit `/droid-refresh-models` discovery and model requests require `FACTORY_API_KEY` or Pi's mutable `factory` login. Nix owns only the pinned extension and dependency closure.

**Basic usage.** The managed configuration installs the official `droid` CLI. Open `/model` to select a bundled `factory/*` model. After setting `FACTORY_API_KEY`, using Pi's `/login` flow for the `factory` provider, or changing Factory authentication, run `/droid-refresh-models` to replace the process-local roster with the account's current catalog. Model availability and organization policy remain controlled by Factory.


## Companion runtimes

These binaries are not additional Pi extensions. They are the immediate runtime packages or local services on which the corresponding extensions depend.

| Runtime | Selected version | Consumer | Links |
| --- | ---: | --- | --- |
| Pi | 0.84.4 | All extensions | [Home](https://pi.dev) · [Fork](https://github.com/jwiegley/pi) · [Upstream](https://github.com/earendil-works/pi) |
| Droid CLI | managed installation | [Factory Droid SDK Provider][pi-droid-sdk] | [Factory quickstart](https://docs.factory.ai/cli/getting-started/quickstart) |
| `agent-browser` | 0.35.1 | [Pi Agent Browser Native][pi-agent-browser-native] | [GitHub](https://github.com/vercel-labs/agent-browser) |
| RTK | 0.44.0 | [Pi RTK Optimizer][pi-rtk-optimizer] | [Home](https://www.rtk-ai.app) · [GitHub](https://github.com/rtk-ai/rtk) |
| Cymbal | 0.14.0 | [Pi Cymbal][pi-cymbal] | [Home](https://chain.sh/cymbal/) · [GitHub](https://github.com/1broseidon/cymbal) |
| llama-swap | v251 | [llama-swap Provider][pi-provider-llama-swap] | [GitHub](https://github.com/mostlygeek/llama-swap) |
| oMLX | 0.6.2 | [oMLX Provider][pi-provider-omlx] and managed Sol route | [GitHub](https://github.com/jundot/omlx) |
| Pandoc | 3.7.0.2 | [Markdown Preview][pi-markdown-preview] | [Home](https://pandoc.org) · [GitHub](https://github.com/jgm/pandoc) |

The Pi profile also installs the support toolchain expected by [Lens][pi-lens] and the orchestration extensions: `actionlint`, ast-grep, Bash Language Server, Biome, `gopls`, `nil`, Node.js 22, Pyright, Ruff, Rust Analyzer, ShellCheck, shfmt, Taplo, Terraform Language Server, tmux, typos, TypeScript Language Server, and YAML Language Server. Agent Browser, Cymbal, RTK, llama-swap, and oMLX appear separately above.

## Operational notes

- The active profile root is `~/.config/pi/agent`; Nix owns only the generated leaves enumerated above.
- Run `/reload` after a Nix activation when the current Pi process must adopt changed extension code.
- On Hera and Clio, reopen `/model` after the llama-swap, `omlx-hera`, or `omlx-clio` roster changes; the picker continues to display its cached list while allowing up to 15 seconds for the combined catalog refresh. Each discovery request retains its separate 2.5-second bound.
- GPT Fast Mode starts disabled and session-only; `/fast` changes process state and `PI_GPT_FAST_MODE` handoff only, while Nix owns the immutable defaults and six-model allowlist.
- Run `/droid-refresh-models` when the current Pi process needs Factory's live account catalog; startup deliberately stays on the bundled roster.
- Mutable extension state remains outside Nix ownership. Examples include [Pi Mem][pi-mem] Markdown, scratchpad, and dashboard cache; [Pi Trace][pi-trace] files; the Usage Dashboard cache; [Cache Optimizer][pi-cache-optimizer], [Caveman][pi-caveman], [Quiet][pi-quiet], and [RTK Optimizer][pi-rtk-optimizer] preferences; [Pi Loop][pi-loop] presets and logs; [Pi MCP Adapter][pi-mcp-adapter] credentials and cache; [Pi Cymbal][pi-cymbal] indexes; and [Pi Subagents][pi-subagents], [Pi Dynamic Workflows][pi-dynamic-workflows], and [Pi Goal X][pi-goal-x] run state.
- Style extensions retain distinct purposes: [Ponytail][ponytail] minimizes implementation; [Caveman][pi-caveman] compresses prose; [Quiet][pi-quiet] compresses tool presentation; [Fleet Theme][fleet-theme] changes TUI color treatment.

## Verification

Confirm the Nix-owned extension entries, exact gallery projection, generated resource counts, structural policy, and companion versions without printing credential values:

```bash
profile=~/.config/pi/agent

for path in \
  "$profile/extensions/fleet-theme/index.ts" \
  "$profile/extensions/nix-gallery/index.ts" \
  "$profile/extensions/pi-gpt-fast-mode/config.json" \
  "$profile/extensions/pi-loop/index.ts" \
  "$profile/extensions/pi-mcp-adapter" \
  "$profile/extensions/pi-quiet" \
  "$profile/themes/dark-tool-backgrounds.json" \
  ~/.pi-lens/config.json
do
  realpath "$path"
done

gallery=$(dirname "$(realpath "$profile/extensions/nix-gallery/index.ts")")
jq -r '.packages[] | "\(.name)\t\(.version)"' "$gallery/projection.json"
find "$profile/agents" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) | wc -l
find "$profile/prompts" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) | wc -l
jq '{providers: (.providers | keys)}' "$profile/models.json"
jq '{settings, servers: (.mcpServers | to_entries | map({name: .key, transport: (if .value.url then "http" else "stdio" end)}))}' ~/.config/mcp/mcp.json
jq 'keys' "$profile/keybindings.json"

if [ "$(uname -s)" = Darwin ]; then
  omlx --version
fi

pi --version
agent-browser --version
rtk --version
cymbal --version
llama-swap --version
pandoc --version | head -1
```

Within a fresh Pi session, confirm the principal control surfaces:

```text
/mcp
/quiet status
/loop list
/trace
/cache-optimizer doctor
/fast status
/rtk verify
/subagents-doctor
/workflows
/goal
/model
```

[Lens][pi-lens] commands and tools and [Pi Mem][pi-mem] tools should be absent while they remain excluded from the generated Gallery.

Source policy last checked against the current `~/src/nix` fleet renderer on 2026-08-28. Activation evidence is recorded separately so this inventory does not imply that an unactivated source revision is already live.

[nix-gallery-loader]: https://github.com/jwiegley/nix-config/tree/main/packages/pi-gallery
[fleet-theme]: https://github.com/jwiegley/nix-config/blob/main/config/ai/extensions/fleet-theme/index.ts
[pi-loop]: https://pi.dev/packages/@realvendex/pi-loop
[pi-mcp-adapter]: https://pi.dev/packages/pi-mcp-adapter
[pi-quiet]: https://pi.dev/packages/@zenspc/pi-quiet
[agent-cat-workflow]: https://github.com/jwiegley/agent-cat/tree/main/pi-extension
[pi-hashline-edit-pro]: https://pi.dev/packages/pi-hashline-edit-pro
[pi-smart-fetch]: https://pi.dev/packages/pi-smart-fetch
[pi-smart-web-search]: https://pi.dev/packages/pi-smart-web-search
[ponytail]: https://pi.dev/packages/@dietrichgebert/ponytail
[pi-agent-browser-native]: https://pi.dev/packages/pi-agent-browser-native
[pi-btw]: https://pi.dev/packages/pi-btw
[pi-copy-message]: https://pi.dev/packages/pi-copy-message
[pi-multi-pass]: https://pi.dev/packages/pi-multi-pass
[pi-droid-sdk]: https://github.com/bentossell/pi-droid-sdk
[pi-provider-llama-swap]: https://github.com/jwiegley/nix-config/blob/main/packages/pi-gallery/providers/pi-provider-llama-swap.ts
[pi-provider-omlx]: https://github.com/jwiegley/nix-config/blob/main/packages/pi-gallery/providers/pi-provider-omlx.ts
[pi-rewind]: https://pi.dev/packages/pi-rewind
[pi-flag]: https://github.com/jwiegley/pi-flag
[pi-idle-check]: https://github.com/jwiegley/pi-idle-check
[pi-trace]: https://pi.dev/packages/pi-trace-extension
[pi-markdown-preview]: https://pi.dev/packages/pi-markdown-preview
[pi-caveman]: https://pi.dev/packages/pi-caveman
[pi-rtk-optimizer]: https://pi.dev/packages/pi-rtk-optimizer
[pi-cymbal]: https://pi.dev/packages/pi-cymbal
[pi-gpt-fast-mode]: https://pi.dev/packages/pi-gpt-fast-mode
[pi-subagents]: https://pi.dev/packages/pi-subagents
[pi-dynamic-workflows]: https://pi.dev/packages/@quintinshaw/pi-dynamic-workflows
[pi-goal-x]: https://pi.dev/packages/pi-goal-x
[pi-cache-optimizer]: https://pi.dev/packages/pi-cache-optimizer
[pi-lens]: https://pi.dev/packages/pi-lens
[pi-mem]: https://pi.dev/packages/@askjo/pi-mem
[pi-openai-server-compaction]: https://github.com/algal/pi-openai-server-compaction
[pi-local-llm]: https://github.com/gaurav-321/pi-local-llm
