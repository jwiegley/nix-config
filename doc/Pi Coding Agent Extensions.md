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
updated: 2026-08-11
pi-version: 0.83.0
---

# Pi Coding Agent Extensions

This note records the Nix-managed Pi estate: 27 gallery packages available on every managed host, four separately deployed extensions, one generated loader, the rendered fleet profiles, and the immediate runtime companions. Versions below are the versions selected by the current Nix source.

The inventory includes generated ownership, model routing, MCP registration, and keybindings. Pi core facilities, built-in tool implementations, ordinary skill bodies, mutable user state, MCP tool-by-tool APIs, and transitive npm dependencies remain outside its scope.

## At a glance

| Extension | Version | Principal purpose | Primary interface |
| --- | ---: | --- | --- |
| Nix Gallery loader | local | Compose the managed package gallery | automatic |
| Fleet Theme | local | Discover and select the managed TUI theme | automatic |
| `@realvendex/pi-loop` | 1.0.2 | Repeat prompts under explicit stop conditions | `/loop` |
| `pi-mcp-adapter` | 2.17.0 | Lazy, context-efficient MCP access | `mcp`, `/mcp` |
| `@zenspc/pi-quiet` | 0.4.0 | Dense tool-result presentation | `/quiet` |
| `pi-hashline-edit-pro` | 0.17.5 | Hash-anchored reads and replacements | `read`, `replace` |
| `pi-smart-fetch` | 0.3.17 | Browser-fingerprinted readable web fetching | `web_fetch`, `batch_web_fetch` |
| `pi-smart-web-search` | 0.4.0 | Ranked batch web discovery | `web_search` |
| `pi-lens` | 3.8.73 | LSP, diagnostics, and structural code intelligence | `lens_diagnostics`, `symbol_search` |
| `@dietrichgebert/ponytail` | 4.8.4 | Minimal implementation discipline | `/ponytail` |
| `pi-agent-browser-native` | 0.2.72 | Native Pi interface to `agent-browser` | `agent_browser` |
| `pi-btw` | 0.4.1 | Side conversations without disturbing the main turn | `/btw` |
| `pi-copy-message` | 1.0.11 | Search and copy raw session messages | `/copy-message`, `/copy-user` |
| `@jakeryderv/pi-artifacts` | 0.9.1 | Portable Markdown and HTML artifacts | `scaffold_artifact`, `/viewer` |
| `@ygncode/pi-insights` | 1.0.1 | Session analytics | `/insights` |
| `@tmustier/pi-usage-extension` | 0.9.4 | Local usage, cost, and token statistics | `/usage` |
| `pi-multi-pass` | 1.3.0 | Multiple OAuth accounts and failover pools | `/subs`, `/pool`, `/mp-preset` |
| `pi-provider-llama-swap` | `57583beb` | Discover chat models from local llama-swap | `/model`, `llama-swap/*` |
| `pi-provider-omlx` | `57583beb` | Discover chat models from local oMLX | `/model`, `omlx/*` |
| `@yeliu84/pi-model-router` | 0.4.4 | Per-turn route and reasoning-tier selection | `/router` |
| `pi-rewind` | 0.5.0 | Conversation and file checkpoints | `/rewind` |
| `pi-blackhole` | 0.4.2 | Context compaction and observational memory | `/blackhole`, `recall` |
| `@askjo/pi-mem` | 1.2.0 | Explicit plain-Markdown memory and scratchpad | `memory_write`, `memory_read`, `memory_search`, `scratchpad` |
| `pi-trace-extension` | 0.1.12 | Local execution traces and HTML reports | `/trace` |
| `pi-markdown-preview` | 0.11.1 | Terminal, browser, PDF, and artifact previews | `/preview`, `preview_export` |
| `pi-caveman` | 1.0.7 | Compressed response style | `/caveman` |
| `pi-rtk-optimizer` | 0.9.0 | RTK command rewriting and output compaction | `/rtk` |
| `pi-cymbal` | 0.5.2 | Indexed, symbol-oriented code navigation | `cymbal_*` |
| `pi-subagents` | 0.42.1 | Focused child-agent delegation and orchestration | `subagent`, `/run` |
| `@quintinshaw/pi-dynamic-workflows` | 3.5.0 | JavaScript orchestration over parallel Pi subagents | `workflow`, `/workflows` |
| `pi-goal-x` | 0.19.0 | Durable goals and Sisyphus continuation | `/goals`, `get_goal` |
| `pi-cache-optimizer` | 2.8.0 | Improve provider prompt-cache reuse and report cache statistics | `/cache-optimizer` |

The llama-swap provider, oMLX provider, and Model Router packages are available on every host. The generated loader registers them automatically only on Darwin, where Nix also provisions their local-service and routing configuration.

## Managed fleet configuration

