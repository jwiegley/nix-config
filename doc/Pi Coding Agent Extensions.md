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
updated: 2026-08-25
pi-version: 0.84.3
---

# Pi Coding Agent Extensions

This note records the Nix-managed Pi estate: 23 gallery packages projected on every managed host, four separately deployed extensions, one generated loader, the rendered fleet profiles, and the immediate runtime companions. The Gallery registers 21 of those packages on Darwin and 19 on Linux; Pi Lens and Pi Mem are retained but are not registered on any managed profile. Versions below are the versions selected by the current Nix source.

The inventory includes generated ownership, model routing, MCP registration, and keybindings. Pi core facilities, built-in tool implementations, ordinary skill bodies, mutable user state, MCP tool-by-tool APIs, and transitive npm dependencies remain outside its scope. The `agent-resources` package also carries `pi-openai-server-compaction` for compatibility testing, but no managed Pi profile renders or loads it, so it is not part of this configured inventory.

## At a glance

This table lists extensions that are active on at least one managed Pi profile. The retained but inactive Gallery packages are listed separately below.

| Extension | Version | Principal purpose | Primary interface |
| --- | ---: | --- | --- |
| Nix Gallery loader | local | Compose the managed package gallery | automatic |
| Fleet Theme | local | Discover and select the managed TUI theme | automatic |
| `@realvendex/pi-loop` | 1.0.2 | Repeat prompts under explicit stop conditions | `/loop` |
| `pi-mcp-adapter` | 2.27.0 | Lazy, context-efficient MCP access | `mcp`, `/mcp` |
| `@zenspc/pi-quiet` | 0.4.1 | Dense tool-result presentation | `/quiet` |
| `pi-hashline-edit-pro` | 0.17.5 | Hash-anchored reads and replacements | `read`, `replace` |
| `pi-smart-fetch` | 0.3.17 | Browser-fingerprinted readable web fetching | `web_fetch`, `batch_web_fetch` |
| `pi-smart-web-search` | 0.4.0 | Ranked batch web discovery | `web_search` |
| `@dietrichgebert/ponytail` | 4.9.0 | Minimal implementation discipline | `/ponytail` |
| `pi-agent-browser-native` | 0.5.0 | Native Pi interface to `agent-browser` | `agent_browser` |
| `pi-btw` | 0.4.1 | Side conversations without disturbing the main turn | `/btw` |
| `pi-copy-message` | 2.1.0 | Search and copy raw session messages | `/copy-message`, `/copy-user` |
| `pi-multi-pass` | 1.3.0 | Multiple OAuth accounts and failover pools | `/subs`, `/pool`, `/mp-preset` |
| `pi-droid-sdk` | 0.1.0 | Factory Droid models through the official Droid SDK and CLI | `/model`, `factory/*` |
| `pi-provider-llama-swap` | `57583beb` | Discover chat models from local llama-swap | `/model`, `llama-swap/*` |
| `pi-provider-omlx` | `57583beb` | Discover chat models from both authenticated workstation oMLX services | `/model`, `omlx-hera/*`, `omlx-clio/*` |
| `pi-rewind` | 0.5.0 | Conversation and file checkpoints | `/rewind` |
| `pi-trace-extension` | 0.1.15 | Local execution traces and HTML reports | `/trace` |
| `pi-markdown-preview` | 0.14.1 | Terminal, browser, PDF, and artifact previews | `/preview`, `preview_export` |
| `pi-caveman` | 1.0.8 | Compressed response style | `/caveman` |
| `pi-rtk-optimizer` | 0.9.0 | RTK command rewriting and output compaction | `/rtk` |
| `pi-cymbal` | 0.5.3 | Indexed, symbol-oriented code navigation | `cymbal_*` |
| `pi-subagents` | 0.56.0 | Focused child-agent delegation and orchestration | `subagent`, `/run` |
| `@quintinshaw/pi-dynamic-workflows` | 3.7.0 | JavaScript orchestration over parallel Pi subagents | `workflow`, `/workflows` |
| `pi-goal-x` | 0.30.2 | Durable goals and Sisyphus continuation | `/goal`, `get_goal` |
| `pi-cache-optimizer` | 2.8.6 | Improve provider prompt-cache reuse and report cache statistics | `/cache-optimizer` |

### Packaged but inactive

These packages remain pinned, built, and present in the immutable Gallery projection, but their extension code is not imported or registered by any managed Pi profile.

| Retained package | Version | Remaining use |
| --- | ---: | --- |
| `pi-lens` | 4.0.1 | One packaged skill root exposing four Lens skills remains advertised, and Nix still renders the hidden Lens widget setting; Lens tools and commands are unavailable |
| `@askjo/pi-mem` | 1.2.0 | Projection only; no Pi Mem imports, tools, commands, or managed state activation |

The Factory Droid SDK provider is available and registered on every host. The llama-swap and oMLX provider packages are available everywhere, but the generated loader registers those two only on Darwin. Local llama-swap remains loopback-only. On both workstations the oMLX adapter registers the stable `omlx-hera` and `omlx-clio` identities and discovers both services through authenticated TLS. Hera receives fixed `omlx-hera` overrides; Clio retains bounded discovery so that Pi advertises only the models the two services actually return.

## Managed fleet configuration

