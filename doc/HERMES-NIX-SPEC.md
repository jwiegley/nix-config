# Hermes Agent Nix Management Specification

**Status:** Draft for review
**Scope:** Initial Hera deployment with a portable package and configuration design
**Last verified:** 2026-07-29
**Upstream evidence revision:** `NousResearch/hermes-agent@a4973c3f11d9cc92da986cbe150d1e79d094626f`

## 1. Purpose

Hermes Agent is presently installed by a signed macOS setup application which clones an upstream Git repository into `~/.hermes/hermes-agent`, creates a Python virtual environment, installs a private Node.js runtime and `node_modules`, and leaves the resulting installation free to update itself. This arrangement has two authorities: the Nix configuration owns the host, while Hermes owns and mutates its own executable environment.

The target arrangement has one authority. Nix owns every immutable component which can reasonably be built, pinned, reviewed, and rolled back; Hermes retains only data which must remain writable at runtime. The first implementation is deliberately modest: it installs the upstream Nix packages, supplies a small managed configuration overlay, preserves the existing state root, and runs Hermes natively on Hera. Containerization, service deployment, and a broader security programme are later work.

This document specifies that arrangement and the migration into it. It does not authorize activation, process termination, deletion, a lock update, or a commit.

## 2. Decisions embodied in this draft

The following decisions are proposed as the working baseline. They remain reviewable, but implementation is not to begin until this specification is accepted.

1. **Hera is the first and only activated host.** Package and renderer code remain portable, but Clio and Linux consumers do not install Hermes during the first deployment.
2. **The upstream flake is reused.** Its `default` and `desktop` outputs already build the Python, Node.js, Electron, skills, plugins, locales, and runtime dependencies. This repository does not reproduce the upstream `uv2nix` or npm build.
3. **The upstream full package is selected initially.** Dependency pruning is deferred until closure size or build time becomes a measured concern.
4. **Hermes executes natively with `terminal.backend = "local"`.** No container, remote execution host, whole-process sandbox, gateway service, or cron service is introduced in the first deployment.
5. **Static configuration is Nix-managed through `HERMES_MANAGED_DIR`.** The generated managed overlay wins at individual leaf keys while preserving unowned mutable siblings. Nix does not rewrite or symlink `~/.hermes/config.yaml`.
6. **`~/.hermes` remains the mutable state root.** Relocating it would add migration risk without improving the first deployment.
7. **The initial desktop surface is the Nix-built `hermes-desktop` executable.** A signed, notarized, LaunchServices-native `Hermes.app` is not required for the first cutover. Dock, Finder, URL-scheme, and stable TCC identity work is deferred.
8. **The downloaded setup app and bootstrap installation are removed after verification.** Removal follows a reversible quarantine and an explicit post-cutover acceptance step; it is not part of ordinary activation.
9. **One incident-specific terminal-command guard is present from the first deployment.** The Hermes terminal tool denies commands containing `tccutil reset All`, even when YOLO or automatic approval is selected. Broader execution paths and security hardening remain later work.

## 3. Governing constraints

### 3.1 Repository constraints

This repository assigns package implementation to `packages/`, package exposure to overlays, profile and resource selection to `config/fleet/catalog.nix`, client serialization to `config/fleet/renderers/`, and Home Manager composition to `config/ai.nix` (`doc/ARCHITECTURE.md`, “Module ownership”). Nix owns generated leaves, not mutable roots; credentials remain environment-only; and activation remains consumer-owned.

Hermes follows these boundaries rather than creating a parallel configuration system.

### 3.2 Upstream constraints

The upstream flake supports `aarch64-darwin`, `aarch64-linux`, and `x86_64-linux` and exports `default`, `minimal`, `messaging`, `tui`, `web`, and `desktop` packages (`flake.nix`; `nix/packages.nix`). The default package includes the portable optional dependency groups and wraps `hermes`, `hermes-agent`, and `hermes-acp` with its runtime tools (`nix/hermes-agent.nix`).

Upstream also supplies a managed configuration seam. `HERMES_MANAGED_DIR/config.yaml` is read independently from user configuration; managed values replace user values at the leaf, while unmanaged siblings remain writable (`hermes_cli/managed_scope.py`; `tests/hermes_cli/test_managed_scope_config.py`). This is distinct from `HERMES_MANAGED`, which applies a coarse package-manager write lock. The deployment uses the former and does not set the latter.

### 3.3 Meaning of “completely managed by Nix”

Complete management applies to the static layer:

