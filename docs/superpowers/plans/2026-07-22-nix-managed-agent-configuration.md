# Nix-Managed Agent Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace promptdeploy as the active desired-state mechanism for Claude Code, Codex, OpenCode, Droid, and Pi with immutable `ai-nix` resources/wrappers and exact Home Manager leaves in `/Users/johnw/src/nix`, then migrate and roll out the result across the approved fleet.

**Architecture:** `/Users/johnw/src/ai-nix` packages pinned external resources, three thin executable wrappers, and the one standard Droid HTTP-header bridge required by its installed client. `/Users/johnw/src/nix` owns the canonical catalog, model data, five native renderers, explicit profile selection, exact Home Manager leaves, previous-generation safety checks, and the Hera-only model-sync activation. Promptdeploy is used once from a frozen nonsecret snapshot as a read-only parity oracle; no converter, manifest, deployer, merge engine, SSH/rsync deployment path, or runtime installer survives.

**Tech Stack:** Nix flakes, Home Manager activation DAGs, `pkgs.formats.json`, `lib.generators.toTOML`, shell checks in Nix derivations, Python `tomllib` for independent TOML parsing, `jq` for independent JSON parsing, and immutable inputs from `llm-agents.nix` and pinned upstream sources.

## Global Constraints

- For Tasks 1–12, work only in `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources` on `feat/nix-managed-agent-resources` and `/Users/johnw/src/nix.worktrees/nix-managed-agent-config` on `feat/nix-managed-agent-config`. Preserve the dirty main worktrees and `/Users/johnw/src/promptdeploy` unchanged. Task 12 must enumerate every exact external consumer repository and file that Task 13 would change before any such mutation.
- The starting commits are `0610fd1283cf5ee52a5c71cbc8411a647b37dd7c` for `ai-nix` and `e5e08e2b20229646e34f3dde570f345c4df85361` for the approved Nix design.
- Durable authority record: the later explicit active implementation goal and the user's earlier push instructions authorize Tasks 1–12 and ordinary, non-force branch pushes. They do not self-authorize Task 13 host mutation or retirement. Task 13 proceeds only when the durable handoff explicitly records that authority and every host operation can run from that host's local shell without deployment SSH.
- Follow RED -> verify the intended failure -> minimal GREEN -> focused checks -> independent task review -> fess audit -> commit for every task. These per-commit audits and safe local rebases are explicit requirements of the active `$command-wiggum` protocol, not additional product scope.
- In the Nix repository, use Anvil first for supported reads/edits and check for modified file-backed Emacs buffers before every edit batch and again before each commit. Explain any narrow shell or `apply_patch` fallback.
- Do not run `nix develop`, install dependencies, invoke `uv`, or invoke `npm`. Task 4 is the deliberate promptdeploy-environment exception: `de` is forbidden there because it loads `.env` and enters through `nix develop`; the oracle runs with an allowlisted `env -i` environment instead.
- Baseline gate: the full `ai-nix` check has exited 0. The Nix check reached only the classified pre-existing empty-PID-marker race; its one focused retry must finish and be recorded before Task 1, and any repeated or different failure must be diagnosed. This is a gate, not a Task 0.
- Do not edit promptdeploy. Never read or copy `.env`, `.env.*`, password stores, SOPS data, auth/session state, or expanded live client configuration into Git, the Nix store, fixtures, argv, or logs.
- Every state-reading or state-writing promptdeploy oracle command uses the named `#promptdeploy` app and a non-symlinked `--target-root`; the read-only `validate` command is the sole exception because its parser has no `--target-root` option. Never use the default app, `#raw`, or `--dry-run`.
- Canonical secret references have exactly the Nix shape `{ env = "NAME"; }`. Evaluation and builds succeed with all secret sources absent.
- `ai-nix` packages resources, wrappers, and the pinned Droid header bridge only. `nix` alone selects profiles, renders client formats, and declares destinations.
- Do not create a public options framework, dependency graph, persistent converter, ownership manifest, ownership stamp, reconciliation engine, force/adoption mode, general deployer, remote copier, or runtime downloader.
- Fixed wrapper companion pairs are Claude `nix-managed-settings.json` + `nix-managed-mcp.json`, Codex `nix-managed.config.toml` + `hooks.json`, and Droid `nix-managed-settings.json` + `mcp.json`. Zero files pass through, two files inject, one file fails closed, and `AI_NIX_BYPASS_MANAGED_CONFIG=1` skips only the new injection.
- OpenCode and Pi use native discovery and receive no wrapper.
- Home Manager owns exact files or complete immutable skill directories, never `.claude`, `.codex`, `.agents`, `.factory`, `.pi`, an XDG client root, or any mutable authentication/session/cache/trust/UI/package state.
- The shared work profile is selected by Linux account/home class (`jwiegley`), not by trusting the configured `andoria-08` hostname. Only Andoria-08 activates it, after all four physical hosts locally realize and root both old and new closures.
- GPTel, git-ai, their files, and their archival promptdeploy manifests are untouched. Runtime `drafts-hera` SSH remains; deployment SSH/rsync does not.
- Preserve Sherlock under its existing separate Nix writer. Do not absorb it into this catalog or create a second Sherlock path.
- DEVONthink/iTerm2 synchronization is Hera-only, activation-time, and digest-gated. One isolated JXA process may inspect the DEVONthink credential only to return a Boolean nonempty result; the bytes never leave that process and are never returned, copied, hashed, logged, persisted, placed in argv/store state, or rewritten. iTerm2 checks Keychain item metadata only.

## Frozen Source Authorities

The Phase-A snapshot must match these SHA-256 values before any import. A mismatch stops the task and requires a newly reviewed freeze; it is never silently accepted.

| Source | SHA-256 |
|---|---|
| `deploy.yaml` | `9a18492297f8b1b9d3919b180f3a82b7b5dd6c9141b3b65f5e8ee8d542f0c346` |
| `models.yaml` | `c6a18cba992a54500796bd26cd99ffeeb422b080a72f7bc6065474457e8db98d` |
| `settings.yaml` | `ef45db2fc07aa4d4e7a465ec9a950403693dc17c43c72b3cfa28fb3342a44fa0` |
| `prompts/emacs.poet` | `1f499971b038daf557ac503e958fa15a87d95b11adffd451145e4c59fbc04176` |
| `prompts/spanish.poet` | `e91d1534e49abf6aafedd614a018af1d895d9271f3540940f0d53cbf5c3b0875` |
| `bundles/ponytail.yaml` | `06767aabfb78fed35e7438e9e89ea28982e14b7d0e367dec46dfa3a0781520b8` |
| `skills/.promptdeploy-skill-links.json` | `054d59d541bf57ead9db9413c249734f276010d3d1db4cdf03e954fa0c5b5eaf` |
| `translate-tool/skill/SKILL.md` | `f26ff06e43b9d99e96876cbd567a7f6d8585983b0a550b97ef5e672f294790fb` |
| `translate-tool/glossary.csv` | `8eab769223267b8b8cded5ba62f7a4250dfcf25d94d35cffd7e360354b3e9523` |
| `statusline-command.sh` | `7cb1fcb475bc94fb61b7324ab6ff2f349e3bfe86fdca775e19842fd74dd28729` |
| `flake.nix` | `e75ed8bcaa21fe1b155fddc5e84d50cf560eeff244267646aae5ffd233e7ded4` |
| `flake.lock` | `66bd535e13626f2232c31b196ae035f9f08a5deccb611e2568b6ab5af4628c9f` |

Pinned composed resources are Superpowers `d884ae04edebef577e82ff7c4e143debd0bbec99`, Ponytail `16f29800fd2681bdf24f3eb4ccffe38be3baec6b`, and promptdeploy's frozen `llm-agents.nix` source `ba8c89d5b4836d46f7bdbffd2df34c66dadef725`. The selected standard bridge is `geelen/mcp-remote` version `0.1.38`, revision `02619aff36e79803d7c894e8c8ae7b34b2d11f8c`, NAR `sha256-+oNI2Uq7gW3sLzJS4ky2+BXhTmo44+WpcdYgieGPpmI=`, with `pnpm-lock.yaml` SHA-256 `598f60becf15b3197fce5c4e38e8158f3db2f774d218a443e50b3b5e2b098542`. Record only these required environment-variable names: `ANTHROPIC_API_KEY`, `CONTEXT7_API_KEY`, `GEMINI_API_KEY`, `LITELLM_API_KEY`, `NVIDIA_API_KEY`, `OPENAI_API_KEY`, `PERPLEXITY_API_KEY`, and `REF_API_KEY`.

Frozen git-surgeon parity is exact: current and frozen promptdeploy resolve to the same source store path; `SKILL.md` is `086445cd0424c46022c7c23912c82ebb43d168e11b3a13141669149bdba6f8bc` and `LICENSE` is `dfc0be306ac621b63914bf0f4854538a2e0a8d09ad24f20e7edd9a80ece241b2` (SHA-256).

## Locked Interfaces and File Map

`agent-resources` exposes complete immutable trees at:

```text
$out/share/agent-resources/skills/<name>/
$out/share/agent-resources/pi-extensions/pi-mcp-adapter/
$out/share/agent-resources/pi-extensions/pi-subagent/
```