The Hera, Clio, shared-work, VPS, and Vulcan Pi profiles are rendered by `~/src/nix/config/ai/renderers/pi.nix` into the active XDG profile at `~/.config/pi/agent`. Nix owns individual generated entries rather than mutable parent directories, preserving authentication, histories, settings, caches, and extension state while keeping the declarative surface collision-checked. Home Manager also owns the compatibility link `~/.pi -> ~/.config/pi`; activation refuses to replace a real legacy `~/.pi` tree or a wrong link.

### Owned surface

| Surface | Current projection |
| --- | --- |
| Generated ownership | Individual leaves below `~/.config/pi/agent`, plus `~/.pi-lens/config.json` and the `~/.pi` compatibility link; Pi shares `~/.config/mcp/mcp.json` with Prime Agent |
| Extension entries | Fleet Theme, Nix Gallery loader, Pi Loop, Pi MCP Adapter, and Quiet Display on every managed host; Linux keeps the two loopback providers and router available without registering them automatically |
| Agent resources | 25 Nix-managed agent definitions |
| Prompt resources | 63 files: 61 command prompts and the `emacs` and `spanish` prompts |
| Skill resources | Shared catalog skills selected for Pi, plus six gallery package skill paths and one gallery prompt path advertised at runtime |
| Generated policy | `keybindings.json`, `models.json`, the managed theme, the hidden Lens widget setting, and the global MCP registry; Darwin also receives `model-router.json` |
| Deliberately absent | No Pi-specific Nix settings file, hooks, marketplaces, or companion leaves |

Shared skills remain in the common discovery estate rather than being copied into a private Pi skill tree. Their ownership is independent of Codex, so Pi-only hosts receive them too. Package skills supplied by Lens, BTW, Artifacts, Subagents, and Dynamic Workflows enter through the gallery loader.

### Model and routing policy

The generated model files deliberately emit no Pi default. Model selection remains mutable at session scope. Darwin configures the locally provisioned providers, opt-in Hermes route, and router; Linux generates only the native remote-provider context overrides even though the complete extension package projection is present.

| Item | Current value |
| --- | --- |
| Darwin provider surface | Gallery providers `llama-swap` and `omlx`; the `hermes` OpenAI-compatible provider; native `openai-codex` and `openrouter` overrides; and the synthetic `router` provider |
| Linux provider surface | Native `openai-codex` and `openrouter` overrides only; the loopback discovery adapters and router are packaged but not registered automatically |
| Hermes route | `hermes/hermes-agent` at `https://hermes.vulcan.lan/v1`; opt-in, with its bearer credential resolved from the Home Manager-configured password store and GnuPG home only when a request uses the provider; stale inherited `GPG_TTY` state is discarded before lookup, isolating credential resolution from Agent Deck/tmux terminal state; Pi session-affinity headers are enabled for stable upstream routing |
| Sol router route | `omlx/Qwen3.6-27B-oQ6e-mtp` through the local OpenAI-compatible oMLX service; text and image input; reasoning enabled; 262,144-token context; 65,536-token output |
| Router profile | One underlying `sol` model; low → `low`, medium → `medium`, high → `xhigh`; `phaseBias` 0.5; debug disabled |
| Native overrides | `openai-codex/gpt-5.6-sol` receives a 1,050,000-token context; `openrouter/z-ai/glm-5.2` receives 1,048,576; selected local compatibility overrides receive 262,144 |
| Local discovery | Each local provider queries its loopback `/models` endpoint once during registration, under a 2.5-second bound; explicit type, modality, and capability metadata determines model behavior, while missing or unknown metadata falls back to text-only, non-reasoning chat with 262,144 context and 65,536 output |
| Request policy | Managed local providers declare a 7,200-second request and stream-idle transport budget in `models.json`; the ordinary global timeout remains 300 seconds, and loopback credentials remain policy-approved and non-secret |

The generated `models.json` owns compatibility and context overrides; on Darwin it also owns the synthetic router model and Hermes route. The Hermes credential is a runtime command reference, not a secret copied into the Nix store. The Darwin-registered local provider extensions own runtime model discovery. No generated model is Pi's default.

### MCP registry

Nix generates the shared, catalog-selected registry at `~/.config/mcp/mcp.json`; Pi MCP Adapter exposes it lazily and renders compact footer status.

| Profiles | Servers |
| --- | --- |
| Hera and Clio | `devonthink`, `drafts`, `pal`, `searxng`, `sequential-thinking`, `stock-trader` |
| shared-work and VPS | `pal`, `sequential-thinking` |
| Vulcan | `pal`, `searxng`, `sequential-thinking` |

Credential-bearing values are environment references rather than literal secrets. The mutable `~/.config/pi/agent/mcp.json` may retain adapter state, but Nix preflight forbids `mcpServers` and `imports` there so that it cannot shadow the generated registry.

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

The Nix Gallery loader projects the complete managed package set on every host. It imports and registers extensions in deterministic order, except that Linux does not automatically import the two loopback providers or their router. All 27 immutable package paths remain in the projection. Before registration the loader suppresses Ponytail's footer status and disables Lens runtime installers. It is infrastructure rather than a public Pi package.

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

