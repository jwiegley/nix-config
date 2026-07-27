# Architecture Remediation Journal

Append-only durable learnings for the architecture-remediation Wiggum loop. Decisions and current task state belong in the plan/handoff; this file records evidence that should survive compaction.

## 2026-07-26 — Audit synthesis and loop entry

- The audit found 22 actionable architecture/maintainability findings, with update authority, Darwin leakage, and root navigability as P0.
- The built-in codebase-audit workflow was unavailable. A custom planning workflow exposed a missing documented `cwd` global, then exhausted its token budget after five lanes. The user waived PAL and directed implementation to continue; the coordinator froze a direct evidence-based plan instead of retrying orchestration.
- Anvil is a dedicated Emacs backend (`ANVIL_EMACS_STATE_DIR` is set), so its buffer checks do not prove the state of a separate interactive Emacs; no modified repository buffers were visible in the dedicated backend.
- Current repository baseline is clean `main` at `a36d3f51d92158e4e055e3baca85044f575e25a6`.
- Significant deletion candidates remain conditional until maintained external consumers are searched. Git history is sufficient archive only after live decisions and authorizations are migrated.

## 2026-07-26 — WU0 baseline

- `python3 -m unittest -v bin/update-overlay-test.py`: 4/4 passed.
- `nix flake check ./config/ai --all-systems --no-build`: all portable outputs evaluated; only `lib` remains an intentionally unchecked output warning.
- Core Darwin contracts `agent-resources`, `agent-wrappers`, `ai-home-manager-contract`, and `pi-gallery` built successfully.
- `./build system` completed successfully for Hera.
- Non-hidden `doc/observations/*.md`: zero.
- Existing auxiliary worktrees were inventoried and left untouched; one prunable stale worktree record exists and is not part of WU1.

## 2026-07-26 — WU0 fess and partner cleanup

- Fess audit target: signed commit `4f25975fe32262bfc85c27f6bba5083e148dc425`.
- Auditor verdict: FAIL with seven documentation/process findings. Disposition: all accepted and fixed in the cleanup commit—WU0 evidence completed, authorization made explicit, WU6/WU7 contract prerequisites moved ahead of implementation movement, audit approval recorded, finding IDs corrected, mandatory CI contracts enumerated, and durable fess verdict fields required.
- Fleet baseline: Hera repo `4f25975f`, Darwin system `sbcyp...`, HM 41; Clio repo `a36d3f5`, Darwin system `wpgfc...`, HM 220; Andoria-08/T2, Delphi, and GPU repo `ae0156cd`, HM 192; Vulcan repo `a999d89b`, NixOS system `118cx...`.
- Partner observation `2026-07-27T00:28:18.461Z` restored a previously lost TMUX socket-parent finding. Resolution: disable Home Manager `programs.tmux.secureSocket`, remove global `TMUX_TMPDIR`, default the Agent Deck package and remote helper to `/tmp`, retain `AGENTDECK_TMUX_TMPDIR` as calibration override, and remove all `/run/user/$uid`/linger dependence.
- Verification: focused `ai-home-manager-contract` passed; `darwinConfigurations.hera.pkgs.agent-deck` built; independent partner-cleanup reviewer returned PASS.
- The first package build command used a nonexistent root `packages.aarch64-darwin.agent-deck` output after the contract had passed. This was a verification-command error, not a code failure; the correct Darwin package attribute passed on the next attempt.

## 2026-07-26 — WU1a operating interface fess audit

- Fess audit target: signed commit `2ddca506` (`refactor: establish repository operating interface`).
- Auditor verdict: FAIL with four findings. Disposition: all accepted—README now marks `update-agents` incomplete and mutating; CLAUDE requires authorization for all activation; `make build` removes only the exact `result` link; `make format` is listed as mutating.
- Original verification before audit: shfmt/shellcheck, `./build` help/error cases, non-mutating default `make`, root document/link checks, `make test`, and Darwin system build all passed.
- Fess-fix verification repeats command-interface checks and diff hygiene; per Wiggum the fess-fix commit is not recursively audited.