Every renderer has this logical interface:

```nix
render = {
  profile,
  selected,
  modelData,
  homeDirectory,
  xdgConfigHome,
}: {
  files = {
    "relative/source-path" = { source = /nix/store/path; };
    "relative/generated-path" = { text = "generated native document"; };
  };
  companions = [ "relative/home/path" ];
  requiredEnvNames = [ "ENV_NAME" ];
};
```

Only the Pi renderer adds `mutableMcpGuard = { path = ".pi/agent/mcp.json"; forbiddenKeys = [ "mcpServers" "imports" ]; };`. `files` keys are relative to `config.home.homeDirectory`; all absolute paths derive from `homeDirectory` or `xdgConfigHome`.

Create or modify only these implementation surfaces:

```text
/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/
  flake.nix
  flake.lock
  README.md
  scripts/lint.sh
  overlays/30-agent-resources.nix
  overlays/30-ai-mcp.nix
  packages/agent-resources.nix
  patches/mcp-remote-header-only.patch
  tests/agent-resources.nix
  tests/agent-wrappers.nix
  tests/agent-wrappers.sh

/Users/johnw/src/nix.worktrees/nix-managed-agent-config/
  flake.nix
  flake.lock
  config/johnw.nix
  config/ai.nix
  config/ai/catalog.nix
  config/ai/models.nix
  config/ai/preflight.nix
  config/ai/model-sync.nix
  config/ai/renderers/{claude,codex,opencode,droid,pi}.nix
  config/ai/{agents,commands,skills,prompts}/...
  config/ai/statusline-command.sh
  packages/ai-home-manager-smoke.nix
  docs/migrations/nix-managed-agent-oracle.md
  docs/runbooks/nix-managed-agent-configuration.md
```

Preserve `config/xdg-symlinks.nix`, `bin/persona`, mutable client roots, and every unrelated dirty file.

---

### Task 1: Package Static External Resources in `ai-nix`

**Files:**

- Modify: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/flake.nix`
- Modify: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/flake.lock`
- Modify: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/README.md`
- Modify: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/scripts/lint.sh`
- Create: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/overlays/30-agent-resources.nix`
- Create: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/packages/agent-resources.nix`
- Create: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/tests/agent-resources.nix`

**Consumes:** flake-false pins for Superpowers, Ponytail, and translate-tool at `bffdb7ba3e5db603ea1390fee555354c1d45d642`; git-surgeon from a source proven equal to the frozen `llm-agents.nix` revision `ba8c89d5b4836d46f7bdbffd2df34c66dadef725`.

**Produces:** `packages.${system}.agent-resources` and `pkgs.agent-resources`, containing every expected Superpowers skill, exactly six Ponytail static skills, git-surgeon, and materialized `translate-en/SKILL.md` plus `GLOSSARY.csv`.

- [ ] **Step 1: Add the failing resource check before the package exists.**

  In `tests/agent-resources.nix`, define one `runCommand` check that requires `SKILL.md` in all expected roots, compares framed path/type/mode/symlink-target/content manifests to their pinned sources, rejects dangling symlinks and duplicate names, and rejects Ponytail `hooks`, runtime, statusline, bundle-receipt, and OpenCode-plugin payloads. The expected Superpowers set is:

  ```text
  brainstorming dispatching-parallel-agents executing-plans
  finishing-a-development-branch receiving-code-review requesting-code-review
  subagent-driven-development systematic-debugging test-driven-development
  using-git-worktrees using-superpowers verification-before-completion
  writing-plans writing-skills
  ```

  The expected Ponytail set is:

  ```text
  ponytail ponytail-review ponytail-audit ponytail-debt ponytail-gain ponytail-help
  ```

  Register it as `checks.${system}.agent-resources` in `flake.nix`.

- [ ] **Step 2: Run RED and confirm the intended failure.**

  ```sh
  cd /Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  nix build -L path:.#checks.aarch64-darwin.agent-resources
  ```

  Expected: evaluation fails because `pkgs.agent-resources` and the required skill roots do not exist. A Nix parse failure is not an acceptable RED.

- [ ] **Step 3: Add only the static source inputs and resource package.**

  Add flake-false inputs for `github:obra/superpowers/d884ae04edebef577e82ff7c4e143debd0bbec99`, `github:DietrichGebert/ponytail/16f29800fd2681bdf24f3eb4ccffe38be3baec6b`, and `github:jwiegley/translate-tool/bffdb7ba3e5db603ea1390fee555354c1d45d642`. In `packages/agent-resources.nix`, copy complete skill directories into `$out/share/agent-resources/skills` and materialize translate-en's glossary as an ordinary store file. Use the current ai-nix git-surgeon source only after the check proves its source store path matches frozen promptdeploy and its `SKILL.md`/`LICENSE` hashes equal `086445cd0424c46022c7c23912c82ebb43d168e11b3a13141669149bdba6f8bc` and `dfc0be306ac621b63914bf0f4854538a2e0a8d09ad24f20e7edd9a80ece241b2`; otherwise pin frozen llm-agents `ba8c89d5b4836d46f7bdbffd2df34c66dadef725` separately. Refuse duplicate destination names before copying.

  `overlays/30-agent-resources.nix` must expose exactly:

  ```nix
  final: _prev: {
    agent-resources = final.callPackage ../packages/agent-resources.nix { };
  }
  ```

  Inputs are already available as `pkgs.inputs` from the first overlay; do not add a second dependency channel. Extend `scripts/lint.sh` so both `statix` and `deadnix` cover `packages` and `tests` in addition to their existing surfaces.

- [ ] **Step 4: Run GREEN.**

  ```sh
  cd /Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  nix build -L path:.#checks.aarch64-darwin.agent-resources
  nix build -L path:.#packages.aarch64-darwin.agent-resources
  nix flake check -L path:.
  ```

  Expected: all commands exit 0; the check names exactly 14 Superpowers skills, six Ponytail skills, git-surgeon, and translate-en, with no dangling link or excluded Ponytail payload.

- [ ] **Step 5: Review, fess-audit, and commit.**

  Review the public output paths and source pins independently; run the fess audit; then commit only this task as `feat: package immutable agent skill resources`.

---

### Task 2: Record and Package Exact Pi Extension Closures

**Files:**

- Modify: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/flake.nix`
- Modify: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/flake.lock`
- Modify: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/packages/agent-resources.nix`
- Modify: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/tests/agent-resources.nix`
- Modify: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/README.md`

**Consumes:** Task 1's derivation, the system-matched Pi package/version from llm-agents, and read-only upstream metadata for pi-mcp-adapter and pi-subagent.

**Produces:** self-contained immutable extension roots at `pi-extensions/pi-mcp-adapter` and `pi-extensions/pi-subagent`, directly linkable by Home Manager without `pi install` or mutable package state.

- [ ] **Step 1: Establish exact source authority before calling either extension pinned.**

  Record and independently verify these read-only freeze values before implementation:

  - pi-mcp-adapter: rev `82724dccc13a49310530898f922bafff12b7f3fe`, NAR `sha256-JjYS9tPSoVuubdmHTqTNNYfDJOc9CBPvVbIxvdJWi7M=`, package `2.11.0`, `package-lock.json` SHA-256 `156cd7b65090cb5600651b40563dea3974fbeeaa7dbb6346f3deb0e9e0528bd0`.
  - pi-subagent: rev `70248dcf7c8a5ca74497e817a699f009c55e6917`, NAR `sha256-TyeqNoz5RLRlDWY4rcZbOY/UCHOMiNIjuGsW2xZoTEE=`, package `3.0.0`, `package-lock.json` SHA-256 `a7fbb2c6c10ee6af111dcf7a10064770cc360e818b6f424854c231ed6872d5ff`, Pi peer floor `>=0.80.5`.

  The current llm-agents Pi is `0.81.1`, satisfying that floor. Record each declared entrypoint from its manifest as part of the same evidence. No packaging implementation begins before all values reverify.

- [ ] **Step 2: Extend the resource test with missing Pi-extension assertions.**

  Require each upstream package manifest and declared entrypoint, resolve every pi-mcp-adapter runtime import using its packaged Node closure, reject dangling links, and assert pi-subagent's declared Pi peer range accepts the pinned llm-agents Pi version.

- [ ] **Step 3: Run RED.**

  ```sh
  cd /Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  nix build -L path:.#checks.aarch64-darwin.agent-resources
  ```

  Expected: the two `pi-extensions` roots are missing while every Task 1 assertion remains green.

- [ ] **Step 4: Package the two now-recorded extension closures.**

  Add flake-false inputs using the exact recorded revisions and NAR hashes for `nicobailon/pi-mcp-adapter` and `mjakl/pi-subagent`. Require the fetched `package-lock.json` hashes to equal the recorded values before building self-contained roots; include only declared runtime files, package metadata, and licenses. Do not register them, run lifecycle scripts at activation, or write beneath `~/.pi`.

- [ ] **Step 5: Run GREEN.**

  ```sh
  cd /Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  nix build -L path:.#checks.aarch64-darwin.agent-resources
  nix build -L path:.#packages.aarch64-darwin.agent-resources
  nix flake check -L path:.
  ```

  Expected: both extension entrypoints resolve entirely inside the `agent-resources` closure; revision, NAR hash, lock hash, and Pi compatibility assertions all pass.