**Version:** 2.17.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-mcp-adapter) · [Home](https://github.com/nicobailon/pi-mcp-adapter#readme) · [GitHub](https://github.com/nicobailon/pi-mcp-adapter)

Pi MCP Adapter exposes Model Context Protocol servers through one compact proxy tool instead of placing every remote tool schema in the model context. Servers are lazy by default; metadata, instructions, resources, and prompts are cached; large results are guarded; selected tools may be promoted directly; and MCP Apps and remote OAuth retain explicit interactive surfaces.

**Basic usage.** Open `/mcp` for status and direct-tool control, `/mcp setup` for guided configuration, and `/mcp-auth` for OAuth. From an agent turn, use `mcp({ search: "term" })`, inspect a candidate with `mcp({ describe: "tool" })`, read server guidance with `mcp({ instructions: "server" })`, and call it with `mcp({ tool: "tool", args: { ... } })`. `/mcp enable` and `/mcp disable` write only project-local overrides and require `/reload`; reconnects and direct-tool changes refresh the current session.

### Quiet Display

**Version:** 0.4.0 · **Links:** [Pi Packages](https://pi.dev/packages/@zenspc/pi-quiet) · [Home](https://github.com/zenspc/pi-extensions/tree/master/packages/pi-quiet#readme) · [GitHub](https://github.com/zenspc/pi-extensions)

Quiet Display changes presentation, not execution. It renders built-in and foreign tool activity as dense verb-first rows, folds adjacent successful operations of the same kind, suppresses live stdout while a tool is running, and preserves Pi's stock expanded display for inspection and failures.

**Basic usage.** Quiet mode is enabled by default. Use `/quiet`, `/quiet on`, `/quiet off`, or `/quiet status`. The sticky preference is stored in `~/.config/pi/agent/extensions/quiet.json`.

## Editing, context, and session control

### Hashline Edit Pro

**Version:** 0.17.5 · **Links:** [Pi Packages](https://pi.dev/packages/pi-hashline-edit-pro) · [Home](https://github.com/YuGiMob/pi-hashline-edit-pro#readme) · [GitHub](https://github.com/YuGiMob/pi-hashline-edit-pro)

Hashline Edit Pro replaces ambiguous text matching with stable, short anchors attached to every line returned by `read`. The corresponding `replace` tool addresses an inclusive anchor range, which makes edits explicit and guards against changing stale or unexpectedly modified text.

**Basic usage.** Read the relevant file, retain the three-character hashes, then call `replace` with `hash_range_inclusive` and literal replacement lines. `/toggle-replace-mode` changes between bulk and flat replacement forms; `/toggle-auto-read` controls automatic anchor refresh after writes and replacements.

### Ponytail

**Version:** 4.8.4 (`4.8.4+16f2980` in the Nix projection) · **Links:** [Pi Packages](https://pi.dev/packages/@dietrichgebert/ponytail) · [Home](https://github.com/DietrichGebert/ponytail) · [GitHub](https://github.com/DietrichGebert/ponytail)

Ponytail imposes a minimal implementation discipline: question speculative work, reuse the existing codebase, prefer the standard library and native platform, and stop at the first simple solution that satisfies the actual requirement. Its purpose is to reduce avoidable code rather than compress prose alone.

**Basic usage.** Use `/ponytail off|lite|full|ultra`, `/ponytail status`, or `/ponytail default <mode>`. The companion commands `/ponytail-review`, `/ponytail-audit`, `/ponytail-debt`, `/ponytail-gain`, and `/ponytail-help` invoke the corresponding skills.

### Rewind

**Version:** 0.5.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-rewind) · [Home](https://arpagon.github.io/pi-rewind) · [GitHub](https://github.com/arpagon/pi-rewind)

Pi Rewind records per-tool checkpoints so conversation state, file changes, or both may be returned to an earlier point. Restoration is bounded to the recorded session history and retains a redo stack, making exploratory work recoverable without a broad Git reset.

**Basic usage.** Run `/rewind` and choose the checkpoint and restoration scope. In interactive sessions, `Esc Esc` opens the quick files-only rewind.

### Blackhole

**Version:** 0.4.2 · **Links:** [Pi Packages](https://pi.dev/packages/pi-blackhole) · [Home](https://github.com/k0valik/pi-blackhole#readme) · [GitHub](https://github.com/k0valik/pi-blackhole)

Pi Blackhole combines deterministic structured compaction with observational memory. Compaction preserves the active goal, completed and pending work, errors, modified files, and next action without an LLM summarization call. Background observer, reflector, and dropper workers use the active session model by default, so memory processing can consume that provider's quota and send it session content. Their observations and durable reflections remain associated with the Pi session ledger and survive compaction.

The fleet activation policy enables memory, automatic Blackhole compaction, and mid-run resume. It preflights path and JSON blockers before Home Manager changes managed links, then atomically updates the user-owned `~/.config/pi/agent/pi-blackhole/pi-blackhole-config.json`. It preserves user-selected models and thresholds while reconciling `memory=true`, `compaction=auto`, `compactionEngine=blackhole`, and `midRunCompaction=resume` and removing the retired aliases `overrideDefaultCompaction`, `noAutoCompact`, and `passive`; it also keeps that directory and file at modes 0700 and 0600. The packaged extension uses Pi's live context accounting and starts proactive compaction at 70 percent of the active model's context window: 735,000 tokens for the 1,050,000-token Sol model and 183,500 for a 262,144-token local model. Blackhole's `compactAfterTokens` remains the fallback only when Pi cannot report usable context data. Process-level `PI_BLACKHOLE_*`, `PI_VCC_OM_PASSIVE`, or `PI_OBSERVATIONAL_MEMORY_PASSIVE` settings can override the file.

**Basic usage.** Use `/blackhole` for immediate compaction, `/blackhole configure` for other mutable settings, `/blackhole-memory` for pipeline status, and `/blackhole-recall <query>` for manual searches. The `recall` tool supports entry expansion, file drill-down, regular expressions, lineage or all-session scope, and file/touched modes. `/blackhole om-off` is temporary: the next Nix activation restores the requested memory policy. Run `/reload` or start a new Pi process after activating a policy change because Blackhole caches its configuration.

### Pi Mem

**Version:** 1.2.0 · **Links:** [Pi Packages](https://pi.dev/packages/@askjo/pi-mem) · [Home](https://github.com/jo-inc/pi-mem#readme) · [GitHub](https://github.com/jo-inc/pi-mem)

Pi Mem maintains explicit, user-directed memory as plain Markdown. `MEMORY.md` holds durable facts and decisions, dated files hold daily notes, `notes/` holds named topics, and `SCRATCHPAD.md` holds a checklist. Writes and mutating scratchpad actions require an explicit user request. It injects selected memory, recent daily logs, and recent catchup indexes into each agent turn, so the chosen model provider receives that content along with the rest of the prompt. This is distinct from Blackhole's session-derived observational memory and compaction pipeline; Pi Mem does not own Blackhole's `recall` tool.

The managed package keeps its dashboard summary local instead of making upstream's automatic secondary model request. It reads recent Pi session titles and costs for the local dashboard, but does not send that inventory to a separate summarizer. Its mutable root is logically `~/.pi/agent/memory` and therefore resolves through the managed compatibility link to `~/.config/pi/agent/memory`; `PI_MEMORY_DIR` may select another root. Configured state directories are created or tightened to mode 0700, and files Pi Mem creates or replaces use mode 0600. File updates reject symbolic-link leaves, replace whole files atomically, and serialize read-modify-write operations across Pi processes. Stale file locks are reclaimed only when a same-host owner is proven to have exited; foreign-host, live-owner, malformed, and in-progress-recovery locks remain in place, and writes fail closed. Nix does not own or delete this state. The managed package deliberately removes upstream Git autocommit: `PI_AUTOCOMMIT` and the legacy `.pi-mem.json` `autocommit` field are inert. Memory history therefore requires an explicit private Git workflow outside Pi Mem, operated manually or by a separate external tool.

**Basic usage.** Use `memory_write` for durable, daily, or named notes; `memory_read` for exact files and indexed notes; `memory_search` for case-insensitive local search; and `scratchpad` to add, complete, reopen, list, or clear checklist items. Start a fresh Pi process or run `/reload` after activation to register the tools.

### Trace

**Version:** 0.1.12 · **Links:** [Pi Packages](https://pi.dev/packages/pi-trace-extension) · [Home](https://github.com/npxcnency-ux/pi-trace-extension) · [GitHub](https://github.com/npxcnency-ux/pi-trace-extension)

Pi Trace records the execution structure of each session—model requests, steps, tool calls, timings, usage, and outcomes—as local JSONL, then renders a self-contained HTML report. The Nix package sanitizes persisted values under secret-like key names, including common authorization, API-key, AWS-secret, and cookie fields; bounds nesting; truncates long strings; flushes pending events before rendering; supplies an immutable Python renderer; and handles unavailable browser launchers without crashing Pi. Trace directories are created with mode 0700 and their JSONL and HTML files with mode 0600.

**Basic usage.** Tracing starts automatically. Run `/trace` for the current session or `/trace all` for the cross-session dashboard. Files live below `~/.pi/agent/traces/`. They still contain prompts, tool inputs and results, file paths, and model data; treat them as sensitive. The extension has no retention or rotation policy.

### Cache Optimizer

**Version:** 2.8.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-cache-optimizer) · [Home](https://github.com/jiangge/pi-cache-optimizer) · [GitHub](https://github.com/jiangge/pi-cache-optimizer)

Pi Cache Optimizer keeps stable prompt content near the front, compresses volatile skill listings, supplies conservative OpenAI-compatible cache keys, diagnoses proxy compatibility, and reports local cache statistics. It is registered last so its prompt hook observes the gallery's final prompt shape.

**Basic usage.** Use `/cache-optimizer doctor`, `/cache-optimizer stats`, `/cache-optimizer compat`, or the interactive `/cache-optimizer` menu. `/cache-optimizer enable|disable` affects the current process; `/cache-optimizer config footer-mode ...` and `/cache-optimizer reset` manage mutable extension state. `/cache-optimizer fix` is deliberately disabled because `models.json` is Nix-managed—change `config/ai` and activate a new generation instead.

### Caveman

**Version:** 1.0.7 · **Links:** [Pi Packages](https://pi.dev/packages/pi-caveman) · [Home](https://github.com/jonjonrankin/pi-caveman) · [GitHub](https://github.com/jonjonrankin/pi-caveman)

Pi Caveman appends a response-style instruction that reduces output prose while retaining technical content. It is a communication control rather than an implementation policy; this distinguishes it from Ponytail, which governs the amount and shape of code produced.

**Basic usage.** Use `/caveman` to toggle the default full mode, or select `/caveman lite|full|ultra|wenyan-lite|wenyan|wenyan-ultra|micro`. `/caveman config` controls the default level and status indicator; `/caveman off` disables it.

### Insights

**Version:** 1.0.1 · **Links:** [Pi Packages](https://pi.dev/packages/@ygncode/pi-insights) · [Home](https://github.com/ygncode/pi-insights#readme) · [GitHub](https://github.com/ygncode/pi-insights)

Pi Insights derives an interactive analytics report from Pi session history. It is suited to reviewing model usage, tool activity, costs, and conversation patterns after substantive work rather than instrumenting the live turn.

**Basic usage.** Run `/insights` and open the generated report. Treat the output as a retrospective view of recorded sessions, not as an execution trace or billing authority.

### Usage Dashboard

**Version:** 0.9.4 · **Links:** [Pi Packages](https://pi.dev/packages/@tmustier/pi-usage-extension) · [Home](https://github.com/tmustier/pi-extensions/tree/main/usage-extension) · [GitHub](https://github.com/tmustier/pi-extensions)

The Usage Dashboard aggregates locally persisted Pi session usage by provider, model, time period, cost, token type, and thinking level. It reads the session ledger only when `/usage` opens and maintains an incremental cache at `~/.pi/agent/usage-extension-cache.json`; the first scan can be substantial, while subsequent scans normally parse only changed files. The cache includes session identifiers, working-directory paths, models, costs, and token counts, so the Nix package forces it to mode `0600` and it should be treated as sensitive.

**Basic usage.** Run `/usage`, use `Tab` or Left/Right to change time periods, `v` to change views, and `e` to export the current view. Exports default to the system temporary directory unless `usage-extension.exportDir` is set in mutable Pi settings. Nix patches exports to use exclusive creation at mode `0600`; they still contain sensitive usage details and should be handled accordingly. Reported costs and tokens are only as complete as the usage metadata persisted by each provider and Pi version.

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

**Version:** 3.8.73 · **Links:** [Pi Packages](https://pi.dev/packages/pi-lens) · [Home](https://github.com/apmantza/pi-lens#readme) · [GitHub](https://github.com/apmantza/pi-lens)

Pi Lens combines language-server diagnostics, formatters, linters, structural scanners, complexity checks, symbol indexing, and edit-read guards. Its indexed tools provide a narrow discovery funnel—search for likely modules, inspect an outline, then read the exact symbol—before resorting to broad file reads.

**Basic usage.** Start with `symbol_search`, `module_report`, and `read_symbol`; use `lsp_diagnostics` for focused type errors and `lens_diagnostics` for the complete runner set. `/lens-health`, `/lens-tools`, `/lens-tdi`, and `/lens-map` expose operational and architectural views. Runtime tool installation is disabled by the Nix policy.

### Agent Browser Native

**Version:** 0.2.72 · **Links:** [Pi Packages](https://pi.dev/packages/pi-agent-browser-native) · [Home](https://github.com/fitchmultz/pi-agent-browser-native#readme) · [GitHub](https://github.com/fitchmultz/pi-agent-browser-native) · [agent-browser](https://github.com/vercel-labs/agent-browser)

Pi Agent Browser Native presents `agent-browser` as the `agent_browser` Pi tool. It supports live browsing, semantic locators, multi-step jobs, screenshots, extraction, QA presets, authenticated browser profiles, and Electron application control while retaining explicit stopping points before consequential submissions.

**Basic usage.** Follow the stable sequence `open` → interactive snapshot → action by current reference → new snapshot. Use the `job` input for bounded multi-step work, `qa` for page assertions and diagnostics, and `electron` only for desktop applications. The managed runtime companion is `agent-browser` 0.33.1.

### RTK Optimizer

**Version:** 0.9.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-rtk-optimizer) · [Home](https://github.com/MasuRii/pi-rtk-optimizer#readme) · [GitHub](https://github.com/MasuRii/pi-rtk-optimizer) · [RTK home](https://www.rtk-ai.app) · [RTK GitHub](https://github.com/rtk-ai/rtk)

Pi RTK Optimizer delegates shell-command rewrites to RTK—Rust Token Killer—and compacts selected tool output before it enters the model context. Test, build, Git, lint, and search output receive specialized treatment; lossy source-read compaction remains disabled by default so anchored edits retain exact source lines.

**Basic usage.** Use `/rtk` for the settings panel, `/rtk verify` to confirm the executable, `/rtk show` for current policy, and `/rtk stats` for session savings. The Nix profile supplies RTK 0.44.0 as `rtk` on `PATH`.

### Cymbal

**Version:** 0.5.2 · **Links:** [Pi Packages](https://pi.dev/packages/pi-cymbal) · [Home](https://github.com/raphapr/pi-cymbal#readme) · [GitHub](https://github.com/raphapr/pi-cymbal) · [Cymbal home](https://chain.sh/cymbal/) · [Cymbal GitHub](https://github.com/1broseidon/cymbal)

Pi Cymbal exposes Cymbal's local tree-sitter and SQLite index as agent-native code navigation. Its tools cover repository maps, structural summaries, symbol and text search, outlines, exact source retrieval, references, impact, imports, implementations, changed symbols, symbol diffs, guided investigations, call traces, and context bundles.

**Basic usage.** Begin unfamiliar work with `cymbal_map` or `cymbal_structure`, then narrow through `cymbal_search`, `cymbal_outline`, and `cymbal_show`. Use `cymbal_refs`, `cymbal_impact`, `cymbal_changed`, or `cymbal_diff` before a refactor. `/cymbal:remind` refreshes the navigation guidance. The Nix profile supplies Cymbal 0.14.0.

## Rendering and artifacts

### Artifacts

**Version:** 0.9.1 · **Links:** [Pi Packages](https://pi.dev/packages/@jakeryderv/pi-artifacts) · [Home](https://github.com/jakeryderv/pi-packages/tree/main/packages/pi-artifacts#readme) · [GitHub](https://github.com/jakeryderv/pi-packages)

Pi Artifacts creates portable Markdown and HTML bundles for reports, diagrams, dashboards, and other results that benefit from a rendered view. Bundles separate authored content from assets, pass through validation before display, and may be exported to a self-contained HTML file.

**Basic usage.** Call `scaffold_artifact`, write the returned bundle entry and assets, then call `render_artifact`. Use `export_artifact` for a portable file, `list_artifacts` for discovery, and the deletion tools for cleanup. `/viewer`, `/viewer-mode`, `/viewer-auto`, and `/artifacts-clean` govern the interactive store.

### Markdown Preview

**Version:** 0.11.1 · **Links:** [Pi Packages](https://pi.dev/packages/pi-markdown-preview) · [Home](https://github.com/omaclaren/pi-markdown-preview#readme) · [GitHub](https://github.com/omaclaren/pi-markdown-preview)

Pi Markdown Preview renders assistant responses and local Markdown, LaTeX, source, and diff files in the terminal or browser, and exports PDF, HTML, or PNG artifacts. It supports syntax highlighting, mathematical notation, Mermaid diagrams, local images, response selection, and Pi-theme-aware styling.

**Basic usage.** Run `/preview` for the latest response, `/preview <path>` for a file, `/preview-browser` for HTML, and `/preview-pdf` for PDF output. The `preview_export` tool writes artifacts without requiring an interactive preview. Nix supplies the Puppeteer closure; browser rendering uses an installed Chromium-based browser or `PUPPETEER_EXECUTABLE_PATH`. Pandoc and XeLaTeX support document and PDF rendering.

## Models and conversational control

### Goal X

**Version:** 0.19.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-goal-x) · [Home](https://github.com/tmonk/pi-goal-x#readme) · [GitHub](https://github.com/tmonk/pi-goal-x)

Pi Goal X persists explicit objectives, lifecycle state, usage, and ordered Sisyphus continuation. Goals can pause, resume, be audited before completion, and survive context compaction without restating the objective in the footer.

**Basic usage.** Use `/goals` or `/sisyphus` to discuss and confirm a new objective; `/goals-set` and `/sisyphus-set` bypass discussion when the objective is already final. `/goal` and `/goal-status` display status, `get_goal` inspects the focused goal, and the remaining commands and phase-specific tools govern pause, resume, abort, and completion. Start a fresh Pi session after activation.

### Subagents

**Version:** 0.42.1 · **Links:** [Pi Packages](https://pi.dev/packages/pi-subagents) · [Home](https://github.com/nicobailon/pi-subagents#readme) · [GitHub](https://github.com/nicobailon/pi-subagents)

Pi Subagents delegates focused work to child Pi sessions without replacing the parent as orchestrator. It supports single, parallel, chained, forked-context, foreground, and background runs, with fleet status and supervisor communication.

Eight builtin roles—context-builder, delegate, oracle, planner, researcher, reviewer, scout, and worker—ship with the extension; `advisor` remains an alias for `oracle`. The Nix-managed baseline adds twenty-five user definitions without collisions, accounting for thirty-three roles before mutable package, user, or project definitions are considered. Live discovery may therefore report a larger total without changing Nix ownership.

**Basic usage.** Ask naturally for `reviewer`, `oracle`, `scout`, or `worker`, or use `/run` for a single child. Use packaged prompt shortcuts such as `/parallel-review` and `/review-loop`, or call `subagent` with `workflowScript` for coordinated multi-agent work. Use `/subagents-doctor` to check setup and `/subagents-fleet` for active work. The watchdog remains opt-in.

### Dynamic Workflows

**Version:** 3.5.0 · **Links:** [Pi Packages](https://pi.dev/packages/@quintinshaw/pi-dynamic-workflows) · [Home](https://github.com/QuintinShaw/pi-dynamic-workflows#readme) · [GitHub](https://github.com/QuintinShaw/pi-dynamic-workflows)

Pi Dynamic Workflows builds JavaScript orchestration over Pi Subagents. A workflow may compose `agent()`, `parallel()`, and `pipeline()` calls, run in the background, retain resumable run state, isolate work in Git worktrees, or invoke the built-in deep-research, adversarial-review, code-review, multi-perspective, and codebase-audit patterns.

**Basic usage.** Use the `workflow` tool only after explicit opt-in: a direct request to run or fan out a workflow, the bounded word `workflow` or `workflows`, or `/workflows run <prompt>`. The keyword authorizes orchestration but does not force it. Open `/workflows` to inspect and control runs, or use `workflow_control` for programmatic list, status, pause, resume, and stop actions.

### BTW

**Version:** 0.4.1 · **Links:** [Pi Packages](https://pi.dev/packages/pi-btw) · [Home](https://github.com/dbachelder/pi-btw#readme) · [GitHub](https://github.com/dbachelder/pi-btw)

Pi BTW creates a focused side conversation while the main session remains intact. A thread may inherit the main context or begin as a contextless tangent; its result may remain private, be saved as a visible note, or be injected into the main conversation in full or summarized form.

**Basic usage.** Use `/btw <question>`, `/btw:new`, or `/btw:tangent`; use `/btw:inject` or `/btw:summarize` to return useful findings to the principal session. `/btw:model` and `/btw:thinking` control thread-specific inference settings. While the BTW overlay is focused, the first Escape closes it without pausing an active Goal X goal; a subsequent Escape retains Goal X's normal pause behavior.

### Copy Message

**Version:** 1.0.11 · **Links:** [Pi Packages](https://pi.dev/packages/pi-copy-message) · [Home](https://github.com/fitchmultz/pi-copy-message#readme) · [GitHub](https://github.com/fitchmultz/pi-copy-message)

Pi Copy Message opens a searchable, keyboard-driven picker over raw session messages, avoiding terminal wrapping and rendered TUI artifacts. It can filter by role or text, include metadata, and copy user, assistant, tool, or bash messages. The Nix package delegates copying to Pi's portable clipboard layer, including its terminal fallback for remote sessions.

**Basic usage.** Use `/copy-message` for the interactive picker, `/copy-message latest` for the newest message visible under the default filters (falling back to the newest copyable message), or `/copy-user` for the most recent user message containing text. Add `--with-meta` to prefix the copied text with its role and displayed local time.

### llama-swap Provider

**Version:** `57583beb` · **Links:** Nix adapter: `~/src/nix/packages/pi-gallery/providers/pi-provider-llama-swap.ts` · [upstream source](https://github.com/gaurav-321/pi-local-llm)

The fleet-packaged llama-swap provider is a reviewed Nix derivative of `pi-local-llm`. Darwin registers it automatically; Linux retains the package without doing so. At registration it queries the loopback llama-swap service once, filters non-chat and non-text models, derives modality and reasoning support from model metadata, and registers the surviving models through Pi's OpenAI Completions interface. A failed discovery emits a warning and leaves the provider empty until Pi reloads or restarts.

**Basic usage.** On Darwin, keep the Nix-managed `org.nixos.llama-swap` launch agent available, then select a discovered `llama-swap/*` model through `/model`. Reload Pi after the local model roster changes so that the one-time discovery runs again. Linux requires an independently provisioned trusted service and explicit extension loading.

### oMLX Provider

**Version:** `57583beb` · **Links:** Nix adapter: `~/src/nix/packages/pi-gallery/providers/pi-provider-omlx.ts` · [upstream source](https://github.com/gaurav-321/pi-local-llm)

The fleet-packaged oMLX provider uses the same bounded discovery adapter against the loopback oMLX service. Darwin registers it automatically and uses it for the generated Sol router route, presently `Qwen3.6-27B-oQ6e-mtp`. Linux retains the package without automatic registration.

**Basic usage.** On Darwin, keep the Nix-managed `org.nixos.omlx` launch agent available and select an `omlx/*` model through `/model`, or select `router/sol` and allow Model Router to choose the reasoning tier. Reload Pi after the oMLX model roster changes. Linux requires an independently provisioned trusted service and explicit extension loading.

### Multi-Pass

**Version:** 1.3.0 · **Links:** [Pi Packages](https://pi.dev/packages/pi-multi-pass) · [Home](https://github.com/hjanuschka/pi-multi-pass#readme) · [GitHub](https://github.com/hjanuschka/pi-multi-pass)

Pi Multi-Pass registers additional OAuth subscription accounts for supported providers. Pools rotate accounts on rate limits or errors; project config may restrict accounts, override pools, and define named routing presets.

**Basic usage.** Use `/subs` to add, authenticate, inspect, or remove accounts; `/pool` to create and manage failover pools and chains; and `/mp-preset` for named model routes. Mutable account and pool state remains outside Nix ownership.

### Model Router

**Version:** 0.4.4 · **Links:** [Pi Packages](https://pi.dev/packages/@yeliu84/pi-model-router) · [Home](https://github.com/yeliu84/pi-model-router#readme) · [GitHub](https://github.com/yeliu84/pi-model-router)

Pi Model Router selects a configured route and reasoning level for each turn according to task complexity, phase, profile, budget, and explicit pins. The Darwin profiles expose one `sol` route backed by `omlx/Qwen3.6-27B-oQ6e-mtp`, so automatic routing changes thinking depth rather than the underlying provider or model. The local Nix configuration keeps this map authoritative, while the extension provides the per-turn decision and interactive control surface. Linux retains the package without automatically loading it or generating a route.

**Basic usage.** On Darwin, open `/router` to inspect or change router state. Select `router/sol` when the managed local route is intended; use direct `/model` selection when a task requires another provider or model. The generated configuration does not force a default. Linux requires an independently reviewed router configuration and explicit extension loading.

## Companion runtimes

These binaries are not additional Pi extensions. They are the immediate runtime packages or local services on which the corresponding extensions depend.

| Runtime | Activated version | Consumer | Links |
| --- | ---: | --- | --- |
| Pi | 0.83.0 | All extensions | [Home](https://pi.dev) · [GitHub](https://github.com/badlogic/pi-mono) |
| `agent-browser` | 0.33.1 | Pi Agent Browser Native | [GitHub](https://github.com/vercel-labs/agent-browser) |
| RTK | 0.44.0 | Pi RTK Optimizer | [Home](https://www.rtk-ai.app) · [GitHub](https://github.com/rtk-ai/rtk) |
| Cymbal | 0.14.0 | Pi Cymbal | [Home](https://chain.sh/cymbal/) · [GitHub](https://github.com/1broseidon/cymbal) |
| llama-swap | v245 | llama-swap Provider | [GitHub](https://github.com/mostlygeek/llama-swap) |
| oMLX | 0.5.7 | oMLX Provider and managed Sol route | [GitHub](https://github.com/jundot/omlx) |
| Pandoc | 3.7.0.2 | Markdown Preview | [Home](https://pandoc.org) · [GitHub](https://github.com/jgm/pandoc) |

The Pi profile also installs the support toolchain expected by Lens and the orchestration extensions: `actionlint`, ast-grep, Bash Language Server, Biome, `gopls`, `nil`, Node.js 22, Pyright, Ruff, Rust Analyzer, ShellCheck, shfmt, Taplo, Terraform Language Server, tmux, typos, TypeScript Language Server, and YAML Language Server. Agent Browser, Cymbal, RTK, llama-swap, and oMLX appear separately above.

## Operational notes

- The active profile root is `~/.config/pi/agent`; Nix owns only the generated leaves enumerated above.
- Run `/reload` after a Nix activation when the current Pi process must adopt changed extension code.
- On Hera and Clio, restart or reload Pi after the llama-swap or oMLX model roster changes, because local provider discovery runs once during registration.
- Mutable extension state remains outside Nix ownership. Examples include Blackhole configuration and observational memory; Pi Mem Markdown, scratchpad, and dashboard cache; trace files; the Usage Dashboard cache; Cache Optimizer, Caveman, Quiet, and RTK preferences; Pi Loop presets and logs; MCP credentials and cache; Cymbal indexes; and Subagent, Workflow, and Goal run state. Nix reconciles Blackhole's four enabled-policy fields and removes its three retired aliases.
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
jq '{memory, compaction, compactionEngine, midRunCompaction, compactAfterTokens}' \
  "$profile/pi-blackhole/pi-blackhole-config.json"
for name in \
  PI_BLACKHOLE_PASSIVE \
  PI_BLACKHOLE_COMPACTION \
  PI_BLACKHOLE_COMPACTION_ENGINE \
  PI_VCC_OM_PASSIVE \
  PI_OBSERVATIONAL_MEMORY_PASSIVE
do
  printenv "$name" >/dev/null && printf 'Blackhole override is set: %s\n' "$name"
done

if [ "$(uname -s)" = Darwin ]; then
  jq '{models: .models, profiles: .profiles, debug, phaseBias}' "$profile/model-router.json"
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
/blackhole-memory
/trace
/usage
/cache-optimizer doctor
/lens-health
/rtk verify
/subagents-doctor
/workflows
/goal
/model
```

Source policy last checked against the current `~/src/nix` fleet renderer on 2026-08-04. Activation evidence is recorded separately so this inventory does not imply that an unactivated source revision is already live.
