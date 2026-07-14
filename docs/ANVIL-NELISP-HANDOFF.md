# Anvil Fleet Backend Handoff

Updated: 2026-07-13

## Current position

The Hera package-level reliability repair is now green, but the fleet objective is not complete until the pinned promptdeploy activation and restarted live clients are verified on every required host. The dedicated topology gives each MCP bridge a generation-qualified supervised root, keeps asynchronous evaluation outside that root, rejects recursive same-root transport, and recovers behind the existing pipe without replaying dispatched requests. No Codex or Claude patch is used.

Current Hera evidence is direct rather than inferential: the standalone guard rejects an implicit call even when direnv changes `XDG_RUNTIME_DIR`; the integrated check completes 25 persistent forced-recovery cycles with concurrent file, Org, Git, Elisp, async, direnv, cleanup, and latency assertions; the two formerly cumulative post-soak recursion probes now run as independent calls under the 210-second tool policy; the final transcript reports 89 unified and 76 typed tools across two isolated daemons; and `./build system` completes successfully. Remaining work is the pinned fail-closed promptdeploy Home Manager transaction, consumer pin/switch propagation, native Linux reruns of this generation, and concurrent live Codex/Claude soaks after complete process restarts.

The Linux contract is `johnw.anvil.useHeadlessEmacs`: false selects the proven NeLisp v0.5.1/anvil.el v1.1.1 pair; true selects current anvil.el 1.3.0 plus anvil-ide under `emacs30-nox`. The independent Darwin contract is `johnw.anvil.useDedicatedDarwinEmacs`: false uses the current interactive Emacs; true reuses the pinned MacPort Emacs in a separate minimal daemon. The PATH launcher remains `anvil-mcp`. Dedicated modes load the full configured optional set, retain 76 direct typed tools, and mirror them into the 13-tool main registry, yielding one 89-tool main surface without promptdeploy knowing either Boolean.

## 2026-07-13 production findings

- The two deployed MCP registrations (`anvil` and `emacs-eval`) share one root per owning top-level Codex process. Internal agents therefore inherit the same root failure domain instead of receiving independent workers.
- `emacs-eval-async` schedules arbitrary evaluation back into the root with `run-with-timer`; it is asynchronous only from the caller's perspective and can freeze the root event loop.
- Synchronous dispatch and async work share one watchdog lease. Any active lease selects the 600-second deadline, so a synchronous root hang can outlive the bridge's 330-second transport budget.
- A shell tool that invokes Anvil or `emacsclient` against its own root can deadlock deterministically: the root waits with `accept-process-output` restricted to its child while the child waits for that root's server loop. The issue-53 fix correctly avoids servicing unrelated process filters, so recursion must be rejected rather than reintroducing reentrant callbacks.
- Supervisor keys and status do not include the packaged generation. A new launcher under a long-lived client can attach to an older responsive daemon, and already-executed stdio bridges cannot hot-upgrade. Full Codex and Claude OS-process restarts are required after activation.
- Claude has not received the new launcher configuration: live Personal and Positron registrations still reference the old interactive socket. Promptdeploy source is correct in part, but it was never activated and its manifest-only drift check can falsely report a manually stale MCP entry as current.
- Supervisor stdout/stderr currently go to `/dev/null`, leaving insufficient bounded diagnostics when readiness or a daemon restart fails.
- A direct recursive reproduction held a dedicated root at high CPU for more than two minutes before recovery. This is a current failed acceptance test, not a theoretical risk.
- A live Codex source/process audit proved that every internal agent thread owns a distinct MCP stdio process even when all bridges have one top-level Codex parent. The deployed generation incorrectly coalesces those transports by the parent PID; the current bridge-PID/start-identity/package-generation key gives each transport its own daemon without any Codex patch. Codex also supplies `_meta.threadId`, but per-transport identity covers initialization and the complete protocol without adding a routing proxy.
- The first integrated request-10 failure sampled an auxiliary shell process stalled before user code in macOS `_dyld_start`. Replacing Bash-to-Python with a direct isolated-Python trampoline removes one cold loader launch and preserves descendant cleanup. A second request-10 failure showed that an artificial six-second host-smoke dispatch deadline still converts ordinary host-wide loader scheduling into a false root hang. The ordinary host transcript now uses the packaged production deadlines; the separate supervisor smoke continues to inject a real non-yielding form and proves same-pipe replacement, sibling isolation, and at-most-once behavior under accelerated deadlines.

## Timeout ordering contract