- [ ] **Step 6: Review, fess-audit, and commit.**

  Review closure completeness and the absence of runtime installation; run the fess audit; commit as `feat: package pinned Pi extensions`.

---

### Task 3: Implement the Claude, Codex, and Droid Wrappers and Header Bridge

**Files:**

- Modify: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/flake.nix`
- Modify: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/flake.lock`
- Modify: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/README.md`
- Modify: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/overlays/30-ai-mcp.nix`
- Create: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/patches/mcp-remote-header-only.patch`
- Create: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/tests/agent-wrappers.nix`
- Create: `/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources/tests/agent-wrappers.sh`

**Consumes:** the unchanged public function signature `lib.patchAgentPackage pkgs name package`, the existing Codex host-local SQLite/log behavior, and the exact frozen `mcp-remote` source recorded above. Source inspection has already proved Pi's pinned adapter expands header environment references natively, while Droid passes its `mcp.json` argv literally and therefore needs the bridge.

**Produces:** managed public binaries for Claude, Codex, and Droid, plus `claude-real`, `pkgs.agent-http-header-bridge`, and `packages.${system}.agent-http-header-bridge`; all other package patching remains unchanged.

- [ ] **Step 1: Build fake upstream packages and write the wrapper matrix first.**

  The shell test must record argv and environment for: both paths wholly absent; two usable regular-file targets; each one-file mixed state; dangling symlinks; directories; FIFO/non-regular types; one usable plus one dangling/type-invalid companion; conflicting separated and `--flag=value` forms; Codex `--profile`, `--profile=...`, and `-p`; explicit bypass in every state; paths containing spaces; upstream nonzero exit propagation; and Codex host-local state in managed and bypass modes. It must also prove error output is bounded/redacted to client name and artifact paths, never file content. Add a real-package smoke using the exact pinned Codex binary: under a synthetic `CODEX_HOME`, place a deliberately strict, recognizable `nix-managed.config.toml`, invoke `codex --profile nix-managed --strict-config features list` (or an equally nonnetworked config-reading subcommand), and require behavior that can occur only if that exact file was loaded; the same behavior must be absent without `--profile`. In the same RED check, add the complete static-header bridge cases specified in Step 6 while `pkgs.agent-http-header-bridge` is still absent.

- [ ] **Step 2: Run RED.**

  ```sh
  cd /Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  nix build -L path:.#checks.aarch64-darwin.agent-wrappers
  ```

  Expected: Claude and Droid delegate without injection, Codex omits `--profile nix-managed`, partial states launch upstream, `claude-real` is absent, and the bridge package/output is missing. A Nix parse failure is not an acceptable RED.

- [ ] **Step 3: Implement one small companion classifier and the Claude wrapper.**

  The classifier never opens either file. It returns `zero` only when both paths satisfy `! -e && ! -L`; it returns `complete` only when both resolve as usable regular files (`-f`); every dangling link, directory, special type, or mixed state returns `partial` and fails. Check `AI_NIX_BYPASS_MANAGED_CONFIG=1` before classification so explicit recovery always delegates while preserving pre-existing wrapper behavior. Claude uses `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, injects `--settings <root>/nix-managed-settings.json --mcp-config <root>/nix-managed-mcp.json`, never injects `--strict-mcp-config`, and rejects caller-supplied `--settings` or `--mcp-config` only in complete mode. Add `claude-real` as a direct exec of the original binary.

- [ ] **Step 4: Add managed selection to the existing Codex wrapper without restructuring it.**

  Preserve every current host-local SQLite/log statement. Immediately before its existing final `exec`, classify `$CODEX_HOME/nix-managed.config.toml` and `$CODEX_HOME/hooks.json`; complete mode prepends `--profile nix-managed`, partial mode exits with a repair message, and complete mode rejects explicit profile flags. Bypass skips this classification/injection but still executes all host-local-state logic.

- [ ] **Step 5: Add the Droid wrapper.**

  Use `$HOME/.factory` as the runtime root, classify `nix-managed-settings.json` and `mcp.json`, and in complete mode inject `--settings <root>/nix-managed-settings.json`. Reject explicit `--settings` only in complete mode. The wrapper never reads base `settings.json`, `mcp.json`, or a secret source.

- [ ] **Step 6: Package and test the single-purpose Droid header bridge.**

  Add one flake-false input for `github:geelen/mcp-remote/02619aff36e79803d7c894e8c8ae7b34b2d11f8c`, require its recorded NAR and `pnpm-lock.yaml` hashes, and expose the package through the existing output machinery. In the existing `overlays/30-ai-mcp.nix`, package that exact source behind a narrow `agent-http-header-bridge URL HEADER ENV_NAME` interface and the reviewed `mcp-remote-header-only.patch`; do not add another overlay/package abstraction or write a second proxy. The wrapper accepts only an HTTPS URL, a syntactically valid header name, and a valid environment-variable name; requires that variable to be present and nonempty without printing it; then directly invokes the packaged executable with the literal `${ENV_NAME}` placeholder, `--header-only`, `--transport http-only`, and `--silent` (never a shell, `npx`, or `--debug`). The bridge process is the one approved stdio child allowed to inherit that named credential. Header-only mode must skip OAuth discovery, provider/coordinator construction, callback-port selection, browser launch, config-directory access, retries, and token/lock/client persistence; make 401 and redirects fatal; resolve exactly the declared placeholder in-process; delete the consumed variable from `process.env` immediately after resolution; spawn no further subprocess; and emit only fixed bounded errors without raw `Error` or header objects. The resolved value may exist only in that process's inherited environment until deletion, its header map, and the outbound TLS request: it must not enter argv, a URL, any further child environment, logs, store paths, config/cache filenames, or persisted files. Exercise the actual patched binary against a recording local HTTPS MCP server; assert exact sentinel header delivery, the expected MCP request count with no discovery/retry, fatal 401/redirect behavior, failing OAuth/config/browser shims never invoked, a complete runtime filesystem scan, bounded stderr, and sentinel absence from argv, any further child environment, stdout/stderr, runtime filenames/content, and the store closure. Make the already-written RED cases pass without weakening them.

- [ ] **Step 7: Run GREEN and regression checks.**

  ```sh
  cd /Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  nix build -L path:.#checks.aarch64-darwin.agent-wrappers
  nix build -L path:.#checks.aarch64-darwin.agent-resources
  nix flake check -L path:.
  ```

  Expected: every matrix case and the real pinned-Codex profile-file smoke pass. Before editing, record the derivation paths for the exact non-target agent set `git-surgeon`, `mcporter`, `opencode`, and `pi`, plus the pre-existing Gemini-patch derivation; after GREEN require all five paths unchanged. No open-ended “unrelated package” claim is accepted.

- [ ] **Step 8: Review, fess-audit, and commit.**

  Obtain an interface/security review of conflict parsing, bypass scope, raw Claude resolution, preserved Codex state, and bridge secret/OAuth boundaries; run the fess audit; commit as `feat: inject Nix-managed agent configuration`.

---

### Task 4: Freeze the Promptdeploy Oracle and Import Canonical Assets

**Files:**

- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/packages/ai-home-manager-smoke.nix`
- Modify: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/flake.nix`
- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai/agents/*.md`
- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai/commands/*.md`
- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai/skills/*/`
- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai/prompts/emacs.md`
- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai/prompts/spanish.md`
- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai/statusline-command.sh`
- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/docs/migrations/nix-managed-agent-oracle.md`

**Consumes:** the unchanged `/Users/johnw/src/promptdeploy` checkout, including the authoritative dirty `models.yaml`, and the composed named `#promptdeploy` app.

**Produces:** a protected content-addressed source snapshot and target-root oracle outside Git, committed body-only canonical assets, and a nonsecret evidence document recording source revision, per-path hashes, tree inventories, selector coverage inputs, and reviewed transformations.

- [ ] **Step 1: Register the initial failing asset check.**

  `packages/ai-home-manager-smoke.nix` must initially assert the exact 26 agent names, all 65 canonical command names, 18 repository-owned skill trees excluding the external `translate-en` copy, two static prompt files, and the statusline file. It must reject deployment fields (`only`, `except`, `droid_deploy`) in committed frontmatter and reject `.promptdeploy`, manifests, receipts, `.env`, selector-source JSON, and symlinks escaping `config/ai`.

- [ ] **Step 2: Run RED.**

  ```sh
  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix build -L path:.#checks.aarch64-darwin.ai-home-manager-smoke \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  ```

  Expected: `config/ai/agents`, `commands`, `skills`, `prompts`, and `statusline-command.sh` are missing. The check itself must parse and evaluate.