- source revision and lock;
- Python, Node.js, Electron, and native dependencies;
- Hermes CLI, TUI, ACP adapter, and desktop executable;
- bundled skills, plugins, locales, and MCP catalog;
- wrappers and package-manager update behavior;
- stable, non-secret configuration policy; and
- optional service definitions when they are later enabled.

It does not make runtime data immutable. Authentication, sessions, memories, databases, logs, caches, pairing material, user-authored skills, runtime OAuth state, and desktop preferences remain writable by design.

## 4. Current state

The current installer has created approximately 2.9 GB beneath `~/.hermes`. The principal replaceable components are:

| Component | Approximate size | Current authority |
| --- | ---: | --- |
| `~/.hermes/hermes-agent` | 2.5 GB | Mutable Git checkout |
| `~/.hermes/hermes-agent/venv` | 660 MB | Installer-created Python environment |
| `~/.hermes/hermes-agent/node_modules` | 1.3 GB | Installer-created npm tree |
| `~/.hermes/node` | 187 MB | Installer-created Node.js runtime |
| `~/.hermes/bin` | 56 MB | Installer-created and runtime-installed tools |
| `~/.local/share/uv/python/cpython-3.11.15-macos-aarch64-none` | 78 MB | Shared uv-managed Python used by the venv |
| `~/.local/bin/hermes` and `hermes-acp` | two regular files | Installer-created launch scripts into the mutable checkout |
| `~/.local/bin/node`, `npm`, and `npx` | three symlinks | Installer-created links into `~/.hermes/node` |
| `~/Library/Caches/ms-playwright` | 1.8 GB | Shared Playwright browser cache populated during setup |
| shell startup files | PATH entries, when needed | Installer may add a marked `~/.local/bin` entry |
| `/Applications/Hermes.app` | setup application | Homebrew/downloaded cask |

The current setup application is `com.nousresearch.hermes.setup` version `0.0.1`; it is a signed and notarized installer, not the final Hermes desktop application. The checked-out agent reports installation method `git`.

Mutable state already present includes `state.db` and its WAL files, `projects.db`, `kanban.db`, cron state, pairing state, `SOUL.md`, configuration, credentials, user skills, logs, caches, and desktop support data. These paths are evidence to preserve, not inputs to print or import wholesale into Nix.

Commit `f3d75450` added the Homebrew cask name `hermes-desktop` to the active
`homebrew.casks` list as an interim declarative installation of the signed setup
application. It does not make the cloned runtime or its dependencies declarative.
Phase 5 removes the cask only after the Nix-built replacement passes the authorized
cutover acceptance; until then, an ordinary authorized activation may install or retain
the setup application.

## 5. Target architecture

```text
config/fleet/flake.nix
  └── pinned NousResearch/hermes-agent input
        └── upstream default + desktop packages
              └── packages/hermes-agent.nix (thin local wrappers)
                    └── pkgs.hermes-agent / pkgs.hermes-desktop

config/fleet/hermes/default.nix
  └── secret-free Hermes policy
        └── config/fleet/renderers/hermes.nix
              └── ~/.config/hermes/nix-managed/config.yaml

local wrappers
  ├── HERMES_MANAGED_DIR=~/.config/hermes/nix-managed
  └── upstream Nix executables

~/.hermes/
  └── mutable state only; never replaced by a store symlink
```

The managed configuration directory is outside `~/.hermes` so the ownership line remains visible: `.config/hermes/nix-managed/config.yaml` is generated; `.hermes/*` is runtime state. Hermes supports an arbitrary managed directory through `HERMES_MANAGED_DIR`.

## 6. Repository layout and ownership

No empty scaffolding is created. The first implementation introduces only files with immediate work.

| Path | Responsibility |
| --- | --- |
| `config/fleet/hermes/default.nix` | Hermes-specific, secret-free semantic policy |
| `config/fleet/renderers/hermes.nix` | Deterministic Hermes configuration serialization |
| `packages/hermes-agent.nix` | Thin selection and wrappers around upstream packages |
| `overlays/ai/30-hermes-agent.nix` | Expose local package names; no package body |
| `test/ai/hermes.nix` | Package, renderer, wrapper, and state-boundary contracts |
| `doc/HERMES-NIX-SPEC.md` | This specification |

The following existing authorities require modification during implementation:

| Path | Change |
| --- | --- |
| `config/fleet/flake.nix` | Add the pinned upstream flake input |
| `config/fleet/flake.lock` and `flake.lock` | Record one coherent upstream revision |
| `sources/ai.json` and updater inventory | Record Hermes as a `flake-input` update authority with paired-lock artifacts |
| `overlays/ai/default.nix` | Include the Hermes exposure overlay exactly once |
| `config/fleet/catalog.nix` | Add the Hermes client and a Hera-only profile |
| `config/ai.nix` | Register the renderer, select packages from the profile, and extend ownership guards |
| `flake/ai.nix` | Export the package where portable outputs require it |
| `test/ai/*` | Extend compatibility, lock, renderer, package-selection, and projection contracts |
| `config/darwin.nix` | Remove the committed interim `hermes-desktop` cask in Phase 5 after authorized cutover acceptance |
| `bin/update-agents` | Include Hermes in the paired root/portable update transaction |

Client-specific serialization remains in `config/fleet/renderers/hermes.nix`, preserving the repository invariant. The `config/fleet/hermes/` directory owns policy, not renderer mechanics or package builds.

## 7. Source, package, and update requirements

### 7.1 Source authority

**H-PKG-1.** `config/fleet/flake.nix` contains one `hermes-agent` flake input pinned by `config/fleet/flake.lock`. Root consumption uses the same revision through the existing portable-input projection; a second independent root input is not introduced.

**H-PKG-2.** Upstream inputs follow the repository `nixpkgs` authority where upstream compatibility permits. Divergence requires an explicit assertion and explanation rather than an implicit second package universe.

**H-PKG-3.** Updates run through the repository update transaction. `hermes update`, desktop bootstrap updates, `git pull`, `uv sync`, `pip install`, and `npm install` never update the active Nix-managed runtime.

**H-PKG-4.** Lock changes are reviewable and atomic across root and portable locks. Package source, nested dependencies, and generated artifacts resolve from that lock.

### 7.2 Package selection

**H-PKG-5.** The first deployment uses upstream `packages.${system}.default` and `packages.${system}.desktop`. It does not construct a custom Python environment or select optional groups individually.

**H-PKG-6.** The local package wrapper supplies:

- `HERMES_MANAGED_DIR`, defaulting to `$HOME/.config/hermes/nix-managed` unless explicitly overridden; and
- a stable reference from the desktop process to the Nix-built Hermes CLI.

`HERMES_HOME` remains unset unless the caller sets it, preserving the upstream default `~/.hermes`.

**H-PKG-7.** The wrapper does not set `HERMES_MANAGED`. Store-path detection already identifies the runtime as Nix-managed for update guidance, while omission of the coarse lock permits Hermes to write unowned user settings.

**H-PKG-8.** The wrapper refuses a partial managed-configuration state. When the Hera Hermes profile is selected, the managed path may be a Home Manager symlink, but its resolved target must be a regular generated file and must parse before Hermes starts. Dangling links and non-regular targets fail with diagnostics which name paths, never configuration values.
**H-PKG-9.** `security.allow_lazy_installs` is false. An enabled feature whose dependency is absent fails before installation and reports the feature and missing package. Upstream may still suggest `uv pip install` or `pip install`; under this deployment that advice means the Nix package or enabled feature set requires adjustment, not that the command is to be run.

### 7.3 Installation policy

**H-PKG-10.** Package availability remains portable. Automatic installation is profile-driven and Hera-only. Clio and external Linux consumers see no package-selection change.

**H-PKG-11.** Hermes is installed through Home Manager composition, not `nix profile install` and not Homebrew.

## 8. Managed configuration

### 8.1 Composition

`config/fleet/hermes/default.nix` returns one secret-free attribute set representing stable operator policy. `config/fleet/renderers/hermes.nix` serializes it to deterministic YAML or JSON-as-YAML at:

```text
~/.config/hermes/nix-managed/config.yaml
```

The wrapper points `HERMES_MANAGED_DIR` at the containing directory. Upstream performs a leaf-level deep merge after reading mutable user configuration. Managed lists replace their corresponding user lists wholesale; managed dictionaries replace only declared descendant leaves.

No activation script edits `~/.hermes/config.yaml`. This avoids races, formatting churn, non-atomic merge logic, and accidental loss of settings written by Hermes Desktop.

### 8.2 Initial managed leaves

The first deployment manages only settings required to establish package ownership, a predictable native launch, and the regression guard arising from the present incident:

```nix
{
  terminal.backend = "local";
  platform_toolsets.cli = [ "hermes-cli" ];

  approvals = {
    mode = "manual";
    cron_mode = "deny";
    deny = [ "*tccutil reset All*" ];
  };

  security.allow_lazy_installs = false;
  hooks_auto_accept = false;
  delegation.subagent_auto_approve = false;
  telemetry.shared_metrics.enabled = false;
}
```

