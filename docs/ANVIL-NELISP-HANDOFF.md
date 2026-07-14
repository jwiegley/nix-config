# Anvil Fleet Backend Handoff

Updated: 2026-07-14

## Current position

The current Hera source tree passes the dedicated fast gate, standalone persistent soak, complete flake check, and `./build system`. Promptdeploy's fail-closed source, exact-item activation transaction, and 210/210-second client contract are pushed at `708656c`. The fleet objective remains incomplete until the fixed generation is activated, fresh Codex/Claude/OpenCode processes prove it live, and this generation is rerun natively on the required Linux architectures. The dedicated topology gives each MCP bridge a generation-qualified supervised root, keeps asynchronous evaluation outside that root, rejects recursive same-root transport, and recovers behind the existing pipe without replaying dispatched requests. No Codex or Claude patch is used.

Current Hera package evidence is direct rather than inferential. The bounded fast smoke rejects implicit same-root recursion even when direnv changes `XDG_RUNTIME_DIR`, verifies partial-frame deadlines and bounded cleanup, and reports 89 unified and 76 typed tools across isolated daemons. The separate production-policy soak passed all 25 alternating forced-recovery cycles with async isolation, emacs-direnv, file, Org, Git, and Elisp work. Dispatch was 45.691–50.023 seconds (median 45.893), sibling calls 3.360–8.988 seconds, restart 0.630–1.302 seconds, and readiness 2.777–9.691 seconds. A real 50-second yielding call retained the same root PID, all four SIGTERM acquisition/finalization windows cleaned up, and the final system closure built successfully. These are source/package proofs; the currently deployed MCP generation remains older until the Darwin switch and complete client-process restarts.

The Linux contract is `johnw.anvil.useHeadlessEmacs`: false selects the proven NeLisp v0.5.1/anvil.el v1.1.1 pair; true selects current anvil.el 1.3.0 plus anvil-ide under `emacs30-nox`. The independent Darwin contract is `johnw.anvil.useDedicatedDarwinEmacs`: false uses the current interactive Emacs; true reuses the pinned MacPort Emacs in a separate minimal daemon. The PATH launcher remains `anvil-mcp`. Dedicated modes load the full configured optional set, retain 76 direct typed tools, and mirror them into the 13-tool main registry, yielding one 89-tool main surface without promptdeploy knowing either Boolean.

## 2026-07-13 production findings

- The two deployed MCP registrations (`anvil` and `emacs-eval`) share one root per owning top-level Codex process. Internal agents therefore inherit the same root failure domain instead of receiving independent workers.
- `emacs-eval-async` schedules arbitrary evaluation back into the root with `run-with-timer`; it is asynchronous only from the caller's perspective and can freeze the root event loop.
- Synchronous dispatch and async work share one watchdog lease. Any active lease selects the 600-second deadline, so a synchronous root hang can outlive the bridge's 330-second transport budget.
- A shell tool that invokes Anvil or `emacsclient` against its own root can deadlock deterministically: the root waits with `accept-process-output` restricted to its child while the child waits for that root's server loop. The issue-53 fix correctly avoids servicing unrelated process filters, so recursion must be rejected rather than reintroducing reentrant callbacks.
- Supervisor keys and status do not include the packaged generation. A new launcher under a long-lived client can attach to an older responsive daemon, and already-executed stdio bridges cannot hot-upgrade. Full Codex and Claude OS-process restarts are required after activation.
- Claude has not received the new launcher configuration: live Personal and Positron registrations still reference the old interactive socket. Promptdeploy source is correct in part, but it was never activated and its manifest-only drift check can falsely report a manually stale MCP entry as current.
- In the then-deployed generation, supervisor stdout/stderr went to `/dev/null`, leaving insufficient bounded diagnostics when readiness or a daemon restart failed.
- A direct recursive reproduction held the then-deployed dedicated root at high CPU for more than two minutes before recovery. This failed acceptance test motivated the repair; it was not a theoretical risk.
- A live Codex source/process audit proved that every internal agent thread owns a distinct MCP stdio process even when all bridges have one top-level Codex parent. The deployed generation incorrectly coalesces those transports by the parent PID; the current bridge-PID/start-identity/package-generation key gives each transport its own daemon without any Codex patch. Codex also supplies `_meta.threadId`, but per-transport identity covers initialization and the complete protocol without adding a routing proxy.
- The first integrated request-10 failure sampled an auxiliary shell process stalled before user code in macOS `_dyld_start`. Replacing Bash-to-Python with a direct isolated-Python trampoline removes one cold loader launch and preserves descendant cleanup. A second request-10 failure showed that an artificial six-second host-smoke dispatch deadline still converts ordinary host-wide loader scheduling into a false root hang. The ordinary host transcript now uses the packaged production deadlines; the separate supervisor smoke continues to inject a real non-yielding form and proves same-pipe replacement, sibling isolation, and at-most-once behavior under accelerated deadlines.

## Timeout ordering contract