- [ ] **Step 3: Build an explicit, reviewed source manifest before copying.**

  Do not run `de`, `direnv`, `nix develop`, or `rsync`. Under a host-local state root verified not to be NFS, create a mode-`0700` staging directory. Enumerate every selected path into a reviewed manifest: `flake.nix`, `flake.lock`, `pyproject.toml`, `uv.lock`, `LICENSE.md`, `README.md`, `.gitmodules`, `deploy.yaml`, `settings.yaml`, `models.yaml`, `statusline-command.sh`; every path beneath `src`, `nix`, `bundles`, `agents`, `commands`, `skills`, `prompts`, `mcp`, `hooks`, and `marketplaces`; and only `translate-tool/skill/SKILL.md` plus `translate-tool/glossary.csv` from translate-tool. Before copying, recursively reject `.env*`, `.git`, `.direnv`, `.venv`, `__pycache__`, cache/auth/session/credential/database/key material, newline/control-character paths, special files, hard-linked regular files, and symlinks whose resolved target is outside the reviewed set. Review the complete manifest, not directory globs, before proceeding.

- [ ] **Step 4: Prove a framed source snapshot and finalize it atomically.**

  For every selected directory, regular file, and symlink, record a NUL-framed tuple of relative path, type, numeric mode, symlink target, size, and SHA-256 content/tree digest. Copy one manifest entry at a time with type/mode preservation into staging; regenerate the framed manifest there; require byte equality with the pre-copy manifest and all hashes in **Frozen Source Authorities**. Derive the snapshot ID from that framed manifest. Set the staged source read-only, then atomically rename the complete staging root to a durable digest-keyed path such as `$XDG_STATE_HOME/nix-managed-ai/oracles/<digest>` after verifying owner, mode `0700`, non-symlink parents, and local filesystem. Record the Git revision and dirty/relevant-untracked classification separately; the immutable framed bytes, not revision alone, are authoritative.

- [ ] **Step 5: Render Hera and Clio in an isolated, fail-loud environment.**

  This is the explicit exception to normal promptdeploy environment usage. Capture the absolute `nix` binary, create an empty synthetic HOME/XDG tree, and invoke only:

  ```zsh
  env -i \
    HOME="$SAFE_HOME" USER="$USER" LOGNAME="$LOGNAME" \
    XDG_CONFIG_HOME="$SAFE_HOME/.config" XDG_CACHE_HOME="$SAFE_HOME/.cache" \
    XDG_DATA_HOME="$SAFE_HOME/.local/share" XDG_STATE_HOME="$SAFE_HOME/.local/state" \
    PATH="$SHIM_PATH:/usr/bin:/bin" TMPDIR="$SAFE_TMP" LANG=C.UTF-8 \
    ANTHROPIC_API_KEY=SYNTHETIC_ANTHROPIC CONTEXT7_API_KEY=SYNTHETIC_CONTEXT7 \
    GEMINI_API_KEY=SYNTHETIC_GEMINI LITELLM_API_KEY=SYNTHETIC_LITELLM \
    NVIDIA_API_KEY=SYNTHETIC_NVIDIA OPENAI_API_KEY=SYNTHETIC_OPENAI \
    PERPLEXITY_API_KEY=SYNTHETIC_PERPLEXITY REF_API_KEY=SYNTHETIC_REF \
    PROMPTDEPLOY_HOST=hera \
    "$NIX_BIN" run --no-write-lock-file "path:$SNAPSHOT#promptdeploy" -- \
      deploy --target-root "$HERA_ORACLE"
  ```

  `SHIM_PATH` supplies failing/logging `ssh`, `scp`, `rsync`, `osascript`, `defaults`, `security`, `open`, and process-termination shims; any invocation fails the proof. Run named-app `validate`, two Hera deploys, and two Clio deploys into distinct roots using the same allowlist. Require second-deploy zero actions, literal `${VAR}` references preserved, every synthetic value absent from output/manifests/logs/closure, and no lock write. A process-level trace must prove promptdeploy never opens the original home, live client state, a secret source, or an unapproved project path; enumerate and permit only the synthetic trees plus required OS/Nix runtime paths such as `/nix/store`, the Nix daemon socket/configuration, dynamic-loader inputs, and system devices.

- [ ] **Step 6: Run strict oracle verification and exact structural comparisons.**

  Build the complete exact-selector union from the generated manifests and pass one repeated `--only-item` for every item to the named app's `verify --target-root` command under the same `env -i` harness. Independently parse every JSON/TOML artifact. Compare exact Hera/Clio manifest item maps, relative paths, file types, modes, symlink targets, and framed tree hashes; normalize only manifest timestamps and the approved semantic transformations. Require the four shared Claude trees to match one another and the four shared OpenCode trees to match one another; compare shared Codex as its union. After all app operations, regenerate the read-only source snapshot's framed manifest and require byte equality with both the pre-copy and staged-copy manifests. No count-only or unlisted-difference pass is allowed.

- [ ] **Step 7: Extract canonical assets through canonical discovery and prove the result.**

  Use the Python runtime from the built named-app closure under `env -i` to call `list(SourceDiscovery(Path(snapshot)).discover_all())`; do not reimplement discovery with independent globs. Use the existing frontmatter stripping/serialization APIs and the oracle's rendered prompt bytes. If the built closure cannot expose those APIs under this harness, stop and correct the closure/harness; no independent extractor fallback is permitted. Copy only reviewed body assets, complete local skill trees, prompts, and statusline into `config/ai`; keep the transient selector JSON outside Git.

- [ ] **Step 8: Establish the nonsecret adoption/evidence record.**

  Record exact per-path evidence, selectors, target mappings, GPTel/git-ai exclusions, `anvil-tools`, Ref/native-secret transformations, relocations, Ponytail exclusions, source-safe Droid PAL, git-surgeon frozen-tree parity, and Pi's direct inventory. Establish OpenCode's adopted static document with a one-shot host-local whitelisting process whose input file is never opened, displayed, or logged in the agent/tool context and whose only output is a mode-`0600` JSON object containing exactly `$schema`, `disabled_providers`, and `instructions`. Independently reject a missing key, any fourth key, noncanonical types, or any secret-shaped value; record only the projection hash and reviewed nonsecret values. Never retain or fixture the expanded source. If that projection cannot be produced under these constraints, stop before Task 7.

- [ ] **Step 9: Run GREEN.**

  ```sh
  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix build -L path:.#checks.aarch64-darwin.ai-home-manager-smoke \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  ```

  Expected: exact asset inventories and metadata-stripping checks pass, and a recursive scan finds no `.env`, manifest, selector-source file, receipt, or external working-tree symlink.

- [ ] **Step 10: Review, fess-audit, and commit.**

  Compare names/bodies/tree hashes to the protected oracle, independently review the evidence document for secret leakage, run the fess audit, and commit as `feat: import canonical agent assets`.

---

### Task 5: Implement Profiles, Selectors, Models, and Typed Runtime References

**Files:**

- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai/catalog.nix`
- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai/models.nix`
- Modify: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/packages/ai-home-manager-smoke.nix`

**Consumes:** Task 4 assets/evidence and `pkgs.agent-resources`.

**Produces:** pure catalog/model data with `profiles`, `items`, `selectorCoverage`, `matches`, `select`, and `validate`; no environment or live-state reads.

- [ ] **Step 1: Add failing selector, inventory, and secret fixtures.**

  Assert all 16 stable profile IDs: six Hera, four Clio, two Vulcan, one VPS, and three shared-work profiles. Assert 26 agents; personal/Positron command counts 59/58; shared Codex union 65; two Droid command projections; 38 broad skills plus Claude-only Forge and Positron-only Retest; two prompts; exact MCP/hook/marketplace sets; eight providers and 111 source provider/model pairs. Negative fixtures must reject unknown selector values, duplicate skill names/target paths, unsupported override fields, multiple MCP transports, literal secrets, secret-bearing URL query values, malformed env names, missing renderers, defaults filtered from their profile, and any `anvil-tools` item. Add per-client/server capability fixtures proving how Ref and Context7 environment-backed headers reach Claude, Codex, OpenCode, Droid, and Pi without URL/argv/file/log materialization; missing variables must fail with bounded redacted errors.

- [ ] **Step 2: Run RED.**

  ```sh
  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix build -L path:.#checks.aarch64-darwin.ai-home-manager-smoke \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  ```

  Expected: `catalog.nix` and `models.nix` are missing; negative fixtures must not fail because of malformed test expressions.

- [ ] **Step 3: Implement only the approved selector algebra.**

  Use these exact semantics in `catalog.nix`:

  ```nix
  matchesAny = actual: wanted:
    wanted == null || lib.any (value: builtins.elem value actual) wanted;

  matches = profile: selectors:
    matchesAny [ profile.client ] (selectors.clients or null)
    && matchesAny profile.audiences (selectors.audiences or null)
    && matchesAny [ profile.host ] (selectors.hosts or null)
    && matchesAny [ profile.platform ] (selectors.platforms or null)
    && matchesAny [ profile.id ] (selectors.profiles or null)
    && !(builtins.elem profile.id (selectors.excludeProfiles or [ ]));

  select = profile: items:
    lib.filterAttrs (_: item: matches profile (item.selectors or { })) items;
  ```

  Values within a dimension are ORed, dimensions are ANDed, missing dimensions are unrestricted, and `excludeProfiles` is the only negative field. Add no dependency graph, groups, priority, or fallback rule.