The exact YAML spelling is rendered from Nix rather than copied literally from this example.

The `tccutil` deny rule governs terminal-tool commands and applies there before YOLO, `approvals.mode = off`, smart approval, cron approval, session approval, and the permanent allowlist. It does not govern subprocesses started by code execution, MCP servers, plugins, hooks, or the desktop application. Closing those execution paths belongs to the later isolation work; the initial rule is a narrow regression guard, not a security boundary.

### 8.3 Existing configuration adoption

The first cutover preserves the existing mutable configuration and lets the managed leaves override it. Stable non-secret settings are then migrated into `config/fleet/hermes/default.nix` by category, after review.

For each category:

1. Parse the existing YAML without printing values.
2. Classify key paths as secret, stable policy, mutable preference, runtime state, or obsolete compatibility.
3. Replace secret-bearing scalar values with environment references where Hermes supports `${VAR}` expansion.
4. Add reviewed stable values to the Nix policy.
5. Verify managed values win while unowned siblings remain unchanged.
6. Remove shadowed values from mutable configuration only through an explicit, one-time migration; ordinary activation never performs this cleanup.

### 8.4 Secrets

Secret values never enter Nix expressions, source catalogs, derivations, generated YAML, wrappers, plist files, command arguments, logs, tests, or this specification.

Managed configuration may contain environment variable names and `${VAR}` references. Actual values remain in the process environment, Hermes authentication stores, or an external secret manager. The generated managed `.env` capability is not used initially.

### 8.5 Catalog integration

The catalog adds one Hermes client/profile for Hera. Initial selection covers the managed configuration and package installation only.

Shared agents, commands, prompts, and skills are not projected automatically. Hermes has different semantics for these resources, and `skills.external_dirs` does not consistently pass through every managed-scope loader at the verified upstream revision. Each resource category is added only after its renderer contract exists.

MCP rendering is likewise incremental. When enabled, the renderer translates catalog MCP records into Hermes `mcp_servers`, preserving typed environment references and transport fields. The implementation must not rely on upstream Nix’s narrower dedicated MCP option schema; the raw Hermes runtime schema is authoritative.

## 9. Mutable and immutable ownership

### 9.1 Final immutable closure

Nix owns:

- Hermes source and revision;
- Python interpreter and packages;
- Node.js, npm-built assets, and Electron;
- `hermes`, `hermes-agent`, `hermes-acp`, TUI, web assets, and desktop executable;
- Git, SSH, ripgrep, ffmpeg, Tirith, and other wrapper runtime tools;
- bundled skills, optional skills, plugins, locales, and optional MCP catalog;
- managed configuration; and
- future launchd definitions, if enabled.

### 9.2 Final mutable state

The following remain outside Nix because Hermes must write them or because they contain secrets or user data:

| Mutable class | Representative paths |
| --- | --- |
| User configuration overlay | `~/.hermes/config.yaml` |
| Credentials and OAuth | `~/.hermes/.env`, `auth.json`, MCP token stores |
| Identity and preferences | `SOUL.md`, user profile files, skins, desktop preferences |
| Conversation state | `state.db*`, sessions, transcripts, compression state |
| Project/task state | `projects.db`, `kanban.db`, checkpoints, worktree metadata |
| Automation state | cron jobs, execution records, ticker state |
| Memory | memories, user profile memory, provider state |
| User extensions | authored or modified skills, plugins, hooks |
| Runtime communication | pairing records, gateway state, lock files, sockets |
| Operational output | logs, caches, image/audio/browser caches |
| Desktop UI state | `~/Library/Application Support/Hermes` |

Mutable does not mean unmanaged in policy. Nix may constrain how a feature uses these paths, but it does not replace their contents with store links.

## 10. Feature surface and rollout posture

The configuration directory is intended to grow by adding real policy, not by pre-creating empty modules. The following matrix records the supported surface and its initial disposition.