The cross-client timeout ladder preserves the full 120-second cooperative synchronous evaluation window while ensuring that each outer layer expires later than the complete serial path it supervises. Root heartbeat progress is due every 45 seconds; the hard root dispatch watchdog fires at 135 seconds; and ordinary stdio dispatch is capped at 150 seconds. JSON-RPC metadata parsing has a two-second cap, each bounded emacsclient runner escalates from TERM to KILL after one second, bridge readiness has a 20-second budget, and each parent-guard handshake has a five-second budget. Supervisor daemon shutdown separately uses bounded five-second TERM and post-KILL waits. Ordinary requests and startup's separate 20-second initialize-dispatch path—including the supervisor wait, parse/readiness phases, parent-guard handshakes, and configured kill waits—remain below the common 210-second MCP client envelope. Runtime overrides may shorten but cannot enlarge these maxima. Synchronous `shell-run` and `shell-tee-grep` overrides are capped at 120 seconds and rejected before spawning when larger; longer builds use native execution or the external asynchronous path. External asynchronous evaluation retains its independent 300-second default and does not lengthen the synchronous root watchdog.

The bridge no longer overloads one timeout variable for every phase: `ANVIL_MCP_REQUEST_PARSE_TIMEOUT` bounds metadata parsing, `ANVIL_EMACSCLIENT_PROBE_TIMEOUT` bounds each pure probe, `ANVIL_EMACSCLIENT_READINESS_TIMEOUT` bounds replayable readiness, `ANVIL_EMACSCLIENT_STARTUP_DISPATCH_TIMEOUT` bounds initialize, and `ANVIL_EMACSCLIENT_DISPATCH_TIMEOUT` bounds ordinary non-replayable dispatch. The generated Nix artifacts and a dedicated regression file are checked against one package-level timeout policy; promptdeploy's target-render tests independently bind the client side to the same 210/210-second values.

Home Manager exports `MCP_TIMEOUT=210000` for Claude startup, but only newly started processes that inherit the Home Manager session environment receive it. Existing shells and complete Codex/Claude OS processes must be restarted after activation. GUI-launched Darwin clients may not inherit shell session variables at all, so the rendered per-server client timeout remains authoritative rather than relying on this environment fallback.

## Evidence gathered

- Nix worktree: `/Users/johnw/src/nix`, branch `main`, initial HEAD `c988ea6dc269312af9d4545fc5d0b76f56cd801e`, initially clean.
- promptdeploy worktree: `/Users/johnw/src/promptdeploy`, branch `main`, initial HEAD `a037d18f4e40baaead3dbda4a41e956c097faadb`.
- Current macOS Anvil is fetched and compiled in `overlays/10-emacs.nix`, included by `config/emacs.nix`, loaded in the running Emacs, and served through the live socket.
- The packaged interactive Darwin launcher reached that daemon: `anvil` returned protocol 2025-03-26 and 13 tools; `emacs-eval` returned 65 tools. The user reports that agent traffic can intermittently lock this development Emacs, motivating the dedicated Darwin process.
- The dedicated Darwin check starts its MCP client before one daemon is ready, then proves bounded launcher waiting, two concurrent MacPort Emacs daemons, exactly 89 unified and 76 typed tools, real eval/file/Org/semantic calls, distinct socket/schema/state paths, private nested worker directories, isolated worker process environments, and clean shutdown. In host mode the evaluated launchd agent sets exactly `ANVIL_EMACS_LOCK_CONFLICT_STATUS=75` and `ANVIL_EMACS_USE_SYSTEM_LOG=1`; the latter opts into `/usr/bin/logger`, preserving startup diagnostics in the bounded macOS system log without an append-only private log file.
- An earlier package generation passed the dedicated native checks on Vulcan ARM64 and Andoria-08 AMD64, including the lock-pinned Andoria staging run against nixpkgs revision `5b2c2d84341b2afb5647081c1386a80d7a8d8605`. Those runs are compatibility evidence, not proof of the present supervisor, stdio, timeout, and standalone-soak changes; current-generation native reruns remain pending. Neither earlier run activated or changed host configuration.
- Focused Home Manager evaluation proves both Boolean defaults and true branches: interactive/no-agent versus dedicated/user-domain launchd on Darwin, and NeLisp/no-service versus dedicated/systemd on Linux. The dedicated Darwin module also evaluates against Home Manager release-25.11, where the launchd `domain` option is absent; its evaluated launchd environment contains exactly `ANVIL_EMACS_LOCK_CONFLICT_STATUS=75` and `ANVIL_EMACS_USE_SYSTEM_LOG=1`.
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
- Upstream anvil.el's complete suite passes after async isolation and cleanup hardening: 102 test files, 2,304 tests run, 235 expected skips, and zero failures. The separate async-isolation regression file covers the original non-yielding reproduction, cancellation, framing, callback exits, ownership, environment propagation, and child cleanup.

## Current Nix changes