- [ ] **Step 4: Transcribe the catalog and complete selector ledger.**

  Use attr keys as stable names. Agents select all five clients. Commands select Claude/Codex/OpenCode/Pi except `discover-bundles` and `restack`, which also select Droid as skills. External skill sources come only from `resources`; no same-name local copy remains. Encode the exact MCP sets from the frozen report, including DEVONthink only for Hera/Clio Claude personal and OpenCode, `drafts-hera` only for Vulcan Claude, and PAL for all Claude plus Hera Droid. Encode all legacy target/tag/allow/deny mappings and explicit GPTel/git-ai exclusions.

- [ ] **Step 5: Transcribe model data and typed references.**

  `models.nix` returns `{ providers; models; profileDefaults; syncInputs; }`. Preserve all eight providers and 111 source pairs, model-level Hera selectors, Clio-only `llama-cpp-remote`, and the OpenCode default `litellm` / `hera/omlx/Qwen3.6-27B-oQ4e-mtp` only when both survive selection. Droid and Pi emit no default. Ref is `https://api.ref.tools/mcp` with `x-ref-api-key = { env = "REF_API_KEY"; }`; Context7 uses an environment-backed header. Canonical data contains no `${VAR}`, `{env:VAR}`, `$VAR`, query token, or expanded value.

- [ ] **Step 6: Verify the already-selected native and bridge secret paths.**

  Exercise the exact installed client/server versions with synthetic variables and inspect argv, generated bytes, store closure, and logs. Claude, Codex, OpenCode, and Pi use their proven native header/environment fields. Droid alone renders the Task 3 `agent-http-header-bridge` command with the nonsecret URL, header name, and environment-variable name; no resolved value or `${VAR}` expansion is performed by Nix or Droid. Reuse Task 3's missing-variable, rejected-credential, redaction, no-OAuth, and leakage checks instead of adding another bridge.

- [ ] **Step 7: Run GREEN.**

  ```sh
  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix build -L path:.#checks.aarch64-darwin.ai-home-manager-smoke \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  ```

  Expected: all exact inventories and selector-coverage rows match; Vulcan OpenCode validly has no default; evaluation succeeds with the eight secret variables unset.

- [ ] **Step 8: Review, fess-audit, and commit.**

  Independently review selectors, defaults, and secret typing against the oracle ledger; run the fess audit; commit as `feat: add typed agent catalog and models`.

---

### Task 6: Render Claude and Codex Contracts

**Files:**

- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai/renderers/claude.nix`
- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai/renderers/codex.nix`
- Modify: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/packages/ai-home-manager-smoke.nix`

**Consumes:** Task 5's renderer interface, catalog selection, model data, canonical assets, and external resources.

**Produces:** exact relative Home Manager leaves, fixed companion lists, and required environment-variable names for Claude and Codex.

- [ ] **Step 1: Add failing per-profile renderer fixtures.**

  Claude fixtures require selected agents/commands/skills, a profile-derived statusline script, `nix-managed-settings.json`, and `nix-managed-mcp.json`; hooks, marketplaces, plugins, and static settings belong only in the settings supplement. For every Claude profile, compare parsed semantic objects—not counts—for every base settings key, the complete environment map, sandbox/model/theme/effort/statusline values, all three hook event bodies, both marketplace source records, every enabled plugin, and intentional deletions. `preferredNotifChannel = "iterm2_with_bell"` exists only in Hera/Clio personal and is absent from Positron, Vulcan, VPS, and shared work; promptdeploy `_source`, base `mcpServers`, and removed ownership metadata are absent everywhere. Codex fixtures require agent TOML, exact `hooks.json` event bodies and `notify = [ "agent-deck" "codex-notify" ]`, selected user skill directories, 59/65 command projections as appropriate, two prompt projections, and `nix-managed.config.toml`. Assert neither renderer replaces mutable `settings.json`, `.claude.json`, `config.toml`, auth, history, or a parent root.

- [ ] **Step 2: Run RED.**

  ```sh
  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix build -L path:.#checks.aarch64-darwin.ai-home-manager-smoke \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  ```

  Expected: renderer imports and companion artifacts are absent.

- [ ] **Step 3: Implement the Claude renderer.**

  Render JSON with `pkgs.formats.json`; render frontmatter as a JSON object between YAML delimiters followed by the exact canonical body. Translate typed secrets to literal Claude `${VAR}` references without evaluating them. Derive statusline paths from `homeDirectory` and the profile root. Emit companions in this exact order:

  ```nix
  companions = [
    "${profile.root}/nix-managed-settings.json"
    "${profile.root}/nix-managed-mcp.json"
  ];
  ```

  Do not emit strict-MCP behavior or read mutable base files.

- [ ] **Step 4: Implement the Codex renderer.**

  Use `lib.generators.toTOML` for agents and the managed profile fragment. Drop Claude-only `tools`; put the body in `developer_instructions`. Render HTTP credentials only through Codex-native environment-key fields such as `env_http_headers`, never URL expansion. Preserve the exact agent-deck hook/notify document. Use `profile.root = ".config/codex"` on Darwin and `profile.root = ".codex"` on Linux; emit `${profile.root}/nix-managed.config.toml` and `${profile.root}/hooks.json` so the wrapper reaches the Darwin leaves through the preserved `~/.codex -> ~/.config/codex` alias. Keep the base `${profile.root}/config.toml` mutable.

- [ ] **Step 5: Independently parse and inspect every generated document.**

  Extend the check derivation to run `jq -e .` on JSON and Python `tomllib.load` on each TOML file. Compare frontmatter/body boundaries, exact path inventories, and the complete per-profile semantic settings/hook/marketplace/plugin/delete fixtures above; then scan the rendered closure for unique synthetic secret sentinels.

- [ ] **Step 6: Run GREEN.**

  ```sh
  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix build -L path:.#checks.aarch64-darwin.ai-home-manager-smoke \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  ```

  Expected: every Claude/Codex document parses; all profile inventories and companion lists match; only variable names, never values, occur.

- [ ] **Step 7: Review, fess-audit, and commit.**

  Review ownership, native syntax, relocation mappings, and body preservation; run the fess audit; commit as `feat: render Claude and Codex configuration`.

---

### Task 7: Render OpenCode and Droid Contracts

**Files:**

- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai/renderers/opencode.nix`
- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai/renderers/droid.nix`
- Modify: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/packages/ai-home-manager-smoke.nix`

**Consumes:** Task 5 catalog/models, Task 3's pinned `agent-http-header-bridge`, and the source-safe PAL definition from the frozen snapshot.

**Produces:** a complete declarative OpenCode document and exact Droid leaves/settings/MCP companions.

- [ ] **Step 1: Add failing native contract fixtures.**

  Assert OpenCode owns complete `opencode.json`, agents, commands plus two prompts, and skills. Required provider/model counts are Hera 80, Clio 81, Vulcan 10, and shared work 57; only Vulcan omits the default. Assert Droid owns 26 droids, 38 selected skill trees, two command-as-skill trees, two prompt-as-skill trees, complete `mcp.json` with source-safe PAL, and `nix-managed-settings.json` containing 87 custom-model pairs and no default.

- [ ] **Step 2: Run RED.**

  ```sh
  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix build -L path:.#checks.aarch64-darwin.ai-home-manager-smoke \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  ```

  Expected: OpenCode/Droid renderer outputs are missing.

- [ ] **Step 3: Implement complete OpenCode generation.**

  Generate one complete JSON object with `$schema`, the separately reviewed nonsecret `disabled_providers` and `instructions` adoption record, selected provider/model/default data, and selected MCP entries. If that three-key nonsecret adoption record is unavailable, stop without opening an expanded live config. Translate the catalog's sole typed secret form only to native `{env:VAR}` references. Do not add a file-secret form, wrapper, or ownership of data/state/cache/npm trees.

- [ ] **Step 4: Implement exact Droid generation.**

  Generate native frontmatter for droids, complete immutable skill roots, complete `mcp.json`, and the settings overlay. Render Ref and Context7 as stdio entries invoking `agent-http-header-bridge` with only URL, header name, and environment-variable name; the Droid parent environment is inherited and no secret is materialized. Adopt PAL from frozen `mcp/pal.yaml` by replacing its three references with typed environment references while preserving `DISABLED_TOOLS=testgen,secaudit,docgen,tracer` and `DEFAULT_MODEL=auto`; never copy live PAL bytes. Emit companions `.config/factory/nix-managed-settings.json` and `.config/factory/mcp.json`, which resolve through Hera's preserved `~/.factory` alias.

- [ ] **Step 5: Parse and compare native output.**

  Parse all JSON independently, assert exact MCP sets per profile, validate OpenCode static keys from the approved nonsecret record, and prove no renderer reads or merges a live file. Reject any unmanaged Droid MCP entry beyond the adopted PAL mapping during migration, not at render time.

- [ ] **Step 6: Run GREEN.**

  ```sh
  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix build -L path:.#checks.aarch64-darwin.ai-home-manager-smoke \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  ```

  Expected: native JSON parses; exact counts/default omissions/MCP sets pass; closure scans contain references only.

- [ ] **Step 7: Review, fess-audit, and commit.**

  Review complete-file ownership, adopted static keys, PAL's source-safe mapping, and mutable-state exclusions; run the fess audit; commit as `feat: render OpenCode and Droid configuration`.

