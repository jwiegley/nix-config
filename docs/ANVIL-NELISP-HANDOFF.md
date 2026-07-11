# Anvil Fleet Backend Handoff

Updated: 2026-07-11

## Current position

The implementation and verification gates are complete in both repositories. Nix has passed focused evaluation, exact generic and actual-consumer graphs, full four-system evaluation, formatting/linting, and the strengthened final-source runtime gate on Darwin, Vulcan ARM64, and Andoria-08 AMD64. promptdeploy has passed exact target/render tests, validation, Ruff, strict mypy, all 1,512 tests at 100% coverage, package build, and all-system flake evaluation. Independent review and atomic commits remain.

The Linux contract is `johnw.anvil.useHeadlessEmacs`: false selects the proven NeLisp v0.5.1/anvil.el v1.1.1 pair; true selects current anvil.el 1.3.0 plus anvil-ide under `emacs30-nox`. The independent Darwin contract is `johnw.anvil.useDedicatedDarwinEmacs`: false uses the current interactive Emacs; true reuses the pinned MacPort Emacs in a separate minimal daemon. The PATH launcher remains `anvil-mcp`. Dedicated modes load the full configured optional set, retain 76 direct typed tools, and mirror them into the 12-tool main registry, yielding one 88-tool main surface without promptdeploy knowing either Boolean.

## Evidence gathered

- Nix worktree: `/Users/johnw/src/nix`, branch `main`, initial HEAD `c988ea6dc269312af9d4545fc5d0b76f56cd801e`, initially clean.
- promptdeploy worktree: `/Users/johnw/src/promptdeploy`, branch `main`, initial HEAD `a037d18f4e40baaead3dbda4a41e956c097faadb`.
- Current macOS Anvil is fetched and compiled in `overlays/10-emacs.nix`, included by `config/emacs.nix`, loaded in the running Emacs, and served through the live socket.
- The packaged interactive Darwin launcher reached that daemon: `anvil` returned protocol 2025-03-26 and 12 tools; `emacs-eval` returned 65 tools. The user reports that agent traffic can intermittently lock this development Emacs, motivating the dedicated Darwin process.
- The dedicated Darwin check starts its MCP client before one daemon is ready, then proves bounded launcher waiting, two concurrent MacPort Emacs daemons, exactly 88 unified and 76 typed tools, real eval/file/Org/semantic calls, distinct socket/schema/state paths, isolated worker process environments, and clean shutdown.
- The strengthened dedicated check passes natively on Vulcan ARM64 and Andoria-08 AMD64 from immutable source `/nix/store/1454yq2m44d89n9v3hqmqkyb9md7r5pb-source`, using the root-mapped nixpkgs revision `f205b5574fd0cb7da5b702a2da51507b7f4fdd1b`. Neither run created a temporary source tree or changed host configuration.
- Focused Home Manager evaluation proves both Boolean defaults and true branches: interactive/no-agent versus dedicated/user-domain launchd on Darwin, and NeLisp/no-service versus dedicated/systemd on Linux.
- NeLisp v0.5.1 contains the Rust `anvil-runtime` crate and checked-in Cargo lock. Its released x86_64 artifact contains Anvil modules byte-identical to anvil.el v1.1.1.
- Upstream's released server silently exposes only `hello` when bootstrap fails. The package patch changes that path to fail closed, and the smoke test detects the distinction.
- The pinned source needed one genuine ARM portability fix: use `std::ffi::c_char` rather than hard-coded `i8` at the FFI C-string boundary.
- Vulcan native ARM64: 63 Rust tests passed; the package smoke reported exactly 42 tools and successful file/shell calls; the runtime closure is Emacs-free.
- Andoria-08 native AMD64: the same 63 tests and 42-tool behavior smoke passed; the runtime closure is Emacs-free.
- Actual consumer override evaluations contain exactly one `anvil-mcp` on Vulcan (`/etc/nixos/flake.nix`), VPS (`/etc/nixos/flake.nix`), and Andoria-08 (`~/.config/home-manager/flake.nix`). No switch or activation occurred.
- Vulcan is ARM64 NixOS with an active lingering user systemd manager and local `/run/user/1000`.
- Andoria-08, Andoria-t2, Delphi-3bd4, and gpu-server are AMD64 Ubuntu hosts. They share the same NFS home/profile and UID 158771033, but each has a host-local `/run/user/158771033`, active user systemd, and lingering enabled.
- No Linux host currently runs an Emacs daemon. Andoria-08's distro Emacs 27.1 is below anvil.el 1.3.0's Emacs 28.2 minimum; the other audited hosts have no Emacs. A Nix `emacs30-nox` closure is therefore required.
- The shared Andoria flake hard-codes `hostname = "andoria-08"`; the daemon and launcher must derive the real hostname at runtime.
- promptdeploy already supports stdio MCP on Claude, Codex, Droid, and OpenCode, including remote Claude through its SSH-stdin merge. No renderer change is presently indicated.
- The PAL consensus service is unavailable in this session. Independent upstream, Nix, promptdeploy, and five-host audits supplied the decision check instead.