- `packages/anvil-mcp/default.nix` and `Cargo.lock`: platform-dispatched NeLisp, interactive-Darwin, and dedicated-Emacs launchers; vendored NeLisp lock; trimmed evaluator source closure; pinned Anvil/anvil-ide/PyMuPDF runtime; authenticated private roots, nested worker directories, and sockets; a process-wide private umask; Linux daemon-lifetime locks on both runtime and state identities; stale-temp/worker pruning after both locks; deterministic sockets; native-JIT suppression; fail-fast bootstrap; isolated root and worker state; and worker-pool shutdown.
- `packages/anvil-mcp/no-placeholder-fallback.patch` and `portable-c-char.patch`: fail-closed NeLisp bootstrap and ARM-compatible FFI.
- `packages/anvil-mcp/smoke.nix` and `smoke.py`: exact 42-tool NeLisp behavior gate.
- `packages/anvil-mcp/headless-smoke.nix` and `headless-smoke.py`: bounded fast functional gate covering concurrent two-daemon isolation, hostile root/nested-directory/socket rejection, dual-lock identity and prune-order sentinels, stale temp/worker removal, private-directory attribute scans, worker lifetimes, post-shutdown restart, exact 89/76 manifests, and real eval/file/Org/semantic/direnv calls; it deliberately excludes the long soak.
- `packages/anvil-mcp/persistent-bridge-soak.nix`, `persistent-bridge-soak.py`, and `persistent-bridge-soak-test.py`: standalone 25-cycle check with a 210-second healthy-call envelope, a 1800-second TERM deadline plus 60-second KILL grace, partial latency summary, partial-frame and cleanup-exit regressions, a 50-second yielding-dispatch proof, and production-`main` SIGTERM cleanup across construction and finalization.
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
| Dedicated fast package/init/services | passed current Hera fast gate | per-bridge generation isolation, external async execution, same-root rejection, fail-closed direnv, and final 89/76 transcript; deliberately excludes the long soak |
| Standalone persistent soak | passed current Hera gate | 25/25 forced recoveries; dispatch 45.691–50.023s, sibling 3.360–8.988s, restart 0.630–1.302s, readiness 2.777–9.691s; 50s yielding call retained its root; bounded signal-safe teardown |
| Boolean Home Manager options | passed focused evaluation | both defaults and both true service branches evaluate with the intended backend |
| Shared-home socket isolation | passed runtime smoke | deterministic platform roots, runtime hostname, distinct host sockets and schema/state trees |
| Generic Home Manager outputs | passed | each architecture evaluates to exactly one `anvil-mcp` package with backend `nelisp` |
| Vulcan consumer override | passed | actual NixOS/Home Manager graph |
| VPS consumer override | passed | actual NixOS/Home Manager graph |
| Andoria-08 consumer override | passed | actual Home Manager graph |
| promptdeploy selection/rendering | source complete and pushed; activation pending | fail-closed activation began at `f4bc916`; exact 210/210-second Anvil client rendering landed at `4c9b2c1`; the exact-item activation transaction is pushed at `708656c`; Home Manager activation and fresh live clients remain |
| Full repository gates | passed current Hera source tree | `nix flake check -L --keep-going` and `./build system` passed after the current dedicated fast gate and 25-cycle soak; activation and current-generation Linux-native reruns remain |
| Commit audits and partner cleanup | enforced | promptdeploy feature audit clean; initial and hardening-commit Nix audit findings are addressed; the final Nix follow-up receives the required post-commit audit |

## Release-close procedure

1. Keep repository units atomic and stage only explicit task paths.
2. Require an independent fess audit after each logical commit and address every verified finding.
3. Run a separate reproducible regression file for every anvil.el hang fix, then run the bounded dedicated fast check and standalone 25-cycle persistent-soak attribute separately before any live-client soak.
4. Restart complete Codex and Claude OS processes after activation and run the live concurrent soak; do not treat session resume or daemon PID replacement as proof that an old stdio bridge upgraded.
5. Recheck upstream-base currency and final repository state before handoff.

## Stop-and-escalate counts

- Generic Home Manager exact-one-package evaluation: the initial name-only filter exposed a real duplicate caused by the flake's `default` package aliases. Removing those aliases fixed the graph; both architectures now return exactly one backend-bearing package.
- Resolved gate failures: the original 20-second soak-only watchdog falsely killed cold Git under parallel load; the SIGTERM harness initially asserted child-side exit logging after SIGKILL; the timeout-ordering fake omitted the socket-race text required for retry; and the async compatibility probe used an artificial five-second cold-start budget. Production policy alignment, parent-side cleanup evidence, a deterministic transient probe, and a bounded 30-second string-timeout probe resolved them.
- Integrated `host-a` request-10 ambiguous dispatch: two occurrences. The first led to the direct-Python trampoline and removed one cold dyld launch; the second isolated the trigger to the host smoke's artificial six-second dispatch deadline. The final dedicated fast gate, production-policy soak, flake check, and complete system build now pass with the independent accelerated recovery test retained.
- The former local Andoria checkout conflict is not an active blocker: the authoritative remote Home Manager flake was evaluated directly.