---

### Task 8: Render the Hera-Only Pi Contract

**Files:**

- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai/renderers/pi.nix`
- Modify: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/packages/ai-home-manager-smoke.nix`

**Consumes:** Tasks 2 and 5, plus the exact Pi inventory in the approved design; promptdeploy is not a Pi oracle.

**Produces:** Pi-native leaves and a structural guard description for mutable adapter settings.

- [ ] **Step 1: Add the failing exact Pi inventory.**

  Hera must have 26 subagents in `.pi/agent/agents`, 59 personal command templates plus two static prompts in `.pi/agent/prompts`, seven providers with 87 Hera-selected model pairs and no default, exactly six global MCP servers (`Ref`, `context-hub`, `context7`, `perplexity`, `sequential-thinking`, `anvil`), and exact links to both packaged extensions. Pi must receive no `.pi` skill copy; it discovers the 38 shared skills and 59 `command-*` plus two `prompt-*` projections from Hera Codex's `.agents/skills`. Clio and every Linux profile receive no Pi leaves.

- [ ] **Step 2: Run RED.**

  ```sh
  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix build -L path:.#checks.aarch64-darwin.ai-home-manager-smoke \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  ```

  Expected: Pi files, models, MCP catalog, and extension links are absent.

- [ ] **Step 3: Implement native Pi leaves only.**

  Generate `models.json` and `$XDG_CONFIG_HOME/mcp/mcp.json` with native runtime references. Use the pinned Pi package's documented provider adapter names; do not infer fields from live state. Link `pi-mcp-adapter` and `pi-subagent` package roots directly. Return:

  ```nix
  mutableMcpGuard = {
    path = ".pi/agent/mcp.json";
    forbiddenKeys = [ "mcpServers" "imports" ];
  };
  ```

  Preserve mutable `settings.json`, adapter `settings`, cache, OAuth state, auth, sessions, model store, and package selections.

- [ ] **Step 4: Assert all deliberate exclusions.**

  Reject Pi PAL, DEVONthink, Drafts, memory-vault, stock-trader, hooks, marketplaces, `anvil-tools`, `llama-cpp-remote`, an emitted default, `.pi` skill copies, wrapper code, and runtime install actions. Assert Hera Pi is enabled only with the Hera Codex profile that owns shared skills/projections.

- [ ] **Step 5: Run GREEN.**

  ```sh
  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix build -L path:.#checks.aarch64-darwin.ai-home-manager-smoke \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  ```

  Expected: exact Pi inventory, native JSON parsing, extension closure, shared-skill dependency, and all exclusions pass.

- [ ] **Step 6: Review, fess-audit, and commit.**

  Review against Pi's direct design contract rather than legacy parity; run the fess audit; commit as `feat: render native Pi configuration`.

---

### Task 9: Integrate Home Manager and Fail Closed Using the Previous Generation

**Files:**

- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai.nix`
- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai/preflight.nix`
- Modify: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/johnw.nix`
- Modify: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/flake.nix` for an explicit test-only personal-Linux home class
- Modify: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/packages/ai-home-manager-smoke.nix`

**Consumes:** all five renderer outputs and Task 3 wrappers.

**Produces:** the fleet profile matrix, one writer per exact leaf, wrapper-first command resolution, and a pre-link guard based solely on `$oldGenPath/home-files`; no ownership database, manifest, receipt, or stamp.

- [ ] **Step 1: Add failing Home Manager/profile/ownership fixtures.**

  Evaluate Hera, Clio, Vulcan, VPS, shared `jwiegley`, and both synthetic Linux outputs. Pass an explicit private test-only `personal-linux` home class to `johnw@aarch64-linux`, yielding personal Claude instead of an empty AI selection; keep Vulcan-only OpenCode host-specific. Assert exact enabled clients, no duplicate path, no parent-root ownership, both Darwin Claude persona roots, wrapper/raw resolution, and preserved `bin/persona`/XDG aliases. In temporary homes test new, retained, and removed paths; absent first adoption; intact prior-generation symlink; new-path collision as file/directory/unrelated symlink; previously managed path missing; replaced/retargeted prior link; a same-payload symlink with a different literal target; tampered and missing removed paths; benign/missing Pi adapter JSON; forbidden `mcpServers`; forbidden `imports`; malformed JSON. Inspect DAG ordering to prove the guard precedes Home Manager's collision/backup/link mutation.

- [ ] **Step 2: Run RED.**

  ```sh
  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix build -L path:.#checks.aarch64-darwin.ai-home-manager-smoke \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  ```

  Expected: the module/import/profile leaves and preflight do not exist, and the current direct Claude wrapper bypass remains visible; the separate Sherlock writer remains outside the new path set.

- [ ] **Step 3: Integrate the explicit fleet profiles.**

  Import `./ai.nix` once from `config/johnw.nix`. Hera selects six profiles, Clio four, Vulcan two, VPS one, and Linux user `jwiegley` the three shared-work profiles regardless of configured hostname. Merge renderer `files` only after asserting unique relative paths. Declare every complete skill directory as one immutable leaf and every generated config as one file; do not use recursive ownership on a mutable parent.

- [ ] **Step 4: Remove only overlapping legacy Nix writers/bypasses.**

  Remove the direct llm-agents `~/.local/bin/claude` link and point claude-mem's mutable `CLAUDE_CODE_PATH` at `claude-real`; the existing package-patching path already selects `ai-nix` wrappers. Preserve Sherlock exactly under its existing separate Nix writer. First run focused login-shell and agent-deck resolution tests; retain existing recursive package discovery and PATH ordering when they pass. Only a focused failing test may justify the smallest correction in `config/johnw.nix`; do not change `config/packages.nix` or `config/agent-deck.nix` for this feature.

- [ ] **Step 5: Implement old/new-union collision and tamper checks without persistent state.**

  `preflight.nix` receives the new selected paths plus the finite AI namespace/predicate needed to enumerate prior AI leaves from `$oldGenPath/home-files`; explicitly subtract separate writers such as Sherlock. Before `checkLinkTargets`, form the union of old and new AI paths and classify each as new, retained, or removed. Treat a genuinely absent prior generation as an empty old set. Otherwise set `old_files=$(readlink -e "$oldGenPath/home-files")`; an intact current link must have the literal `readlink "$HOME/<path>"` value exactly equal to `$old_files/<path>`—resolved-content equality is not sufficient.

  - new (old absent/new present): accept only a wholly absent current path; otherwise fail collision;
  - retained (old present/new present): require the exact literal old-generation symlink target;
  - removed (old present/new absent): require the same exact old-generation link so Home Manager may remove it cleanly;
  - any missing, non-symlink, dangling, retargeted, or same-payload/different-link retained/removed path: fail as tamper.

  Emit only the path and remediation in errors. Do not move, back up, delete, or hash the current content. Home Manager itself handles clean removal of old links after this guard. Do not write `ownership.json`, a managed-path ledger, an adoption receipt, or an XDG ownership stamp.

- [ ] **Step 6: Add the Pi shadow guard to the same pre-link boundary.**

  If `.pi/agent/mcp.json` is absent, accept it. If present, require a JSON object and use structural parsing to reject either top-level `mcpServers` or `imports`; never grep text or alter adapter settings. Malformed JSON fails closed.

- [ ] **Step 7: Run GREEN and non-activating builds.**

  ```sh
  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix build -L path:.#checks.aarch64-darwin.ai-home-manager-smoke \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  nix build -L path:.#darwinConfigurations.hera.system \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  nix build -L 'path:.#homeConfigurations."jwiegley@x86_64-linux".activationPackage' \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  ```

  Expected: profile/path matrices pass; every negative preflight fails for its intended reason; no test touches real user state.

- [ ] **Step 8: Review, fess-audit, and commit.**

  Review the exact DAG order, previous-generation proof, first-adoption rule, parent alias preservation, and absence of persistent ownership machinery; run the fess audit; commit as `feat: realize guarded agent profiles with Home Manager`.

---

### Task 10: Add Hera-Only Digest-Gated DEVONthink/iTerm2 Model Sync

**Files:**

- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai/model-sync.nix`
- Modify: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/config/ai.nix`
- Modify: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/packages/ai-home-manager-smoke.nix`

**Consumes:** deterministic nonsecret `modelData.syncInputs` and the Hera profile classification.

**Produces:** one Hera-only activation entry and `$XDG_STATE_HOME/nix-managed-ai/model-sync-v1.sha256`, advanced only after both nonsecret application updates succeed.

- [ ] **Step 1: Add a fake-tool synchronization harness first.**

  Parameterize the generated script's `pgrep`, `defaults`, DEVONthink Boolean-presence probe, `security`, and file operations for the check derivation. Test first run; unchanged digest; changed digest; Clio/Linux exclusion; either app running; missing DEVONthink compatible key; missing iTerm2 Keychain metadata; first updater failure; second updater failure; successful retry; and atomic stamp replacement. The fake invocation log must prove unchanged digest performs zero app probes/writes, every defaults read names one exact approved nonsecret key, all command output is discarded/redacted, and a synthetic credential sentinel never reaches stdout, stderr, invocation logs, the digest, or the stamp.

- [ ] **Step 2: Add static credential-safety assertions.**

  Reject whole-domain `defaults read`, `defaults export`, any `defaults write` of `OpenAI (Compatible)Key` or `PromptdeployOpenAICompatibleKeyHash`, any `security ... -w`, any read/copy/hash of credential bytes outside the isolated Boolean JXA probe, any secret environment-variable access, and any output derived from a credential. Permit only exact-key, output-discarded reads of the five approved DEVONthink and five approved iTerm2 nonsecret fields, the isolated Boolean DEVONthink nonempty-key presence result, and `security find-generic-password -s 'iTerm2 API Keys' -a 'OpenAI API Key for iTerm2'` with all output discarded.

- [ ] **Step 3: Run RED.**

  ```sh
  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix build -L path:.#checks.aarch64-darwin.ai-home-manager-smoke \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  ```

  Expected: no model-sync activation/digest logic exists; fake cases cannot pass.