The Hera, Clio, shared-work, VPS, and Vulcan Pi profiles are rendered by `~/src/nix/config/ai/renderers/pi.nix` into the active XDG profile at `~/.config/pi/agent`. Nix owns individual generated entries rather than mutable parent directories, preserving authentication, histories, settings, caches, and extension state while keeping the declarative surface collision-checked. Home Manager also owns the compatibility link `~/.pi -> ~/.config/pi`; activation refuses to replace a real legacy `~/.pi` tree or a wrong link. On Darwin only, activation performs one lock-scoped migration when the mutable global `enabledModels` list contains the retired `omlx/` provider identity or a known-stale exact oMLX pattern left by the prior bilateral expansion. Each legacy entry contributes any missing matching local-first `omlx-hera/` and `omlx-clio/` entries for that workstation except known-stale provider/model pairs; stale entries are removed, generated/current-provider collisions are deduplicated, and `factory/*` is added once without moving an existing entry. Unrelated entries, including duplicates, retain their order. Missing, empty, or unaffected current scopes remain byte-for-byte untouched.

### Owned surface

| Surface | Current projection |
| --- | --- |
| Generated ownership | Individual leaves below `~/.config/pi/agent`, plus `~/.pi-lens/config.json` and the `~/.pi` compatibility link; Pi shares `~/.config/mcp/mcp.json` with Prime Agent |
| Extension entries | Fleet Theme, Nix Gallery loader, Pi Loop, Pi MCP Adapter, and Quiet Display on every managed host; the Gallery loads the Factory Droid SDK provider everywhere; Darwin additionally loads loopback llama-swap and the bilateral authenticated oMLX discovery adapter, while Linux retains those local providers without registering them automatically |
| Agent resources | 25 Nix-managed agent definitions |
| Prompt resources | 63 files: 61 command prompts and the `emacs` and `spanish` prompts |
| Skill resources | Shared catalog skills selected for Pi, plus five gallery package skill paths and one gallery prompt path advertised at runtime |
| Generated policy | `keybindings.json`, `models.json`, the managed theme, the hidden Lens widget setting, and the global MCP registry |
| Deliberately absent | No Pi-specific Nix settings file, hooks, marketplaces, or companion leaves |

Shared skills remain in the common discovery estate rather than being copied into a private Pi skill tree. Their ownership is independent of Codex, so Pi-only hosts receive them too. Package skills supplied by Lens, BTW, Subagents, and Dynamic Workflows enter through the gallery loader.

### Model and routing policy

The generated model files deliberately emit no default model. Model selection remains mutable at session scope. Hera configures fixed `llama-swap` and `omlx-hera` overrides plus the Hermes route. Clio retains Hermes and bounded runtime discovery for `llama-swap`, `omlx-hera`, and `omlx-clio`, but emits no fixed local-provider override. Linux generates only the native remote-provider context overrides even though the complete extension package projection is present.

| Item | Current value |
| --- | --- |
| Hera provider surface | Gallery providers `factory`, `llama-swap`, `omlx-hera`, and `omlx-clio`; fixed `llama-swap` and `omlx-hera` model overrides; the `hermes` OpenAI-compatible provider; and native `openai-codex` and `openrouter` overrides |
| Clio provider surface | Gallery providers `factory`, `llama-swap`, `omlx-hera`, and `omlx-clio`, whose bounded discovery exposes only returned chat models; the `hermes` OpenAI-compatible provider; and native `openai-codex` and `openrouter` overrides. No fixed local model route is generated |
| Linux provider surface | Gallery provider `factory` plus native `openai-codex` and `openrouter` overrides; the llama-swap and oMLX discovery adapters are packaged but not registered automatically |
| Hermes route | `hermes/hermes-agent` at `https://hermes.vulcan.lan/v1`; opt-in, with its bearer credential resolved from the Home Manager-configured password store and GnuPG home only when a request uses the provider; stale inherited `GPG_TTY` state is discarded before lookup, isolating credential resolution from Agent Deck/tmux terminal state; Pi session-affinity headers are enabled for stable upstream routing |
| Native overrides | `openai-codex/gpt-5.6-sol` receives a 1,050,000-token context; `openrouter/z-ai/glm-5.2` receives 1,048,576 |
| Discovery | `llama-swap` queries its loopback `/models` endpoint; `omlx-hera` and `omlx-clio` query their respective authenticated TLS endpoints. Registration and `/model` refreshes use a 2.5-second per-request bound, and a failed refresh retains the last good list. Explicit type, modality, and capability metadata determines model behavior, while missing or unknown metadata falls back to text-only, non-reasoning chat with 262,144 context and 65,536 output |
| Request and credential policy | Both Darwin profiles declare a 7,200-second request and stream-idle transport budget for all three local discovery providers in `models.json`; the ordinary global timeout remains 300 seconds. For each provider-specific runtime environment variable, Pi prefers an explicit value, then the matching login-Keychain item, then the services' non-secret compatibility sentinel. The Factory provider uses the launching process's `FACTORY_API_KEY` or Pi's mutable `factory` login, without rendering any credential into Nix-owned files |