The cross-client timeout ladder preserves the full 120-second cooperative synchronous evaluation window while ensuring that each outer layer expires later than the complete serial path it supervises. Root heartbeat progress is due every 45 seconds; the hard root dispatch watchdog fires at 135 seconds; and ordinary stdio dispatch is capped at 150 seconds. JSON-RPC metadata parsing has a two-second cap, every external timeout escalates from TERM to KILL after one second, and bridge readiness has a 20-second budget. Parsing, readiness, kill escalation, and ordinary dispatch remain below the 210-second MCP client tool deadline. Startup uses a separate 20-second initialize-dispatch cap, so the 120-second supervisor wait plus parsing, readiness, escalation, and initialize remain below the 180-second client startup deadline. Runtime overrides may shorten but cannot enlarge these maxima. Synchronous `shell-run` and `shell-tee-grep` overrides are capped at 120 seconds and rejected before spawning when larger; longer builds use native execution or the external asynchronous path. External asynchronous evaluation retains its independent 300-second default and does not lengthen the synchronous root watchdog.

The bridge no longer overloads one timeout variable for every phase: `ANVIL_MCP_REQUEST_PARSE_TIMEOUT` bounds metadata parsing, `ANVIL_EMACSCLIENT_PROBE_TIMEOUT` bounds each pure probe, `ANVIL_EMACSCLIENT_READINESS_TIMEOUT` bounds replayable readiness, `ANVIL_EMACSCLIENT_STARTUP_DISPATCH_TIMEOUT` bounds initialize, and `ANVIL_EMACSCLIENT_DISPATCH_TIMEOUT` bounds ordinary non-replayable dispatch. The generated Nix artifacts and a dedicated regression file are checked against one package-level timeout policy; promptdeploy's target-render tests independently bind the client side to the same 180/210-second values.

Home Manager exports `MCP_TIMEOUT=180000` for Claude startup, but only newly started processes that inherit the Home Manager session environment receive it. Existing shells and complete Codex/Claude OS processes must be restarted after activation. GUI-launched Darwin clients may not inherit shell session variables at all, so the rendered per-server client timeout remains authoritative rather than relying on this environment fallback.

## Evidence gathered

- Nix worktree: `/Users/johnw/src/nix`, branch `main`, initial HEAD `c988ea6dc269312af9d4545fc5d0b76f56cd801e`, initially clean.
- promptdeploy worktree: `/Users/johnw/src/promptdeploy`, branch `main`, initial HEAD `a037d18f4e40baaead3dbda4a41e956c097faadb`.
- Current macOS Anvil is fetched and compiled in `overlays/10-emacs.nix`, included by `config/emacs.nix`, loaded in the running Emacs, and served through the live socket.
- The packaged interactive Darwin launcher reached that daemon: `anvil` returned protocol 2025-03-26 and 13 tools; `emacs-eval` returned 65 tools. The user reports that agent traffic can intermittently lock this development Emacs, motivating the dedicated Darwin process.
- The dedicated Darwin check starts its MCP client before one daemon is ready, then proves bounded launcher waiting, two concurrent MacPort Emacs daemons, exactly 89 unified and 76 typed tools, real eval/file/Org/semantic calls, distinct socket/schema/state paths, private nested worker directories, isolated worker process environments, and clean shutdown. The launchd service opts into `/usr/bin/logger`, preserving startup diagnostics in the bounded macOS system log without an append-only private log file.
- The current hardened dedicated check passes natively on Vulcan ARM64 and Andoria-08 AMD64. The final Andoria rerun evaluated the current package and checks directly against lock-pinned nixpkgs revision `5b2c2d84341b2afb5647081c1386a80d7a8d8605` from a unique host-local staging directory that was removed afterward. Neither run activated or changed host configuration.
- Focused Home Manager evaluation proves both Boolean defaults and true branches: interactive/no-agent versus dedicated/user-domain launchd on Darwin, and NeLisp/no-service versus dedicated/systemd on Linux. The dedicated Darwin module also evaluates against Home Manager release-25.11, where the launchd `domain` option is absent; its evaluated launchd environment contains exactly `ANVIL_EMACS_USE_SYSTEM_LOG=1`.
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
- Upstream anvil.el's complete suite passes after async isolation and cleanup hardening: 102 test files, 2,304 tests run, 235 expected skips, and zero failures. The separate async-isolation regression file covers the original non-yielding reproduction, cancellation, framing, callback exits, ownership, environment propagation, and child cleanup.