- [ ] **Step 4: Implement the digest fast path before every application operation.**

  Hash `builtins.toJSON { schema = 1; provider; model; chatUrl; }`. At activation, read only the prior digest stamp. If equal, exit 0 before `pgrep`, defaults, JXA, or Keychain calls. If different, leave the old stamp untouched until all checks, writes, and verification finish.

- [ ] **Step 5: Implement credential-preserving nonsecret updates.**

  Before any write, require DEVONthink/DEVONthink 3 and iTerm2 not running. The isolated JXA/NSUserDefaults process may inspect `OpenAI (Compatible)Key` only to decide whether it is nonempty; credential bytes must never leave that process, be returned, copied, hashed, logged, persisted, placed in argv/store state, or changed. Query only iTerm2 Keychain item metadata, never password data. Write only these DEVONthink fields: `ChatEngine=2`, `ChatModel-OpenAI (Compatible)=<model>`, `OpenAI (Compatible)URL=<chatUrl>`, `ChatSummaryEngine=2`, and `ChatSummaryModel=<model>`. Write only these iTerm2 fields: `UseRecommendedAIModel=false`, `AiModel=<model>`, `AITermAPI=1`, `AitermURL=<chatUrl>`, and `AIVendor=2`. Reverify one exact nonsecret key at a time with command output suppressed; never read/export a whole preference domain. Recheck credential-presence metadata, then atomically rename the new digest stamp.

- [ ] **Step 6: Wire only Hera after linked managed inputs.**

  Add the activation entry only when `hostname == "hera" && pkgs.stdenv.isDarwin`. Order it after Home Manager links the generated model inputs. Add no Clio branch, launch daemon, remote invocation, forced application quit, API-key environment dependency, or credential hash.

- [ ] **Step 7: Run GREEN.**

  ```sh
  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix build -L path:.#checks.aarch64-darwin.ai-home-manager-smoke \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  ```

  Expected: unchanged digest records zero app operations; changed digest updates once; every failure preserves the old stamp and credential state; Clio/Linux have no activation entry.

- [ ] **Step 8: Review, fess-audit, and commit.**

  Obtain an independent secret-safety/idempotence review, run the fess audit, and commit as `feat: gate Hera model synchronization by digest`.

---

### Task 11: Run Full Gates, Publish `ai-nix`, and Pin Its Reviewed Revision

**Files:**

- Modify: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/packages/ai-home-manager-smoke.nix`
- Modify: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/flake.lock`
- Modify: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/flake.nix` for final check registration and an immutable ai-nix revision URL

**Consumes:** reviewed Task 1–3 `ai-nix` commits and Task 4–10 Nix commits.

**Produces:** green checks on supported systems, a remotely reachable reviewed `ai-nix` commit, and an exact nix-config lock pin with no local override.

- [ ] **Step 1: Add the final cross-profile matrix before changing the lock.**

  Gate exact destinations/resources; one renderer per profile; independent JSON/TOML parsing; deterministic equivalent renders; no duplicate paths/skills/parents; expected missing default; typed secret references and closure scans; wrapper/private-raw availability; previous-generation/preflight negatives; Pi shadow negatives; sync digest behavior; and Darwin, aarch64-linux, x86_64-linux evaluation. Register the same smoke derivation on every applicable system.

- [ ] **Step 2: Run the entire matrix with the local dependency override.**

  ```sh
  cd /Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  nix flake check -L path:.

  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix flake check -L path:. \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  nix build -L path:.#darwinConfigurations.hera.system \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  nix build -L path:.#darwinConfigurations.clio.system \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  nix build -L 'path:.#homeConfigurations."johnw@aarch64-linux".activationPackage' \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  nix build -L 'path:.#homeConfigurations."jwiegley@x86_64-linux".activationPackage' \
    --override-input ai-nix path:/Users/johnw/src/ai-nix.worktrees/nix-managed-agent-resources
  ```

  Expected: all commands exit 0 before any publication or activation.

- [ ] **Step 3: Review and publish the exact `ai-nix` dependency commit.**

  Run final code review and fess audit in `ai-nix`; verify a clean task branch; push `feat/nix-managed-agent-resources`; and require `git ls-remote origin refs/heads/feat/nix-managed-agent-resources` to equal local `HEAD`. No force push is permitted.

- [ ] **Step 4: Pin an immutable `ai-nix` revision URL and prove the complete lock delta.**

  Read the actual reviewed 40-hex ai-nix `HEAD` and set `ai-nix.url` to the `git+https://github.com/jwiegley/ai-nix` URL with that literal value in its `rev` query, then regenerate only that input closure; never resolve the default branch. Use `nix flake metadata --json path:.` and the lock JSON to assert repository URL, exact revision, NAR hash, and follows relationships. Diff pre/post lock graphs and require the only changed nodes to be ai-nix and its expected new/changed transitive resource inputs (Superpowers, Ponytail, translate-tool, `mcp-remote`, the two Pi extensions, and any mechanically required follows node); reject every unrelated node or revision change.

- [ ] **Step 5: Run every gate without an override.**

  ```sh
  cd /Users/johnw/src/nix.worktrees/nix-managed-agent-config
  nix flake check -L path:.
  nix build -L path:.#darwinConfigurations.hera.system
  nix build -L path:.#darwinConfigurations.clio.system
  nix build -L 'path:.#homeConfigurations."johnw@aarch64-linux".activationPackage'
  nix build -L 'path:.#homeConfigurations."jwiegley@x86_64-linux".activationPackage'
  ```

  Expected: all outputs build from the published pin and match local-override inventories/digests.

- [ ] **Step 6: Review, fess-audit, commit, and publish the Nix gate.**

  Review lock scope and full evidence, run the fess audit, commit as `test: gate Nix-managed agent fleet`, push `feat/nix-managed-agent-config`, and verify remote readback. Do not merge either feature branch as part of this step.

---

### Task 12: Write and Review the One-Time Migration Runbook

**Files:**

- Create: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/docs/runbooks/nix-managed-agent-configuration.md`

**Consumes:** exact published revisions, frozen oracle/selector evidence, exact managed paths, previous-generation guard, and live read-only inspection of each consumer flake.

**Produces:** an operator-complete checked Markdown checklist for Phase A, Phase B, rollout, rollback, and retirement. It is documentation, not a script or deployer.

- [ ] **Step 1: Write the unchecked acceptance checklist first.**

  The runbook begins with unchecked boxes for frozen dirty/tracked/untracked source hashes; legacy manifest hashes; quiescence; Task 4's named `#promptdeploy` `env -i` oracle; separate secret-free desired-state and redacted live-drift oracles; selector ledger; collision classes; protected backup/journal; terminal/persona/agent-deck/applicable-GUI synthetic-secret checks; Hera -> Clio -> Vulcan -> VPS -> shared-work order; old/new closure roots on all four shared-home hosts; single Andoria-08 activation; second-switch and unchanged-sync no-ops; forced-failure restore; rollback verification; observation closure; and retirement. Each box names its exact command and evidence artifact. Include no force mode, persistent manifest, deployment SSH/rsync, or promptdeploy implementation coupling.

- [ ] **Step 2: Inspect real consumer flakes read-only and replace every generic command.**

  On each host, inspect its current repository, flake input names, lock path, output, build serialization convention, switch/rollback command, and exact active instruction/job/alias files eligible for retirement without activating: Hera/Clio Nix Darwin outputs; Vulcan's `/etc/nixos#vulcan`; VPS's actual NixOS output; and the shared Home Manager consumer. Record every repository/file plus exact lock-update, review, build, commit, push/readback, activation, rollback, local GC-root, and retirement command. If a path/output/file cannot be proven locally, leave its checkbox blocked and stop rather than substituting a synthetic output or using deployment SSH.

- [ ] **Step 3: Write Phase A and Phase B as disposable operations.**

  Phase A reuses Task 4's immutable snapshot/oracles, collects protected legacy manifest hashes, compares unchanged assets by framed hash and relocated configs semantically, validates Pi directly, and scans synthetic references/leaks. Phase B classifies each destination. Before mutation, atomically create the backup root on a verified host-local filesystem, reject symlinked parents, verify current-user ownership and mode `0700`, finish every backup, and fsync/complete the journal. The complete pre-mutation journal contains only paths, types, modes, hashes, backup references, and expected pre/post states; only then may exact legacy leaves/owned keys be removed. Mixed files use in-memory redacted structure/key ownership. Any incomplete backup/journal, drift, or unmanaged entry stops; no force path exists.