| Area | Configuration roots | Initial disposition | Later Nix management |
| --- | --- | --- | --- |
| Main inference | `model`, `providers`, `fallback_providers`, credential-pool strategy | Preserve current user configuration | Render from shared model registry and profile defaults |
| Auxiliary inference | `auxiliary.*` | Preserve defaults/user values | Pin model/provider per task where cost or behavior warrants it |
| Terminal execution | `terminal.*` | Native `local` backend | SSH, Docker, Modal, Daytona, Singularity, mounts, network, resource limits |
| Tool surface | `platform_toolsets.*`, `tools.*`, `tool_output`, loop guardrails | `hermes-cli` for CLI | Per-platform least-capability sets and deferred tool discovery |
| Command approval | `approvals`, `command_allowlist`, `security` | Manual approval plus `tccutil` deny; no lazy installs | Broader deny policy, fail-closed scanning, reviewed permanent approvals |
| MCP | `mcp_servers`, `mcp.*`, discovery limits | Preserve current user servers | Catalog rendering, TLS/OAuth, filters, sampling, resources, elicitation |
| Skills | `skills.*`, external directories | Bundled upstream skills; preserve user skills | Shared skill projection after loader parity is proven |
| Plugins and hooks | `plugins`, `hooks`, `hooks_auto_accept` | Preserve installed user plugins; no auto-accept | Explicit plugin allowlist, packaged Python dependencies, managed hooks |
| Memory | `memory`, memory-provider plugin config | Preserve current state/defaults | Stable limits, write approvals, provider selection |
| Context and compression | `compression`, `prompt_caching`, context engine, file/tool limits | Preserve current behavior | Profile-specific thresholds and cost policy |
| Sessions | `sessions`, reset policy, concurrency, retention | Preserve current databases and defaults | Retention, archive, reset, and concurrency policy |
| Profiles and routing | profile homes, multiplexing, `profile_routes` | Default profile only | Declarative profile overlays and gateway routing |
| Browser and web | `browser`, `web`, proxy/network options | Preserve current settings | Provider, private-URL, recording, CDP, and persistence policy |
| Checkpoints | `checkpoints` | Preserve current setting | Capacity, pruning, and rollback policy |
| Desktop/TUI/dashboard | `desktop`, `display`, `dashboard` | Nix desktop executable; no app bundle or dashboard service | UI policy, LaunchServices app, dashboard auth/bind policy |
| Gateway platforms | `gateway`, `platforms`, Telegram, Discord, Slack, Signal, WhatsApp, Matrix, email, API/webhooks, and plugins | No service enabled by Nix | One explicit service design per enabled profile/platform |
| Cron | `cron`, jobs under mutable state | Preserve jobs; no new service | Nix-owned scheduler service and delivery policy |
| Voice and media | `tts`, `stt`, `voice`, `wake_word`, image/video generation | Available only when full package already supplies dependency | Provider/model/device policy and packaged optional dependencies |
| Delegation and code execution | `delegation`, `code_execution`, MoA, goals | Preserve defaults except no subagent auto-approval | Cost, concurrency, depth, and isolation policy |
| Kanban and curator | `kanban`, `curator` | Preserve current state/defaults | Service and maintenance policy if actively used |
| Observability | `logging`, `monitoring`, local telemetry | Local shared metrics pinned off | Retention, OTLP, health, and cost display policy |
| Secrets | `secrets.*`, environment references | Existing credential stores; no Nix values | External secret-source references and launch-context delivery |
| Updates | install method and desktop update UI | Nix only | Repository updater integration and release checks |

Top-level `toolsets` is not used: current Hermes resolves tools through `platform_toolsets`, and upstream documentation marks the former deprecated.

## 11. Desktop behavior

### 11.1 Initial desktop contract

The upstream Nix `desktop` output is an Electron command wrapper, not a signed `.app` bundle. The first deployment accepts this limitation and launches:

```text
hermes-desktop
```

The implementation proves that this command opens the existing desktop UI, uses the Nix-built Hermes backend, reads the existing mutable desktop state, and does not begin bootstrap or self-update work.

### 11.2 Mutable-runtime precedence

At the verified upstream revision, desktop backend discovery prefers a healthy `~/.hermes/hermes-agent` checkout before the `HERMES_DESKTOP_HERMES` override. Consequently, the Nix desktop cannot be considered verified while the bootstrap checkout remains active at that path.

Migration therefore uses this order:

1. Build and inspect the Nix packages.
2. Stop Hermes writers with explicit authorization.
3. Move the mutable checkout to a private quarantine path.
4. Launch the Nix desktop executable.
5. Prove the backend executable resolves into the Nix closure.
6. Restore the checkout immediately if verification fails.
7. Delete the quarantine only after post-cutover acceptance.

### 11.3 Deferred application integration

A later work item may produce a stable `Hermes.app`, Dock/Finder integration, the `hermes:` URL scheme, fixed bundle identity, signing, notarization, and stable TCC behavior. These are not prerequisites for the first Nix cutover and are not to be smuggled into it.