## Current Nix changes

- `packages/anvil-mcp/default.nix` and `Cargo.lock`: platform-dispatched NeLisp, interactive-Darwin, and dedicated-Emacs launchers; vendored NeLisp lock; trimmed evaluator source closure; pinned Anvil/anvil-ide/PyMuPDF runtime; authenticated private roots, nested worker directories, and sockets; a process-wide private umask; Linux daemon-lifetime locks on both runtime and state identities; stale-temp/worker pruning after both locks; deterministic sockets; native-JIT suppression; fail-fast bootstrap; isolated root and worker state; and worker-pool shutdown.
- `packages/anvil-mcp/no-placeholder-fallback.patch` and `portable-c-char.patch`: fail-closed NeLisp bootstrap and ARM-compatible FFI.
- `packages/anvil-mcp/smoke.nix` and `smoke.py`: exact 42-tool NeLisp behavior gate.
- `packages/anvil-mcp/headless-smoke.nix` and `headless-smoke.py`: concurrent two-daemon isolation, hostile root/nested-directory/socket rejection, dual-lock identity and prune-order sentinels, stale temp/worker removal, private-directory attribute scans, all eight worker lifetimes, post-shutdown restart, exact 89/76 manifests, and real eval/file/Org/semantic calls.
- `config/anvil.nix`: both Boolean options, selected package installation, deferred systemd service, and a user-domain launchd agent compatible with current and release-25.11 Home Manager option schemas that routes diagnostics to the macOS system logger.
- `config/johnw.nix` and `flake.nix`: module import plus focused packages and platform checks, with package/check evaluation decoupled from the complete Hera Darwin configuration while unrelated development shells continue to use stock nixpkgs.
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
| Darwin live bridge | passed | 13 main tools and 65 typed tools through packaged launcher |
| Dedicated package/init/services | passed Hera package gate | per-bridge generation isolation, external async execution, same-root rejection, 25 recovery cycles, post-soak 89/76 transcript, and full Darwin system build passed |
| Boolean Home Manager options | passed focused evaluation | both defaults and both true service branches evaluate with the intended backend |
| Shared-home socket isolation | passed runtime smoke | deterministic platform roots, runtime hostname, distinct host sockets and schema/state trees |
| Generic Home Manager outputs | passed | each architecture evaluates to exactly one `anvil-mcp` package with backend `nelisp` |
| Vulcan consumer override | passed | actual NixOS/Home Manager graph |
| VPS consumer override | passed | actual NixOS/Home Manager graph |
| Andoria-08 consumer override | passed | actual Home Manager graph |
| promptdeploy selection/rendering | core committed; activation pending | exact semantic deploy/verify and hardened source handling are pushed at promptdeploy `d77b7d9`; pinned fail-closed Home Manager activation and live client refresh remain |
| Full repository gates | passed on Hera | `anvil-mcp-dedicated` passed all unit/integration gates and 25 cycles; `./build system` passed; current-generation Linux-native reruns remain |
| Commit audits and partner cleanup | enforced | promptdeploy feature audit clean; initial and hardening-commit Nix audit findings are addressed; the final Nix follow-up receives the required post-commit audit |

## Release-close procedure

1. Keep repository units atomic and stage only explicit task paths.
2. Require an independent fess audit after each logical commit and address every verified finding.
3. Run a separate reproducible regression file for every anvil.el hang fix, then exercise the built Nix launcher for at least 25 forced recovery cycles under concurrent clients.
4. Restart complete Codex and Claude OS processes after activation and run the live concurrent soak; do not treat session resume or daemon PID replacement as proof that an old stdio bridge upgraded.
5. Recheck upstream-base currency and final repository state before handoff.

## Stop-and-escalate counts

- Generic Home Manager exact-one-package evaluation: the initial name-only filter exposed a real duplicate caused by the flake's `default` package aliases. Removing those aliases fixed the graph; both architectures now return exactly one backend-bearing package.
- Repeated implementation or runtime gate failures: none.
- Integrated `host-a` request-10 ambiguous dispatch: two occurrences. The first led to the direct-Python trampoline and removed one cold dyld launch; the second isolated the remaining trigger to the host smoke's artificial six-second dispatch deadline. The next full gate runs the same ordinary transcript under the packaged production timeout policy, while the independent accelerated supervisor recovery test remains unchanged.
- The former local Andoria checkout conflict is not an active blocker: the authoritative remote Home Manager flake was evaluated directly.