## Current Nix changes

- `packages/anvil-mcp/default.nix`: platform-dispatched NeLisp, interactive-Darwin, and dedicated-Emacs launchers; pinned Anvil/anvil-ide/PyMuPDF runtime; deterministic sockets; fail-fast bootstrap; isolated root and worker state; and worker-pool shutdown.
- `packages/anvil-mcp/no-placeholder-fallback.patch` and `portable-c-char.patch`: fail-closed NeLisp bootstrap and ARM-compatible FFI.
- `packages/anvil-mcp/smoke.nix` and `smoke.py`: exact 42-tool NeLisp behavior gate.
- `packages/anvil-mcp/headless-smoke.nix` and `headless-smoke.py`: concurrent two-daemon isolation, exact 88/76 manifests, and real eval/file calls.
- `config/anvil.nix`: both Boolean options, selected package installation, deferred systemd service, and user-domain launchd agent.
- `config/johnw.nix` and `flake.nix`: module import plus focused packages and platform checks.
- This plan and handoff document.

## User-owned state

The promptdeploy worktree was already dirty before implementation. `commands/wiggum.md` remains modified and untouched. The live `skills/anvil/SKILL.md` buffer contained the user's unsaved checkpoint section; it was edited in place through Anvil, the checkpoint section was retained, and the buffer was saved. Emacs then retired its `#SKILL.md#` autosave artifact normally. Stage and commit only explicit task paths.

## Verification ledger

| Gate | State | Evidence or next action |
|---|---|---|
| Upstream compatibility tuple | proved | NeLisp v0.5.1 + anvil.el v1.1.1 source/release comparison |
| NeLisp ARM64 native runtime | passed | Vulcan: 63 tests, exact 42-tool behavior smoke |
| NeLisp AMD64 native runtime | passed | Andoria-08: 63 tests, exact 42-tool behavior smoke |
| Emacs-free NeLisp closures | passed | native recursive closure scans on both architectures |
| ARM FFI portability | passed | `std::ffi::c_char` patch compiled and tested on Vulcan |
| Darwin live bridge | passed | 12 main tools and 65 typed tools through packaged launcher |
| Dedicated package/init/services | passed focused runtime | Darwin, Vulcan ARM64, and Andoria-08 AMD64: exact 88 unified/76 typed, real calls, two-daemon isolation |
| Boolean Home Manager options | passed focused evaluation | both defaults and both true service branches evaluate with the intended backend |
| Shared-home socket isolation | passed runtime smoke | deterministic platform roots, runtime hostname, distinct host sockets and schema/state trees |
| Generic Home Manager outputs | passed | each architecture evaluates to exactly one `anvil-mcp` package with backend `nelisp` |
| Vulcan consumer override | passed | actual NixOS/Home Manager graph |
| VPS consumer override | passed | actual NixOS/Home Manager graph |
| Andoria-08 consumer override | passed | actual Home Manager graph |
| promptdeploy selection/rendering | passed | exact matrices and bare launcher rendering pass for Claude, Codex, Droid, and OpenCode |
| Full repository gates | passed | Nix final gates pass on Darwin/ARM64/AMD64; promptdeploy Ruff, mypy, 1,512 tests/100% coverage, package build, and all-system evaluation pass |
| Commit audits and partner cleanup | pending | run after each logical commit |

## Immediate next actions

1. Commit each coherent repository unit.
2. Dispatch independent fess audits, inspect partner observations, and address every verified finding.
3. Recheck upstream-base currency and final repository state.

## Stop-and-escalate counts

- Generic Home Manager exact-one-package evaluation: the initial name-only filter exposed a real duplicate caused by the flake's `default` package aliases. Removing those aliases fixed the graph; both architectures now return exactly one backend-bearing package.
- Repeated implementation or runtime gate failures: none.
- The former local Andoria checkout conflict is not an active blocker: the authoritative remote Home Manager flake was evaluated directly.