The generated `models.json` owns compatibility and context overrides; on Hera it owns fixed `llama-swap` and `omlx-hera` overrides, while both Darwin profiles own the Hermes route. Image input is not advertised until an exact model-and-service probe establishes it. Hermes uses a runtime command reference, and each oMLX provider first uses its own explicit or Keychain-backed runtime environment value. When neither exists, the Pi wrapper supplies the non-secret workstation sentinel accepted by the local services; no secret credential is copied into the Nix store. The Darwin-registered provider extensions own runtime model discovery. No generated model is Pi's default.

### MCP registry

Nix generates the shared, catalog-selected registry at `~/.config/mcp/mcp.json`; Pi MCP Adapter exposes it lazily and renders compact footer status.

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

### Nix Gallery loader

**Version:** local · **Links:** Nix authority: `~/src/nix/packages/pi-gallery/` · deployed leaf: `~/.config/pi/agent/extensions/nix-gallery/index.ts`

The Nix Gallery loader projects the complete managed package set on every host. It imports and registers extensions in deterministic order, except that Linux does not automatically import the llama-swap or oMLX providers and Pi Lens and Pi Mem are temporarily excluded on every platform. All 24 immutable package paths, including Lens and Pi Mem, remain in the projection. Before registration the loader suppresses Ponytail's footer status, disables Lens runtime installers, and enforces model-only Factory Droid operation by setting autonomy off and disabling the Pi tool bridge. It is infrastructure rather than a public Pi package.

**Basic usage.** No direct command is required. Run `/reload` after activating a new Nix generation, or start a fresh Pi process, to load the current gallery. The loader itself owns no mutable state.

### Fleet Theme

**Version:** local · **Links:** extension: `~/src/nix/config/ai/extensions/fleet-theme/index.ts` · theme: `~/src/nix/config/ai/themes/dark-tool-backgrounds.json`

Fleet Theme advertises the immutable `dark-tool-backgrounds` theme during resource discovery and selects it when an interactive TUI session begins. The palette gives pending, successful, and failed tool calls distinct dark backgrounds while leaving headless sessions unchanged.

**Basic usage.** The extension is automatic and has no command. Run `/reload` or begin a fresh Pi process after activation; the theme is selected at the next interactive session start.

### Pi Loop