The downloaded setup application is removed after the Nix executable is accepted. Its signed identity is not reused or claimed by the first Nix desktop command.

## 12. Migration and cleanup

Migration is an operator transaction, separate from package construction. Every mutating step requires explicit authorization when executed.

### 12.1 Preflight inventory

Record, without displaying secret contents:

- current repository revision and dirty state;
- current Darwin generation;
- setup app/cask version and signature identity;
- Hermes checkout revision and install marker;
- `~/.hermes` owner, mode, inode, byte count, and entry count;
- names, modes, and sizes of state databases and secret-bearing files;
- existing Hermes processes and launchd labels;
- existing executable/symlink locations;
- shared uv Python and Playwright cache consumers;
- installer-marked PATH additions in shell startup files; and
- mutable desktop support paths.

A missing or unreadable state path is a blocker, not permission to create a replacement over it.

### 12.2 Backup

With Hermes writers stopped, create an opaque private backup of:

- `~/.hermes`;
- `~/Library/Application Support/Hermes`;
- `/Applications/Hermes.app`; and
- any Hermes-owned launchd artifact found during inventory.

The operation does not print file contents. Validate ownership, permissions, counts, byte sizes, and SQLite integrity. A live copy of databases with active WAL writers is not accepted as a backup.

### 12.3 Build before activation

Build the CLI and desktop packages and the complete Darwin system without activation. Evaluate portable contracts on all supported systems. No current executable or state path changes during this stage.

### 12.4 Reversible cutover

1. Stop Hermes processes.
2. Quarantine `~/.hermes/hermes-agent` outside the resolver’s active path.
3. Activate the built Nix generation after explicit authorization.
4. Verify CLI and desktop behavior first with an isolated temporary `HERMES_HOME`, then with the real state root.
5. Confirm mutable databases, sessions, projects, memory, configuration, and desktop preferences remain accessible.
6. Confirm no bootstrap, Git update, pip, uv, npm, private Node, or lazy installer is invoked.

### 12.5 Bootstrap artifact removal

After acceptance, remove all verified bootstrap-owned artifacts:

| Remove | Condition |
| --- | --- |
| Homebrew `hermes-desktop` cask receipt and `/Applications/Hermes.app` setup stub | Nix desktop executable accepted |
| Quarantined `~/.hermes/hermes-agent` checkout, venv, and `node_modules` | Nix backend path proven |
| `~/.hermes/node` | All enabled Node-dependent features use Nix Node.js |
| `~/.hermes/bootstrap-cache` | No bootstrap path remains active |
| `~/.hermes/hermes-setup` | Setup rollback no longer required |
| Installer-created regular launchers `~/.local/bin/hermes` and `hermes-acp` | File content and ownership identify the mutable checkout; Home Manager commands are active first on PATH |
| Installer-created `~/.local/bin/node`, `npm`, and `npx` symlinks | Every link is proven to target removed bootstrap content |
| Nix-replaced files in `~/.hermes/bin` | Per-file ownership proven; user/runtime-only tools preserved |
| uv Python used by the old venv | No remaining environment uses that exact interpreter; never delete the shared uv root |
| Hermes-installed Playwright browser versions | Nix supplies the enabled browser dependency, or browser capability is disabled, and no other consumer uses those versions |
| Installer-marked shell PATH lines | Exact block is proven installer-added and `~/.local/bin` is no longer required by another executable; otherwise preserve effective PATH |

Do not recursively delete `~/.hermes/bin`, `skills`, `plugins`, the shared uv Python root, or the shared Playwright cache. Reconcile them by manifest, target, consumer, and content identity:

- remove unchanged bundled copies now provided by the Nix package;
- preserve user-created or modified entries;
- preserve runtime tools not yet provided by Nix; and
- record every retained exception as mutable or as a later packaging task.

### 12.6 End-state proof

After cleanup:

- no active executable resolves into `~/.hermes/hermes-agent`, its venv, its `node_modules`, or `~/.hermes/node`;
- no Hermes cask or setup app remains;
- immutable runtime paths resolve into the current Nix generation;
- `~/.hermes` contains only classified mutable state and retained exceptions;
- the managed configuration file is generated from `config/fleet/hermes/default.nix`; and
- a rebuild reproduces the same runtime without network installation at launch.

## 13. Verification contract

### 13.1 Static and evaluation checks

The implementation adds focused checks which establish:

1. Hermes input revision is coherent across root and portable locks.
2. The overlay exposes the package exactly once.
3. Hera selects CLI and desktop packages; Clio and Linux home profiles do not install them.
4. The renderer owns only `.config/hermes/nix-managed/config.yaml`.
5. Parent-path, duplicate-path, and collision guards include the Hermes managed directory.
6. Fields classified as secret-bearing accept typed environment references only; generated output contains reference names and never resolved values.
7. Managed environment references retain literal `${NAME}` form.
8. Unsupported values and obsolete top-level `toolsets` fail evaluation.
9. The wrapper uses a regular, complete managed file and preserves explicit environment overrides.
10. `HERMES_HOME` remains mutable and is never a store path.

### 13.2 Package checks

Build and inspect both selected outputs on `aarch64-darwin`:

- `hermes --version` and `hermes --help`;
- `hermes-desktop` wrapper structure;
- Python import and entry-point availability;
- Node.js, Git, SSH, ripgrep, ffmpeg, and Tirith resolution;
- bundled skills, plugins, locales, TUI, web, and MCP catalog paths; and
- absence of references to the bootstrap checkout, venv, private Node tree, and user home from the derivation.

The package test runs with a temporary empty home and no credentials.

### 13.3 Configuration behavior

Against temporary homes, prove:

- managed leaf wins over conflicting user leaf;
- unmanaged sibling remains user-controlled;
- a managed list replaces the user list;
- malformed or missing managed configuration prevents the local wrapper from launching;
- user config remains byte-identical after reads and failed launches;
- managed config does not block writes to unowned user preferences;
- store-path detection disables self-update behavior; and
- `security.allow_lazy_installs = false` produces a clear failure rather than a runtime install.

### 13.4 Incident regression

Use the terminal approval layer with a stubbed executor and prove that every terminal-tool command containing `tccutil reset All` is denied before execution, including absolute paths, bundle-scoped variants, and commands which contain the phrase as quoted text. This conservative rule may reject harmless commands such as `echo "tccutil reset All"`; that false positive is accepted because an operator can run such text outside Hermes. No test invokes real `tccutil` or changes TCC.

### 13.5 Migration checks

Cleanup remains an operator runbook, not a new migration framework. Tests cover only production helpers introduced by implementation. If a classification or cleanup-plan helper is added, temporary-directory fixtures prove its symlink handling, per-file ownership decisions, modified skill/plugin preservation, and idempotent plan output. If no helper is required, the cutover and cleanup are verified by recorded preflight and postflight evidence rather than duplicate test-only shell logic.

No automated deletion test touches a real home directory.

### 13.6 Runtime acceptance

After authorized activation, observe:

1. `command -v hermes` resolves through the Home Manager generation.
2. `hermes` reports the expected pinned version and install method.
3. `hermes update` directs the operator to Nix and makes no change.
4. `hermes-desktop` opens without bootstrap and uses the Nix backend.
5. Existing projects and sessions are visible without transcript output.
6. State database integrity checks pass.
7. Existing secrets retain ownership and mode and never appear in logs or process arguments.
8. The interactive UI opens against an isolated home and exits without submitting a provider request.
9. No unexpected launchd service is registered.
10. Restarting the desktop preserves state.

Provider calls, microphone, camera, Accessibility, Input Monitoring, Full Disk Access, and other permission-bearing probes require separate authorization and are not implicit in activation.

### 13.7 Repository gates

Run the repository’s established checks, correcting only failures attributable to this work:

```bash
python3 -m unittest -v test/bin/update-overlay-test.py
nix flake check ./config/fleet --all-systems --no-build
make test
./build system
nix fmt
lefthook run pre-commit --all-files
```

A pre-existing failure is reported and classified; it is not bypassed or silently folded into the Hermes change.

## 14. Update and rollback

### 14.1 Updates

Hermes updates are ordinary source updates:

1. update the pinned flake input through the repository transaction;
2. review source and lock deltas;
3. build package and system outputs;
4. run focused and broad checks;
5. activate only with authorization; and
6. repeat runtime acceptance.

No update path writes into the Nix store or resurrects a mutable checkout.

### 14.2 Rollback

Before cleanup, rollback restores the previous Darwin generation and moves the quarantined checkout back into place. Mutable state is not overwritten.

After bootstrap artifact deletion, rollback uses the previous Nix generation. The opaque backup remains available until the operator explicitly releases it. Restoring the entire state backup is never the default because it would discard sessions and changes created after migration; full restore requires stopped writers and explicit acknowledgement of that data-loss boundary.