## 2026-07-27 — WU1a partner follow-up

- Partner observation `2026-07-27T01:20:44.318Z` found that root documentation consolidation dropped the critical prohibition against `sudo nix flake update/lock` and its NAR-mismatch recovery path.
- Resolution: root CLAUDE now explains root/user fetcher-cache divergence, forbids sudo lock/update, and names regular-user `make verify-inputs` then `make lock-local` recovery. Activation remains separately authorization-gated.
- Independent partner-cleanup reviewer verdict: PASS.

## 2026-07-27 — WU1b deletion fess audit

- Fess audit target: signed commit `205f4827` (`refactor: remove superseded repository surfaces`).
- Auditor verdict: FAIL. Four findings accepted.
- Root `LICENSE.txt` now carries the prior 2014–2026 New Artisans BSD notice; the conflicting secondary file remains deleted.
- `doc/SECURITY-REVIEW.md` and `doc/VULCAN-SSH-TIMEOUT-ANALYSIS.md` were restored with explicit historical/debt status. Their unresolved dispositions are assigned to WU1/WU5/WU9 before later retirement.
- Local Beads merge driver, role, and exclude entry were removed. Two Beads refs are intentionally preserved pending WU9 history-retention evidence.
- Verified deletions that remain: superseded Nix-managed/Pi capsules, empty tracked Beads JSONL files, orphan Emacs site-start, duplicated command body, and stale CI literals.
- Per Wiggum, this fess-fix commit is verified but not recursively audited.

## 2026-07-27 — WU2a update inventory and transaction boundary

- Added `packages/update-manifest.nix` with 23 non-overlay targets: immutable Pi releases, agent resources, Bigpowers/Ponytail copies, Anvil sources, and fixed-revision flake inputs.
- `bin/update-overlay --inventory --json` now reports 116 unique managed targets and 83 non-package overlay attributes without network access.
- `SourceTransaction` snapshots every source before mutation and rolls back the whole invocation on dependent-hash failure or abnormal process exit. An end-to-end fake-hash test proves version/source changes are byte-identically restored.
- `update-agents` no longer names retired inputs. Pull, signed commit, switch, push, and Homebrew are explicit; switch/push require commit; staging is limited to updater-owned paths.
- `make update` now updates both locks and evaluates the portable boundary.
- Verification: shellcheck/shfmt, Ruff, 7 updater tests, inventory contract, portable all-system evaluation, and four core AI contracts passed.

## 2026-07-27 — WU2a fess corrections

- Fess audit target: signed commit `233279de` (`refactor(updates): establish atomic package inventory`).
- Auditor verdict: FAIL with seven findings; all accepted.
- `update-agents` now snapshots and restores both locks and every changed tracked source on failed update/check, blocks switch/push unless a new signed commit exists, and is the sole owner used by `make update --all-inputs`.
- Manifest expanded from 23 to 32 explicit targets, including eight pure shared inputs, six gallery lock files, adapter ledgers/tests, Nelisp Cargo lock, and the independent `ws` pin.
- Inventory now distinguishes `inventoried` from `managed/executable`: 125 total targets, 101 executable (93 overlays + 8 pure inputs), 24 pending WU4 executors.
- Duplicate overlay validation now rejects multiple updateable source definitions while allowing intentional later overrides such as `z3`.
- Verification: shellcheck/shfmt, Ruff, Nix formatting/evaluation, 9 updater tests including full lock+overlay rollback, inventory counts/status, and four core contracts passed.
- Per Wiggum, the fess-fix commit is not recursively audited.

## 2026-07-27 — WU2a partner cleanup

- Partner observation `.356Z` found that `bin/upgrade` still passed no-op legacy updater flags and could leave a dirty tree while continuing. Resolution: upgrade is fail-fast and invokes exactly `./bin/update-agents --commit`; tests reject appended switch/push/brew flags.
- Partner observation `.362Z` found stale README claims against `233279de`; the in-progress fess correction already replaced them with accurate safe-default/inventory status.
- Independent reviewer accepted the README fix and requested exact invocation testing for upgrade; that test now passes.
- Full WU2a correction gate: shellcheck/shfmt, Ruff, Nix formatting/evaluation, 9 updater tests, inventory 125/101/24 contract, and four core checks PASS.