**Version:** 1.0.2 · **Links:** [Pi Packages](https://pi.dev/packages/@realvendex/pi-loop) · [Home](https://github.com/ZachDreamZ/pi-loop#readme) · [GitHub](https://github.com/ZachDreamZ/pi-loop)

Pi Loop repeats a prompt under bounded iteration, timeout, convergence, text, regular-expression, command, and error stop conditions. It supports prompt templating, lifecycle hooks, run logs, named presets, a live TUI panel, and completion notifications. Nix deploys its entry directly from an immutable support package rather than loading it through the managed gallery.

**Basic usage.** Run `/loop "prompt" --max 5` for confirmed rounds, or add `--yes` only when unattended execution and automatic approval of confirmations are intended. Use `/loop stop` to cancel after the current iteration, `/loop preview` to inspect a resolved run without starting it, and `/loop list`, `/loop logs`, or `/loop show` for retained state under `~/.pi/loops/`.

### Pi MCP Adapter

**Version:** 2.27.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-mcp-adapter) · [Home](https://github.com/nicobailon/pi-mcp-adapter#readme) · [GitHub](https://github.com/nicobailon/pi-mcp-adapter)

Pi MCP Adapter exposes Model Context Protocol servers through one compact proxy tool instead of placing every remote tool schema in the model context. Servers are lazy by default; metadata, instructions, resources, and prompts are cached; large results are guarded; selected tools may be promoted directly; and MCP Apps and remote OAuth retain explicit interactive surfaces.

**Basic usage.** Open `/mcp` for status and direct-tool control, `/mcp setup` for guided configuration, and `/mcp-auth` for OAuth. From an agent turn, use `mcp({ search: "term" })`, inspect a candidate with `mcp({ describe: "tool" })`, read server guidance with `mcp({ instructions: "server" })`, and call it with `mcp({ tool: "tool", args: { ... } })`. `/mcp enable` and `/mcp disable` write only project-local overrides and require `/reload`; reconnects and direct-tool changes refresh the current session.

### Quiet Display

**Version:** 0.4.1 · **Links:** [Pi Packages](https://pi.dev/packages/@zenspc/pi-quiet) · [Home](https://github.com/zenspc/pi-extensions/tree/master/packages/pi-quiet#readme) · [GitHub](https://github.com/zenspc/pi-extensions)

Quiet Display changes presentation, not execution. It renders built-in and foreign tool activity as dense verb-first rows, folds adjacent successful operations of the same kind, suppresses live stdout while a tool is running, and preserves Pi's stock expanded display for inspection and failures.

**Basic usage.** Quiet mode is enabled by default. Use `/quiet`, `/quiet on`, `/quiet off`, or `/quiet status`. The sticky preference is stored in `~/.config/pi/agent/extensions/quiet.json`.

## Editing, context, and session control

### Hashline Edit Pro

**Version:** 0.17.5 · **Links:** [Pi Packages](https://pi.dev/packages/pi-hashline-edit-pro) · [Home](https://github.com/YuGiMob/pi-hashline-edit-pro#readme) · [GitHub](https://github.com/YuGiMob/pi-hashline-edit-pro)

Hashline Edit Pro replaces ambiguous text matching with stable, short anchors attached to every line returned by `read`. The corresponding `replace` tool addresses an inclusive anchor range, which makes edits explicit and guards against changing stale or unexpectedly modified text.

**Basic usage.** Read the relevant file, retain the three-character hashes, then call `replace` with `hash_range_inclusive` and literal replacement lines. `/toggle-replace-mode` changes between bulk and flat replacement forms; `/toggle-auto-read` controls automatic anchor refresh after writes and replacements.

### Ponytail

**Version:** 4.9.0 (`4.9.0+2ed6c52` in the Nix projection) · **Links:** [Pi Packages](https://pi.dev/packages/@dietrichgebert/ponytail) · [Home](https://github.com/DietrichGebert/ponytail) · [GitHub](https://github.com/DietrichGebert/ponytail)

Ponytail imposes a minimal implementation discipline: question speculative work, reuse the existing codebase, prefer the standard library and native platform, and stop at the first simple solution that satisfies the actual requirement. Its purpose is to reduce avoidable code rather than compress prose alone.

**Basic usage.** Use `/ponytail off|lite|full|ultra`, `/ponytail status`, or `/ponytail default <mode>`. The companion commands `/ponytail-review`, `/ponytail-audit`, `/ponytail-debt`, `/ponytail-gain`, and `/ponytail-help` invoke the corresponding skills.

### Rewind

**Version:** 0.5.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-rewind) · [Home](https://arpagon.github.io/pi-rewind) · [GitHub](https://github.com/arpagon/pi-rewind)

Pi Rewind records per-tool checkpoints so conversation state, file changes, or both may be returned to an earlier point. Restoration is bounded to the recorded session history and retains a redo stack, making exploratory work recoverable without a broad Git reset.

**Basic usage.** Run `/rewind` and choose the checkpoint and restoration scope. In interactive sessions, `Esc Esc` opens the quick files-only rewind.

### Pi Mem

**Version:** 1.2.0 · **Links:** [Pi Packages](https://pi.dev/packages/@askjo/pi-mem) · [Home](https://github.com/jo-inc/pi-mem#readme) · [GitHub](https://github.com/jo-inc/pi-mem)

When registered, Pi Mem maintains explicit, user-directed memory as plain Markdown. `MEMORY.md` holds durable facts and decisions, dated files hold daily notes, `notes/` holds named topics, and `SCRATCHPAD.md` holds a checklist. Writes and mutating scratchpad actions require an explicit user request. While active, it injects selected memory, recent daily logs, and recent catchup indexes into each agent turn, so the chosen model provider receives that content along with the rest of the prompt. Pi Mem does not supply session-derived compaction or a recall tool.

The managed package keeps its dashboard summary local instead of making upstream's automatic secondary model request. It reads recent Pi session titles and costs for the local dashboard, but does not send that inventory to a separate summarizer. Its mutable root is logically `~/.pi/agent/memory` and therefore resolves through the managed compatibility link to `~/.config/pi/agent/memory`; `PI_MEMORY_DIR` may select another root. Configured state directories are created or tightened to mode 0700, and files Pi Mem creates or replaces use mode 0600. File updates reject symbolic-link leaves, replace whole files atomically, and serialize read-modify-write operations across Pi processes. Stale file locks are reclaimed only when a same-host owner is proven to have exited; foreign-host, live-owner, malformed, and in-progress-recovery locks remain in place, and writes fail closed. Nix does not own or delete this state. The managed package deliberately removes upstream Git autocommit: `PI_AUTOCOMMIT` and the legacy `.pi-mem.json` `autocommit` field are inert. Memory history therefore requires an explicit private Git workflow outside Pi Mem, operated manually or by a separate external tool.

Pi Mem is currently retained as a managed package in the Gallery projection but is not imported or registered by the generated Gallery. This reversible state removes its synchronous startup scan without deleting its mutable memory.

**Basic usage.** Pi Mem tools are unavailable while automatic registration is disabled. Restoring Pi Mem to the generated Gallery restores `memory_write`, `memory_read`, `memory_search`, and `scratchpad`; start a fresh Pi process or run `/reload` after activation to register them.

### Trace

**Version:** 0.1.15 · **Links:** [Pi Packages](https://pi.dev/packages/pi-trace-extension) · [Home](https://github.com/npxcnency-ux/pi-trace-extension) · [GitHub](https://github.com/npxcnency-ux/pi-trace-extension)

Pi Trace records the execution structure of each session—model requests, steps, tool calls, timings, usage, and outcomes—as local JSONL, then renders a self-contained HTML report. The Nix package sanitizes persisted values under secret-like key names, including common authorization, API-key, AWS-secret, and cookie fields; bounds nesting; truncates long strings; flushes pending events before rendering; supplies an immutable Python renderer; and handles unavailable browser launchers without crashing Pi. Trace directories are created with mode 0700 and their JSONL and HTML files with mode 0600.

**Basic usage.** Tracing starts automatically. Run `/trace` for the current session or `/trace all` for the cross-session dashboard. Files live below `~/.pi/agent/traces/`. They still contain prompts, tool inputs and results, file paths, and model data; treat them as sensitive. The extension has no retention or rotation policy.

### Cache Optimizer

**Version:** 2.8.6 · **Links:** [Pi Packages](https://pi.dev/packages/pi-cache-optimizer) · [Home](https://github.com/jiangge/pi-cache-optimizer) · [GitHub](https://github.com/jiangge/pi-cache-optimizer)

Pi Cache Optimizer keeps stable prompt content near the front, compresses volatile skill listings, supplies conservative OpenAI-compatible cache keys, diagnoses proxy compatibility, and reports local cache statistics. It is registered last so its prompt hook observes the gallery's final prompt shape.

**Basic usage.** Use `/cache-optimizer doctor`, `/cache-optimizer stats`, `/cache-optimizer compat`, or the interactive `/cache-optimizer` menu. `/cache-optimizer enable|disable` affects the current process; `/cache-optimizer config footer-mode ...` and `/cache-optimizer reset` manage mutable extension state. `/cache-optimizer fix` is deliberately disabled because `models.json` is Nix-managed—change `config/ai` and activate a new generation instead.

### Caveman

**Version:** 1.0.8 · **Links:** [Pi Packages](https://pi.dev/packages/pi-caveman) · [Home](https://github.com/jonjonrankin/pi-caveman) · [GitHub](https://github.com/jonjonrankin/pi-caveman)

Pi Caveman appends a response-style instruction that reduces output prose while retaining technical content. It is a communication control rather than an implementation policy; this distinguishes it from Ponytail, which governs the amount and shape of code produced.

**Basic usage.** Use `/caveman` to toggle the default full mode, or select `/caveman lite|full|ultra|wenyan-lite|wenyan|wenyan-ultra|micro`. `/caveman config` controls the default level and status indicator; `/caveman off` disables it.

## Research, code intelligence, and browsers

### Smart Fetch

**Version:** 0.3.17 · **Links:** [Pi Packages](https://pi.dev/packages/pi-smart-fetch) · [Home](https://github.com/Thinkscape/agent-smart-fetch#readme) · [GitHub](https://github.com/Thinkscape/agent-smart-fetch)

Pi Smart Fetch retrieves readable web content with browser-like TLS and HTTP fingerprints, Defuddle extraction, bounded batch concurrency, metadata, redirects, and streamed binary downloads. It does not execute page JavaScript or bypass interactive login challenges.

**Basic usage.** Use `web_fetch` for one URL and `batch_web_fetch` for several. Choose `markdown` for readable content or `html`, `text`, `json`, or `raw` when downstream processing requires another representation.

### Smart Web Search

**Version:** 0.4.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-smart-web-search) · [Home](https://github.com/joematthews/pi-smart-web-search#readme) · [GitHub](https://github.com/joematthews/pi-smart-web-search)

Pi Smart Web Search owns the `web_search` tool. It accepts up to six focused queries, returns ranked links and snippets, and directs the agent to Smart Fetch for full pages.

**Basic usage.** Call `web_search` with a `searches` array, then read selected results with `web_fetch` or `batch_web_fetch`. Nix does not override `smartWebSearch.resultsPerQuery`, so its managed value is the package default of five; mutable settings may select one to ten.

### Lens

**Version:** 4.0.1 · **Links:** [Pi Packages](https://pi.dev/packages/pi-lens) · [Home](https://github.com/apmantza/pi-lens#readme) · [GitHub](https://github.com/apmantza/pi-lens)

Pi Lens combines language-server diagnostics, formatters, linters, structural scanners, complexity checks, symbol indexing, and edit-read guards. Its indexed tools provide a narrow discovery funnel—search for likely modules, inspect an outline, then read the exact symbol—before resorting to broad file reads.

Pi Lens is currently retained as a managed package and projected resource but is not imported or registered by the generated Gallery. Its packaged skill root continues to expose four Lens skills through the Gallery, and Nix still renders the hidden Lens widget setting. This reversible state isolates the extension's eager startup cost without removing those resources.

**Basic usage.** Lens tools and commands are unavailable while automatic registration is disabled. Restoring Lens to the generated Gallery restores `symbol_search`, `module_report`, `read_symbol`, `lsp_diagnostics`, `lens_diagnostics`, `/lens-health`, `/lens-tools`, `/lens-tdi`, and `/lens-map`. Runtime tool installation remains disabled by the Nix policy.

### Agent Browser Native

**Version:** 0.5.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-agent-browser-native) · [Home](https://github.com/fitchmultz/pi-agent-browser-native#readme) · [GitHub](https://github.com/fitchmultz/pi-agent-browser-native) · [agent-browser](https://github.com/vercel-labs/agent-browser)

Pi Agent Browser Native presents `agent-browser` as the `agent_browser` Pi tool. It supports live browsing, semantic locators, multi-step jobs, screenshots, extraction, QA presets, authenticated browser profiles, and Electron application control while retaining explicit stopping points before consequential submissions.

**Basic usage.** Follow the stable sequence `open` → interactive snapshot → action by current reference → new snapshot. Use the `job` input for bounded multi-step work, `qa` for page assertions and diagnostics, and `electron` only for desktop applications. The managed runtime companion is `agent-browser` 0.34.0.

### RTK Optimizer

**Version:** 0.9.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-rtk-optimizer) · [Home](https://github.com/MasuRii/pi-rtk-optimizer#readme) · [GitHub](https://github.com/MasuRii/pi-rtk-optimizer) · [RTK home](https://www.rtk-ai.app) · [RTK GitHub](https://github.com/rtk-ai/rtk)

Pi RTK Optimizer delegates shell-command rewrites to RTK—Rust Token Killer—and compacts selected tool output before it enters the model context. Test, build, Git, lint, and search output receive specialized treatment; lossy source-read compaction remains disabled by default so anchored edits retain exact source lines.

**Basic usage.** Use `/rtk` for the settings panel, `/rtk verify` to confirm the executable, `/rtk show` for current policy, and `/rtk stats` for session savings. The Nix profile supplies RTK 0.44.0 as `rtk` on `PATH`.

### Cymbal

**Version:** 0.5.3 · **Links:** [Pi Packages](https://pi.dev/packages/pi-cymbal) · [Home](https://github.com/raphapr/pi-cymbal#readme) · [GitHub](https://github.com/raphapr/pi-cymbal) · [Cymbal home](https://chain.sh/cymbal/) · [Cymbal GitHub](https://github.com/1broseidon/cymbal)

Pi Cymbal exposes Cymbal's local tree-sitter and SQLite index as agent-native code navigation. Its tools cover repository maps, structural summaries, symbol and text search, outlines, exact source retrieval, references, impact, imports, implementations, changed symbols, symbol diffs, guided investigations, call traces, and context bundles.

**Basic usage.** Begin unfamiliar work with `cymbal_map` or `cymbal_structure`, then narrow through `cymbal_search`, `cymbal_outline`, and `cymbal_show`. Use `cymbal_refs`, `cymbal_impact`, `cymbal_changed`, or `cymbal_diff` before a refactor. `/cymbal` shows or changes session guidance settings. The Nix profile supplies Cymbal 0.14.0.

## Rendering and previews

### Markdown Preview

**Version:** 0.14.1 · **Links:** [Pi Packages](https://pi.dev/packages/pi-markdown-preview) · [Home](https://github.com/omaclaren/pi-markdown-preview#readme) · [GitHub](https://github.com/omaclaren/pi-markdown-preview)

Pi Markdown Preview renders assistant responses and local Markdown, LaTeX, source, and diff files in the terminal or browser, and exports PDF, HTML, or PNG artifacts. It supports syntax highlighting, mathematical notation, Mermaid diagrams, local images, response selection, and Pi-theme-aware styling.

**Basic usage.** Run `/preview` for the latest response, `/preview <path>` for a file, `/preview-browser` for HTML, and `/preview-pdf` for PDF output. The `preview_export` tool writes artifacts without requiring an interactive preview. Nix supplies the Puppeteer closure; browser rendering uses an installed Chromium-based browser or `PUPPETEER_EXECUTABLE_PATH`. Pandoc and XeLaTeX support document and PDF rendering.

## Models and conversational control

### Goal X

**Version:** 0.30.2 · **Links:** [Pi Packages](https://pi.dev/packages/pi-goal-x) · [Home](https://github.com/tmonk/pi-goal-x#readme) · [GitHub](https://github.com/tmonk/pi-goal-x)

Pi Goal X persists explicit objectives, lifecycle and task state, usage, ordered Sisyphus continuation, and a bounded append-only event ledger. Goals can pause, resume, be audited before completion, retain compact task and recent-ledger guidance across context compaction, retry transient network interruptions, and consult an optional blocker Oracle without restating the objective in the footer.

**Basic usage.** Use `/goal` or `/sisyphus` to discuss and confirm a new objective; `/goal-direct` and `/sisyphus-direct` bypass discussion when the objective is already final. `/goal-list` lists open goals, `/goal-status` displays the focused goal, and `get_goal` exposes it to the agent. Use `/goal-clear` for user-owned abandonment and `/goal-cancel` to discard an unconfirmed draft; the remaining commands and phase-specific tools govern selection, pause, resume, recovery, and completion. Start a fresh Pi session after activation.

### Subagents

**Version:** 0.56.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-subagents) · [Home](https://github.com/nicobailon/pi-subagents#readme) · [GitHub](https://github.com/nicobailon/pi-subagents)

Pi Subagents delegates focused work to child Pi sessions without replacing the parent as orchestrator. It supports single foreground and asynchronous runs, scripted sequential and parallel composition, fresh or forked context, fleet status, steering, and supervisor communication.

Seven builtin definitions—delegate, gpt-pro, oracle, researcher, reviewer, scout, and worker—ship with the extension; `advisor` remains an alias for `oracle`. The `gpt-pro` definition requires a separately registered Surf `surf-oracle` external-job provider, which the managed fleet does not configure, so it is discoverable but cannot run from Nix configuration alone. The Nix-managed baseline adds twenty-five user definitions without collisions, accounting for thirty-two definitions before mutable package, user, or project definitions are considered. Live discovery may therefore report a larger total without changing Nix ownership.

**Basic usage.** Ask naturally for `reviewer`, `oracle`, `scout`, or `worker`, or use `/run` for a single child. Use packaged prompt shortcuts such as `/parallel-review` and `/review-loop`, or call `subagent` with `workflowScript` for coordinated multi-agent work. Use `/subagents-doctor` to check setup and `/subagents-fleet` for active work. The watchdog remains opt-in.

### Dynamic Workflows

**Version:** 3.7.0 · **Links:** [Pi Packages](https://pi.dev/packages/@quintinshaw/pi-dynamic-workflows) · [Home](https://github.com/QuintinShaw/pi-dynamic-workflows#readme) · [GitHub](https://github.com/QuintinShaw/pi-dynamic-workflows)

Pi Dynamic Workflows builds JavaScript orchestration over Pi Subagents. A workflow may compose `agent()`, `parallel()`, and `pipeline()` calls, run in the background, retain resumable run state, isolate work in Git worktrees, or invoke the built-in deep-research, adversarial-review, code-review, multi-perspective, and codebase-audit patterns.

**Basic usage.** Use the `workflow` tool only after explicit opt-in: a direct request to run or fan out a workflow, the bounded word `workflow` or `workflows`, or `/workflows run <prompt>`. The keyword authorizes orchestration but does not force it. Open `/workflows` to inspect and control runs, or use `workflow_control` for programmatic list, status, pause, resume, and stop actions.

### BTW

**Version:** 0.4.1 · **Links:** [Pi Packages](https://pi.dev/packages/pi-btw) · [Home](https://github.com/dbachelder/pi-btw#readme) · [GitHub](https://github.com/dbachelder/pi-btw)

Pi BTW creates a focused side conversation while the main session remains intact. A thread may inherit the main context or begin as a contextless tangent; its result may remain private, be saved as a visible note, or be injected into the main conversation in full or summarized form.

**Basic usage.** Use `/btw <question>`, `/btw:new`, or `/btw:tangent`; use `/btw:inject` or `/btw:summarize` to return useful findings to the principal session. `/btw:model` and `/btw:thinking` control thread-specific inference settings. While the BTW overlay is focused, the first Escape closes it without pausing an active Goal X goal; a subsequent Escape retains Goal X's normal pause behavior.

### Copy Message

**Version:** 2.1.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-copy-message) · [Home](https://github.com/fitchmultz/pi-copy-message#readme) · [GitHub](https://github.com/fitchmultz/pi-copy-message)

Pi Copy Message opens a searchable, keyboard-driven picker over raw session messages, avoiding terminal wrapping and rendered TUI artifacts. It can filter by role or text, include metadata, and copy user, assistant, tool, or bash messages. The Nix package delegates copying to Pi's portable clipboard layer, including its terminal fallback for remote sessions.

**Basic usage.** Use `/copy-message` for the interactive picker, `/copy-message latest` for the newest message visible under the default filters (falling back to the newest copyable message), or `/copy-user` for the most recent user message containing text. Add `--with-meta` to prefix the copied text with its role and displayed local time.

### llama-swap Provider

**Version:** `57583beb` · **Links:** Nix adapter: `~/src/nix/packages/pi-gallery/providers/pi-provider-llama-swap.ts` · [upstream source](https://github.com/gaurav-321/pi-local-llm)

The fleet-packaged llama-swap provider is a reviewed Nix derivative of `pi-local-llm`. Darwin registers it automatically; Linux retains the package without doing so. At registration and on an explicit `/model` refresh it queries the loopback llama-swap service, filters non-chat and non-text models, derives modality and reasoning support from model metadata, and registers the surviving models through Pi's OpenAI Completions interface. A failed initial discovery emits a warning; a later refresh failure is reported by Pi while retaining the last good model list.

**Basic usage.** On Darwin, keep the Nix-managed `org.nixos.llama-swap` launch agent available, then open `/model` to refresh and select a discovered `llama-swap/*` model. Managed Linux profiles provide no maintained local-provider loading path. A custom deployment must supply its own trusted service and loader that passes a validated typed endpoint projection to the adapter; loading the adapter directly without that projection is intentionally inert.

### oMLX Provider

**Version:** `57583beb` · **Links:** Nix adapter: `~/src/nix/packages/pi-gallery/providers/pi-provider-omlx.ts` · [upstream source](https://github.com/gaurav-321/pi-local-llm)

The fleet-packaged oMLX provider uses the same bounded discovery adapter against two authenticated TLS services. Darwin registers the stable `omlx-hera` and `omlx-clio` provider identities on both workstations. Pi prefers a provider-specific explicit environment value, then its matching login-Keychain item, and finally the non-secret `dummy-key` workstation sentinel already accepted by both local services. Generated configuration contains only environment-variable references; secret values remain outside Nix evaluation and the store. Hera adds a fixed context override for `omlx-hera/DeepSeek-V4-Flash-0731-oQ8e-mtp`; Clio exposes only models returned by either service, with sparse records remaining conservatively non-reasoning and text-only. Linux retains the package without automatic registration.

**Basic usage.** On either workstation, keep both managed TLS proxies reachable, then open `/model` to refresh and select a discovered `omlx-hera/*` or `omlx-clio/*` model. Clio's discovered sparse records retain conservative defaults. Managed Linux profiles provide no maintained local-provider loading path. A custom deployment must supply its own trusted service and loader that passes validated typed endpoint and credential-reference records to the adapter; loading the adapter directly without those records is intentionally inert.

### Multi-Pass

**Version:** 1.3.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-multi-pass) · [Home](https://github.com/hjanuschka/pi-multi-pass#readme) · [GitHub](https://github.com/hjanuschka/pi-multi-pass)

Pi Multi-Pass registers additional OAuth subscription accounts for the managed Pi runtime's native Anthropic, OpenAI Codex, and GitHub Copilot providers. It reuses each native provider's login, refresh, request-auth, model-filtering, and cancellation behavior; stale Gemini CLI and Antigravity entries are ignored because managed Pi no longer provides those runtimes. Pools rotate accounts on rate limits or errors; project config may restrict accounts, override pools, and define named routing presets.

**Basic usage.** Use `/subs` to add, authenticate, inspect, or remove accounts; `/pool` to create and manage failover pools and chains; and `/mp-preset` for named model routes. Mutable account and pool state remains outside Nix ownership.

### Factory Droid SDK Provider

**Version:** 0.1.0, pinned at `ecc7e9e` · **Links:** [Pi extension](https://github.com/bentossell/pi-droid-sdk) · [Factory TypeScript SDK](https://docs.factory.ai/sdk/typescript) · [Factory models](https://docs.factory.ai/models)

Pi Droid SDK registers Factory's model catalog through the public `@factory/droid-sdk` package and the official `droid` CLI. It presents those models under `factory/*` and maps Pi thinking levels to the model's advertised Droid reasoning levels. The managed Gallery enforces model-only operation with autonomy off and the Pi tool bridge disabled. When no credential is available, the extension loads a bundled fallback roster without contacting Factory; live discovery and requests require `FACTORY_API_KEY` or Pi's mutable `factory` login. Nix owns only the pinned extension and dependency closure.

**Basic usage.** The managed configuration installs the official `droid` CLI. Set `FACTORY_API_KEY` in the launching environment or use Pi's `/login` flow for the `factory` provider, then open `/model` and select a `factory/*` model. After adding credentials to an already-running Pi process, run `/droid-refresh-models` to refresh the account's current catalog. Model availability and organization policy remain controlled by Factory.


## Companion runtimes

These binaries are not additional Pi extensions. They are the immediate runtime packages or local services on which the corresponding extensions depend.

| Runtime | Selected version | Consumer | Links |
| --- | ---: | --- | --- |
| Pi | 0.84.3 | All extensions | [Home](https://pi.dev) · [GitHub](https://github.com/earendil-works/pi) |
| Droid CLI | managed installation | Factory Droid SDK Provider | [Factory quickstart](https://docs.factory.ai/cli/getting-started/quickstart) |
| `agent-browser` | 0.34.0 | Pi Agent Browser Native | [GitHub](https://github.com/vercel-labs/agent-browser) |
| RTK | 0.44.0 | Pi RTK Optimizer | [Home](https://www.rtk-ai.app) · [GitHub](https://github.com/rtk-ai/rtk) |
| Cymbal | 0.14.0 | Pi Cymbal | [Home](https://chain.sh/cymbal/) · [GitHub](https://github.com/1broseidon/cymbal) |
| llama-swap | v251 | llama-swap Provider | [GitHub](https://github.com/mostlygeek/llama-swap) |
| oMLX | 0.6.3rc1 | oMLX Provider and managed Sol route | [GitHub](https://github.com/jundot/omlx) |
| Pandoc | 3.7.0.2 | Markdown Preview | [Home](https://pandoc.org) · [GitHub](https://github.com/jgm/pandoc) |

The Pi profile also installs the support toolchain expected by Lens and the orchestration extensions: `actionlint`, ast-grep, Bash Language Server, Biome, `gopls`, `nil`, Node.js 22, Pyright, Ruff, Rust Analyzer, ShellCheck, shfmt, Taplo, Terraform Language Server, tmux, typos, TypeScript Language Server, and YAML Language Server. Agent Browser, Cymbal, RTK, llama-swap, and oMLX appear separately above.

## Operational notes

- The active profile root is `~/.config/pi/agent`; Nix owns only the generated leaves enumerated above.
- Run `/reload` after a Nix activation when the current Pi process must adopt changed extension code.
- On Hera and Clio, reopen `/model` after the llama-swap, `omlx-hera`, or `omlx-clio` roster changes; the picker continues to display its cached list while allowing up to 15 seconds for the combined catalog refresh. Each discovery request retains its separate 2.5-second bound.
- Run `/droid-refresh-models` after adding or changing Factory authentication in an already-running Pi session.
- Mutable extension state remains outside Nix ownership. Examples include Pi Mem Markdown, scratchpad, and dashboard cache; trace files; the Usage Dashboard cache; Cache Optimizer, Caveman, Quiet, and RTK preferences; Pi Loop presets and logs; MCP credentials and cache; Cymbal indexes; and Subagent, Workflow, and Goal run state.
- Style extensions retain distinct purposes: Ponytail minimizes implementation; Caveman compresses prose; Quiet compresses tool presentation; Fleet Theme changes TUI color treatment.

## Verification

Confirm the Nix-owned extension entries, exact gallery projection, generated resource counts, structural policy, and companion versions without printing credential values:

```bash
profile=~/.config/pi/agent

for path in \
  "$profile/extensions/fleet-theme/index.ts" \
  "$profile/extensions/nix-gallery/index.ts" \
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
/rtk verify
/subagents-doctor
/workflows
/goal
/model
```

Lens commands and tools and Pi Mem tools should be absent while they remain excluded from the generated Gallery.

Source policy last checked against the current `~/src/nix` fleet renderer on 2026-08-19. Activation evidence is recorded separately so this inventory does not imply that an unactivated source revision is already live.