Garbage collection and generation deletion do not occur during the rollback window. The Home Manager/system generation keeps the active package closure rooted.

## 15. Delivery phases

### Phase 0 — Accept specification and establish authority

- Review this document and resolve any changed decisions.
- Create a current Fleet Configuration Programme work item with acceptance, rollback, authorization, and verification commands.
- Capture a clean implementation baseline without disturbing unrelated work.

**Done when:** specification and work item are accepted; no implementation has begun prematurely.

### Phase 1 — Package and source

- Add the portable upstream flake input and paired lock authority.
- Expose thin local CLI and desktop wrappers.
- Export packages without selecting them on any host.
- Add package and update-contract tests.

**Done when:** CLI and desktop outputs build on Hera and no runtime path references the bootstrap installation.

### Phase 2 — Managed configuration

- Add `config/fleet/hermes/default.nix` and the Hermes renderer.
- Add the Hera profile and profile-driven package selection.
- Generate the initial managed leaves and wrapper preflight.
- Add renderer, collision, environment-reference, and incident-regression tests.

**Done when:** a temporary-home launch proves managed policy and mutable-state separation without activation.

### Phase 3 — Darwin build and independent review

- Build the complete Hera system without switching.
- Run focused and repository-wide gates.
- Conduct independent package, configuration, migration, and simplicity review.

**Done when:** every accepted finding is resolved and the exact activation diff is known.

### Phase 4 — Authorized cutover

- Stop writers, back up state, and quarantine the mutable runtime.
- Activate the already-built generation.
- Run runtime acceptance and observe the actual desktop/backend path.

**Done when:** Hermes works from Nix against preserved real state, with no bootstrap or runtime installation.

### Phase 5 — Authorized cleanup

- Remove cask/setup app and every proven bootstrap-owned dependency.
- Reconcile mixed mutable directories without deleting user work.
- Re-run runtime and state-integrity checks.

**Done when:** only classified mutable state remains outside Nix and the rollback boundary is recorded.

### Phase 6 — Incremental enrichment

Add one feature category at a time to `config/fleet/hermes/default.nix`, with a focused contract for each. Likely order:

1. shared model/provider rendering;
2. MCP catalog rendering;
3. skills and hook projection;
4. memory, compression, and session policy;
5. browser and media dependencies;
6. gateway and cron services;
7. signed macOS application integration; and
8. stronger isolation and security policy.

No later category is required to declare the initial migration complete.

## 16. Initial non-goals

The first implementation does not:

- containerize Hermes or introduce OpenShell;
- claim the in-process approval gate is a security boundary;
- create a launchd gateway, cron ticker, dashboard, or messaging service;
- deploy to Clio or Linux hosts;
- produce or sign a native `.app` bundle;
- manage TCC grants or run `tccutil`;
- redesign provider credentials;
- package every optional third-party plugin immediately;
- prune the upstream full dependency closure;
- relocate `HERMES_HOME`;
- import mutable session or memory data into Nix; or
- delete bootstrap artifacts before a verified cutover.

These omissions are deliberate. They keep the first change small enough to understand and reverse.

## 17. Review points

This draft adopts the following defaults unless review changes them:

- managed directory: `~/.config/hermes/nix-managed`;
- initial package variant: upstream `default` plus `desktop`;
- initial execution backend: native local;
- initial desktop UX: `hermes-desktop` command, not `.app`;
- initial host: Hera only;
- existing model/provider configuration: preserved, not yet rendered from the shared catalog;
- services: disabled;
- bootstrap cleanup: performed only after runtime acceptance; and
- quarantine backup: retained until explicitly released.

Review should concentrate on whether these defaults are correct, whether the mutable/immutable classification omits any user-owned state, and whether any feature category belongs in the initial managed overlay rather than Phase 6.

## 18. Acceptance criteria for this specification

The specification is ready for implementation planning when the reviewer can answer yes to each statement:

- One source and update authority is named.
- Exact package, renderer, composition, and state owners are named.
- Initial scope is useful without requiring container or service design.
- Every current bootstrap artifact has a preserve, quarantine, remove, or reconcile disposition.
- No secret value is required in Nix.
- Existing state survives activation and rollback.
- Desktop verification cannot accidentally use the old mutable checkout.
- Runtime installers and self-update paths are excluded from the managed runtime.
- Feature surface is recorded without enabling it all at once.
- Tests prove configuration precedence, package identity, state preservation, and the `tccutil` regression.
- Cleanup follows successful cutover rather than preceding it.
- Every destructive or externally consequential operation remains separately authorized.