## 2026-07-27 — WU3 platform and overlay isolation

- Replaced filename discovery and AI-first composition with one explicit `config/overlays.nix` phase manifest; Python tests require every numbered root/AI overlay exactly once.
- Wrapped `00-last-known-good.nix` and `15-darwin-fixes.nix` at the Darwin boundary. Moved cross-platform Eask to `10-eask-cli.nix`.
- Removed the `pkgs.inputs` publication/restoration bus. Every input-consuming overlay is now a factory receiving explicit sources; portable checks/renderers use their actual flake inputs directly.
- Removed now-orphaned `config/paths.nix` pass-through registry.
- Added Linux isolation checks for all available Darwin-pinned/fixed top-level and Python packages, specific ImageIO/Gradio test policy, and absence of `pkgs.inputs`; x86_64-linux and aarch64-linux builds pass.
- Explicit Ledger input evaluation exposed an obsolete Python-install relocation against Ledger's new split output. Removed the stale hook; the native Darwin Home Manager contract rebuild passes.
- Verification PASS: Nix formatting, Statix, Deadnix, Ruff, 10 updater/structure tests, portable all-system evaluation, both Linux isolation builds, four core AI contracts, and native Hera `./build system`.
- Known gate debt: root `nix flake check --all-systems --no-build` still hits the pre-existing contextless `builtins.path` source failure in root Home Manager/preflight checks; focused builds succeed. This maps to WU6/WU8 portable/check-source ownership and is not treated as WU3 evidence.

## 2026-07-27 — WU3 pre-commit partner cleanup

- Late observation `.296Z` against `5ce2e91f` correctly found that global `set -euo pipefail` broke `bin/upgrade`'s intentionally best-effort legacy workspace sweep.
- Strict mode remains active for the host update/build/sign phase. `set +e` and `set +u` now mark the workspace boundary pending WU5's result-aggregating runner.
- Independent review found the runtime boundary correct but requested stronger regression assertions. Tests now prove strict mode precedes the host case/updater and both relaxations occur after host completion but before the first project block.
- Current inventory is 126 total / 102 executable / 24 pending after the explicit Eask overlay became independently discoverable.

## 2026-07-27 — WU3 fess audit

- Audited signed commit: `a3cc3843bf15fdf6f327dd4297efa4c6f351b14e`.
- Independent verdict: FAIL with two findings; both accepted.
- Medium: `flake.nix` retained one unused `inputs` publisher in the Darwin-only `pkgsFor` import, while the static regression scan omitted root `flake.nix`. Removed the publisher and added root flake coverage plus its exact forbidden form.
- Low: handoff still described WU3 as uncommitted. Corrected resume state to name the signed implementation and pending fess-fix commit.
- Auditor independently confirmed P0-2 and P1-6 resolved, both Linux isolation checks, portable evaluation, formatting/static checks, all 10 tests, and Ledger runtime/Python output behavior.
- Per Wiggum, this fess-fix commit is not recursively audited.

## 2026-07-27 — WU3 partner observations

- Observation `.497Z` reported that top-level Darwin gating re-enabled six Linux test suites. Disposition: intended, not a defect. This is the approved P0-2 resolution and the Linux parity check's purpose. Native aarch64-linux builds of configured z3, libvirt, kvazaar, fsspec, Gradio, and Mirakuru all completed successfully; an independent reviewer accepted the disposition.
- Observation `.504Z` requested optional PAL/mcp-remote inputs. Accepted, but first implementation gated unrelated MCP packages with mcp-remote. Independent review caught the over-broad gate.
- Final implementation gates only `pal-mcp-server` and `agent-http-header-bridge` on their respective sources. Composition-path tests remove each input independently and prove every unrelated MCP package remains present.
- Portable all-system evaluation, both Linux isolation checks, Darwin agent-resources/Home Manager contracts, and 10 structural/updater tests pass.