- [ ] **Step 4: Write complete rollback and shared-home procedures.**

  Rollback reactivates the recorded old generation and restores every whole leaf, manifest, and mixed file only if its current state still equals the journaled post-cutover state; then verifies type/mode/hash. For shared work, locally realize and root identical old/new closures under each host's local `/nix/var/nix/gcroots`, verify recursive closure presence and identical activation paths on all four machines, activate only on Andoria-08, and smoke-test from the other three without activating.

- [ ] **Step 5: Prove commands non-mutatingly and review every checklist row.**

  Run the recorded evaluation/build commands, Task 4 oracle verification, migration classification against synthetic temporary homes, backup/journal dry runs, and rollback dry runs without activating or changing live client state. Two independent reviewers map every approved-design requirement to a checklist row and verify every command against its live repository. Keep rollout-only boxes unchecked for Task 13; do not add a permanent checker or flake registration.

- [ ] **Step 6: Review, fess-audit, commit, and publish the runbook.**

  Obtain independent operational and security review, run the fess audit, commit as `docs: add managed agent migration runbook`, push the feature branch, and verify remote readback before touching host state.

---

### Task 13: Execute the Explicitly Authorized Rollout, Rollback Proof, Idempotence Checks, and Retirement

**Files:**

- Modify only when recording nonsecret evidence: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/docs/migrations/nix-managed-agent-oracle.md`
- Modify only when execution reveals an exact command correction: `/Users/johnw/src/nix.worktrees/nix-managed-agent-config/docs/runbooks/nix-managed-agent-configuration.md`
- Update each consumer's lock file only to the reviewed published `ai-nix` and Nix revisions.

**Consumes:** the reviewed Task 12 runbook plus a durable handoff entry explicitly authorizing host mutation and retirement. Neither this plan nor the agent may infer that authority. Every operation must run from the affected host's local shell; deployment SSH/rsync is forbidden. A missing authority record, collision, dirty consumer overlap, missing closure, running application, inaccessible local session, or unproven output is a fail-closed stop boundary.

**Produces:** locally realized and activated fleet state, proven rollback/restoration, proven second-run idempotence, closed rollback evidence, and promptdeploy removed from the active five-client workflow.

- [ ] **Step 1: Reverify immutable prerequisites immediately before mutation.**

  Confirm the handoff's explicit Task 13 authority, remote branch heads, promptdeploy source hashes, protected local snapshot/oracle/evidence ownership/mode, and writer quiescence. Rerun the Task 4 named-app target-root verification through its exact `env -i`, synthetic-HOME, failing-shim harness—never `de` or `direnv`. Stop on any drift or missing local execution surface.

- [ ] **Step 2: Discover, update, review, publish, and read back every consumer before activation.**

  On each host's local shell, record the consumer repository path, flake file, lock file, input node names, and exact output. Update only the immutable reviewed ai-nix/Nix revisions; inspect the complete diff and transitive lock delta; build without activation; commit the lock change atomically in that consumer; push normally; and verify remote branch/readback equals local `HEAD`. Do this for Hera, Clio, Vulcan, VPS, and the actual shared-home consumer before migrating that class. Do not use deployment SSH/rsync or substitute synthetic Linux outputs.

- [ ] **Step 3: Prove runtime environment success and failure before cutover.**

  From terminal, persona, agent-deck, and each applicable GUI launch surface, use synthetic variables to prove required values arrive unchanged and do not appear in argv/files/store/logs. Unset each required variable in turn and require a bounded, redacted failure naming only the missing variable/server. Restart agent-deck before its tests whenever its inherited environment changes, and record that restart/readback; a stale long-lived environment is not accepted.

- [ ] **Step 4: Migrate and canary Hera, including real rollback proof.**

  Collect protected legacy manifest evidence, run collision/redacted-drift preflight, back up exact affected leaves/mixed files, remove only proven promptdeploy-owned leaves/keys, and switch Hera. Exercise Claude personal/Positron, Codex, OpenCode, Droid, and Pi from terminal/persona/agent-deck/applicable GUI; verify exact inventories, MCP visibility, wrapper complete/pass-through/bypass behavior, and synthetic secret delivery without argv/file/store/log leakage. With DEVONthink and iTerm2 closed and credential-presence metadata valid, prove first/changed model sync once and an unchanged activation makes zero app calls. Force the documented activation failure, restore the old generation plus all journaled state, verify hashes/modes/types, then reapply the candidate and repeat the unchanged switch.

- [ ] **Step 5: Roll out Clio, Vulcan, and VPS in order.**

  For each host, repeat protected preflight/backup/migration/local switch/client smoke/second unchanged switch. Clio must have dual Claude, Codex, OpenCode, and no Droid/Pi/model sync. Vulcan must have personal Claude/OpenCode and no managed OpenCode default. VPS must have personal Claude only. Any unexpected client, default, MCP, collision, or mutation rolls that host back before continuing.

- [ ] **Step 6: Prepare all four shared-home local stores before the single write.**

  On Andoria-08, Andoria-t2, Delphi-3bd4, and gpu-server, realize the same committed consumer revision/lock; root both recorded old and new closures under host-local `/nix/var/nix/gcroots` paths; verify every recursive store reference exists locally; and require identical new activation paths and managed inventories. Quiesce all possible shared-home writers. If any host is unavailable or differs, do not activate.

- [ ] **Step 7: Activate shared work once and verify from all four hosts.**

  Run migration preflight/backup and the only shared Home Manager activation on Andoria-08. From Andoria-t2, Delphi-3bd4, and gpu-server, run parse/link/client/MCP/inventory smoke checks without another activation. Prove shared-work Claude Positron, Codex 65-command union, and OpenCode Positron; prove no personal-only/Hera-only state. Keep both local closure roots everywhere through rollback closure.

- [ ] **Step 8: Close the evidence-based observation and retire promptdeploy.**

  Require every home to pass one normal client-launch cycle, the unchanged second switch, exact managed bytes/symlink targets/store references, and rollback/restore verification. Record explicit rollback-window closure with nonsecret evidence. Remove legacy promptdeploy manifests/marker blocks/bundle receipts only from the five migrated clients after protected backups are accepted; preserve GPTel/git-ai artifacts/manifests and mutable client state. Remove promptdeploy from active instructions/jobs/aliases for these clients, but leave the repository and frozen oracle unchanged as an archive. Remove old GC roots/backups only after the recorded closure decision; never automatically delete later user changes.

- [ ] **Step 9: Run final verification, review, fess-audit, and commit the evidence.**

  Rerun both repositories' full flake checks, all local real-consumer builds, review every Task 12 checklist box against its evidence, and run live smoke checks. Obtain final independent code/operations/security review and the final fess audit. Commit only nonsecret evidence/corrections as `docs: record managed agent rollout completion`, push normally, and verify remote readback. The task is complete only when all five fleet classes are active, idempotent, locally rollback-safe, and promptdeploy has no active ownership role.

---

## Mandatory Serialization and Completion Rules

1. Tasks 1–3 are serial `ai-nix` commits. Tasks 4–10 are serial Nix commits using the local path override. Task 11 publishes and pins the reviewed interface. Task 12 uses only published revisions. Task 13 additionally requires explicit authority recorded in the handoff and local execution on each affected host.
2. A task cannot begin until its predecessor's focused tests, independent review, fess audit, and commit are complete.
3. Every subagent is read-only unless assigned an isolated file-generation namespace; the coordinator alone owns Git, lock updates, publication, and host mutations.
4. Any secret exposure, live-config ambiguity, unmanaged collision, dirty consumer overlap, missing host-local closure, application-running refusal, or rollback mismatch stops execution. It is not bypassed with force.
5. Final completion requires green `nix flake check -L path:.` in both repositories, green real consumer builds, successful live launch inventories, successful rollback/restore, unchanged second switches, unchanged model-sync no-op, four-host shared closure roots, and explicit promptdeploy retirement evidence.

## Design Coverage Audit

| Approved design area | Implemented by |
|---|---|
| Repository boundary and external resources | Tasks 1–2 |
| Wrapper zero/complete/partial/conflict/bypass | Task 3 |
| Dirty-source freeze, oracle, assets, selector ledger | Task 4 |
| Profiles, selectors, models, defaults, secrets | Task 5 |
| Claude and Codex native contracts | Task 6 |
| OpenCode and Droid native contracts/PAL adoption | Task 7 |
| Pi direct inventory and native discovery | Task 8 |
| Exact leaves, persona, wrappers, collision/tamper/Pi shadow safety | Task 9 |
| Hera-only credential-preserving digest sync | Task 10 |
| Cross-platform gates and published `ai-nix` pin | Task 11 |
| One-time migration, backup, shared-home, rollback procedure | Task 12 |
| Actual fleet rollout, rollback/idempotence proof, retirement | Task 13 |

No task retains promptdeploy code, creates persistent ownership machinery, reads `.env`, or introduces a general deployment abstraction.
